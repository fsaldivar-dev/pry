import Foundation
import PryLib
import NIO
#if canImport(Glibc)
import Glibc
#else
import Darwin
#endif

let args = Array(CommandLine.arguments.dropFirst())

func printUsage() {
    print("""
    🐱 Pry — Proxy CLI for iOS devs

    Usage:
      pry start [--port PORT]    Start proxy (default: 8080)
      pry stop                   Stop running proxy
      pry add DOMAIN             Add domain to HTTPS interception watchlist
      pry add domains.txt        Add domains from file
      pry remove DOMAIN          Remove domain from watchlist
      pry list                   Show intercepted domains
      pry mock PATH RESPONSE     Mock an endpoint with JSON
      pry mock PATH file.json    Mock an endpoint with a JSON file
      pry mocks                  List active mocks
      pry mocks clear            Clear all mocks
      pry log                    Show captured requests
      pry log clear              Clear log
      pry watch PATTERN          Filter traffic by domain pattern
      pry watch clear            Clear filter
      pry trust                  Install CA cert in iOS Simulator
      pry ca                     Show CA certificate info
      pry map REGEX FILE         Map URL regex to local file
      pry maps                   List active maps
      pry maps clear             Clear all maps
      pry header add NAME VALUE  Add header to all requests
      pry header remove NAME     Remove header from all requests
      pry headers                List active header rules
      pry headers clear          Clear all header rules
      pry export har FILE        Export traffic as HAR 1.2
      pry break PATTERN          Set breakpoint on URL pattern
      pry breaks                 List active breakpoints
      pry breaks clear           Clear all breakpoints
      pry init [DIR]             Scan project for API domains → .prywatch
      pry nocache on|off         Toggle no-cache headers
      pry block DOMAIN           Block domain (responds 403)
      pry blocks                 List blocked domains
      pry blocks clear           Clear block list
      pry redirect SRC DST       Redirect host to another host
      pry redirects              List active redirects
      pry redirects clear        Clear all redirects
      pry dns DOMAIN IP          Override DNS resolution
      pry dns list               List DNS overrides
      pry dns clear              Clear DNS overrides
      pry send METHOD URL        Send request through proxy
      pry save FILE              Save captured session
      pry load FILE              Load saved session
      pry diff ID1 ID2           Compare two captured requests
      pry rules load FILE        Load .pryrules scripting file
      pry rules                  List active rules
      pry rules clear            Clear all rules

    Scenarios:
      pry scenario use NAME       Activate a scenario
      pry scenario off            Deactivate current scenario
      pry scenario list           List all scenarios
      pry scenario create NAME    Create empty scenario
      pry scenario delete NAME    Delete scenario
      pry scenario show NAME      Show scenario JSON
      pry scenario capture NAME   Capture current config as scenario

    Status Override:
      pry override PATTERN CODE   Override response status code
      pry overrides [clear]       List/clear status overrides

    Mock Project:
      pry project init            Initialize .pry/mocking/ directory
      pry project list            List project mocks
      pry project apply           Apply project mocks to proxy
      pry project clear           Clear all project mocks

    Recorder:
      pry record start NAME       Start recording traffic
      pry record stop             Stop and save recording
      pry record list             List recordings
      pry record show NAME        Show recording details
      pry record delete NAME      Delete recording
      pry record to-mocks NAME    Convert recording to mocks

    Sharing:
      pry export scenario NAME    Export scenario to .pryscenario
      pry import scenario FILE    Import scenario from file

    Devices:
      pry device                  Start device setup server

    Examples:
      pry start
      pry add api.myapp.com
      pry mock /api/login '{"token":"abc123"}'
      pry map '/api/v1/.*' mock-data.json
      pry header add Authorization "Bearer token123"
      pry export har traffic.har
    """)
}

guard let command = args.first else {
    printUsage()
    exit(0)
}

// Watchdog subprocess mode: `pry --watchdog <parent_pid>`
// Bloquea en un loop observando al padre (PryApp). Si el padre muere de golpe
// (SIGKILL, force-quit, crash), el watchdog restaura el system proxy para que
// el Mac no pierda la red. Si hay un sentinel file, sale silenciosamente
// (shutdown limpio en curso). Solo Foundation + Darwin, sin NIO.
if command == "--watchdog" {
    guard args.count >= 2, let parentPID = pid_t(args[1]) else {
        fputs("Usage: pry --watchdog <parent_pid>\n", stderr)
        exit(2)
    }
    fputs("[pry-watchdog] starting, watching pid \(parentPID)\n", stderr)
    // Ignorar SIGPIPE por si stderr se cierra cuando el padre muere.
    signal(SIGPIPE, SIG_IGN)
    let result = Watchdog.run(parentPID: parentPID)
    fputs("[pry-watchdog] exiting: \(result)\n", stderr)
    exit(0)
}

// Check for orphaned proxy config on every CLI invocation
ProxyGuard.cleanupIfNeeded()

switch command {
case "start":
    var port = Config.defaultPort
    if let portIdx = args.firstIndex(of: "--port"), portIdx + 1 < args.count {
        guard let p = Int(args[portIdx + 1]), p > 0, p < 65536 else {
            print("Error: \(ProxyError.invalidPort(args[portIdx + 1]))")
            exit(1)
        }
        port = p
    }

    // Check if already running — try to clean up zombie processes
    if let pidStr = try? String(contentsOfFile: Config.pidFile, encoding: .utf8),
       let pid = Int32(pidStr.trimmingCharacters(in: .whitespacesAndNewlines)) {
        if kill(pid, 0) == 0 {
            print("Error: \(ProxyError.alreadyRunning) (PID \(pid))")
            print("   Run 'pry stop' first")
            exit(1)
        } else {
            // PID file exists but process is dead — clean up
            try? FileManager.default.removeItem(atPath: Config.pidFile)
        }
    }

    // Check if port is occupied by orphan process
    let checkPort = Process()
    checkPort.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
    checkPort.arguments = ["-i", ":\(port)", "-t"]
    let checkPipe = Pipe()
    checkPort.standardOutput = checkPipe
    checkPort.standardError = FileHandle.nullDevice
    if let _ = try? checkPort.run() {
        checkPort.waitUntilExit()
        let output = String(data: checkPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let pids = output.split(separator: "\n").compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
        if !pids.isEmpty {
            print("⚠️  Port \(port) in use by PID \(pids[0]). Cleaning up...")
            for pid in pids { kill(pid, SIGTERM) }
            usleep(500_000) // Wait 0.5s for process to die
        }
    }

    let server = ProxyServer(port: port)
    ProxyGuard.installAtexitHandler()
    let headless = args.contains("--headless")

    if headless {
        // Headless mode — direct print, blocking
        signal(SIGINT) { _ in
            print("\n🐱 Pry stopped")
            if let state = ProxyState.load() {
                SystemProxy.disable(service: state.networkService)
            }
            ProxyState.clear()
            try? FileManager.default.removeItem(atPath: Config.pidFile)
            exit(0)
        }
        signal(SIGTERM) { _ in
            if let state = ProxyState.load() {
                SystemProxy.disable(service: state.networkService)
            }
            ProxyState.clear()
            try? FileManager.default.removeItem(atPath: Config.pidFile)
            exit(0)
        }
        do {
            try server.startAndWait()
        } catch {
            print("Error: \(error)")
            exit(1)
        }
    } else {
        // TUI mode
        do {
            try server.start()
        } catch {
            print("Error: \(error)")
            exit(1)
        }

        let tui = TUI(port: port)
        tui.onCommand = { input in
            // Parse and execute commands from TUI command line
            let tuiArgs = input.split(separator: " ").map(String.init)
            guard let cmd = tuiArgs.first else { return }
            switch cmd {
            case "mock":
                if tuiArgs.count >= 3 {
                    let path = tuiArgs[1]
                    let json = tuiArgs.dropFirst(2).joined(separator: " ")
                    if path.hasPrefix("/") {
                        Config.saveMock(path: path, response: json)
                        OutputBroker.shared.log(mock("🐱 Mock registered: \(path)"), type: .mock)
                    } else {
                        // Domain mock
                        Watchlist.add(path)
                        let parts = path.split(separator: "/", maxSplits: 1)
                        let domain = String(parts[0])
                        let mockPath = parts.count > 1 ? "/\(parts[1])" : "/"
                        Config.saveMock(path: "\(domain):\(mockPath)", response: json)
                        OutputBroker.shared.log(mock("🐱 Mock registered: \(domain)\(mockPath)"), type: .mock)
                    }
                }
            case "add":
                if tuiArgs.count >= 2 {
                    Watchlist.add(tuiArgs[1])
                    OutputBroker.shared.log(info("🐱 Added: \(tuiArgs[1])"), type: .info)
                }
            case "remove":
                if tuiArgs.count >= 2 {
                    Watchlist.remove(tuiArgs[1])
                    OutputBroker.shared.log(info("🐱 Removed: \(tuiArgs[1])"), type: .info)
                }
            case "list":
                let domains = Watchlist.load()
                if domains.isEmpty {
                    OutputBroker.shared.log("No domains in watchlist", type: .info)
                } else {
                    OutputBroker.shared.log("Domains: \(domains.sorted().joined(separator: ", "))", type: .info)
                }
            case "mocks":
                let mocks = Config.loadMocks()
                if mocks.isEmpty {
                    OutputBroker.shared.log("No mocks registered", type: .info)
                } else {
                    for (path, resp) in mocks {
                        OutputBroker.shared.log("  \(path) -> \(resp.prefix(60))", type: .info)
                    }
                }
            case "map":
                if tuiArgs.count >= 3 {
                    MapLocal.save(regex: tuiArgs[1], filePath: tuiArgs[2])
                    OutputBroker.shared.log(info("🐱 Map: \(tuiArgs[1]) → \(tuiArgs[2])"), type: .info)
                }
            case "maps":
                let maps = MapLocal.loadAll()
                if maps.isEmpty {
                    OutputBroker.shared.log("No maps registered", type: .info)
                } else {
                    for m in maps {
                        OutputBroker.shared.log("  \(m.regex) → \(m.filePath)", type: .info)
                    }
                }
            case "header":
                if tuiArgs.count >= 4 && tuiArgs[1] == "add" {
                    let value = tuiArgs.dropFirst(3).joined(separator: " ")
                    HeaderRewrite.addRule(name: tuiArgs[2], value: value)
                    OutputBroker.shared.log(info("🐱 Header: +\(tuiArgs[2])"), type: .info)
                } else if tuiArgs.count >= 3 && tuiArgs[1] == "remove" {
                    HeaderRewrite.removeRule(name: tuiArgs[2])
                    OutputBroker.shared.log(info("🐱 Header: -\(tuiArgs[2])"), type: .info)
                }
            case "headers":
                let rules = HeaderRewrite.loadAll()
                if rules.isEmpty {
                    OutputBroker.shared.log("No header rules", type: .info)
                } else {
                    for r in rules {
                        let prefix = r.action == .add ? "+" : "-"
                        OutputBroker.shared.log("  \(prefix) \(r.name): \(r.value ?? "")", type: .info)
                    }
                }
            case "export":
                if tuiArgs.count >= 3 && tuiArgs[1] == "har" {
                    do {
                        try HARExporter.exportToFile(from: RequestStore.shared, path: tuiArgs[2])
                        OutputBroker.shared.log(info("🐱 Exported HAR to \(tuiArgs[2])"), type: .info)
                    } catch {
                        OutputBroker.shared.log(errText("Export failed: \(error)"), type: .error)
                    }
                }
            case "scenario":
                if tuiArgs.count >= 3 && tuiArgs[1] == "use" {
                    if ScenarioManager.activate(name: tuiArgs[2]) {
                        OutputBroker.shared.log(info("🐱 Scenario activated: \(tuiArgs[2])"), type: .info)
                    } else {
                        OutputBroker.shared.log(errText("Scenario '\(tuiArgs[2])' not found"), type: .error)
                    }
                } else if tuiArgs.count >= 2 && tuiArgs[1] == "off" {
                    ScenarioManager.deactivate()
                    OutputBroker.shared.log(info("🐱 Scenario deactivated"), type: .info)
                } else if tuiArgs.count >= 2 && tuiArgs[1] == "list" {
                    let scenarios = ScenarioManager.list()
                    let active = ScenarioManager.active()
                    if scenarios.isEmpty {
                        OutputBroker.shared.log("No scenarios", type: .info)
                    } else {
                        for name in scenarios {
                            let marker = (name == active) ? " (active)" : ""
                            OutputBroker.shared.log("  \(name)\(marker)", type: .info)
                        }
                    }
                } else {
                    OutputBroker.shared.log(errText("Usage: scenario <use NAME|off|list>"), type: .error)
                }
            case "override":
                if tuiArgs.count >= 3, let status = UInt(tuiArgs[2]) {
                    StatusOverrideStore.save(pattern: tuiArgs[1], status: status)
                    OutputBroker.shared.log(info("🐱 Override: \(tuiArgs[1]) → \(status)"), type: .info)
                } else {
                    OutputBroker.shared.log(errText("Usage: override PATTERN STATUS_CODE"), type: .error)
                }
            case "record":
                if tuiArgs.count >= 3 && tuiArgs[1] == "start" {
                    Recorder.shared.start(name: tuiArgs[2])
                    OutputBroker.shared.log(info("🐱 Recording started: \(tuiArgs[2])"), type: .info)
                } else if tuiArgs.count >= 2 && tuiArgs[1] == "stop" {
                    if let recording = Recorder.shared.stop() {
                        OutputBroker.shared.log(info("🐱 Recording stopped: \(recording.name) (\(recording.steps.count) steps)"), type: .info)
                    } else {
                        OutputBroker.shared.log("No active recording", type: .info)
                    }
                } else {
                    OutputBroker.shared.log(errText("Usage: record <start NAME|stop>"), type: .error)
                }
            default:
                OutputBroker.shared.log(errText("Unknown command: \(cmd)"), type: .error)
            }
        }
        tui.start()

        // TUI exited — cleanup
        if let state = ProxyState.load(),
           state.pid == ProcessInfo.processInfo.processIdentifier {
            SystemProxy.disable(service: state.networkService)
            ProxyState.clear()
        }
        server.shutdown()
    }

case "stop":
    var stopped = false

    // Try PID file first
    if let pidStr = try? String(contentsOfFile: Config.pidFile, encoding: .utf8),
       let pid = Int32(pidStr.trimmingCharacters(in: .whitespacesAndNewlines)),
       kill(pid, 0) == 0 {
        kill(pid, SIGTERM)
        try? FileManager.default.removeItem(atPath: Config.pidFile)
        print("🐱 Pry stopped (PID \(pid))")
        stopped = true
    }

    // Fallback: find process by port using lsof
    if !stopped {
        let port = Config.port()
        let lsof = Process()
        lsof.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        lsof.arguments = ["-i", ":\(port)", "-t"]
        let pipe = Pipe()
        lsof.standardOutput = pipe
        lsof.standardError = FileHandle.nullDevice
        do {
            try lsof.run()
            lsof.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let pids = output.split(separator: "\n").compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
            for pid in pids {
                kill(pid, SIGTERM)
                print("🐱 Pry stopped (PID \(pid) on port \(port))")
                stopped = true
            }
        } catch {
            // lsof failed
        }
        try? FileManager.default.removeItem(atPath: Config.pidFile)
    }

    if !stopped {
        print("Error: \(ProxyError.notRunning)")
        exit(1)
    }

case "add":
    guard args.count >= 2 else {
        print("Usage: pry add api.myapp.com")
        print("       pry add domains.txt")
        exit(1)
    }
    let arg = args[1]
    if FileManager.default.fileExists(atPath: arg) {
        do {
            try Watchlist.addFromFile(arg)
            let domains = Watchlist.load()
            print("🐱 Domains loaded from \(arg) (\(domains.count) total)")
        } catch {
            print("Error: \(error)")
            exit(1)
        }
    } else {
        Watchlist.add(arg)
        print("🐱 Added to watchlist: \(arg)")
    }

case "remove":
    guard args.count >= 2 else {
        print("Usage: pry remove api.myapp.com")
        exit(1)
    }
    Watchlist.remove(args[1])
    print("🐱 Removed from watchlist: \(args[1])")

case "list":
    let domains = Watchlist.load()
    if domains.isEmpty {
        print("No domains in watchlist")
        print("Usage: pry add api.myapp.com")
    } else {
        print("Intercepted domains:")
        for domain in domains.sorted() {
            print("  \(domain)")
        }
    }

case "trust":
    let caPath = CertificateAuthority.caCertPath
    guard FileManager.default.fileExists(atPath: caPath) else {
        print("No CA certificate found. Run 'pry start' first to generate one.")
        exit(1)
    }

    // Install in macOS system keychain
    print("🐱 Installing CA certificate in macOS...")
    let macProcess = Process()
    macProcess.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    macProcess.arguments = ["add-trusted-cert", "-d", "-r", "trustRoot", "-k", "/Library/Keychains/System.keychain", caPath]
    do {
        try macProcess.run()
        macProcess.waitUntilExit()
        if macProcess.terminationStatus == 0 {
            print("   macOS: CA installed and trusted")
        } else {
            // Try user keychain if system keychain fails (no sudo)
            let userProcess = Process()
            userProcess.executableURL = URL(fileURLWithPath: "/usr/bin/security")
            userProcess.arguments = ["add-trusted-cert", "-r", "trustRoot", "-k", NSHomeDirectory() + "/Library/Keychains/login.keychain-db", caPath]
            try userProcess.run()
            userProcess.waitUntilExit()
            if userProcess.terminationStatus == 0 {
                print("   macOS: CA installed in user keychain")
            } else {
                print("   macOS: Failed. You may need to run with sudo or install manually:")
                print("   security add-trusted-cert -r trustRoot -k ~/Library/Keychains/login.keychain-db \(caPath)")
            }
        }
    } catch {
        print("   macOS: Error — \(error)")
    }

    // Install in iOS Simulator
    print("🐱 Installing CA certificate in iOS Simulator...")
    let simProcess = Process()
    simProcess.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    simProcess.arguments = ["simctl", "keychain", "booted", "add-root-cert", caPath]
    do {
        try simProcess.run()
        simProcess.waitUntilExit()
        if simProcess.terminationStatus == 0 {
            print("   Simulator: CA installed")
            print("")
            print("   Next step: On the Simulator, go to")
            print("   Settings > General > About > Certificate Trust Settings")
            print("   and enable trust for 'Pry CA'")
        } else {
            print("   Simulator: Skipped (no simulator booted)")
        }
    } catch {
        print("   Simulator: Error — \(error)")
    }

case "ca":
    let caPath = CertificateAuthority.caCertPath
    if FileManager.default.fileExists(atPath: caPath) {
        print("🐱 CA Certificate")
        print("   Path: \(caPath)")
        print("   Key:  \(CertificateAuthority.caKeyPath)")
        if let content = try? String(contentsOfFile: caPath, encoding: .utf8) {
            let lines = content.components(separatedBy: "\n").count
            print("   Format: PEM (\(lines) lines)")
        }
    } else {
        print("No CA certificate found. Run 'pry start' first to generate one.")
    }

case "mock":
    guard args.count >= 3 else {
        print("Usage: pry mock /path '{\"key\":\"value\"}'")
        print("       pry mock /path response.json")
        print("       pry mock domain.com '{\"key\":\"value\"}'")
        print("       pry mock https://domain.com/path '{\"key\":\"value\"}'")
        exit(1)
    }
    let rawTarget = args[1]
    let responseArg = args[2]

    // Parse target: could be /path, domain.com, domain.com/path, or https://domain.com/path
    var mockPath: String
    var mockDomain: String?

    if rawTarget.hasPrefix("/") {
        // Simple path: /api/login
        mockPath = rawTarget
    } else if rawTarget.hasPrefix("http://") || rawTarget.hasPrefix("https://") {
        // Full URL: https://domain.com/path
        if let components = URLComponents(string: rawTarget) {
            mockDomain = components.host
            mockPath = components.path.isEmpty ? "/" : components.path
        } else {
            mockPath = rawTarget
        }
    } else {
        // Domain or domain/path: domain.com or domain.com/path
        let parts = rawTarget.split(separator: "/", maxSplits: 1)
        mockDomain = String(parts[0])
        mockPath = parts.count > 1 ? "/\(parts[1])" : "/"
    }

    // Auto-add domain to watchlist for HTTPS interception
    if let domain = mockDomain {
        Watchlist.add(domain)
        print("🐱 Added to watchlist: \(domain)")
    }

    var json: String
    if FileManager.default.fileExists(atPath: responseArg) {
        guard let content = try? String(contentsOfFile: responseArg, encoding: .utf8) else {
            print("Error: \(ProxyError.mockFileNotFound(responseArg))")
            exit(1)
        }
        json = content.trimmingCharacters(in: .whitespacesAndNewlines)
    } else {
        json = responseArg
    }

    guard (try? JSONSerialization.jsonObject(with: json.data(using: .utf8)!)) != nil else {
        print("Error: \(ProxyError.invalidJSON(json))")
        exit(1)
    }

    // Store mock with domain context if available
    let mockKey = mockDomain != nil ? "\(mockDomain!):\(mockPath)" : mockPath
    Config.saveMock(path: mockKey, response: json)
    if let domain = mockDomain {
        print("🐱 Mock registered: https://\(domain)\(mockPath)")
    } else {
        print("🐱 Mock registered: \(mockPath)")
    }

case "mocks":
    if args.count >= 2 && args[1] == "clear" {
        Config.clearMocks()
        print("🐱 All mocks cleared")
    } else {
        let mocks = Config.loadMocks()
        if mocks.isEmpty {
            print("No mocks registered")
        } else {
            print("Active mocks:")
            for (path, response) in mocks {
                let preview = response.prefix(60)
                print("  \(path) -> \(preview)\(response.count > 60 ? "..." : "")")
            }
        }
    }

case "log":
    if args.count >= 2 && args[1] == "clear" {
        Config.clearLog()
        print("🐱 Log cleared")
    } else {
        let entries = Config.readLog()
        if entries.isEmpty {
            print("No requests captured yet")
        } else {
            for entry in entries {
                print(entry)
            }
        }
    }

case "watch":
    if args.count < 2 {
        if let current = Config.get("filter") {
            print("Current filter: \(current)")
        } else {
            print("No filter set")
            print("Usage: pry watch api.myapp.com")
        }
    } else if args[1] == "clear" {
        var config = Config.readAll()
        config.removeValue(forKey: "filter")
        let content = config.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
        try? content.write(toFile: Config.configFile, atomically: true, encoding: .utf8)
        print("🐱 Filter cleared")
    } else {
        Config.set("filter", value: args[1])
        print("🐱 Watching: \(args[1])")
        print("   Restart proxy for changes to take effect")
    }

case "map":
    if args.count >= 3 {
        let regex = args[1]
        let filePath = args[2]
        guard FileManager.default.fileExists(atPath: filePath) else {
            print("Error: File not found: \(filePath)")
            exit(1)
        }
        MapLocal.save(regex: regex, filePath: filePath)
        print("🐱 Map registered: \(regex) → \(filePath)")
    } else {
        print("Usage: pry map '/api/v1/.*' response.json")
        exit(1)
    }

case "maps":
    if args.count >= 2 && args[1] == "clear" {
        MapLocal.clear()
        print("🐱 All maps cleared")
    } else {
        let maps = MapLocal.loadAll()
        if maps.isEmpty {
            print("No maps registered")
        } else {
            print("Active maps:")
            for m in maps {
                print("  \(m.regex) → \(m.filePath)")
            }
        }
    }

case "header":
    guard args.count >= 3 else {
        print("Usage: pry header add NAME VALUE")
        print("       pry header remove NAME")
        exit(1)
    }
    let action = args[1]
    if action == "add" && args.count >= 4 {
        let name = args[2]
        let value = args.dropFirst(3).joined(separator: " ")
        HeaderRewrite.addRule(name: name, value: value)
        print("🐱 Header rule: add \(name): \(value)")
    } else if action == "remove" {
        HeaderRewrite.removeRule(name: args[2])
        print("🐱 Header rule: remove \(args[2])")
    } else {
        print("Usage: pry header add NAME VALUE")
        print("       pry header remove NAME")
        exit(1)
    }

case "headers":
    if args.count >= 2 && args[1] == "clear" {
        HeaderRewrite.clear()
        print("🐱 All header rules cleared")
    } else {
        let rules = HeaderRewrite.loadAll()
        if rules.isEmpty {
            print("No header rules")
        } else {
            print("Active header rules:")
            for r in rules {
                if r.action == .add {
                    print("  + \(r.name): \(r.value ?? "")")
                } else {
                    print("  - \(r.name)")
                }
            }
        }
    }

case "export":
    if args.count >= 2 && args[1] == "scenario" {
        guard args.count >= 3 else {
            print("Usage: pry export scenario NAME [--output FILE]")
            exit(1)
        }
        let name = args[2]
        let outputPath: String
        if let outputIdx = args.firstIndex(of: "--output"), outputIdx + 1 < args.count {
            outputPath = args[outputIdx + 1]
        } else {
            outputPath = "\(name).pryscenario"
        }
        do {
            try ScenarioExporter.export(name: name, to: outputPath)
            print("🐱 Scenario exported to: \(outputPath)")
        } catch {
            print("Error: \(error)")
            exit(1)
        }
    } else if args.count >= 3 && args[1] == "har" {
        let filePath = args[2]
        do {
            try HARExporter.exportToFile(from: RequestStore.shared, path: filePath)
            print("🐱 Exported HAR to \(filePath)")
        } catch {
            print("Error: \(error)")
            exit(1)
        }
    } else {
        print("Usage: pry export har output.har")
        print("       pry export scenario NAME [--output FILE]")
        exit(1)
    }

case "break":
    guard args.count >= 2 else {
        print("Usage: pry break /api/login")
        print("       pry break *.myapp.com")
        exit(1)
    }
    let pattern = args[1]
    BreakpointStore.shared.add(pattern)
    print("🐱 Breakpoint added: \(pattern)")
    print("   Requests matching this pattern will be paused in TUI")

case "breaks":
    if args.count >= 2 && args[1] == "clear" {
        BreakpointStore.shared.clearAll()
        print("🐱 All breakpoints cleared")
    } else {
        let patterns = BreakpointStore.shared.all()
        if patterns.isEmpty {
            print("🐱 No breakpoints set")
            print("   Add one with: pry break /api/login")
        } else {
            print("🐱 Active breakpoints:")
            for pattern in patterns {
                print("   ⏸️  \(pattern)")
            }
        }
    }

case "init":
    let dir = args.count >= 2 ? args[1] : FileManager.default.currentDirectoryPath
    print("🐱 Scanning \(dir) for API domains...")
    let domains = ProjectScanner.scan(directory: dir)
    if domains.isEmpty {
        print("   No domains found. Add them manually with: pry add DOMAIN")
    } else {
        for domain in domains {
            Watchlist.add(domain)
        }
        print("   Found \(domains.count) domain(s):")
        for domain in domains {
            print("   + \(domain)")
        }
        print("\n   Written to .prywatch")
        print("   Run 'pry trust' to install CA, then 'pry start'")
    }

case "nocache":
    guard args.count >= 2 else {
        print("Usage: pry nocache on|off")
        exit(1)
    }
    if args[1] == "on" {
        Config.set("nocache", value: "true")
        print("🐱 No-cache enabled — Cache-Control: no-store will be added to all requests")
    } else {
        Config.set("nocache", value: "false")
        print("🐱 No-cache disabled")
    }

case "block":
    guard args.count >= 2 else {
        print("Usage: pry block domain.com")
        exit(1)
    }
    BlockList.add(args[1])
    print("🐱 Blocked: \(args[1])")

case "blocks":
    if args.count >= 2 && args[1] == "clear" {
        BlockList.clear()
        print("🐱 Block list cleared")
    } else {
        let domains = BlockList.loadAll()
        if domains.isEmpty {
            print("🐱 No blocked domains")
        } else {
            print("🐱 Blocked domains:")
            for d in domains { print("   🚫 \(d)") }
        }
    }

case "redirect":
    guard args.count >= 3 else {
        print("Usage: pry redirect api.prod.com api.staging.com")
        exit(1)
    }
    MapRemote.save(sourceHost: args[1], targetHost: args[2])
    print("🐱 Redirect: \(args[1]) → \(args[2])")

case "redirects":
    if args.count >= 2 && args[1] == "clear" {
        MapRemote.clear()
        print("🐱 All redirects cleared")
    } else {
        let rules = MapRemote.loadAll()
        if rules.isEmpty {
            print("🐱 No redirects set")
        } else {
            print("🐱 Active redirects:")
            for r in rules { print("   \(r.sourceHost) → \(r.targetHost)") }
        }
    }

case "dns":
    if args.count >= 3 && args[1] != "list" && args[1] != "clear" {
        DNSSpoofing.add(domain: args[1], ip: args[2])
        print("🐱 DNS override: \(args[1]) → \(args[2])")
    } else if args.count >= 2 && args[1] == "clear" {
        DNSSpoofing.clear()
        print("🐱 DNS overrides cleared")
    } else if args.count >= 2 && args[1] == "list" {
        let rules = DNSSpoofing.loadAll()
        if rules.isEmpty {
            print("🐱 No DNS overrides")
        } else {
            print("🐱 DNS overrides:")
            for r in rules { print("   \(r.domain) → \(r.ip)") }
        }
    } else {
        print("Usage: pry dns DOMAIN IP | pry dns list | pry dns clear")
    }

case "send":
    guard args.count >= 3 else {
        print("Usage: pry send METHOD URL [--header \"Name: Value\"] [--body '{...}']")
        exit(1)
    }
    let method = args[1].uppercased()
    let urlStr = args[2]
    var headers: [(String, String)] = []
    var body: String?
    var i = 3
    while i < args.count {
        if args[i] == "--header" && i + 1 < args.count {
            let parts = args[i+1].split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                headers.append((parts[0].trimmingCharacters(in: .whitespaces), parts[1].trimmingCharacters(in: .whitespaces)))
            }
            i += 2
        } else if args[i] == "--body" && i + 1 < args.count {
            body = args[i+1]
            i += 2
        } else { i += 1 }
    }
    RequestComposer.send(method: method, urlString: urlStr, headers: headers, body: body, proxyPort: Config.defaultPort)

case "save":
    guard args.count >= 2 else {
        print("Usage: pry save session.pry")
        exit(1)
    }
    do {
        try SessionManager.save(to: args[1])
        let count = RequestStore.shared.count()
        print("🐱 Session saved: \(args[1]) (\(count) requests)")
    } catch {
        print("Error: \(error)")
        exit(1)
    }

case "load":
    guard args.count >= 2 else {
        print("Usage: pry load session.pry")
        exit(1)
    }
    do {
        try SessionManager.load(from: args[1])
        let count = RequestStore.shared.count()
        print("🐱 Session loaded: \(args[1]) (\(count) requests)")
    } catch {
        print("Error: \(error)")
        exit(1)
    }

case "diff":
    guard args.count >= 3, let id1 = Int(args[1]), let id2 = Int(args[2]) else {
        print("Usage: pry diff ID1 ID2")
        exit(1)
    }
    guard let req1 = RequestStore.shared.get(id: id1),
          let req2 = RequestStore.shared.get(id: id2) else {
        print("Error: Request not found")
        exit(1)
    }
    let diffLines = DiffTool.diff(req1: req1, req2: req2)
    print(DiffTool.format(diffLines))

case "rules":
    if args.count >= 2 && args[1] == "load" {
        guard args.count >= 3 else {
            print("Usage: pry rules load rules.pry")
            exit(1)
        }
        do {
            try RuleEngine.loadFromFile(path: args[2])
            let count = RuleEngine.all().count
            print("🐱 Loaded \(count) rule(s) from \(args[2])")
        } catch {
            print("Error: \(error)")
            exit(1)
        }
    } else if args.count >= 2 && args[1] == "clear" {
        RuleEngine.clear()
        print("🐱 All rules cleared")
    } else {
        let rules = RuleEngine.all()
        if rules.isEmpty {
            print("🐱 No rules loaded")
            print("   Load with: pry rules load rules.pry")
        } else {
            print("🐱 Active rules:")
            for rule in rules {
                let method = rule.method.map { "\($0) " } ?? ""
                print("   rule \"\(method)\(rule.pattern)\"")
                for action in rule.actions {
                    switch action {
                    case .setHeader(let n, let v): print("     set-header \(n) \"\(v)\"")
                    case .removeHeader(let n): print("     remove-header \(n)")
                    case .replaceHost(let h): print("     replace-host \(h)")
                    case .replacePort(let p): print("     replace-port \(p)")
                    case .replacePath(let p): print("     replace-path \"\(p)\"")
                    case .setStatus(let s): print("     set-status \(s)")
                    case .setBody(let b): print("     set-body '\(b.prefix(60))'")
                    case .delay(let ms): print("     delay \(ms)")
                    case .drop: print("     drop")
                    }
                }
            }
        }
    }

case "scenario":
    guard args.count >= 2 else {
        print("Usage: pry scenario <use|off|list|create|delete|show|capture> [NAME]")
        exit(1)
    }
    switch args[1] {
    case "use":
        guard args.count >= 3 else { print("Usage: pry scenario use NAME"); exit(1) }
        let name = args[2]
        if ScenarioManager.activate(name: name) {
            print("🐱 Scenario activated: \(name)")
        } else {
            print("Error: scenario '\(name)' not found")
            exit(1)
        }
    case "off":
        ScenarioManager.deactivate()
        print("🐱 Scenario deactivated")
    case "list":
        let scenarios = ScenarioManager.list()
        let active = ScenarioManager.active()
        if scenarios.isEmpty {
            print("No scenarios. Create one with: pry scenario create NAME")
        } else {
            for name in scenarios {
                let marker = (name == active) ? " (active)" : ""
                print("  \(name)\(marker)")
            }
        }
    case "create":
        guard args.count >= 3 else { print("Usage: pry scenario create NAME"); exit(1) }
        do {
            try ScenarioManager.create(name: args[2])
            print("🐱 Scenario created: \(args[2])")
        } catch {
            print("Error: \(error)")
            exit(1)
        }
    case "delete":
        guard args.count >= 3 else { print("Usage: pry scenario delete NAME"); exit(1) }
        ScenarioManager.delete(name: args[2])
        print("🐱 Scenario deleted: \(args[2])")
    case "show":
        guard args.count >= 3 else { print("Usage: pry scenario show NAME"); exit(1) }
        guard let scenario = ScenarioManager.load(name: args[2]) else {
            print("Error: scenario '\(args[2])' not found")
            exit(1)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(scenario), let json = String(data: data, encoding: .utf8) {
            print(json)
        }
    case "capture":
        guard args.count >= 3 else { print("Usage: pry scenario capture NAME"); exit(1) }
        do {
            try ScenarioManager.capture(name: args[2])
            print("🐱 Current config captured as scenario: \(args[2])")
        } catch {
            print("Error: \(error)")
            exit(1)
        }
    default:
        print("Unknown scenario command: \(args[1])")
        print("Usage: pry scenario <use|off|list|create|delete|show|capture> [NAME]")
        exit(1)
    }

case "override":
    guard args.count >= 3, let status = UInt(args[2]) else {
        print("Usage: pry override PATTERN STATUS_CODE")
        print("Example: pry override /api/login 401")
        exit(1)
    }
    StatusOverrideStore.save(pattern: args[1], status: status)
    print("🐱 Override: \(args[1]) → \(status)")

case "overrides":
    if args.count >= 2 && args[1] == "clear" {
        StatusOverrideStore.clear()
        print("🐱 All overrides cleared")
    } else {
        let overrides = StatusOverrideStore.loadAll()
        if overrides.isEmpty {
            print("No status overrides. Add one with: pry override /api/path 500")
        } else {
            for o in overrides {
                print("  \(o.pattern) → \(o.status)")
            }
        }
    }

case "project":
    guard args.count >= 2 else {
        print("Usage: pry project <init|list|apply|clear>")
        exit(1)
    }
    switch args[1] {
    case "init":
        do {
            try MockProject.initProject()
            print("🐱 Mock project initialized at .pry/mocking/")
        } catch {
            print("Error: \(error)")
            exit(1)
        }
    case "list":
        let mocks = MockProject.loadAll()
        if mocks.isEmpty {
            print("No project mocks. Init with: pry project init")
        } else {
            for m in mocks {
                let method = m.method ?? "*"
                print("  [\(method)] \(m.pattern) → \(m.status) (\(m.id))")
            }
        }
    case "apply":
        MockProject.applyAll()
        let count = MockProject.count()
        print("🐱 Applied \(count) project mock(s)")
    case "clear":
        MockProject.clear()
        print("🐱 Mock project cleared")
    default:
        print("Unknown project command: \(args[1])")
        exit(1)
    }

case "record":
    guard args.count >= 2 else {
        print("Usage: pry record <start|stop|list|show|delete|to-mocks> [NAME]")
        exit(1)
    }
    switch args[1] {
    case "start":
        guard args.count >= 3 else { print("Usage: pry record start NAME"); exit(1) }
        Recorder.shared.start(name: args[2])
        print("🐱 Recording started: \(args[2])")
    case "stop":
        if let recording = Recorder.shared.stop() {
            print("🐱 Recording stopped: \(recording.name) (\(recording.steps.count) steps)")
        } else {
            print("No active recording")
        }
    case "list":
        let recordings = Recorder.list()
        if recordings.isEmpty {
            print("No recordings. Start one with: pry record start NAME")
        } else {
            for name in recordings {
                if let r = Recorder.load(name: name) {
                    print("  \(name) — \(r.steps.count) steps")
                }
            }
        }
    case "show":
        guard args.count >= 3 else { print("Usage: pry record show NAME"); exit(1) }
        guard let recording = Recorder.load(name: args[2]) else {
            print("Error: recording '\(args[2])' not found")
            exit(1)
        }
        print("Recording: \(recording.name)")
        print("Steps: \(recording.steps.count)")
        for step in recording.steps {
            let status = step.statusCode.map { "\($0)" } ?? "?"
            print("  \(step.sequence). \(step.method) \(step.url) → \(status) (\(step.latencyMs)ms)")
        }
    case "delete":
        guard args.count >= 3 else { print("Usage: pry record delete NAME"); exit(1) }
        Recorder.delete(name: args[2])
        print("🐱 Recording deleted: \(args[2])")
    case "to-mocks":
        guard args.count >= 3 else { print("Usage: pry record to-mocks NAME"); exit(1) }
        let count = Recorder.toMocks(name: args[2])
        if count > 0 {
            print("🐱 Converted \(count) steps to mocks")
        } else {
            print("No steps to convert (recording not found or empty)")
        }
    default:
        print("Unknown record command: \(args[1])")
        exit(1)
    }

case "import":
    guard args.count >= 3 && args[1] == "scenario" else {
        print("Usage: pry import scenario FILE")
        exit(1)
    }
    do {
        let name = try ScenarioExporter.importScenario(from: args[2])
        print("🐱 Scenario imported: \(name)")
    } catch {
        print("Error: \(error)")
        exit(1)
    }

case "device":
    let ips = DeviceOnboarding.localIPAddresses()
    if ips.isEmpty {
        print("Error: no local network IP detected. Are you connected to Wi-Fi?")
        exit(1)
    }
    let ip = ips[0]
    let proxyPort = Config.port()
    print("🐱 Device Setup")
    print("   Proxy: \(ip):\(proxyPort)")
    print("   Setup page: http://\(ip):8081")
    print("")
    print("   Open http://\(ip):8081 on your device to configure it.")
    print("   Press Ctrl+C to stop the setup server.")
    print("")
    // Start onboarding server (blocking)
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    defer { try? group.syncShutdownGracefully() }
    do {
        let channel = try DeviceOnboarding.startServer(port: 8081, proxyPort: proxyPort, group: group)
        try channel.closeFuture.wait()
    } catch {
        print("Error starting setup server: \(error)")
        exit(1)
    }

case "help", "--help", "-h":
    printUsage()

default:
    print("Unknown command: \(command)")
    printUsage()
    exit(1)
}

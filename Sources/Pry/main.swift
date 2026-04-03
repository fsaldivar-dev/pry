import Foundation
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

    Examples:
      pry start
      pry add api.myapp.com
      pry add staging.myapp.com
      pry trust
      pry start --port 9090
      pry mock /api/login '{"token":"abc123"}'
      pry log
    """)
}

guard let command = args.first else {
    printUsage()
    exit(0)
}

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

    // Check if already running
    if let pidStr = try? String(contentsOfFile: Config.pidFile, encoding: .utf8),
       let pid = Int32(pidStr.trimmingCharacters(in: .whitespacesAndNewlines)),
       kill(pid, 0) == 0 {
        print("Error: \(ProxyError.alreadyRunning) (PID \(pid))")
        exit(1)
    }

    let server = ProxyServer(port: port)

    // Handle Ctrl+C
    signal(SIGINT) { _ in
        print("\n🐱 Pry stopped")
        try? FileManager.default.removeItem(atPath: Config.pidFile)
        exit(0)
    }
    signal(SIGTERM) { _ in
        try? FileManager.default.removeItem(atPath: Config.pidFile)
        exit(0)
    }

    do {
        try server.start()
    } catch {
        print("Error: \(error)")
        exit(1)
    }

case "stop":
    guard let pidStr = try? String(contentsOfFile: Config.pidFile, encoding: .utf8),
          let pid = Int32(pidStr.trimmingCharacters(in: .whitespacesAndNewlines)) else {
        print("Error: \(ProxyError.notRunning)")
        exit(1)
    }
    kill(pid, SIGTERM)
    try? FileManager.default.removeItem(atPath: Config.pidFile)
    print("🐱 Pry stopped (PID \(pid))")

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

case "help", "--help", "-h":
    printUsage()

default:
    print("Unknown command: \(command)")
    printUsage()
    exit(1)
}

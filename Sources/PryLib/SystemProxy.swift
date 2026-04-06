import Foundation

/// Manages macOS system proxy settings via `networksetup`.
/// Enables/disables HTTP and HTTPS proxy on the active network interface.
public struct SystemProxy {
    /// Detect the primary active network service (Wi-Fi, Ethernet, etc.)
    public static func activeNetworkService() -> String? {
        // Get the default route interface
        let routeProcess = Process()
        routeProcess.executableURL = URL(fileURLWithPath: "/sbin/route")
        routeProcess.arguments = ["-n", "get", "default"]
        let routePipe = Pipe()
        routeProcess.standardOutput = routePipe
        routeProcess.standardError = Pipe()
        try? routeProcess.run()
        routeProcess.waitUntilExit()

        let routeOutput = String(data: routePipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard let interfaceLine = routeOutput.components(separatedBy: "\n")
            .first(where: { $0.contains("interface:") }) else { return nil }
        let iface = interfaceLine.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "interface: ", with: "")

        // Map interface (en0, en1, etc.) to network service name
        let listProcess = Process()
        listProcess.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        listProcess.arguments = ["-listallhardwareports"]
        let listPipe = Pipe()
        listProcess.standardOutput = listPipe
        listProcess.standardError = Pipe()
        try? listProcess.run()
        listProcess.waitUntilExit()

        let listOutput = String(data: listPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let blocks = listOutput.components(separatedBy: "\n\n")
        for block in blocks {
            let lines = block.components(separatedBy: "\n")
            if lines.contains(where: { $0.contains("Device: \(iface)") }),
               let nameLine = lines.first(where: { $0.hasPrefix("Hardware Port:") }) {
                return nameLine.replacingOccurrences(of: "Hardware Port: ", with: "")
            }
        }

        // Fallback: try Wi-Fi
        return "Wi-Fi"
    }

    /// Enable HTTP + HTTPS proxy on the active network service.
    public static func enable(port: Int) {
        guard let service = activeNetworkService() else {
            print("[SystemProxy] Could not detect active network service")
            return
        }
        run("/usr/sbin/networksetup", ["-setwebproxy", service, "localhost", "\(port)"])
        run("/usr/sbin/networksetup", ["-setsecurewebproxy", service, "localhost", "\(port)"])
        run("/usr/sbin/networksetup", ["-setwebproxystate", service, "on"])
        run("/usr/sbin/networksetup", ["-setsecurewebproxystate", service, "on"])
        print("[SystemProxy] Enabled on \(service) → localhost:\(port)")
    }

    /// Disable HTTP + HTTPS proxy on the active network service.
    public static func disable() {
        guard let service = activeNetworkService() else {
            print("[SystemProxy] Could not detect active network service")
            return
        }
        run("/usr/sbin/networksetup", ["-setwebproxystate", service, "off"])
        run("/usr/sbin/networksetup", ["-setsecurewebproxystate", service, "off"])
        print("[SystemProxy] Disabled on \(service)")
    }

    /// Check if system proxy is currently pointing to our port.
    public static func isEnabled(port: Int) -> Bool {
        guard let service = activeNetworkService() else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        process.arguments = ["-getwebproxy", service]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return output.contains("Enabled: Yes") && output.contains("Port: \(port)")
    }

    private static func run(_ path: String, _ args: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
    }
}

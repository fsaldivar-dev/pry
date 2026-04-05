//
//  ContentView.swift
//  SimulationPry
//
//  Created by Francisco Javier Saldivar Rubio on 04/04/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var vm = RequestViewModel()

    var body: some View {
        NavigationView {
            List {
                Section("HTTP Requests") {
                    RequestButton(title: "GET httpbin.org/get", icon: "arrow.down.circle", color: .green) {
                        await vm.get("http://httpbin.org/get")
                    }
                    RequestButton(title: "POST httpbin.org/post", icon: "arrow.up.circle", color: .blue) {
                        await vm.post("http://httpbin.org/post", body: ["name": "Pry", "version": "1.0"])
                    }
                    RequestButton(title: "PUT httpbin.org/put", icon: "pencil.circle", color: .orange) {
                        await vm.put("http://httpbin.org/put", body: ["updated": true])
                    }
                    RequestButton(title: "DELETE httpbin.org/delete", icon: "trash.circle", color: .red) {
                        await vm.delete("http://httpbin.org/delete")
                    }
                }

                Section("HTTPS Requests") {
                    RequestButton(title: "GET https://httpbin.org/get", icon: "lock.shield", color: .green) {
                        await vm.get("https://httpbin.org/get")
                    }
                    RequestButton(title: "POST https://httpbin.org/post", icon: "lock.shield.fill", color: .blue) {
                        await vm.post("https://httpbin.org/post", body: ["secure": true])
                    }
                }

                Section("Status Codes") {
                    RequestButton(title: "200 OK", icon: "checkmark.circle", color: .green) {
                        await vm.get("https://httpbin.org/status/200")
                    }
                    RequestButton(title: "404 Not Found", icon: "xmark.circle", color: .orange) {
                        await vm.get("https://httpbin.org/status/404")
                    }
                    RequestButton(title: "500 Server Error", icon: "exclamationmark.triangle", color: .red) {
                        await vm.get("https://httpbin.org/status/500")
                    }
                }

                Section("Delays (para throttling)") {
                    RequestButton(title: "Delay 1s", icon: "clock", color: .purple) {
                        await vm.get("https://httpbin.org/delay/1")
                    }
                    RequestButton(title: "Delay 3s", icon: "clock.fill", color: .purple) {
                        await vm.get("https://httpbin.org/delay/3")
                    }
                }

                Section("Headers & Auth") {
                    RequestButton(title: "Con Bearer Token", icon: "key", color: .yellow) {
                        await vm.getWithAuth("https://httpbin.org/bearer", token: "pry-test-token-123")
                    }
                    RequestButton(title: "Custom Headers", icon: "list.bullet", color: .cyan) {
                        await vm.getWithHeaders("https://httpbin.org/headers", headers: [
                            "X-Pry-Test": "true",
                            "X-App-Version": "1.0",
                            "Accept-Language": "es-MX"
                        ])
                    }
                }

                Section("JSON Bodies") {
                    RequestButton(title: "POST JSON complejo", icon: "doc.text", color: .indigo) {
                        await vm.post("https://httpbin.org/post", body: [
                            "user": "francisco",
                            "action": "test_pry",
                            "timestamp": "\(Date())",
                            "nested": ["key": "value"]
                        ] as [String: Any])
                    }
                }

                if let response = vm.lastResponse {
                    Section("Última respuesta") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Status: \(vm.lastStatus)")
                                    .font(.headline)
                                    .foregroundColor(vm.lastStatus < 400 ? .green : .red)
                                Spacer()
                                Text("\(vm.lastDuration)ms")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Text(response)
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(20)
                        }
                    }
                }

                if let error = vm.lastError {
                    Section("Error") {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("🐱 Pry Test")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Clear") {
                        vm.clear()
                    }
                }
            }
        }
    }
}

struct RequestButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () async -> Void

    @State private var isLoading = false

    var body: some View {
        Button {
            Task {
                isLoading = true
                await action()
                isLoading = false
            }
        } label: {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                Spacer()
                if isLoading {
                    ProgressView()
                }
            }
        }
        .disabled(isLoading)
    }
}

#Preview {
    ContentView()
}

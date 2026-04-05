//
//  RequestViewModel.swift
//  SimulationPry
//
//  Created by Francisco Javier Saldivar Rubio on 04/04/26.
//

import Foundation
import SwiftUI
import Combine

@MainActor
class RequestViewModel: ObservableObject {
    @Published var lastResponse: String?
    @Published var lastError: String?
    @Published var lastStatus: Int = 0
    @Published var lastDuration: Int = 0

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        // Configurar proxy directamente en la app — no depender del proxy del sistema
        config.connectionProxyDictionary = [
            "HTTPEnable": true,
            "HTTPProxy": "127.0.0.1",
            "HTTPPort": 8080,
            "HTTPSEnable": true,
            "HTTPSProxy": "127.0.0.1",
            "HTTPSPort": 8080
        ]
        return URLSession(configuration: config)
    }()

    func get(_ urlString: String) async {
        await request(method: "GET", urlString: urlString)
    }

    func post(_ urlString: String, body: [String: Any]) async {
        await request(method: "POST", urlString: urlString, body: body)
    }

    func put(_ urlString: String, body: [String: Any]) async {
        await request(method: "PUT", urlString: urlString, body: body)
    }

    func delete(_ urlString: String) async {
        await request(method: "DELETE", urlString: urlString)
    }

    func getWithAuth(_ urlString: String, token: String) async {
        await request(method: "GET", urlString: urlString, headers: ["Authorization": "Bearer \(token)"])
    }

    func getWithHeaders(_ urlString: String, headers: [String: String]) async {
        await request(method: "GET", urlString: urlString, headers: headers)
    }

    func clear() {
        lastResponse = nil
        lastError = nil
        lastStatus = 0
        lastDuration = 0
    }

    private func request(method: String, urlString: String, body: [String: Any]? = nil, headers: [String: String]? = nil) async {
        guard let url = URL(string: urlString) else {
            lastError = "URL inválida: \(urlString)"
            return
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("SimulationPry/1.0", forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("close", forHTTPHeaderField: "Connection")

        if let body = body {
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        if let headers = headers {
            for (key, value) in headers {
                req.setValue(value, forHTTPHeaderField: key)
            }
        }

        let start = Date()
        lastError = nil

        do {
            let (data, response) = try await session.data(for: req)
            let duration = Int(Date().timeIntervalSince(start) * 1000)
            lastDuration = duration

            if let httpResponse = response as? HTTPURLResponse {
                lastStatus = httpResponse.statusCode
            }

            if let json = try? JSONSerialization.jsonObject(with: data),
               let prettyData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
               let prettyString = String(data: prettyData, encoding: .utf8) {
                lastResponse = prettyString
            } else {
                lastResponse = String(data: data, encoding: .utf8) ?? "[\(data.count) bytes]"
            }
        } catch {
            lastError = error.localizedDescription
            lastResponse = nil
        }
    }
}

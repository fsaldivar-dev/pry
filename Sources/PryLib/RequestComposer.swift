import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct RequestComposer {
    /// Build a URLRequest (testable, no side effects)
    public static func buildRequest(method: String, urlString: String, headers: [(String, String)], body: String?) -> URLRequest? {
        guard let url = URL(string: urlString), !urlString.isEmpty else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = method
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        if let body = body {
            request.httpBody = body.data(using: .utf8)
        }
        return request
    }

    /// Send request through the proxy (side effect)
    public static func send(method: String, urlString: String, headers: [(String, String)], body: String?, proxyPort: Int) {
        guard let request = buildRequest(method: method, urlString: urlString, headers: headers, body: body) else {
            print("Error: Invalid URL: \(urlString)")
            return
        }
        let config = URLSessionConfiguration.default
        #if canImport(Darwin)
        config.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable: true,
            kCFNetworkProxiesHTTPProxy: "127.0.0.1",
            kCFNetworkProxiesHTTPPort: proxyPort
        ]
        #else
        config.connectionProxyDictionary = [
            "HTTPEnable": true,
            "HTTPProxy": "127.0.0.1",
            "HTTPPort": proxyPort
        ]
        #endif
        let session = URLSession(configuration: config)
        let semaphore = DispatchSemaphore(value: 0)

        session.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Error: \(error.localizedDescription)")
            } else if let httpResp = response as? HTTPURLResponse {
                print("<<< \(httpResp.statusCode)")
                if let data = data, let text = String(data: data, encoding: .utf8) {
                    print(text)
                }
            }
            semaphore.signal()
        }.resume()
        semaphore.wait()
    }
}

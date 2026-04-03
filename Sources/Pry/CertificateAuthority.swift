import Foundation
import X509
import SwiftASN1
import Crypto
import NIOSSL

final class CertificateAuthority {
    static let caDir = NSHomeDirectory() + "/.pry/ca"
    static let caCertPath = caDir + "/pry-ca.pem"
    static let caKeyPath = caDir + "/pry-ca-key.pem"

    private let caKey: P256.Signing.PrivateKey
    private let caCertificate: Certificate
    private var certCache: [String: (NIOSSLCertificate, NIOSSLPrivateKey)] = [:]

    init() throws {
        // Create dir if needed
        try FileManager.default.createDirectory(atPath: Self.caDir, withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: Self.caCertPath),
           FileManager.default.fileExists(atPath: Self.caKeyPath) {
            // Load existing
            let keyPem = try String(contentsOfFile: Self.caKeyPath, encoding: .utf8)
            let certPem = try String(contentsOfFile: Self.caCertPath, encoding: .utf8)
            self.caKey = try P256.Signing.PrivateKey(pemRepresentation: keyPem)
            self.caCertificate = try Certificate(pemEncoded: certPem)
        } else {
            // Generate new CA
            let key = P256.Signing.PrivateKey()
            let name = try DistinguishedName {
                CommonName("Pry CA")
                OrganizationName("Pry Proxy")
            }

            let extensions = try Certificate.Extensions {
                Critical(BasicConstraints.isCertificateAuthority(maxPathLength: 0))
                Critical(KeyUsage(keyCertSign: true, cRLSign: true))
            }

            let cert = try Certificate(
                version: .v3,
                serialNumber: Certificate.SerialNumber(bytes: withUnsafeBytes(of: UInt64.random(in: 0...UInt64.max)) { Array($0) }),
                publicKey: .init(key.publicKey),
                notValidBefore: Date(),
                notValidAfter: Date(timeIntervalSinceNow: 365 * 24 * 3600 * 5), // 5 years
                issuer: name,
                subject: name,
                signatureAlgorithm: .ecdsaWithSHA256,
                extensions: extensions,
                issuerPrivateKey: .init(key)
            )

            self.caKey = key
            self.caCertificate = cert

            // Save to disk
            var serializer = DER.Serializer()
            try cert.serialize(into: &serializer)
            let certPem = try Certificate.PEMRepresentation(cert)
            try certPem.write(toFile: Self.caCertPath, atomically: true, encoding: .utf8)
            try key.pemRepresentation.write(toFile: Self.caKeyPath, atomically: true, encoding: .utf8)

            print("🐱 Generated new CA certificate: \(Self.caCertPath)")
        }
    }

    func generateCert(for domain: String) throws -> (certificate: NIOSSLCertificate, key: NIOSSLPrivateKey) {
        if let cached = certCache[domain] {
            return cached
        }

        let serverKey = P256.Signing.PrivateKey()

        let name = try DistinguishedName {
            CommonName(domain)
            OrganizationName("Pry Proxy")
        }

        let extensions = try Certificate.Extensions {
            SubjectAlternativeNames([
                .dnsName(domain)
            ])
        }

        let cert = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(bytes: withUnsafeBytes(of: UInt64.random(in: 0...UInt64.max)) { Array($0) }),
            publicKey: .init(serverKey.publicKey),
            notValidBefore: Date(),
            notValidAfter: Date(timeIntervalSinceNow: 365 * 24 * 3600), // 1 year
            issuer: caCertificate.subject,
            subject: name,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: extensions,
            issuerPrivateKey: .init(caKey)
        )

        let certPem = try Certificate.PEMRepresentation(cert)
        let nioSSLCert = try NIOSSLCertificate(bytes: Array(certPem.utf8), format: .pem)
        let nioSSLKey = try NIOSSLPrivateKey(bytes: Array(serverKey.pemRepresentation.utf8), format: .pem)

        certCache[domain] = (nioSSLCert, nioSSLKey)
        return (nioSSLCert, nioSSLKey)
    }

    func printInfo() {
        print("CA Certificate: \(Self.caCertPath)")
        print("CA Key:         \(Self.caKeyPath)")
        print("Subject:        Pry CA")
        print("Cached certs:   \(certCache.count)")
    }
}

extension Certificate {
    static func PEMRepresentation(_ cert: Certificate) throws -> String {
        var serializer = DER.Serializer()
        try cert.serialize(into: &serializer)
        let derBytes = serializer.serializedBytes
        let base64 = Data(derBytes).base64EncodedString()
        // PEM requires 64-char lines
        var lines = [String]()
        var idx = base64.startIndex
        while idx < base64.endIndex {
            let end = base64.index(idx, offsetBy: 64, limitedBy: base64.endIndex) ?? base64.endIndex
            lines.append(String(base64[idx..<end]))
            idx = end
        }
        return "-----BEGIN CERTIFICATE-----\n\(lines.joined(separator: "\n"))\n-----END CERTIFICATE-----"
    }
}

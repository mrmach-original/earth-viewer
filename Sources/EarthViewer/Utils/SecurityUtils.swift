import Foundation
import CryptoKit

enum SecurityError: Error {
    case invalidChecksum
    case fileSizeTooLarge
    case downloadFailed(String)
}

class SecurityUtils {
    static let maxFileSize: Int64 = 50 * 1024 * 1024  // 50MB limit
    
    // Exponential backoff settings
    static var retryAttempts = 0
    static let maxRetryAttempts = 5
    static var lastRetryTime: Date?
    
    // Certificate pinning
    private static let pinnedCertificates: [String: [String]] = [
        "cdn.star.nesdis.noaa.gov": [
            "sha256//VRManf2vhQ9FxUFYUJCNBYqF0PZ5LN1CX5M2/+9H5GE=",  // Primary cert
            "sha256//YZPgTZ+woNCCCIW3LH2CxQeLzB/1m42QcCTBSdUeFRE="   // Backup cert
        ],
        "eoimages.gsfc.nasa.gov": [
            "sha256//KwccWaCgrnaw6tsrrSO61FgLacNgG2MMLq8GE6+oP5I=",  // Primary cert
            "sha256//grX4Ta9HpZx6tSHkmCrvpApTQGo67CYDnvprLg5yRME="   // Backup cert
        ]
    ]
    
    static func validateFileSize(_ url: URL) throws {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? Int64 else {
            throw SecurityError.invalidFile
        }
        
        if fileSize > maxFileSize {
            throw SecurityError.fileSizeTooLarge
        }
    }
    
    static func calculateChecksum(of data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    static func shouldRetry() -> TimeInterval? {
        guard retryAttempts < maxRetryAttempts else { return nil }
        
        let backoffTime = pow(2.0, Double(retryAttempts)) // Exponential backoff
        retryAttempts += 1
        lastRetryTime = Date()
        
        return backoffTime
    }
    
    static func resetRetry() {
        retryAttempts = 0
        lastRetryTime = nil
    }
    
    // Enhanced SSL Certificate pinning
    static func verifyServerTrust(_ serverTrust: SecTrust, domain: String) -> Bool {
        let policies = NSMutableArray()
        policies.add(SecPolicyCreateSSL(true, domain as CFString))
        
        SecTrustSetPolicies(serverTrust, policies)
        
        // Verify basic trust evaluation
        var error: CFError?
        guard SecTrustEvaluateWithError(serverTrust, &error) else {
            SecureLogger.shared.log("SSL Trust evaluation failed: \(String(describing: error))", type: "ERROR")
            return false
        }
        
        // Get the server's certificate chain
        let serverCertificatesCount = SecTrustGetCertificateCount(serverTrust)
        guard serverCertificatesCount > 0,
              let serverCertificate = SecTrustGetCertificateAtIndex(serverTrust, 0) else {
            SecureLogger.shared.log("No certificates found", type: "ERROR")
            return false
        }
        
        // Get the public key data
        guard let serverPublicKey = SecCertificateCopyKey(serverCertificate),
              let serverPublicKeyData = SecKeyCopyExternalRepresentation(serverPublicKey, nil) as Data? else {
            SecureLogger.shared.log("Could not get public key data", type: "ERROR")
            return false
        }
        
        // Calculate the hash of the public key
        let serverKeyHash = SHA256.hash(data: serverPublicKeyData)
        let serverKeyHashString = "sha256//" + serverKeyHash.compactMap { String(format: "%02x", $0) }.joined()
        
        // Check if the hash matches any of our pinned certificates for this domain
        guard let pinnedHashes = pinnedCertificates[domain],
              pinnedHashes.contains(serverKeyHashString) else {
            SecureLogger.shared.log("Certificate pinning failed for domain: \(domain)", type: "ERROR")
            return false
        }
        
        return true
    }
}

// Secure logging with rotation
class SecureLogger {
    static let shared = SecureLogger()
    private let logFile: URL
    private let dateFormatter: DateFormatter
    private let maxLogSize: Int64 = 10 * 1024 * 1024  // 10MB
    private let maxLogFiles = 5
    
    private init() {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        logFile = paths[0].appendingPathComponent("secure.log")
        
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    }
    
    func log(_ message: String, type: String = "INFO") {
        let timestamp = dateFormatter.string(from: Date())
        let logMessage = "[\(timestamp)] [\(type)] \(message)\n"
        
        do {
            if !FileManager.default.fileExists(atPath: logFile.path) {
                try "".write(to: logFile, atomically: true, encoding: .utf8)
            }
            
            // Check log size and rotate if needed
            let attributes = try FileManager.default.attributesOfItem(atPath: logFile.path)
            if let fileSize = attributes[.size] as? Int64, fileSize > maxLogSize {
                rotateLog()
            }
            
            let handle = try FileHandle(forWritingTo: logFile)
            handle.seekToEndOfFile()
            handle.write(logMessage.data(using: .utf8)!)
            handle.closeFile()
        } catch {
            print("Failed to write to log: \(error)")
        }
    }
    
    private func rotateLog() {
        let fileManager = FileManager.default
        
        // Remove oldest log if we have reached max files
        if let oldestLog = logFile.deletingPathExtension().appendingPathExtension("log.\(maxLogFiles)") {
            try? fileManager.removeItem(at: oldestLog)
        }
        
        // Rotate existing logs
        for i in (1...maxLogFiles-1).reversed() {
            let oldPath = logFile.deletingPathExtension().appendingPathExtension("log.\(i)")
            let newPath = logFile.deletingPathExtension().appendingPathExtension("log.\(i+1)")
            try? fileManager.moveItem(at: oldPath, to: newPath)
        }
        
        // Move current log to .log.1
        let rotatedLog = logFile.deletingPathExtension().appendingPathExtension("log.1")
        try? fileManager.moveItem(at: logFile, to: rotatedLog)
    }
} 
import Cocoa
import Foundation
import CryptoKit
import Security

enum Assets {
    struct ImageMetadata {
        let url: String
        let updateFrequency: String
        let longitude: Double
        let expectedChecksum: String?  // Added for security
    }
    
    static let metadata: [GlobeView.EarthTexture: ImageMetadata] = [
        .blueMarble: ImageMetadata(
            url: "",
            updateFrequency: "Static base image",
            longitude: 0,
            expectedChecksum: nil),
        .goesEast: ImageMetadata(
            url: "https://cdn.star.nesdis.noaa.gov/GOES16/ABI/FD/GEOCOLOR/latest.jpg",
            updateFrequency: "Updates every 10 minutes",
            longitude: -75.2,
            expectedChecksum: nil),  // Dynamic content, checksum varies
        .goesWest: ImageMetadata(
            url: "https://cdn.star.nesdis.noaa.gov/GOES17/ABI/FD/GEOCOLOR/latest.jpg",
            updateFrequency: "Updates every 10 minutes",
            longitude: -137.2,
            expectedChecksum: nil)  // Dynamic content, checksum varies
    ]
    
    static func earthTexture(for type: GlobeView.EarthTexture) -> NSImage? {
        guard let resourcePath = Bundle.main.resourcePath else {
            SecureLogger.shared.log("Failed to get resource path", type: "ERROR")
            return nil
        }
        
        // For GOES images, download fresh copy
        if type != .blueMarble {
            return downloadAndValidateTexture(type: type, resourcePath: resourcePath)
        }
        
        // Fall back to saved image
        let imagePath = (resourcePath as NSString).appendingPathComponent(type.filename)
        return NSImage(contentsOfFile: imagePath)
    }
    
    private static func downloadAndValidateTexture(type: GlobeView.EarthTexture, resourcePath: String) -> NSImage? {
        guard let metadata = metadata[type],
              let url = URL(string: metadata.url),
              !metadata.url.isEmpty else {
            SecureLogger.shared.log("Invalid URL for texture type: \(type)", type: "ERROR")
            return nil
        }
        
        let configuration = URLSessionConfiguration.ephemeral
        let session = URLSession(configuration: configuration, delegate: SSLPinningDelegate(), delegateQueue: nil)
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Earth-Viewer/1.0", forHTTPHeaderField: "User-Agent")
        
        var image: NSImage?
        let semaphore = DispatchSemaphore(value: 0)
        
        let task = session.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            
            // Handle network errors
            if let error = error {
                SecureLogger.shared.log("Download failed: \(error.localizedDescription)", type: "ERROR")
                return
            }
            
            // Validate response
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                SecureLogger.shared.log("Invalid HTTP response", type: "ERROR")
                return
            }
            
            guard let data = data else {
                SecureLogger.shared.log("No data received", type: "ERROR")
                return
            }
            
            // Validate file size
            guard data.count <= SecurityUtils.maxFileSize else {
                SecureLogger.shared.log("File size exceeds maximum allowed", type: "ERROR")
                return
            }
            
            // Create temporary file for validation
            let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
            do {
                try data.write(to: tempURL)
                try SecurityUtils.validateFileSize(tempURL)
                
                // Log checksum for auditing
                let checksum = SecurityUtils.calculateChecksum(of: data)
                SecureLogger.shared.log("Downloaded file checksum: \(checksum)")
                
                if let nsImage = NSImage(data: data) {
                    // Save to disk for backup with atomic write
                    let imagePath = (resourcePath as NSString).appendingPathComponent(type.filename)
                    try data.write(to: URL(fileURLWithPath: imagePath), options: .atomic)
                    image = nsImage
                    SecurityUtils.resetRetry()
                }
            } catch {
                SecureLogger.shared.log("File validation failed: \(error.localizedDescription)", type: "ERROR")
            }
            
            // Cleanup
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        task.resume()
        _ = semaphore.wait(timeout: .now() + 30)  // 30 second timeout
        
        if image == nil {
            // Handle retry logic
            if let backoffTime = SecurityUtils.shouldRetry() {
                SecureLogger.shared.log("Retrying download after \(backoffTime) seconds")
                Thread.sleep(forTimeInterval: backoffTime)
                return downloadAndValidateTexture(type: type, resourcePath: resourcePath)
            }
            
            // Fall back to saved image if download fails
            let imagePath = (resourcePath as NSString).appendingPathComponent(type.filename)
            return NSImage(contentsOfFile: imagePath)
        }
        
        return image
    }
}

// SSL Pinning Delegate
class SSLPinningDelegate: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, 
                   completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        
        guard let serverTrust = challenge.protectionSpace.serverTrust,
              let domain = challenge.protectionSpace.host as CFString? else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        
        if SecurityUtils.verifyServerTrust(serverTrust, domain: domain as String) {
            let credential = URLCredential(trust: serverTrust)
            completionHandler(.useCredential, credential)
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}
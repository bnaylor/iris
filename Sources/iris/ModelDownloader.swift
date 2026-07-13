import Foundation
import SwiftUI

@Observable
@MainActor
class ModelDownloader {
    static let shared = ModelDownloader()
    
    var isDownloading = false
    var progress: Double = 0.0
    var error: String? = nil
    
    // Some known models and their URLs for convenience
    let knownModels = [
        "Llama-3.2-1B-Instruct-Q4_K_M.gguf": "https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf"
    ]
    
    func isModelDownloaded(name: String) -> Bool {
        let filename = name.starts(with: "http") ? (URL(string: name)?.lastPathComponent ?? name) : name
        let path = ("~/.iris/models/" as NSString).expandingTildeInPath + "/" + filename
        return FileManager.default.fileExists(atPath: path)
    }
    
    func downloadModel(name: String) async {
        guard !isDownloading else { return }
        
        let isUrl = name.starts(with: "http")
        let urlString = knownModels[name] ?? (isUrl ? name : nil)
        
        guard let finalUrlString = urlString, let url = URL(string: finalUrlString), url.scheme != nil else {
            self.error = "Unknown model name. Please provide a full https:// URL to a .gguf file."
            return
        }
        
        let filename = isUrl ? url.lastPathComponent : name
        
        guard !isModelDownloaded(name: filename) else {
            if isUrl { ConfigManager.shared.vibecopModel = filename }
            return 
        }
        
        self.isDownloading = true
        self.progress = 0.0
        self.error = nil
        
        let dirPath = ("~/.iris/models/" as NSString).expandingTildeInPath
        if !FileManager.default.fileExists(atPath: dirPath) {
            try? FileManager.default.createDirectory(atPath: dirPath, withIntermediateDirectories: true)
        }
        
        let destination = URL(fileURLWithPath: dirPath).appendingPathComponent(filename)
        
        do {
            let request = URLRequest(url: url)
            let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                self.error = "Download failed: Invalid response"
                self.isDownloading = false
                return
            }
            
            let contentLength = Double(httpResponse.expectedContentLength)
            var currentLength: Double = 0
            
            FileManager.default.createFile(atPath: destination.path, contents: nil)
            let handle = try FileHandle(forWritingTo: destination)
            defer { try? handle.close() }
            
            var lastUpdate = Date()
            
            for try await byte in asyncBytes {
                try handle.write(contentsOf: Data([byte]))
                currentLength += 1
                
                let now = Date()
                if now.timeIntervalSince(lastUpdate) > 0.1 {
                    self.progress = contentLength > 0 ? currentLength / contentLength : 0
                    lastUpdate = now
                }
            }
            self.progress = 1.0
            self.isDownloading = false
            
            if isUrl {
                Task { @MainActor in
                    ConfigManager.shared.vibecopModel = filename
                }
            }
            
        } catch {
            self.error = "Download failed: \(error.localizedDescription)"
            self.isDownloading = false
            try? FileManager.default.removeItem(at: destination)
        }
    }
}

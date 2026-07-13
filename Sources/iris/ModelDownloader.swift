import Foundation
import SwiftUI

@Observable
@MainActor
class ModelDownloader: NSObject, URLSessionDownloadDelegate {
    static let shared = ModelDownloader()
    
    var isDownloading = false
    var progress: Double = 0.0
    var error: String? = nil
    
    private var downloadTask: URLSessionDownloadTask?
    private var destinationFilename: String?
    private var isUrlDownload = false
    
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
        self.destinationFilename = filename
        self.isUrlDownload = isUrl
        
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
        
        let configuration = URLSessionConfiguration.default
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
        
        let request = URLRequest(url: url)
        self.downloadTask = session.downloadTask(with: request)
        self.downloadTask?.resume()
    }
    
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        Task { @MainActor in
            guard let filename = self.destinationFilename else { return }
            let dirPath = ("~/.iris/models/" as NSString).expandingTildeInPath
            let destination = URL(fileURLWithPath: dirPath).appendingPathComponent(filename)
            
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: location, to: destination)
                
                self.progress = 1.0
                self.isDownloading = false
                
                if self.isUrlDownload {
                    ConfigManager.shared.vibecopModel = filename
                }
            } catch {
                self.error = "Download failed to save: \(error.localizedDescription)"
                self.isDownloading = false
            }
        }
    }
    
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        Task { @MainActor in
            if totalBytesExpectedToWrite > 0 {
                self.progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            }
        }
    }
    
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        Task { @MainActor in
            if let error = error {
                self.error = "Download failed: \(error.localizedDescription)"
                self.isDownloading = false
            }
        }
    }
}

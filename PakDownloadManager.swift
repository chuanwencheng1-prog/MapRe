// PakDownloadManager.swift
// 对应原始 PakDownloadManager 模块 - PAK 文件下载管理器

import Foundation
import Combine

// MARK: - PakDownloadManager（对应原始 PakDownloadManager）
class PakDownloadManager: NSObject, ObservableObject {

    static let shared = PakDownloadManager()

    // MARK: - 对应原始 @Published 属性
    @Published var isDownloading: Bool = false
    @Published var downloadProgress: Double = 0.0
    @Published var downloadedBytes: Int64 = 0
    @Published var totalBytes: Int64 = 0
    @Published var downloadStatus: String = "就绪"

    private var downloadSession: URLSession?
    private var downloadTask: URLSessionDownloadTask?
    private var downloadCompletion: ((URL?) -> Void)?
    private var currentMode: PakMode?

    private override init() {
        super.init()
        let config = URLSessionConfiguration.background(
            withIdentifier: "com.pakreplacertest.download"
        )
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        self.downloadSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    // MARK: - 缓存目录
    private static var cacheDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let cache = docs.appendingPathComponent("PakCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        return cache
    }

    // MARK: - 缓存路径（对应原始 cachedPath）
    static func cachedPath(for mode: PakMode, cheatSub: CheatSubMode) -> String {
        return cacheDirectory.appendingPathComponent("\(mode.rawValue)_\(cheatSub.rawValue).pak").path
    }

    // MARK: - 缓存文件大小
    static func cachedFileSize(for mode: PakMode, cheatSub: CheatSubMode) -> UInt64 {
        let path = cachedPath(for: mode, cheatSub: cheatSub)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? UInt64 else { return 0 }
        return size
    }

    // MARK: - 下载 URL 构建（对应原始 downloadURL）
    static func downloadURL(for config: PakFileConfig) -> URL? {
        return URL(string: config.downloadURL)
    }

    // MARK: - 格式化文件大小
    private func formatSize(_ bytes: UInt64) -> String {
        let mb = Double(bytes) / 1024.0 / 1024.0
        if mb >= 1.0 {
            return String(format: "%.1f MB", mb)
        } else {
            return String(format: "%.0f KB", Double(bytes) / 1024.0)
        }
    }

    // MARK: - 开始下载（对应原始 download:url:mode:cheatSub:completion:）
    func download(config: PakFileConfig,
                  progress: @escaping (String) -> Void,
                  completion: @escaping (String?) -> Void) {

        guard !isDownloading else {
            completion("下载中，请稍候...")
            return
        }

        guard let url = URL(string: config.downloadURL), !config.downloadURL.isEmpty else {
            completion("下载地址无效，请检查配置")
            return
        }

        DispatchQueue.main.async {
            self.isDownloading = true
            self.downloadProgress = 0
            self.downloadedBytes = 0
            self.totalBytes = 0
            self.downloadStatus = "连接服务器..."
        }

        // 保存 completion 回调，供 delegate 使用
        self.downloadCompletion = { [weak self] localURL in
            guard let self = self else { return }
            guard let localURL = localURL else {
                DispatchQueue.main.async {
                    self.isDownloading = false
                    self.downloadStatus = "下载失败"
                }
                completion("下载失败，请重试")
                return
            }

            // 移动到缓存目录
            let destURL = Self.cacheDirectory.appendingPathComponent(config.pakFileName)
            try? FileManager.default.removeItem(at: destURL)
            do {
                try FileManager.default.moveItem(at: localURL, to: destURL)
                DispatchQueue.main.async {
                    self.isDownloading = false
                    self.downloadStatus = "下载完成"
                    self.downloadProgress = 1.0
                }
                completion(nil) // nil 表示成功
            } catch {
                DispatchQueue.main.async {
                    self.isDownloading = false
                    self.downloadStatus = "保存失败"
                }
                completion("文件保存失败: \(error.localizedDescription)")
            }
        }

        let request = URLRequest(url: url)
        downloadTask = downloadSession?.downloadTask(with: request)
        downloadTask?.resume()
        DispatchQueue.main.async { self.downloadStatus = "下载中..." }
    }

    // MARK: - 取消下载（对应原始 cancelDownload）
    func cancelDownload() {
        downloadTask?.cancel()
        DispatchQueue.main.async {
            self.isDownloading = false
            self.downloadStatus = "已取消"
            self.downloadProgress = 0
        }
    }

    // MARK: - 获取 PAK 本地路径（对应原始 getPakFilePath）
    func getPakFilePath(for config: PakFileConfig,
                        progress: @escaping (String) -> Void,
                        completion: @escaping (String?) -> Void) {

        let cachePath = Self.cacheDirectory.appendingPathComponent(config.pakFileName).path
        // 如果本地有缓存直接返回
        if FileManager.default.fileExists(atPath: cachePath) {
            completion(cachePath)
        } else {
            // 下载
            download(config: config, progress: progress) { error in
                if error == nil {
                    completion(cachePath)
                } else {
                    completion(nil)
                }
            }
        }
    }
}

// MARK: - URLSession 下载代理
extension PakDownloadManager: URLSessionDownloadDelegate {

    // 下载进度（对应原始 urlSession:downloadTask:didWriteData:）
    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        DispatchQueue.main.async {
            self.downloadedBytes = totalBytesWritten
            self.totalBytes = totalBytesExpectedToWrite
            if totalBytesExpectedToWrite > 0 {
                self.downloadProgress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
                let downloaded = self.formatSize(UInt64(totalBytesWritten))
                let total = self.formatSize(UInt64(totalBytesExpectedToWrite))
                self.downloadStatus = "\(downloaded) / \(total)"
            }
        }
    }

    // 下载完成（对应原始 urlSession:downloadTask:didFinishDownloadingTo:）
    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        downloadCompletion?(location)
        downloadCompletion = nil
    }

    // 任务完成/出错（对应原始 urlSession:task:didCompleteWithError:）
    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        if let error = error {
            DispatchQueue.main.async {
                self.isDownloading = false
                self.downloadStatus = "网络错误: \(error.localizedDescription)"
            }
            downloadCompletion?(nil)
            downloadCompletion = nil
        }
    }
}

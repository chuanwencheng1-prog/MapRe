// PakReplacerViewModel.swift
// 对应原始 PakReplacerViewModel - 主业务逻辑 ViewModel

import Foundation
import Combine
import SwiftUI
import BackgroundTasks

class PakReplacerViewModel: ObservableObject {

    // MARK: - 对应原始 @Published 状态
    @Published var isVerified: Bool = false
    @Published var showAlert: Bool = false
    @Published var alertMessage: String = ""
    @Published var exploitStatus: ExploitStatus = .idle
    @Published var exploitLog: [String] = []
    @Published var selectedMode: PakMode = .cheat
    @Published var selectedCheatSub: CheatSubMode = .full
    @Published var pakConfigs: [PakFileConfig] = PakFileConfig.defaultConfigs
    @Published var showPathPicker: Bool = false
    @Published var appStatus: AppStatus = AppStatus()

    // 对应原始 autoRestoreTimer
    private var autoRestoreTimer: Timer?
    @Published var autoRestoreCountdown: Int = 0

    // 对应原始 autoRestoreCountdown (Combine Published)
    private var cancellables = Set<AnyCancellable>()

    init() {
        checkActivationStatus()
        detectEnvironment()
    }

    // MARK: - 检查激活状态（对应原始 isVerified）
    func checkActivationStatus() {
        isVerified = SecureCardStorage.shared.isActivated
        appStatus.isVerified = isVerified
    }

    // MARK: - 检测运行环境（对应原始环境检测逻辑）
    func detectEnvironment() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            var info = DeviceInfo()

            // 检测 TrollStore
            let trollStorePaths = [
                "/Applications/TrollStore.app",
                "/var/jb/Applications/TrollStore.app",
                "/var/mobile/Library/TrollStore",
                "/usr/bin/trollstorehelper"
            ]
            info.hasTrollStore = trollStorePaths.contains { FileManager.default.fileExists(atPath: $0) }

            // 检测 Frida
            info.hasFrida = FileManager.default.fileExists(atPath: "/usr/sbin/frida-server")

            // 检测 MobileSubstrate
            let substratePaths = [
                "/Library/MobileSubstrate/",
                "/usr/lib/libsubstrate.dylib"
            ]
            info.hasMobileSubstrate = substratePaths.contains { FileManager.default.fileExists(atPath: $0) }

            // 检测越狱
            info.isJailbroken = info.hasTrollStore || info.hasFrida || info.hasMobileSubstrate

            DispatchQueue.main.async {
                self.appStatus.deviceInfo = info
                self.appStatus.isTrollStoreInstalled = info.hasTrollStore
                self.appendLog("环境检测完成")
                self.appendLog("TrollStore: \(info.hasTrollStore ? "✅ 已安装" : "❌ 未安装")")
                self.appendLog("Frida: \(info.hasFrida ? "⚠️ 检测到" : "✅ 未检测到")")
                self.appendLog("MobileSubstrate: \(info.hasMobileSubstrate ? "⚠️ 检测到" : "✅ 未检测到")")
            }
        }
    }

    // MARK: - 验证卡密（对应原始 verifyCardCode）
    func verifyCardCode(_ code: String) {
        guard !code.isEmpty else {
            showAlertMessage("请输入卡密")
            return
        }

        let deviceId = SecureCardStorage.shared.cachedDeviceId()
        appendLog("正在验证卡密...")

        TXNHVerifyAPI.shared.verifyCardCode(code, deviceId: deviceId) { [weak self] result in
            guard let self = self else { return }
            if result.success {
                self.isVerified = true
                self.appStatus.isVerified = true
                self.appendLog("✅ 验证成功: \(result.message)")
                // 上报设备
                TXNHVerifyAPI.shared.reportDevice(deviceId: deviceId)
            } else {
                self.showAlertMessage("验证失败: \(result.message)")
                self.appendLog("❌ 验证失败: \(result.message)")
            }
        }
    }

    // MARK: - 执行 Exploit（对应原始 runExploitWithCompletion）
    func runExploit(completion: @escaping (Bool, String) -> Void) {
        guard exploitStatus != .running else { return }

        exploitStatus = .running
        let strategy = ExploitRunner.shared.detectBestStrategy()
        appendLog("开始运行 Exploit...")
        appendLog("设备: \(appStatus.deviceInfo.deviceModel) iOS \(appStatus.deviceInfo.osVersion)")
        appendLog("推荐策略: \(strategy)")

        // 调用真实 Exploit（MDC / KFD / cicuta_virosa 自动选择）
        ExploitRunner.shared.run { [weak self] success, message in
            guard let self = self else { return }
            if success {
                self.exploitStatus = .success
                self.appStatus.sandboxEscaped = true
                self.appendLog("✅ Exploit 成功: \(message)")

                // 沙盒逃逸
                if sandbox_escape() {
                    self.appendLog("✅ 沙盒逃逸成功")
                } else {
                    self.appendLog("⚠️ 沙盒逃逸未完成（TrollStore模式不需要）")
                }

                completion(true, message)
            } else {
                self.exploitStatus = .failed
                self.appendLog("❌ Exploit 失败: \(message)")
                completion(false, message)
            }
        }
    }

    // MARK: - 替换 PAK 文件（对应原始 replace_pak / overwrite_system_file）
    func replacePakFile(config: PakFileConfig,
                        statusCallback: @escaping (String) -> Void,
                        completion: @escaping (Bool, String) -> Void) {

        appendLog("准备替换 PAK: \(config.pakFileName)")
        statusCallback("获取本地 PAK 文件...")

        // Step1: 下载/获取本地 PAK 文件
        PakDownloadManager.shared.getPakFilePath(for: config, progress: { [weak self] msg in
            self?.appendLog(msg)
            statusCallback(msg)
        }) { [weak self] localPath in
            guard let self = self else { return }
            guard let localPath = localPath else {
                completion(false, "获取 PAK 文件失败")
                return
            }

            self.appendLog("PAK 文件就绪: \(localPath)")
            statusCallback("正在使用 Exploit 替换目标文件...")

            // Step2: 动态查找游戏容器路径（对应原始沙盒逃逸后遍历容器）
            var targetPath = config.targetFullPath
            if targetPath.contains("<UUID>") {
                // 动态查找游戏容器 UUID
                if let gameDocs = ExploitRunner.shared.findGameContainer(bundleID: config.gameBundleID) {
                    targetPath = targetPath.replacingOccurrences(of: "<UUID>", with: gameDocs)
                    self.appendLog("动态容器路径: \(targetPath)")
                }
            }

            // Step3: 使用 ExploitRunner 调用真实 Exploit 覆写
            ExploitRunner.shared.replacePak(
                localPath: localPath,
                targetPath: targetPath,
                progress: { [weak self] p, log in
                    self?.appendLog(log)
                    statusCallback(log)
                },
                completion: { [weak self] success, message in
                    guard let self = self else { return }
                    if success {
                        self.appendLog("✅ PAK 替换成功: \(config.pakFileName)")
                        completion(true, "替换成功")
                    } else {
                        self.appendLog("❌ PAK 替换失败: \(message)")
                        completion(false, message)
                    }
                }
            )
        }
    }

    // MARK: - 自动还原定时器（对应原始 autoRestoreTimer）
    func startAutoRestore(interval: TimeInterval = 60) {
        stopAutoRestore()
        autoRestoreCountdown = Int(interval)
        autoRestoreTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.autoRestoreCountdown > 0 {
                self.autoRestoreCountdown -= 1
            } else {
                self.autoRestoreCountdown = Int(interval)
                self.appendLog("[AutoRestore] 触发自动还原...")
                // 批量还原所有已配置的 PAK
                let pairs = self.pakConfigs.map { config -> [String: String] in
                    let backup = PakFileReplacer.backupPak(config.targetFullPath) ?? ""
                    return ["local": backup, "target": config.targetFullPath]
                }.filter { !($0["local"]?.isEmpty ?? true) }

                if !pairs.isEmpty {
                    ExploitRunner.shared.replacePakBatch(
                        pairs: pairs,
                        progress: nil
                    ) { [weak self] ok, msg in
                        self?.appendLog("[AutoRestore] \(msg)")
                    }
                }
            }
        }
        appendLog("[AutoRestore] 已启动，间隔 \(Int(interval))s")
    }

    func stopAutoRestore() {
        autoRestoreTimer?.invalidate()
        autoRestoreTimer = nil
        autoRestoreCountdown = 0
    }

    // MARK: - 注册后台任务（对应原始 BGTask）
    func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.pakreplacertest.autorestore",
            using: nil
        ) { [weak self] task in
            guard let self = self else { task.setTaskCompleted(success: false); return }
            self.appendLog("[BGTask] 后台自动还原触发")
            // 执行后台 PAK 还原
            let pairs = self.pakConfigs.map { config -> [String: String] in
                let backup = PakFileReplacer.backupPak(config.targetFullPath) ?? ""
                return ["local": backup, "target": config.targetFullPath]
            }.filter { !($0["local"]?.isEmpty ?? true) }
            ExploitRunner.shared.replacePakBatch(pairs: pairs, progress: nil) { _, _ in
                task.setTaskCompleted(success: true)
            }
        }
    }

    // MARK: - 退出登录
    func logout() {
        SecureCardStorage.shared.clearToken()
        isVerified = false
        appStatus.isVerified = false
        appendLog("已退出登录")
    }

    // MARK: - 工具方法
    private func showAlertMessage(_ msg: String) {
        alertMessage = msg
        showAlert = true
    }

    func appendLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let time = formatter.string(from: Date())
        DispatchQueue.main.async {
            self.exploitLog.append("[\(time)] \(message)")
            if self.exploitLog.count > 200 {
                self.exploitLog.removeFirst()
            }
        }
    }

    func clearLog() {
        exploitLog.removeAll()
    }
}

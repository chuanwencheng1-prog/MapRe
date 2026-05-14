// MainAppView.swift
// 对应原始 MainAppView - 主功能界面

import SwiftUI

struct MainAppView: View {
    @ObservedObject var viewModel: PakReplacerViewModel
    @ObservedObject var downloadManager = PakDownloadManager.shared
    @State private var selectedConfigIndex: Int = 0
    @State private var showPathEditor: Bool = false
    @State private var showLogPanel: Bool = false
    @State private var isRunning: Bool = false
    @State private var actionStatus: String = ""

    var selectedConfig: Binding<PakFileConfig> {
        $viewModel.pakConfigs[selectedConfigIndex]
    }

    var body: some View {
        ZStack {
            // 主背景
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.06, blue: 0.12),
                    Color(red: 0.04, green: 0.08, blue: 0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {

                    // MARK: - 顶部标题栏
                    headerView

                    // MARK: - 设备 & 状态信息
                    deviceStatusCard

                    // MARK: - PAK 模式选择（对应原始 FeatureItem 列表）
                    pakModeCard

                    // MARK: - 当前选中配置详情
                    configDetailCard

                    // MARK: - 操作按钮区
                    actionButtonsCard

                    // MARK: - 下载进度（对应原始 PakDownloadManager）
                    if downloadManager.isDownloading {
                        downloadProgressCard
                    }

                    // MARK: - 运行日志（对应原始 exploitLog）
                    if showLogPanel {
                        LogView(logs: viewModel.exploitLog) {
                            viewModel.clearLog()
                        }
                        .padding(.horizontal, 16)
                    }

                    Spacer().frame(height: 30)
                }
                .padding(.top, 8)
            }
        }
        .sheet(isPresented: $showPathEditor) {
            PathEditorView(
                config: selectedConfig,
                isPresented: $showPathEditor
            )
        }
        .alert(isPresented: $viewModel.showAlert) {
            Alert(
                title: Text("提示"),
                message: Text(viewModel.alertMessage),
                dismissButton: .default(Text("确定"))
            )
        }
    }

    // MARK: - 顶部标题栏
    private var headerView: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("A全系统内透")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                Text("PAK Replacer Test Tool")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }

            Spacer()

            // 激活状态徽章
            VerifyFeatureBadge(isVerified: viewModel.isVerified)

            // 退出按钮
            Button(action: { viewModel.logout() }) {
                Image(systemName: "person.crop.circle.badge.minus")
                    .font(.system(size: 18))
                    .foregroundColor(.gray)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    // MARK: - 设备 & 状态信息卡
    private var deviceStatusCard: some View {
        WhiteCard {
            VStack(spacing: 10) {
                HStack {
                    Label("设备状态", systemImage: "info.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    ExploitStatusBadge(status: viewModel.exploitStatus)
                }

                CardDivider()

                Group {
                    StatusRow(
                        title: "设备 UDID",
                        value: String(viewModel.appStatus.deviceInfo.udid.prefix(16)) + "...",
                        icon: "iphone"
                    )
                    StatusRow(
                        title: "iOS 版本",
                        value: viewModel.appStatus.deviceInfo.osVersion,
                        icon: "applelogo"
                    )
                    StatusRow(
                        title: "TrollStore",
                        value: viewModel.appStatus.isTrollStoreInstalled ? "已安装" : "未安装",
                        valueColor: viewModel.appStatus.isTrollStoreInstalled ? .green : .orange,
                        icon: "tray.fill"
                    )
                    StatusRow(
                        title: "沙盒状态",
                        value: viewModel.appStatus.sandboxEscaped ? "已逃逸" : "沙盒内",
                        valueColor: viewModel.appStatus.sandboxEscaped ? .green : .gray,
                        icon: "lock.open.fill"
                    )
                    StatusRow(
                        title: "Frida",
                        value: viewModel.appStatus.deviceInfo.hasFrida ? "⚠️ 已检测" : "未检测到",
                        valueColor: viewModel.appStatus.deviceInfo.hasFrida ? .yellow : .gray,
                        icon: "eye.slash.fill"
                    )
                }
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - PAK 模式选择卡
    private var pakModeCard: some View {
        WhiteCard {
            VStack(spacing: 4) {
                HStack {
                    Label("选择模式", systemImage: "square.grid.2x2.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.bottom, 8)

                // 功能列表（对应原始 ForEach + FeatureItem）
                ForEach(Array(viewModel.pakConfigs.enumerated()), id: \.element.id) { idx, config in
                    FeatureItem(
                        mode: config.mode,
                        isSelected: selectedConfigIndex == idx
                    ) {
                        selectedConfigIndex = idx
                        viewModel.selectedMode = config.mode
                    }

                    if idx < viewModel.pakConfigs.count - 1 {
                        CardDivider()
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - 当前选中配置详情
    private var configDetailCard: some View {
        let config = viewModel.pakConfigs[selectedConfigIndex]
        return WhiteCard {
            VStack(spacing: 10) {
                HStack {
                    Label("配置详情", systemImage: "doc.text.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    // 编辑路径按钮（对应原始 showPathPicker）
                    Button(action: { showPathEditor = true }) {
                        Label("编辑路径", systemImage: "pencil")
                            .font(.system(size: 12))
                            .foregroundColor(.blue)
                    }
                }

                CardDivider()

                StatusRow(title: "PAK 文件名", value: config.pakFileName, icon: "doc.fill")
                StatusRow(
                    title: "目标目录",
                    value: shortenPath(config.targetDirectory),
                    icon: "folder.fill"
                )
                StatusRow(
                    title: "下载地址",
                    value: config.downloadURL.isEmpty ? "未配置" : shortenURL(config.downloadURL),
                    valueColor: config.downloadURL.isEmpty ? .red : .gray,
                    icon: "arrow.down.circle.fill"
                )

                // 本地缓存状态
                let cachePath = PakDownloadManager.cacheDirectory.appendingPathComponent(config.pakFileName).path
                let hasCached = FileManager.default.fileExists(atPath: cachePath)
                StatusRow(
                    title: "本地缓存",
                    value: hasCached ? "已缓存" : "无缓存",
                    valueColor: hasCached ? .green : .gray,
                    icon: "externaldrive.fill"
                )
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - 操作按钮区
    private var actionButtonsCard: some View {
        VStack(spacing: 12) {
            // 状态提示
            if !actionStatus.isEmpty {
                Text(actionStatus)
                    .font(.system(size: 12))
                    .foregroundColor(.yellow)
                    .padding(.horizontal, 20)
            }

            HStack(spacing: 12) {
                // Exploit 按钮（对应原始 runExploitWithCompletion）
                Button(action: runExploit) {
                    HStack(spacing: 6) {
                        if viewModel.exploitStatus == .running {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "bolt.fill")
                        }
                        Text("运行 Exploit")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(
                        viewModel.exploitStatus == .success ?
                            Color.green.opacity(0.3) : Color.orange.opacity(0.2)
                    )
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                viewModel.exploitStatus == .success ? Color.green : Color.orange,
                                lineWidth: 1
                            )
                    )
                }
                .disabled(viewModel.exploitStatus == .running)

                // 替换 PAK 按钮（对应原始 replace_pak）
                Button(action: replacePak) {
                    HStack(spacing: 6) {
                        if isRunning && viewModel.exploitStatus != .running {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        Text("替换 PAK")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Color.blue.opacity(0.2))
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.blue, lineWidth: 1)
                    )
                }
                .disabled(isRunning || downloadManager.isDownloading)
            }
            .padding(.horizontal, 16)

            // 工具栏
            HStack(spacing: 16) {
                // 日志按钮
                Button(action: { withAnimation { showLogPanel.toggle() } }) {
                    Label(
                        showLogPanel ? "隐藏日志" : "显示日志",
                        systemImage: showLogPanel ? "eye.slash" : "terminal"
                    )
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                }

                Spacer()

                // 自动还原开关（对应原始 autoRestoreTimer）
                Toggle(isOn: .init(
                    get: { viewModel.autoRestoreCountdown > 0 },
                    set: { on in
                        if on { viewModel.startAutoRestore() }
                        else  { viewModel.stopAutoRestore() }
                    }
                )) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise.circle")
                            .font(.system(size: 12))
                        Text(viewModel.autoRestoreCountdown > 0 ?
                             "自动还原 \(viewModel.autoRestoreCountdown)s" : "自动还原")
                            .font(.system(size: 12))
                    }
                    .foregroundColor(.gray)
                }
                .toggleStyle(SwitchToggleStyle(tint: .blue))
                .scaleEffect(0.85, anchor: .trailing)
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - 下载进度卡
    private var downloadProgressCard: some View {
        WhiteCard {
            VStack(spacing: 10) {
                HStack {
                    Label("下载中", systemImage: "arrow.down.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Button("取消") {
                        downloadManager.cancelDownload()
                    }
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                }
                DownloadProgressBar(
                    progress: downloadManager.downloadProgress,
                    status: downloadManager.downloadStatus,
                    color: viewModel.pakConfigs[selectedConfigIndex].mode.color
                )
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - 动作：运行 Exploit
    private func runExploit() {
        actionStatus = "正在运行 Exploit..."
        viewModel.runExploit { success, message in
            actionStatus = message
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                actionStatus = ""
            }
        }
    }

    // MARK: - 动作：替换 PAK
    private func replacePak() {
        isRunning = true
        actionStatus = "准备替换..."
        let config = viewModel.pakConfigs[selectedConfigIndex]

        viewModel.replacePakFile(config: config, statusCallback: { msg in
            actionStatus = msg
        }) { success, message in
            isRunning = false
            actionStatus = message
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                actionStatus = ""
            }
        }
    }

    // MARK: - 工具函数
    private func shortenPath(_ path: String) -> String {
        if path.count > 40 {
            return "..." + path.suffix(37)
        }
        return path
    }

    private func shortenURL(_ url: String) -> String {
        guard let host = URL(string: url)?.host else { return url }
        return host
    }
}

// 暴露 cacheDirectory 供外部访问
extension PakDownloadManager {
    static var cacheDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let cache = docs.appendingPathComponent("PakCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        return cache
    }
}

struct MainAppView_Previews: PreviewProvider {
    static var previews: some View {
        MainAppView(viewModel: PakReplacerViewModel())
            .preferredColorScheme(.dark)
    }
}

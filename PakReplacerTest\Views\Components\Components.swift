// Components.swift
// UI 组件：WhiteCard / StatusRow / FeatureItem / CardDivider / VerifyFeatureBadge
// 对应原始分析中的 SwiftUI UI 组件

import SwiftUI

// MARK: - WhiteCard（对应原始 WhiteCardV）
struct WhiteCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
            )
    }
}

// MARK: - CardDivider（对应原始 CardDividerV）
struct CardDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.12))
            .frame(height: 1)
            .padding(.horizontal, 4)
    }
}

// MARK: - StatusRow（对应原始 StatusRowV）
struct StatusRow: View {
    let title: String
    let value: String
    var valueColor: Color = .white
    var icon: String = ""

    var body: some View {
        HStack(spacing: 8) {
            if !icon.isEmpty {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
                    .frame(width: 18)
            }
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(.gray)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(valueColor)
        }
    }
}

// MARK: - FeatureItem（对应原始 FeatureItemV）
struct FeatureItem: View {
    let mode: PakMode
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // 图标
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(mode.color.opacity(isSelected ? 0.3 : 0.15))
                        .frame(width: 42, height: 42)
                    Image(systemName: mode.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(isSelected ? mode.color : .gray)
                }

                // 文字
                VStack(alignment: .leading, spacing: 3) {
                    Text(mode.rawValue)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    Text(mode.description)
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
                Spacer()

                // 选中指示
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(mode.color)
                }
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
        .background(
            isSelected ?
                RoundedRectangle(cornerRadius: 12)
                    .fill(mode.color.opacity(0.08)) : nil
        )
    }
}

// MARK: - VerifyFeatureBadge（对应原始 VerifyFeatureBadgeV）
struct VerifyFeatureBadge: View {
    let isVerified: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isVerified ? "checkmark.shield.fill" : "xmark.shield.fill")
                .font(.system(size: 13))
                .foregroundColor(isVerified ? .green : .red)
            Text(isVerified ? "已激活" : "未激活")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isVerified ? .green : .red)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill((isVerified ? Color.green : Color.red).opacity(0.15))
        )
    }
}

// MARK: - ExploitStatusBadge（状态徽章）
struct ExploitStatusBadge: View {
    let status: ExploitStatus

    var body: some View {
        HStack(spacing: 5) {
            if status == .running {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: status.color))
                    .scaleEffect(0.7)
            } else {
                Circle()
                    .fill(status.color)
                    .frame(width: 8, height: 8)
            }
            Text(status.rawValue)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(status.color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(status.color.opacity(0.15))
        )
    }
}

// MARK: - DownloadProgressBar（下载进度条）
struct DownloadProgressBar: View {
    let progress: Double
    let status: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("下载进度")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                Spacer()
                Text(status)
                    .font(.system(size: 12))
                    .foregroundColor(.white)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [color, color.opacity(0.6)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * min(max(progress, 0), 1), height: 8)
                        .animation(.easeInOut(duration: 0.3), value: progress)
                }
            }
            .frame(height: 8)
            Text("\(Int(progress * 100))%")
                .font(.system(size: 11))
                .foregroundColor(.gray)
        }
    }
}

// MARK: - LogView（日志视图，对应原始 exploitLog）
struct LogView: View {
    let logs: [String]
    let onClear: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("运行日志", systemImage: "terminal.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Button(action: onClear) {
                    Text("清除")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.05))

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(logs.enumerated()), id: \.offset) { idx, log in
                            Text(log)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(
                                    log.contains("✅") ? .green :
                                    log.contains("❌") ? .red :
                                    log.contains("⚠️") ? .yellow : .gray
                                )
                                .padding(.horizontal, 12)
                                .padding(.vertical, 1)
                                .id(idx)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .onChange(of: logs.count) { _ in
                    if let last = logs.indices.last {
                        withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
            }
        }
        .background(Color.black.opacity(0.3))
        .cornerRadius(12)
        .frame(height: 160)
    }
}

// MARK: - 路径编辑 Sheet（修改 PAK 目标路径）
struct PathEditorView: View {
    @Binding var config: PakFileConfig
    @Binding var isPresented: Bool

    @State private var editDirectory: String = ""
    @State private var editURL: String = ""
    @State private var editFileName: String = ""

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("PAK 文件名")) {
                    TextField("例: game_patch_cheat2.pak", text: $editFileName)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }

                Section(header: Text("目标目录路径"),
                        footer: Text("修改为你自己 IPA 应用的 PAK 存储目录")) {
                    TextField("/var/mobile/Containers/...", text: $editDirectory)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .font(.system(size: 13, design: .monospaced))
                }

                Section(header: Text("下载地址（URL）"),
                        footer: Text("PAK 文件的下载 URL")) {
                    TextField("https://your-server.com/paks/xxx.pak", text: $editURL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .keyboardType(.URL)
                }

                Section(header: Text("完整目标路径（预览）")) {
                    Text(editDirectory + "/" + editFileName)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("编辑路径配置")
            .navigationBarItems(
                leading: Button("取消") { isPresented = false },
                trailing: Button("保存") {
                    config.pakFileName = editFileName
                    config.targetDirectory = editDirectory
                    config.downloadURL = editURL
                    isPresented = false
                }
                .fontWeight(.semibold)
            )
        }
        .onAppear {
            editDirectory = config.targetDirectory
            editURL       = config.downloadURL
            editFileName  = config.pakFileName
        }
    }
}

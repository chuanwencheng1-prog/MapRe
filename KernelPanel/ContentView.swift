import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var viewModel = PanelViewModel()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 头部卡密卡片
                HeaderCardView(viewModel: viewModel)
                
                // 主内容区域
                MainContentView(viewModel: viewModel)
                
                // 运行日志区域
                LogContainerView(viewModel: viewModel)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .background(Color(red: 0.949, green: 0.953, blue: 0.969))
        .onAppear {
            viewModel.addLog("面板初始化完成，请先输入卡密激活")
        }
    }
}

// MARK: - 头部卡密卡片
struct HeaderCardView: View {
    @ObservedObject var viewModel: PanelViewModel
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                TextField("请输入卡密", text: $viewModel.inputKey)
                    .frame(height: 44)
                    .padding(.horizontal, 14)
                    .background(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(viewModel.inputFocused ? Color(red: 0, green: 0.478, blue: 1) : Color(red: 0.867, green: 0.867, blue: 0.867), lineWidth: 1)
                    )
                    .cornerRadius(12)
                    .font(.system(size: 14))
                    .onTapGesture {
                        viewModel.inputFocused = true
                    }
                
                Button(action: {
                    viewModel.activate()
                }) {
                    Text("激活")
                        .font(.system(size: 14))
                        .frame(width: 80, height: 44)
                        .background(Color(red: 0.941, green: 0.969, blue: 0.941))
                        .foregroundColor(Color(red: 0.204, green: 0.780, blue: 0.349))
                        .cornerRadius(12)
                }
            }
            
            if viewModel.showExpireTips {
                Text("卡密到期时间：2026-12-31")
                    .font(.system(size: 12))
                    .foregroundColor(.black)
                    .transition(.opacity)
            }
        }
        .padding(20)
        .frame(minHeight: 90)
        .background(Color.white)
        .cornerRadius(18)
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 4)
    }
}

// MARK: - 主内容区域
struct MainContentView: View {
    @ObservedObject var viewModel: PanelViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            // 内核按钮组
            HStack(spacing: 12) {
                KernelButton(
                    title: "启动内核读写",
                    isEnabled: viewModel.readBtnEnabled,
                    isFinished: viewModel.readDone,
                    action: { viewModel.startRead() }
                )
                
                KernelButton(
                    title: "初始化内核",
                    isEnabled: viewModel.initBtnEnabled,
                    isFinished: viewModel.initDone,
                    action: { viewModel.startInit() }
                )
            }
            .padding(.bottom, 24)
            
            // 功能按钮组 - 第一行
            HStack(spacing: 10) {
                ContentButton(
                    title: "测试测试(测试)",
                    isEnabled: viewModel.contentBtnsEnabled,
                    action: { viewModel.startDownload(name: "测试测试(测试)") }
                )
                ContentButton(
                    title: "测试测试(测试)",
                    isEnabled: viewModel.contentBtnsEnabled,
                    action: { viewModel.startDownload(name: "测试测试(测试)") }
                )
                ContentButton(
                    title: "测试测试(测试)",
                    isEnabled: viewModel.contentBtnsEnabled,
                    action: { viewModel.startDownload(name: "测试测试(测试)") }
                )
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 16)
            
            // 功能按钮组 - 第二行
            HStack(spacing: 10) {
                ContentButton(
                    title: "新增按钮1",
                    isEnabled: viewModel.contentBtnsEnabled,
                    action: { viewModel.startDownload(name: "新增按钮1") }
                )
                ContentButton(
                    title: "新增按钮2",
                    isEnabled: viewModel.contentBtnsEnabled,
                    action: { viewModel.startDownload(name: "新增按钮2") }
                )
                ContentButton(
                    title: "新增按钮3",
                    isEnabled: viewModel.contentBtnsEnabled,
                    action: { viewModel.startDownload(name: "新增按钮3") }
                )
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 24)
            
            // 启动按钮
            Button(action: {
                viewModel.addLog("点击启动按钮")
            }) {
                Text("启动")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 120, height: 44)
                    .background(Color(red: 0.941, green: 0.969, blue: 0.941))
                    .foregroundColor(Color(red: 0.204, green: 0.780, blue: 0.349))
                    .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.startBtnEnabled)
        }
        .padding(20)
        .background(Color.white)
        .cornerRadius(18)
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 4)
    }
}

// MARK: - 内核按钮
struct KernelButton: View {
    let title: String
    let isEnabled: Bool
    let isFinished: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(buttonBackground)
                .foregroundColor(buttonForeground)
                .cornerRadius(14)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isFinished)
    }
    
    private var buttonBackground: Color {
        if isFinished {
            return Color(red: 0.914, green: 0.914, blue: 0.922)
        }
        return Color(red: 0.941, green: 0.969, blue: 0.941)
    }
    
    private var buttonForeground: Color {
        if isFinished {
            return Color(red: 0.557, green: 0.557, blue: 0.576)
        }
        return Color(red: 0.204, green: 0.780, blue: 0.349)
    }
}

// MARK: - 内容按钮
struct ContentButton: View {
    let title: String
    let isEnabled: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color(red: 0.941, green: 0.969, blue: 0.941))
                .foregroundColor(Color(red: 0.204, green: 0.780, blue: 0.349))
                .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

// MARK: - 日志容器
struct LogContainerView: View {
    @ObservedObject var viewModel: PanelViewModel
    @State private var blinkOpacity: Double = 0.4
    
    var body: some View {
        VStack(spacing: 0) {
            // 日志标题
            HStack {
                Text("运行日志")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color(red: 0.173, green: 0.173, blue: 0.180))
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .overlay(
                Rectangle()
                    .fill(Color(red: 0, green: 0.478, blue: 1))
                    .frame(height: 1)
                    .opacity(blinkOpacity)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                            blinkOpacity = 1.0
                        }
                    },
                alignment: .bottom
            )
            
            // 日志内容 - overflow:hidden 禁止手动滑动，仅代码自动滚动
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(viewModel.logs) { log in
                            Text(log.text)
                                .font(.system(size: 13))
                                .foregroundColor(.black)
                                .lineSpacing(1.8)
                                .id(log.id)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .frame(height: 200)
                .allowsHitTesting(false) // 禁止用户触摸滚动（对应HTML的overflow:hidden）
                .onChange(of: viewModel.logs.count) { _ in
                    if let lastLog = viewModel.logs.last {
                        withAnimation {
                            proxy.scrollTo(lastLog.id, anchor: .bottom)
                        }
                    }
                }
            }
            .clipped() // 裁剪溢出内容（对应overflow:hidden）
        }
        .background(Color(red: 0.973, green: 0.976, blue: 0.984))
        .cornerRadius(18)
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 4)
    }
}

// MARK: - 日志模型
struct LogEntry: Identifiable {
    let id = UUID()
    var text: String
}

// MARK: - ViewModel
class PanelViewModel: ObservableObject {
    @Published var inputKey: String = ""
    @Published var inputFocused: Bool = false
    @Published var showExpireTips: Bool = false
    @Published var readBtnEnabled: Bool = false
    @Published var initBtnEnabled: Bool = false
    @Published var readDone: Bool = false
    @Published var initDone: Bool = false
    @Published var contentBtnsEnabled: Bool = false
    @Published var startBtnEnabled: Bool = false
    @Published var logs: [LogEntry] = []
    
    private let correctKey = "1"
    
    func getNowTime() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }
    
    func getDeviceInfo() -> (device: String, iosVer: String, screen: String) {
        var device = "iPhone"
        let iosVer = "\(UIDevice.current.systemVersion)"
        let screen = "\(Int(UIScreen.main.bounds.width)) × \(Int(UIScreen.main.bounds.height))"
        
        if UIDevice.current.userInterfaceIdiom == .pad {
            device = "iPad"
        }
        
        return (device, iosVer, screen)
    }
    
    func addLog(_ text: String) {
        let time = getNowTime()
        let entry = LogEntry(text: "[\(time)] \(text)")
        DispatchQueue.main.async {
            self.logs.append(entry)
        }
    }
    
    func updateLastLog(_ text: String) {
        let time = getNowTime()
        DispatchQueue.main.async {
            if !self.logs.isEmpty {
                self.logs[self.logs.count - 1].text = "[\(time)] \(text)"
            }
        }
    }
    
    func activate() {
        let key = inputKey.trimmingCharacters(in: .whitespaces)
        if key == correctKey {
            withAnimation {
                showExpireTips = true
            }
            addLog("卡密验证通过，激活成功")
            let info = getDeviceInfo()
            addLog("设备类型：\(info.device)")
            addLog("iOS 系统版本：\(info.iosVer)")
            addLog("屏幕分辨率：\(info.screen)")
            readBtnEnabled = true
            initBtnEnabled = true
        } else {
            withAnimation {
                showExpireTips = false
            }
            addLog("卡密错误，所有功能无法使用！")
            readBtnEnabled = false
            initBtnEnabled = false
            contentBtnsEnabled = false
            startBtnEnabled = false
        }
    }
    
    func checkUnlock() {
        if readDone && initDone {
            contentBtnsEnabled = true
            startBtnEnabled = true
            addLog("内核服务全部就绪，所有功能已解锁")
        }
    }
    
    func startRead() {
        addLog("收到指令，准备启动读写服务")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.addLog("加载读写驱动模块")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            self.addLog("权限校验通过")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            self.addLog("内核读写通道已完全开启")
            self.readDone = true
            self.readBtnEnabled = false
            self.checkUnlock()
        }
    }
    
    func startInit() {
        addLog("即将执行内核重置操作")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.addLog("清空临时缓存数据")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            self.addLog("内核参数恢复默认值")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            self.addLog("内核初始化全部完成")
            self.initDone = true
            self.initBtnEnabled = false
            self.checkUnlock()
        }
    }
    
    func startDownload(name: String) {
        addLog("\(name) 开始下载")
        let progressLog = LogEntry(text: "[\(getNowTime())] [进度]  0%")
        logs.append(progressLog)
        let progressIndex = logs.count - 1
        
        var progress = 0
        let total = 20
        
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            progress += 1
            var bar = ""
            for _ in 0..<progress {
                bar += ">"
            }
            let percent = Int((Double(progress) / Double(total)) * 100)
            let time = self.getNowTime()
            
            DispatchQueue.main.async {
                if progressIndex < self.logs.count {
                    self.logs[progressIndex].text = "[\(time)] [进度] \(bar) \(percent)%"
                }
            }
            
            if progress >= total {
                timer.invalidate()
                self.addLog("\(name) 下载完成")
            }
        }
    }
}

#Preview {
    ContentView()
}

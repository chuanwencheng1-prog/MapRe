//
//  ContentView.swift
//  KernelPanel
//

import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var mgr = KernelManager.shared
    @ObservedObject private var logger = globallogger
    
    var body: some View {
        NavigationStack {
            List {
                // 警告区域
                AlertsSection
                
                // 内核读写区域
                KRWSection
                
                // 操作区域
                ActionsSection
                
                // 调试信息区域
                DebugSection
                
                // 日志区域
                LogsSection
            }
            .navigationTitle("内核管理")
        }
        .onAppear {
            globallogger.capture()
            init_offsets()
            offsets_init()
            mgr.hasOffsets = emergencyfixfunctiontobereplacedlateronquestionmark()
        }
    }
    
    // MARK: - 警告区域
    private var AlertsSection: some View {
        Section {
            if !mgr.hasOffsets {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("未找到偏移量!")
                            .font(.headline)
                        Text("内核缓存偏移量缺失。请点击"运行漏洞利用"然后获取偏移量。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
    
    // MARK: - 内核读写区域
    private var KRWSection: some View {
        Section {
            // 运行漏洞利用按钮
            LabeledContent(content: {
                if mgr.dsready {
                    Image(systemName: "checkmark.circle")
                        .foregroundColor(.green)
                } else if mgr.dsrunning {
                    HStack {
                        Text("\(Int(mgr.dsprogress * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        ProgressView()
                    }
                } else if mgr.dsattempted && mgr.dsfailed {
                    Image(systemName: "xmark.circle")
                        .foregroundColor(.red)
                }
            }) {
                Button("运行漏洞利用", action: {
                    offsets_init()
                    mgr.run()
                })
                .disabled(mgr.dsready || mgr.dsrunning || mgr.isdebugged())
            }
            
            // 初始化系统按钮
            LabeledContent(content: {
                if mgr.vfsready && mgr.sbxready {
                    Image(systemName: "checkmark.circle")
                        .foregroundColor(.green)
                } else if mgr.vfsrunning || mgr.sbxrunning {
                    HStack {
                        Text("运行中...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        ProgressView()
                    }
                } else if (mgr.vfsattempted && mgr.vfsfailed) || (mgr.sbxattempted && mgr.sbxfailed) {
                    Image(systemName: "xmark.circle")
                        .foregroundColor(.red)
                }
            }) {
                Button("初始化系统", action: {
                    mgr.vfsinit()
                    mgr.sbxescape()
                })
                .disabled(!mgr.hasOffsets || !mgr.dsready || mgr.vfsrunning || mgr.sbxrunning || (mgr.vfsready && mgr.sbxready))
            }
        } header: {
            HStack(spacing: 6) {
                Image(systemName: "externaldrive")
                Text("内核读写")
            }
            .font(.caption)
            .textCase(.none)
        } footer: {
            if mgr.isdebugged() {
                Text("调试器已连接时不可用。")
                    .foregroundColor(.orange)
            }
        }
    }
    
    // MARK: - 操作区域
    private var ActionsSection: some View {
        Section(header: HStack(spacing: 6) {
            Image(systemName: "wrench.and.screwdriver")
            Text("操作")
        }.font(.caption).textCase(.none)) {
            Button("重新启动SpringBoard", action: {
                // respring
            })
            .disabled(!mgr.dsready)
            
            Button("内核恐慌!", action: {
                guard mgr.dsready else { return }
                globallogger.log("triggering panic")
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    let kernbase = ds_get_kernel_base()
                    globallogger.log("writing to read-only memory at kernel base")
                    ds_kwrite64(kernbase, 0xDEADBEEF)
                }
            })
            .disabled(!mgr.dsready)
            .foregroundColor(.red)
        }
    }
    
    // MARK: - 调试信息区域
    private var DebugSection: some View {
        Group {
            if mgr.dsready {
                Section(header: HStack(spacing: 6) {
                    Image(systemName: "ant")
                    Text("调试信息")
                }.font(.caption).textCase(.none)) {
                    LabeledContent("kernel_base") {
                        Text(String(format: "0x%llx", mgr.kernbase))
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    LabeledContent("kernel_slide") {
                        Text(String(format: "0x%llx", mgr.kernslide))
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
    
    // MARK: - 日志区域
    private var LogsSection: some View {
        Section(header: HStack(spacing: 6) {
            Image(systemName: "terminal")
            Text("运行日志")
        }.font(.caption).textCase(.none)) {
            ScrollView {
                let combined = logger.logs.joined(separator: "\n")
                Text(combined)
                    .font(.system(size: 12, design: .monospaced))
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .onTapGesture {
                        UIPasteboard.general.string = combined
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
            }
            .frame(height: 200)
            
            Button("复制全部日志") {
                UIPasteboard.general.string = logger.logs.joined(separator: "\n\n")
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
            
            Button("清除日志") {
                logger.clear()
            }
            .foregroundColor(.red)
        }
    }
}

#Preview {
    ContentView()
}

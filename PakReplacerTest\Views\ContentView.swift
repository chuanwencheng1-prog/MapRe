// ContentView.swift
// 对应原始 ContentView - 顶层路由视图

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = PakReplacerViewModel()

    var body: some View {
        Group {
            if viewModel.isVerified {
                // 已验证：进入主功能界面
                MainAppView(viewModel: viewModel)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            } else {
                // 未验证：显示验证界面
                VerificationView(viewModel: viewModel)
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
            }
        }
        .animation(.easeInOut(duration: 0.35), value: viewModel.isVerified)
        .preferredColorScheme(.dark)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

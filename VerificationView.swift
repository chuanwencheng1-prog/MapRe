// VerificationView.swift
// 对应原始 VerificationView - 卡密验证界面

import SwiftUI

struct VerificationView: View {
    @ObservedObject var viewModel: PakReplacerViewModel
    @State private var cardCode: String = ""
    @State private var isVerifying: Bool = false
    @State private var showWave: Bool = false

    var body: some View {
        ZStack {
            // 背景渐变（对应原始深色主题）
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.06, blue: 0.12),
                    Color(red: 0.04, green: 0.08, blue: 0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // 背景装饰圆
            Circle()
                .fill(Color.blue.opacity(0.08))
                .frame(width: 300, height: 300)
                .offset(x: -80, y: -200)
                .blur(radius: 40)

            Circle()
                .fill(Color.purple.opacity(0.08))
                .frame(width: 250, height: 250)
                .offset(x: 100, y: 250)
                .blur(radius: 40)

            VStack(spacing: 0) {

                Spacer()

                // MARK: - 顶部 Logo 区域
                VStack(spacing: 16) {
                    // App 图标区域（VerifyWaveShape 对应）
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [Color.blue.opacity(0.4), Color.blue.opacity(0.05)],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 60
                                )
                            )
                            .frame(width: 100, height: 100)
                            .scaleEffect(showWave ? 1.15 : 1.0)
                            .animation(
                                Animation.easeInOut(duration: 2.0).repeatForever(autoreverses: true),
                                value: showWave
                            )

                        Image(systemName: "eye.fill")
                            .font(.system(size: 38, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .onAppear { showWave = true }

                    Text("A全系统内透")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)

                    Text("请输入卡密以激活")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                }

                Spacer().frame(height: 50)

                // MARK: - 卡密输入区域
                WhiteCard {
                    VStack(spacing: 20) {

                        // 设备信息
                        VStack(spacing: 10) {
                            StatusRow(
                                title: "设备 ID",
                                value: String(SecureCardStorage.shared.cachedDeviceId().prefix(18)) + "...",
                                icon: "iphone"
                            )
                            CardDivider()
                            StatusRow(
                                title: "iOS 版本",
                                value: UIDevice.current.systemVersion,
                                icon: "applelogo"
                            )
                            CardDivider()
                            StatusRow(
                                title: "设备型号",
                                value: UIDevice.current.model,
                                icon: "cpu"
                            )
                        }

                        // 输入框
                        VStack(alignment: .leading, spacing: 8) {
                            Text("激活码")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)

                            HStack {
                                Image(systemName: "key.fill")
                                    .foregroundColor(.gray)
                                    .font(.system(size: 14))
                                TextField("请输入激活码", text: $cardCode)
                                    .foregroundColor(.white)
                                    .autocapitalization(.allCharacters)
                                    .disableAutocorrection(true)
                                    .font(.system(size: 15, design: .monospaced))
                            }
                            .padding(12)
                            .background(Color.white.opacity(0.07))
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.blue.opacity(0.4), lineWidth: 1)
                            )
                        }

                        // 验证按钮
                        Button(action: performVerify) {
                            HStack(spacing: 8) {
                                if isVerifying {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "shield.checkered")
                                }
                                Text(isVerifying ? "验证中..." : "立即激活")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(
                                LinearGradient(
                                    colors: [Color.blue, Color.blue.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .disabled(isVerifying || cardCode.isEmpty)
                        .opacity((isVerifying || cardCode.isEmpty) ? 0.6 : 1.0)
                    }
                }
                .padding(.horizontal, 24)

                Spacer().frame(height: 30)

                // 版本信息
                Text("PakReplacerTest v1.0  •  仅用于安全测试")
                    .font(.system(size: 11))
                    .foregroundColor(Color.white.opacity(0.3))

                Spacer()
            }
        }
        .alert(isPresented: $viewModel.showAlert) {
            Alert(
                title: Text("提示"),
                message: Text(viewModel.alertMessage),
                dismissButton: .default(Text("确定"))
            )
        }
    }

    private func performVerify() {
        isVerifying = true
        viewModel.verifyCardCode(cardCode) { [self] in
            isVerifying = false
        }
    }
}

// 添加带回调的 verifyCardCode 包装
extension PakReplacerViewModel {
    func verifyCardCode(_ code: String, completion: @escaping () -> Void) {
        let deviceId = SecureCardStorage.shared.cachedDeviceId()
        TXNHVerifyAPI.shared.verifyCardCode(code, deviceId: deviceId) { [weak self] result in
            guard let self = self else { completion(); return }
            if result.success {
                self.isVerified = true
                self.appStatus.isVerified = true
                self.appendLog("✅ 验证成功")
            } else {
                self.showAlert = true
                self.alertMessage = result.message
                self.appendLog("❌ 验证失败: \(result.message)")
            }
            completion()
        }
    }
}

import UIKit

struct VerificationView_Previews: PreviewProvider {
    static var previews: some View {
        VerificationView(viewModel: PakReplacerViewModel())
            .preferredColorScheme(.dark)
    }
}

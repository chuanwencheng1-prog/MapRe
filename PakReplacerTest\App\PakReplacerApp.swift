// PakReplacerApp.swift
// 对应原始 PakReplacerApp - App 入口点

import SwiftUI
import BackgroundTasks

@main
struct PakReplacerApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// MARK: - AppDelegate（处理后台任务注册）
class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        // 注册后台任务（对应原始 BGTaskSchedulerPermittedIdentifiers）
        registerBackgroundTasks()

        // 配置验证 API（对应原始 TXNHVerifyAPI 配置）
        // ✅ TODO: 修改为你自己的服务器地址和 AppKey
        TXNHVerifyAPI.shared.configure(
            baseURL: VerifyAPIConfig.baseURL,
            appKey:  VerifyAPIConfig.appKey
        )

        return true
    }

    // MARK: - 注册后台任务（对应原始 com.pakreplacer.autorestore）
    private func registerBackgroundTasks() {

        // 后台刷新任务
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.pakreplacertest.autorestore",
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            refreshTask.expirationHandler = { refreshTask.setTaskCompleted(success: false) }

            // ✅ TODO: 在此执行后台 PAK 还原逻辑
            // 调度下次后台刷新
            Self.scheduleBackgroundRefresh()
            refreshTask.setTaskCompleted(success: true)
        }

        // 后台处理任务
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.pakreplacertest.autorestore.processing",
            using: nil
        ) { task in
            guard let processingTask = task as? BGProcessingTask else { return }
            processingTask.expirationHandler = { processingTask.setTaskCompleted(success: false) }

            // ✅ TODO: 在此执行后台处理逻辑
            processingTask.setTaskCompleted(success: true)
        }
    }

    // MARK: - 调度后台刷新
    static func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(
            identifier: "com.pakreplacertest.autorestore"
        )
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60) // 60秒后
        try? BGTaskScheduler.shared.submit(request)
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        AppDelegate.scheduleBackgroundRefresh()
    }
}

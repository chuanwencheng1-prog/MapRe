// Models.swift
// PakReplacerTest - 用于测试自己IPA的工具

import Foundation
import SwiftUI

// MARK: - PAK 模式枚举（对应原始 PakMode）
enum PakMode: String, CaseIterable, Identifiable {
    case cheat   = "透视模式"
    case skin    = "皮肤模式"
    case map     = "地图模式"
    case custom  = "自定义"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .cheat:  return "eye.fill"
        case .skin:   return "paintbrush.fill"
        case .map:    return "map.fill"
        case .custom: return "folder.fill"
        }
    }

    var color: Color {
        switch self {
        case .cheat:  return .red
        case .skin:   return .purple
        case .map:    return .blue
        case .custom: return .orange
        }
    }

    var description: String {
        switch self {
        case .cheat:  return "替换游戏透视相关 PAK 文件"
        case .skin:   return "替换游戏皮肤相关 PAK 文件"
        case .map:    return "替换游戏地图相关 PAK 文件"
        case .custom: return "自定义 PAK 文件路径"
        }
    }
}

// MARK: - CheatSub 模式（对应原始 CheatSubMode）
enum CheatSubMode: String, CaseIterable, Identifiable {
    case full    = "全图内透"
    case range   = "范围内透"
    case skin1   = "皮肤包 A"
    case skin2   = "皮肤包 B"
    case custom  = "自定义"

    var id: String { rawValue }
}

// MARK: - PAK 文件配置（对应原始分析中的 PAK 路径）
struct PakFileConfig: Identifiable {
    let id = UUID()
    var name: String              // 显示名
    var pakFileName: String       // PAK 文件名
    var targetDirectory: String   // 目标目录（可修改）
    var downloadURL: String       // 下载地址（可修改）
    var mode: PakMode
    var gameBundleID: String = "" // 目标游戏 BundleID（用于动态查找容器）

    // 完整目标路径
    var targetFullPath: String {
        return targetDirectory + "/" + pakFileName
    }

    // ✅ 预设配置 - 用户可在此修改自己的 IPA 路径
    static let defaultConfigs: [PakFileConfig] = [
        PakFileConfig(
            name: "透视补丁",
            pakFileName: "game_patch_cheat2.pak",
            // TODO: 修改为你自己的 IPA 应用 PAK 目录路径
            targetDirectory: "/var/mobile/Containers/Data/Application/YOUR_APP_UUID/Documents/YourGame/Saved/Paks",
            downloadURL: "https://your-server.com/paks/game_patch_cheat2.pak",
            mode: .cheat
        ),
        PakFileConfig(
            name: "皮肤包",
            pakFileName: "game_patch_skin.pak",
            targetDirectory: "/var/mobile/Containers/Data/Application/YOUR_APP_UUID/Documents/YourGame/Saved/Paks",
            downloadURL: "https://your-server.com/paks/game_patch_skin.pak",
            mode: .skin
        ),
        PakFileConfig(
            name: "地图补丁",
            pakFileName: "map_lobby_range.pak",
            targetDirectory: "/var/mobile/Containers/Data/Application/YOUR_APP_UUID/Documents/YourGame/Saved/Paks",
            downloadURL: "https://your-server.com/paks/map_lobby_range.pak",
            mode: .map
        ),
        PakFileConfig(
            name: "自定义 PAK",
            pakFileName: "custom.pak",
            targetDirectory: "/var/mobile/Containers/Data/Application/YOUR_APP_UUID/Documents/YourGame/Saved/Paks",
            downloadURL: "https://your-server.com/paks/custom.pak",
            mode: .custom
        ),
    ]
}

// MARK: - 验证结果（对应原始 TXNHVerifyResult）
struct VerifyResult {
    var success: Bool
    var message: String
    var token: String?
    var expireAt: TimeInterval?

    static let failed = VerifyResult(success: false, message: "验证失败", token: nil, expireAt: nil)
}

// MARK: - 漏洞状态（对应原始 Exploit 模块）
enum ExploitStatus: String {
    case idle      = "就绪"
    case running   = "运行中"
    case success   = "成功"
    case failed    = "失败"
    case unsupported = "不支持"

    var color: Color {
        switch self {
        case .idle:        return .gray
        case .running:     return .yellow
        case .success:     return .green
        case .failed:      return .red
        case .unsupported: return .orange
        }
    }
}

// MARK: - App 运行状态
struct AppStatus {
    var isVerified: Bool = false
    var isTrollStoreInstalled: Bool = false
    var exploitStatus: ExploitStatus = .idle
    var sandboxEscaped: Bool = false
    var currentPakMode: PakMode? = nil
    var deviceInfo: DeviceInfo = DeviceInfo()
}

// MARK: - 设备信息
struct DeviceInfo {
    var udid: String = UIDevice.current.identifierForVendor?.uuidString ?? "Unknown"
    var osVersion: String = UIDevice.current.systemVersion
    var deviceModel: String = UIDevice.current.model
    var isJailbroken: Bool = false
    var hasTrollStore: Bool = false
    var hasFrida: Bool = false
    var hasMobileSubstrate: Bool = false
}

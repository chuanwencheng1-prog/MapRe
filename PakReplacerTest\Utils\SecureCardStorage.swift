// SecureCardStorage.swift
// 对应原始 SecureCardStorage 模块 - 安全存储卡密 Token

import Foundation
import Security

class SecureCardStorage {

    static let shared = SecureCardStorage()
    private init() {}

    private let tokenKey    = "com.pakreplacertest.verify_token"
    private let expireKey   = "com.pakreplacertest.expire_at"
    private let cardCodeKey = "com.pakreplacertest.card_code"

    // MARK: - 保存 Token（使用 Keychain）
    func saveVerifyToken(_ token: String) {
        let data = token.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: tokenKey,
            kSecValueData as String:   data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    // MARK: - 读取 Token
    func loadVerifyToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: tokenKey,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }
        return token
    }

    // MARK: - 删除 Token（退出登录）
    func clearToken() {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: tokenKey
        ]
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: expireKey)
        UserDefaults.standard.removeObject(forKey: cardCodeKey)
    }

    // MARK: - 保存过期时间
    func saveExpireAt(_ timestamp: TimeInterval) {
        UserDefaults.standard.set(timestamp, forKey: expireKey)
    }

    func loadExpireAt() -> TimeInterval? {
        let val = UserDefaults.standard.double(forKey: expireKey)
        return val > 0 ? val : nil
    }

    // MARK: - 是否已激活且未过期
    var isActivated: Bool {
        guard let token = loadVerifyToken(), !token.isEmpty else { return false }
        if let expireAt = loadExpireAt() {
            return Date().timeIntervalSince1970 < expireAt
        }
        return true
    }

    // MARK: - 缓存 DeviceID
    func cachedDeviceId() -> String {
        let key = "com.pakreplacertest.device_id"
        if let cached = UserDefaults.standard.string(forKey: key) {
            return cached
        }
        let newId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        UserDefaults.standard.set(newId, forKey: key)
        return newId
    }
}

// UIDevice import
import UIKit

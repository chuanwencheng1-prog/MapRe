// TXNHVerifyAPI.swift
// 对应原始 TXNHVerifyAPI.mm 模块 - 卡密验证 API
// ✅ 修改 baseURL 为你自己的服务器地址

import Foundation

// MARK: - 验证API配置（对应原始 setBaseURL/setAppKey/setAesKey）
struct VerifyAPIConfig {
    // ✅ TODO: 修改为你自己的服务器地址
    static var baseURL: String = "https://your-verify-server.com"
    static var appKey: String  = "your_app_key"
    static var aesKey: String  = "your_aes_key"
    static var xorKey: String  = "your_xor_key"
}

// MARK: - TXNHVerifyAPI（对应原始 TXNHVerifyAPI）
class TXNHVerifyAPI: NSObject {

    static let shared = TXNHVerifyAPI()
    private override init() {}

    private var session: URLSession?

    // MARK: - 配置 API（对应原始 setBaseURL/setAppKey）
    func configure(baseURL: String, appKey: String) {
        VerifyAPIConfig.baseURL = baseURL
        VerifyAPIConfig.appKey  = appKey
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    // MARK: - 验证卡密（对应原始 verifyCardCode:completion:）
    func verifyCardCode(_ cardCode: String,
                        deviceId: String,
                        completion: @escaping (VerifyResult) -> Void) {

        guard let url = URL(string: VerifyAPIConfig.baseURL + "/api/verify.php") else {
            completion(VerifyResult(success: false, message: "服务器地址无效", token: nil, expireAt: nil))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "card_code":  cardCode,
            "device_id":  deviceId,
            "app_key":    VerifyAPIConfig.appKey,
            "timestamp":  Int(Date().timeIntervalSince1970),
            "os_version": UIDevice.current.systemVersion,
            "device":     UIDevice.current.model
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            completion(.failed)
            return
        }
        request.httpBody = bodyData

        let task = (session ?? URLSession.shared).dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(VerifyResult(success: false, message: error.localizedDescription, token: nil, expireAt: nil))
                    return
                }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    completion(VerifyResult(success: false, message: "服务器响应异常", token: nil, expireAt: nil))
                    return
                }

                let success   = (json["code"] as? Int) == 200
                let message   = json["msg"] as? String ?? (success ? "验证成功" : "验证失败")
                let token     = json["token"] as? String
                let expireAt  = json["expire_at"] as? TimeInterval

                let result = VerifyResult(success: success, message: message, token: token, expireAt: expireAt)

                // 成功则存储 Token
                if success, let token = token {
                    SecureCardStorage.shared.saveVerifyToken(token)
                    if let expireAt = expireAt {
                        SecureCardStorage.shared.saveExpireAt(expireAt)
                    }
                }
                completion(result)
            }
        }
        task.resume()
    }

    // MARK: - 上报设备信息（对应原始 /api/report.php）
    func reportDevice(deviceId: String, ipInfo: [String: Any]? = nil) {
        guard let url = URL(string: VerifyAPIConfig.baseURL + "/api/report.php") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "device_id":  deviceId,
            "os_version": UIDevice.current.systemVersion,
            "device":     UIDevice.current.model,
            "timestamp":  Int(Date().timeIntervalSince1970)
        ]
        if let ip = ipInfo {
            body.merge(ip) { _, new in new }
        }

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        (session ?? URLSession.shared).dataTask(with: request).resume()
    }

    // MARK: - 获取 IP 地理信息（对应原始 ip-api.com 调用）
    func fetchIPGeoInfo(completion: @escaping ([String: Any]?) -> Void) {
        guard let url = URL(string: "http://ip-api.com/json/?lang=zh-CN&fields=country,regionName,city,status") else {
            completion(nil); return
        }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(nil); return
            }
            completion(json)
        }.resume()
    }
}

// MARK: - URLSession 证书锁定（对应原始 SSL Pinning）
extension TXNHVerifyAPI: URLSessionDelegate {
    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // ✅ TODO: 在此实现你自己的证书锁定逻辑
        // 示例：直接信任（测试用，生产环境应验证证书）
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let serverTrust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

import UIKit

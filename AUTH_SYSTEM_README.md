# 卡密授权系统 · 部署与使用指南

为 PersonalCenterUI（iOS dylib）配套的 **完整卡密授权方案**：
iOS 端弹窗激活 + RSA 防破解 + PHP 后台自助安装 + 卡密/设备/到期下线全套管理。

---

## 一、目录结构

```
.
├── iOS 端（Theos tweak）
│   ├── PCAuthManager.h/.m     ← 新增：授权管理（设备指纹/RSA验签/心跳）
│   ├── PCAuthPopView.h/.m     ← 新增：卡密激活弹窗
│   ├── Tweak.xm               ← 改动：注入入口加入授权门禁
│   ├── Makefile               ← 改动：加入两个新文件 + Security.framework
│   └── （原有 PCMainViewController、PCDownloadPopView、PCPakDownloader 等不变）
│
└── server/                    ← 新增：PHP 卡密授权系统
    ├── install.php            安装向导（4 步）
    ├── index.php              入口重定向
    ├── api.php                iOS 对接接口（activate / verify）
    ├── admin/                 管理后台
    │   ├── login.php / logout.php
    │   ├── dashboard.php      仪表盘（卡片统计 + 7天趋势）
    │   ├── cards.php          卡密管理（筛选/批量禁用/延长/删除/点击复制）
    │   ├── generate.php       批量生成（小时/天/周/月/年/永久）
    │   ├── devices.php        设备管理（踢下线/解绑/封禁）
    │   ├── logs.php           日志
    │   └── settings.php       系统设置 + RSA 公钥查看
    ├── includes/              核心库
    │   ├── db.php / auth.php / rsa.php / functions.php
    │   ├── header.php / footer.php
    │   └── config.php         （由安装向导自动生成）
    ├── assets/                前端静态资源
    │   ├── admin.css
    │   └── admin.js
    ├── keys/                  RSA 密钥（安装向导自动生成，勿泄露）
    │   ├── private.pem  ← 服务器私钥（保密）
    │   └── public.pem   ← 公钥（贴到 iOS）
    └── data/                  运行时数据（install.lock）
```

---

## 二、服务端部署（5 分钟）

### 1. 环境要求
- PHP ≥ 7.2（建议 8.x）、MySQL ≥ 5.7 / MariaDB
- PHP 扩展：`pdo_mysql`、`openssl`、`json`
- Web 服务器：Apache / Nginx（建议上 HTTPS）

### 2. 上传并安装
1. 将整个 `server/` 目录上传到网站，例如：`https://your.domain.com/pc_auth/`
2. 保证以下目录可写（755 即可）：`data/`、`includes/`、`keys/`
3. 浏览器访问：`https://your.domain.com/pc_auth/install.php`
4. 按 4 步向导填数据库/管理员账号/APP_ID → 自动建表 + 生成 RSA 2048 密钥对
5. 安装完成页会展示 **公钥 PEM 全文**，整段复制待会儿粘贴到 iOS
6. 出于安全，安装完成后建议改名或删除 `install.php`

### 3. Nginx 用户注意
`.htaccess` 仅对 Apache 生效。Nginx 请在 server 块加：
```nginx
location ~* \.(pem|lock)$ { deny all; }
location /pc_auth/keys/    { deny all; }
location /pc_auth/data/    { deny all; }
location /pc_auth/includes/ { deny all; }
```

---

## 三、iOS 端配置（3 项必改）

打开 [`PCAuthManager.m`](./PCAuthManager.m) 顶部"必改配置区"：

```objc
static NSString *const kPCAuthServerBase = @"https://your.domain.com/pc_auth";    // ① 改
static NSString *const kPCAuthAppID      = @"pcui_default";                       // ② 必须与后台一致
static NSString *const kPCAuthPubKeyPEM  = @""
"-----BEGIN PUBLIC KEY-----\n"
"...安装向导返回的公钥粘贴到这里（保留每行 \\n）...\n"
"-----END PUBLIC KEY-----\n";                                                     // ③ 贴公钥
```

然后用 Theos 正常编译（`make package` / 云编译）。

---

## 四、核心机制

### 4.1 设备指纹（一机一码）
- `identifierForVendor + 机型 + 设备名 + Bundle` 拼接后 SHA256 得 64 字节 hex
- 首次计算即写入 **Keychain**（`kSecAttrService = com.personalcenterui.auth`），
  App 卸载重装、甚至部分系统刷机仍可恢复，避免刷机绕过
- 每张卡密首次激活时被绑定该 `device_id`，后续任何其它设备拿同一卡密激活均返回 `1004 卡密已绑定其它设备`

### 4.2 RSA 防破解
- 服务端安装时生成 RSA-2048 密钥对，私钥留 `keys/private.pem`
- iOS 硬编码 **公钥**。每次 `activate` / `verify` 请求后，服务器会对
  `app_id|device_id|card|expires_at` 做 SHA256WithRSA 签名返回 `sign`
- iOS 用内置公钥 `SecKeyVerifySignature` 验签，签名不对 → 判定中间人攻击（`PCAuthStatusSignatureBad`）
- 中间人即使全流量换包，也无法伪造签名

### 4.3 心跳到期下线
- 主界面弹出后，`PCAuthManager startHeartbeatWithInterval:300` 每 5 分钟：
  1. 本地到期时间 ≤ 当前 → 立即弹"授权失效"警告
  2. 否则向服务器发 `verify`；若返回 `1002/1003/1004` → 清缓存并弹警告
  3. 网络异常不踢人，避免误杀
- 后台"设备管理 → 踢下线并禁卡" 会把对应卡 `status=2`，最多等一个心跳周期后该设备立即失效

### 4.4 防重放
- 每次请求带 `ts`（UNIX 秒）+ `nonce`（16 字节 hex 随机数）
- 服务端校验 `abs(now-ts) ≤ 600`，超时直接拒绝

---

## 五、API 参考

### `POST /pc_auth/api.php`
Content-Type: application/json

请求：
```json
{
  "app_id":    "pcui_default",
  "action":    "activate",          // 或 "verify"
  "card":      "ABCD-EFGH-IJKL-MNPQ",
  "device_id": "<sha256 hex>",
  "device_info": {
    "model":  "iPhone14,7",
    "sys":    "17.4",
    "name":   "张三的 iPhone",
    "bundle": "com.tigisoftware.Filza"
  },
  "ts":    1710000000,
  "nonce": "a1b2c3d4e5f60718"
}
```

响应（成功）：
```json
{
  "code": 0,
  "msg":  "ok",
  "data": {
    "expires_at": 1712678400,
    "sign":       "base64(RSA-SHA256-Sign('app_id|device_id|card|expires_at'))",
    "type":       "day"
  }
}
```

错误码表：

| code | 含义 |
| ---- | ---- |
| 0    | 成功 |
| 1001 | 卡密不存在 |
| 1002 | 卡密已禁用 |
| 1003 | 卡密已过期 |
| 1004 | 卡密已绑定其它设备 |
| 1005 | 未激活（verify 时） |
| 1006 | 参数错误 |
| 1007 | APP_ID 不匹配 |
| 1008 | 时间戳失效（防重放） |
| 500  | 服务器异常 |

---

## 六、功能清单（已全部实现）

### iOS 端
- [x] 启动首屏前强制弹出卡密激活
- [x] 设备指纹一机一码（Keychain 持久化）
- [x] RSA-2048 签名校验（防中间人）
- [x] 本地缓存 + 离线宽容放行（网络异常不踢人）
- [x] 心跳到期下线（5 分钟间隔）
- [x] 点击复制机器码 / 剪贴板粘贴卡密
- [x] 失败提示、校验中 loading
- [x] 授权失效弹 Alert → 一键重新激活

### PHP 管理后台
- [x] 4 步自助安装向导（环境检测/建库/建管理员/生成 RSA）
- [x] 仪表盘（6 个彩色统计卡片 + 最近 7 天激活柱状图 + 即将到期提醒 + 最近活动）
- [x] 卡密管理（搜索/按状态/类型/批次筛选/分页）
- [x] 点击卡密任意字段即复制 + toast 提示
- [x] 批量禁用/恢复/解绑设备/延长时长/删除
- [x] 批量生成（小时/天/周/月/年/永久卡 + 自定义长度 + 前缀 + 备注 + 批次号）
- [x] 一键复制全部 / 导出 TXT
- [x] 设备管理（在线/离线状态 + 机器码复制 + 踢下线 + 解绑）
- [x] 系统日志（全部 API 请求/后台动作均留痕，可按类型筛选，支持定期清理）
- [x] 修改管理员密码
- [x] RSA 公钥查看/复制
- [x] CSRF 防护 + 密码 bcrypt 加密 + 防重放

---

## 七、运维建议

1. 强烈建议启用 **HTTPS**，否则 API 请求中 `device_info` 仍可能被抓包（签名只保护结果不可伪造，但请求参数仍是明文）
2. 定期备份 `server/keys/private.pem` 到安全位置（丢失后所有 iOS 客户端必须重发公钥更新版本）
3. 大批量生产时建议改 `PHP max_execution_time` ≥ 60s，生成 1000 张 ≈ 5 秒
4. 若要做**多 App 共用同一后台**：在每个 App 用不同 `kPCAuthAppID`，再在后台新增字段区分，本方案默认单 APP_ID 强匹配
5. 后台 `includes/config.php` 含数据库密码，千万别提交公共仓库

---

## 八、测试账号

安装完成即可用安装向导第 3 步填的账号登录 `admin/login.php`。

建议第一件事：
1. 进入 **批量生成** → 生成 1 张"日卡"做联调
2. 把这张卡粘贴到 iPhone 上 → 看是否正常激活、主界面正常弹出
3. 后台 **卡密管理** 查看绑定设备 + 到期时间
4. 点一下 **禁用** → 等 5 分钟看 iOS 是否弹"授权失效"

完成！🎉

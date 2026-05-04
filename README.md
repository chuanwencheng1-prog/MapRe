# PersonalCenterUI —— 按 `wy.html` 1:1 还原的 iOS dylib 插件

## 一、功能概述

本工程是一个 **Theos tweak / dylib**，注入到宿主 `com.tigisoftware.Filza` 进程（可换任意宿主），
启动即在 `keyWindow` 上 `present` 一个全屏首屏，
**UI 与 `wy.html` 像素级一致**（尺寸、颜色、阴影、圆角、间距、动画均按 CSS 原样还原）：

- 顶部 **56pt 渐变标题栏**（135° `#1677ff → #0958d9`，白字 18pt 600，阴影 0 2 12 rgba(9,88,217,0.18)）
- 4 张 **白色圆角 20 菜单卡片**（阴影 0 4 18 rgba(0,0,0,0.06)，`margin-bottom: 16`）
  - 订单管理 / 个人资料 / 系统设置 / 帮助与客服（图标、颜色、子项均一致）
- 每个菜单：一级 60pt 行高、32x32 圆角 10 彩色图标、右侧 ⌄ 箭头（展开旋转 180° 并变蓝）
- 二级行：`padding: 14 24`、14pt #555、底部 1pt 分隔；右侧 **#00b96b 圆角"确定"按钮**
- 点击"确定" → 弹出 **320pt 圆角 20 居中进度弹窗**（进度条 12pt 高 `#00b96b → #23c97c` 渐变）

逻辑流程**完整沿用** `yy1_ipa_分析报告.txt` 第二、三、四节：
`LC_LOAD_WEAK_DYLIB` 注入 → `+load`/`UIApplicationDidFinishLaunchingNotification` 监听
→ `keyWindow` 上 `present` VC → 点击按钮触发三路沙盒定位策略 + `downloadAndCopyPakFileWithURL:toDestination:`。

### 三路沙盒定位（即 yy1.ipa 中 `[PAK下载器] 找到和平精英路径(方法1/2/3)` 的对应实现）

> iOS 沙盒 UUID 是系统随机分配的 —— 你**写不出**绝对路径，必须扫描定位。

| 策略 | 做什么 |
| --- | --- |
| **方法 1** | 扫描 `/var/mobile/Containers/Data/Application/*/.com.apple.mobile_container_manager.metadata.plist`，读取 `MCMMetadataIdentifier` 与目标 Bundle ID 比对 |
| **方法 2** | 私有 API `LSApplicationWorkspace` 枚举所有 App，匹配 `applicationIdentifier` 后取 `dataContainerURL` |
| **方法 3** | 若 dylib 宿主就是目标 App 自身（自注入场景），直接 `NSHomeDirectory()` 兜底 |

> 与 yy1.ipa 唯一区别：目标 Bundle ID 不再写死为 `com.tencent.tmgp.pubgmhd`，而是由你在配置区填写**自己程序的 Bundle ID**。

---

## 二、★ 必改的自定义配置 ★

打开 [`PCPakDownloader.m`](./PCPakDownloader.m)，顶部有醒目的 **"自定义配置区"**：

| 字段 | 是否必改 | 说明 |
| --- | --- | --- |
| `kPCPakDownloadURL` | ❌ 已预填直链，不用动 | `.pak` 下载 URL |
| `kPCPakFileName` | ⭕ 可选 | 保存后的文件名 |
| **`kPCTargetBundleID`** | ✅ **必改** | **你自己程序的 Bundle ID**。扫描遍历的匹配键 |
| **`kPCRelativeSubPath`** | ⭕ 已预填 `ShadowTrackerExtra/Saved/Paks` | 沙盒内相对子路径，相对 `Documents/` |
| `kPCFallbackUUIDHint` | ⭕ 可选 | UUID 兜底 hint，留空=自动扫描 |
| `kPCOverwriteIfExists` | ⭕ 可选 | `YES` = 覆盖已存在同名文件 |

**最终落盘路径计算规则**：
```
<扫描定位到的沙盒根>/Documents/<kPCRelativeSubPath>/<kPCPakFileName>
```
例：`/var/mobile/Containers/Data/Application/DA6AEC98-D732-4E82-B789-246C0687FB93/Documents/ShadowTrackerExtra/Saved/Paks/xxx.pak`

---

## 三、目录结构

```
projects/PersonalCenterUI/
├── Makefile                     Theos 编译脚本（arm64 + arm64e，target iOS 14）
├── control                      deb 包描述
├── PersonalCenterUI.plist       注入目标 Filter（默认 com.tigisoftware.Filza）
├── Tweak.xm                     dylib 入口 %ctor + 启动首屏 present
├── PCMainViewController.h/.m    主 VC（wy.html 1:1 UI）
├── PCDownloadPopView.h/.m       居中进度弹窗
└── PCPakDownloader.h/.m         ★ 自定义配置区 ★ + 下载/复制实现
```

---

## 四、云编译 + 注入 + 重签流程

1. 把整个 `projects/PersonalCenterUI/` 目录 + `Filza.ipa` 一起喂给
   [`theos_online_builder.py`](../../theos_online_builder.py)；
2. GitHub Actions 会：
   - 用 Theos 编译出 `PersonalCenterUI.dylib`（arm64 + arm64e）
   - 用 `insert_dylib --weak --inplace` 给 `Payload/Filza.app/Filza` 追加
     `LC_LOAD_WEAK_DYLIB @executable_path/PersonalCenterUI.dylib`
   - `ldid`/`codesign` 重签并打包回 `Filza_PersonalCenter.ipa`；
3. 用 AltStore / Sideloadly / 在线签名平台装回手机即可。

安装后打开 Filza：**第一屏就是 `wy.html` 的个人中心页面**，
点击任一菜单下的"确定" → 弹出进度条 → 自动下载 `.pak` 到你填的自定义路径。

---

## 五、想换宿主 App？

修改 [`PersonalCenterUI.plist`](./PersonalCenterUI.plist) 里的 `Bundles` 为目标 App 的 Bundle ID，
同时 [`Makefile`](./Makefile) 里的 `INSTALL_TARGET_PROCESSES` 改为对应进程名即可。
dylib 注入到的目标 App 必须是 **未加密的 Mach-O**（App Store 的 IPA 需先砸壳）。

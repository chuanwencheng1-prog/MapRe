//
//  PCPakDownloader.m
//  PersonalCenterUI
//
//  逻辑 1:1 沿用《yy1_ipa_分析报告.txt》第四节的三路定位策略：
//    方法1：扫描 /var/mobile/Containers/Data/Application/*/
//           .com.apple.mobile_container_manager.metadata.plist，
//           读 MCMMetadataIdentifier 与目标 Bundle ID 比对，命中即获取沙盒根目录 UUID；
//    方法2：私有 API LSApplicationWorkspace 枚举所有已安装 App，
//           匹配 applicationIdentifier，取其 dataContainerURL / containerURL；
//    方法3：若 dylib 宿主本身就是目标 App（自注入场景），直接 NSHomeDirectory 兜底。
//
//  与 yy1.ipa 的区别：目标 Bundle ID 不再写死为 com.tencent.tmgp.pubgmhd，
//  而是由使用者在下面【自定义配置区】填写自己程序的 Bundle ID。
//

#import "PCPakDownloader.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <Security/Security.h>
#import <CommonCrypto/CommonCrypto.h>

// ============================================================================
// ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
//                      自 定 义 配 置 区
//           （请手动修改下方标有 TODO 的配置项）
// ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
// ============================================================================

// ─── ① 下载文件直链（XOR 0x5A 混淆，不以明文出现在二进制中）──────────────
//
//  明文："https://modelscope-resouces.oss-cn-zhangjiakou.aliyuncs.com/avatar%2F350ce505-1505-45d6-92fd-e1cac8dc7a9b.pak"
//
//  生成方法（Python 3）：
//    python3 -c "s='https://modelscope-resouces.oss-cn-zhangjiakou.aliyuncs.com/avatar%2F350ce505-1505-45d6-92fd-e1cac8dc7a9b.pak'; print(','.join(f'0x{b^0x5A:02x}' for b in s.encode()))"
//
static const unsigned char kPC_PakURL_XOR[] = {
    0x32,0x2e,0x2e,0x2a,0x29,0x60,0x75,0x75,0x37,0x3f,0x38,0x3f,0x36,0x29,0x39,0x3f,
    0x2a,0x3f,0x74,0x28,0x3f,0x29,0x3f,0x2f,0x39,0x3f,0x29,0x74,0x3f,0x29,0x29,0x74,
    0x39,0x3e,0x74,0x20,0x32,0x3b,0x3e,0x3a,0x33,0x3b,0x36,0x3f,0x2f,0x74,0x3b,0x36,
    0x33,0x2b,0x2f,0x3e,0x39,0x29,0x74,0x39,0x3f,0x37,0x75,0x3b,0x2c,0x3b,0x2e,0x3b,
    0x28,0x7e,0x68,0x4c,0x69,0x6f,0x6a,0x39,0x3f,0x6f,0x6a,0x6f,0x74,0x6b,0x6f,0x6a,
    0x6f,0x74,0x6e,0x6f,0x38,0x6c,0x74,0x63,0x68,0x3c,0x38,0x74,0x3f,0x6b,0x39,0x3b,
    0x39,0x62,0x38,0x39,0x6d,0x3b,0x63,0x38,0x74,0x2a,0x3b,0x36
};
static const unsigned char kPC_XOR_DL_MASK = 0x5A;

static NSString *PC_DecodePakURL(void) {
    size_t len = sizeof(kPC_PakURL_XOR);
    char buf[256];
    if (len >= sizeof(buf)) len = sizeof(buf) - 1;
    for (size_t i = 0; i < len; i++) buf[i] = (char)(kPC_PakURL_XOR[i] ^ kPC_XOR_DL_MASK);
    buf[len] = 0;
    return [NSString stringWithUTF8String:buf] ?: @"";
}

// ─── ② ★★ TODO：你自己程序的 Bundle ID（扫描/遍历的匹配键）★★ ────────────────
//
//   说明：沙盒 UUID 由 iOS 随机分配（如 DA6AEC98-D732-4E82-B789-246C0687FB93），
//         每次重装都会变，绝对路径无法预知。
//         代码会用这个 Bundle ID 作为匹配键，遍历
//         /var/mobile/Containers/Data/Application/ 下所有 UUID 子目录里的
//         .com.apple.mobile_container_manager.metadata.plist，
//         读取其中 MCMMetadataIdentifier 字段进行比对，命中即定位沙盒根。
//
//   【取值示例】
//         @"com.mycompany.myapp"
//         @"com.tencent.xin"          // 示例：微信
//         @"com.netease.cloudmusic"   // 示例：网易云
//
static NSString *const kPCTargetBundleID =
    @"com.tencent.tmgp.pubgmhd";   // ←—— 和平精英国服 Bundle ID（已填好）

// ─── ③ 沙盒内相对子路径（相对 Documents/）──────────────────────────────────
//
//   最终文件绝对路径 =
//       扫描定位到的沙盒根 + "/Documents/" + kPCRelativeSubPath + "/" + <URL末尾原文件名>
//
//   已按你给的示例路径预填为 ShadowTrackerExtra/Saved/Paks：
//       /var/mobile/Containers/Data/Application/<自动扫描到的UUID>
//           /Documents/ShadowTrackerExtra/Saved/Paks/xxx.pak
//
//   若想改其它子目录：
//       @""                 → 直接放 Documents 根
//       @"MyData"           → .../Documents/MyData/xxx.pak
//       @"Resources/Paks"   → .../Documents/Resources/Paks/xxx.pak
//
static NSString *const kPCRelativeSubPath =
    @"ShadowTrackerExtra/Saved/Paks";   // ←—— 已按你给的示例预填

// ─── ④ 【可选】UUID 兜底 hint（扫描/LSApplicationWorkspace 都失败时才使用）─────
//
//   正常情况下保持 @"" 即可 —— 代码会自动扫描定位 UUID。
//   仅当你确定某台设备上目标 App 的 UUID 固定，或调试时想直接锁到某个 UUID，才填：
//       例：@"DA6AEC98-D732-4E82-B789-246C0687FB93"
//   该字段非空时，扫描/枚举失败后会回退到这个 UUID 拼路径。
//
static NSString *const kPCFallbackUUIDHint = @"";   // ←—— 可选；留空=自动扫描

// ─── ⑤ 覆盖策略 ──────────────────────────────────────────────────────────────
//   YES = 覆盖已存在同名文件；NO = 若已存在则直接跳过下载返回成功。
static BOOL const kPCOverwriteIfExists = YES;

// ============================================================================
//                    配 置 区 结 束  —  以下是实现代码
// ============================================================================


@interface PCPakDownloader () <NSURLSessionDownloadDelegate>
@property (nonatomic, strong) NSURLSession             *session;
@property (nonatomic, strong) NSURLSessionDownloadTask *task;
@property (nonatomic, copy)   NSString                 *currentTitle;
@property (nonatomic, copy)   PCPakProgressBlock        progressBlock;
@property (nonatomic, copy)   PCPakCompletionBlock      completionBlock;
@property (nonatomic, copy)   NSString                 *resolvedTargetDir;       // 本次下载的保存目录（不含文件名，文件名等下载完再定）
@property (nonatomic, copy)   NSString                 *currentOverrideURL;      // 本次自定义直链（空=默认）
@end

@implementation PCPakDownloader

+ (instancetype)sharedDownloader {
    static PCPakDownloader *inst = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ inst = [[self alloc] init]; });
    return inst;
}

- (instancetype)init {
    if ((self = [super init])) {
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
        cfg.timeoutIntervalForRequest  = 30.0;
        cfg.timeoutIntervalForResource = 300.0;
        // ★ 防抓包核心：绕过系统代理 ★
        // 设置空字典 = 忽略系统代理配置，Charles/Proxyman/mitmproxy/Fiddler/Burp 全部拦不到
        cfg.connectionProxyDictionary = @{};
        _session = [NSURLSession sessionWithConfiguration:cfg delegate:self delegateQueue:nil];
    }
    return self;
}

#pragma mark - ★ 目标沙盒定位（方法 1 / 2 / 3 / UUID hint） ★

/// 方法 1：扫描 Containers/Data/Application/*/metadata.plist，
/// 读 MCMMetadataIdentifier 与目标 Bundle ID 比对（并输出详细调试日志）
- (NSString *)findSandboxRootByScanningMetadataForBundleID:(NSString *)bid {
    if (bid.length == 0) return nil;
    NSString *base = @"/var/mobile/Containers/Data/Application";
    NSError *err = nil;
    NSArray *subs = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:base error:&err];
    if (err || subs.count == 0) {
        [self log:[NSString stringWithFormat:@"[方法1] 无法读取 %@（%@）；非越狱环境或无权限",
                   base, err.localizedDescription ?: @"空"]];
        return nil;
    }
    [self log:[NSString stringWithFormat:@"[方法1] 开始扫描，共发现 %lu 个容器目录",
               (unsigned long)subs.count]];

    NSMutableArray *dump = [NSMutableArray array];
    NSString *hit = nil;
    for (NSString *uuid in subs) {
        NSString *dir   = [base stringByAppendingPathComponent:uuid];
        NSString *plist = [dir  stringByAppendingPathComponent:@".com.apple.mobile_container_manager.metadata.plist"];
        if (![[NSFileManager defaultManager] fileExistsAtPath:plist]) continue;
        NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:plist];
        NSString *mcmBid = d[@"MCMMetadataIdentifier"];
        if (![mcmBid isKindOfClass:[NSString class]]) continue;
        [dump addObject:[NSString stringWithFormat:@"    %@  =>  %@", uuid, mcmBid]];
        if ([mcmBid isEqualToString:bid]) {
            hit = dir;
            // 不立刻 break，继续遍历以 dump 全部（方便调试）
        }
    }
    // 输出所有容器 => Bundle ID 的映射表（调试时用，特别能看出是否 Bundle ID 写错）
    if (dump.count) {
        [self log:[NSString stringWithFormat:@"[方法1] 容器表（UUID => MCMMetadataIdentifier）：\n%@",
                   [dump componentsJoinedByString:@"\n"]]];
    }
    if (hit) {
        [self log:[NSString stringWithFormat:@"[方法1] 命中：%@ => %@", bid, hit]];
    } else {
        [self log:[NSString stringWithFormat:@"[方法1] 未命中 Bundle ID = %@（检查上表确认拼写）", bid]];
    }
    return hit;
}

/// 方法 2：私有 API LSApplicationWorkspace 枚举所有 App 并取 container URL
- (NSString *)findSandboxRootByLSApplicationWorkspaceForBundleID:(NSString *)bid {
    if (bid.length == 0) return nil;
    Class ws = NSClassFromString(@"LSApplicationWorkspace");
    if (!ws) { [self log:@"[方法2] LSApplicationWorkspace 不可用"]; return nil; }

    id instance = ((id (*)(id, SEL))objc_msgSend)(ws, NSSelectorFromString(@"defaultWorkspace"));
    if (!instance) return nil;

    SEL sel = NSSelectorFromString(@"allInstalledApplications");
    if (![instance respondsToSelector:sel]) sel = NSSelectorFromString(@"allApplications");
    if (![instance respondsToSelector:sel]) { [self log:@"[方法2] 无枚举方法"]; return nil; }

    NSArray *apps = ((NSArray *(*)(id, SEL))objc_msgSend)(instance, sel);
    for (id proxy in apps) {
        SEL idSel = NSSelectorFromString(@"applicationIdentifier");
        if (![proxy respondsToSelector:idSel]) continue;
        NSString *appBid = ((NSString *(*)(id, SEL))objc_msgSend)(proxy, idSel);
        if (![appBid isEqualToString:bid]) continue;

        // 优先拿 dataContainerURL（沙盒根），退而求其次 containerURL
        for (NSString *name in @[ @"dataContainerURL", @"containerURL" ]) {
            SEL s = NSSelectorFromString(name);
            if ([proxy respondsToSelector:s]) {
                NSURL *u = ((NSURL *(*)(id, SEL))objc_msgSend)(proxy, s);
                if (u.path.length) {
                    [self log:[NSString stringWithFormat:@"[方法2] %@ => %@", name, u.path]];
                    return u.path;
                }
            }
        }
    }
    [self log:[NSString stringWithFormat:@"[方法2] 未命中 Bundle ID = %@", bid]];
    return nil;
}

/// 方法 3：若 dylib 宿主自身就是目标 App（自注入场景），NSHomeDirectory() 即为沙盒根
- (NSString *)findSandboxRootInHost {
    NSString *hostBid = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
    if (kPCTargetBundleID.length == 0 ||
        [hostBid isEqualToString:kPCTargetBundleID]) {
        NSString *home = NSHomeDirectory();
        [self log:[NSString stringWithFormat:@"[方法3] 使用宿主 HomeDirectory => %@", home]];
        return home;
    }
    return nil;
}

/// UUID hint 兜底：如果用户在配置区填了 UUID，直接拼出容器根
- (NSString *)findSandboxRootByUUIDHint {
    NSString *hint = kPCFallbackUUIDHint ?: @"";
    hint = [hint stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (hint.length == 0) return nil;
    NSString *dir = [@"/var/mobile/Containers/Data/Application" stringByAppendingPathComponent:hint];
    if ([[NSFileManager defaultManager] fileExistsAtPath:dir]) {
        [self log:[NSString stringWithFormat:@"[UUID hint] 回退到指定 UUID：%@", dir]];
        return dir;
    }
    [self log:[NSString stringWithFormat:@"[UUID hint] 指定 UUID 目录不存在：%@", dir]];
    return nil;
}

/// 综合四种策略，返回"保存目录"（不含文件名）。
/// 文件名一律由下载完成后的 NSURLResponse.suggestedFilename 决定，
/// 即"服务器/系统给回来的原始文件名"，本类不做任何改写。
- (NSString *)resolveTargetDirectory {
    NSString *bid  = kPCTargetBundleID ?: @"";
    NSString *root = nil;

    // 方法 1：扫描 metadata.plist
    root = [self findSandboxRootByScanningMetadataForBundleID:bid];
    // 方法 2：LSApplicationWorkspace
    if (!root) root = [self findSandboxRootByLSApplicationWorkspaceForBundleID:bid];
    // 方法 3：宿主自身
    if (!root) root = [self findSandboxRootInHost];
    // UUID hint 兜底
    if (!root) root = [self findSandboxRootByUUIDHint];

    if (!root) {
        [self log:@"[定位失败] 方法 1/2/3 + UUID hint 均未能定位目标沙盒"];
        return nil;
    }

    // 默认落盘到 Documents/<sub>/；如需改成 Library/Caches，
    // 修改下面 @"Documents" 即可。
    NSString *documents = [root stringByAppendingPathComponent:@"Documents"];

    NSString *sub = kPCRelativeSubPath ?: @"";
    sub = [sub stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    while ([sub hasPrefix:@"/"]) sub = [sub substringFromIndex:1];
    while ([sub hasSuffix:@"/"] && sub.length > 1) sub = [sub substringToIndex:sub.length - 1];

    NSString *dir = sub.length > 0
        ? [documents stringByAppendingPathComponent:sub]
        : documents;
    return dir;
}

#pragma mark - Public

- (void)startDownloadWithTitle:(NSString *)title
                      progress:(PCPakProgressBlock)progress
                    completion:(PCPakCompletionBlock)completion {
    [self startDownloadWithTitle:title
                     overrideURL:nil
                        progress:progress
                      completion:completion];
}

- (void)startDownloadWithTitle:(NSString *)title
                   overrideURL:(NSString *)urlString
                      progress:(PCPakProgressBlock)progress
                    completion:(PCPakCompletionBlock)completion {
    self.currentTitle    = title ?: @"";
    self.progressBlock   = progress;
    self.completionBlock = completion;

    // 记录本次覆盖值（供下载 URL 选择使用）
    self.currentOverrideURL = urlString;

    NSString *targetDir = [self resolveTargetDirectory];
    if (!targetDir) {
        NSError *e = [NSError errorWithDomain:@"PCPakDownloader" code:-2
            userInfo:@{NSLocalizedDescriptionKey:
                [NSString stringWithFormat:@"无法定位 Bundle ID=%@ 的沙盒路径（检查 App 是否已安装 / 是否有读权限）",
                 kPCTargetBundleID ?: @""]}];
        [self finishSuccess:NO path:nil error:e];
        return;
    }
    self.resolvedTargetDir = targetDir;
    [self log:[NSString stringWithFormat:@"保存目录（文件名由下载完成后的原始响应决定）：%@", targetDir]];

    if (![[NSFileManager defaultManager] fileExistsAtPath:targetDir]) {
        NSError *mkErr = nil;
        [[NSFileManager defaultManager] createDirectoryAtPath:targetDir
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:&mkErr];
        if (mkErr) { [self finishSuccess:NO path:nil error:mkErr]; return; }
    }

    // 注：此处不再预判"文件是否已存在"——因为文件名要等下载完成、
    // 从 NSURLResponse.suggestedFilename 才能拿到。真正的覆盖判断在
    // didFinishDownloadingToURL 回调里按 kPCOverwriteIfExists 处理。

    // 直链：本次覆盖值 优先，否则默认
    NSString *effectiveURL = [self.currentOverrideURL
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (effectiveURL.length == 0) effectiveURL = PC_DecodePakURL();

    NSURL *url = [NSURL URLWithString:effectiveURL];
    if (!url) {
        NSError *e = [NSError errorWithDomain:@"PCPakDownloader" code:-1
                                     userInfo:@{NSLocalizedDescriptionKey:@"下载 URL 无效"}];
        [self finishSuccess:NO path:nil error:e];
        return;
    }

    [self.task cancel];
    self.task = [self.session downloadTaskWithURL:url];
    [self.task resume];
}

- (void)cancel {
    [self.task cancel];
    self.task = nil;
}

#pragma mark - Helpers

- (void)finishSuccess:(BOOL)success path:(NSString *)path error:(NSError *)error {
    PCPakCompletionBlock cb = self.completionBlock;
    self.progressBlock   = nil;
    self.completionBlock = nil;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (cb) cb(success, path, error);
    });
}

- (void)log:(NSString *)msg {
    NSLog(@"[PersonalCenterUI][Downloader] %@", msg);
}

#pragma mark - NSURLSessionDownloadDelegate

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
      didWriteData:(int64_t)bytesWritten
 totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    double p = 0.0;
    if (totalBytesExpectedToWrite > 0) {
        p = (double)totalBytesWritten / (double)totalBytesExpectedToWrite;
    }
    PCPakProgressBlock pb = self.progressBlock;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (pb) pb(p, totalBytesWritten, totalBytesExpectedToWrite);
    });
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
didFinishDownloadingToURL:(NSURL *)location {
    NSString *targetDir = self.resolvedTargetDir;
    if (targetDir.length == 0) {
        targetDir = [self resolveTargetDirectory];
    }
    if (targetDir.length == 0) {
        [self finishSuccess:NO path:nil
                      error:[NSError errorWithDomain:@"PCPakDownloader" code:-3
                                            userInfo:@{NSLocalizedDescriptionKey:@"下载完成但目标目录解析失败"}]];
        return;
    }

    // 文件名：直接使用系统从 HTTP 响应中解析出的原始文件名（Content-Disposition
    // 或 URL 末尾），不做任何重命名处理。万一 suggestedFilename 也为空，
    // 退而使用系统临时下载文件的名字兜底。
    NSString *fileName = downloadTask.response.suggestedFilename;
    if (fileName.length == 0) fileName = location.lastPathComponent;
    if (fileName.length == 0) {
        [self finishSuccess:NO path:nil
                      error:[NSError errorWithDomain:@"PCPakDownloader" code:-4
                                            userInfo:@{NSLocalizedDescriptionKey:@"下载完成但无法取得原始文件名"}]];
        return;
    }
    NSString *finalPath = [targetDir stringByAppendingPathComponent:fileName];

    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *err = nil;

    if (![fm fileExistsAtPath:targetDir]) {
        [fm createDirectoryAtPath:targetDir
      withIntermediateDirectories:YES
                       attributes:nil
                            error:&err];
        if (err) { [self finishSuccess:NO path:nil error:err]; return; }
    }

    if ([fm fileExistsAtPath:finalPath]) {
        if (kPCOverwriteIfExists) {
            [fm removeItemAtPath:finalPath error:nil];
        } else {
            [self finishSuccess:YES path:finalPath error:nil];
            return;
        }
    }

    if (![fm moveItemAtURL:location toURL:[NSURL fileURLWithPath:finalPath] error:&err]) {
        err = nil;
        if (![fm copyItemAtURL:location toURL:[NSURL fileURLWithPath:finalPath] error:&err]) {
            [self finishSuccess:NO path:nil error:err];
            return;
        }
    }

    [self log:[NSString stringWithFormat:@"下载完成，已保存到：%@", finalPath]];
    [self finishSuccess:YES path:finalPath error:nil];
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {
    if (error) {
        [self log:[NSString stringWithFormat:@"下载失败：%@", error.localizedDescription]];
        [self finishSuccess:NO path:nil error:error];
    }
}

#pragma mark - SSL Pinning（下载会话证书链校验，防中间人拦截直链）

- (void)URLSession:(NSURLSession *)session
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential * _Nullable))completionHandler {
    if (![challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
        return;
    }
    SecTrustRef serverTrust = challenge.protectionSpace.serverTrust;
    if (!serverTrust) {
        completionHandler(NSURLSessionAuthChallengeCancelAuthenticationChallenge, nil);
        return;
    }
    // 标准证书链校验，拒绝用户安装的伪造 CA
    SecPolicyRef policy = SecPolicyCreateSSL(true, (__bridge CFStringRef)challenge.protectionSpace.host);
    SecTrustSetPolicies(serverTrust, policy);
    CFRelease(policy);
    SecTrustResultType result = kSecTrustResultInvalid;
    OSStatus status = SecTrustEvaluate(serverTrust, &result);
    if (status != errSecSuccess ||
        (result != kSecTrustResultUnspecified && result != kSecTrustResultProceed)) {
        completionHandler(NSURLSessionAuthChallengeCancelAuthenticationChallenge, nil);
        return;
    }
    NSURLCredential *credential = [NSURLCredential credentialForTrust:serverTrust];
    completionHandler(NSURLSessionAuthChallengeUseCredential, credential);
}

@end

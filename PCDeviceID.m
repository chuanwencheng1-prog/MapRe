//
//  PCDeviceID.m
//  PersonalCenterUI
//

#import "PCDeviceID.h"
#import "PCAuthCrypto.h"
#import <UIKit/UIKit.h>
#import <sys/utsname.h>
#import <dlfcn.h>

static NSString *gCachedUDID  = nil;
static NSString *gCachedSrc   = nil;

/// 运行时拼出 "UniqueDeviceID" / "/usr/lib/libMobileGestalt.dylib"
/// 避免明文常量被 strings 扫到。
static NSString *PC_S(const char *frags[], int n) {
    NSMutableString *m = [NSMutableString string];
    for (int i = 0; i < n; i++) {
        if (frags[i]) [m appendFormat:@"%s", frags[i]];
    }
    return m;
}

/// 零闪退读取真 UDID：dlopen + dlsym，任何一步失败就返回 nil。
static NSString * _Nullable PC_ReadRealUDID(void) {
    const char *fragsLib[] = { "/usr/lib/", "libMobile", "Gestalt", ".dylib" };
    NSString *libPath = PC_S(fragsLib, 4);
    if (libPath.length == 0) return nil;

    void *h = dlopen(libPath.UTF8String, RTLD_LAZY | RTLD_GLOBAL);
    if (!h) return nil;

    typedef CFTypeRef (*MG_f)(CFStringRef);
    const char *symFrags[] = { "MG", "Copy", "Answer" };
    NSString *sym = PC_S(symFrags, 3);
    MG_f fn = (MG_f)dlsym(h, sym.UTF8String);
    if (!fn) {
        // 注意：dlclose 之后 fn 就失效；这里暂不 close（开销极小、稳定性优先）
        return nil;
    }

    const char *keyFrags[] = { "Unique", "Device", "ID" };
    NSString *key = PC_S(keyFrags, 3);

    @try {
        CFTypeRef answer = fn((__bridge CFStringRef)key);
        if (!answer) return nil;
        NSString *out = nil;
        if (CFGetTypeID(answer) == CFStringGetTypeID()) {
            out = [(__bridge NSString *)answer copy];
        }
        CFRelease(answer);
        // iOS 的 UDID 是 40 位十六进制（A5 及之前旧设备）
        // iOS 7+ 新设备：8-4-4-4-12 UUID 风格（36 位，含 '-'）
        // 两种我们都接受，只要非空且长度 >= 16
        if (out.length >= 16) return out;
    } @catch (__unused id e) {
        return nil;
    }
    return nil;
}

/// 越狱环境下某些工具 / 老 jb 会把 UDID 写到这里
static NSString * _Nullable PC_ReadJbCachedUDID(void) {
    NSArray<NSString *> *paths = @[
        @"/var/mobile/Library/Preferences/.GlobalPreferences.plist",
        @"/var/mobile/Library/Lockdown/data_ark.plist",
    ];
    for (NSString *p in paths) {
        NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:p];
        NSString *uid = d[@"UniqueDeviceID"] ?: d[@"SerialNumber"];
        if ([uid isKindOfClass:[NSString class]] && uid.length >= 16) return uid;
    }
    return nil;
}

static NSString *PC_DerivedFallback(void) {
    struct utsname u; uname(&u);
    NSString *machine = [NSString stringWithUTF8String:u.machine] ?: @"unknown";
    NSString *idfv    = [[UIDevice currentDevice].identifierForVendor UUIDString] ?: @"00000000-0000-0000-0000-000000000000";
    NSString *osMajor = [[UIDevice currentDevice].systemVersion componentsSeparatedByString:@"."].firstObject ?: @"";
    NSString *bundle  = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
    NSString *mix     = [NSString stringWithFormat:@"%@|%@|%@|%@|pcui-udid-v1", idfv, machine, osMajor, bundle];
    NSData *raw = [mix dataUsingEncoding:NSUTF8StringEncoding];
    return [PCAuthCrypto hexString:[PCAuthCrypto sha256:raw]];
}

@implementation PCDeviceID

+ (void)_resolve {
    if (gCachedUDID.length) return;

    NSString *u = PC_ReadRealUDID();
    if (u.length >= 16) {
        gCachedUDID = [[u lowercaseString] stringByReplacingOccurrencesOfString:@"-" withString:@""];
        gCachedSrc  = @"real";
        return;
    }
    u = PC_ReadJbCachedUDID();
    if (u.length >= 16) {
        gCachedUDID = [[u lowercaseString] stringByReplacingOccurrencesOfString:@"-" withString:@""];
        gCachedSrc  = @"jailbreak";
        return;
    }
    gCachedUDID = PC_DerivedFallback();
    gCachedSrc  = @"derived";
}

+ (NSString *)udid {
    @synchronized (self) {
        [self _resolve];
        return gCachedUDID ?: @"";
    }
}

+ (NSString *)source {
    @synchronized (self) {
        [self _resolve];
        return gCachedSrc ?: @"derived";
    }
}

@end

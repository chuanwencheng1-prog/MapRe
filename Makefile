THEOS_PACKAGE_SCHEME = rootless
TARGET := iphone:clang:latest:14.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = PakReplacerTest

# ============================================================
# Swift 源文件
# ============================================================
PakReplacerTest_FILES += \
    PakReplacerApp.swift \
    ContentView.swift \
    VerificationView.swift \
    MainAppView.swift \
    Components.swift \
    PakReplacerViewModel.swift \
    Models.swift \
    TXNHVerifyAPI.swift \
    PakDownloadManager.swift \
    SecureCardStorage.swift \
    ExploitRunner.swift

# ============================================================
# ObjC/C 源文件（Exploit 核心）
# ============================================================
PakReplacerTest_FILES += \
    MDCExploit.m \
    KFDExploit.m \
    CicutaVirosa.m \
    SandboxEscape.m \
    PakFileReplacer.m \
    ExploitBridgeImpl.m

# ============================================================
# 框架依赖
# ============================================================
PakReplacerTest_FRAMEWORKS  = Foundation UIKit SwiftUI Combine BackgroundTasks Security IOKit
PakReplacerTest_PRIVATE_FRAMEWORKS = IOSurface

# ============================================================
# 编译选项
# ============================================================
PakReplacerTest_SWIFTFLAGS = \
    -swift-version 5 \
    -import-objc-header $(THEOS_PROJECT_DIR)/ExploitBridge.h

PakReplacerTest_CFLAGS = \
    -fobjc-arc \
    -I$(THEOS_PROJECT_DIR)

PakReplacerTest_LDFLAGS = -lz -liconv

# ============================================================
# Info.plist & 签名授权
# ============================================================
PakReplacerTest_INFOPLIST_FILE  = Info.plist
PakReplacerTest_CODESIGN_FLAGS  = -Sent.plist

include $(THEOS)/makefiles/application.mk

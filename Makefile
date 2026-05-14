THEOS_PACKAGE_SCHEME = rootless
TARGET := iphone:clang:latest:14.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = PakReplacerTest

# ============================================================
# Swift 源文件
# ============================================================
PakReplacerTest_FILES += \
    PakReplacerTest/App/PakReplacerApp.swift \
    PakReplacerTest/Views/ContentView.swift \
    PakReplacerTest/Views/VerificationView.swift \
    PakReplacerTest/Views/MainAppView.swift \
    PakReplacerTest/Views/Components/Components.swift \
    PakReplacerTest/ViewModels/PakReplacerViewModel.swift \
    PakReplacerTest/Models/Models.swift \
    PakReplacerTest/Network/TXNHVerifyAPI.swift \
    PakReplacerTest/Download/PakDownloadManager.swift \
    PakReplacerTest/Utils/SecureCardStorage.swift \
    PakReplacerTest/Exploit/ExploitRunner.swift

# ============================================================
# ObjC/C 源文件（Exploit 核心）
# ============================================================
PakReplacerTest_FILES += \
    PakReplacerTest/Exploit/MDCExploit.m \
    PakReplacerTest/Exploit/KFDExploit.m \
    PakReplacerTest/Exploit/CicutaVirosa.m \
    PakReplacerTest/Exploit/SandboxEscape.m \
    PakReplacerTest/Exploit/PakFileReplacer.m \
    PakReplacerTest/Exploit/ExploitBridgeImpl.m

# ============================================================
# 框架依赖
# ============================================================
PakReplacerTest_FRAMEWORKS  = Foundation UIKit SwiftUI Combine BackgroundTasks Security
PakReplacerTest_PRIVATE_FRAMEWORKS = IOSurface

# ============================================================
# 编译选项
# ============================================================
PakReplacerTest_SWIFTFLAGS = \
    -swift-version 5 \
    -import-objc-header $(THEOS_PROJECT_DIR)/PakReplacerTest/Exploit/ExploitBridge.h

PakReplacerTest_CFLAGS = \
    -fobjc-arc \
    -I$(THEOS_PROJECT_DIR)/PakReplacerTest/Exploit

PakReplacerTest_LDFLAGS = -lz -liconv

# ============================================================
# Info.plist & 签名授权
# ============================================================
PakReplacerTest_INFOPLIST_FILE  = PakReplacerTest/Info.plist
PakReplacerTest_CODESIGN_FLAGS  = -Sent.plist

include $(THEOS)/makefiles/application.mk

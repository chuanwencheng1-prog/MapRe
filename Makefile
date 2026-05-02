# OTABlocker tweak Makefile
#
# 说明：
#   - TARGET 指定编译用的 toolchain、clang、最新 SDK，最低部署版本 13.0
#     （运行环境覆盖 iOS 17.1 ~ iOS 26.0，部署目标低一些不影响）
#   - ARCHS 同时打 arm64 和 arm64e，老/新设备都能跑
#   - TWEAK_NAME 决定输出的 dylib 文件名： .theos/obj/OTABlocker.dylib
#

TARGET           = iphone:clang:latest:13.0
ARCHS            = arm64 arm64e
INSTALL_TARGET_PROCESSES = Filza

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = OTABlocker

OTABlocker_FILES        = OTABlockerTweak.m OTABlockerViewController.m
OTABlocker_FRAMEWORKS   = UIKit Foundation CoreGraphics QuartzCore
OTABlocker_CFLAGS       = -fobjc-arc -Wno-deprecated-declarations
OTABlocker_PRIVATE_FRAMEWORKS =

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 Filza || true"

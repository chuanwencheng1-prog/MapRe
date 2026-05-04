TARGET := iphone:clang:latest:14.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = Filza

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = PersonalCenterUI

PersonalCenterUI_FILES      = Tweak.xm PCMainViewController.m PCDownloadPopView.m PCPakDownloader.m
PersonalCenterUI_CFLAGS     = -fobjc-arc -Wno-deprecated-declarations
PersonalCenterUI_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk

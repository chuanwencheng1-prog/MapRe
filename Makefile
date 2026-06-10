INSTALL_TARGET_PROCESSES = KernelPanel
ARCHS = arm64
TARGET = iphone:clang:latest:14.0
PACKAGE_FORMAT = ipa

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = KernelPanel

KernelPanel_FILES = main.m KPAppDelegate.m KPRootViewController.m
KernelPanel_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore
KernelPanel_CFLAGS = -fobjc-arc
KernelPanel_RESOURCE_DIR = Resources

include $(THEOS_MAKE_PATH)/application.mk

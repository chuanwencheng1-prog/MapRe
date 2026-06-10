INSTALL_TARGET_PROCESSES = KernelPanel

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = KernelPanel

KernelPanel_FILES = main.m KPAppDelegate.m KPRootViewController.m
KernelPanel_FRAMEWORKS = UIKit Foundation
KernelPanel_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/application.mk

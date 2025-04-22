TARGET = iphone:clang:13.7:13.0
INSTALL_TARGET_PROCESSES = SpringBoard
ARCHS = arm64e
#THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = mycpumonitor

mycpumonitor_FILES = Tweak.x
mycpumonitor_CFLAGS = -fobjc-arc
#mycpumonitor_FRAMEWORKS += UIKit  UserNotifications
mycpumonitor_FRAMEWORKS += SpringBoardServices Foundation
mycpumonitor_PRIVATE_FRAMEWORKS = SpringBoardServices
include $(THEOS_MAKE_PATH)/tweak.mk
ADDITIONAL_CFLAGS += -I$(THEOS_PROJECT_DIR)/include

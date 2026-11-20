# Glass6Prefs.bundle — bảng điều khiển của Glass 6 trong Cài đặt (PreferenceLoader; mục vào ở
# layout/Library/PreferenceLoader/Preferences/Glass6.plist). Công tắc / thanh trượt khai trong Resources/Root.plist, lưu vào
# /var/mobile/Library/Preferences/vn.glass6.plist rồi gửi thông báo Darwin «vn.glass6/prefs» cho tweak đọc lại.
include ../g6.mk
include $(THEOS)/makefiles/common.mk

# Số bản lấy từ tệp control của gói — một chỗ duy nhất
G6_VERSION := $(shell sed -n 's/^Version: *//p' ../control)

BUNDLE_NAME = Glass6Prefs
# Màn «Dịch vụ hệ thống» dùng lõi (danh mục) và cầu nối g6svc của tweak/Common
Glass6Prefs_FILES = G6RootListController.m G6ServicesController.m G6AssistController.m ../tweak/Common/G6Core.m ../tweak/Common/G6Log.m \
	../tweak/Common/G6Services.m ../tweak/Common/G6Lang.m ../tweak/Common/G6Device.c ../tweak/Common/G6OTA.m G6LTE.m
Glass6Prefs_INSTALL_PATH = /Library/PreferenceBundles
Glass6Prefs_FRAMEWORKS = UIKit Foundation
Glass6Prefs_PRIVATE_FRAMEWORKS = Preferences
# Tệp đầu Preferences của Theos dùng API_AVAILABLE(…) — macro của SDK iOS 11+, SDK 9.3 chưa có → định nghĩa rỗng
Glass6Prefs_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -I../tweak/Common -DG6_VERSION=\"$(G6_VERSION)\" 	'-DAPI_AVAILABLE(...)=' '-DAPI_UNAVAILABLE(...)=' '-DAPI_DEPRECATED(...)=' '-DAPI_DEPRECATED_WITH_REPLACEMENT(...)='
Glass6Prefs_CODESIGN_FLAGS = -S -Hsha1

# Bản thử: cho phép giả mã máy bằng tệp «fake-machine» (G6Device.c) để thử màn «máy chưa được hỗ trợ»
ifneq ($(FINALPACKAGE),1)
Glass6Prefs_CFLAGS += -DG6_DEBUG=1
endif

include $(THEOS_MAKE_PATH)/bundle.mk

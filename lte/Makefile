# g6lte — bật / tắt 4G (LTE dữ liệu) cho SIM MobiFone, Viettel, VinaPhone trên iPhone 5 iOS 6 (docs/DECISIONS.md D47). Cài ở
# /usr/libexec/glass6 (phân vùng hệ thống — /private/var thường gắn «nosuid»); postinst đặt chủ root + bit setuid; prerm chạy
# «g6lte off» trước khi gỡ gói.
include ../g6.mk
include $(THEOS)/makefiles/common.mk

TOOL_NAME = g6lte
g6lte_FILES = g6lte.c
g6lte_INSTALL_PATH = /usr/libexec/glass6
g6lte_CFLAGS = -Wall -Wextra -Werror
g6lte_FRAMEWORKS = CoreFoundation
g6lte_CODESIGN_FLAGS = -S -Hsha1

include $(THEOS_MAKE_PATH)/tool.mk

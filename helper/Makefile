# g6update — công cụ quyền root cài bản cập nhật OTA đã kiểm chữ ký (docs/THIET-KE.md mục 10). Cài ở /usr/libexec/glass6
# (phân vùng hệ thống — phân vùng dữ liệu /private/var của iOS thường gắn «nosuid»); postinst đặt chủ root + bit setuid.
# ota_cert.h (chứng chỉ công khai) sinh bằng tools/gen_ota_cert.py trên máy phát hành và nằm trong git.
include ../g6.mk
include $(THEOS)/makefiles/common.mk

TOOL_NAME = g6update
g6update_FILES = g6update.c
g6update_INSTALL_PATH = /usr/libexec/glass6
g6update_CFLAGS = -Wall -Wextra -Werror
g6update_FRAMEWORKS = CoreFoundation Security
g6update_CODESIGN_FLAGS = -S -Hsha1

include $(THEOS_MAKE_PATH)/tool.mk

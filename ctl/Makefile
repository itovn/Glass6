# glass6ctl — kiểm / tải bản cập nhật qua HTTPS (lõi Rust core/crates/g6-ctl → libg6_ctl.a, rustls). Cài ở /usr/bin, chạy quyền
# mobile; việc cài là của g6update (helper/). G6Shims.c: các hàm iOS 6 thiếu mà thư viện chuẩn Rust gọi (dùng chung với corelib).
include ../g6.mk
include $(THEOS)/makefiles/common.mk

TOOL_NAME = glass6ctl
glass6ctl_FILES = main.c ../corelib/G6Shims.c
glass6ctl_INSTALL_PATH = /usr/bin
glass6ctl_CFLAGS = -Wno-deprecated-declarations
glass6ctl_LDFLAGS = $(CORE_LIB_DIR)/libg6_ctl.a -Wl,-dead_strip
glass6ctl_CODESIGN_FLAGS = -S -Hsha1

include $(THEOS_MAKE_PATH)/tool.mk

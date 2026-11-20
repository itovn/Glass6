# libglass6core.dylib — lõi Rust của Glass 6 (core/crates/g6-ffi → libg6_ffi.a) bọc thành thư viện động, cài ở /usr/lib.
# Tweak và bảng Cài đặt nạp bằng dlopen lúc cần (lõi hỏng thì tự tắt, tiến trình chủ vẫn chạy).
# Chỉ xuất các hàm g6_* (exports.txt): hàm thay thế trong G6Shims.c (clock_gettime…) ở lại trong thư viện.
include ../g6.mk
include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = libglass6core
libglass6core_FILES = G6Shims.c
libglass6core_INSTALL_PATH = /usr/lib
libglass6core_CFLAGS = -Wno-deprecated-declarations
libglass6core_LDFLAGS = -Wl,-force_load,$(CORE_LIB_DIR)/libg6_ffi.a -Wl,-exported_symbols_list,exports.txt -Wl,-dead_strip
libglass6core_CODESIGN_FLAGS = -S -Hsha1

include $(THEOS_MAKE_PATH)/library.mk

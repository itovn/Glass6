# Cài đặt chung cho mọi Makefile của Glass 6 (gói, corelib, tweak, prefs) — include trước common.mk của Theos.
# Dự án con không thừa hưởng biến của Makefile cha: thiếu tệp này Theos dựng thêm arm64 và hỏng lúc liên kết.
TARGET := iphone:clang:9.3:6.0
ARCHS = armv7

# dpkg của iOS 6 chỉ đọc .deb nén gzip; nhân iOS 6 chỉ hiểu chữ ký SHA-1
THEOS_PLATFORM_DEB_COMPRESSION_TYPE = gzip
TARGET_CODESIGN_FLAGS = -S -Hsha1

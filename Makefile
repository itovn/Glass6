# Glass 6 — gói vn.glass6.tweak cho iPad iOS 6 đã jailbreak. Theos trên Linux, SDK 9.3, armv7.
#   bash tools/build.sh                    bản thử
#   bash tools/build.sh FINALPACKAGE=1     bản phát hành
# Cần lõi Rust đã dựng (tools/build.sh lo): CORE_LIB_DIR/libg6_ffi.a, CORE_LIB_DIR/libg6_ctl.a
include g6.mk

# Lõi do tools/build.sh dựng ở <thư mục chứa repo>/target-ios (cạnh repo)
export CORE_LIB_DIR ?= $(abspath $(CURDIR)/../target-ios/armv7-apple-ios6/release)

include $(THEOS)/makefiles/common.mk

SUBPROJECTS += corelib tweak prefs svc helper ctl
include $(THEOS_MAKE_PATH)/aggregate.mk

# Script của gói cần quyền chạy (tệp chép từ Windows không giữ bit x). launchd bỏ qua tệp việc mà nhóm / người khác ghi được.
# Chủ root + bit setuid của g6svc / g6update do postinst đặt.
before-package::
	chmod -R go-w $(THEOS_STAGING_DIR)
	chmod 0755 $(THEOS_STAGING_DIR)/DEBIAN/postinst $(THEOS_STAGING_DIR)/DEBIAN/prerm $(THEOS_STAGING_DIR)/DEBIAN/postrm
	chmod 0644 $(THEOS_STAGING_DIR)/Library/LaunchDaemons/vn.glass6.svcguard.plist

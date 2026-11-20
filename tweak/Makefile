# Thư viện của Glass 6 nạp bằng MobileSubstrate. ObjC thuần, không Logos: lớp / hàm đích tra lúc chạy, thiếu thì bỏ qua.
#   Glass6SB — nạp vào SpringBoard (Glass6SB.plist): mọi bề mặt của SpringBoard, bộ gác an toàn.
#   Glass6UI — nạp vào mọi app dùng UIKit (Glass6UI.plist), tự thôi ngay nếu app ngoài phạm vi: thanh, bảng, nút của UIKit.
# Mã dùng chung ở Common/. Debug/ chỉ có trong bản thử (không FINALPACKAGE=1).
include ../g6.mk
include $(THEOS)/makefiles/common.mk

# Số bản lấy từ tệp control của gói — một chỗ duy nhất
G6_VERSION := $(shell sed -n 's/^Version: *//p' ../control)

TWEAK_NAME = Glass6SB Glass6UI
Glass6SB_FILES = $(wildcard SB/*.m) $(wildcard Common/*.m) Common/G6Guard.c Common/G6Device.c
Glass6SB_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Werror=unguarded-availability -ICommon -ISB -IDebug 	-DG6_VERSION=\"$(G6_VERSION)\" -DG6_SB=1

# Glass6UI cũng được nạp vào SpringBoard (lọc theo UIKit) rồi thôi ngay: lớp ObjC dùng chung phải mang tên khác kẻo runtime
# báo «lớp có ở cả hai thư viện».
Glass6UI_FILES = $(wildcard UI/*.m) $(filter-out Common/G6Services.m Common/G6OTA.m,$(wildcard Common/*.m)) Common/G6Guard.c Common/G6Device.c
Glass6UI_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Werror=unguarded-availability -ICommon -IUI -IDebug 	-DG6_VERSION=\"$(G6_VERSION)\" -DG6Backdrop=G6UIBackdrop
Glass6UI_FRAMEWORKS = Foundation UIKit CoreGraphics QuartzCore ImageIO CoreText
Glass6UI_CODESIGN_FLAGS = -S -Hsha1

ifneq ($(FINALPACKAGE),1)
Glass6SB_FILES += $(wildcard Debug/*.m)
Glass6SB_CFLAGS += -DG6_DEBUG=1
Glass6UI_FILES += $(wildcard Debug/*.m)
Glass6UI_CFLAGS += -DG6_DEBUG=1
endif
Glass6SB_FRAMEWORKS = Foundation UIKit CoreGraphics QuartzCore ImageIO CoreText
Glass6SB_CODESIGN_FLAGS = -S -Hsha1

include $(THEOS_MAKE_PATH)/tweak.mk

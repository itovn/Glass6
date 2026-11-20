// Nút AssistiveTouch của Glass 6 (thành phần «assist»): nút nổi kéo thả được + bảng nút tuỳ biến, thay nút của iOS.
// Xem G6Assist.m.
#import <Foundation/Foundation.h>

void G6AssistInstall(void);

#if G6_DEBUG
// Công cụ thử: «menu 1|0» mở / đóng bảng nút, «do <mã chức năng>» chạy một chức năng, «tap» / «double» / «hold» giả thao tác
// trên nút, «state» ghi trạng thái.
void G6AssistDebug(NSString *arg);
#endif

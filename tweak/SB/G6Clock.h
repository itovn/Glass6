// Biểu tượng Đồng hồ sống (thành phần «clock»): mặt đồng hồ tự vẽ, kim giờ / phút / giây chạy theo giờ và múi giờ của máy —
// như iOS 7 trở đi. Xem G6Clock.m.
#import <UIKit/UIKit.h>

// Gắn các hàm thay thế + bắt đầu nghe cấu hình. Gọi sớm cùng G6IconsInstall (trước khi SpringBoard tạo ảnh biểu tượng).
void G6ClockInstall(void);

// G6Icons gọi khi SpringBoard xin ảnh biểu tượng của app `bundleID` ở định dạng `format`: nếu đó là app Đồng hồ và thành phần
// đang bật thì trả ảnh đồng hồ tự vẽ (kim đứng ở 10:09:30 — dùng cho mọi chỗ ảnh tĩnh: thư mục, tìm kiếm…), cùng cỡ với
// `orig`. Không thì nil. Gọi được từ mọi luồng.
UIImage *G6ClockIconImage(NSString *bundleID, int format, UIImage *orig);

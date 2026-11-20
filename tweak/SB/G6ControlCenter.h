// Control Center (thành phần «control_center») — iOS 6 chưa có: bảng kính ở góc trên phải với các nút Máy bay, Wi-Fi,
// Bluetooth, khoá xoay, sáng / tối; thanh độ sáng, âm lượng; điều khiển nhạc. Mở bằng cách kéo từ mép trên xuống ở một phần
// ba bên phải màn hình (phần còn lại vẫn mở Trung tâm thông báo). Xem G6ControlCenter.m.
#import <Foundation/Foundation.h>

void G6ControlCenterInstall(void);

// Khoá / mở khoá xoay màn hình. Khoá theo hướng giao diện đang hiện: -[SBOrientationLockManager lock] lấy hướng của cảm biến,
// máy nằm phẳng trên bàn (hướng «ngửa mặt») thì nó không khoá được gì.
void G6SetRotationLocked(BOOL locked);
BOOL G6RotationLocked(void);
// Cho công cụ thử: hiện / ẩn bảng không qua cử chỉ.
void G6ControlCenterSetVisible(BOOL visible, BOOL animated);
#if G6_DEBUG
// Cho công cụ thử (bảng phải đang mở): «state» = ghi trạng thái các nút / thanh trượt vào nhật ký; «tap <tên>» = bấm nút
// (airplane, wifi, bluetooth, rotation, dark, prev, play, next); «brightness <0–1>», «volume <0–1>» = kéo thanh trượt.
void G6ControlCenterDebug(NSString *arg);
#endif

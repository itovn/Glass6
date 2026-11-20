// Hộp thoại (UIAlertView — thành phần «alerts»): hộp xanh bóng của iOS 6 → tấm kính, chữ phông Inter theo sáng / tối, nút
// dạng viên bo tròn. Là mã mức UIKit (không phụ thuộc SpringBoard) nên để ở Common: Đợt 2 nạp vào app cũng dùng tệp này.
// Xem G6Alert.m.
// Cũng đổi nút và chữ của bảng chọn (UIActionSheet — cùng họ nút với hộp thoại).
#import <objc/objc.h>

void G6AlertInstall(void);
// Bảng chọn (khác hộp thoại) nằm ngay trong cửa sổ của app. App đang được «vẽ lại» (Glass6UI, D32) dựng mọi thứ theo bảng
// màu sáng rồi để bộ lọc của cửa sổ lo phần tối → ở đó bảng chọn phải hỏi «tối hay sáng» theo cách của app, không theo chế
// độ thật (không thì chữ sáng của bảng màu tối rơi lên nền sáng: tiêu đề mất hút, chữ nút nhạt). Không đặt thì dùng chế độ
// thật (SpringBoard, app thường).
void G6AlertSetSheetDarkProvider(BOOL (*provider)(void));

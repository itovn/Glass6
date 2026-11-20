// Biểu tượng app của màn hình chính (thành phần «icons»): hình bo góc liên tục, bỏ lớp bóng kính của iOS 6, viền sáng mảnh,
// bóng đổ mềm; nền biểu tượng thư mục thành ô kính. Xem G6Icons.m.

#import <UIKit/UIKit.h>

// Cho thành phần khác tự vẽ ảnh biểu tượng (vd Đồng hồ) rồi đưa qua cùng khâu cắt hình. Cả ba gọi được từ mọi luồng.
// Cạnh (điểm ảnh) của vùng chứa biểu tượng trong ảnh định dạng `format`; 0 = định dạng này không phải ô vuông, đừng đụng.
int G6IconContentPixels(int format, CGFloat scale);
// Vùng đó tính bằng điểm, trong toạ độ của ảnh (gốc trên trái). Rỗng nếu không biết.
CGRect G6IconContentRect(int format, CGFloat scale);
// Ảnh vuông chưa cắt `src` → ảnh biểu tượng hoàn chỉnh đúng cỡ SpringBoard chờ: kiểu mới của Glass 6 nếu «Biểu tượng kiểu
// mới» đang bật, không thì nhờ UIKit cắt theo kiểu gốc của máy (không phủ lớp bóng kính).
UIImage *G6IconImageFromSource(CGImageRef src, int format, CGFloat scale);

// Gắn các hàm thay thế. Gọi SỚM (lúc nạp, trước khi SpringBoard tạo ảnh biểu tượng đầu tiên) để ảnh ra đúng kiểu ngay từ
// đầu, khỏi tạo hai lần.
void G6IconsInstall(void);
// Sau khi quét xung đột xong: bắt đầu nghe cấu hình; trạng thái bật / tắt lệch với lúc gắn thì tạo lại mọi ảnh.
void G6IconsStart(void);

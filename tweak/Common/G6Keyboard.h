// Bàn phím tối ở chế độ tối (thành phần «keyboard», khoá `featKeyboard`) — dùng chung cho SpringBoard (ô Tìm kiếm) và các app
// trong phạm vi của Glass6UI. Xem G6Keyboard.m. Chỉ gọi trên luồng chính.
#import <Foundation/Foundation.h>

// Đọc cấu hình hiện hành rồi bật / tắt: bàn phím đang hiện đổi ngay. Gọi lại mỗi lần cấu hình đổi.
void G6KeyboardApply(void);

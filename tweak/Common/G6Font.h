// Phông Inter (giấy phép OFL) đóng kèm gói ở /Library/Application Support/Glass6/Fonts — dùng cho chữ do Glass 6 vẽ hoặc
// đổi kiểu (nhãn biểu tượng, đồng hồ màn khoá, Control Center…). Đăng ký với CoreText cho riêng tiến trình đang chạy.
#import <UIKit/UIKit.h>

typedef enum {
    G6FontRegular,
    G6FontMedium,
    G6FontSemiBold,
    G6FontBold,
} G6FontWeight;

// Phông Inter cỡ `size`. Thiếu tệp phông / đăng ký hỏng thì trả phông hệ thống (đậm cho SemiBold / Bold). Gọi được từ mọi luồng.
UIFont *G6Font(G6FontWeight weight, CGFloat size);
// Inter có dùng được không (đã đăng ký và UIKit tìm thấy)
BOOL G6FontAvailable(void);

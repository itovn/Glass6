// Âm lịch Việt Nam cho app Lịch: số liệu do lõi tính (lệnh «lunar.month» / «lunar.day», core/crates/g6-core/src/lunar.rs —
// thuật toán Hồ Ngọc Đức, múi giờ +7), ở đây chỉ gói lại cho phần vẽ và giữ bộ đệm theo tháng. Gọi trên luồng chính.
#import <UIKit/UIKit.h>

typedef struct {
    BOOL valid;    // NO: ngoài 1800–2199 hoặc lõi không trả lời
    int ld, lm, ly;
    BOOL leap;     // tháng nhuận
    BOOL good;     // ngày hoàng đạo
    BOOL fest;     // có lễ âm lịch (Tết, Rằm tháng Giêng, Giỗ Tổ, Phật đản, Đoan ngọ, Vu lan, Trung thu, ông Công ông Táo)
} G6LunarCell;

// Ngày âm của một ngày dương (tháng 1–12)
G6LunarCell G6LunarCellFor(int d, int m, int y);
// Chữ ngắn dưới số ngày dương: «15»; mùng 1 (hoặc `withMonth`) thì kèm tháng «1/10», tháng nhuận thêm «N» («1/4N»)
NSString *G6LunarShortText(G6LunarCell c, BOOL withMonth);
// Chi tiết một ngày (khoá như DayDetail của lõi: ld lm ly leap month_days can_chi_day can_chi_month can_chi_year than good
// tiet_khi hours festival). nil nếu ngày sai / lõi không trả lời.
NSDictionary *G6LunarDayDetail(int d, int m, int y);
// Thứ trong tuần: 0 = Chủ nhật … 6 = thứ Bảy
int G6LunarWeekday(int d, int m, int y);

// Màu chung của phần âm lịch (bảng màu SÁNG — phần tối do bộ lọc của cửa sổ lo, xem G6UISkin.h)
UIColor *G6LunarGoodColor(void);     // ngày hoàng đạo: vàng cam
UIColor *G6LunarFestColor(void);     // ngày lễ: đỏ
UIColor *G6LunarAccentColor(void);   // màu nhấn của app Lịch (đỏ kiểu iOS 26): hôm nay, mũi tên

// Khung «vẽ lại app giả vật liệu» của Glass6UI (Đợt 3) — xem G6UISkin.m. Mỗi app một tệp G6UIApp<Tên>.m khai bảng thay hình.
#import <UIKit/UIKit.h>

// Một hình trong bộ vân của app được thay bằng gì. Ảnh thay thế luôn CÙNG CỠ với ảnh gốc (bố cục của app tính theo cỡ ảnh).
typedef enum {
    G6SkinClear = 0,    // trong suốt: bóng đổ, mép giấy rách, túi da, đường khâu…
    G6SkinBackdrop,     // nền sau cùng của app (thay da / vải)
    G6SkinSurface,      // mặt giấy phẳng, phủ kín ảnh
    G6SkinCard,         // thẻ nổi trên nền: mặt giấy bo góc + viền mảnh, lùi vào so với mép ảnh (tham số: lề, bán kính)
    G6SkinBar,          // thanh trên: mặt thanh + nét mảnh ở mép dưới
    G6SkinBarBottom,    // thanh dưới: mặt thanh + nét mảnh ở mép trên
    G6SkinButton,       // nút trên thanh: viên bo tròn
    G6SkinButtonDown,   // nút đang bấm
    G6SkinField,        // ô tìm kiếm: viên xám nhạt
    G6SkinGlyph,        // hình một màu (mũi tên, thùng rác…): giữ hình, tô màu chữ phụ
    G6SkinSelection,    // dòng đang chọn: viên bo góc mờ
    G6SkinPressed,      // vầng dưới nút lúc bấm: đĩa mờ
    G6SkinHairline,     // nét mảnh phủ kín ảnh (vạch ngăn)
    G6SkinHighlight,    // lớp phủ mờ kín ảnh (dải «đang chọn» kéo giãn được)
    G6SkinChip,         // viên nhỏ bo góc phủ kín ảnh, mờ + viền mảnh (núm của thanh trượt ngày…)
    // Cộng thêm cờ này cho hình nằm trong một «vùng vốn tối» (xem G6UISkinInvertRegion): ảnh được vẽ bằng màu ĐẢO của bảng
    // màu sáng, để qua bộ lọc của vùng nó hiện ra đúng màu như các hình khác.
    G6SkinInverted = 0x100,
} G6SkinKind;

// Hình mà các kiểu chung không tả được: app tự vẽ. Nhận ảnh gốc, trả ảnh thay thế CÙNG CỠ (theo bảng màu SÁNG; nil = giữ ảnh
// gốc). Khối lệnh chỉ được gọi lúc hình được nạp (UIKit đã khởi động xong), không phải lúc khai.
typedef UIImage * (^G6SkinMaker)(UIImage *original);

// Khai bảng thay hình của app này: tên hình (không đuôi «.png», không «~ipad») → @(G6SkinKind), hoặc @[@(kind), @(lề),
// @(bán kính)] cho G6SkinCard, hoặc một khối G6SkinMaker. Chỉ làm việc của runtime — gọi được từ hàm khởi tạo của thư viện.
// Gọi nhiều lần thì gộp bảng.
void G6UISkinRegister(NSDictionary *images);
// Bật / tắt phần vẽ lại của app này. Hình app đã nạp rồi thì giữ nguyên tới lần mở app sau; bộ lọc tối đổi ngay.
void G6UISkinSetActive(BOOL active);
BOOL G6UISkinActive(void);
// Áp bộ lọc tối lên các cửa sổ của app theo chế độ hiện hành (gọi lại mỗi lần cấu hình đổi).
void G6UISkinApply(void);
// View chứa ảnh thật (ảnh chân dung, ảnh đính kèm): đảo ngược lần nữa để ảnh giữ đúng màu dưới bộ lọc tối của cửa sổ.
// keep = NO: view này thôi giữ màu (vd ô ảnh chân dung đang hiện hình bóng mặc định — để nó tối theo như mọi thứ khác).
void G6UISkinKeepColors(UIView *view, BOOL keep);
// Màu nền chung của app đang vẽ lại (cho view nền mà app tô bằng màu chứ không bằng hình)
UIColor *G6UISkinBackdropColor(void);
// «Vùng vốn tối»: phần giao diện app vẽ chữ SÁNG trên nền tối (cột trái của Lời nhắc…). Vùng này mang bộ lọc đảo suốt lúc
// đang vẽ lại: ở chế độ sáng nó thành chữ tối trên nền sáng như phần còn lại; ở chế độ tối, bộ lọc của cửa sổ đảo thêm lần
// nữa nên nó về đúng dạng gốc (chữ sáng trên nền tối). Hình thay thế nằm trong vùng phải khai kèm cờ G6SkinInverted.
void G6UISkinInvertRegion(UIView *view);

// Bộ lọc màu «đảo sáng tối, giữ sắc màu» (CAFilter; nil nếu máy không có) — cho nơi khác cần đảo riêng một view (ô tự vẽ của
// bảng thường ở chế độ tối — G6UITables.m). Áp hai lần thì về màu gốc.
id G6UISkinInvertFilter(void);

// «Đang ở chế độ tối» theo cách các thành phần chuẩn của Glass6UI phải hiểu: app đang được vẽ lại bằng khung này thì luôn là
// NO — mọi thứ trong app dựng theo bảng màu SÁNG, phần tối do bộ lọc của cửa sổ lo.
BOOL G6UIDark(void);

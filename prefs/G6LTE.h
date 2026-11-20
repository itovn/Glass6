// Bật 4G (LTE dữ liệu) cho SIM MobiFone, Viettel, VinaPhone trên iPhone 5 iOS 6 — phần của bảng Cài đặt: chạy công cụ quyền
// root /usr/libexec/glass6/g6lte và đọc trạng thái mạng di động qua CoreTelephony. Xem lte/g6lte.c, docs/DECISIONS.md D47.
#import <Foundation/Foundation.h>

#define G6_LTE_TOOL "/usr/libexec/glass6/g6lte"
// Có tệp này = Glass 6 đã điền cấu hình MMS của MobiFone (SIM MobiFone, gói gốc Unknown không có MMS). «g6lte off» gỡ đúng hai giá trị
// đó khỏi com.apple.mms_override rồi xoá dấu (lte/g6lte.c — cùng giá trị)
#define G6_LTE_MMS_MARKER "/var/mobile/Library/Glass6/lte-mms-injected"
#define G6_MOBIFONE_MMSC "http://203.162.21.114/mmsc"
#define G6_MOBIFONE_MMS_PROXY "203.162.21.114:3130"

// Chạy «g6lte <lệnh>» và chờ xong (gọi ở luồng nền với on / off: mất chừng một phút). Trả mã thoát; -1 = không chạy được.
int G6LTERun(NSString *command, NSString **output);
// Có công cụ (chủ root + bit setuid) không
BOOL G6LTEAvailable(void);
// 4G đang bật (ít nhất một trong ba nhà mạng đang dùng gói 4G của Glass 6)
BOOL G6LTEIsOn(void);
// Lời báo (đã dịch) cho mã thoát khác 0 của g6lte
NSString *G6LTEErrorText(int code);
// Một dòng mô tả mạng di động đang dùng: «MobiFone · 4G (LTE)», «Viettel · 3G», «Không có SIM»…
NSString *G6CellularSummary(void);

// ---- APN / MMS (trang «Mạng dữ liệu di động» của iOS) ----
// Gói 4G mang APN / MMS của gói nguồn LTE (3 Hồng Kông — xem lte/g6lte.c). Bảng Cài đặt trả lại như trước khi bật, ghi qua
// chính EdgeSettingsController của iOS (như người dùng tự sửa). Gọi ở luồng chính.
// Mã MCC+MNC của SIM đang lắp («45201»…); nil nếu chưa đọc được
NSString *G6SIMCode(void);
// Các ô APN / MMS đang hiện (mã dòng → chữ); nil nếu không đọc được trang
NSDictionary *G6APNSnapshot(void);
// Ghi lại các ô theo `values` (thiếu ô nào thì lấy giá trị gốc của nhà mạng `sim`); trả số ô đã đổi, -1 nếu không ghi được
int G6APNRestore(NSDictionary *values, NSString *sim);
// Như trên nhưng đợi mạng ổn định (đăng ký xong, bám LTE; tối đa 90 giây) rồi mới ghi, kiểm lại ở +5 / +20 / +40 giây và ghi lại
// ô bị đổi về giá trị của gói; xong thì làm mới dữ liệu di động nếu có ô đổi và gọi `done` (số ô đã ghi) ở luồng chính
void G6APNRestoreSettled(NSDictionary *values, NSString *sim, void (^done)(int changed));
// 4G đang bật cho SIM này mà trang APN còn mang giá trị của gói nguồn (vd vừa đổi SIM) → trả về giá trị gốc của nhà mạng (chạy
// sau, xem G6APNRestoreSettled). Trả 1 nếu đã lên lịch trả, 0 nếu không cần
int G6APNRepairIfForeign(void);
// Tắt rồi bật lại dữ liệu di động (nếu đang bật) để ngữ cảnh dữ liệu dùng APN mới — chạy ở luồng nền
void G6CellularDataRefresh(void);
// Sau khi tắt 4G: gỡ cấu hình MMS mà Glass 6 đã điền cho SIM MobiFone (nếu ô còn đúng giá trị đó)
void G6APNClearInjected(NSString *sim);

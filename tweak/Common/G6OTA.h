// Cập nhật OTA của Glass 6 — phần dùng chung cho SpringBoard (tự kiểm bản mới) và bảng Cài đặt (kiểm, tải, cài).
// Việc nặng nằm ở hai công cụ ngoài (docs/THIET-KE.md mục 10):
//   /usr/bin/glass6ctl              quyền mobile — hỏi GitHub, tải gói + chữ ký qua HTTPS (lõi Rust g6-ctl)
//   /usr/libexec/glass6/g6update    setuid root — kiểm chữ ký số của gói rồi cài, khởi động lại SpringBoard
// Tệp này chỉ chạy chúng, đọc kết quả (mỗi dòng stdout của glass6ctl là một dòng «progress …» hoặc một dòng JSON) và giữ vài
// hàm nhỏ: so số bản, đọc tệp trạng thái, lời báo lỗi. Không nạp vào app (Glass6UI không dịch tệp này).
#import <Foundation/Foundation.h>

#define G6_OTA_CTL "/usr/bin/glass6ctl"
#define G6_OTA_HELPER "/usr/libexec/glass6/g6update"
// Kết quả lượt kiểm thành công gần nhất (glass6ctl ghi)
#define G6_OTA_STATE "/var/mobile/Library/Glass6/update.json"

// Một lượt chạy glass6ctl: giữ pid để huỷ giữa chừng
@interface G6OTATask : NSObject
@property (atomic, assign) pid_t pid;
@property (atomic, assign) BOOL cancelled;
// Dừng công cụ (đang tải thì bỏ dở). Gọi từ luồng nào cũng được.
- (void)cancel;
@end

// Chạy `glass6ctl <args…>` và CHỜ nó xong (gọi ở luồng nền). `onLine` nhận từng dòng stdout ngay khi có (trên luồng gọi).
// Trả mã thoát; -1 = không chạy được.
int G6OTARun(NSArray *args, G6OTATask *task, void (^onLine)(NSString *line));
// Một dòng JSON của glass6ctl → từ điển (nil nếu không phải JSON)
NSDictionary *G6OTAParse(NSString *line);
// Chạy `glass6ctl update check` (chờ xong) → kết quả: @{@"ok": @YES, @"latest", @"newer", @"installable", @"notes"…} hoặc
// @{@"ok": @NO, @"error", @"detail"…}
NSDictionary *G6OTACheck(NSString *currentVersion);
// Bản `a` mới hơn bản `b` (so từng số: «1.2.10» > «1.2.9»; đuôi «-1+debug» bỏ qua)
BOOL G6OTANewer(NSString *a, NSString *b);
// Lượt kiểm gần nhất còn ghi trong tệp trạng thái, nếu nó nói có bản mới hơn `currentVersion`; không thì nil
NSDictionary *G6OTAPending(NSString *currentVersion);
// Chạy g6update (chờ nó kiểm xong — vài giây; phần cài chạy nền rồi máy tự khởi động lại SpringBoard). Trả mã thoát của
// g6update: 0 = đã nhận, đang cài; -1 = không chạy được; còn lại xem helper/g6update.c. Chỉ app Cài đặt và SpringBoard gọi được.
int G6OTAInstallPackage(NSString *debPath, NSString *sigPath);
// Có công cụ cài chưa (chủ root + bit setuid)
BOOL G6OTAHelperReady(void);
// Lời báo lỗi (đã dịch) cho kết quả lỗi của glass6ctl
NSString *G6OTAErrorText(NSDictionary *result);
// Lời báo lỗi (đã dịch) cho mã thoát khác 0 của g6update
NSString *G6OTAInstallErrorText(int code);

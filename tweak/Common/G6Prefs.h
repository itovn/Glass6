// Cấu hình: đọc tệp plist do Cài đặt ghi, đưa cho lõi kiểm + điền mặc định, giữ bản đã kiểm. Nghe thông báo Darwin
// «vn.glass6/prefs» để đọc lại khi người dùng đổi trong Cài đặt.
#import <Foundation/Foundation.h>

// Tên miền cấu hình = tên tệp trong /var/mobile/Library/Preferences
#define G6_PREFS_DOMAIN "vn.glass6"
#define G6_PREFS_NOTE "vn.glass6/prefs"

// Gửi trên luồng chính sau mỗi lần cấu hình đổi
extern NSString *const G6ConfigDidChangeNotification;

// Đọc cấu hình lần đầu và bắt đầu nghe thay đổi. Gọi sau G6CoreLoad.
void G6PrefsStart(void);
// Cấu hình đã qua lõi (khoá như struct Config của g6-core: enabled, appearance, blur, features…)
NSDictionary *G6Config(void);
BOOL G6Enabled(void);
// Một thành phần (tên khoá trong `features`: dock, icons…) có được bật không — đã trừ thành phần bị chặn vì xung đột.
BOOL G6Feature(NSString *name);
// Đang ở chế độ tối (theo cấu hình + giờ máy)
BOOL G6IsDark(void);
// Thành phần phải tắt vì có gói xung đột (bộ gác đặt sau khi quét)
void G6SetBlockedFeatures(NSArray *names);

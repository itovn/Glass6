// Chặn SpringBoard sập vì chữ thông báo có nửa cặp surrogate (nửa emoji) — mọi máy.
//
// Lý do (iPhone 5 iOS 6.1.4, 19/11 và 21/11/2026 — D51): `-[SBPushStore saveLocalNotification:forBundleID:]` gọi
// `+[SBSystemLocalNotificationAlert localizedStringFromKey:defaultValue:inBundle:arguments:]`; khi bundle của app trả được chữ,
// hàm này chuyển sang một hàm định dạng của SpringBoard làm `[chữ UTF8String]` rồi đọc byte đầu KHÔNG kiểm NULL. Chữ có nửa
// emoji (app cắt `substringToIndex:` giữa cặp surrogate — GramMini / Roza từng như vậy) đổi sang UTF-8 không được → NULL →
// SIGSEGV ở luồng chính → MobileSubstrate đưa máy vào safe mode. Lỗi sẵn của iOS 6, không phải mã của Glass 6, nhưng app nào
// mắc lỗi cắt chữ cũng làm máy sập nên Glass 6 chặn luôn.
//
// Cách làm (runtime ObjC, thiếu lớp / hàm thì bỏ qua): móc
//   +[SBSystemLocalNotificationAlert localizedStringFromKey:defaultValue:inBundle:arguments:] — đúng chỗ sập, chung cho mọi đường
//      (thông báo cục bộ, hộp cảnh báo, khoá «loc-key» của thông báo đẩy): lọc khoá, chữ mặc định, các tham số và kết quả;
//   -[SBPushStore saveLocalNotification:forBundleID:] và +[SBSystemLocalNotificationAlert presentWithLocalNotification:
//      application:] — lọc alertBody / alertAction của UILocalNotification trước khi SpringBoard lưu / hiện.
// «Lọc» = thay nửa surrogate lẻ bằng U+FFFD; chữ hợp lệ (gần như luôn luôn) đi qua nguyên vẹn, chỉ tốn một lần `UTF8String`.
#import <Foundation/Foundation.h>

// Gọi trong constructor của SpringBoard. Gọi lại không sao.
void G6NotifGuardInstall(void);

#if G6_DEBUG
// Bản thử: «» = gọi localizedStringFromKey: (đã móc) với chữ có nửa emoji; «raw» = gọi hàm GỐC của SpringBoard (bỏ qua chốt —
// SpringBoard sẽ sập như lỗi thật, chỉ dùng trên máy thử); «save <bundle id>» = lưu một UILocalNotification có nửa emoji qua
// SBPushStore rồi xoá lại. Trả mô tả để ghi nhật ký.
NSString *G6NotifGuardDebug(NSString *arg);
#endif

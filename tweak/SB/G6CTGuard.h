// Giữ cho các callback CoreTelephony mà SpringBoard đăng ký luôn chạy ở luồng chính (chỉ iPhone — iPad không có CommCenter).
//
// Lý do (iPhone 5 iOS 6.1.4, đo 17/11 và 20/11/2026): SpringBoard văng «this call must be made on the main thread» trong
// _TelephonyCapabilitiesChanged (SBTelephonyManager.m) khi thông báo của CTTelephonyCenter đến trên luồng
// com.apple.NSURLConnectionLoader thay vì luồng chính → MobileSubstrate đưa máy vào safe mode. Không phải mã của Glass 6 gây
// ra (backtrace chỉ có CoreTelephony → SpringBoard), nhưng các thông báo «khả năng di động đã đổi» đến dồn dập mỗi lần
// CommCenter nạp lại gói nhà mạng — đúng việc «Bật 4G» (lte/g6lte.c) làm — nên Glass 6 phải chặn đường văng này.
//
// Cách làm: móc CTTelephonyCenterAddObserver (MSHookFunction của Substrate, tra bằng dlsym — không có thì bỏ qua). Callback
// nằm trong chính tệp SpringBoard được thay bằng hàm đệm: đang ở luồng chính thì gọi thẳng như cũ; ở luồng khác thì giữ
// name / userInfo rồi chuyển sang luồng chính, BẤT ĐỒNG BỘ (đồng bộ có thể kẹt khi luồng chính đang chờ chính luồng mạng đó).
// Callback của thư viện / tweak khác giữ nguyên.
#import <Foundation/Foundation.h>

// Gọi sớm trong constructor (trước khi SpringBoard tạo SBTelephonyManager). Gọi lại không sao.
void G6CTGuardInstall(void);

#if G6_DEBUG
// Bản thử: không tham số = liệt kê các thông báo đã bọc; có = gọi hàm đệm TỪ MỘT LUỒNG PHỤ cho thông báo đầu tiên có tên chứa
// `part` (giả đúng tình huống từng làm SpringBoard văng). Trả mô tả để ghi nhật ký.
NSString *G6CTGuardDebugFire(NSString *part);
#endif

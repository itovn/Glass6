// Ngôn ngữ hiển thị của Glass 6: tiếng Việt (gốc — mọi chuỗi trong mã viết bằng tiếng Việt) hoặc tiếng Anh.
//
// Một bảng dịch duy nhất Việt → Anh (`prefs/Resources/Strings-en.plist`, sinh bằng `tools/gen_strings.py` từ
// `data/strings-en.txt`), dùng chung cho bảng Cài đặt và các chuỗi của tweak trên SpringBoard. Không dùng cơ chế `.lproj` của
// hệ thống: nó chỉ theo ngôn ngữ của máy, còn ở đây người dùng chọn được (khoá `language`: «auto» / «vi» / «en»; «auto» =
// máy đặt tiếng Việt thì tiếng Việt, còn lại tiếng Anh) và thử được mà không phải đổi ngôn ngữ của máy.
#import <Foundation/Foundation.h>

// @"vi" hoặc @"en"
NSString *G6Language(void);
// Đọc lại lựa chọn ngôn ngữ (gọi khi cấu hình đổi)
void G6LangReload(void);
// Chuỗi tiếng Việt → chuỗi của ngôn ngữ đang dùng; không có bản dịch thì trả nguyên chuỗi
NSString *G6L(NSString *text);
// Chuỗi số do lõi định dạng kiểu Việt («1,2 GB»): tiếng Anh thì đổi dấu phẩy thập phân thành dấu chấm
NSString *G6LDecimal(NSString *text);

// Móc hàm bằng runtime của ObjC (không Logos, không cần Substrate): lớp / hàm tra lúc chạy, thiếu thì trả NO để tính năng
// tự bỏ qua. Hàm thay thế PHẢI gọi lại `*orig`.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// Thay cài đặt của `sel` trên lớp `cls`. Hàm chỉ có ở lớp cha thì thêm bản ghi đè vào `cls` (không sửa lớp cha).
// NO nếu thiếu lớp hoặc thiếu hàm.
BOOL G6Hook(Class cls, SEL sel, IMP repl, IMP *orig);
// Như trên, lớp tra theo tên.
BOOL G6HookNamed(const char *cls, SEL sel, IMP repl, IMP *orig);

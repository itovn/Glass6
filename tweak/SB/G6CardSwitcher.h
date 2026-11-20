// Khay đa nhiệm dạng thẻ của iPhone (kiểu iOS 26) — thay cho dải biểu tượng ở đáy màn hình của iOS 6; thuộc thành phần
// «switcher» (khoá `featSwitcher`) + khoá `switcherCards`. Chỉ có trên iPhone. Xem G6CardSwitcher.m.
#import <Foundation/Foundation.h>

void G6CardSwitcherInstall(void);
// Mở / đóng khay (mở: chỉ khi thành phần đang bật và máy đang đứng)
void G6CardSwitcherSetVisible(BOOL visible, BOOL animated);
#if G6_DEBUG
// Lệnh thử: «1» / «0» mở / đóng; «tap n» chạm thẻ thứ n; «quit n» thoát app của thẻ thứ n (n = 0 là thẻ mới nhất); «list»
void G6CardSwitcherDebug(NSString *arg);
#endif

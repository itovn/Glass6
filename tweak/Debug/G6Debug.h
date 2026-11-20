// Công cụ thử — CHỈ có trong bản thử (không FINALPACKAGE=1). Nhận lệnh từ SSH:
//   echo '<lệnh>' > /var/mobile/Library/Glass6/cmd.txt && cblaunch post vn.glass6/debug
// Tệp lệnh phải do root ghi. Kết quả ghi vào /var/mobile/Library/Glass6/. Xem G6Debug.m.
#import <Foundation/Foundation.h>

void G6DebugStart(void);

// Giả lập ngón tay: «tap x y [giữ ms]», «drag x1 y1 x2 y2 [ms] [giữ ms]» — G6DebugTouch.m
void G6DebugTouch(NSString *command, NSString *arg);

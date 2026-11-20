// Nhật ký của Glass 6: NSLog + tệp G6_DIR/glass6.log (giới hạn cỡ, đầy thì đổi thành glass6.log.1).
#import <Foundation/Foundation.h>

void G6Log(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

// Ghi / gộp trạng thái đang chạy vào G6_DIR/status.plist — bảng Cài đặt đọc tệp này để hiện «đang chạy / đã tự tắt…».
void G6StatusSet(NSDictionary *values);

// Thời gian đơn điệu tính bằng mili giây (đo thời gian dựng kính).
double G6NowMs(void);

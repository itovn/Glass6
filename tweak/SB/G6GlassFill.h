// Phủ kính lên một view nền của SpringBoard (dải vải SBLinenView của thư mục, khay đa nhiệm…): ẩn các view con sẵn có của
// nó và đặt bên trong một UIImageView kính phủ kín, nền là hình nền màn hình chính đã mờ đúng chỗ view nằm trên màn hình.
// Kính nằm TRONG view nền nên SpringBoard đổi khung / độ mờ của nền thế nào kính theo thế ấy.
#import <UIKit/UIKit.h>

// active = YES: phủ / cập nhật (không gì đổi thì không dựng lại; view chưa vào cửa sổ thì chưa dựng — gọi lại khi đã vào).
// active = NO: gỡ kính, hiện lại các view con. Trả YES nếu `host` đang được phủ kính sau lời gọi. Chỉ dùng ở luồng chính.
BOOL G6GlassFill(UIView *host, BOOL active, NSString *surface);

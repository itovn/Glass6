// Các mục của thanh trạng thái (UIKit) — phần dùng chung giữa SpringBoard (tweak/SB/G6StatusBar.m) và các app
// (tweak/UI/G6UIStatusBar.m): giờ + mặt trăng «Không làm phiền» sang bên trái, hình pin vẽ lại (tia sét xanh lá khi cắm
// sạc), chữ Inter. Thanh trạng thái của iOS 6 do từng tiến trình tự vẽ nên muốn đâu cũng giống nhau thì tiến trình nào cũng
// phải gắn. Xem G6StatusItems.m. Chỉ gọi trên luồng chính.
#import <UIKit/UIKit.h>

// Gắn các hàm thay thế (một lần mỗi tiến trình). Chưa gọi G6StatusItemsSet thì mọi thứ còn y như gốc. Chỉ làm việc của
// runtime, không gọi vào UIKit → gọi được từ hàm khởi tạo của thư viện, trước UIApplicationMain (cùng với G6StatusItemsSet).
void G6StatusItemsInstall(void);
// Đặt trạng thái mong muốn. timeLeft: giờ + mặt trăng nằm bên trái; signalRight: cột sóng + biểu tượng mạng (Wi-Fi / 3G)
// dồn sang bên phải, sát pin (kiểu iOS 26 của iPhone); battery: hình pin vẽ lại; font: chữ Inter.
// Tuỳ chọn nào không gắn được hàm thì coi như NO. Trả qua con trỏ: các mục có phải đổi vùng không (layoutChanged), hình /
// chữ của các mục có đổi không (lookChanged) — bên gọi dùng để gọi G6StatusItemsRefresh.
void G6StatusItemsSet(BOOL timeLeft, BOOL signalRight, BOOL battery, BOOL font, BOOL *layoutChanged, BOOL *lookChanged);
// Trạng thái đang có hiệu lực
BOOL G6StatusItemsTimeLeft(void);
BOOL G6StatusItemsSignalRight(void);
BOOL G6StatusItemsBattery(void);
// Loại mục «dịch vụ» (tên nhà mạng / «Không có SIM») tra được lúc chạy; −1 = không tra được
int G6StatusItemsServiceType(void);
// Số loại của mục «Không làm phiền» (trăng khuyết) trên máy này; −1 nếu chưa tra ra
int G6StatusItemsQuietType(void);

// Thanh trạng thái của tiến trình này (nil nếu chưa được tạo) và view chứa các mục của nó
UIView *G6StatusBarView(void);
UIView *G6StatusBarForeground(void);
// Áp lên thanh đang hiện: relayout = có mục đổi vùng → cho thanh xếp lại từ dữ liệu đang có; rồi từng mục vẽ lại (phông,
// hình pin) và xếp lại theo bề rộng mới. Thanh chưa được tạo thì không làm gì.
void G6StatusItemsRefresh(BOOL relayout);
// Bản thử: loại mục, vùng, các mục đang có và khung của chúng
NSString *G6StatusItemsDescribe(void);

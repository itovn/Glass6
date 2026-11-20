// Thanh trạng thái của SpringBoard — màn hình chính, màn khoá, khay đa nhiệm (thành phần «status_bar»): bỏ dải nền đen mờ,
// chữ và biểu tượng trắng rõ, phông Inter; giờ + mặt trăng nằm bên trái kiểu iPadOS; hình pin vẽ lại (tia sét xanh khi sạc);
// ẩn chữ «Không có SIM». Thanh trạng thái bên trong từng app do chính app vẽ — không đụng ở đây (riêng việc ẩn «Không có
// SIM» làm ở nguồn dữ liệu nên app nào cũng theo). Xem G6StatusBar.m.
#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

// Gửi (luồng chính, đã gom) sau khi các mục của thanh trạng thái được xếp lại — thứ nằm chen giữa thanh (dải hiệu suất)
// nghe để tính lại chỗ trống.
extern NSString *const G6StatusBarDidReflowNotification;

void G6StatusBarInstall(void);
// Giữa thanh trạng thái có đang trống không (giờ đã dời sang trái, không mục nào nằm vắt qua tâm). YES thì trả mép phải của
// cụm mục bên trái và mép trái của cụm mục bên phải (toạ độ của thanh = toạ độ ngang của màn hình chính).
BOOL G6StatusBarCenterFree(CGFloat *leftEdge, CGFloat *rightEdge);
// Bản thử: loại mục, vùng, trạng thái SIM, các mục đang hiện và khung của chúng.
NSString *G6StatusBarDebugState(void);

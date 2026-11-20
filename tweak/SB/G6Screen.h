// «Có ai đang nhìn màn hình không»: máy khoá / mở khoá, màn hình tắt / sáng. Dùng chung cho các thành phần chỉ nên chạy khi
// có người nhìn (kim đồng hồ sống, dải hiệu suất). Xem G6Screen.m.
#import <Foundation/Foundation.h>

// Gửi trên luồng chính sau mỗi lần khoá / mở khoá / tắt / sáng màn hình — bên nghe hỏi lại G6ScreenAwake().
extern NSString *const G6ScreenStateDidChangeNotification;

// Máy đang mở khoá và màn hình đang sáng.
BOOL G6ScreenAwake(void);
// Gắn hàm theo dõi vào SBAwayController. Gọi nhiều lần được (chỉ gắn một lần).
void G6ScreenWatchInstall(void);

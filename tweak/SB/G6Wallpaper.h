// Hình nền màn hình chính đã làm mờ — nền chung cho các tấm kính nằm trên màn hình chính (dock, thư mục mở…).
// Dựng một lần, giữ tới khi xoay máy / đổi hình nền / đổi cấu hình. Chỉ dùng ở luồng chính.
#import "G6Glass.h"

// Gửi (luồng chính) khi nền đã cũ và tấm kính nào dùng nó nên dựng lại: đổi hình nền, hình nền vừa vào cửa sổ (lần mở khoá
// đầu sau khi SpringBoard lên), đổi cấu hình.
extern NSString *const G6WallpaperDidChangeNotification;

// Gắn hàm theo dõi hình nền. Gọi một lần, trước các thành phần dùng nền.
void G6WallpaperInstall(void);
// Nền mờ của hình nền màn hình chính, theo hệ toạ độ khung hình. Hình nền đang hiện thì vẽ đúng thứ trên màn hình; không
// (đang ở trong app, máy còn ở màn khoá) thì tự vẽ từ ảnh của hình nền. nil nếu chưa có hình nền.
G6Backdrop *G6WallpaperBackdrop(void);
// Vẽ + làm mờ một view hình nền bất kỳ (vd hình nền màn khoá) theo hướng giao diện hiện tại; không nhớ lại — bên gọi tự giữ.
G6Backdrop *G6WallpaperRender(UIView *wallpaperView);
// Số tăng mỗi lần nền cũ đi — để bên dùng biết ảnh mình dựng còn đúng không.
NSUInteger G6WallpaperGeneration(void);

// Các thành phần giao diện của Glass6UI (nạp vào app). Mỗi hàm «Apply» gọi được nhiều lần: đọc cấu hình hiện hành rồi tự
// bật / tắt / dựng lại phần của mình. Gọi trên luồng chính.
#import <UIKit/UIKit.h>

#import "G6UISkin.h"

// `allowed`: chính sách của lõi cho app này (lệnh «app.policy») — NO thì thành phần coi như tắt.
// Hai hàm đổi kiểu qua UIAppearance trả YES khi kiểu vừa đổi lúc app ĐANG chạy: bên gọi phải gọi G6UIRefreshAppearance().

// Thanh điều hướng, thanh công cụ, thanh thẻ, ô tìm kiếm (thành phần «bars») — G6UIBars.m
BOOL G6UIBarsApply(BOOL allowed);
// Công tắc, thanh trượt, nút chọn đoạn, thanh tiến độ (thành phần «controls») — G6UIControls.m
BOOL G6UIControlsApply(BOOL allowed);
// Bánh xe chọn: UIPickerView, UIDatePicker (cũng thuộc thành phần «controls») — G6UIPickers.m. Tự làm mới bánh xe đang hiện.
void G6UIPickersApply(BOOL allowed);
// Nền, ô và chữ của bảng kiểu nhóm (thành phần «tables») — G6UITables.m. Tự làm mới các bảng đang hiện.
void G6UITablesApply(BOOL allowed);
// Cho / không cho tô tối các bảng thường (không chia nhóm) của app này ở chế độ tối. Mặc định cho.
void G6UITablesSetPlainAllowed(BOOL allowed);
// Bảng thường có ô do app tự vẽ, ở chế độ tối: mặc định cả bảng được để sáng (không đổi được màu chữ app tự vẽ). Bật cờ này
// cho app đã thử: từng ô của bảng đó mang bộ lọc «đảo sáng tối, giữ sắc màu» → ô trắng chữ đen thành ô đen chữ sáng.
void G6UITablesSetInvertCustomCells(BOOL on);
// Gọi TRƯỚC G6UITablesApply lần đầu, cho app Cài đặt: cột trái (bảng thường trên nền dải màu) cũng đổi theo chế độ tối.
void G6UITablesSetSidebar(BOOL on);

// Biểu tượng các mục trong app Cài đặt (thành phần «settings_icons») — G6UISettingsIcons.m. Ngoài app Cài đặt thì không làm gì.
void G6UISettingsIconsApply(void);

// Thanh trạng thái trong app (thành phần «status_bar»): giờ + mặt trăng bên trái, hình pin vẽ lại, chữ Inter — G6UIStatusBar.m
void G6UIStatusBarApply(void);
// iPhone: thanh trạng thái phẳng vốn tô màu mặt thanh; một màn hình không có thanh điều hướng (bàn phím số…) báo màu nền của
// mình để thanh trạng thái liền với nó. nil = thôi, về màu mặt thanh. Gọi lúc màn đó hiện / ẩn.
void G6UIStatusBarSetOverride(UIColor *color);
// iPhone: app này luôn dùng thanh trạng thái phẳng, kể cả khi nó xin kiểu đen (app vốn tối được vẽ lại theo sáng / tối của máy)
void G6UIStatusBarSetForceFlat(BOOL force);

// Phần vẽ lại riêng cho từng app của Apple (thành phần «app_skins») — G6UIAppSkins.m chọn theo mã gói, mỗi app một tệp.
// Gọi SAU các hàm Apply của thanh và nút điều khiển (dùng lại mặt thanh, kiểu nút hiện hành của chúng).
void G6UIAppSkinsApply(NSString *bundleID);
// Gọi từ hàm khởi tạo của thư viện (chỉ việc của runtime): app nào có bảng thay hình thì khai ngay, trước khi app nạp hình.
void G6UIAppSkinsPrepare(NSString *bundleID);
// Gọi ở ĐẦU mỗi lượt đặt kiểu: chốt «app này có đang được vẽ lại không» trước khi các thành phần chuẩn hỏi G6UIDark().
void G6UIAppSkinsUpdate(NSString *bundleID);
// App Đồng hồ (com.apple.mobiletimer): iPad — thanh thẻ dưới cùng; iPhone — vẽ lại bằng khung chung — G6UIAppClock.m
void G6UIAppClockPrepare(void);
void G6UIAppClockApply(BOOL active);
// App Điện thoại (com.apple.mobilephone, iPhone): bàn phím số — G6UIAppPhone.m
void G6UIAppPhoneApply(BOOL active);
// App Máy tính (com.apple.calculator, iPhone): bàn phím + màn hình số — G6UIAppCalculator.m
void G6UIAppCalculatorApply(BOOL active);
// App La bàn (com.apple.compass, iPhone): đổi tại chỗ bộ hình của mặt la bàn — G6UIAppCompass.m
void G6UIAppCompassApply(BOOL active);
// App Ghi âm (com.apple.VoiceMemos, iPhone): micro, bảng điều khiển, đồng hồ VU — G6UIAppVoiceMemos.m
void G6UIAppVoiceMemosPrepare(void);
void G6UIAppVoiceMemosApply(BOOL active);
// App Ghi chú (com.apple.mobilenotes) — G6UIAppNotes.m
void G6UIAppNotesPrepare(void);
void G6UIAppNotesApply(BOOL active);
// App Lời nhắc (com.apple.reminders) — G6UIAppReminders.m
void G6UIAppRemindersPrepare(void);
void G6UIAppRemindersApply(BOOL active);
// App Lịch (com.apple.mobilecal) — G6UIAppCalendar.m
void G6UIAppCalendarPrepare(void);
void G6UIAppCalendarApply(BOOL active);
// App Danh bạ (com.apple.MobileAddressBook) — G6UIAppContacts.m
void G6UIAppContactsPrepare(void);
void G6UIAppContactsApply(BOOL active);
// App Ảnh (com.apple.mobileslideshow) — G6UIAppPhotos.m. Không dùng khung thay hình / bộ lọc (nội dung là ảnh của người dùng).
void G6UIAppPhotosApply(BOOL active);
// App Tin nhắn (com.apple.MobileSMS) — G6UIAppMessages.m: bong bóng phẳng, nền, cột danh sách, thanh nhập.
void G6UIAppMessagesApply(BOOL active);

// Thành phần «bars» có đang bật trong app này không, và đang ở bảng màu tối không — G6UIBars.m
BOOL G6UIBarsActive(void);
BOOL G6UIBarsDark(void);
// Mặt thanh phẳng theo bảng màu hiện hành, cao `height`, kéo giãn theo chiều ngang; nét mảnh ngăn với nội dung nằm ở mép trên
// (thanh dưới cùng) hoặc mép dưới (thanh trên cùng)
UIImage *G6UIBarSurfaceImage(CGFloat height, BOOL hairlineOnTop);
// Áp / gỡ kiểu nút chọn đoạn của Glass 6 trên MỘT nút mà app tự đặt ảnh riêng — G6UIControls.m
void G6UIControlsStyleSegmented(UISegmentedControl *control, BOOL dark);
void G6UIControlsRestoreSegmented(UISegmentedControl *control);

// Khung bảng nổi (UIPopoverController; trên iPad gồm cả bảng chọn) — đi cùng thành phần «bars» — G6UIPopover.m
void G6UIPopoverApply(BOOL allowed);

// Màu chữ / hình trên thanh theo kiểu hiện hành (đen nhạt ở chế độ sáng, trắng ở chế độ tối)
UIColor *G6UIBarTextColor(void);
// Độ sáng (0–1) của mặt thanh theo bảng màu hiện hành — để thứ nằm sát thanh (thanh trạng thái của iPhone) tô liền màu
CGFloat G6UIBarSurfaceWhite(void);
// Ảnh `image` tô lại bằng `color`, giữ độ đục từng điểm ảnh — G6UIBars.m
UIImage *G6UITintedImage(UIImage *image, UIColor *color);

// Bắt mọi view đang hiện nhận lại kiểu dáng UIAppearance (gỡ ra rồi gắn lại vào cửa sổ) — sau khi đổi kiểu lúc app đang chạy
void G6UIRefreshAppearance(void);

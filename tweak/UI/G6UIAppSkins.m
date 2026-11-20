// Phần vẽ lại riêng cho từng app của Apple (thành phần «app_skins», khoá `featAppSkins`).
//
// Kiểu chung của Glass6UI (thanh, bảng, nút) đi qua UIAppearance nên chỉ tới được những chỗ app dùng thành phần chuẩn và
// không tự đặt ảnh. Chỗ app tự vẽ bằng ảnh riêng thì phải xử theo từng app — mỗi app một tệp G6UIApp<Tên>.m, tệp này chỉ chọn
// theo mã gói. Tắt công tắc thì từng phần tự trả lại nguyên trạng.
#import "G6UI.h"

#import "G6Device.h"
#import "G6Prefs.h"

static BOOL G6AppSkinsWanted(void) {
    return G6Feature(@"apps") && G6Feature(@"app_skins");
}

void G6UIAppSkinsPrepare(NSString *bundleID) {
    if ([bundleID isEqualToString:@"com.apple.mobilenotes"]) G6UIAppNotesPrepare();
    else if ([bundleID isEqualToString:@"com.apple.reminders"]) G6UIAppRemindersPrepare();
    else if ([bundleID isEqualToString:@"com.apple.mobilecal"]) G6UIAppCalendarPrepare();
    else if ([bundleID isEqualToString:@"com.apple.MobileAddressBook"]) G6UIAppContactsPrepare();
    else if ([bundleID isEqualToString:@"com.apple.VoiceMemos"]) G6UIAppVoiceMemosPrepare();
    else if ([bundleID isEqualToString:@"com.apple.mobiletimer"]) G6UIAppClockPrepare();
    G6UIAppSkinsUpdate(bundleID);
}

void G6UIAppSkinsUpdate(NSString *bundleID) {
    // App không khai bảng thay hình thì hàm này không có tác dụng (khung chung tự giữ «không vẽ lại»)
    G6UISkinSetActive(G6AppSkinsWanted());
}

void G6UIAppSkinsApply(NSString *bundleID) {
    if (bundleID.length == 0) return;
    BOOL active = G6AppSkinsWanted();
    if ([bundleID isEqualToString:@"com.apple.mobiletimer"]) G6UIAppClockApply(active);
    else if ([bundleID isEqualToString:@"com.apple.mobilenotes"]) G6UIAppNotesApply(active);
    else if ([bundleID isEqualToString:@"com.apple.reminders"]) G6UIAppRemindersApply(active);
    else if ([bundleID isEqualToString:@"com.apple.mobilecal"]) G6UIAppCalendarApply(active);
    else if ([bundleID isEqualToString:@"com.apple.MobileAddressBook"]) G6UIAppContactsApply(active);
    else if ([bundleID isEqualToString:@"com.apple.mobileslideshow"]) G6UIAppPhotosApply(active);
    else if ([bundleID isEqualToString:@"com.apple.MobileSMS"]) G6UIAppMessagesApply(active);
    else if ([bundleID isEqualToString:@"com.apple.mobilephone"]) G6UIAppPhoneApply(active);
    else if ([bundleID isEqualToString:@"com.apple.calculator"]) G6UIAppCalculatorApply(active);
    else if ([bundleID isEqualToString:@"com.apple.compass"]) G6UIAppCompassApply(active);
    else if ([bundleID isEqualToString:@"com.apple.VoiceMemos"]) G6UIAppVoiceMemosApply(active);
    // iPhone: app đang được vẽ lại bằng khung chung vốn mang thanh trên tối (da, gỗ) và xin thanh trạng thái đen → nay thanh
    // trên theo sáng / tối của máy nên thanh trạng thái cũng phải theo kiểu phẳng
    if (g6_device_is_phone()) G6UIStatusBarSetForceFlat(G6UISkinActive());
    // Bộ lọc tối của các app vẽ lại bằng khung chung (app khác: không làm gì)
    G6UISkinApply();
}

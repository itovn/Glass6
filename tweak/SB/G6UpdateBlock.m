// Chặn cập nhật iOS qua mạng — dọn dấu nhắc còn sót.
//
// Lúc dịch vụ cập nhật của iOS (softwareupdateservicesd) tìm thấy bản mới, nó để lại hai thứ (tra trên iPad mini 1 iOS 6.1.3,
// 19/11/2026):
//   - huy hiệu «1» trên biểu tượng Cài đặt (SpringBoard giữ trong trạng thái app — khoá SBApplicationBadgeKey);
//   - khoá `kBadgedForSoftwareUpdateKey` (và `kBadgedForSoftwareUpdateJumpOnceKey`) trong cấu hình của app Cài đặt
//     (com.apple.Preferences) → số «1» ở dòng «Cài đặt chung» và «Cập nhật phần mềm».
// Chính dịch vụ đó mới là thứ gỡ dấu nhắc đi. Đã chặn nó (tắt bằng g6svc, hoặc tệp việc của nó bị gỡ từ trước) thì dấu nhắc
// nằm lại mãi — người đã quyết giữ bản iOS hiện tại cứ thấy số «1» đỏ trên Cài đặt.
//
// Cách làm: khi cập nhật ĐANG BỊ CHẶN (G6SvcUpdateBlock) và khoá kBadgedForSoftwareUpdateKey đang bật → tắt hai khoá, gỡ huy
// hiệu của biểu tượng Cài đặt. Chỉ gỡ huy hiệu khi chính khoá đó nói huy hiệu là của việc cập nhật; cập nhật không bị chặn
// thì không đụng gì. Xét: ít lâu sau khi SpringBoard mở xong, và mỗi lần màn «Dịch vụ hệ thống» vừa đổi dịch vụ (thông báo
// Darwin «vn.glass6/svc»).
#import "G6UpdateBlock.h"

#import <UIKit/UIKit.h>
#import <notify.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "G6Log.h"
#import "G6Services.h"

// Đợi SpringBoard mở xong hẳn rồi mới chạy g6svc (không gấp, đừng chen vào lúc máy đang bận nhất)
static const NSTimeInterval kFirstCheckDelay = 20;

static id G6UpdateSettingsIcon(void) {
    Class cls = objc_getClass("SBIconController");
    SEL shared = NSSelectorFromString(@"sharedInstance"), model = NSSelectorFromString(@"model");
    SEL find = NSSelectorFromString(@"leafIconForIdentifier:");
    id controller = [cls respondsToSelector:shared] ? ((id (*)(id, SEL))objc_msgSend)(cls, shared) : nil;
    id iconModel = [controller respondsToSelector:model] ? ((id (*)(id, SEL))objc_msgSend)(controller, model) : nil;
    return [iconModel respondsToSelector:find] ? ((id (*)(id, SEL, id))objc_msgSend)(iconModel, find, @"com.apple.Preferences") : nil;
}

// Luồng chính. Trả YES nếu vừa dọn.
static BOOL G6UpdateClearReminder(void) {
    CFStringRef app = CFSTR("com.apple.Preferences"), key = CFSTR("kBadgedForSoftwareUpdateKey");
    CFPreferencesAppSynchronize(app);
    Boolean valid = false;
    Boolean badged = CFPreferencesGetAppBooleanValue(key, app, &valid);
    if (!valid || !badged) return NO;
    CFPreferencesSetAppValue(key, kCFBooleanFalse, app);
    CFPreferencesSetAppValue(CFSTR("kBadgedForSoftwareUpdateJumpOnceKey"), kCFBooleanFalse, app);
    CFPreferencesAppSynchronize(app);
    id icon = G6UpdateSettingsIcon();
    SEL get = NSSelectorFromString(@"badgeNumberOrString"), set = NSSelectorFromString(@"setBadge:");
    BOOL hadBadge = [icon respondsToSelector:get] && ((id (*)(id, SEL))objc_msgSend)(icon, get) != nil;
    if (hadBadge && [icon respondsToSelector:set]) ((void (*)(id, SEL, id))objc_msgSend)(icon, set, nil);
    G6Log(@"cập nhật iOS: đang bị chặn — đã dọn dấu nhắc «có bản cập nhật» (huy hiệu trên Cài đặt: %@)", hadBadge ? @"gỡ" : @"không có");
    return YES;
}

static void G6UpdateCheck(void) {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        @autoreleasepool {
            G6UpdateBlock block = G6SvcUpdateBlock(G6SvcStatus());
            if (block == G6UpdateOpen) return;
            dispatch_async(dispatch_get_main_queue(), ^{
                @try {
                    G6UpdateClearReminder();
                } @catch (NSException *e) {
                    G6Log(@"cập nhật iOS: lỗi khi dọn dấu nhắc: %@", e);
                }
            });
        }
    });
}

static void G6UpdateServicesChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object,
                                    CFDictionaryRef userInfo) {
    G6UpdateCheck();
}

void G6UpdateBlockInstall(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, G6UpdateServicesChanged, CFSTR(G6_SVC_NOTE),
                                        NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kFirstCheckDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            G6UpdateCheck();
        });
    });
}

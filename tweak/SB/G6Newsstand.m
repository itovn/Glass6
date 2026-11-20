// Ẩn biểu tượng Quầy báo (Newsstand) khỏi màn hình chính — khoá cấu hình `hideNewsstand`, mặc định tắt.
//
// iOS 6 không cho xoá hay cho Quầy báo vào thư mục. SpringBoard hỏi -[SBIconModel isIconVisible:] cho từng biểu tượng lúc
// xếp màn hình chính → trả NO cho biểu tượng Quầy báo (SBNewsstandIcon) khi tính năng bật. Đổi lúc đang chạy: bảo mô hình
// biểu tượng phát thông báo «độ hiện đã đổi» (đúng thông báo SpringBoard dùng khi ẩn / hiện app theo hạn chế) để
// SBIconController gỡ / thêm biểu tượng và xếp lại ngay, không cần khởi động lại SpringBoard.
// Hiện lại thì Quầy báo về ô trống đầu tiên chứ không về đúng chỗ cũ (SpringBoard quyết định).
#import "G6Newsstand.h"

#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "G6Hook.h"
#import "G6Log.h"
#import "G6Prefs.h"

static BOOL gHide;
static BOOL gHooked;
static Class gNewsstandIconClass;

static BOOL (*o_isIconVisible)(id, SEL, id);
static BOOL g6_isIconVisible(id self, SEL _cmd, id icon) {
    if (gHide && gNewsstandIconClass && [icon isKindOfClass:gNewsstandIconClass]) return NO;
    return o_isIconVisible(self, _cmd, icon);
}

static id G6IconModel(void) {
    Class modelClass = objc_getClass("SBIconModel");
    if ([modelClass respondsToSelector:@selector(sharedInstance)]) return ((id (*)(id, SEL))objc_msgSend)(modelClass, @selector(sharedInstance));
    Class ctlClass = objc_getClass("SBIconController");
    id ctl = [ctlClass respondsToSelector:@selector(sharedInstance)] ? ((id (*)(id, SEL))objc_msgSend)(ctlClass, @selector(sharedInstance)) : nil;
    SEL model = NSSelectorFromString(@"model");
    return [ctl respondsToSelector:model] ? ((id (*)(id, SEL))objc_msgSend)(ctl, model) : nil;
}

static void G6NewsstandApply(BOOL initial) {
    BOOL hide = gHooked && G6Enabled() && [G6Config()[@"hide_newsstand"] boolValue];
    if (hide == gHide) return;
    gHide = hide;
    // Lúc SpringBoard vừa khởi động: lượt xếp biểu tượng đầu tiên tự hỏi isIconVisible:, không cần báo gì
    if (!initial) {
        id model = G6IconModel();
        SEL iconSel = NSSelectorFromString(@"newsstandIcon"), post = NSSelectorFromString(@"_postIconVisibilityChangedNotificationShowing:hiding:");
        id icon = [model respondsToSelector:iconSel] ? ((id (*)(id, SEL))objc_msgSend)(model, iconSel) : nil;
        if (icon && [model respondsToSelector:post]) {
            NSSet *one = [NSSet setWithObject:icon], *none = [NSSet set];
            ((void (*)(id, SEL, id, id))objc_msgSend)(model, post, hide ? none : one, hide ? one : none);
        } else {
            G6Log(@"quầy báo: không báo được việc đổi — có tác dụng từ lần khởi động lại SpringBoard sau");
        }
    }
    G6Log(@"quầy báo: %@", hide ? @"ẩn" : @"hiện");
}

void G6NewsstandInstall(void) {
    gNewsstandIconClass = objc_getClass("SBNewsstandIcon");
    gHooked = gNewsstandIconClass &&
              G6HookNamed("SBIconModel", NSSelectorFromString(@"isIconVisible:"), (IMP)g6_isIconVisible, (IMP *)&o_isIconVisible);
    if (!gHooked) {
        G6Log(@"quầy báo: thiếu SBNewsstandIcon / -[SBIconModel isIconVisible:] — không ẩn được");
        return;
    }
    [[NSNotificationCenter defaultCenter] addObserverForName:G6ConfigDidChangeNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
                                                      @try {
                                                          G6NewsstandApply(NO);
                                                      } @catch (NSException *e) {
                                                          G6Log(@"quầy báo: lỗi %@", e);
                                                      }
                                                  }];
    G6NewsstandApply(YES);
}

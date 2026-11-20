// Theo dõi khoá / mở khoá / tắt / sáng màn hình qua SBAwayController (iOS 6: bộ điều khiển màn khoá).
//
// Sau mỗi việc đó gửi G6ScreenStateDidChangeNotification; bên nghe tự hỏi G6ScreenAwake() rồi chạy / dừng phần của mình.
// Trước đây phần này nằm trong G6Clock.m; tách ra khi dải hiệu suất (G6Perf.m) cũng cần — hai thành phần cùng gắn năm hàm
// giống nhau là thừa.
#import "G6Screen.h"

#import <objc/message.h>
#import <objc/runtime.h>

#import "G6Hook.h"

NSString *const G6ScreenStateDidChangeNotification = @"G6ScreenStateDidChangeNotification";

BOOL G6ScreenAwake(void) {
    Class cls = objc_getClass("SBAwayController");
    SEL shared = NSSelectorFromString(@"sharedAwayControllerIfExists");
    id away = [cls respondsToSelector:shared] ? ((id (*)(id, SEL))objc_msgSend)(cls, shared) : nil;
    SEL locked = NSSelectorFromString(@"isLocked"), dimmed = NSSelectorFromString(@"isDimmed");
    if ([away respondsToSelector:locked] && ((BOOL (*)(id, SEL))objc_msgSend)(away, locked)) return NO;
    if ([away respondsToSelector:dimmed] && ((BOOL (*)(id, SEL))objc_msgSend)(away, dimmed)) return NO;
    return YES;
}

static void G6ScreenChanged(void) {
    if ([NSThread isMainThread]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:G6ScreenStateDidChangeNotification object:nil];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:G6ScreenStateDidChangeNotification object:nil];
        });
    }
}

#define G6_AWAY_HOOK0(name)                         \
    static void (*o_away_##name)(id, SEL);          \
    static void g6_away_##name(id self, SEL _cmd) { \
        o_away_##name(self, _cmd);                  \
        G6ScreenChanged();                          \
    }
#define G6_AWAY_HOOK1(name)                                   \
    static void (*o_away_##name)(id, SEL, BOOL);              \
    static void g6_away_##name(id self, SEL _cmd, BOOL arg) { \
        o_away_##name(self, _cmd, arg);                       \
        G6ScreenChanged();                                    \
    }
G6_AWAY_HOOK0(activate)
G6_AWAY_HOOK0(deactivate)
G6_AWAY_HOOK0(finishedDimmingScreen)
G6_AWAY_HOOK1(undimScreen)
G6_AWAY_HOOK1(finishedUnlock)

void G6ScreenWatchInstall(void) {
    static BOOL installed;
    if (installed) return;
    installed = YES;
    G6HookNamed("SBAwayController", NSSelectorFromString(@"activate"), (IMP)g6_away_activate, (IMP *)&o_away_activate);
    G6HookNamed("SBAwayController", NSSelectorFromString(@"deactivate"), (IMP)g6_away_deactivate, (IMP *)&o_away_deactivate);
    G6HookNamed("SBAwayController", NSSelectorFromString(@"finishedDimmingScreen"), (IMP)g6_away_finishedDimmingScreen,
                (IMP *)&o_away_finishedDimmingScreen);
    G6HookNamed("SBAwayController", NSSelectorFromString(@"undimScreen:"), (IMP)g6_away_undimScreen, (IMP *)&o_away_undimScreen);
    G6HookNamed("SBAwayController", NSSelectorFromString(@"_finishedUnlockAttemptWithStatus:"), (IMP)g6_away_finishedUnlock,
                (IMP *)&o_away_finishedUnlock);
}

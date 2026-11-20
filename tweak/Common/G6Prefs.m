#import "G6Prefs.h"

#import "G6Core.h"
#import "G6Device.h"
#import "G6Log.h"
#import <UIKit/UIKit.h>

NSString *const G6ConfigDidChangeNotification = @"G6ConfigDidChangeNotification";

static NSString *const kPrefsPath = @"/var/mobile/Library/Preferences/" G6_PREFS_DOMAIN ".plist";
static NSDictionary *gConfig;
static NSSet *gBlocked;

// Chỉ giữ kiểu JSON chở được (số, chuỗi, bool) — tệp plist có thể bị sửa tay thành ngày / dữ liệu thô
static NSDictionary *G6JSONSafe(NSDictionary *prefs) {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    [prefs enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
        if ([key isKindOfClass:[NSString class]] &&
            ([value isKindOfClass:[NSNumber class]] || [value isKindOfClass:[NSString class]])) {
            out[key] = value;
        }
    }];
    return out;
}

// ---- Chế độ «Tự động»: hẹn giờ tới lúc đổi sáng ↔ tối kế tiếp rồi báo như một lần đổi cấu hình ----
// Đồng hồ hẹn theo giờ thật (CFRunLoopTimer): máy ngủ qua giờ hẹn thì lúc thức dậy nó nổ ngay.
static CFRunLoopTimerRef gAutoTimer;
static int gLastDark = -1;

static void G6AutoSchedule(void);

// Giờ máy vừa qua một mốc (hoặc đồng hồ / múi giờ bị chỉnh): sáng ↔ tối có đổi thì báo cho mọi thành phần dựng lại
static void G6AutoCheck(void) {
    int dark = G6IsDark() ? 1 : 0;
    if (gLastDark >= 0 && dark != gLastDark) {
        G6Log(@"tự động: chuyển sang chế độ %@", dark ? @"tối" : @"sáng");
        [[NSNotificationCenter defaultCenter] postNotificationName:G6ConfigDidChangeNotification object:nil];
    }
    gLastDark = dark;
    G6AutoSchedule();
}

// Gọi trên luồng chính sau mỗi lần cấu hình đổi và sau mỗi lần đồng hồ nổ
static void G6AutoSchedule(void) {
    if (gAutoTimer) {
        CFRunLoopTimerInvalidate(gAutoTimer);
        CFRelease(gAutoTimer);
        gAutoTimer = NULL;
    }
    NSDictionary *cfg = G6Config();
    if (![cfg[@"enabled"] boolValue] || ![cfg[@"appearance"] isEqual:@"auto"]) return;
    NSDateComponents *c = [[NSCalendar currentCalendar] components:NSHourCalendarUnit | NSMinuteCalendarUnit | NSSecondCalendarUnit
                                                          fromDate:[NSDate date]];
    NSInteger now = c.hour * 3600 + c.minute * 60 + c.second, wait = 86400;
    for (NSString *key in @[@"dark_from", @"dark_to"]) {
        NSInteger t = ([cfg[key] integerValue] * 60 - now) % 86400;
        if (t <= 0) t += 86400;
        wait = MIN(wait, t);
    }
    // +1 giây: nổ khi phút mới đã bắt đầu hẳn (lõi so theo phút trong ngày)
    gAutoTimer = CFRunLoopTimerCreateWithHandler(NULL, CFAbsoluteTimeGetCurrent() + wait + 1, 0, 0, 0, ^(CFRunLoopTimerRef timer) {
        G6AutoCheck();
    });
    CFRunLoopAddTimer(CFRunLoopGetMain(), gAutoTimer, kCFRunLoopCommonModes);
}

static void G6PrefsReload(void) {
    NSDictionary *raw = [NSDictionary dictionaryWithContentsOfFile:kPrefsPath] ?: @{};
    NSDictionary *reply = G6CoreCall(@{@"cmd" : @"config.set", @"prefs" : G6JSONSafe(raw), @"device" : @(g6_device_name(g6_device_kind()))});
    NSDictionary *config = reply[@"config"];
    if (![config isKindOfClass:[NSDictionary class]]) {
        G6Log(@"lõi không trả cấu hình");
        return;
    }
    @synchronized(kPrefsPath) {
        gConfig = config;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        gLastDark = G6IsDark() ? 1 : 0;
        G6AutoSchedule();
        [[NSNotificationCenter defaultCenter] postNotificationName:G6ConfigDidChangeNotification object:nil];
    });
}

static void G6PrefsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object,
                           CFDictionaryRef userInfo) {
    G6PrefsReload();
}

void G6PrefsStart(void) {
    G6PrefsReload();
    // Qua nửa đêm, đổi múi giờ, chỉnh đồng hồ: mốc đã hẹn không còn đúng → xét lại
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationSignificantTimeChangeNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
                                                      G6AutoCheck();
                                                  }];
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, G6PrefsChanged, CFSTR(G6_PREFS_NOTE),
                                    NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
}

NSDictionary *G6Config(void) {
    @synchronized(kPrefsPath) {
        return gConfig;
    }
}

BOOL G6Enabled(void) {
    return [G6Config()[@"enabled"] boolValue];
}

BOOL G6Feature(NSString *name) {
    @synchronized(kPrefsPath) {
        if ([gBlocked containsObject:name]) return NO;
    }
    return G6Enabled() && [G6Config()[@"features"][name] boolValue];
}

void G6SetBlockedFeatures(NSArray *names) {
    @synchronized(kPrefsPath) {
        gBlocked = [NSSet setWithArray:names ?: @[]];
    }
}

BOOL G6IsDark(void) {
    NSDateComponents *c = [[NSCalendar currentCalendar] components:NSHourCalendarUnit | NSMinuteCalendarUnit fromDate:[NSDate date]];
    NSDictionary *r = G6CoreCall(@{@"cmd" : @"theme.dark", @"minutes" : @(c.hour * 60 + c.minute)});
    return [r[@"dark"] boolValue];
}

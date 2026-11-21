#import "G6NotifGuard.h"

#import "G6Hook.h"
#import "G6Log.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>

typedef id (*G6NGLocalizedFn)(id self, SEL _cmd, id key, id def, id bundle, id args);
typedef void (*G6NGSaveFn)(id self, SEL _cmd, id notification, id bundleID);
typedef id (*G6NGPresentFn)(id self, SEL _cmd, id notification, id app);

static G6NGLocalizedFn o_localized;
static G6NGSaveFn o_save;
static G6NGPresentFn o_present;
static int gFixes;  // số chữ đã lọc (chỉ ghi nhật ký vài lần đầu)

// Chữ đổi được sang UTF-8 thì trả lại nguyên; không thì thay nửa surrogate lẻ bằng U+FFFD
static id G6NGValid(id s, NSString *where) {
    if (![s isKindOfClass:[NSString class]]) return s;
    NSString *str = s;
    if (!str.length || [str UTF8String]) return s;
    NSUInteger n = str.length;
    unichar *buf = malloc(n * sizeof(unichar));
    if (!buf) return @"";
    [str getCharacters:buf range:NSMakeRange(0, n)];
    NSUInteger fixed = 0;
    for (NSUInteger i = 0; i < n; i++) {
        if (CFStringIsSurrogateHighCharacter(buf[i]) && i + 1 < n && CFStringIsSurrogateLowCharacter(buf[i + 1])) {
            i++;
            continue;
        }
        if (CFStringIsSurrogateHighCharacter(buf[i]) || CFStringIsSurrogateLowCharacter(buf[i])) {
            buf[i] = 0xFFFD;
            fixed++;
        }
    }
    NSString *r = [[NSString alloc] initWithCharacters:buf length:n];
    free(buf);
    if (gFixes++ < 10) G6Log(@"thông báo: %@ có %lu nửa emoji (chữ dài %lu) — đã thay bằng U+FFFD, SpringBoard không sập", where,
                             (unsigned long)fixed, (unsigned long)n);
    return r;
}

static void G6NGFixNotification(id n, NSString *where) {
    if (![n isKindOfClass:[UILocalNotification class]]) return;
    UILocalNotification *ln = n;
    NSString *body = ln.alertBody, *action = ln.alertAction;
    id b = G6NGValid(body, where), a = G6NGValid(action, where);
    if (b != body) ln.alertBody = b;
    if (a != action) ln.alertAction = a;
}

static id g6_localized(id self, SEL _cmd, id key, id def, id bundle, id args) {
    key = G6NGValid(key, @"khoá chữ");
    def = G6NGValid(def, @"chữ mặc định");
    if ([args isKindOfClass:[NSArray class]]) {
        NSMutableArray *clean = nil;
        NSArray *list = args;
        for (NSUInteger i = 0; i < list.count; i++) {
            id v = [list objectAtIndex:i], c = G6NGValid(v, @"tham số");
            if (c != v && !clean) clean = [list mutableCopy];
            if (clean) [clean replaceObjectAtIndex:i withObject:c];
        }
        if (clean) args = clean;
    }
    return G6NGValid(o_localized(self, _cmd, key, def, bundle, args), @"chữ đã dịch");
}

static void g6_save(id self, SEL _cmd, id notification, id bundleID) {
    G6NGFixNotification(notification, @"thông báo cục bộ (lưu)");
    o_save(self, _cmd, notification, bundleID);
}

static id g6_present(id self, SEL _cmd, id notification, id app) {
    G6NGFixNotification(notification, @"thông báo cục bộ (hiện)");
    return o_present(self, _cmd, notification, app);
}

void G6NotifGuardInstall(void) {
    static BOOL done;
    if (done) return;
    done = YES;
    Class alert = objc_getClass("SBSystemLocalNotificationAlert");
    Class meta = alert ? object_getClass(alert) : Nil;
    BOOL a = meta && G6Hook(meta, NSSelectorFromString(@"localizedStringFromKey:defaultValue:inBundle:arguments:"), (IMP)g6_localized,
                            (IMP *)&o_localized);
    BOOL b = G6HookNamed("SBPushStore", NSSelectorFromString(@"saveLocalNotification:forBundleID:"), (IMP)g6_save, (IMP *)&o_save);
    BOOL c = meta && G6Hook(meta, NSSelectorFromString(@"presentWithLocalNotification:application:"), (IMP)g6_present,
                            (IMP *)&o_present);
    if (!a || !b || !c) G6Log(@"thông báo: chốt nửa emoji — móc %d / %d / %d (thiếu hàm nào thì bỏ qua chỗ đó)", a, b, c);
}

#if G6_DEBUG
static NSString *G6NGBroken(void) {
    // «thử …» + nửa đầu của 😀 (D83D) — đúng kiểu chữ bị cắt `substringToIndex:` giữa emoji
    unichar tail[] = {0xD83D};
    return [@"Glass 6 thử chốt nửa emoji " stringByAppendingString:[NSString stringWithCharacters:tail length:1]];
}

NSString *G6NotifGuardDebug(NSString *arg) {
    NSString *broken = G6NGBroken();
    NSString *state = [NSString stringWithFormat:@"chữ thử dài %lu, UTF8String %@", (unsigned long)broken.length,
                                                 [broken UTF8String] ? @"được" : @"NULL"];
    Class alert = objc_getClass("SBSystemLocalNotificationAlert");
    SEL sel = NSSelectorFromString(@"localizedStringFromKey:defaultValue:inBundle:arguments:");
    if ([arg isEqualToString:@"raw"]) {
        if (!o_localized) return @"chưa móc localizedStringFromKey: — không có hàm gốc để gọi";
        G6Log(@"[thử] ngtest raw: %@ — gọi hàm GỐC của SpringBoard, sắp sập nếu lỗi đúng như phân tích", state);
        id r = o_localized(alert, sel, broken, broken, [NSBundle mainBundle], nil);
        return [NSString stringWithFormat:@"hàm gốc KHÔNG sập (kết quả dài %lu) — phân tích sai?", (unsigned long)[r length]];
    }
    if ([arg hasPrefix:@"save"]) {
        NSString *bid = [[arg substringFromIndex:4] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (!bid.length) bid = @"com.apple.mobilecal";
        Class store = objc_getClass("SBPushStore");
        SEL shared = NSSelectorFromString(@"sharedInstance");
        id ps = [store respondsToSelector:shared] ? ((id (*)(id, SEL))objc_msgSend)(store, shared) : nil;
        if (!ps) return @"không có +[SBPushStore sharedInstance]";
        UILocalNotification *ln = [[UILocalNotification alloc] init];
        ln.alertBody = broken;
        ln.alertAction = @"Xem";
        ((void (*)(id, SEL, id, id))objc_msgSend)(ps, NSSelectorFromString(@"saveLocalNotification:forBundleID:"), ln, bid);
        NSString *after = ln.alertBody;
        ((void (*)(id, SEL, id, id))objc_msgSend)(ps, NSSelectorFromString(@"removeLocalNotification:forBundleID:"), ln, bid);
        return [NSString stringWithFormat:@"%@ → lưu qua SBPushStore cho %@ KHÔNG sập; alertBody sau khi lưu: UTF8String %@; đã xoá lại",
                                          state, bid, [after UTF8String] ? @"được" : @"NULL"];
    }
    id r = ((id (*)(id, SEL, id, id, id, id))objc_msgSend)(alert, sel, broken, broken, [NSBundle mainBundle], nil);
    return [NSString stringWithFormat:@"%@ → localizedStringFromKey: (đã móc) KHÔNG sập, kết quả dài %lu, UTF8String %@", state,
                                      (unsigned long)[r length], [r UTF8String] ? @"được" : @"NULL"];
}
#endif

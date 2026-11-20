// Các mục của thanh trạng thái — phần dùng chung cho SpringBoard và app.
//
// iOS 6 (tra trên iPad mini 1, 19/11/2026): UIStatusBar › UIStatusBarForegroundView chứa các UIStatusBarItemView (tên mạng,
// Wi-Fi, giờ, pin…), mỗi cái tự vẽ thành ảnh; ba UIStatusBarLayoutManager xếp ba vùng: trái, phải, giữa. Thanh trạng thái
// do TỪNG tiến trình tự vẽ (SpringBoard chỉ phát dữ liệu) — nên phần này được gắn cả trong SpringBoard lẫn trong app.
//
//   - Giờ + mặt trăng «Không làm phiền» sang bên trái: mỗi loại mục (UIStatusBarItem) tự khai thuộc vùng nào và đứng thứ mấy
//     trong vùng. Trả lời thay cho hai loại Giờ và Không-làm-phiền: thuộc vùng trái, đứng đầu (mặt trăng rồi tới giờ, như lúc
//     còn ở giữa). Phải gắn đủ năm hàm (+itemType:appearsInRegion:, -appearsInRegion:, -appearsOnLeft, -appearsOnRight,
//     -compareLeftOrder:) — thiếu một hàm thì coi như không có tuỳ chọn này.
//   - Cột sóng + biểu tượng mạng sang bên phải (iOS 26 trên iPhone: giờ bên trái; sóng, Wi-Fi, pin dồn bên phải): cùng cách
//     — hai loại mục đó trả lời «thuộc vùng phải», và -compareRightOrder: xếp chúng ngay sau pin tính từ mép phải vào (pin,
//     phần trăm pin, mạng, sóng, rồi mới tới các mục vốn ở vùng phải). Vùng phải = vùng mà mục pin khai.
//   - Hình pin: -[UIStatusBarBatteryItemView contentsImageForStyle:] → hình tự vẽ (viền mờ, ruột theo mức pin, đỏ khi còn
//     ≤ 20% mà không cắm sạc); đang cắm sạc thì thêm tia sét XANH LÁ bên phải thay cho tia sét đen khoét giữa ruột pin của
//     iOS 6 (anh yêu cầu tia sét màu xanh lá, 19/11/2026 — xanh lá trên ruột pin trắng thì chìm nên đưa ra cạnh pin như iOS 7
//     trở đi). Màu nét lấy từ -textColorForStyle: của chính mục đó nên đúng cả trên thanh đen của app lẫn thanh trong suốt
//     của SpringBoard.
//   - Chữ: -[UIStatusBarItemView textFont] → Inter SemiBold cùng cỡ.
// Loại mục và số vùng không viết cứng: tra lúc chạy theo lớp view của từng loại (UIStatusBarTimeItemView…) và theo vùng mà
// mục «dịch vụ» khai (đo được trên máy: giờ 0, trăng 1, dịch vụ 4, vùng trái 0) — khác bản iOS thì tự đúng hoặc tự thôi.
//
// Gắn sớm, tra muộn: trong app, thanh trạng thái được tạo ngay trong UIApplicationMain, TRƯỚC -[UIApplication setDelegate:]
// (chỗ Glass6UI đặt kiểu). Gắn ở đó thì thanh đã dựng xong kiểu gốc, phải xếp và vẽ lại lần nữa: đo trên app Cài đặt tốn thêm
// ~24 ms mỗi lần mở app. Vì vậy G6StatusItemsInstall chỉ làm việc của runtime (đổi hàm) để gọi được ngay từ hàm khởi tạo của
// thư viện; còn việc tra loại mục (phải gọi vào UIKit) hoãn tới lần đầu một hàm thay thế được gọi — lúc đó chính UIKit đang
// dựng thanh trạng thái nên chắc chắn đã khởi động xong.
#import "G6StatusItems.h"

#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "G6Font.h"
#import "G6Hook.h"
#import "G6Log.h"

// Trạng thái đang có hiệu lực
static BOOL gTimeLeft, gSignalRight, gBattery, gFont;
// Tra lúc chạy, một lần (−1 = không tìm thấy → phần dùng tới nó đứng yên)
static BOOL gDiscovered;
static int gTypeTime = -1, gTypeQuiet = -1, gTypeService = -1;
static int gTypeSignal = -1, gTypeData = -1, gTypeBattery = -1, gTypeBatteryPercent = -1;
static int gRegionLeft = -1, gRegionRight = -1;

static void G6StatusItemsDiscover(void);

// ---- Tiện ích ----

static UIView *G6FindSubview(UIView *parent, const char *className) {
    Class cls = objc_getClass(className);
    for (UIView *sub in parent.subviews) {
        if (cls && [sub isKindOfClass:cls]) return sub;
    }
    return nil;
}

UIView *G6StatusBarView(void) {
    UIApplication *app = [UIApplication sharedApplication];
    SEL barSel = NSSelectorFromString(@"statusBar");
    UIView *bar = [app respondsToSelector:barSel] ? ((id (*)(id, SEL))objc_msgSend)(app, barSel) : nil;
    return [bar isKindOfClass:[UIView class]] ? bar : nil;
}

UIView *G6StatusBarForeground(void) {
    return G6FindSubview(G6StatusBarView(), "UIStatusBarForegroundView");
}

static int G6IntIvar(id obj, const char *name, int fallback) {
    Ivar iv = obj ? class_getInstanceVariable([obj class], name) : NULL;
    const char *enc = iv ? ivar_getTypeEncoding(iv) : NULL;
    if (!enc || enc[0] != 'i') return fallback;
    return *(int *)((char *)(__bridge void *)obj + ivar_getOffset(iv));
}

static int G6ItemType(id item) {
    SEL sel = NSSelectorFromString(@"type");
    return [item respondsToSelector:sel] ? ((int (*)(id, SEL))objc_msgSend)(item, sel) : -1;
}

// ---- Chữ ----

static id (*o_textFont)(id, SEL);
static id g6_textFont(id self, SEL _cmd) {
    UIFont *orig = o_textFont(self, _cmd);
    if (!gFont || ![orig isKindOfClass:[UIFont class]] || !G6FontAvailable()) return orig;
    return G6Font(G6FontSemiBold, orig.pointSize) ?: orig;
}

// ---- Giờ + mặt trăng sang trái ----

static BOOL (*o_typeAppears)(id, SEL, int, int);

// Tra loại mục theo lớp view của nó, và số của vùng trái theo mục «dịch vụ». Chạy một lần, ở lần đầu cần tới.
static void G6StatusItemsDiscover(void) {
    if (gDiscovered) return;
    gDiscovered = YES;
    Class item = objc_getClass("UIStatusBarItem");
    SEL valid = NSSelectorFromString(@"typeIsValid:"), make = NSSelectorFromString(@"itemWithType:");
    SEL viewClass = NSSelectorFromString(@"viewClass"), appears = NSSelectorFromString(@"itemType:appearsInRegion:");
    if (![item respondsToSelector:valid] || ![item respondsToSelector:make] || ![item respondsToSelector:appears]) return;
    for (int t = 0; t < 48; t++) {
        if (!((BOOL (*)(id, SEL, int))objc_msgSend)(item, valid, t)) continue;
        id it = ((id (*)(id, SEL, int))objc_msgSend)(item, make, t);
        Class cls = [it respondsToSelector:viewClass] ? ((Class (*)(id, SEL))objc_msgSend)(it, viewClass) : Nil;
        const char *name = cls ? class_getName(cls) : "";
        if (strcmp(name, "UIStatusBarTimeItemView") == 0) gTypeTime = t;
        else if (strcmp(name, "UIStatusBarQuietModeItemView") == 0) gTypeQuiet = t;
        else if (strcmp(name, "UIStatusBarServiceItemView") == 0) gTypeService = t;
        else if (strcmp(name, "UIStatusBarSignalStrengthItemView") == 0) gTypeSignal = t;
        else if (strcmp(name, "UIStatusBarDataNetworkItemView") == 0) gTypeData = t;
        else if (strcmp(name, "UIStatusBarBatteryItemView") == 0) gTypeBattery = t;
        else if (strcmp(name, "UIStatusBarBatteryPercentItemView") == 0) gTypeBatteryPercent = t;
    }
    for (int r = 0; r < 3; r++) {
        // Hỏi thẳng hàm gốc (hàm này đã bị thay — đi qua objc_msgSend là vòng về chính mình)
        BOOL (*ask)(id, SEL, int, int) = o_typeAppears ?: (BOOL (*)(id, SEL, int, int))objc_msgSend;
        if (gRegionLeft < 0 && gTypeService >= 0 && ask(item, appears, gTypeService, r)) gRegionLeft = r;
        if (gRegionRight < 0 && gTypeBattery >= 0 && ask(item, appears, gTypeBattery, r)) gRegionRight = r;
    }
    if (gTypeTime < 0 || gRegionLeft < 0) {
        G6Log(@"thanh trạng thái: không tra được loại mục (giờ %d, vùng trái %d) — giờ giữ ở giữa", gTypeTime, gRegionLeft);
    }
}

static BOOL G6MovedLeft(int type) {
    if (!gTimeLeft || type < 0) return NO;
    G6StatusItemsDiscover();
    return gRegionLeft >= 0 && gTypeTime >= 0 && (type == gTypeTime || type == gTypeQuiet);
}

// Cột sóng và biểu tượng mạng: sang vùng phải
static BOOL G6MovedRight(int type) {
    if (!gSignalRight || type < 0) return NO;
    G6StatusItemsDiscover();
    return gRegionRight >= 0 && gTypeBattery >= 0 && (type == gTypeSignal || type == gTypeData);
}

// Thứ tự trong vùng phải, tính từ mép phải vào: pin, phần trăm pin, mạng, sóng, rồi tới các mục khác vốn ở đó
static int G6RightRank(int type) {
    if (type < 0) return 4;
    if (type == gTypeBattery) return 0;
    if (type == gTypeBatteryPercent) return 1;
    if (type == gTypeData) return 2;
    if (type == gTypeSignal) return 3;
    return 4;
}

// Thứ tự trong vùng trái: mặt trăng, giờ, rồi tới các mục vốn ở đó
static int G6LeftRank(int type) {
    if (type >= 0 && type == gTypeQuiet) return 0;
    if (type >= 0 && type == gTypeTime) return 1;
    return 2;
}

static BOOL g6_typeAppears(id self, SEL _cmd, int type, int region) {
    if (G6MovedLeft(type)) return region == gRegionLeft;
    if (G6MovedRight(type)) return region == gRegionRight;
    return o_typeAppears(self, _cmd, type, region);
}

static BOOL (*o_appearsInRegion)(id, SEL, int);
static BOOL g6_appearsInRegion(id self, SEL _cmd, int region) {
    int type = G6ItemType(self);
    if (G6MovedLeft(type)) return region == gRegionLeft;
    if (G6MovedRight(type)) return region == gRegionRight;
    return o_appearsInRegion(self, _cmd, region);
}

static BOOL (*o_appearsOnLeft)(id, SEL);
static BOOL g6_appearsOnLeft(id self, SEL _cmd) {
    int type = G6ItemType(self);
    if (G6MovedLeft(type)) return YES;
    if (G6MovedRight(type)) return NO;
    return o_appearsOnLeft(self, _cmd);
}

static BOOL (*o_appearsOnRight)(id, SEL);
static BOOL g6_appearsOnRight(id self, SEL _cmd) {
    int type = G6ItemType(self);
    if (G6MovedLeft(type)) return NO;
    if (G6MovedRight(type)) return YES;
    return o_appearsOnRight(self, _cmd);
}

static int (*o_compareRightOrder)(id, SEL, id);
static int g6_compareRightOrder(id self, SEL _cmd, id other) {
    if (gSignalRight) {
        G6StatusItemsDiscover();
        if (gRegionRight >= 0 && gTypeBattery >= 0) {
            int a = G6RightRank(G6ItemType(self)), b = G6RightRank(G6ItemType(other));
            if (a != b) return a < b ? NSOrderedAscending : NSOrderedDescending;
            if (a < 4) return NSOrderedSame;
        }
    }
    return o_compareRightOrder(self, _cmd, other);
}

static int (*o_compareLeftOrder)(id, SEL, id);
static int g6_compareLeftOrder(id self, SEL _cmd, id other) {
    if (gTimeLeft) {
        G6StatusItemsDiscover();
        int a = G6LeftRank(G6ItemType(self)), b = G6LeftRank(G6ItemType(other));
        if (a != b) return a < b ? NSOrderedAscending : NSOrderedDescending;
        if (a < 2) return NSOrderedSame;
    }
    return o_compareLeftOrder(self, _cmd, other);
}

// ---- Hình pin ----

// Tia sét trong khung 8×13 điểm, gốc ở (x, y)
static void G6AddBolt(CGContextRef ctx, CGFloat x, CGFloat y) {
    const CGFloat p[6][2] = {{5.6, 0}, {0.2, 7.6}, {3.4, 7.6}, {2.4, 13.0}, {7.8, 5.4}, {4.6, 5.4}};
    CGContextMoveToPoint(ctx, x + p[0][0], y + p[0][1]);
    for (int i = 1; i < 6; i++) CGContextAddLineToPoint(ctx, x + p[i][0], y + p[i][1]);
    CGContextClosePath(ctx);
}

// Hình pin tự vẽ, cao bằng ảnh gốc. capacity 0–100; power = đang cắm sạc (đang nạp hoặc đã đầy).
static UIImage *G6BatteryImage(UIColor *base, int capacity, BOOL power, CGFloat height) {
    static NSMutableDictionary *cache;
    CGFloat r = 1, g = 1, b = 1, a = 1, white = 1;
    if (![base getRed:&r green:&g blue:&b alpha:&a] && [base getWhite:&white alpha:&a]) r = g = b = white;
    NSString *key = [NSString stringWithFormat:@"%d|%d|%.0f|%.2f|%.2f|%.2f", capacity, power, height, r, g, b];
    UIImage *img = cache[key];
    if (img) return img;

    // Màn hình 1x: nét mảnh dưới 2 điểm ảnh bị nhoè → tia sét vẽ trong khung 8×13
    const CGFloat bodyW = 22, bodyH = 11, nubW = 2, boltGap = 2, boltW = 8, boltH = 13;
    CGFloat width = bodyW + nubW + 1 + (power ? boltGap + boltW : 0);
    CGFloat top = floor((height - bodyH) / 2);
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(width, height), NO, MAX([UIScreen mainScreen].scale, 1));
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    UIColor *soft = [UIColor colorWithRed:r green:g blue:b alpha:0.5];
    // Vỏ pin: viền mờ 1 điểm
    UIBezierPath *shell = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0.5, top + 0.5, bodyW - 1, bodyH - 1) cornerRadius:3];
    shell.lineWidth = 1;
    [soft setStroke];
    [shell stroke];
    // Núm
    [soft setFill];
    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(bodyW + 0.5, top + 3.5, nubW - 0.5, bodyH - 7)
                           byRoundingCorners:UIRectCornerTopRight | UIRectCornerBottomRight
                                 cornerRadii:CGSizeMake(1, 1)] fill];
    // Ruột: theo mức pin; còn ít mà không cắm sạc thì đỏ
    CGFloat room = bodyW - 4, fill = MAX(2, round(room * capacity / 100.0));
    if (!power && capacity <= 20) [[UIColor colorWithRed:1.0 green:0.27 blue:0.23 alpha:1] setFill];
    else [[UIColor colorWithRed:r green:g blue:b alpha:1] setFill];
    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(2, top + 2, fill, bodyH - 4) cornerRadius:1.5] fill];
    // Tia sét xanh lá khi đang cắm sạc
    if (power) {
        G6AddBolt(ctx, bodyW + nubW + boltGap, floor((height - boltH) / 2));
        CGContextSetRGBFillColor(ctx, 0.19, 0.82, 0.35, 1);
        CGContextFillPath(ctx);
    }
    img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (!img) return nil;
    if (!cache) cache = [NSMutableDictionary dictionary];
    if (cache.count > 240) [cache removeAllObjects];
    cache[key] = img;
    return img;
}

static id (*o_batteryImage)(id, SEL, int);
static id g6_batteryImage(UIView *self, SEL _cmd, int style) {
    UIImage *orig = o_batteryImage(self, _cmd, style);
    if (!gBattery || ![orig isKindOfClass:[UIImage class]]) return orig;
    @try {
        // _capacity: phần trăm pin; _state: 0 = không cắm, 1 = đang nạp, 2 = cắm và đã đầy
        int capacity = G6IntIvar(self, "_capacity", -1), state = G6IntIvar(self, "_state", 0);
        if (capacity < 0) return orig;
        SEL colorSel = NSSelectorFromString(@"textColorForStyle:");
        UIColor *base = [self respondsToSelector:colorSel] ? ((id (*)(id, SEL, int))objc_msgSend)(self, colorSel, style) : nil;
        if (![base isKindOfClass:[UIColor class]]) base = [UIColor whiteColor];
        UIImage *mine = G6BatteryImage(base, MIN(capacity, 100), state != 0, orig.size.height > 0 ? orig.size.height : 20);
        if (mine) return mine;
    } @catch (NSException *e) {
    }
    return orig;
}

// ---- Cửa chung ----

void G6StatusItemsInstall(void) {
    static BOOL installed;
    if (installed) return;
    installed = YES;
    G6HookNamed("UIStatusBarItemView", NSSelectorFromString(@"textFont"), (IMP)g6_textFont, (IMP *)&o_textFont);
    G6HookNamed("UIStatusBarBatteryItemView", NSSelectorFromString(@"contentsImageForStyle:"), (IMP)g6_batteryImage,
                (IMP *)&o_batteryImage);
    // Từ đây xuống chỉ đổi hàm (việc của runtime) — KHÔNG gọi vào UIKit: hàm này có thể đang chạy trong hàm khởi tạo của
    // thư viện, trước UIApplicationMain
    Class item = objc_getClass("UIStatusBarItem");
    if (!item) return;
    // Hàm của lớp nằm trên siêu lớp (metaclass)
    BOOL ok = G6Hook(object_getClass(item), NSSelectorFromString(@"itemType:appearsInRegion:"), (IMP)g6_typeAppears,
                     (IMP *)&o_typeAppears);
    ok = ok && G6Hook(item, NSSelectorFromString(@"appearsInRegion:"), (IMP)g6_appearsInRegion, (IMP *)&o_appearsInRegion);
    ok = ok && G6Hook(item, NSSelectorFromString(@"appearsOnLeft"), (IMP)g6_appearsOnLeft, (IMP *)&o_appearsOnLeft);
    ok = ok && G6Hook(item, NSSelectorFromString(@"appearsOnRight"), (IMP)g6_appearsOnRight, (IMP *)&o_appearsOnRight);
    ok = ok && G6Hook(item, NSSelectorFromString(@"compareLeftOrder:"), (IMP)g6_compareLeftOrder, (IMP *)&o_compareLeftOrder);
    // Riêng cho «sóng sang phải»: thiếu hàm này thì chỉ tuỳ chọn đó không có
    if (ok) G6Hook(item, NSSelectorFromString(@"compareRightOrder:"), (IMP)g6_compareRightOrder, (IMP *)&o_compareRightOrder);
    if (!ok) {
        // Gắn được nửa chừng thì coi như không có: G6StatusItemsSet chỉ cho bật «giờ bên trái» khi còn o_typeAppears
        o_typeAppears = NULL;
        G6Log(@"thanh trạng thái: thiếu hàm xếp vùng — giờ giữ ở giữa");
    }
}

void G6StatusItemsSet(BOOL timeLeft, BOOL signalRight, BOOL battery, BOOL font, BOOL *layoutChanged, BOOL *lookChanged) {
    // Chưa tra loại mục thì cứ nhận «muốn giờ bên trái»; tra không ra thì các hàm thay thế tự trả kết quả gốc
    timeLeft = timeLeft && o_typeAppears && (!gDiscovered || (gTypeTime >= 0 && gRegionLeft >= 0));
    signalRight = signalRight && o_typeAppears && o_compareRightOrder && (!gDiscovered || (gTypeBattery >= 0 && gRegionRight >= 0));
    battery = battery && o_batteryImage;
    font = font && o_textFont;
    if (layoutChanged) *layoutChanged = timeLeft != gTimeLeft || signalRight != gSignalRight;
    if (lookChanged) *lookChanged = battery != gBattery || font != gFont;
    gTimeLeft = timeLeft;
    gSignalRight = signalRight;
    gBattery = battery;
    gFont = font;
}

BOOL G6StatusItemsTimeLeft(void) {
    if (!gTimeLeft) return NO;
    G6StatusItemsDiscover();
    return gTypeTime >= 0 && gRegionLeft >= 0;
}

BOOL G6StatusItemsSignalRight(void) {
    if (!gSignalRight) return NO;
    G6StatusItemsDiscover();
    return gTypeBattery >= 0 && gRegionRight >= 0;
}

BOOL G6StatusItemsBattery(void) {
    return gBattery;
}

int G6StatusItemsServiceType(void) {
    G6StatusItemsDiscover();
    return gTypeService;
}

int G6StatusItemsQuietType(void) {
    G6StatusItemsDiscover();
    return gTypeQuiet;
}

void G6StatusItemsRefresh(BOOL relayout) {
    UIView *bar = G6StatusBarView(), *fg = G6StatusBarForeground();
    if (!bar || !fg) return;
    // Có mục đổi vùng: cho thanh xếp lại từ dữ liệu đang có — từng mục được hỏi lại «thuộc vùng nào». Đo trên máy: vùng mới
    // tạo view cho mục vừa chuyển sang; view cũ ở vùng cũ không bị gỡ mà chuyển sang ẩn (isVisible = NO) và nằm yên đó (mỗi
    // vùng nhiều nhất một view cho mỗi loại mục nên không tích dần) → mọi chỗ đo vị trí các mục phải bỏ qua view ẩn.
    SEL force = NSSelectorFromString(@"forceUpdateData:");
    if (relayout && [bar respondsToSelector:force]) ((void (*)(id, SEL, BOOL))objc_msgSend)(bar, force, NO);
    // Rồi từng mục vẽ lại theo phông / hình mới và xếp lại (bề rộng đổi). Bước trên chỉ tạo mới view của mục đổi vùng — các
    // mục khác (pin…) còn nguyên ảnh cũ nếu bỏ bước này (đã gặp: hình pin mới chỉ hiện khi phần trăm pin đổi).
    SEL update = NSSelectorFromString(@"updateContentsAndWidth"), reflow = NSSelectorFromString(@"reflowItemViews:");
    Class itemClass = objc_getClass("UIStatusBarItemView");
    for (UIView *item in fg.subviews) {
        if (itemClass && [item isKindOfClass:itemClass] && [item respondsToSelector:update]) {
            ((float (*)(id, SEL))objc_msgSend)(item, update);
        }
    }
    if ([fg respondsToSelector:reflow]) ((void (*)(id, SEL, BOOL))objc_msgSend)(fg, reflow, NO);
}

NSString *G6StatusItemsDescribe(void) {
    NSMutableString *out = [NSMutableString string];
    G6StatusItemsDiscover();
    [out appendFormat:@"giờ trái=%d sóng phải=%d pin=%d chữ=%d | loại: giờ %d, trăng %d, dịch vụ %d, sóng %d, mạng %d, pin %d, %%pin %d; vùng trái %d, phải %d |",
                      gTimeLeft, gSignalRight, gBattery, gFont, gTypeTime, gTypeQuiet, gTypeService, gTypeSignal, gTypeData, gTypeBattery,
                      gTypeBatteryPercent, gRegionLeft, gRegionRight];
    UIView *fg = G6StatusBarForeground();
    Class itemClass = objc_getClass("UIStatusBarItemView");
    SEL visible = NSSelectorFromString(@"isVisible"), itemSel = NSSelectorFromString(@"item");
    for (UIView *v in fg.subviews) {
        if (!itemClass || ![v isKindOfClass:itemClass]) continue;
        id item = [v respondsToSelector:itemSel] ? ((id (*)(id, SEL))objc_msgSend)(v, itemSel) : nil;
        BOOL shown = [v respondsToSelector:visible] ? ((BOOL (*)(id, SEL))objc_msgSend)(v, visible) : YES;
        NSString *name = [[NSStringFromClass([v class]) stringByReplacingOccurrencesOfString:@"UIStatusBar" withString:@""]
            stringByReplacingOccurrencesOfString:@"ItemView" withString:@""];
        [out appendFormat:@" %@(%d)%@ x %.0f–%.0f", name, G6ItemType(item), shown ? @"" : @"[ẩn]", CGRectGetMinX(v.frame),
                          CGRectGetMaxX(v.frame)];
        if ([name isEqualToString:@"Battery"]) {
            [out appendFormat:@" [pin %d%%, trạng thái %d]", G6IntIvar(v, "_capacity", -1), G6IntIvar(v, "_state", -1)];
        }
    }
    return out;
}

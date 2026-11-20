// Control Center cho iOS 6.
//
// Mở: SpringBoard iOS 6 có sẵn cử chỉ hệ thống «kéo từ mép trên xuống» (chạy cả trong app) để mở Trung tâm thông báo, đi qua
//   -[SBUIController _showNotificationsGestureBeganWithLocation:] / …ChangedWithLocation:velocity: /
//   …EndedWithLocation:velocity: / _showNotificationsGestureCancelled / _showNotificationsGestureFailed.
// Móc năm hàm đó: cử chỉ bắt đầu ở một phần ba bên phải → giữ lại cho Control Center (không gọi hàm gốc cho cả cử chỉ ấy),
// kéo xuống đủ xa thì mở bảng; bắt đầu ở chỗ khác → hàm gốc, Trung tâm thông báo như cũ.
// Đóng: chạm ra ngoài bảng, bấm nút Home, xoay máy, khoá máy.
//
// Bảng nằm trong một UIWindow riêng (mức 1055), tự xoay theo hướng giao diện như các cửa sổ của SpringBoard. Nền bảng là tấm
// kính đậm (bề mặt `hud`) trên ảnh chụp màn hình lúc sắp mở. Hình trên nút tự vẽ bằng UIBezierPath (không dùng ảnh của Apple).
//
// Điều khiển dùng chính các lớp của SpringBoard iOS 6 (tra trên máy 19/11/2026), thiếu lớp / hàm nào thì nút đó ẩn:
//   Máy bay     SBTelephonyManager  +sharedTelephonyManager  -isInAirplaneMode / -setIsInAirplaneMode:
//   Wi-Fi       SBWiFiManager       +sharedInstance          -wiFiEnabled / -setWiFiEnabled:
//   Bluetooth   BluetoothManager    +sharedInstance          -powered / -setPowered: (+ -setEnabled:)
//   Khoá xoay   SBOrientationLockManager +sharedInstance     -isLocked / -lock / -unlock
//   Không làm phiền  BBSettingsGateway (BulletinBoard) -setBehaviorOverrideStatus: 1 / 0 — đúng việc công tắc «Không làm
//               phiền» của app Cài đặt làm. iOS 6 không có hàm hỏi trạng thái tức thời → đọc mục «trăng khuyết» của thanh
//               trạng thái: mảng `_itemIsEnabled` của SBStatusBarDataManager (đang có hiệu lực, kể cả theo lịch hẹn)
//   Sáng / tối  khoá `appearance` của Glass 6 (ghi tệp cấu hình + báo «vn.glass6/prefs» như bảng Cài đặt vẫn làm)
//   Độ sáng     SBBrightnessController +sharedBrightnessController -setBrightnessLevel:; đọc: BKSDisplayBrightnessGetCurrent
//   Âm lượng    SBMediaController   +sharedInstance          -volume / -setVolume:
//   Nhạc        SBMediaController   -nowPlayingTitle / -nowPlayingArtist / -isPlaying / -togglePlayPause / -changeTrack:
//   Dữ liệu di động (iPhone)  CTCellularDataPlanGetIsEnabled / CTCellularDataPlanSetIsEnabled của CoreTelephony (tìm bằng dlsym)
//   Đèn pin (iPhone)          AVCaptureDevice (nạp AVFoundation lúc cần) -hasTorch / -torchMode / -setTorchMode:
//
// iPhone (kiểu iOS 26 của iPhone): bảng là một lưới ô kính vuông — máy đứng 2 × 2, máy ngang 1 × 4:
//      [ máy bay · dữ liệu · Wi-Fi · Bluetooth ]   [ bài đang phát + ba nút ]
//      [ không làm phiền · khoá xoay · tối · đèn pin ]   [ độ sáng ▮ ▮ âm lượng — hai thanh trượt ĐỨNG ]
// Thanh trượt đứng (G6CCVSlider) kéo tương đối như iOS 26: chạm đâu cũng được, kéo lên / xuống là tăng / giảm. Cử chỉ «vuốt lên
// để đóng» không nhận ngón tay đặt trên thanh trượt đứng. iPad giữ bố cục cũ (một hàng nút tròn + hai thanh trượt ngang).
#import "G6ControlCenter.h"

#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <notify.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "G6Device.h"
#import "G6Font.h"
#import "G6Glass.h"
#import "G6Hook.h"
#import "G6Lang.h"
#import "G6Log.h"
#import "G6Prefs.h"
#import "G6StatusItems.h"

// Số đo của bảng (điểm). kToggle: cỡ nút tròn lớn nhất — nhiều nút quá thì cả hàng thu nhỏ cho vừa (kToggleGap: khe nhỏ nhất)
static const CGFloat kPanelWidth = 340, kPad = 14, kToggle = 54, kToggleGap = 8, kRow = 40, kRowGap = 6, kMusicHeight = 62;
static const CGFloat kPanelTop = 28, kPanelRight = 12;
// iPhone: ô vuông của lưới (máy đứng / máy ngang), khe giữa các ô, lề trong bảng, lề trong ô
static const CGFloat kTilePortrait = 134, kTileLandscape = 124, kTileGapPortrait = 12, kTileGapLandscape = 10, kTilePad = 12, kTileInset = 12;
// Cử chỉ phải kéo xuống ít nhất chừng này (hoặc vuốt nhanh) mới mở
static const CGFloat kPullDistance = 24;

static UIWindow *gWindow;
static UIView *gRoot, *gPanel;
static UIImageView *gGlass;
static NSMutableArray *gToggles;  // UIButton, tag = chỉ số trong bảng kToggleNames
static UISlider *gBrightness, *gVolume;
static UILabel *gTitle, *gArtist;
static UIButton *gPlay;
static BOOL gVisible;
static NSTimer *gRefreshTimer;
static NSTimer *gHideTimer;  // đếm thời gian chờ tự ẩn
static CGFloat gToggleSize = 54;  // cỡ nút tròn của lần dựng bảng gần nhất

// ---- Gọi lớp của SpringBoard ----

static id G6Shared(const char *className, NSString *selName) {
    Class cls = objc_getClass(className);
    SEL sel = NSSelectorFromString(selName);
    return [cls respondsToSelector:sel] ? ((id (*)(id, SEL))objc_msgSend)(cls, sel) : nil;
}

static BOOL G6GetBool(id obj, NSString *selName) {
    SEL sel = NSSelectorFromString(selName);
    return [obj respondsToSelector:sel] ? ((BOOL (*)(id, SEL))objc_msgSend)(obj, sel) : NO;
}

static void G6SetBool(id obj, NSString *selName, BOOL value) {
    SEL sel = NSSelectorFromString(selName);
    if ([obj respondsToSelector:sel]) ((void (*)(id, SEL, BOOL))objc_msgSend)(obj, sel, value);
}

static void G6Send(id obj, NSString *selName) {
    SEL sel = NSSelectorFromString(selName);
    if ([obj respondsToSelector:sel]) ((void (*)(id, SEL))objc_msgSend)(obj, sel);
}

static id G6GetObject(id obj, NSString *selName) {
    SEL sel = NSSelectorFromString(selName);
    return [obj respondsToSelector:sel] ? ((id (*)(id, SEL))objc_msgSend)(obj, sel) : nil;
}

// ---- Khoá xoay ----

BOOL G6RotationLocked(void) {
    return G6GetBool(G6Shared("SBOrientationLockManager", @"sharedInstance"), @"isLocked");
}

void G6SetRotationLocked(BOOL locked) {
    id manager = G6Shared("SBOrientationLockManager", @"sharedInstance");
    if (!locked) {
        G6Send(manager, @"unlock");
        return;
    }
    UIApplication *app = [UIApplication sharedApplication];
    SEL active = NSSelectorFromString(@"activeInterfaceOrientation"), lockTo = NSSelectorFromString(@"lock:");
    NSInteger orientation = [app respondsToSelector:active] ? ((NSInteger (*)(id, SEL))objc_msgSend)(app, active) : app.statusBarOrientation;
    if ([manager respondsToSelector:lockTo] && orientation >= 1 && orientation <= 4) {
        ((void (*)(id, SEL, int))objc_msgSend)(manager, lockTo, (int)orientation);
    } else {
        G6Send(manager, @"lock");
    }
}

// ---- Không làm phiền ----

// Mục «trăng khuyết» của thanh trạng thái đang bật? (SpringBoard bật nó khi «Không làm phiền» đang có hiệu lực)
static BOOL G6QuietAvailable(void) {
    Class gateway = objc_getClass("BBSettingsGateway"), manager = objc_getClass("SBStatusBarDataManager");
    Ivar iv = manager ? class_getInstanceVariable(manager, "_itemIsEnabled") : NULL;
    int type = G6StatusItemsQuietType();
    return [gateway instancesRespondToSelector:NSSelectorFromString(@"setBehaviorOverrideStatus:")] && iv &&
           strcmp(ivar_getTypeEncoding(iv) ?: "", "[24c]") == 0 && type >= 0 && type < 24;
}

static BOOL G6QuietActive(void) {
    if (!G6QuietAvailable()) return NO;
    id manager = G6Shared("SBStatusBarDataManager", @"sharedDataManager");
    if (!manager) return NO;
    Ivar iv = class_getInstanceVariable([manager class], "_itemIsEnabled");
    const char *enabled = (const char *)(__bridge void *)manager + ivar_getOffset(iv);
    return enabled[G6StatusItemsQuietType()] != 0;
}

static void G6SetQuiet(BOOL on) {
    static id gateway;  // giữ suốt: cổng nối tới dịch vụ thông báo, tạo một lần
    if (!gateway) gateway = [[objc_getClass("BBSettingsGateway") alloc] init];
    SEL sel = NSSelectorFromString(@"setBehaviorOverrideStatus:");
    if ([gateway respondsToSelector:sel]) ((void (*)(id, SEL, int))objc_msgSend)(gateway, sel, on ? 1 : 0);
}

// ---- Các nút bật / tắt ----

typedef enum { G6CCAirplane, G6CCWiFi, G6CCBluetooth, G6CCQuiet, G6CCRotation, G6CCDark, G6CCCellular, G6CCFlashlight, G6CCToggleCount } G6CCToggle;

// Dữ liệu di động: hai hàm C của CoreTelephony, không có trong tệp đầu công khai
static Boolean (*gCellularGet)(void);
static void (*gCellularSet)(Boolean);

static BOOL G6CCCellularReady(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *h = dlopen("/System/Library/Frameworks/CoreTelephony.framework/CoreTelephony", RTLD_NOW);
        if (h) {
            gCellularGet = dlsym(h, "CTCellularDataPlanGetIsEnabled");
            gCellularSet = dlsym(h, "CTCellularDataPlanSetIsEnabled");
        }
    });
    return gCellularGet && gCellularSet;
}

// Đèn pin: đèn của máy ảnh sau. AVFoundation chỉ nạp khi cần tới (SpringBoard không liên kết sẵn).
static id G6CCTorch(void) {
    static id device;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dlopen("/System/Library/Frameworks/AVFoundation.framework/AVFoundation", RTLD_NOW);
        Class cls = objc_getClass("AVCaptureDevice");
        SEL sel = NSSelectorFromString(@"defaultDeviceWithMediaType:");
        // @"vide" = AVMediaTypeVideo
        id d = [cls respondsToSelector:sel] ? ((id (*)(id, SEL, id))objc_msgSend)(cls, sel, @"vide") : nil;
        if (G6GetBool(d, @"hasTorch")) device = d;
    });
    return device;
}

static BOOL G6CCTorchOn(void) {
    id device = G6CCTorch();
    SEL sel = NSSelectorFromString(@"torchMode");
    return [device respondsToSelector:sel] && ((int (*)(id, SEL))objc_msgSend)(device, sel) == 1;
}

static void G6CCSetTorch(BOOL on) {
    id device = G6CCTorch();
    SEL lock = NSSelectorFromString(@"lockForConfiguration:"), set = NSSelectorFromString(@"setTorchMode:");
    if (![device respondsToSelector:lock] || ![device respondsToSelector:set]) return;
    if (!((BOOL (*)(id, SEL, NSError **))objc_msgSend)(device, lock, NULL)) return;
    ((void (*)(id, SEL, int))objc_msgSend)(device, set, on ? 1 : 0);
    G6Send(device, @"unlockForConfiguration");
}

static BOOL G6CCAvailable(G6CCToggle t) {
    switch (t) {
        case G6CCCellular:
            return g6_device_is_phone() && G6CCCellularReady();
        case G6CCFlashlight:
            return g6_device_is_phone() && G6CCTorch() != nil;
        case G6CCAirplane:
            return [G6Shared("SBTelephonyManager", @"sharedTelephonyManager") respondsToSelector:NSSelectorFromString(@"setIsInAirplaneMode:")];
        case G6CCWiFi:
            return [G6Shared("SBWiFiManager", @"sharedInstance") respondsToSelector:NSSelectorFromString(@"setWiFiEnabled:")];
        case G6CCBluetooth:
            return [G6Shared("BluetoothManager", @"sharedInstance") respondsToSelector:NSSelectorFromString(@"setPowered:")];
        case G6CCQuiet:
            return G6QuietAvailable();
        case G6CCRotation:
            return [G6Shared("SBOrientationLockManager", @"sharedInstance") respondsToSelector:NSSelectorFromString(@"lock")];
        default:
            return YES;
    }
}

static BOOL G6CCState(G6CCToggle t) {
    switch (t) {
        case G6CCCellular:
            return G6CCCellularReady() && gCellularGet();
        case G6CCFlashlight:
            return G6CCTorchOn();
        case G6CCAirplane:
            return G6GetBool(G6Shared("SBTelephonyManager", @"sharedTelephonyManager"), @"isInAirplaneMode");
        case G6CCWiFi:
            return G6GetBool(G6Shared("SBWiFiManager", @"sharedInstance"), @"wiFiEnabled");
        case G6CCBluetooth:
            return G6GetBool(G6Shared("BluetoothManager", @"sharedInstance"), @"powered");
        case G6CCQuiet:
            return G6QuietActive();
        case G6CCRotation:
            return G6GetBool(G6Shared("SBOrientationLockManager", @"sharedInstance"), @"isLocked");
        default:
            return G6IsDark();
    }
}

static void G6CCSetState(G6CCToggle t, BOOL on) {
    switch (t) {
        case G6CCCellular:
            if (G6CCCellularReady()) gCellularSet(on);
            break;
        case G6CCFlashlight:
            G6CCSetTorch(on);
            break;
        case G6CCAirplane:
            G6SetBool(G6Shared("SBTelephonyManager", @"sharedTelephonyManager"), @"setIsInAirplaneMode:", on);
            break;
        case G6CCWiFi:
            G6SetBool(G6Shared("SBWiFiManager", @"sharedInstance"), @"setWiFiEnabled:", on);
            break;
        case G6CCBluetooth: {
            id bt = G6Shared("BluetoothManager", @"sharedInstance");
            G6SetBool(bt, @"setPowered:", on);
            G6SetBool(bt, @"setEnabled:", on);
            break;
        }
        case G6CCQuiet:
            G6SetQuiet(on);
            break;
        case G6CCRotation:
            G6SetRotationLocked(on);
            break;
        default: {
            // Sáng ↔ tối: ghi khoá `appearance` (0 sáng, 1 tối) rồi báo như bảng Cài đặt — mọi thành phần tự đổi theo
            NSString *path = @"/var/mobile/Library/Preferences/" G6_PREFS_DOMAIN ".plist";
            NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithContentsOfFile:path] ?: [NSMutableDictionary dictionary];
            prefs[@"appearance"] = @(on ? 1 : 0);
            if ([prefs writeToFile:path atomically:YES]) notify_post(G6_PREFS_NOTE);
            break;
        }
    }
}

// ---- Hình vẽ ----

// Màu vẽ hình; nil = trắng (thanh trượt đứng vẽ lại phần hình nằm trên vùng đã tô bằng màu tối)
static UIColor *gGlyphColor;

// Vẽ một hình (tên trong bảng dưới) vào ô vuông cạnh `s`, màu trắng
static void G6CCDrawGlyph(NSString *name, CGFloat s) {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    [(gGlyphColor ?: [UIColor whiteColor]) set];
    CGContextSetLineCap(ctx, kCGLineCapRound);
    CGContextSetLineJoin(ctx, kCGLineJoinRound);
#define P(x, y) CGPointMake((x) * s, (y) * s)
    UIBezierPath *path = [UIBezierPath bezierPath];
    if ([name isEqualToString:@"airplane"]) {
        // Máy bay nhìn từ trên xuống, mũi hướng lên
        const CGFloat pts[][2] = {{0.50, 0.06}, {0.56, 0.16}, {0.56, 0.40}, {0.92, 0.62}, {0.92, 0.70}, {0.56, 0.58}, {0.56, 0.80}, {0.68, 0.89},
                                  {0.68, 0.94}, {0.50, 0.89}, {0.32, 0.94}, {0.32, 0.89}, {0.44, 0.80}, {0.44, 0.58}, {0.08, 0.70}, {0.08, 0.62},
                                  {0.44, 0.40}, {0.44, 0.16}};
        [path moveToPoint:P(pts[0][0], pts[0][1])];
        for (int i = 1; i < 18; i++) [path addLineToPoint:P(pts[i][0], pts[i][1])];
        [path closePath];
        [path fill];
    } else if ([name isEqualToString:@"wifi"]) {
        CGPoint c = P(0.5, 0.76);
        [[UIBezierPath bezierPathWithArcCenter:c radius:0.07 * s startAngle:0 endAngle:2 * M_PI clockwise:YES] fill];
        for (int i = 1; i <= 3; i++) {
            UIBezierPath *arc = [UIBezierPath bezierPathWithArcCenter:c radius:(0.06 + 0.17 * i) * s startAngle:-M_PI * 0.75 endAngle:-M_PI * 0.25 clockwise:YES];
            arc.lineWidth = 0.085 * s;
            arc.lineCapStyle = kCGLineCapRound;
            [arc stroke];
        }
    } else if ([name isEqualToString:@"bluetooth"]) {
        [path moveToPoint:P(0.32, 0.32)];
        [path addLineToPoint:P(0.68, 0.66)];
        [path addLineToPoint:P(0.50, 0.84)];
        [path addLineToPoint:P(0.50, 0.16)];
        [path addLineToPoint:P(0.68, 0.34)];
        [path addLineToPoint:P(0.32, 0.68)];
        path.lineWidth = 0.075 * s;
        path.lineJoinStyle = kCGLineJoinRound;
        path.lineCapStyle = kCGLineCapRound;
        [path stroke];
    } else if ([name isEqualToString:@"rotation"]) {
        // Mũi tên vòng + ổ khoá ở giữa
        CGPoint c = P(0.5, 0.5);
        UIBezierPath *arc = [UIBezierPath bezierPathWithArcCenter:c radius:0.36 * s startAngle:-M_PI * 0.30 endAngle:M_PI * 1.40 clockwise:YES];
        arc.lineWidth = 0.07 * s;
        arc.lineCapStyle = kCGLineCapRound;
        [arc stroke];
        // Đầu mũi tên ở đầu cung (góc −54°)
        CGFloat a = -M_PI * 0.30;
        CGPoint tip = CGPointMake(c.x + 0.36 * s * cos(a), c.y + 0.36 * s * sin(a));
        UIBezierPath *head = [UIBezierPath bezierPath];
        [head moveToPoint:CGPointMake(tip.x + 0.13 * s, tip.y - 0.02 * s)];
        [head addLineToPoint:CGPointMake(tip.x - 0.02 * s, tip.y + 0.13 * s)];
        [head addLineToPoint:CGPointMake(tip.x - 0.08 * s, tip.y - 0.10 * s)];
        [head closePath];
        [head fill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0.39 * s, 0.47 * s, 0.22 * s, 0.18 * s) cornerRadius:0.03 * s] fill];
        UIBezierPath *shackle = [UIBezierPath bezierPathWithArcCenter:P(0.5, 0.47) radius:0.07 * s startAngle:M_PI endAngle:0 clockwise:YES];
        shackle.lineWidth = 0.045 * s;
        [shackle stroke];
    } else if ([name isEqualToString:@"quiet"]) {
        // Trăng khuyết: đĩa tròn bị khoét bởi một đĩa lệch lên trên – sang phải (cắt theo đĩa lớn rồi tô phần ngoài đĩa khoét)
        CGContextSaveGState(ctx);
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0.16 * s, 0.16 * s, 0.68 * s, 0.68 * s)] addClip];
        UIBezierPath *rest = [UIBezierPath bezierPathWithRect:CGRectMake(0, 0, s, s)];
        [rest appendPath:[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0.37 * s, 0.07 * s, 0.60 * s, 0.60 * s)]];
        rest.usesEvenOddFillRule = YES;
        [rest fill];
        CGContextRestoreGState(ctx);
    } else if ([name isEqualToString:@"dark"]) {
        CGPoint c = P(0.5, 0.5);
        UIBezierPath *ring = [UIBezierPath bezierPathWithArcCenter:c radius:0.33 * s startAngle:0 endAngle:2 * M_PI clockwise:YES];
        ring.lineWidth = 0.07 * s;
        [ring stroke];
        UIBezierPath *half = [UIBezierPath bezierPath];
        [half moveToPoint:P(0.5, 0.17)];
        [half addArcWithCenter:c radius:0.33 * s startAngle:-M_PI_2 endAngle:M_PI_2 clockwise:NO];
        [half closePath];
        [half fill];
    } else if ([name isEqualToString:@"cellular"]) {
        // Cột phát sóng: chấm + thân, hai bên mỗi bên hai cung sóng
        CGPoint c = P(0.5, 0.42);
        [[UIBezierPath bezierPathWithArcCenter:c radius:0.075 * s startAngle:0 endAngle:2 * M_PI clockwise:YES] fill];
        [path moveToPoint:P(0.5, 0.50)];
        [path addLineToPoint:P(0.5, 0.86)];
        path.lineWidth = 0.075 * s;
        path.lineCapStyle = kCGLineCapRound;
        [path stroke];
        for (int side = 0; side < 2; side++) {
            for (int i = 1; i <= 2; i++) {
                CGFloat mid = side ? 0 : M_PI, half = M_PI * 0.27;
                UIBezierPath *arc = [UIBezierPath bezierPathWithArcCenter:c radius:(0.05 + 0.14 * i) * s startAngle:mid - half endAngle:mid + half clockwise:YES];
                arc.lineWidth = 0.07 * s;
                arc.lineCapStyle = kCGLineCapRound;
                [arc stroke];
            }
        }
    } else if ([name isEqualToString:@"flashlight"]) {
        // Đèn pin dựng đứng: đầu loe + thân
        [path moveToPoint:P(0.29, 0.12)];
        [path addLineToPoint:P(0.71, 0.12)];
        [path addLineToPoint:P(0.71, 0.27)];
        [path addLineToPoint:P(0.61, 0.41)];
        [path addLineToPoint:P(0.39, 0.41)];
        [path addLineToPoint:P(0.29, 0.27)];
        [path closePath];
        [path fill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0.39 * s, 0.45 * s, 0.22 * s, 0.43 * s) cornerRadius:0.05 * s] fill];
    } else if ([name isEqualToString:@"sun"]) {
        CGPoint c = P(0.5, 0.5);
        [[UIBezierPath bezierPathWithArcCenter:c radius:0.17 * s startAngle:0 endAngle:2 * M_PI clockwise:YES] fill];
        for (int i = 0; i < 8; i++) {
            CGFloat a = i * M_PI / 4;
            UIBezierPath *ray = [UIBezierPath bezierPath];
            [ray moveToPoint:CGPointMake(c.x + 0.28 * s * cos(a), c.y + 0.28 * s * sin(a))];
            [ray addLineToPoint:CGPointMake(c.x + 0.40 * s * cos(a), c.y + 0.40 * s * sin(a))];
            ray.lineWidth = 0.07 * s;
            ray.lineCapStyle = kCGLineCapRound;
            [ray stroke];
        }
    } else if ([name isEqualToString:@"speaker"]) {
        [path moveToPoint:P(0.12, 0.40)];
        [path addLineToPoint:P(0.28, 0.40)];
        [path addLineToPoint:P(0.48, 0.22)];
        [path addLineToPoint:P(0.48, 0.78)];
        [path addLineToPoint:P(0.28, 0.60)];
        [path addLineToPoint:P(0.12, 0.60)];
        [path closePath];
        [path fill];
        for (int i = 1; i <= 2; i++) {
            UIBezierPath *arc = [UIBezierPath bezierPathWithArcCenter:P(0.50, 0.50) radius:(0.04 + 0.15 * i) * s startAngle:-M_PI * 0.23 endAngle:M_PI * 0.23 clockwise:YES];
            arc.lineWidth = 0.07 * s;
            arc.lineCapStyle = kCGLineCapRound;
            [arc stroke];
        }
    } else if ([name isEqualToString:@"play"]) {
        [path moveToPoint:P(0.30, 0.20)];
        [path addLineToPoint:P(0.82, 0.50)];
        [path addLineToPoint:P(0.30, 0.80)];
        [path closePath];
        [path fill];
    } else if ([name isEqualToString:@"pause"]) {
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0.26 * s, 0.22 * s, 0.17 * s, 0.56 * s) cornerRadius:0.03 * s] fill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0.57 * s, 0.22 * s, 0.17 * s, 0.56 * s) cornerRadius:0.03 * s] fill];
    } else if ([name isEqualToString:@"next"] || [name isEqualToString:@"prev"]) {
        // Hai tam giác; «prev» là «next» lật ngang
        if ([name isEqualToString:@"prev"]) {
            CGContextTranslateCTM(ctx, s, 0);
            CGContextScaleCTM(ctx, -1, 1);
        }
        for (int i = 0; i < 2; i++) {
            CGFloat x = 0.14 + 0.36 * i;
            UIBezierPath *tri = [UIBezierPath bezierPath];
            [tri moveToPoint:P(x, 0.26)];
            [tri addLineToPoint:P(x + 0.36, 0.50)];
            [tri addLineToPoint:P(x, 0.74)];
            [tri closePath];
            [tri fill];
        }
    }
#undef P
}

static UIImage *G6CCGlyphImage(NSString *name, CGFloat size) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0);
    G6CCDrawGlyph(name, size);
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

// Nút tròn bật / tắt: nền tròn (bật: màu `color`; tắt: trắng mờ) + hình trắng ở giữa
static UIImage *G6CCToggleImage(NSString *glyph, UIColor *color, BOOL on) {
    const CGFloat size = gToggleSize;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0);
    [(on ? color : [UIColor colorWithWhite:1 alpha:0.16]) setFill];
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, size, size)] fill];
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    const CGFloat g = round(size * 30 / kToggle);
    CGContextTranslateCTM(ctx, (size - g) / 2, (size - g) / 2);
    G6CCDrawGlyph(glyph, g);
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

static NSString *G6CCToggleGlyph(G6CCToggle t) {
    return @[@"airplane", @"wifi", @"bluetooth", @"quiet", @"rotation", @"dark", @"cellular", @"flashlight"][t];
}

static UIColor *G6CCToggleColor(G6CCToggle t) {
    switch (t) {
        case G6CCAirplane:
            return [UIColor colorWithRed:1.0 green:0.58 blue:0.0 alpha:1];
        case G6CCQuiet:
            return [UIColor colorWithRed:0.62 green:0.35 blue:0.86 alpha:1];
        case G6CCRotation:
            return [UIColor colorWithRed:0.92 green:0.26 blue:0.22 alpha:1];
        case G6CCDark:
            return [UIColor colorWithRed:0.36 green:0.34 blue:0.84 alpha:1];
        case G6CCCellular:
            return [UIColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:1];
        case G6CCFlashlight:
            return [UIColor colorWithRed:1.0 green:0.80 blue:0.0 alpha:1];
        default:
            return [UIColor colorWithRed:0.0 green:0.48 blue:1.0 alpha:1];
    }
}

// Ảnh đường trượt (viên bo tròn kéo giãn) và núm trượt
static UIImage *G6CCTrackImage(CGFloat alpha) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(9, 8), NO, 0);
    [[UIColor colorWithWhite:1 alpha:alpha] setFill];
    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, 9, 8) cornerRadius:4] fill];
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [img resizableImageWithCapInsets:UIEdgeInsetsMake(0, 4, 0, 4)];
}

static UIImage *G6CCThumbImage(void) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(30, 30), NO, 0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetShadowWithColor(ctx, CGSizeMake(0, 1), 3, [UIColor colorWithWhite:0 alpha:0.4].CGColor);
    [[UIColor whiteColor] setFill];
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(4, 3, 22, 22)] fill];
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

// ---- Trạng thái ----

static float G6CCCurrentBrightness(void) {
    static float (*get)(void);
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *h = dlopen("/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices", RTLD_NOW);
        if (h) get = dlsym(h, "BKSDisplayBrightnessGetCurrent");
    });
    return get ? get() : 0.5f;
}

static void G6CCRefresh(void) {
    for (UIButton *b in gToggles) {
        G6CCToggle t = (G6CCToggle)b.tag;
        BOOL on = G6CCState(t);
        b.selected = on;
        [b setImage:G6CCToggleImage(G6CCToggleGlyph(t), G6CCToggleColor(t), on) forState:UIControlStateNormal];
    }
    id media = G6Shared("SBMediaController", @"sharedInstance");
    if (!gBrightness.tracking) gBrightness.value = G6CCCurrentBrightness();
    SEL volumeSel = NSSelectorFromString(@"volume");
    if (!gVolume.tracking && [media respondsToSelector:volumeSel]) gVolume.value = ((float (*)(id, SEL))objc_msgSend)(media, volumeSel);
    NSString *title = G6GetObject(media, @"nowPlayingTitle"), *artist = G6GetObject(media, @"nowPlayingArtist");
    BOOL hasTrack = [title isKindOfClass:[NSString class]] && title.length > 0;
    gTitle.text = hasTrack ? title : G6L(@"Không phát");
    gArtist.text = hasTrack && [artist isKindOfClass:[NSString class]] ? artist : @"";
    [gPlay setImage:G6CCGlyphImage(G6GetBool(media, @"isPlaying") ? @"pause" : @"play", 26) forState:UIControlStateNormal];
}

// ---- Đích của nút / thanh trượt ----

@interface G6CCTarget : NSObject
@end

// Thanh trượt đứng của iPhone: viên bo tròn, phần đã tô dâng từ dưới lên, hình (mặt trời / loa) ở chân. Kéo tương đối.
@interface G6CCVSlider : UIControl
@property (nonatomic) float value;
@property (nonatomic, copy) NSString *glyph;
@end

@implementation G6CCVSlider {
    CGFloat _startY;
    float _startValue;
}

- (void)setValue:(float)value {
    value = MAX(0, MIN(1, value));
    if (value == _value) return;
    _value = value;
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    CGRect b = self.bounds;
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    [[UIBezierPath bezierPathWithRoundedRect:b cornerRadius:22] addClip];
    [[UIColor colorWithWhite:1 alpha:0.16] setFill];
    CGContextFillRect(ctx, b);
    CGRect fill = CGRectMake(0, round(b.size.height * (1 - _value)), b.size.width, b.size.height);
    [[UIColor colorWithWhite:1 alpha:0.92] setFill];
    CGContextFillRect(ctx, fill);
    if (!_glyph) return;
    // Hình ở chân: trắng trên nền mờ, tối trên phần đã tô
    const CGFloat g = 26;
    CGPoint origin = CGPointMake(round((b.size.width - g) / 2), b.size.height - g - 12);
    for (int pass = 0; pass < 2; pass++) {
        CGContextSaveGState(ctx);
        if (pass == 1) {
            CGContextClipToRect(ctx, fill);
            gGlyphColor = [UIColor colorWithWhite:0.15 alpha:1];
        }
        CGContextTranslateCTM(ctx, origin.x, origin.y);
        G6CCDrawGlyph(_glyph, g);
        gGlyphColor = nil;
        CGContextRestoreGState(ctx);
    }
}

- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    _startY = [touch locationInView:self].y;
    _startValue = _value;
    return YES;
}

- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    CGFloat height = MAX(1, self.bounds.size.height);
    self.value = _startValue + (_startY - [touch locationInView:self].y) / height;
    [self sendActionsForControlEvents:UIControlEventValueChanged];
    return YES;
}

@end

// Tấm của bảng: mỗi lần có ngón chạm vào (hitTest chạy lúc chạm xuống) thì tính lại thời gian chờ tự ẩn
@interface G6CCPanelView : UIView
@end

static void G6CCArmHideTimer(void);

@implementation G6CCPanelView

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit) G6CCArmHideTimer();
    return hit;
}

@end

@implementation G6CCTarget

// Hết thời gian chờ mà không ai đụng tới: tự ẩn
+ (void)hideTimeout:(NSTimer *)timer {
    gHideTimer = nil;
    if (!gVisible) return;
    G6Log(@"control center: tự ẩn (hết thời gian chờ)");
    G6ControlCenterSetVisible(NO, YES);
}

// Ngón tay đặt trên thanh trượt đứng là để kéo thanh, không phải vuốt lên để đóng
+ (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
    return ![touch.view isKindOfClass:[G6CCVSlider class]];
}

// Vuốt lên trên bảng (hoặc ngoài bảng): đóng
+ (void)swipeUp:(UIGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateRecognized) {
        G6Log(@"control center: đóng do vuốt lên");
        G6ControlCenterSetVisible(NO, YES);
    }
}

+ (void)toggle:(UIButton *)button {
    @try {
        G6CCToggle t = (G6CCToggle)button.tag;
        G6CCSetState(t, !G6CCState(t));
    } @catch (NSException *e) {
        G6Log(@"control center: lỗi khi bật / tắt: %@", e);
    }
    // Trạng thái thật đổi chậm một nhịp (Wi-Fi, Bluetooth) → đọc lại ngay và sau nửa giây
    G6CCRefresh();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (gVisible) G6CCRefresh();
    });
}

+ (void)brightness:(UISlider *)slider {
    G6CCArmHideTimer();  // đang kéo thanh trượt: đừng tự ẩn giữa chừng
    id ctl = G6Shared("SBBrightnessController", @"sharedBrightnessController");
    SEL sel = NSSelectorFromString(@"setBrightnessLevel:");
    if ([ctl respondsToSelector:sel]) ((void (*)(id, SEL, float))objc_msgSend)(ctl, sel, slider.value);
}

+ (void)volume:(UISlider *)slider {
    G6CCArmHideTimer();
    id media = G6Shared("SBMediaController", @"sharedInstance");
    SEL sel = NSSelectorFromString(@"setVolume:");
    if ([media respondsToSelector:sel]) ((void (*)(id, SEL, float))objc_msgSend)(media, sel, slider.value);
}

+ (void)media:(UIButton *)button {
    id media = G6Shared("SBMediaController", @"sharedInstance");
    if (button.tag == 0) {
        G6Send(media, @"togglePlayPause");
    } else {
        SEL sel = NSSelectorFromString(@"changeTrack:");
        if ([media respondsToSelector:sel]) ((BOOL (*)(id, SEL, int))objc_msgSend)(media, sel, (int)button.tag);
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (gVisible) G6CCRefresh();
    });
}

+ (void)dismiss:(id)sender {
    G6ControlCenterSetVisible(NO, YES);
}

+ (void)refresh:(NSTimer *)timer {
    if (!gVisible) return;
    // Máy vừa khoá lúc bảng đang mở: đóng (cửa sổ của bảng nằm trên cả màn khoá)
    if (G6GetBool(G6Shared("SBAwayController", @"sharedAwayControllerIfExists"), @"isLocked")) {
        G6ControlCenterSetVisible(NO, NO);
        return;
    }
    G6CCRefresh();
}

@end

// ---- Dựng bảng ----

// (Đặt lại) đồng hồ tự ẩn theo cấu hình `cc_timeout` (giây; 0 = không tự ẩn)
static void G6CCArmHideTimer(void) {
    [gHideTimer invalidate];
    gHideTimer = nil;
    NSInteger seconds = [G6Config()[@"cc_timeout"] integerValue];
    if (!gVisible || seconds <= 0) return;
    gHideTimer = [NSTimer scheduledTimerWithTimeInterval:seconds target:[G6CCTarget class] selector:@selector(hideTimeout:) userInfo:nil repeats:NO];
}

static UISlider *G6CCMakeSlider(CGRect frame, NSString *glyph, SEL action, UIView *parent) {
    UIImageView *icon = [[UIImageView alloc] initWithImage:G6CCGlyphImage(glyph, 24)];
    icon.frame = CGRectMake(frame.origin.x, frame.origin.y + (frame.size.height - 24) / 2, 24, 24);
    icon.alpha = 0.9;
    [parent addSubview:icon];
    UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(frame.origin.x + 34, frame.origin.y, frame.size.width - 34, frame.size.height)];
    [slider setMinimumTrackImage:G6CCTrackImage(0.92) forState:UIControlStateNormal];
    [slider setMaximumTrackImage:G6CCTrackImage(0.22) forState:UIControlStateNormal];
    [slider setThumbImage:G6CCThumbImage() forState:UIControlStateNormal];
    [slider addTarget:[G6CCTarget class] action:action forControlEvents:UIControlEventValueChanged];
    [parent addSubview:slider];
    return slider;
}

static UILabel *G6CCMakeLabel(CGRect frame, G6FontWeight weight, CGFloat size, CGFloat alpha, UIView *parent) {
    UILabel *label = [[UILabel alloc] initWithFrame:frame];
    label.backgroundColor = [UIColor clearColor];
    label.textColor = [UIColor colorWithWhite:1 alpha:alpha];
    label.font = G6Font(weight, size);
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    [parent addSubview:label];
    return label;
}

// ---- Bảng của iPhone: lưới ô kính ----

static UIView *G6CCMakeTile(CGRect frame) {
    UIView *tile = [[UIView alloc] initWithFrame:frame];
    tile.backgroundColor = [UIColor colorWithWhite:1 alpha:0.10];
    tile.layer.cornerRadius = 22;
    [gPanel addSubview:tile];
    return tile;
}

// Xếp các nút tròn (những nút máy này làm được) thành lưới 2 × 2 trong một ô
static void G6CCAddToggleGrid(UIView *tile, const G6CCToggle *list, int count) {
    CGFloat size = gToggleSize, step = tile.bounds.size.width - 2 * kTileInset - size;
    int placed = 0;
    for (int i = 0; i < count; i++) {
        if (!G6CCAvailable(list[i])) continue;
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.frame = CGRectMake(kTileInset + (placed % 2) * step, kTileInset + (placed / 2) * step, size, size);
        b.tag = list[i];
        [b addTarget:[G6CCTarget class] action:@selector(toggle:) forControlEvents:UIControlEventTouchUpInside];
        [tile addSubview:b];
        [gToggles addObject:b];
        placed++;
    }
}

static void G6CCBuildPhonePanel(void) {
    BOOL landscape = UIInterfaceOrientationIsLandscape([UIApplication sharedApplication].statusBarOrientation);
    const CGFloat tile = landscape ? kTileLandscape : kTilePortrait, gap = landscape ? kTileGapLandscape : kTileGapPortrait;
    const int columns = landscape ? 4 : 2, rows = 4 / columns;
    gPanel = [[G6CCPanelView alloc] initWithFrame:CGRectZero];
    gGlass = [[UIImageView alloc] initWithFrame:CGRectZero];
    gGlass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [gPanel addSubview:gGlass];
    gToggles = [NSMutableArray array];
    // Hai nút tròn mỗi hàng trong ô, khe giữa bằng lề trong ô
    gToggleSize = floor((tile - 3 * kTileInset) / 2);
    CGRect cell[4];
    for (int i = 0; i < 4; i++) cell[i] = CGRectMake(kTilePad + (i % columns) * (tile + gap), kTilePad + (i / columns) * (tile + gap), tile, tile);

    // Ô 1: kết nối
    static const G6CCToggle network[] = {G6CCAirplane, G6CCCellular, G6CCWiFi, G6CCBluetooth};
    G6CCAddToggleGrid(G6CCMakeTile(cell[0]), network, 4);

    // Ô 2: bài đang phát + ba nút
    UIView *music = G6CCMakeTile(cell[1]);
    gTitle = G6CCMakeLabel(CGRectMake(14, 16, tile - 28, 18), G6FontSemiBold, 13, 1, music);
    gArtist = G6CCMakeLabel(CGRectMake(14, 35, tile - 28, 16), G6FontRegular, 11.5, 0.7, music);
    NSArray *glyphs = @[@"prev", @"play", @"next"];
    CGFloat buttonWidth = floor((tile - 16) / 3);
    for (int i = 0; i < 3; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.frame = CGRectMake(8 + i * buttonWidth, tile - 16 - 40, buttonWidth, 40);
        b.tag = i - 1;
        [b setImage:G6CCGlyphImage(glyphs[i], i == 1 ? 28 : 22) forState:UIControlStateNormal];
        [b addTarget:[G6CCTarget class] action:@selector(media:) forControlEvents:UIControlEventTouchUpInside];
        [music addSubview:b];
        if (i == 1) gPlay = b;
    }

    // Ô 3: chế độ
    static const G6CCToggle modes[] = {G6CCQuiet, G6CCRotation, G6CCDark, G6CCFlashlight};
    G6CCAddToggleGrid(G6CCMakeTile(cell[2]), modes, 4);

    // Ô 4: hai thanh trượt đứng — độ sáng, âm lượng
    CGFloat sliderWidth = floor((tile - gap) / 2);
    NSArray *sliders = @[@[@"sun", NSStringFromSelector(@selector(brightness:))], @[@"speaker", NSStringFromSelector(@selector(volume:))]];
    for (int i = 0; i < 2; i++) {
        CGFloat x = i == 0 ? cell[3].origin.x : CGRectGetMaxX(cell[3]) - sliderWidth;
        G6CCVSlider *slider = [[G6CCVSlider alloc] initWithFrame:CGRectMake(x, cell[3].origin.y, sliderWidth, tile)];
        slider.backgroundColor = [UIColor clearColor];
        slider.opaque = NO;
        slider.contentMode = UIViewContentModeRedraw;
        slider.glyph = sliders[i][0];
        [slider addTarget:[G6CCTarget class] action:NSSelectorFromString(sliders[i][1]) forControlEvents:UIControlEventValueChanged];
        [gPanel addSubview:slider];
        // Cùng tên hàm `value` / `setValue:` / `tracking` với UISlider nên phần còn lại của mã dùng chung
        if (i == 0) gBrightness = (UISlider *)slider;
        else gVolume = (UISlider *)slider;
    }
    gPanel.bounds = CGRectMake(0, 0, 2 * kTilePad + columns * tile + (columns - 1) * gap, 2 * kTilePad + rows * tile + (rows - 1) * gap);
}

static void G6CCBuildPanel(void) {
    if (g6_device_is_phone()) {
        G6CCBuildPhonePanel();
        return;
    }
    CGFloat y = kPad;
    gPanel = [[G6CCPanelView alloc] initWithFrame:CGRectZero];
    gGlass = [[UIImageView alloc] initWithFrame:CGRectZero];
    gGlass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [gPanel addSubview:gGlass];

    // Hàng nút tròn: chỉ những nút máy này làm được
    gToggles = [NSMutableArray array];
    NSMutableArray *available = [NSMutableArray array];
    for (int t = 0; t < G6CCToggleCount; t++) {
        if (G6CCAvailable((G6CCToggle)t)) [available addObject:@(t)];
    }
    // Sáu nút cỡ 54 không vừa bề ngang bảng: thu nhỏ cả hàng sao cho khe giữa các nút còn ít nhất kToggleGap
    CGFloat room = kPanelWidth - 2 * kPad, count = MAX(1, (CGFloat)available.count);
    gToggleSize = MIN(kToggle, floor((room - (count - 1) * kToggleGap) / count));
    CGFloat gap = available.count > 1 ? (room - available.count * gToggleSize) / (available.count - 1) : 0;
    CGFloat x = kPad;
    for (NSNumber *t in available) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.frame = CGRectMake(round(x), y, gToggleSize, gToggleSize);
        b.tag = t.intValue;
        [b addTarget:[G6CCTarget class] action:@selector(toggle:) forControlEvents:UIControlEventTouchUpInside];
        [gPanel addSubview:b];
        [gToggles addObject:b];
        x += gToggleSize + gap;
    }
    y += gToggleSize + 12;

    gBrightness = G6CCMakeSlider(CGRectMake(kPad + 2, y, kPanelWidth - 2 * kPad - 4, kRow), @"sun", @selector(brightness:), gPanel);
    y += kRow + kRowGap;
    gVolume = G6CCMakeSlider(CGRectMake(kPad + 2, y, kPanelWidth - 2 * kPad - 4, kRow), @"speaker", @selector(volume:), gPanel);
    y += kRow + 12;

    // Khối nhạc: nền trắng mờ bo góc, tên bài + nghệ sĩ, ba nút
    UIView *music = [[UIView alloc] initWithFrame:CGRectMake(kPad, y, kPanelWidth - 2 * kPad, kMusicHeight)];
    music.backgroundColor = [UIColor colorWithWhite:1 alpha:0.10];
    music.layer.cornerRadius = 16;
    [gPanel addSubview:music];
    CGFloat buttons = 3 * 40 + 8, textWidth = music.bounds.size.width - buttons - 20;
    gTitle = G6CCMakeLabel(CGRectMake(14, 11, textWidth, 20), G6FontSemiBold, 14, 1, music);
    gArtist = G6CCMakeLabel(CGRectMake(14, 32, textWidth, 18), G6FontRegular, 12, 0.7, music);
    NSArray *glyphs = @[@"prev", @"play", @"next"];
    for (int i = 0; i < 3; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.frame = CGRectMake(music.bounds.size.width - buttons + i * 40, (kMusicHeight - 40) / 2, 40, 40);
        // -changeTrack: nhận −1 (bài trước) / +1 (bài sau); 0 = phát / dừng
        b.tag = i - 1;
        [b setImage:G6CCGlyphImage(glyphs[i], i == 1 ? 26 : 22) forState:UIControlStateNormal];
        [b addTarget:[G6CCTarget class] action:@selector(media:) forControlEvents:UIControlEventTouchUpInside];
        [music addSubview:b];
        if (i == 1) gPlay = b;
    }
    y += kMusicHeight + kPad;
    gPanel.bounds = CGRectMake(0, 0, kPanelWidth, y);
}

// ---- Hiện / ẩn ----

static void G6CCTearDown(void) {
    [gRefreshTimer invalidate];
    gRefreshTimer = nil;
    [gHideTimer invalidate];
    gHideTimer = nil;
    gWindow.hidden = YES;
    gWindow = nil;
    gRoot = gPanel = nil;
    gGlass = nil;
    gToggles = nil;
    gBrightness = gVolume = nil;
    gTitle = gArtist = nil;
    gPlay = nil;
}

void G6ControlCenterSetVisible(BOOL visible, BOOL animated) {
    if (visible == gVisible) return;
    if (!visible) {
        gVisible = NO;
        UIWindow *window = gWindow;
        [UIView animateWithDuration:animated ? 0.18 : 0
                         animations:^{
                             gPanel.alpha = 0;
                             gPanel.transform = CGAffineTransformMakeTranslation(0, -16);
                         }
                         completion:^(BOOL finished) {
                             // Trong lúc đang mờ dần người dùng có thể đã mở lại
                             if (!gVisible && gWindow == window) G6CCTearDown();
                         }];
        return;
    }
    if (!G6Feature(@"control_center")) return;
    @try {
        G6CCTearDown();
        // Chụp màn hình trước khi cửa sổ của bảng hiện
        G6Backdrop *backdrop = [G6Backdrop backdropWithScreen:YES];
        UIScreen *screen = [UIScreen mainScreen];
        UIInterfaceOrientation orientation = [UIApplication sharedApplication].statusBarOrientation;
        BOOL landscape = UIInterfaceOrientationIsLandscape(orientation);
        // bounds của UIScreen trên iOS 6 luôn theo hệ dọc
        CGSize full = screen.bounds.size;
        CGSize ui = landscape ? CGSizeMake(full.height, full.width) : full;
        gWindow = [[UIWindow alloc] initWithFrame:screen.bounds];
        gWindow.windowLevel = 1055;
        gWindow.backgroundColor = [UIColor clearColor];
        // Khung xoay theo hướng giao diện (như các cửa sổ của SpringBoard): 1: 0°, 2: 180°, 3: +90°, 4: −90°
        static const CGFloat angles[5] = {0, 0, M_PI, M_PI_2, -M_PI_2};
        gRoot = [[UIView alloc] initWithFrame:CGRectZero];
        gRoot.bounds = CGRectMake(0, 0, ui.width, ui.height);
        gRoot.center = CGPointMake(full.width / 2, full.height / 2);
        gRoot.transform = CGAffineTransformMakeRotation(angles[(orientation >= 1 && orientation <= 4) ? orientation : 1]);
        [gWindow addSubview:gRoot];
        // Chạm ra ngoài bảng → đóng
        UIControl *catcher = [[UIControl alloc] initWithFrame:gRoot.bounds];
        [catcher addTarget:[G6CCTarget class] action:@selector(dismiss:) forControlEvents:UIControlEventTouchDown];
        [gRoot addSubview:catcher];
        // Vuốt lên ở bất cứ đâu (trên bảng hay ngoài bảng) → đóng, như Control Center của iOS đời sau
        UISwipeGestureRecognizer *swipe = [[UISwipeGestureRecognizer alloc] initWithTarget:[G6CCTarget class] action:@selector(swipeUp:)];
        swipe.direction = UISwipeGestureRecognizerDirectionUp;
        swipe.delegate = (id<UIGestureRecognizerDelegate>)[G6CCTarget class];
        [gRoot addGestureRecognizer:swipe];

        G6CCBuildPanel();
        CGSize size = gPanel.bounds.size;
        CGRect frame = CGRectMake(ui.width - size.width - kPanelRight, kPanelTop, size.width, size.height);
        // iPhone: bảng rộng gần hết màn hình → canh giữa, ngay dưới thanh trạng thái
        if (g6_device_is_phone()) frame = CGRectMake(round((ui.width - size.width) / 2), landscape ? 24 : kPanelTop, size.width, size.height);
        gPanel.frame = frame;
        [gRoot addSubview:gPanel];
        gWindow.hidden = NO;
        gGlass.frame = gPanel.bounds;
        gGlass.image = G6GlassImageForRect(@"hud", gRoot, frame, YES, backdrop);
        G6CCRefresh();
        gVisible = YES;
        // Trạng thái có thể đổi từ bên ngoài lúc bảng đang mở (bài hát chuyển, Wi-Fi vừa nối…)
        gRefreshTimer = [NSTimer scheduledTimerWithTimeInterval:2 target:[G6CCTarget class] selector:@selector(refresh:) userInfo:nil repeats:YES];
        G6CCArmHideTimer();
        gPanel.alpha = 0;
        gPanel.transform = CGAffineTransformMakeTranslation(0, -16);
        [UIView animateWithDuration:animated ? 0.22 : 0
                         animations:^{
                             gPanel.alpha = 1;
                             gPanel.transform = CGAffineTransformIdentity;
                         }];
    } @catch (NSException *e) {
        G6Log(@"control center: lỗi khi mở: %@", e);
        G6CCTearDown();
        gVisible = NO;
    }
}

#if G6_DEBUG
void G6ControlCenterDebug(NSString *arg) {
    NSArray *parts = [arg componentsSeparatedByString:@" "];
    NSString *verb = parts.count ? parts[0] : @"", *what = parts.count > 1 ? parts[1] : @"";
    if (!gVisible) {
        G6Log(@"[thử] control center: bảng chưa mở");
        return;
    }
    if ([verb isEqualToString:@"tap"]) {
        NSArray *names = @[@"airplane", @"wifi", @"bluetooth", @"quiet", @"rotation", @"dark", @"cellular", @"flashlight"];
        NSUInteger t = [names indexOfObject:what];
        UIButton *target = nil;
        if (t != NSNotFound) {
            for (UIButton *b in gToggles) {
                if ((NSUInteger)b.tag == t) target = b;
            }
        } else if ([what isEqualToString:@"play"]) {
            target = gPlay;
        } else if ([what isEqualToString:@"prev"] || [what isEqualToString:@"next"]) {
            for (UIView *v in gPlay.superview.subviews) {
                if ([v isKindOfClass:[UIButton class]] && v.tag == ([what isEqualToString:@"prev"] ? -1 : 1)) target = (UIButton *)v;
            }
        }
        if (target) [target sendActionsForControlEvents:UIControlEventTouchUpInside];
        else G6Log(@"[thử] control center: không có nút «%@»", what);
    } else if ([verb isEqualToString:@"brightness"] || [verb isEqualToString:@"volume"]) {
        UISlider *slider = [verb isEqualToString:@"brightness"] ? gBrightness : gVolume;
        slider.value = what.floatValue;
        [slider sendActionsForControlEvents:UIControlEventValueChanged];
    }
    // Trạng thái thật của máy (đọc thẳng từ SpringBoard, không qua nút)
    id media = G6Shared("SBMediaController", @"sharedInstance");
    SEL volumeSel = NSSelectorFromString(@"volume");
    float volume = [media respondsToSelector:volumeSel] ? ((float (*)(id, SEL))objc_msgSend)(media, volumeSel) : -1;
    G6Log(@"[thử] control center: máy bay %d, Wi-Fi %d, Bluetooth %d, không làm phiền %d (có nút: %d), khoá xoay %d, tối %d, độ sáng %.2f, âm lượng %.2f, đang phát %d, bài «%@»",
          G6CCState(G6CCAirplane), G6CCState(G6CCWiFi), G6CCState(G6CCBluetooth), G6CCState(G6CCQuiet), G6CCAvailable(G6CCQuiet),
          G6CCState(G6CCRotation), G6CCState(G6CCDark),
          G6CCCurrentBrightness(), volume, G6GetBool(media, @"isPlaying"), G6GetObject(media, @"nowPlayingTitle"));
}
#endif

// ---- Cử chỉ kéo từ mép trên ----

static BOOL gGestureMine;
static CGPoint gGestureStart, gGestureLast;

// Điểm bắt đầu có nằm ở một phần ba bên phải của mép trên không (toạ độ theo hướng giao diện)
static BOOL G6CCIsRightZone(CGPoint location) {
    CGSize full = [UIScreen mainScreen].bounds.size;
    BOOL landscape = UIInterfaceOrientationIsLandscape([UIApplication sharedApplication].statusBarOrientation);
    CGFloat width = landscape ? full.height : full.width;
    return location.x > width * 2 / 3;
}

static void (*o_gestureBegan)(id, SEL, CGPoint);
static void g6_gestureBegan(id self, SEL _cmd, CGPoint location) {
    gGestureMine = !gVisible && G6Feature(@"control_center") && G6CCIsRightZone(location);
#if G6_DEBUG
    G6Log(@"control center: cử chỉ kéo từ mép trên bắt đầu ở %@ → %@", NSStringFromCGPoint(location), gGestureMine ? @"Control Center" : @"Trung tâm thông báo");
#endif
    if (gGestureMine) {
        gGestureStart = gGestureLast = location;
        return;
    }
    o_gestureBegan(self, _cmd, location);
}

static void (*o_gestureChanged)(id, SEL, CGPoint, CGPoint);
static void g6_gestureChanged(id self, SEL _cmd, CGPoint location, CGPoint velocity) {
    if (gGestureMine) {
        gGestureLast = location;
        return;
    }
    o_gestureChanged(self, _cmd, location, velocity);
}

static void (*o_gestureEnded)(id, SEL, CGPoint, CGPoint);
static void g6_gestureEnded(id self, SEL _cmd, CGPoint location, CGPoint velocity) {
    if (gGestureMine) {
        gGestureMine = NO;
        if (location.y - gGestureStart.y > kPullDistance || velocity.y > 300) G6ControlCenterSetVisible(YES, YES);
        return;
    }
    o_gestureEnded(self, _cmd, location, velocity);
}

static void (*o_gestureCancelled)(id, SEL);
static void g6_gestureCancelled(id self, SEL _cmd) {
    if (gGestureMine) {
        gGestureMine = NO;
        return;
    }
    o_gestureCancelled(self, _cmd);
}

static void (*o_gestureFailed)(id, SEL);
static void g6_gestureFailed(id self, SEL _cmd) {
    if (gGestureMine) {
        gGestureMine = NO;
        return;
    }
    o_gestureFailed(self, _cmd);
}

// Nút Home lúc bảng đang mở: đóng bảng, không làm gì khác
static BOOL (*o_clickedMenuButton)(id, SEL);
static BOOL g6_clickedMenuButton(id self, SEL _cmd) {
    if (gVisible) {
        G6ControlCenterSetVisible(NO, YES);
        return YES;
    }
    return o_clickedMenuButton(self, _cmd);
}

void G6ControlCenterInstall(void) {
    Class ui = objc_getClass("SBUIController");
    SEL began = NSSelectorFromString(@"_showNotificationsGestureBeganWithLocation:");
    SEL changed = NSSelectorFromString(@"_showNotificationsGestureChangedWithLocation:velocity:");
    SEL ended = NSSelectorFromString(@"_showNotificationsGestureEndedWithLocation:velocity:");
    SEL cancelled = NSSelectorFromString(@"_showNotificationsGestureCancelled"), failed = NSSelectorFromString(@"_showNotificationsGestureFailed");
    // Phải móc được đủ cả năm hàm của cử chỉ: giữ lại «bắt đầu» mà để lọt «kết thúc» thì SpringBoard nhận cử chỉ cụt đầu
    if (!ui || !class_getInstanceMethod(ui, began) || !class_getInstanceMethod(ui, changed) || !class_getInstanceMethod(ui, ended) ||
        !class_getInstanceMethod(ui, cancelled) || !class_getInstanceMethod(ui, failed)) {
        G6Log(@"control center: thiếu hàm cử chỉ của SBUIController — không gắn cử chỉ mở");
    } else {
        G6Hook(ui, began, (IMP)g6_gestureBegan, (IMP *)&o_gestureBegan);
        G6Hook(ui, changed, (IMP)g6_gestureChanged, (IMP *)&o_gestureChanged);
        G6Hook(ui, ended, (IMP)g6_gestureEnded, (IMP *)&o_gestureEnded);
        G6Hook(ui, cancelled, (IMP)g6_gestureCancelled, (IMP *)&o_gestureCancelled);
        G6Hook(ui, failed, (IMP)g6_gestureFailed, (IMP *)&o_gestureFailed);
    }
    if (ui && class_getInstanceMethod(ui, NSSelectorFromString(@"clickedMenuButton"))) {
        G6Hook(ui, NSSelectorFromString(@"clickedMenuButton"), (IMP)g6_clickedMenuButton, (IMP *)&o_clickedMenuButton);
    }
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    // Xoay máy → đóng bảng (khung và tấm kính đã dựng theo hướng cũ). Đổi cấu hình (kể cả vừa bấm nút sáng / tối) → đọc lại
    // trạng thái các nút; thành phần vừa bị tắt thì đóng.
    [nc addObserverForName:UIApplicationDidChangeStatusBarOrientationNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *note) {
                    G6ControlCenterSetVisible(NO, NO);
                }];
    [nc addObserverForName:G6ConfigDidChangeNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *note) {
                    if (gVisible && !G6Feature(@"control_center")) G6ControlCenterSetVisible(NO, NO);
                    else if (gVisible) G6CCRefresh();
                }];
}

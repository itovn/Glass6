// Màn khoá — iOS 6 → kính.
//
// iOS 6 trên iPad (tra trên máy 19/11/2026): cửa sổ SBAlertWindow (mức 1050) › UIView (xoay theo máy) › SBAwayView
//   SBWallpaperView                       hình nền màn khoá (có thể khác hình nền màn hình chính)
//   SBAwayBulletinListView                danh sách thông báo
//   TPLCDView : TPLCDBar : UIImageView    thanh trên — ảnh nền bóng kính (image), nét bóng (-shadowView)
//     … SBAwayDateView (-[SBAwayView _dateHeaderView])
//         TPLCDTextView _timeLabel, _dateAndTetheringLabel   tự vẽ chữ; đổi phông bằng -setLCDTextFont:
//   SBAwayLockBar : TPBottomLockBar : TPBottomBar (_lockBar) thanh dưới — nền vẽ trong drawRect (tắt bằng
//                                         -setSuppressDrawingBackground:), _backgroundView, -shadowView
//       TPWell (_well, UIImageView)       rãnh trượt
//         TPLockTextView (_labelView), TPLockKnobView (_knobView, UIImageView)
//       UIButton (_slideshowButton)       nút khung ảnh: ảnh nền + ảnh biểu tượng
// GramLockControl (tweak của anh) thêm GLCPanel vào SBAwayView và cũng móc layoutSubviews / didMoveToWindow của SBAwayView —
// ở đây không đụng tới view của nó, không đổi khung của view nào.
//
// Cách làm: chỉ đổi vật liệu, giữ nguyên bố cục và cách trượt mở khoá —
//   - thanh trên: bỏ ảnh nền + nét bóng; giờ → Inter SemiBold, ngày → Inter Medium (cùng cỡ chữ gốc);
//   - thanh dưới: bỏ nền; rãnh trượt → viên kính (bề mặt `capsule`), nền là hình nền màn khoá đã mờ đúng chỗ; núm trượt vẽ
//     lại; nút khung ảnh → nền kính tròn.
//   - nút khung ảnh (hình bông hoa — anh yêu cầu ẩn, 19/11/2026): ẩn bằng chính hàm của SpringBoard
//     -[SBAwayLockBar setShowsSlideshowButton:] (nó gỡ nút khỏi thanh, vùng chạm cũng mất), theo khoá cấu hình
//     `lockHidePictureFrame` (mặc định ẩn). SpringBoard gọi hàm đó mỗi lần dựng màn khoá nên móc nó: nhớ ý SpringBoard muốn
//     (hiện / không) và ép «không» khi đang ẩn; bỏ ẩn thì trả đúng ý đó.
//   - mục «Chưa cài đặt Thẻ SIM» trong danh sách thông báo của màn khoá (anh yêu cầu ẩn, 19/11/2026): đó là một
//     SBSIMLockAlertItem trạng thái 3, SBAwayController đưa vào danh sách qua -[SBAwayBulletinListController
//     activateAlertItem:didUndimScreen:]. Móc hàm đó, bỏ qua đúng mục này (khoá cấu hình `lockHideNoSIM`, mặc định ẩn); mục
//     đã lỡ hiện thì gỡ bằng -deactivateAlertItem:. Các cảnh báo SIM khác (lỗi SIM, khoá SIM, khoá PUK…) để nguyên.
//   - khung danh sách thông báo (SBAwayBulletinListView: ảnh khung đen bóng + bảng các ô + hai ảnh bóng): ảnh khung → tấm
//     kính đậm (bề mặt `list`, nền = hình nền màn khoá đã mờ), hai ảnh bóng ẩn; khung đổi cỡ theo số thông báo thì dựng lại.
//     Chữ trong ô đã là Inter nhờ G6NotificationCenter (dùng chung SBBulletinCellContentView).
//   - hình viên pin lớn lúc đang sạc (SBAwayChargingView — anh yêu cầu bỏ, 19/11/2026: iOS 26 không có, mà nó còn che cả
//     hình nền thành đen): SpringBoard hỏi -[SBAwayView shouldShowChargingView] trước khi hiện → móc, trả NO (khoá cấu hình
//     `lockHideBattery`, mặc định ẩn). Thay vào đó, kiểu iOS 26: lúc màn khoá sáng lên / vừa cắm sạc, dòng ngày đổi thành
//     «Đã sạc N%» trong vài giây rồi trở lại ngày.
//   - iPhone (kiểu iOS 26 của iPhone): dòng ngày nằm trên, giờ thật lớn nằm dưới (đổi cỡ phông + đặt lại khung hai nhãn sau
//     mỗi lần SpringBoard xếp); nút máy ảnh ở góc phải (_cameraGrabber, vẫn kéo lên để mở máy ảnh) → nút tròn bằng kính.
//     Lúc đang hiện nút điều khiển nhạc / đang phát nhạc thì giữ bố cục gốc (chỉ đổi phông).
//   - iPhone, thông báo trên màn khoá (tra trên máy 20/11/2026, lệnh thử `lockbulletin`): khác iPad — không có ảnh khung.
//     Một thông báo mới: ô «nổi» giữa màn hình (SBAwayBulletinFloatingCell trong _firstAlertTableView, nền là ảnh đen bóng
//     _firstAlertBGView 304×81). Nhiều thông báo: bảng các dòng 44 điểm chạy hết bề ngang (SBAwayListItemCell: nền đen mờ
//     đặt qua -setBackgroundColor:, hai nét kẻ _separatorTopHalf / _separatorBottomHalf). Kiểu iOS 26: ảnh nền của ô nổi →
//     tấm kính (bề mặt `list`, nền = hình nền màn khoá đã mờ); mỗi dòng → một thẻ kính bo góc lùi vào hai bên (kính không
//     nền, một ảnh dùng chung cho mọi dòng cùng cỡ — dòng cuộn được nên không dựng theo vị trí), bỏ nền đen + nét kẻ, nội
//     dung của dòng thu nhỏ một chút cho lọt vào thẻ (sublayerTransform — không đụng khung của view nào); cả danh sách hạ
//     xuống vài điểm cho thoáng dưới chữ số giờ.
// Mọi ảnh / phông gốc được cất lại trên chính view đó; tắt thành phần lúc đang chạy thì trả lại nguyên trạng.
#import "G6Lock.h"

#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "G6Device.h"
#import "G6Font.h"
#import "G6Glass.h"
#import "G6Hook.h"
#import "G6Lang.h"
#import "G6Log.h"
#import "G6Prefs.h"
#import "G6Wallpaper.h"

// Máy nằm ngang: hạ cả cụm giờ + ngày xuống chừng này điểm (anh yêu cầu 19/11/2026 — nằm ngang thì đồng hồ sát mép trên quá)
static const CGFloat kLandscapeClockDrop = 24;
// iPhone: cỡ chữ giờ / ngày và chỗ đặt, tính trong SBAwayDateView (view này bắt đầu ngay dưới thanh trạng thái, y = 20)
static const CGFloat kPhoneTimeSize = 80, kPhoneDateSize = 17;
static const CGFloat kPhoneDateMidY = 22;   // tâm dòng ngày
static const CGFloat kPhoneTimeCapTop = 36; // mép trên của các chữ số giờ
// iPhone: đường kính nút máy ảnh tròn
static const CGFloat kCameraButtonSize = 48;
// Dòng «Đã sạc N%» hiện trong bấy nhiêu giây
static const CFTimeInterval kChargeNoteSeconds = 4.0;
// iPhone, thông báo trên màn khoá: lề của thẻ trong mỗi dòng, tỉ lệ thu nội dung dòng, khoảng hạ cả danh sách
static const CGFloat kRowCardInsetX = 8, kRowCardInsetY = 2, kRowContentScale = 0.94, kPhoneListDrop = 8;

static __weak UIView *gAwayView;
static char kOrigKey, kDrawnKey, kRowCardKey, kRowColorKey;

// Nền mờ của hình nền màn khoá — nhớ lại tới khi đổi hình nền / hướng máy / cấu hình
static G6Backdrop *gBackdrop;
static NSUInteger gBackdropGeneration;
static int gBackdropOrientation = -1;
static __weak UIImage *gBackdropSource;

// ---- Tiện ích ----

static id G6Ivar(id obj, const char *name) {
    Ivar iv = obj ? class_getInstanceVariable([obj class], name) : NULL;
    return iv ? object_getIvar(obj, iv) : nil;
}

static id G6Call(id obj, NSString *selName) {
    SEL sel = NSSelectorFromString(selName);
    return [obj respondsToSelector:sel] ? ((id (*)(id, SEL))objc_msgSend)(obj, sel) : nil;
}

// Chỗ cất đồ gốc (ảnh, phông) của một view để trả lại khi tắt
static NSMutableDictionary *G6Orig(id obj, BOOL create) {
    NSMutableDictionary *d = objc_getAssociatedObject(obj, &kOrigKey);
    if (!d && create) {
        d = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(obj, &kOrigKey, d, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return d;
}

static UIView *G6FirstSubviewOfClass(UIView *parent, const char *className) {
    Class cls = objc_getClass(className);
    for (UIView *sub in parent.subviews) {
        if (cls && [sub isKindOfClass:cls]) return sub;
    }
    return nil;
}

static G6Backdrop *G6LockBackdrop(UIView *away) {
    UIView *wallpaper = G6FirstSubviewOfClass(away, "SBWallpaperView");
    if (!wallpaper.window) return nil;
    UIImage *source = [wallpaper isKindOfClass:[UIImageView class]] ? [(UIImageView *)wallpaper image] : nil;
    int orientation = (int)[UIApplication sharedApplication].statusBarOrientation;
    if (gBackdrop && gBackdropGeneration == G6WallpaperGeneration() && gBackdropOrientation == orientation && gBackdropSource == source) {
        return gBackdrop;
    }
    double t0 = G6NowMs();
    G6Backdrop *b = G6WallpaperRender(wallpaper);
    if (!b) return nil;
    gBackdrop = b;
    gBackdropGeneration = G6WallpaperGeneration();
    gBackdropOrientation = orientation;
    gBackdropSource = source;
    G6Log(@"màn khoá: vẽ + làm mờ hình nền %.1f ms", G6NowMs() - t0);
    return b;
}

// ---- Nút khung ảnh ----

// SpringBoard muốn hiện nút khung ảnh không (theo lần gần nhất nó gọi setShowsSlideshowButton:); chưa gọi lần nào thì chưa biết
static BOOL gWantsFrameButton, gWantsFrameButtonKnown;
static void (*o_setShowsSlideshow)(id, SEL, BOOL);

static BOOL G6LockHidesFrameButton(void) {
    return G6Feature(@"lock_screen") && [G6Config()[@"lock_hide_frame"] boolValue];
}

static void g6_setShowsSlideshow(id self, SEL _cmd, BOOL shows) {
    gWantsFrameButton = shows;
    gWantsFrameButtonKnown = YES;
    o_setShowsSlideshow(self, _cmd, shows && !G6LockHidesFrameButton());
}

// Đưa nút về đúng trạng thái hiện tại (đang ẩn mà nút còn đó → gỡ; hết ẩn mà SpringBoard vốn muốn hiện → hiện lại)
static void G6LockApplyFrameButton(UIView *bar) {
    SEL sel = NSSelectorFromString(@"setShowsSlideshowButton:");
    if (!o_setShowsSlideshow || ![bar respondsToSelector:sel]) return;
    UIView *button = G6Ivar(bar, "_slideshowButton");
    BOOL present = [button isKindOfClass:[UIView class]] && button.superview != nil;
    if (!gWantsFrameButtonKnown) {
        // Màn khoá dựng trước khi Glass 6 gắn hàm: nút đang có nghĩa là SpringBoard muốn hiện
        gWantsFrameButton = present;
        gWantsFrameButtonKnown = YES;
    }
    BOOL show = gWantsFrameButton && !G6LockHidesFrameButton();
    if (show != present) o_setShowsSlideshow(bar, sel, show);
}

// ---- Mục «Chưa cài đặt Thẻ SIM» ----

// -[SBSIMLockAlertItem status] (đo trên máy bằng lệnh thử `sim`): 3 = chưa cài đặt thẻ SIM; 4 lỗi SIM, 5 đã khoá SIM,
// 6 đã khoá PUK, 7 PUK hết hạn, 8 quay số cố định, 9 SIM không đúng
static const int kSIMStatusNoSIM = 3;
// Mục đã bị chặn / gỡ — để hiện lại khi anh tắt tuỳ chọn ẩn
static __weak id gSuppressedSIMAlert;
static void (*o_activateAlertItem)(id, SEL, id, BOOL);

static BOOL G6IsNoSIMAlert(id item) {
    Class cls = objc_getClass("SBSIMLockAlertItem");
    SEL status = NSSelectorFromString(@"status");
    return cls && [item isKindOfClass:cls] && [item respondsToSelector:status] &&
           ((int (*)(id, SEL))objc_msgSend)(item, status) == kSIMStatusNoSIM;
}

static BOOL G6LockHidesNoSIM(void) {
    return G6Feature(@"lock_screen") && [G6Config()[@"lock_hide_no_sim"] boolValue];
}

static void g6_activateAlertItem(id self, SEL _cmd, id item, BOOL didUndim) {
    @try {
        if (G6IsNoSIMAlert(item) && G6LockHidesNoSIM()) {
            gSuppressedSIMAlert = item;
            return;
        }
    } @catch (NSException *e) {
    }
    o_activateAlertItem(self, _cmd, item, didUndim);
}

// Đưa danh sách đang có về đúng trạng thái: đang ẩn mà mục còn đó → gỡ; hết ẩn mà mục đã bị chặn → hiện lại
static void G6LockApplyNoSIM(UIView *away) {
    if (!o_activateAlertItem) return;
    id controller = G6Ivar(away, "_bulletinController");
    NSArray *items = [G6Ivar(controller, "_listItems") copy];
    if (!controller || ![items isKindOfClass:[NSArray class]]) return;
    id shown = nil;
    for (id listItem in items) {
        id alert = G6Call(listItem, @"currentAlert");
        if (G6IsNoSIMAlert(alert)) {
            shown = alert;
            break;
        }
    }
    BOOL hide = G6LockHidesNoSIM();
    SEL deactivate = NSSelectorFromString(@"deactivateAlertItem:");
    if (hide && shown && [controller respondsToSelector:deactivate]) {
        gSuppressedSIMAlert = shown;
        ((void (*)(id, SEL, id))objc_msgSend)(controller, deactivate, shown);
        G6Log(@"màn khoá: đã ẩn mục «chưa cài đặt thẻ SIM»");
    } else if (!hide && !shown && gSuppressedSIMAlert) {
        id alert = gSuppressedSIMAlert;
        gSuppressedSIMAlert = nil;
        // Chỉ hiện lại khi máy vẫn đang ở màn khoá và trạng thái SIM chưa đổi
        Class awayClass = objc_getClass("SBAwayController");
        SEL shared = NSSelectorFromString(@"sharedAwayControllerIfExists"), locked = NSSelectorFromString(@"isLocked");
        id awayController = [awayClass respondsToSelector:shared] ? ((id (*)(id, SEL))objc_msgSend)(awayClass, shared) : nil;
        BOOL isLocked = [awayController respondsToSelector:locked] && ((BOOL (*)(id, SEL))objc_msgSend)(awayController, locked);
        if (isLocked && G6IsNoSIMAlert(alert)) {
            o_activateAlertItem(controller, NSSelectorFromString(@"activateAlertItem:didUndimScreen:"), alert, NO);
        }
    }
}

// ---- Hình pin lớn lúc đang sạc ----

// Dòng «Đã sạc N%» hiện thay dòng ngày tới thời điểm này
static CFAbsoluteTime gChargeNoteUntil;
// Dòng ngày của SpringBoard lúc bị thay (để trả lại)
static NSString *gChargeNoteReplaced;
// SpringBoard muốn hiện hình pin mà mình đã chặn / đã cho ẩn — để hiện lại khi anh tắt tuỳ chọn ẩn
static BOOL gBatteryHidden;
static char kBatteryHiddenKey;
static BOOL (*o_shouldShowCharging)(id, SEL);

static BOOL G6LockHidesBattery(void) {
    return G6Feature(@"lock_screen") && [G6Config()[@"lock_hide_battery"] boolValue];
}

static BOOL g6_shouldShowCharging(id self, SEL _cmd) {
    BOOL stock = o_shouldShowCharging(self, _cmd);
    if (stock && G6LockHidesBattery()) {
        gBatteryHidden = YES;
        return NO;
    }
    return stock;
}

// Lúc SpringBoard vừa khởi động (respring khi đang cắm sạc) nó gọi thẳng showChargingView, không hỏi shouldShowChargingView
// → chặn luôn ở đây, hình pin không kịp loé lên
static void (*o_showCharging)(id, SEL);
static void g6_showCharging(id self, SEL _cmd) {
    if (G6LockHidesBattery()) {
        gBatteryHidden = YES;
        return;
    }
    o_showCharging(self, _cmd);
}

static id G6UIController(void) {
    Class cls = objc_getClass("SBUIController");
    return [cls respondsToSelector:@selector(sharedInstance)] ? ((id (*)(id, SEL))objc_msgSend)(cls, @selector(sharedInstance)) : nil;
}

static BOOL G6LockOnAC(void) {
    id ctl = G6UIController();
    SEL sel = NSSelectorFromString(@"isOnAC");
    return [ctl respondsToSelector:sel] && ((BOOL (*)(id, SEL))objc_msgSend)(ctl, sel);
}

// «Đã sạc 92%»; nil khi không đọc được mức pin
static NSString *G6LockChargeText(void) {
    id ctl = G6UIController();
    SEL sel = NSSelectorFromString(@"displayBatteryCapacityAsPercentage");
    if (![ctl respondsToSelector:sel]) return nil;
    int percent = ((int (*)(id, SEL))objc_msgSend)(ctl, sel);
    if (percent < 0 || percent > 100) return nil;
    return [NSString stringWithFormat:G6L(@"Đã sạc %d%%"), percent];
}

// Hình pin đang hiện mà vừa bật ẩn → cho nó mờ đi bằng chính hàm của SpringBoard; tắt ẩn → hiện lại nếu SpringBoard vẫn muốn
static void G6LockApplyBattery(UIView *away) {
    if (!o_shouldShowCharging) return;
    UIView *charging = G6Ivar(away, "_chargingView");
    BOOL shown = [charging isKindOfClass:[UIView class]] && charging.superview != nil;
    SEL hide = NSSelectorFromString(@"hideChargingView"), show = NSSelectorFromString(@"showChargingView");
    if (G6LockHidesBattery()) {
        // Mỗi hình pin chỉ gọi ẩn một lần (nó mờ dần rồi SpringBoard mới gỡ)
        if (shown && !objc_getAssociatedObject(charging, &kBatteryHiddenKey) && [away respondsToSelector:hide]) {
            objc_setAssociatedObject(charging, &kBatteryHiddenKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            gBatteryHidden = YES;
            // Giấu ngay (hàm của SpringBoard cho mờ dần — đủ để hình pin loé lên lúc vừa respring), rồi để nó dọn
            charging.hidden = YES;
            ((void (*)(id, SEL))objc_msgSend)(away, hide);
            // Lúc hiện hình pin SpringBoard cho hình nền màn khoá trong suốt hẳn (nền đen), và chỉ trả lại sau khi hình pin mờ
            // xong — đo trên iPhone: nền đen 3–7 giây sau respring. Trả hình nền ngay.
            UIView *wallpaper = G6FirstSubviewOfClass(away, "SBWallpaperView");
            if (wallpaper && wallpaper.alpha < 1) wallpaper.alpha = 1;
            G6Log(@"màn khoá: đã ẩn hình pin lớn");
        }
    } else if (gBatteryHidden) {
        gBatteryHidden = NO;
        if (!shown && away.window && [away respondsToSelector:show] && o_shouldShowCharging(away, NSSelectorFromString(@"shouldShowChargingView"))) {
            ((void (*)(id, SEL))objc_msgSend)(away, show);
            UIView *again = G6Ivar(away, "_chargingView");
            if ([again isKindOfClass:[UIView class]]) again.hidden = NO;
        }
    }
}

// Chuyển chữ của một nhãn cho êm (mờ chéo)
static void G6LockFade(UIView *label) {
    CATransition *fade = [CATransition animation];
    fade.type = kCATransitionFade;
    fade.duration = 0.3;
    [label.layer addAnimation:fade forKey:@"g6-fade"];
}

// ---- Thanh trên: giờ, ngày ----

// Nới bề rộng nhãn cho vừa chữ (giữ nguyên tâm): SpringBoard đặt khung theo bề rộng chữ của phông gốc, phông Inter rộng hơn
// nên chữ bị cắt «…» (đã gặp với dòng ngày tiếng Việt). SpringBoard đặt lại khung mỗi lần cập nhật đồng hồ → gọi mỗi lần áp.
static void G6LockFitLabel(UIView *label, UIFont *font) {
    NSString *text = G6Call(label, @"text");
    UIView *parent = label.superview;
    if (![text isKindOfClass:[NSString class]] || !text.length || !font || !parent) return;
    CGFloat need = MIN(ceil([text sizeWithFont:font].width) + 12, parent.bounds.size.width - 16);
    CGRect f = label.frame;
    if (f.size.width >= need) return;
    f.origin.x = floor(CGRectGetMidX(f) - need / 2);
    f.size.width = need;
    label.frame = f;
    [label setNeedsDisplay];
}

// Đổi phông của một nhãn sang Inter. `size` = 0: giữ cỡ chữ gốc. Trả phông đang dùng (nil nếu chưa đổi được).
static UIFont *G6LockRestyleLabel(UIView *label, BOOL active, G6FontWeight weight, CGFloat size, BOOL fit) {
    SEL setFont = NSSelectorFromString(@"setLCDTextFont:");
    if (!label || ![label respondsToSelector:setFont]) return nil;
    UIFont *current = G6Ivar(label, "_font");
    NSMutableDictionary *orig = G6Orig(label, active);
    if (active) {
        if (![current isKindOfClass:[UIFont class]] || !G6FontAvailable()) return nil;
        UIFont *mine = orig[@"mine"];
        // SpringBoard có thể đặt lại phông gốc (đổi định dạng giờ, xoay máy) → phông đang dùng không phải của mình thì cất + đổi
        BOOL foreign = !mine || ![current isEqual:mine];
        if (foreign) orig[@"font"] = current;
        CGFloat want = size > 0 ? size : [(UIFont *)orig[@"font"] pointSize];
        if (foreign || fabs(mine.pointSize - want) > 0.01) {
            mine = G6Font(weight, want);
            orig[@"mine"] = mine;
            ((void (*)(id, SEL, id))objc_msgSend)(label, setFont, mine);
            [label setNeedsDisplay];
        }
        // Bóng chữ: iOS 6 vẽ một bóng đen đậm sát chữ (kiểu chữ nổi) — trên hình nền sáng nó thành viền tối quanh chữ số
        // lớn. Chỉ giữ một bóng rất nhạt cho chữ trắng còn tách khỏi nền.
        SEL setShadow = NSSelectorFromString(@"setShadowColor:");
        if ([label respondsToSelector:setShadow]) {
            UIColor *shadow = G6Ivar(label, "_shadowColor"), *soft = orig[@"softShadow"];
            if (!soft || ![shadow isEqual:soft]) {
                if (!orig[@"shadow"]) orig[@"shadow"] = [shadow isKindOfClass:[UIColor class]] ? shadow : (id)[NSNull null];
                soft = [UIColor colorWithWhite:0 alpha:0.14];
                orig[@"softShadow"] = soft;
                ((void (*)(id, SEL, id))objc_msgSend)(label, setShadow, soft);
                [label setNeedsDisplay];
            }
        }
        if (fit) G6LockFitLabel(label, mine);
        return mine;
    } else if (orig[@"font"]) {
        ((void (*)(id, SEL, id))objc_msgSend)(label, setFont, orig[@"font"]);
        SEL setShadow = NSSelectorFromString(@"setShadowColor:");
        if (orig[@"shadow"] && [label respondsToSelector:setShadow]) {
            id shadow = orig[@"shadow"];
            ((void (*)(id, SEL, id))objc_msgSend)(label, setShadow, shadow == [NSNull null] ? nil : shadow);
        }
        [label setNeedsDisplay];
        [orig removeAllObjects];
    }
    return nil;
}

// Đặt khung của mình cho một nhãn (cất khung gốc lần đầu); `mine` = CGRectNull → trả khung gốc. Trả YES nếu vừa trả khung gốc.
static BOOL G6LockPlaceLabel(UIView *label, CGRect mine) {
    if (!label) return NO;
    BOOL place = !CGRectIsNull(mine);
    NSMutableDictionary *orig = G6Orig(label, place);
    if (place) {
        if (!orig[@"frame"]) orig[@"frame"] = [NSValue valueWithCGRect:label.frame];
        if (!CGRectEqualToRect(label.frame, mine)) {
            label.frame = mine;
            [label setNeedsDisplay];
        }
        return NO;
    }
    if (!orig[@"frame"]) return NO;
    label.frame = [orig[@"frame"] CGRectValue];
    [orig removeObjectForKey:@"frame"];
    [label setNeedsDisplay];
    return YES;
}

// iPhone đang ở bố cục thường (không hiện nút điều khiển nhạc, không phát nhạc) → dùng bố cục kiểu iOS 26
static BOOL G6LockPhonePlain(UIView *dateView) {
    if (!g6_device_is_phone() || !dateView) return NO;
    for (NSString *name in @[@"isShowingControls", @"isPlaying"]) {
        SEL sel = NSSelectorFromString(name);
        if ([dateView respondsToSelector:sel] && ((BOOL (*)(id, SEL))objc_msgSend)(dateView, sel)) return NO;
    }
    return YES;
}

static void (*o_updateClock)(id, SEL);

static void G6LockApplyHeader(UIView *away, BOOL active) {
    UIView *dateView = G6Ivar(away, "_dateHeaderView");
    UIView *timeLabel = G6Ivar(dateView, "_timeLabel"), *dateLabel = G6Ivar(dateView, "_dateAndTetheringLabel");
    BOOL phone = active && G6LockPhonePlain(dateView);
    if (!phone) {
        // Rời bố cục iPhone (tắt thành phần / đang hiện nút nhạc): trả khung gốc trước khi trả phông, rồi để SpringBoard xếp lại
        BOOL restored = G6LockPlaceLabel(timeLabel, CGRectNull);
        restored = G6LockPlaceLabel(dateLabel, CGRectNull) || restored;
        if (restored && o_updateClock && dateView) o_updateClock(dateView, NSSelectorFromString(@"updateClock"));
    }

    // Đang sạc + màn khoá vừa sáng: dòng ngày nhường chỗ cho «Đã sạc N%» trong vài giây
    BOOL note = active && CFAbsoluteTimeGetCurrent() < gChargeNoteUntil;
    SEL setText = NSSelectorFromString(@"setText:");
    if (note && [dateLabel respondsToSelector:setText]) {
        NSString *text = G6LockChargeText(), *shown = G6Call(dateLabel, @"text");
        if (text && ![text isEqual:shown]) {
            if ([shown isKindOfClass:[NSString class]]) gChargeNoteReplaced = [shown copy];
            G6LockFade(dateLabel);
            ((void (*)(id, SEL, id))objc_msgSend)(dateLabel, setText, text);
            [dateLabel setNeedsDisplay];
        }
    }

    UIFont *timeFont = G6LockRestyleLabel(timeLabel, active, G6FontSemiBold, phone ? kPhoneTimeSize : 0, NO);
    UIFont *dateFont = G6LockRestyleLabel(dateLabel, active, phone ? G6FontSemiBold : G6FontMedium, phone ? kPhoneDateSize : 0, !phone);
    if (phone && timeFont && dateFont) {
        CGFloat width = dateView.bounds.size.width;
        // Giờ: nhãn cao đúng một dòng chữ, rộng hết thanh; đặt sao cho mép trên chữ số rơi vào kPhoneTimeCapTop
        CGFloat lineHeight = ceil(timeFont.lineHeight);
        G6LockPlaceLabel(timeLabel, CGRectMake(0, round(kPhoneTimeCapTop - (timeFont.ascender - timeFont.capHeight)), width, lineHeight));
        // Ngày: nhãn vừa khít chữ, nằm giữa
        NSString *text = G6Call(dateLabel, @"text");
        CGFloat need = [text isKindOfClass:[NSString class]] ? ceil([text sizeWithFont:dateFont].width) + 12 : width - 16;
        need = MIN(need, width - 16);
        CGFloat dateHeight = ceil(dateFont.lineHeight);
        G6LockPlaceLabel(dateLabel, CGRectMake(floor((width - need) / 2), round(kPhoneDateMidY - dateHeight / 2), need, dateHeight));
    } else if (note && dateFont) {
        // iPad: chữ «Đã sạc N%» ngắn hơn dòng ngày → thu nhãn lại cho khít, vẫn nằm giữa
        NSString *text = G6Call(dateLabel, @"text");
        UIView *parent = dateLabel.superview;
        if ([text isKindOfClass:[NSString class]] && parent) {
            CGRect f = dateLabel.frame;
            CGFloat need = MIN(ceil([text sizeWithFont:dateFont].width) + 12, parent.bounds.size.width - 16);
            if (fabs(f.size.width - need) > 0.5) {
                f.origin.x = floor((parent.bounds.size.width - need) / 2);
                f.size.width = need;
                dateLabel.frame = f;
                [dateLabel setNeedsDisplay];
            }
        }
    }
    // Thanh bóng kính chứa nó: TPLCDBar là UIImageView, ảnh nền là image của chính nó
    Class barClass = objc_getClass("TPLCDBar");
    UIView *bar = dateView;
    while (bar && !(barClass && [bar isKindOfClass:barClass])) bar = bar.superview;
    if (![bar isKindOfClass:[UIImageView class]]) return;
    UIImageView *barImage = (UIImageView *)bar;
    NSMutableDictionary *orig = G6Orig(bar, active);
    if (active) {
        // SpringBoard đặt lại ảnh nền khi xoay máy → thấy có ảnh thì cất rồi bỏ
        if (barImage.image) {
            orig[@"image"] = barImage.image;
            barImage.image = nil;
        }
    } else if (orig[@"image"]) {
        if (!barImage.image) barImage.image = orig[@"image"];
        // Chỉ bỏ ảnh đã cất: cùng chỗ cất này còn ghi độ dời của thanh (xử lý ngay dưới)
        [orig removeObjectForKey:@"image"];
    }
    UIView *shadow = G6Call(bar, @"shadowView");
    if ([shadow isKindOfClass:[UIView class]]) shadow.hidden = active;

    // Nằm ngang: hạ cả thanh (giờ, ngày, tên bài hát đang phát) xuống một chút. Dùng phép dời (transform) chứ không sửa
    // khung: SpringBoard đặt lại khung mỗi lần xếp, còn phép dời thì nó không đụng tới.
    BOOL landscape = UIInterfaceOrientationIsLandscape([UIApplication sharedApplication].statusBarOrientation);
    CGFloat drop = (active && landscape) ? kLandscapeClockDrop : 0;
    NSMutableDictionary *moved = G6Orig(bar, drop != 0);
    if (drop != 0) {
        if ([moved[@"drop"] floatValue] != drop || CGAffineTransformIsIdentity(bar.transform)) {
            bar.transform = CGAffineTransformMakeTranslation(0, drop);
            moved[@"drop"] = @(drop);
        }
    } else if (moved[@"drop"]) {
        bar.transform = CGAffineTransformIdentity;
        [moved removeObjectForKey:@"drop"];
    }
}

// ---- Thanh dưới: rãnh trượt, núm, nút khung ảnh ----

// Núm trượt: viên trắng có mũi tên, cùng cỡ ảnh núm gốc
static UIImage *G6KnobImage(CGSize size, CGFloat scale) {
    if (size.width < 8 || size.height < 8) return nil;
    UIGraphicsBeginImageContextWithOptions(size, NO, scale);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGRect pill = CGRectInset(CGRectMake(0, 0, size.width, size.height), 2.5, 3);
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:pill cornerRadius:pill.size.height / 2];
    // Bóng đổ nhẹ dưới núm
    CGContextSaveGState(ctx);
    CGContextSetShadowWithColor(ctx, CGSizeMake(0, 1), 2, [UIColor colorWithWhite:0 alpha:0.35].CGColor);
    [[UIColor whiteColor] setFill];
    [path fill];
    CGContextRestoreGState(ctx);
    // Thân núm: trắng → xám rất nhạt
    CGContextSaveGState(ctx);
    [path addClip];
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGFloat colors[] = {1, 1, 1, 1, 0.90, 0.90, 0.93, 1};
    CGGradientRef grad = CGGradientCreateWithColorComponents(cs, colors, NULL, 2);
    CGContextDrawLinearGradient(ctx, grad, CGPointMake(0, CGRectGetMinY(pill)), CGPointMake(0, CGRectGetMaxY(pill)), 0);
    CGGradientRelease(grad);
    CGColorSpaceRelease(cs);
    CGContextRestoreGState(ctx);
    // Mũi tên chỉ sang phải
    CGFloat cx = CGRectGetMidX(pill), cy = CGRectGetMidY(pill), half = pill.size.height * 0.20, len = pill.size.width * 0.20;
    CGContextSetLineWidth(ctx, 2.5);
    CGContextSetLineCap(ctx, kCGLineCapRound);
    CGContextSetLineJoin(ctx, kCGLineJoinRound);
    [[UIColor colorWithWhite:0.25 alpha:1] setStroke];
    CGContextMoveToPoint(ctx, cx - len, cy);
    CGContextAddLineToPoint(ctx, cx + len, cy);
    CGContextMoveToPoint(ctx, cx + len - half, cy - half);
    CGContextAddLineToPoint(ctx, cx + len, cy);
    CGContextAddLineToPoint(ctx, cx + len - half, cy + half);
    CGContextStrokePath(ctx);
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

// Hình máy ảnh (thân bo góc + gù ống ngắm + ống kính khoét vòng) cỡ `size`
static UIImage *G6CameraGlyph(CGSize size, UIColor *color, CGFloat scale) {
    UIGraphicsBeginImageContextWithOptions(size, NO, scale);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGFloat w = size.width, h = size.height, bump = round(h * 0.18);
    [color setFill];
    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, bump, w, h - bump) cornerRadius:3] fill];
    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(round(w * 0.30), 0, w - 2 * round(w * 0.30), bump + 3) cornerRadius:1.5] fill];
    CGPoint c = CGPointMake(w / 2, bump + (h - bump) / 2);
    CGFloat ring = (h - bump) * 0.34;
    CGContextSetBlendMode(ctx, kCGBlendModeClear);
    CGContextFillEllipseInRect(ctx, CGRectMake(c.x - ring, c.y - ring, ring * 2, ring * 2));
    CGContextSetBlendMode(ctx, kCGBlendModeNormal);
    CGFloat lens = ring - 1.75;
    [color setFill];
    CGContextFillEllipseInRect(ctx, CGRectMake(c.x - lens, c.y - lens, lens * 2, lens * 2));
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

// Nút máy ảnh tròn bằng kính, vẽ quanh tâm của `grabber` (ảnh to hơn view — view hiện ảnh ở giữa, không cắt)
static UIImage *G6LockCameraButton(UIView *grabber, G6Backdrop *backdrop, BOOL dark) {
    if (!grabber.window) return nil;
    CGRect b = grabber.bounds;
    CGSize size = CGSizeMake(kCameraButtonSize, kCameraButtonSize);
    CGRect disc = CGRectMake(floor(CGRectGetMidX(b) - size.width / 2), floor(CGRectGetMidY(b) - size.height / 2), size.width, size.height);
    UIImage *glass = G6GlassImageForRect(@"capsule", grabber, disc, dark, backdrop);
    if (!glass) return nil;
    CGSize glyphSize = CGSizeMake(22, 17);
    UIImage *glyph = G6CameraGlyph(glyphSize, dark ? [UIColor colorWithWhite:1 alpha:0.95] : [UIColor colorWithWhite:0.12 alpha:0.9], glass.scale);
    UIGraphicsBeginImageContextWithOptions(size, NO, glass.scale);
    [glass drawInRect:CGRectMake(0, 0, size.width, size.height)];
    [glyph drawInRect:CGRectMake(floor((size.width - glyphSize.width) / 2), floor((size.height - glyphSize.height) / 2), glyphSize.width, glyphSize.height)];
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

// Ảnh kính phủ kín `view` (đang trong cửa sổ); nil nếu chưa dựng được
static UIImage *G6LockGlass(UIView *view, NSString *surface, G6Backdrop *backdrop, BOOL dark) {
    if (!view.window || view.bounds.size.width < 2 || view.bounds.size.height < 2) return nil;
    return G6GlassImageForView(surface, view, dark, backdrop);
}

// Mô tả thứ quyết định hình tấm kính của một view — không đổi thì không dựng lại
static NSString *G6DrawnKey(UIView *view, G6Backdrop *backdrop, BOOL dark) {
    CGPoint o = view.window ? [view.window convertPoint:[view convertPoint:CGPointZero toView:nil] toWindow:nil] : CGPointZero;
    return [NSString stringWithFormat:@"%.0f|%.0f|%.0f|%.0f|%d|%lu|%p|%d", view.bounds.size.width, view.bounds.size.height, o.x, o.y, dark,
                                      (unsigned long)G6WallpaperGeneration(), backdrop, (int)[UIApplication sharedApplication].statusBarOrientation];
}

static void G6LockApplyBar(UIView *away, BOOL active) {
    UIView *bar = G6Ivar(away, "_lockBar");
    if (![bar isKindOfClass:[UIView class]]) return;
    G6LockApplyFrameButton(bar);
    BOOL styled = G6Orig(bar, NO)[@"styled"] != nil;
    if (!active && !styled) return;
    BOOL dark = G6IsDark();
    G6Backdrop *backdrop = active ? G6LockBackdrop(away) : nil;

    // Nền của thanh: phần vẽ trong drawRect + ảnh nền + nét bóng
    SEL suppress = NSSelectorFromString(@"setSuppressDrawingBackground:");
    if ([bar respondsToSelector:suppress]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(bar, suppress, active);
        [bar setNeedsDisplay];
    }
    UIView *bgView = G6Ivar(bar, "_backgroundView");
    if ([bgView isKindOfClass:[UIView class]]) bgView.hidden = active;
    UIView *shadow = G6Call(bar, @"shadowView");
    if ([shadow isKindOfClass:[UIView class]]) shadow.hidden = active;

    // Rãnh trượt
    UIImageView *well = G6Ivar(bar, "_well");
    if ([well isKindOfClass:[UIImageView class]]) {
        NSMutableDictionary *orig = G6Orig(well, active);
        if (active) {
            NSString *key = G6DrawnKey(well, backdrop, dark);
            UIImage *mine = orig[@"mine"];
            if (!mine || well.image != mine || ![key isEqualToString:orig[@"key"]]) {
                if (well.image && well.image != mine) orig[@"image"] = well.image;
                UIImage *glass = G6LockGlass(well, @"capsule", backdrop, dark);
                if (glass) {
                    well.image = glass;
                    orig[@"mine"] = glass;
                    orig[@"key"] = key;
                }
            }
        } else if (orig[@"image"]) {
            well.image = orig[@"image"];
            [orig removeAllObjects];
        }
    }

    // Núm trượt
    UIImageView *knob = G6Ivar(bar, "_knobView");
    if ([knob isKindOfClass:[UIImageView class]]) {
        NSMutableDictionary *orig = G6Orig(knob, active);
        if (active) {
            UIImage *mine = orig[@"mine"];
            if (knob.image && knob.image != mine) {
                orig[@"image"] = knob.image;
                mine = G6KnobImage(knob.image.size, knob.image.scale);
                if (mine) {
                    orig[@"mine"] = mine;
                    knob.image = mine;
                }
            }
        } else if (orig[@"image"]) {
            knob.image = orig[@"image"];
            [orig removeAllObjects];
        }
    }

    // Nút máy ảnh (iPhone): ảnh tay nắm có ba vạch → nút tròn bằng kính; vẫn kéo lên để mở máy ảnh như cũ
    UIImageView *grabber = G6Ivar(bar, "_cameraGrabber");
    if ([grabber isKindOfClass:[UIImageView class]]) {
        NSMutableDictionary *orig = G6Orig(grabber, active);
        if (active) {
            NSString *key = G6DrawnKey(grabber, backdrop, dark);
            UIImage *mine = orig[@"mine"];
            if (!mine || grabber.image != mine || ![key isEqualToString:orig[@"key"]]) {
                if (grabber.image && grabber.image != mine) {
                    orig[@"image"] = grabber.image;
                    orig[@"mode"] = @(grabber.contentMode);
                    if (grabber.highlightedImage) orig[@"highlighted"] = grabber.highlightedImage;
                }
                UIImage *button = G6LockCameraButton(grabber, backdrop, dark);
                if (button) {
                    grabber.contentMode = UIViewContentModeCenter;
                    grabber.image = button;
                    if (orig[@"highlighted"]) grabber.highlightedImage = button;
                    orig[@"mine"] = button;
                    orig[@"key"] = key;
                }
            }
        } else if (orig[@"image"]) {
            grabber.contentMode = (UIViewContentMode)[orig[@"mode"] integerValue];
            grabber.image = orig[@"image"];
            if (orig[@"highlighted"]) grabber.highlightedImage = orig[@"highlighted"];
            [orig removeAllObjects];
        }
    }

    // Nút khung ảnh: đổi ảnh nền của nút, giữ ảnh biểu tượng
    UIButton *button = G6Ivar(bar, "_slideshowButton");
    if ([button isKindOfClass:[UIButton class]]) {
        NSMutableDictionary *orig = G6Orig(button, active);
        if (active) {
            NSString *key = G6DrawnKey(button, backdrop, dark);
            UIImage *mine = orig[@"mine"];
            UIImage *current = [button backgroundImageForState:UIControlStateNormal];
            if (!mine || current != mine || ![key isEqualToString:orig[@"key"]]) {
                if (current && current != mine) {
                    orig[@"normal"] = current;
                    UIImage *hi = [button backgroundImageForState:UIControlStateHighlighted];
                    if (hi) orig[@"highlighted"] = hi;
                    UIImage *sel = [button backgroundImageForState:UIControlStateSelected];
                    if (sel) orig[@"selected"] = sel;
                }
                UIImage *glass = G6LockGlass(button, @"capsule", backdrop, dark);
                if (glass) {
                    for (NSNumber *state in @[@(UIControlStateNormal), @(UIControlStateHighlighted), @(UIControlStateSelected)]) {
                        [button setBackgroundImage:glass forState:(UIControlState)state.unsignedIntegerValue];
                    }
                    orig[@"mine"] = glass;
                    orig[@"key"] = key;
                }
            }
        } else if (orig[@"normal"]) {
            [button setBackgroundImage:orig[@"normal"] forState:UIControlStateNormal];
            [button setBackgroundImage:orig[@"highlighted"] forState:UIControlStateHighlighted];
            [button setBackgroundImage:orig[@"selected"] forState:UIControlStateSelected];
            [orig removeAllObjects];
        }
    }

    if (active) G6Orig(bar, YES)[@"styled"] = @YES;
    else [G6Orig(bar, NO) removeAllObjects];
}

// ---- Khung danh sách thông báo ----

// iPhone: các dòng thông báo đang hiện xếp lại (để thẻ / nền theo kịp lúc bật, tắt thành phần)
static void G6LockRelayoutRows(UIView *list) {
    for (NSString *name in @[@"_tableView", @"_firstAlertTableView"]) {
        UITableView *table = G6Ivar(list, name.UTF8String);
        if (![table isKindOfClass:[UITableView class]]) continue;
        for (UIView *cell in table.visibleCells) [cell setNeedsLayout];
    }
}

static void G6LockApplyList(UIView *away, BOOL active) {
    UIView *list = G6FirstSubviewOfClass(away, "SBAwayBulletinListView");
    if (!list) return;
    BOOL phone = g6_device_is_phone();
    // iPad — con trực tiếp là UIImageView: cái phủ kín khung là ảnh khung, hai cái còn lại là bóng trên / dưới.
    // iPhone — không có ảnh khung; ảnh nền của ô thông báo nổi là _firstAlertBGView.
    UIImageView *frameView = nil;
    NSMutableArray *shades = [NSMutableArray array];
    if (phone) {
        UIImageView *floating = G6Ivar(list, "_firstAlertBGView");
        if ([floating isKindOfClass:[UIImageView class]]) frameView = floating;
    } else {
        for (UIView *sub in list.subviews) {
            if ([sub class] != [UIImageView class]) continue;
            if (!frameView && fabs(sub.bounds.size.width - list.bounds.size.width) < 1 && fabs(sub.bounds.size.height - list.bounds.size.height) < 1) {
                frameView = (UIImageView *)sub;
            } else {
                [shades addObject:sub];
            }
        }
    }
    NSMutableDictionary *orig = G6Orig(list, active);
    if (phone) {
        // Các dòng tự lo trong -layoutSubviews của chúng; ở đây chỉ gọi xếp lại khi trạng thái bật / tắt vừa đổi
        NSNumber *rows = orig[@"rows"];
        if (orig && (!rows || rows.boolValue != active)) {
            orig[@"rows"] = @(active);
            G6LockRelayoutRows(list);
        }
    }
    if (!active) {
        if (!orig[@"styled"]) return;
        // frameView có thể không tìm lại được theo cỡ (khung vừa đổi cỡ) → dùng view đã ghi lúc phủ kính
        UIImageView *styledView = orig[@"view"];
        if (orig[@"image"]) styledView.image = orig[@"image"];
        if (!phone) {
            for (UIView *sub in list.subviews) {
                if ([sub class] == [UIImageView class]) sub.hidden = NO;
            }
        }
        [orig removeAllObjects];
        return;
    }
    if (!frameView) frameView = orig[@"view"];
    // Khung rỗng (không có thông báo) cao vài điểm — không có gì để dựng
    if (!frameView || !frameView.window || frameView.bounds.size.height < 16) return;
    G6Backdrop *backdrop = G6LockBackdrop(away);
    NSString *key = G6DrawnKey(frameView, backdrop, YES);
    UIImage *mine = orig[@"mine"];
    if (!mine || frameView.image != mine || ![key isEqualToString:orig[@"key"]]) {
        if (frameView.image && frameView.image != mine) orig[@"image"] = frameView.image;
        // Luôn kính tối + đậm: chữ trong ô do máy vẽ màu trắng
        UIImage *glass = G6LockGlass(frameView, @"list", backdrop, YES);
        if (glass) {
            frameView.image = glass;
            orig[@"mine"] = glass;
            orig[@"key"] = key;
            orig[@"view"] = frameView;
            orig[@"styled"] = @YES;
        }
    }
    if (orig[@"styled"]) {
        for (UIView *shade in shades) shade.hidden = YES;
    }
}

// ---- iPhone: mỗi dòng thông báo trên màn khoá là một thẻ kính ----

// Thẻ của dòng: kính không nền (dòng cuộn được), nhớ theo cỡ
static UIImage *G6LockRowCardImage(CGSize size) {
    static NSCache *cache;
    if (!cache) cache = [[NSCache alloc] init];
    if (size.width < 20 || size.height < 16) return nil;
    NSString *key = [NSString stringWithFormat:@"%.0f|%.0f|%lu", size.width, size.height, (unsigned long)G6WallpaperGeneration()];
    UIImage *img = [cache objectForKey:key];
    if (img) return img;
    img = G6GlassImage(@"list", size, YES, nil, CGAffineTransformIdentity);
    if (img) [cache setObject:img forKey:key];
    return img;
}

static BOOL G6LockRowCards(void) {
    return g6_device_is_phone() && G6Feature(@"lock_screen");
}

// Dòng trong danh sách (có nền riêng) hay ô nổi (nền là _firstAlertBGView)
static BOOL G6LockRowHasBackground(UIView *cell) {
    Class floating = objc_getClass("SBAwayBulletinFloatingCell");
    return !(floating && [cell isKindOfClass:floating]);
}

// Nền đen mờ của dòng: SBAwayListItemCell tự tô khi -_hasBackgroundColor trả YES (ô nổi tự trả NO) → đang bật thì trả NO
static BOOL (*o_rowWantsBackground)(id, SEL);
static BOOL g6_rowWantsBackground(id self, SEL _cmd) {
    if (G6LockRowCards()) return NO;
    return o_rowWantsBackground(self, _cmd);
}

static void (*o_rowSetBackground)(id, SEL, UIColor *);

static void G6LockStyleRow(UITableViewCell *cell) {
    BOOL active = G6LockRowCards();
    UIImageView *card = objc_getAssociatedObject(cell, &kRowCardKey);
    UIView *top = G6Ivar(cell, "_separatorTopHalf"), *bottom = G6Ivar(cell, "_separatorBottomHalf");
    BOOL plain = G6LockRowHasBackground(cell);
    if (!active) {
        if (!card) return;
        [card removeFromSuperview];
        objc_setAssociatedObject(cell, &kRowCardKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        cell.contentView.layer.sublayerTransform = CATransform3DIdentity;
        if ([top isKindOfClass:[UIView class]]) top.hidden = NO;
        if ([bottom isKindOfClass:[UIView class]]) bottom.hidden = NO;
        // Trả màu nền SpringBoard đã muốn đặt
        UIColor *wanted = objc_getAssociatedObject(cell, &kRowColorKey);
        if (wanted && o_rowSetBackground) o_rowSetBackground(cell, @selector(setBackgroundColor:), wanted);
        return;
    }
    if (!plain) return;
    if ([top isKindOfClass:[UIView class]]) top.hidden = YES;
    if ([bottom isKindOfClass:[UIView class]]) bottom.hidden = YES;
    CGRect frame = CGRectInset(cell.bounds, kRowCardInsetX, kRowCardInsetY);
    UIImage *image = G6LockRowCardImage(frame.size);
    if (!image) return;
    if (!card) {
        card = [[UIImageView alloc] initWithFrame:frame];
        card.userInteractionEnabled = NO;
        objc_setAssociatedObject(cell, &kRowCardKey, card, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        // Dòng đã có nền đen từ trước khi bật (bật thành phần lúc danh sách đang hiện)
        if (o_rowSetBackground) o_rowSetBackground(cell, @selector(setBackgroundColor:), [UIColor clearColor]);
    }
    if (card.superview != cell || cell.subviews.firstObject != card) [cell insertSubview:card atIndex:0];
    if (!CGRectEqualToRect(card.frame, frame)) card.frame = frame;
    if (card.image != image) card.image = image;
    // Nội dung của dòng (biểu tượng ở x = 9, giờ ở sát mép phải) thu về quanh tâm cho lọt vào thẻ
    cell.contentView.layer.sublayerTransform = CATransform3DMakeScale(kRowContentScale, kRowContentScale, 1);
}

static void (*o_rowLayout)(id, SEL);
static void g6_rowLayout(UITableViewCell *self, SEL _cmd) {
    o_rowLayout(self, _cmd);
    @try {
        G6LockStyleRow(self);
    } @catch (NSException *e) {
        G6Log(@"màn khoá: lỗi khi dựng dòng thông báo: %@", e);
    }
}

// Nền đen mờ của dòng: SpringBoard đặt qua hàm này mỗi lần dựng dòng. Nhớ màu nó muốn (để trả lại khi tắt), đang bật thì
// để trong suốt.
static void g6_rowSetBackground(UITableViewCell *self, SEL _cmd, UIColor *color) {
    BOOL clear = NO;
    @try {
        objc_setAssociatedObject(self, &kRowColorKey, color, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        clear = G6LockRowCards() && G6LockRowHasBackground(self);
    } @catch (NSException *e) {
    }
    o_rowSetBackground(self, _cmd, clear ? [UIColor clearColor] : color);
}

// Danh sách hạ xuống vài điểm: chữ số giờ lớn của iPhone chạm sát mép dưới của thanh trên
static void (*o_setViewRect)(id, SEL, CGRect);
static void g6_setViewRect(id self, SEL _cmd, CGRect rect) {
    if (G6LockRowCards() && rect.size.height > 4 * kPhoneListDrop) {
        rect.origin.y += kPhoneListDrop;
        rect.size.height -= kPhoneListDrop;
    }
    o_setViewRect(self, _cmd, rect);
}

// ---- Áp lên màn khoá ----

static BOOL gApplying;
static void G6LockChargeNote(void);
static void G6LockChargeNoteEnd(BOOL force);

// Đưa màn khoá về đúng trạng thái hiện tại (kiểu mới / kiểu gốc). Gọi bao nhiêu lần cũng được.
static void G6LockApply(UIView *away) {
    // Việc mình làm (đổi ảnh, phông) có thể khiến SpringBoard xếp lại view → hàm này bị gọi lồng: bỏ lần lồng
    if (!away || gApplying) return;
    gApplying = YES;
    @try {
        BOOL active = G6Feature(@"lock_screen");
        G6LockApplyBattery(away);
        G6LockApplyHeader(away, active);
        G6LockApplyBar(away, active);
        G6LockApplyNoSIM(away);
        G6LockApplyList(away, active);
        NSNumber *last = objc_getAssociatedObject(away, &kDrawnKey);
        if (!last || last.boolValue != active) {
            objc_setAssociatedObject(away, &kDrawnKey, @(active), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            if (last || active) G6Log(@"màn khoá: %@", active ? @"kiểu mới" : @"kiểu gốc");
        }
    } @catch (NSException *e) {
        G6Log(@"màn khoá: lỗi khi áp: %@", e);
    }
    gApplying = NO;
}

// ---- Dòng «Đã sạc N%» ----

// Hết giờ (hoặc rút sạc): trả dòng ngày. `force` = NO: chỉ làm khi đã thật sự hết giờ (có thể vừa được nhắc lại).
static void G6LockChargeNoteEnd(BOOL force) {
    if (!force && CFAbsoluteTimeGetCurrent() < gChargeNoteUntil) return;
    if (gChargeNoteUntil == 0) return;
    gChargeNoteUntil = 0;
    NSString *replaced = gChargeNoteReplaced;
    gChargeNoteReplaced = nil;
    UIView *dateView = G6Ivar(gAwayView, "_dateHeaderView");
    UIView *dateLabel = G6Ivar(dateView, "_dateAndTetheringLabel");
    SEL setText = NSSelectorFromString(@"setText:"), update = NSSelectorFromString(@"updateClock");
    if (!dateLabel) return;
    G6LockFade(dateLabel);
    // Trả chữ cũ trước (phòng khi SpringBoard chỉ đặt lại dòng ngày lúc ngày đổi), rồi để SpringBoard cập nhật theo ý nó
    if (replaced && [dateLabel respondsToSelector:setText]) {
        ((void (*)(id, SEL, id))objc_msgSend)(dateLabel, setText, replaced);
        [dateLabel setNeedsDisplay];
    }
    if ([dateView respondsToSelector:update]) ((void (*)(id, SEL))objc_msgSend)(dateView, update);
    else G6LockApply(gAwayView);
}

// Màn khoá vừa hiện / vừa sáng / vừa cắm sạc: máy đang cắm điện thì hiện «Đã sạc N%» vài giây ở chỗ dòng ngày
static void G6LockChargeNote(void) {
    UIView *away = gAwayView;
    if (!away.window || !G6LockHidesBattery() || !G6LockOnAC()) return;
    gChargeNoteUntil = CFAbsoluteTimeGetCurrent() + kChargeNoteSeconds;
    G6LockApply(away);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((kChargeNoteSeconds + 0.05) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        G6LockChargeNoteEnd(NO);
    });
}

// ---- Hàm thay thế ----

static void (*o_awayLayout)(id, SEL);
static void g6_awayLayout(UIView *self, SEL _cmd) {
    o_awayLayout(self, _cmd);
    gAwayView = self;
    G6LockApply(self);
}

// Vào cửa sổ: giờ mới dựng được kính (cần biết view nằm đâu trên hình nền) — ngay, và lần nữa ở vòng lặp kế khi khung đã yên
static void (*o_awayMoved)(id, SEL);
static void g6_awayMoved(UIView *self, SEL _cmd) {
    o_awayMoved(self, _cmd);
    if (!self.window) return;
    gAwayView = self;
    G6LockApply(self);
    __weak UIView *weak = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        G6LockApply(weak);
    });
    G6LockChargeNote();
}

// Màn khoá sáng lên (hết mờ) → nhắc mức sạc
static void (*o_setDimmed)(id, SEL, BOOL);
static void g6_setDimmed(UIView *self, SEL _cmd, BOOL dimmed) {
    o_setDimmed(self, _cmd, dimmed);
    if (!dimmed) G6LockChargeNote();
}

// Vừa cắm / rút sạc
static void (*o_acPowerChanged)(id, SEL);
static void g6_acPowerChanged(id self, SEL _cmd) {
    o_acPowerChanged(self, _cmd);
    if (G6LockOnAC()) G6LockChargeNote();
    else if (gChargeNoteUntil > 0) G6LockChargeNoteEnd(YES);
}

// Khung danh sách đổi cỡ (thêm / bớt thông báo) → dựng lại tấm kính theo cỡ mới
static void (*o_listLayout)(id, SEL);
static void g6_listLayout(UIView *self, SEL _cmd) {
    o_listLayout(self, _cmd);
    G6LockApply(gAwayView);
}

// Mỗi lần đồng hồ màn khoá cập nhật (mỗi phút, lúc sáng màn hình): SpringBoard có thể vừa tạo lại nhãn / đặt lại phông
static void g6_updateClock(UIView *self, SEL _cmd) {
    o_updateClock(self, _cmd);
    G6LockApply(gAwayView);
}

void G6LockInstall(void) {
    Class away = objc_getClass("SBAwayView");
    if (!away) {
        G6Log(@"màn khoá: thiếu lớp SBAwayView — bỏ qua");
        return;
    }
    G6WallpaperInstall();
    if (!G6Hook(away, @selector(layoutSubviews), (IMP)g6_awayLayout, (IMP *)&o_awayLayout)) return;
    G6Hook(away, @selector(didMoveToWindow), (IMP)g6_awayMoved, (IMP *)&o_awayMoved);
    G6HookNamed("SBAwayDateView", NSSelectorFromString(@"updateClock"), (IMP)g6_updateClock, (IMP *)&o_updateClock);
    G6HookNamed("SBAwayBulletinListView", @selector(layoutSubviews), (IMP)g6_listLayout, (IMP *)&o_listLayout);
    if (g6_device_is_phone()) {
        Class row = objc_getClass("SBAwayListItemCell");
        if (row && class_getInstanceVariable(row, "_separatorTopHalf")) {
            G6Hook(row, @selector(layoutSubviews), (IMP)g6_rowLayout, (IMP *)&o_rowLayout);
            G6Hook(row, @selector(setBackgroundColor:), (IMP)g6_rowSetBackground, (IMP *)&o_rowSetBackground);
            G6Hook(row, NSSelectorFromString(@"_hasBackgroundColor"), (IMP)g6_rowWantsBackground, (IMP *)&o_rowWantsBackground);
        }
        G6HookNamed("SBAwayBulletinListController", NSSelectorFromString(@"setViewRect:"), (IMP)g6_setViewRect, (IMP *)&o_setViewRect);
    }
    G6HookNamed("SBAwayLockBar", NSSelectorFromString(@"setShowsSlideshowButton:"), (IMP)g6_setShowsSlideshow, (IMP *)&o_setShowsSlideshow);
    G6HookNamed("SBAwayBulletinListController", NSSelectorFromString(@"activateAlertItem:didUndimScreen:"), (IMP)g6_activateAlertItem,
                (IMP *)&o_activateAlertItem);
    G6Hook(away, NSSelectorFromString(@"shouldShowChargingView"), (IMP)g6_shouldShowCharging, (IMP *)&o_shouldShowCharging);
    G6Hook(away, NSSelectorFromString(@"showChargingView"), (IMP)g6_showCharging, (IMP *)&o_showCharging);
    G6Hook(away, NSSelectorFromString(@"setDimmed:"), (IMP)g6_setDimmed, (IMP *)&o_setDimmed);
    G6HookNamed("SBUIController", NSSelectorFromString(@"ACPowerChanged"), (IMP)g6_acPowerChanged, (IMP *)&o_acPowerChanged);
    for (NSString *name in @[G6ConfigDidChangeNotification, G6WallpaperDidChangeNotification]) {
        [[NSNotificationCenter defaultCenter] addObserverForName:name
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *note) {
                                                          G6LockApply(gAwayView);
                                                      }];
    }
}

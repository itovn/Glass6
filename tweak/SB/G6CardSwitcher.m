// Khay đa nhiệm dạng thẻ của iPhone (kiểu iOS 26).
//
// iOS 6 mở khay đa nhiệm bằng cách đẩy màn hình đang hiện lên, để lộ một dải biểu tượng ở đáy. iOS 26 thì hiện từng app thành
// một tấm thẻ ảnh chụp, cuộn ngang, chạm để mở, vuốt thẻ lên để thoát app. Ở đây dựng lại kiểu thẻ đó bằng các thứ SpringBoard
// iOS 6 có sẵn (tra trên iPhone 5, 19/11/2026):
//   Danh sách app gần đây   SBAppSwitcherModel +sharedInstance  -identifiers (mới nhất đứng đầu)  -remove:
//   Đối tượng app           SBApplicationController +sharedInstance  -applicationWithDisplayIdentifier:
//   Ảnh của app             -[SBApplication defaultImage:preferredScale:originalOrientation:currentOrientation:canUseIOSurface:]
//                           — ảnh chụp lúc app lui về nền (không có thì ảnh mở đầu Default.png); app đang đứng trước thì chụp
//                           thẳng màn hình lúc mở khay
//   Biểu tượng, tên         SBIconModel -leafIconForIdentifier: → -getIconImage:; -[SBApplication displayName]
//   Mở app                  -[SBUIController activateApplicationFromSwitcher:]
//   Thoát app               BKSTerminateApplicationForReasonAndReportWithDescription (BackBoardServices) + -remove: của danh sách
//   Bấm Home hai lần        -[SBUIController _toggleSwitcher]  ← móc: thành phần bật + máy đứng thì mở khay thẻ thay cho dải gốc
//   Bấm Home một lần        -[SBUIController clickedMenuButton] ← móc: khay thẻ đang mở thì đóng
//
// Khay nằm trong một UIWindow riêng (mức 1045: trên app và màn hình chính, dưới thanh trạng thái của SpringBoard). Nền là ảnh
// chụp màn hình đã mờ + lớp tối. Thẻ xếp từ trái sang phải theo thứ tự cũ → mới, mở ra đứng ở thẻ mới nhất; cuộn dừng đúng
// từng thẻ. Ảnh của các thẻ nạp dần sau khi khay đã hiện (mỗi vòng lặp một thẻ, thẻ gần nhất trước) và thu về đúng cỡ thẻ để
// đỡ bộ nhớ; tối đa kMaxCards thẻ. Máy đang nằm ngang (trong app) thì dùng khay gốc của iOS 6.
#import "G6CardSwitcher.h"

#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "G6Device.h"
#import "G6Font.h"
#import "G6Glass.h"
#import "G6Hook.h"
#import "G6Lang.h"
#import "G6Log.h"
#import "G6Prefs.h"
#import "G6Screen.h"

// Thẻ = màn hình thu nhỏ chừng này lần; khe giữa hai thẻ; bán kính góc
static const CGFloat kCardScale = 0.62, kCardGap = 20, kCardRadius = 18;
// Biểu tượng + tên app nằm trên thẻ
static const CGFloat kIconSize = 26, kHeaderGap = 8;
static const NSUInteger kMaxCards = 12;
// Vuốt thẻ lên quá chừng này điểm (hoặc nhanh hơn chừng này điểm / giây) thì thoát app
static const CGFloat kQuitDistance = 90, kQuitVelocity = 700;
static const CGFloat kWindowLevel = 1045;

@interface G6CardView : UIView
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, strong) UIImageView *shot;
@end

@implementation G6CardView
@end

@interface G6CardTarget : NSObject <UIScrollViewDelegate, UIGestureRecognizerDelegate>
- (void)tapAway:(UITapGestureRecognizer *)gesture;
- (void)tapCard:(UITapGestureRecognizer *)gesture;
- (void)panCard:(UIPanGestureRecognizer *)gesture;
@end

static UIWindow *gWindow;
static UIScrollView *gScroll;
static UILabel *gEmpty;
static NSMutableArray *gCards;  // G6CardView, trái → phải = cũ → mới
static G6CardTarget *gTarget;
static BOOL gVisible;
static NSString *gFrontIdentifier;  // app đang đứng trước lúc mở khay (nil: đang ở màn hình chính)
static CGSize gCardSize;
static NSUInteger gLoadGeneration;
// Hàm gốc của -[SBUIController clickedMenuButton] (bấm Home một lần)
static BOOL (*o_clickedMenuButton)(id, SEL);

// ---- Gọi SpringBoard ----

static id G6CSShared(const char *className, NSString *selName) {
    Class cls = objc_getClass(className);
    SEL sel = NSSelectorFromString(selName);
    return [cls respondsToSelector:sel] ? ((id (*)(id, SEL))objc_msgSend)(cls, sel) : nil;
}

static id G6CSApp(NSString *identifier) {
    id controller = G6CSShared("SBApplicationController", @"sharedInstance");
    SEL sel = NSSelectorFromString(@"applicationWithDisplayIdentifier:");
    return [controller respondsToSelector:sel] ? ((id (*)(id, SEL, id))objc_msgSend)(controller, sel, identifier) : nil;
}

static NSString *G6CSFrontIdentifier(void) {
    UIApplication *springBoard = [UIApplication sharedApplication];
    SEL front = NSSelectorFromString(@"_accessibilityFrontMostApplication"), ident = NSSelectorFromString(@"displayIdentifier");
    id app = [springBoard respondsToSelector:front] ? ((id (*)(id, SEL))objc_msgSend)(springBoard, front) : nil;
    id identifier = [app respondsToSelector:ident] ? ((id (*)(id, SEL))objc_msgSend)(app, ident) : nil;
    return [identifier isKindOfClass:[NSString class]] ? identifier : nil;
}

// Mã các app gần đây còn cài trên máy, mới nhất đứng đầu
static NSArray *G6CSRecents(void) {
    id model = G6CSShared("SBAppSwitcherModel", @"sharedInstance");
    SEL sel = NSSelectorFromString(@"identifiers");
    NSArray *all = [model respondsToSelector:sel] ? ((id (*)(id, SEL))objc_msgSend)(model, sel) : nil;
    NSMutableArray *out = [NSMutableArray array];
    if (![all isKindOfClass:[NSArray class]]) return out;
    for (id identifier in [all copy]) {
        if ([identifier isKindOfClass:[NSString class]] && ![out containsObject:identifier] && G6CSApp(identifier)) [out addObject:identifier];
        if (out.count >= kMaxCards) break;
    }
    return out;
}

static NSString *G6CSName(id app) {
    SEL sel = NSSelectorFromString(@"displayName");
    id name = [app respondsToSelector:sel] ? ((id (*)(id, SEL))objc_msgSend)(app, sel) : nil;
    return [name isKindOfClass:[NSString class]] ? name : @"";
}

static UIImage *G6CSIcon(NSString *identifier) {
    id controller = G6CSShared("SBIconController", @"sharedInstance");
    SEL modelSel = NSSelectorFromString(@"model"), find = NSSelectorFromString(@"leafIconForIdentifier:"), get = NSSelectorFromString(@"getIconImage:");
    id model = [controller respondsToSelector:modelSel] ? ((id (*)(id, SEL))objc_msgSend)(controller, modelSel) : nil;
    id icon = [model respondsToSelector:find] ? ((id (*)(id, SEL, id))objc_msgSend)(model, find, identifier) : nil;
    // Định dạng 2 = biểu tượng của màn hình chính
    id image = [icon respondsToSelector:get] ? ((id (*)(id, SEL, int))objc_msgSend)(icon, get, 2) : nil;
    return [image isKindOfClass:[UIImage class]] ? image : nil;
}

// Ảnh SpringBoard dùng lúc phóng app ra: ảnh chụp lần lui về nền gần nhất, không có thì ảnh mở đầu của app
static UIImage *G6CSSnapshot(id app) {
    SEL sel = NSSelectorFromString(@"defaultImage:preferredScale:originalOrientation:currentOrientation:canUseIOSurface:");
    if (![app respondsToSelector:sel]) return nil;
    BOOL isSnapshot = NO;
    int original = 0, current = 0;
    id image = ((id (*)(id, SEL, BOOL *, float, int *, int *, BOOL))objc_msgSend)(app, sel, &isSnapshot, (float)[UIScreen mainScreen].scale, &original,
                                                                                &current, NO);
    return [image isKindOfClass:[UIImage class]] ? image : nil;
}

static void G6CSTerminate(NSString *identifier) {
    static void (*terminate)(CFStringRef, int, int, CFStringRef);
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *h = dlopen("/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices", RTLD_NOW);
        if (h) terminate = dlsym(h, "BKSTerminateApplicationForReasonAndReportWithDescription");
    });
    id model = G6CSShared("SBAppSwitcherModel", @"sharedInstance");
    SEL remove = NSSelectorFromString(@"remove:");
    if ([model respondsToSelector:remove]) ((void (*)(id, SEL, id))objc_msgSend)(model, remove, identifier);
    // Lý do 1 = người dùng thoát app từ khay đa nhiệm (đúng số SpringBoard dùng); không ghi báo cáo sập
    if (terminate) terminate((__bridge CFStringRef)identifier, 1, 0, CFSTR("Glass 6: thoát từ khay đa nhiệm"));
}

// Thoát app của một thẻ. App đang đứng trước (mở khay từ trong app đó): iOS 6 không có đường «thoát app đang mở từ khay» — dừng
// thẳng thì SpringBoard không dựng lại màn hình chính (đo trên iPhone: màn hình đen, bấm Home cũng không về). Vì vậy cho app lui
// về nền như bấm Home trước (khay thẻ đang che phía trên nên không thấy), xong mới dừng.
static void G6CSQuit(NSString *identifier) {
    BOOL front = gFrontIdentifier && [identifier isEqualToString:gFrontIdentifier];
    if (!front) {
        G6CSTerminate(identifier);
        return;
    }
    gFrontIdentifier = nil;
    id ui = G6CSShared("SBUIController", @"sharedInstance");
    if (o_clickedMenuButton && ui) o_clickedMenuButton(ui, NSSelectorFromString(@"clickedMenuButton"));
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.9 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        // Trong lúc chờ người dùng có thể đã mở lại đúng app đó: khi ấy để yên
        if (![G6CSFrontIdentifier() isEqualToString:identifier]) G6CSTerminate(identifier);
    });
}

// ---- Ảnh thẻ ----

// Thu ảnh về đúng cỡ thẻ. Ảnh chụp của app có thanh trạng thái thường thiếu phần thanh trạng thái → dồn xuống đáy, phần trên
// để đen; ảnh nằm ngang thì đặt vừa bề ngang, ở giữa.
static UIImage *G6CSScaled(UIImage *image, CGSize size) {
    if (!image || image.size.width < 1 || image.size.height < 1) return nil;
    UIGraphicsBeginImageContextWithOptions(size, YES, 0);
    [[UIColor colorWithWhite:0.06 alpha:1] setFill];
    UIRectFill(CGRectMake(0, 0, size.width, size.height));
    CGFloat scale = size.width / image.size.width, height = image.size.height * scale;
    BOOL landscape = image.size.width > image.size.height;
    CGFloat y = landscape ? (size.height - height) / 2 : size.height - height;
    if (!landscape && y > 0.5 && image.CGImage) {
        // Phần thanh trạng thái còn thiếu: kéo giãn hàng điểm ảnh trên cùng của ảnh lên lấp (liền màu với thanh của app)
        CGImageRef strip = CGImageCreateWithImageInRect(image.CGImage, CGRectMake(0, 0, CGImageGetWidth(image.CGImage), 2));
        if (strip) {
            [[UIImage imageWithCGImage:strip] drawInRect:CGRectMake(0, 0, size.width, y + 1)];
            CGImageRelease(strip);
        }
    }
    [image drawInRect:CGRectMake(0, y, size.width, height)];
    UIImage *out = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return out;
}

// ---- Bố cục ----

static CGFloat G6CSStep(void) {
    return gCardSize.width + kCardGap;
}

static void G6CSLayout(BOOL animated) {
    CGSize full = gScroll.bounds.size;
    CGFloat side = floor((full.width - gCardSize.width) / 2), header = kIconSize + kHeaderGap;
    CGFloat top = floor((full.height - gCardSize.height - header) / 2) + 8;
    void (^place)(void) = ^{
        NSUInteger i = 0;
        for (G6CardView *card in gCards) {
            card.transform = CGAffineTransformIdentity;
            card.alpha = 1;
            card.frame = CGRectMake(side + i * G6CSStep(), top, gCardSize.width, gCardSize.height + header);
            i++;
        }
        CGFloat width = 2 * side + gCards.count * gCardSize.width + (gCards.count > 1 ? (gCards.count - 1) * kCardGap : 0);
        gScroll.contentSize = CGSizeMake(MAX(width, full.width), full.height);
        // Bớt thẻ ở cuối: lùi về thẻ cuối cùng còn lại
        CGFloat last = gCards.count > 0 ? (gCards.count - 1) * G6CSStep() : 0;
        if (gScroll.contentOffset.x > last) gScroll.contentOffset = CGPointMake(last, 0);
    };
    if (animated) [UIView animateWithDuration:0.25 animations:place];
    else place();
    gEmpty.hidden = gCards.count > 0;
}

static G6CardView *G6CSMakeCard(NSString *identifier) {
    id app = G6CSApp(identifier);
    CGFloat header = kIconSize + kHeaderGap;
    G6CardView *card = [[G6CardView alloc] initWithFrame:CGRectMake(0, 0, gCardSize.width, gCardSize.height + header)];
    card.identifier = identifier;
    UIImageView *icon = [[UIImageView alloc] initWithFrame:CGRectMake(2, 0, kIconSize, kIconSize)];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.image = G6CSIcon(identifier);
    [card addSubview:icon];
    UILabel *name = [[UILabel alloc] initWithFrame:CGRectMake(kIconSize + 9, 0, gCardSize.width - kIconSize - 11, kIconSize)];
    name.backgroundColor = [UIColor clearColor];
    name.textColor = [UIColor whiteColor];
    name.font = G6Font(G6FontSemiBold, 14);
    name.shadowColor = [UIColor colorWithWhite:0 alpha:0.5];
    name.shadowOffset = CGSizeMake(0, 1);
    name.lineBreakMode = NSLineBreakByTruncatingTail;
    name.text = G6CSName(app);
    [card addSubview:name];
    CGRect shotFrame = CGRectMake(0, header, gCardSize.width, gCardSize.height);
    card.shot = [[UIImageView alloc] initWithFrame:shotFrame];
    card.shot.backgroundColor = [UIColor colorWithWhite:0.10 alpha:1];
    card.shot.layer.cornerRadius = kCardRadius;
    card.shot.layer.masksToBounds = YES;
    [card addSubview:card.shot];
    // Bóng đổ của thẻ (thẻ không cắt theo khung nên bóng hiện được); khai đường viền bóng để khỏi phải tính lại mỗi khung hình
    card.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:shotFrame cornerRadius:kCardRadius].CGPath;
    card.layer.shadowColor = [UIColor blackColor].CGColor;
    card.layer.shadowOpacity = 0.45;
    card.layer.shadowRadius = 12;
    card.layer.shadowOffset = CGSizeMake(0, 6);
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:gTarget action:@selector(tapCard:)];
    [card addGestureRecognizer:tap];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:gTarget action:@selector(panCard:)];
    pan.delegate = gTarget;
    [card addGestureRecognizer:pan];
    return card;
}

// Nạp ảnh cho các thẻ còn trống, mỗi vòng lặp một thẻ, bắt đầu từ thẻ mới nhất (đang nằm giữa màn hình)
static void G6CSLoadNext(NSUInteger generation) {
    if (!gVisible || generation != gLoadGeneration) return;
    for (G6CardView *card in [gCards reverseObjectEnumerator]) {
        if (card.shot.image || card.tag == 1) continue;
        card.tag = 1;  // đã thử nạp (kể cả khi app không có ảnh nào)
        @try {
            card.shot.image = G6CSScaled(G6CSSnapshot(G6CSApp(card.identifier)), gCardSize);
        } @catch (NSException *e) {
            G6Log(@"khay thẻ: lỗi khi lấy ảnh của %@: %@", card.identifier, e);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            G6CSLoadNext(generation);
        });
        return;
    }
}

static void G6CSLayout(BOOL animated);

// Thẻ bay lên khỏi màn hình rồi app của nó bị thoát; các thẻ còn lại dồn lại
static void G6CSFlyAwayAndQuit(G6CardView *card) {
    [UIView animateWithDuration:0.18
                     animations:^{
                         card.transform = CGAffineTransformMakeTranslation(0, -(CGRectGetMaxY(card.frame) + 40));
                         card.alpha = 0;
                     }
                     completion:^(BOOL finished) {
                         NSString *identifier = card.identifier;
                         [card removeFromSuperview];
                         [gCards removeObject:card];
                         @try {
                             G6CSQuit(identifier);
                             G6Log(@"khay thẻ: thoát app %@", identifier);
                         } @catch (NSException *e) {
                             G6Log(@"khay thẻ: lỗi khi thoát app %@: %@", identifier, e);
                         }
                         if (gVisible) G6CSLayout(YES);
                     }];
}

// ---- Hiện / ẩn ----

static void G6CSTearDown(void) {
    gLoadGeneration++;
    gWindow.hidden = YES;
    gWindow = nil;
    gScroll = nil;
    gEmpty = nil;
    gCards = nil;
    gFrontIdentifier = nil;
}

static BOOL G6CSEnabled(void) {
    if (!g6_device_is_phone() || !G6Feature(@"switcher") || ![G6Config()[@"switcher_cards"] boolValue]) return NO;
    return [UIApplication sharedApplication].statusBarOrientation == UIInterfaceOrientationPortrait;
}

void G6CardSwitcherSetVisible(BOOL visible, BOOL animated) {
    if (visible == gVisible) return;
    if (!visible) {
        gVisible = NO;
        UIWindow *window = gWindow;
        [UIView animateWithDuration:animated ? 0.2 : 0
                         animations:^{
                             window.alpha = 0;
                         }
                         completion:^(BOOL finished) {
                             // Trong lúc đang mờ dần người dùng có thể đã mở lại
                             if (!gVisible && gWindow == window) G6CSTearDown();
                         }];
        return;
    }
    if (!G6CSEnabled()) return;
    @try {
        G6CSTearDown();
        double t0 = G6NowMs();
        if (!gTarget) gTarget = [[G6CardTarget alloc] init];
        gFrontIdentifier = G6CSFrontIdentifier();
        // Chụp màn hình trước khi cửa sổ của khay hiện: làm nền mờ, và làm ảnh thẻ của app đang đứng trước
        G6Backdrop *backdrop = nil;
        UIImage *screen = G6ScreenImage(&backdrop, YES);
        CGRect bounds = [UIScreen mainScreen].bounds;
        gCardSize = CGSizeMake(round(bounds.size.width * kCardScale), round(bounds.size.height * kCardScale));
        gWindow = [[UIWindow alloc] initWithFrame:bounds];
        gWindow.windowLevel = kWindowLevel;
        gWindow.backgroundColor = [UIColor blackColor];
        UIImageView *blur = [[UIImageView alloc] initWithFrame:bounds];
        if (backdrop) blur.image = G6ImageFromPixels(backdrop.pixels, backdrop.width, backdrop.height, 1);
        [gWindow addSubview:blur];
        UIView *dim = [[UIView alloc] initWithFrame:bounds];
        dim.backgroundColor = [UIColor colorWithWhite:0 alpha:0.38];
        [gWindow addSubview:dim];

        gScroll = [[UIScrollView alloc] initWithFrame:bounds];
        gScroll.showsHorizontalScrollIndicator = NO;
        gScroll.showsVerticalScrollIndicator = NO;
        gScroll.alwaysBounceHorizontal = YES;
        gScroll.decelerationRate = UIScrollViewDecelerationRateFast;
        gScroll.delegate = gTarget;
        gScroll.clipsToBounds = NO;
        [gWindow addSubview:gScroll];
        // Chạm vào chỗ trống → đóng
        UITapGestureRecognizer *away = [[UITapGestureRecognizer alloc] initWithTarget:gTarget action:@selector(tapAway:)];
        away.delegate = gTarget;
        [gScroll addGestureRecognizer:away];

        gEmpty = [[UILabel alloc] initWithFrame:CGRectMake(20, bounds.size.height / 2 - 20, bounds.size.width - 40, 40)];
        gEmpty.backgroundColor = [UIColor clearColor];
        gEmpty.textColor = [UIColor colorWithWhite:1 alpha:0.75];
        gEmpty.font = G6Font(G6FontMedium, 16);
        gEmpty.textAlignment = NSTextAlignmentCenter;
        gEmpty.text = G6L(@"Chưa có app nào mở gần đây");
        [gWindow addSubview:gEmpty];

        gCards = [NSMutableArray array];
        for (NSString *identifier in [G6CSRecents() reverseObjectEnumerator]) {
            G6CardView *card = G6CSMakeCard(identifier);
            if ([identifier isEqualToString:gFrontIdentifier]) {
                card.shot.image = G6CSScaled(screen, gCardSize);
                card.tag = 1;
            }
            [gScroll addSubview:card];
            [gCards addObject:card];
        }
        G6CSLayout(NO);
        if (gCards.count > 0) gScroll.contentOffset = CGPointMake((gCards.count - 1) * G6CSStep(), 0);
        gVisible = YES;
        gWindow.alpha = 0;
        gWindow.hidden = NO;
        gScroll.transform = CGAffineTransformMakeScale(1.08, 1.08);
        [UIView animateWithDuration:animated ? 0.22 : 0
                         animations:^{
                             gWindow.alpha = 1;
                             gScroll.transform = CGAffineTransformIdentity;
                         }];
        NSUInteger generation = ++gLoadGeneration;
        dispatch_async(dispatch_get_main_queue(), ^{
            G6CSLoadNext(generation);
        });
        G6Log(@"khay thẻ: mở, %lu thẻ, app đứng trước «%@» (%.1f ms)", (unsigned long)gCards.count, gFrontIdentifier ?: @"màn hình chính", G6NowMs() - t0);
    } @catch (NSException *e) {
        G6Log(@"khay thẻ: lỗi khi mở: %@", e);
        G6CSTearDown();
        gVisible = NO;
    }
}

// ---- Chạm, vuốt, cuộn ----

@implementation G6CardTarget

- (void)tapAway:(UITapGestureRecognizer *)gesture {
    G6CardSwitcherSetVisible(NO, YES);
}

- (void)tapCard:(UITapGestureRecognizer *)gesture {
    G6CardView *card = (G6CardView *)gesture.view;
    if (![card isKindOfClass:[G6CardView class]] || !gVisible) return;
    NSString *identifier = card.identifier;
    BOOL isFront = gFrontIdentifier && [identifier isEqualToString:gFrontIdentifier];
    G6CardSwitcherSetVisible(NO, YES);
    if (isFront) return;  // app đang đứng trước: chỉ cần đóng khay
    @try {
        id app = G6CSApp(identifier), ui = G6CSShared("SBUIController", @"sharedInstance");
        SEL sel = NSSelectorFromString(@"activateApplicationFromSwitcher:");
        if (app && [ui respondsToSelector:sel]) ((void (*)(id, SEL, id))objc_msgSend)(ui, sel, app);
        G6Log(@"khay thẻ: mở app %@", identifier);
    } @catch (NSException *e) {
        G6Log(@"khay thẻ: lỗi khi mở app %@: %@", identifier, e);
    }
}

// Vuốt thẻ lên: thẻ đi theo ngón tay; thả tay khi đã đủ xa / đủ nhanh thì thoát app, không thì thẻ về chỗ cũ
- (void)panCard:(UIPanGestureRecognizer *)gesture {
    G6CardView *card = (G6CardView *)gesture.view;
    if (![card isKindOfClass:[G6CardView class]]) return;
    CGFloat dy = MIN(0, [gesture translationInView:gScroll].y);
    if (gesture.state == UIGestureRecognizerStateChanged) {
        card.transform = CGAffineTransformMakeTranslation(0, dy);
        card.alpha = MAX(0.4, 1 + dy / 500);
        return;
    }
    if (gesture.state != UIGestureRecognizerStateEnded && gesture.state != UIGestureRecognizerStateCancelled) return;
    BOOL quit = gesture.state == UIGestureRecognizerStateEnded && (dy < -kQuitDistance || [gesture velocityInView:gScroll].y < -kQuitVelocity);
    if (!quit) {
        [UIView animateWithDuration:0.2
                         animations:^{
                             card.transform = CGAffineTransformIdentity;
                             card.alpha = 1;
                         }];
        return;
    }
    G6CSFlyAwayAndQuit(card);
}

// Thẻ chỉ nhận cử chỉ kéo khi ngón tay đi LÊN là chính — kéo ngang để cho khung cuộn
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
    if (![gesture isKindOfClass:[UIPanGestureRecognizer class]] || ![gesture.view isKindOfClass:[G6CardView class]]) return YES;
    CGPoint v = [(UIPanGestureRecognizer *)gesture velocityInView:gScroll];
    return v.y < 0 && fabs(v.y) > fabs(v.x) * 1.2;
}

// Cử chỉ «chạm chỗ trống» không nhận ngón tay đặt trên thẻ
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
    if (gesture.view != gScroll) return YES;
    for (UIView *v = touch.view; v && v != gScroll; v = v.superview) {
        if ([v isKindOfClass:[G6CardView class]]) return NO;
    }
    return YES;
}

// Cuộn dừng đúng một thẻ ở giữa màn hình
- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView withVelocity:(CGPoint)velocity targetContentOffset:(inout CGPoint *)target {
    if (gCards.count == 0) return;
    CGFloat step = G6CSStep();
    NSInteger index = (NSInteger)lround(target->x / step);
    index = MAX(0, MIN((NSInteger)gCards.count - 1, index));
    target->x = index * step;
}

@end

#if G6_DEBUG
void G6CardSwitcherDebug(NSString *arg) {
    NSArray *parts = [arg componentsSeparatedByString:@" "];
    NSString *verb = parts.count ? parts[0] : @"";
    if ([verb isEqualToString:@"1"] || [verb isEqualToString:@"0"]) {
        G6CardSwitcherSetVisible(verb.intValue != 0, YES);
    } else if (!gVisible) {
        G6Log(@"[thử] khay thẻ: chưa mở");
        return;
    } else if ([verb isEqualToString:@"tap"] || [verb isEqualToString:@"quit"]) {
        NSInteger n = parts.count > 1 ? [parts[1] integerValue] : 0, index = (NSInteger)gCards.count - 1 - n;
        if (index < 0 || index >= (NSInteger)gCards.count) {
            G6Log(@"[thử] khay thẻ: không có thẻ thứ %ld", (long)n);
            return;
        }
        G6CardView *card = gCards[(NSUInteger)index];
        if ([verb isEqualToString:@"tap"]) {
            [gTarget tapCard:card.gestureRecognizers.firstObject];
        } else {
            // Như vuốt thẻ lên quá ngưỡng: thẻ bay lên rồi thoát app
            G6CSFlyAwayAndQuit(card);
        }
        return;
    }
    NSMutableArray *names = [NSMutableArray array];
    for (G6CardView *card in [gCards reverseObjectEnumerator]) [names addObject:card.identifier];
    G6Log(@"[thử] khay thẻ: %@, đứng trước «%@», vị trí cuộn %.0f, thẻ (mới → cũ): %@", gVisible ? @"đang mở" : @"đóng", gFrontIdentifier ?: @"màn hình chính",
          gScroll.contentOffset.x, [names componentsJoinedByString:@", "]);
}
#endif

// ---- Hàm thay thế ----

// Bấm Home hai lần (đã qua các phép kiểm của SpringBoard: không khoá máy, không đang gọi…)
static void (*o_toggleSwitcher)(id, SEL);
static void g6_toggleSwitcher(id self, SEL _cmd) {
    if (gVisible) {
        G6CardSwitcherSetVisible(NO, YES);
        return;
    }
    if (G6CSEnabled()) {
        G6CardSwitcherSetVisible(YES, YES);
        if (gVisible) return;
    }
    o_toggleSwitcher(self, _cmd);
}

// Bấm Home một lần lúc khay thẻ đang mở: đóng khay, ở lại chỗ cũ
static BOOL g6_clickedMenuButton(id self, SEL _cmd) {
    if (gVisible) {
        G6CardSwitcherSetVisible(NO, YES);
        return YES;
    }
    return o_clickedMenuButton(self, _cmd);
}

void G6CardSwitcherInstall(void) {
    if (!g6_device_is_phone()) return;
    Class ui = objc_getClass("SBUIController");
    if (!ui || !objc_getClass("SBAppSwitcherModel")) {
        G6Log(@"khay thẻ: thiếu SBUIController / SBAppSwitcherModel — bỏ qua");
        return;
    }
    G6ScreenWatchInstall();
    if (!G6Hook(ui, NSSelectorFromString(@"_toggleSwitcher"), (IMP)g6_toggleSwitcher, (IMP *)&o_toggleSwitcher)) return;
    G6Hook(ui, NSSelectorFromString(@"clickedMenuButton"), (IMP)g6_clickedMenuButton, (IMP *)&o_clickedMenuButton);
    // Tắt thành phần lúc khay đang mở, khoá máy, tắt màn hình → đóng khay
    for (NSString *name in @[G6ConfigDidChangeNotification, G6ScreenStateDidChangeNotification]) {
        [[NSNotificationCenter defaultCenter] addObserverForName:name
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *note) {
                                                          if (gVisible && (!G6CSEnabled() || !G6ScreenAwake())) G6CardSwitcherSetVisible(NO, NO);
                                                      }];
    }
}

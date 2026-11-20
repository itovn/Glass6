// Bảng nổi (UIPopoverController — trên iPad cả bảng chọn UIActionSheet cũng nằm trong bảng nổi), thuộc thành phần «bars».
//
// iOS 6 vẽ khung bảng nổi xanh đen bóng, viền dày. UIKit cho thay khung bằng một lớp con của UIPopoverBackgroundView (API công
// khai từ iOS 5: `popoverBackgroundViewClass`) → G6UIPopoverBackground: tấm phẳng cùng màu với thanh (sáng / than), bo góc,
// viền mảnh, bóng đổ mềm, mũi tên cùng màu.
//
// Gắn mặc định: ngay sau -[UIPopoverController initWithContentViewController:] đặt lớp khung của Glass 6. App tự đặt lớp khung
// riêng (sau khi tạo) thì của app thắng. Bảng nổi đang mở không đổi theo khi bật / tắt — bảng mở sau mới theo kiểu mới.
//
// Nút lớn trong bảng nổi (UIPopoverButton — «Bắt đầu Trình chiếu» của app Ảnh…): nền xanh đen bóng → viên bo góc màu nhấn, chữ
// trắng phông Inter, bỏ bóng chữ.
#import "G6UI.h"

#import <QuartzCore/QuartzCore.h>

#import "G6Font.h"
#import "G6Hook.h"
#import "G6Log.h"
#import "G6Prefs.h"

static BOOL gActive;

static const CGFloat kArrowBase = 30, kArrowHeight = 13, kCorner = 12, kBorder = 5;

@interface G6UIPopoverBackground : UIPopoverBackgroundView
@end

@implementation G6UIPopoverBackground {
    CGFloat _offset;
    UIPopoverArrowDirection _direction;
    CAShapeLayer *_shape;
}

+ (CGFloat)arrowBase {
    return kArrowBase;
}

+ (CGFloat)arrowHeight {
    return kArrowHeight;
}

+ (UIEdgeInsets)contentViewInsets {
    return UIEdgeInsetsMake(kBorder, kBorder, kBorder, kBorder);
}

// iOS 6: không vẽ bóng chìm / bo góc mặc định lên nội dung
+ (BOOL)wantsDefaultContentAppearance {
    return NO;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        _shape = [CAShapeLayer layer];
        [self.layer addSublayer:_shape];
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOffset = CGSizeMake(0, 6);
        self.layer.shadowRadius = 18;
        self.layer.shadowOpacity = 0.30;
    }
    return self;
}

- (CGFloat)arrowOffset {
    return _offset;
}

- (void)setArrowOffset:(CGFloat)arrowOffset {
    _offset = arrowOffset;
    [self setNeedsLayout];
}

- (UIPopoverArrowDirection)arrowDirection {
    return _direction;
}

- (void)setArrowDirection:(UIPopoverArrowDirection)arrowDirection {
    _direction = arrowDirection;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds, body = bounds;
    CGFloat ah = kArrowHeight, half = kArrowBase / 2;
    // Thân tấm: phần còn lại sau khi trừ chỗ của mũi tên
    switch (_direction) {
        case UIPopoverArrowDirectionUp:
            body.origin.y += ah;
            body.size.height -= ah;
            break;
        case UIPopoverArrowDirectionDown:
            body.size.height -= ah;
            break;
        case UIPopoverArrowDirectionLeft:
            body.origin.x += ah;
            body.size.width -= ah;
            break;
        case UIPopoverArrowDirectionRight:
            body.size.width -= ah;
            break;
        default:
            break;
    }
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:body cornerRadius:kCorner];
    // Mũi tên: tam giác đỉnh hơi tù, tâm lệch `_offset` so với giữa cạnh, không chạm vào góc bo
    UIBezierPath *arrow = [UIBezierPath bezierPath];
    CGFloat limitX = CGRectGetWidth(body) / 2 - kCorner - half, limitY = CGRectGetHeight(body) / 2 - kCorner - half;
    CGFloat dx = MAX(-limitX, MIN(limitX, _offset)), dy = MAX(-limitY, MIN(limitY, _offset));
    CGFloat cx = CGRectGetMidX(body) + dx, cy = CGRectGetMidY(body) + dy;
    switch (_direction) {
        case UIPopoverArrowDirectionUp:
            [arrow moveToPoint:CGPointMake(cx - half, CGRectGetMinY(body) + 0.5)];
            [arrow addLineToPoint:CGPointMake(cx, 0)];
            [arrow addLineToPoint:CGPointMake(cx + half, CGRectGetMinY(body) + 0.5)];
            break;
        case UIPopoverArrowDirectionDown:
            [arrow moveToPoint:CGPointMake(cx - half, CGRectGetMaxY(body) - 0.5)];
            [arrow addLineToPoint:CGPointMake(cx, CGRectGetMaxY(bounds))];
            [arrow addLineToPoint:CGPointMake(cx + half, CGRectGetMaxY(body) - 0.5)];
            break;
        case UIPopoverArrowDirectionLeft:
            [arrow moveToPoint:CGPointMake(CGRectGetMinX(body) + 0.5, cy - half)];
            [arrow addLineToPoint:CGPointMake(0, cy)];
            [arrow addLineToPoint:CGPointMake(CGRectGetMinX(body) + 0.5, cy + half)];
            break;
        case UIPopoverArrowDirectionRight:
            [arrow moveToPoint:CGPointMake(CGRectGetMaxX(body) - 0.5, cy - half)];
            [arrow addLineToPoint:CGPointMake(CGRectGetMaxX(bounds), cy)];
            [arrow addLineToPoint:CGPointMake(CGRectGetMaxX(body) - 0.5, cy + half)];
            break;
        default:
            break;
    }
    [arrow closePath];
    [path appendPath:arrow];

    BOOL dark = G6UIDark();
    _shape.frame = bounds;
    _shape.path = path.CGPath;
    _shape.fillColor = (dark ? [UIColor colorWithWhite:0.11 alpha:1] : [UIColor colorWithWhite:0.972 alpha:1]).CGColor;
    _shape.strokeColor = [UIColor colorWithWhite:dark ? 1 : 0 alpha:dark ? 0.16 : 0.12].CGColor;
    _shape.lineWidth = 1 / [UIScreen mainScreen].scale;
    self.layer.shadowPath = path.CGPath;
    self.layer.shadowOpacity = dark ? 0.55 : 0.30;
}

@end

static id (*orig_popoverInit)(id, SEL, id);
__attribute__((ns_returns_retained)) static id repl_popoverInit(__attribute__((ns_consumed)) id self, SEL _cmd, id content) {
    UIPopoverController *popover = orig_popoverInit(self, _cmd, content);
    @try {
        if (gActive && popover && !popover.popoverBackgroundViewClass) {
            popover.popoverBackgroundViewClass = [G6UIPopoverBackground class];
        }
    } @catch (NSException *e) {
        G6Log(@"bảng nổi: lỗi %@", e);
    }
    return popover;
}

// ---- Nút lớn trong bảng nổi ----

static UIImage *G6PopoverButtonImage(CGFloat height, BOOL pressed) {
    static NSMutableDictionary *cache;
    if (height < 12) return nil;
    NSString *key = [NSString stringWithFormat:@"%.0f|%d", height, pressed];
    UIImage *image = cache[key];
    if (image) return image;
    const CGFloat radius = 10, width = 2 * radius + 1;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(width, height), NO, 0);
    [(pressed ? [UIColor colorWithRed:0 green:0.38 blue:0.84 alpha:1] : [UIColor colorWithRed:0 green:0.478 blue:1 alpha:1]) setFill];
    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, width, height) cornerRadius:radius] fill];
    image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    image = [image resizableImageWithCapInsets:UIEdgeInsetsMake(radius, radius, radius, radius)];
    if (!cache) cache = [NSMutableDictionary dictionary];
    if (image) cache[key] = image;
    return image;
}

static void (*orig_popButtonLayout)(UIButton *, SEL);
static void repl_popButtonLayout(UIButton *self, SEL _cmd) {
    if (gActive) {
        @try {
            UIImage *normal = G6PopoverButtonImage(self.bounds.size.height, NO);
            if (normal && [self backgroundImageForState:UIControlStateNormal] != normal) {
                [self setBackgroundImage:normal forState:UIControlStateNormal];
                [self setBackgroundImage:G6PopoverButtonImage(self.bounds.size.height, YES) forState:UIControlStateHighlighted];
                // App đang được vẽ lại ở chế độ tối: cửa sổ mang bộ lọc đảo → chữ phải vẽ ĐEN mới hiện ra trắng
                UIColor *text = (G6UISkinActive() && G6IsDark()) ? [UIColor blackColor] : [UIColor whiteColor];
                for (NSNumber *state in @[@(UIControlStateNormal), @(UIControlStateHighlighted)]) {
                    [self setTitleColor:text forState:(UIControlState)state.unsignedIntegerValue];
                    [self setTitleShadowColor:[UIColor clearColor] forState:(UIControlState)state.unsignedIntegerValue];
                }
                if (G6FontAvailable()) {
                    UIFont *want = G6Font(G6FontSemiBold, self.titleLabel.font.pointSize > 0 ? self.titleLabel.font.pointSize : 17);
                    if (want) self.titleLabel.font = want;
                }
            }
        } @catch (NSException *e) {
        }
    }
    orig_popButtonLayout(self, _cmd);
}

void G6UIPopoverApply(BOOL allowed) {
    BOOL active = allowed && G6Feature(@"apps") && G6Feature(@"bars");
    if (active) {
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            if (!G6Hook([UIPopoverController class], @selector(initWithContentViewController:), (IMP)repl_popoverInit,
                        (IMP *)&orig_popoverInit)) {
                G6Log(@"bảng nổi: không gắn được — giữ khung cũ");
            }
            if (objc_getClass("UIPopoverButton")) {
                G6HookNamed("UIPopoverButton", @selector(layoutSubviews), (IMP)repl_popButtonLayout, (IMP *)&orig_popButtonLayout);
            }
        });
    }
    gActive = active;
}

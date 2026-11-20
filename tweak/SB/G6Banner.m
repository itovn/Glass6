// Băng thông báo — iOS 6 → kính.
//
// iOS 6 (tra trên máy 19/11/2026): SBBulletinBannerController tạo SBBulletinBannerView (: SBUIRoundedBannerItemView) cho mỗi
// thông báo: _backgroundImageView (ảnh nền đen bóng, từ -_backgroundImageWithAttachmentImage:), _iconView, _titleLabel,
// _messageLabel. Băng nằm trong SBBannerAndShadowView (bóng đổ + hiệu ứng lật khối). Thử: -[SBBulletinBannerController
// showTestBanner] (lệnh thử `banner`).
//
// Cách làm: sau -layoutSubviews / -didMoveToWindow của băng, thay ảnh nền bằng tấm kính (bề mặt `banner`), nền của kính là
// ảnh chụp màn hình một lần lúc băng sắp hiện (băng nổi trên app). Chữ: Inter, màu theo chế độ sáng / tối. Mỗi băng chỉ dựng
// một lần; băng sống vài giây rồi bỏ nên không cần trả lại kiểu gốc — tắt thành phần thì băng kế tiếp là kiểu gốc.
//
// iPhone — thẻ kính nổi kiểu iOS 26: băng gốc chạy hết bề ngang và che thanh trạng thái (320×40 ở gốc toạ độ). Trên iPhone
// băng thành một thẻ bo góc lùi vào hai bên, nằm ngay DƯỚI thanh trạng thái (thanh trạng thái vẫn hiện nguyên):
//   - khung: -[SBBannerController _normalBannerFrameForOrientation:] trả khung thẻ;
//   - nền: một UIImageView kính riêng (+ bóng đổ) nằm dưới cùng của băng; mọi nền gốc bị ẩn, bóng gốc của
//     SBBannerAndShadowView bị giữ ở 0;
//   - bố cục: biểu tượng lớn (lấy biểu tượng màn hình chính của app), tiêu đề + nội dung xếp lại sau khi SpringBoard xếp;
//   - hiệu ứng: vẫn là hiệu ứng lật khối của iOS 6, nhưng mặt «ảnh chụp chỗ cũ» bị ẩn → chỉ còn tấm thẻ lật xuống.
#import "G6Banner.h"

#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "G6Device.h"
#import "G6Font.h"
#import "G6Glass.h"
#import "G6Hook.h"
#import "G6Log.h"
#import "G6Prefs.h"

static G6Backdrop *gBackdrop;
static double gBackdropTime;
static char kStyledKey, kFontsKey, kCardKey, kGlassKey, kShadowKey, kAttachKey, kIconKey, kBackdropKey;

// Thẻ của iPhone (điểm): lề hai bên, bề rộng tối đa (máy nằm ngang thì thẻ đứng giữa), cách mép trên (= dưới thanh trạng
// thái 20 điểm + 4), chiều cao; biểu tượng, các lề chữ; cỡ chữ
static const CGFloat kCardMarginX = 8, kCardMaxWidth = 380, kCardTop = 24, kCardHeight = 54;
static const CGFloat kCardIconSize = 32, kCardIconLeft = 11, kCardTextGap = 10, kCardPadRight = 14, kCardAttachInset = 10;
static const CGFloat kCardTitleSize = 14, kCardMessageSize = 13;

// Băng dạng thẻ: chỉ iPhone, khi thành phần đang bật
static BOOL G6BannerCardMode(void) {
    return g6_device_is_phone() && G6Feature(@"notifications");
}

// Băng này đã được chuẩn bị theo kiểu thẻ chưa (chốt một lần lúc chuẩn bị, cùng lúc với màu chữ)
static BOOL G6BannerIsCard(UIView *banner) {
    return [objc_getAssociatedObject(banner, &kCardKey) boolValue];
}

static id G6Ivar(id obj, const char *name) {
    Ivar iv = obj ? class_getInstanceVariable([obj class], name) : NULL;
    return iv ? object_getIvar(obj, iv) : nil;
}

static void G6BannerRestyleLabel(UILabel *label, G6FontWeight weight, BOOL dark) {
    if (![label isKindOfClass:[UILabel class]]) return;
    if (G6FontAvailable()) label.font = G6Font(weight, label.font.pointSize);
    label.textColor = dark ? [UIColor whiteColor] : [UIColor colorWithWhite:0.08 alpha:1];
    // Bóng chữ cứng của iOS 6 không hợp với kính
    label.shadowColor = nil;
    label.backgroundColor = [UIColor clearColor];
}

// Đổi phông + màu chữ TRƯỚC khi SpringBoard xếp chỗ: nó tính bề rộng nhãn theo phông đang gắn — đổi phông sau khi xếp thì
// tiêu đề bị cắt «…» (đã gặp 19/11/2026). Mỗi băng một lần.
static void G6BannerPrepare(UIView *banner) {
    if (objc_getAssociatedObject(banner, &kFontsKey) || !G6Feature(@"notifications")) return;
    UILabel *title = G6Ivar(banner, "_titleLabel");
    if (![title isKindOfClass:[UILabel class]]) return;
    BOOL dark = G6IsDark(), card = G6BannerCardMode();
    G6BannerRestyleLabel(title, G6FontSemiBold, dark);
    UILabel *message = G6Ivar(banner, "_messageLabel");
    G6BannerRestyleLabel(message, G6FontRegular, dark);
    if (card) {
        // Thẻ cao hơn băng gốc → chữ lớn hơn một nấc; nội dung nhạt hơn tiêu đề
        title.font = G6Font(G6FontSemiBold, kCardTitleSize);
        if ([message isKindOfClass:[UILabel class]]) {
            message.font = G6Font(G6FontRegular, kCardMessageSize);
            message.textColor = dark ? [UIColor colorWithWhite:1 alpha:0.86] : [UIColor colorWithWhite:0.16 alpha:1];
        }
    }
    objc_setAssociatedObject(banner, &kCardKey, @(card), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(banner, &kFontsKey, @(dark), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// Ảnh chụp màn hình làm nền của kính: chụp khi băng chưa hiện (lúc băng vừa vào cửa sổ, trước khung hình đầu). Hai băng nối
// nhau trong vòng 1 giây thì dùng chung ảnh chụp — chụp lại sẽ dính băng trước. Mỗi băng giữ ảnh của mình để dựng lại (đổi
// cỡ) không chụp dính chính nó.
static G6Backdrop *G6BannerBackdrop(UIView *banner) {
    G6Backdrop *backdrop = objc_getAssociatedObject(banner, &kBackdropKey);
    if (backdrop) return backdrop;
    double now = G6NowMs();
    if (!gBackdrop || now - gBackdropTime > 1000) {
        gBackdrop = [G6Backdrop backdropWithScreen:YES];
        gBackdropTime = now;
    }
    if (gBackdrop) objc_setAssociatedObject(banner, &kBackdropKey, gBackdrop, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return gBackdrop;
}

// Tấm kính riêng của thẻ (dưới cùng của băng) + bóng đổ quanh nó; tạo lần đầu, các lần sau trả lại
static UIImageView *G6BannerCardGlassView(UIView *banner) {
    UIImageView *glass = objc_getAssociatedObject(banner, &kGlassKey);
    if (glass) return glass;
    glass = [[UIImageView alloc] initWithFrame:banner.bounds];
    glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [banner insertSubview:glass atIndex:0];
    objc_setAssociatedObject(banner, &kGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIImageView *shadow = [[UIImageView alloc] initWithFrame:banner.bounds];
    [banner insertSubview:shadow atIndex:0];
    objc_setAssociatedObject(banner, &kShadowKey, shadow, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return glass;
}

static void G6BannerStyle(UIView *banner) {
    if (!banner.window || !G6Feature(@"notifications")) return;
    // Kính cùng chế độ sáng / tối với màu chữ đã đặt lúc chuẩn bị
    NSNumber *prepared = objc_getAssociatedObject(banner, &kFontsKey);
    if (!prepared) return;
    BOOL dark = prepared.boolValue, card = G6BannerIsCard(banner);
    UIImageView *bg = card ? G6BannerCardGlassView(banner) : G6Ivar(banner, "_backgroundImageView");
    if (![bg isKindOfClass:[UIImageView class]] || bg.bounds.size.width < 2 || bg.bounds.size.height < 2) return;
    // Băng gốc: dựng một lần. Thẻ: SpringBoard tạo băng ở cỡ gốc rồi mới đặt khung thẻ → dựng lại khi cỡ đổi.
    NSString *key = card ? NSStringFromCGSize(bg.bounds.size) : @"1";
    if ([key isEqualToString:objc_getAssociatedObject(banner, &kStyledKey)]) return;
    double now = G6NowMs();
    G6Backdrop *backdrop = G6BannerBackdrop(banner);
    UIImage *glass = G6GlassImageForView(@"banner", bg, dark, backdrop);
    if (!glass) return;
    bg.image = glass;
    if (card) {
        UIImageView *shadow = objc_getAssociatedObject(banner, &kShadowKey);
        CGFloat margin = 0;
        shadow.image = G6ShadowImage(@"banner", bg.bounds.size, dark, &margin);
        shadow.frame = CGRectInset(bg.frame, -margin, -margin);
    }
    objc_setAssociatedObject(banner, &kStyledKey, key, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    G6Log(@"băng thông báo: kính %.0f×%.0f (%@, %@ nền%@) %.1f ms", bg.bounds.size.width, bg.bounds.size.height, dark ? @"tối" : @"sáng",
          backdrop ? @"có" : @"KHÔNG", card ? @", thẻ" : @"", G6NowMs() - now);
}

// ---- iPhone: bố cục của thẻ ----

// Biểu tượng màn hình chính của app gửi thông báo (đã qua khuôn kính của G6Icons); nil nếu mục gửi không phải một app có
// biểu tượng (khi đó giữ biểu tượng nhỏ của băng gốc, phóng lên)
static UIImage *G6BannerBigIcon(UIView *banner) {
    SEL itemSel = NSSelectorFromString(@"bannerItem"), seedSel = NSSelectorFromString(@"seedBulletin"), sectionSel = NSSelectorFromString(@"sectionID");
    id item = [banner respondsToSelector:itemSel] ? ((id (*)(id, SEL))objc_msgSend)(banner, itemSel) : nil;
    id bulletin = [item respondsToSelector:seedSel] ? ((id (*)(id, SEL))objc_msgSend)(item, seedSel) : nil;
    NSString *section = [bulletin respondsToSelector:sectionSel] ? ((id (*)(id, SEL))objc_msgSend)(bulletin, sectionSel) : nil;
    if (![section isKindOfClass:[NSString class]] || !section.length) return nil;
    Class cls = objc_getClass("SBIconController");
    SEL shared = NSSelectorFromString(@"sharedInstance"), modelSel = NSSelectorFromString(@"model");
    SEL find = NSSelectorFromString(@"leafIconForIdentifier:"), get = NSSelectorFromString(@"getIconImage:");
    id controller = [cls respondsToSelector:shared] ? ((id (*)(id, SEL))objc_msgSend)(cls, shared) : nil;
    id model = [controller respondsToSelector:modelSel] ? ((id (*)(id, SEL))objc_msgSend)(controller, modelSel) : nil;
    id icon = [model respondsToSelector:find] ? ((id (*)(id, SEL, id))objc_msgSend)(model, find, section) : nil;
    // Định dạng 2 = biểu tượng của màn hình chính
    id image = [icon respondsToSelector:get] ? ((id (*)(id, SEL, int))objc_msgSend)(icon, get, 2) : nil;
    return [image isKindOfClass:[UIImage class]] ? image : nil;
}

// Hình đính kèm (vd ảnh của tin nhắn): băng gốc vẽ nó vào ảnh nền — nền gốc đã ẩn nên thẻ tự hiện ở mép phải
static UIImageView *G6BannerAttachment(UIView *banner) {
    UIImageView *view = objc_getAssociatedObject(banner, &kAttachKey);
    if (view) return view.image ? view : nil;
    SEL itemSel = NSSelectorFromString(@"bannerItem"), attachSel = NSSelectorFromString(@"attachmentImage");
    id item = [banner respondsToSelector:itemSel] ? ((id (*)(id, SEL))objc_msgSend)(banner, itemSel) : nil;
    id image = [item respondsToSelector:attachSel] ? ((id (*)(id, SEL))objc_msgSend)(item, attachSel) : nil;
    view = [[UIImageView alloc] initWithFrame:CGRectZero];
    view.contentMode = UIViewContentModeScaleAspectFill;
    view.layer.cornerRadius = 8;
    view.layer.masksToBounds = YES;
    if ([image isKindOfClass:[UIImage class]]) view.image = image;
    view.hidden = !view.image;
    [banner addSubview:view];
    objc_setAssociatedObject(banner, &kAttachKey, view, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return view.image ? view : nil;
}

static void G6BannerPlace(UIView *banner, UIView *view, CGRect rect) {
    if (![view isKindOfClass:[UIView class]] || !view.superview) return;
    view.frame = [banner convertRect:rect toView:view.superview];
}

static void G6BannerCardLayout(UIView *banner) {
    if (!G6BannerIsCard(banner)) return;
    CGSize size = banner.bounds.size;
    if (size.width < 60 || size.height < 30) return;
    UIImageView *glass = G6BannerCardGlassView(banner);
    UIView *shadow = objc_getAssociatedObject(banner, &kShadowKey);
    UIView *content = G6Ivar(banner, "_contentContainerView");
    UIImageView *attach = G6BannerAttachment(banner);
    // Nền gốc (ảnh bóng trong phần nội dung, lớp nền bo góc + dải sáng của lớp cha) không còn dùng
    UIView *stockBg = G6Ivar(banner, "_backgroundImageView");
    if ([stockBg isKindOfClass:[UIView class]]) stockBg.hidden = YES;
    for (UIView *sub in banner.subviews) {
        if (sub != glass && sub != shadow && sub != content && sub != objc_getAssociatedObject(banner, &kAttachKey)) sub.hidden = YES;
    }

    // Biểu tượng: ô vuông bên trái, giữa chiều cao
    CGFloat iconSize = MIN(kCardIconSize, size.height - 12);
    UIImageView *icon = G6Ivar(banner, "_iconView");
    G6BannerPlace(banner, icon, CGRectMake(kCardIconLeft, round((size.height - iconSize) / 2), iconSize, iconSize));
    if ([icon isKindOfClass:[UIImageView class]] && !objc_getAssociatedObject(banner, &kIconKey)) {
        objc_setAssociatedObject(banner, &kIconKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        icon.contentMode = UIViewContentModeScaleAspectFit;
        UIImage *big = G6BannerBigIcon(banner);
        if (big) icon.image = big;
    }

    // Hình đính kèm ở mép phải
    CGFloat right = size.width - kCardPadRight;
    if (attach) {
        CGFloat side = size.height - 2 * kCardAttachInset;
        attach.frame = CGRectMake(size.width - kCardAttachInset - side, kCardAttachInset, side, side);
        right = CGRectGetMinX(attach.frame) - 8;
    }

    // Chữ: tiêu đề + nội dung thành một khối đứng giữa chiều cao thẻ
    UILabel *title = G6Ivar(banner, "_titleLabel"), *message = G6Ivar(banner, "_messageLabel");
    UIView *accessory = G6Ivar(banner, "_accessoryImageView");
    if (![title isKindOfClass:[UILabel class]]) return;
    BOOL hasMessage = [message isKindOfClass:[UILabel class]] && message.text.length && !message.hidden;
    BOOL hasAccessory = [accessory isKindOfClass:[UIView class]] && !accessory.hidden && accessory.superview;
    CGFloat left = kCardIconLeft + iconSize + kCardTextGap;
    CGFloat titleH = ceil(title.font.lineHeight), messageH = hasMessage ? ceil(message.font.lineHeight) : 0;
    CGFloat gap = hasMessage && size.height >= 50 ? 1 : 0;
    CGFloat top = floor((size.height - titleH - gap - messageH) / 2);
    CGFloat accessoryRoom = hasAccessory ? accessory.bounds.size.width + 4 : 0;
    CGFloat titleW = MIN(ceil([title.text sizeWithFont:title.font].width), right - left - accessoryRoom);
    if (titleW < 10) titleW = MAX(right - left - accessoryRoom, 10);
    G6BannerPlace(banner, title, CGRectMake(left, top, titleW, titleH));
    if (hasAccessory) {
        CGSize a = accessory.bounds.size;
        G6BannerPlace(banner, accessory, CGRectMake(left + titleW + 4, top + round((titleH - a.height) / 2), a.width, a.height));
    }
    if (hasMessage) G6BannerPlace(banner, message, CGRectMake(left, top + titleH + gap, right - left, messageH));
}

// SpringBoard chừa bề rộng tiêu đề theo phông gốc (không theo phông đang gắn) → với Inter tiêu đề bị cắt «…» dù còn chỗ.
// Sau mỗi lần nó xếp: nới tiêu đề cho vừa chữ (không lấn mép phải của băng) và đẩy hình phụ đứng sau tiêu đề sang phải theo.
static void G6BannerFitTitle(UIView *banner) {
    if (!objc_getAssociatedObject(banner, &kFontsKey)) return;
    // Thẻ của iPhone tự xếp cả khối chữ
    if (G6BannerIsCard(banner)) {
        G6BannerCardLayout(banner);
        return;
    }
    UILabel *title = G6Ivar(banner, "_titleLabel");
    UIView *accessory = G6Ivar(banner, "_accessoryImageView");
    if (![title isKindOfClass:[UILabel class]] || !title.text.length || !title.superview) return;
    BOOL hasAccessory = [accessory isKindOfClass:[UIView class]] && !accessory.hidden && accessory.superview == title.superview &&
                        CGRectGetMinX(accessory.frame) >= CGRectGetMaxX(title.frame) - 1;
    CGRect f = title.frame;
    CGFloat right = title.superview.bounds.size.width - 12 - (hasAccessory ? accessory.frame.size.width + 6 : 0);
    CGFloat need = MIN(ceil([title.text sizeWithFont:title.font].width), right - f.origin.x);
    if (need <= f.size.width + 0.5) return;
    CGFloat delta = need - f.size.width;
    f.size.width = need;
    title.frame = f;
    if (hasAccessory) {
        CGRect a = accessory.frame;
        a.origin.x += delta;
        accessory.frame = a;
    }
}

static void G6BannerStyleSafe(UIView *banner) {
    @try {
        G6BannerStyle(banner);
    } @catch (NSException *e) {
        G6Log(@"băng thông báo: lỗi khi dựng: %@", e);
    }
}

static void (*o_layoutSubviews)(id, SEL);
static void g6_layoutSubviews(UIView *self, SEL _cmd) {
    @try {
        G6BannerPrepare(self);
    } @catch (NSException *e) {
    }
    o_layoutSubviews(self, _cmd);
    @try {
        G6BannerFitTitle(self);
    } @catch (NSException *e) {
    }
    G6BannerStyleSafe(self);
}

static void (*o_didMoveToWindow)(id, SEL);
static void g6_didMoveToWindow(UIView *self, SEL _cmd) {
    o_didMoveToWindow(self, _cmd);
    if (!self.window) return;
    // Xếp view con ngay để biết khung của ảnh nền rồi dựng kính trước khung hình đầu
    [self layoutIfNeeded];
    G6BannerStyleSafe(self);
}

// ---- iPhone: khung thẻ, bóng gốc, mặt «ảnh chụp chỗ cũ» của hiệu ứng lật ----

static CGRect (*o_normalFrame)(id, SEL, int);
static CGRect g6_normalFrame(id self, SEL _cmd, int orientation) {
    CGRect f = o_normalFrame(self, _cmd, orientation);
    if (!G6BannerCardMode() || f.size.width < 2 * kCardMarginX + 60) return f;
    CGFloat w = MIN(f.size.width - 2 * kCardMarginX, kCardMaxWidth);
    return CGRectMake(round(f.origin.x + (f.size.width - w) / 2), f.origin.y + kCardTop, w, kCardHeight);
}

// Hiệu ứng lật của iOS 6: một «khối hộp» quay, mặt đang hiện là ảnh chụp vùng màn hình mà băng sắp che, mặt kế là băng. Thẻ
// trong suốt quanh bốn góc nên mặt ảnh chụp (một hình chữ nhật) lộ ra khi quay → ẩn nó, chỉ còn tấm thẻ lật xuống.
static CGRect (*o_flipRect)(id, SEL, CGRect, int);
static CGRect g6_flipRect(id self, SEL _cmd, CGRect frame, int orientation) {
    CGRect r = o_flipRect(self, _cmd, frame, orientation);
    @try {
        if (G6BannerCardMode()) {
            UIView *snapshot = G6Ivar(self, "_snapshotView");
            if ([snapshot isKindOfClass:[UIView class]]) snapshot.hidden = YES;
        }
    } @catch (NSException *e) {
    }
    return r;
}

// Bóng đổ gốc (dải bóng dưới băng) không hợp với thẻ đã có bóng riêng
static void (*o_setShadowAlpha)(id, SEL, float);
static void g6_setShadowAlpha(id self, SEL _cmd, float alpha) {
    o_setShadowAlpha(self, _cmd, G6BannerCardMode() ? 0 : alpha);
}

// ---- iPhone: hiệu ứng trượt thay cho hiệu ứng lật ----
// iOS 6 (tra trên máy 20/11/2026): lúc hiện / cất băng, SBBannerController bật SBSpringBoardMetaHostingWindow (mức 2300) —
// cửa sổ này hiện lại TOÀN BỘ màn hình của SpringBoard qua một lưới biến dạng (CAMeshTransform) rồi chạy hoạt hình khoá
// «bẻ» vùng của băng thành một khối hộp quay: -_meshTransformForDegreesOfRotation:… được gọi với 0°, 45°, 90° (0° = mặt
// «ảnh chụp chỗ cũ» quay ra trước, 90° = băng nằm phẳng đúng chỗ). Thẻ trong suốt quanh bốn góc nên khối hộp lộ nguyên một
// hình chữ nhật đen khi quay. Cách làm: mọi khoá hình đều lấy lưới của 90° (màn hình đứng yên, băng nằm đúng chỗ) rồi tự
// cho thẻ trượt từ mép trên xuống / trượt ngược lên bằng hoạt hình thường trên lớp của SBBannerAndShadowView. Các bước còn
// lại của SpringBoard (hẹn giờ cất băng, dọn view khi hoạt hình gốc xong) giữ nguyên.
static const CFTimeInterval kCardShowSeconds = 0.46, kCardHideSeconds = 0.26;

static id (*o_mesh)(id, SEL, float, UIEdgeInsets, int, BOOL);
static id g6_mesh(id self, SEL _cmd, float degrees, UIEdgeInsets insets, int orientation, BOOL topIsLive) {
    return o_mesh(self, _cmd, G6BannerCardMode() ? 90.0f : degrees, insets, orientation, topIsLive);
}

static void G6BannerSlide(id context) {
    SEL fromSel = NSSelectorFromString(@"fromView"), toSel = NSSelectorFromString(@"toView");
    if (![context respondsToSelector:fromSel] || ![context respondsToSelector:toSel]) return;
    UIView *from = ((id (*)(id, SEL))objc_msgSend)(context, fromSel), *to = ((id (*)(id, SEL))objc_msgSend)(context, toSel);
    // Băng này thay băng kia (cả hai cùng có): không trượt
    if ((from != nil) == (to != nil)) return;
    UIView *banner = to ?: from;
    UIView *holder = banner.superview;
    if (![banner isKindOfClass:[UIView class]] || !holder) return;
    CGFloat distance = CGRectGetMaxY(holder.frame) + 20;
    CABasicAnimation *move = [CABasicAnimation animationWithKeyPath:@"transform.translation.y"];
    CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
    if (to) {
        // Hiện: trượt xuống, quá đà một chút rồi về chỗ
        move.fromValue = @(-distance);
        move.toValue = @0;
        move.duration = kCardShowSeconds;
        move.timingFunction = [CAMediaTimingFunction functionWithControlPoints:0.22:1.16:0.36:1.0];
        fade.fromValue = @0;
        fade.toValue = @1;
        fade.duration = kCardShowSeconds * 0.4;
    } else {
        // Cất: trượt lên rồi giữ nguyên ở ngoài màn hình tới khi SpringBoard dọn view
        move.fromValue = @0;
        move.toValue = @(-distance);
        move.duration = kCardHideSeconds;
        move.timingFunction = [CAMediaTimingFunction functionWithControlPoints:0.5:0.0:0.9:0.6];
        fade.fromValue = @1;
        fade.toValue = @0;
        fade.duration = kCardHideSeconds;
        fade.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];
        for (CABasicAnimation *a in @[move, fade]) {
            a.fillMode = kCAFillModeForwards;
            a.removedOnCompletion = NO;
        }
    }
    [holder.layer addAnimation:move forKey:@"g6Slide"];
    [holder.layer addAnimation:fade forKey:@"g6Fade"];
}

static void (*o_flip)(id, SEL, id);
static void g6_flip(id self, SEL _cmd, id context) {
    o_flip(self, _cmd, context);
    @try {
        if (G6BannerCardMode()) G6BannerSlide(context);
    } @catch (NSException *e) {
        G6Log(@"băng thông báo: lỗi khi trượt thẻ: %@", e);
    }
}
#if G6_DEBUG
static void (*o_animStop)(id, SEL, CAAnimation *, BOOL);
static void g6_animStop(id self, SEL _cmd, CAAnimation *anim, BOOL finished) {
    G6Log(@"[lat] animationDidStop finished=%d dai=%.2f", finished, anim.duration);
    o_animStop(self, _cmd, anim, finished);
}
#endif

void G6BannerInstall(void) {
    Class banner = objc_getClass("SBBulletinBannerView");
    if (!banner || !class_getInstanceVariable(banner, "_backgroundImageView")) {
        G6Log(@"băng thông báo: thiếu SBBulletinBannerView / _backgroundImageView — bỏ qua");
        return;
    }
    if (!G6Hook(banner, @selector(layoutSubviews), (IMP)g6_layoutSubviews, (IMP *)&o_layoutSubviews)) return;
    G6Hook(banner, @selector(didMoveToWindow), (IMP)g6_didMoveToWindow, (IMP *)&o_didMoveToWindow);
    if (g6_device_is_phone()) {
        Class controller = objc_getClass("SBBannerController"), holder = objc_getClass("SBBannerAndShadowView");
        if (!G6Hook(controller, NSSelectorFromString(@"_normalBannerFrameForOrientation:"), (IMP)g6_normalFrame, (IMP *)&o_normalFrame)) {
            G6Log(@"băng thông báo: thiếu -[SBBannerController _normalBannerFrameForOrientation:] — thẻ giữ khung gốc");
        }
        if (controller && class_getInstanceVariable(controller, "_snapshotView")) {
            G6Hook(controller, NSSelectorFromString(@"_calculateFlipRectAndCreateSnapshotViewForBannerFrame:orientation:"), (IMP)g6_flipRect,
                   (IMP *)&o_flipRect);
        }
        G6Hook(holder, NSSelectorFromString(@"setShadowAlpha:"), (IMP)g6_setShadowAlpha, (IMP *)&o_setShadowAlpha);
        // Hiệu ứng trượt: cần cả hai hàm, thiếu một thì giữ hiệu ứng lật gốc
        SEL meshSel = NSSelectorFromString(@"_meshTransformForDegreesOfRotation:flipInsets:orientation:topIsLive:");
        SEL flipSel = NSSelectorFromString(@"_flipWithContext:");
        if (controller && class_getInstanceMethod(controller, meshSel) && class_getInstanceMethod(controller, flipSel) &&
            objc_getClass("SBBannerTransitionContext")) {
            G6Hook(controller, meshSel, (IMP)g6_mesh, (IMP *)&o_mesh);
            G6Hook(controller, flipSel, (IMP)g6_flip, (IMP *)&o_flip);
        }
#if G6_DEBUG
        G6Hook(controller, NSSelectorFromString(@"animationDidStop:finished:"), (IMP)g6_animStop, (IMP *)&o_animStop);
#endif
    }
}

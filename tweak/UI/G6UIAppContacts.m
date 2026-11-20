// App Danh bạ (com.apple.MobileAddressBook) trên iPad — bỏ «cuốn sổ địa chỉ».
//
// Bố cục iOS 6 (tra 19/11/2026 bằng `imglog` + cây view đã bỏ chữ; máy ngang):
//   ABBookCoverView 1024×748       bìa sổ: mép «BookTopEdge / BookBottomEdge / BookLeftEdge / BookRightEdge», gáy
//                                  «BookTopSpine / BookBottomSpine», bóng giấy «BookPagesShadow»
//     ABPageView ×2                hai trang: ảnh «LeftPage_/RightPage_<hướng>_noStitching», đường khâu «…_stitching»
//       trái: tiêu đề nhóm, ô tìm kiếm («searchFieldStretchableImage»), danh sách tên, dải chữ cái («index_well»),
//             nút «+» («bottom_button» + «plus_button»)
//       phải: ABPersonContainerView — ABPersonImageView (ảnh chân dung), tên, các dòng thông tin; nút «Sửa»
//             («darkerStretchableButton»)
// Chữ trong app vốn tối trên giấy sáng → cả app là vùng sáng bình thường.
//
// Vẽ lại: mép bìa thành màu nền, hai trang trắng, bỏ gáy / đường khâu / bóng, nút bo tròn. Ảnh chân dung giữ đúng màu ở chế
// độ tối (đảo ngược bộ lọc của cửa sổ riêng cho view đó).
#import "G6UI.h"

#import <objc/message.h>
#import <objc/runtime.h>

#import "G6Hook.h"
#import "G6Log.h"

void G6UIAppContactsPrepare(void) {
    NSMutableDictionary *images = [@{
        @"BookTopEdge" : @(G6SkinBackdrop),
        @"BookBottomEdge" : @(G6SkinBackdrop),
        @"BookLeftEdge" : @(G6SkinBackdrop),
        @"BookRightEdge" : @(G6SkinBackdrop),
        @"BookTopSpine" : @(G6SkinClear),
        @"BookBottomSpine" : @(G6SkinClear),
        @"BookPagesShadow" : @(G6SkinClear),
        @"LeftPage_stitching" : @(G6SkinClear),
        @"RightPage_stitching" : @(G6SkinClear),
        @"RibbonBack" : @(G6SkinClear),
        @"RibbonFront" : @(G6SkinClear),
        @"index_well" : @(G6SkinClear),
        @"table_frame" : @(G6SkinClear),
        @"toolbar_cutline" : @(G6SkinClear),
        @"MembersTableDividerLine" : @(G6SkinHairline),
        @"header" : @(G6SkinHighlight),
        @"searchFieldStretchableImage" : @(G6SkinField),
        @"darkerStretchableButton" : @(G6SkinButton),
        @"bottom_button" : @(G6SkinButton),
        @"bottom_button_depressed" : @(G6SkinButtonDown),
        @"plus_button" : @(G6SkinGlyph),
        @"UIButtonBarRefreshLandscapeGray" : @(G6SkinGlyph),
    } mutableCopy];
    for (NSString *side in @[@"LeftPage", @"RightPage"]) {
        for (NSString *o in @[@"landscape", @"portrait"]) images[[NSString stringWithFormat:@"%@_%@_noStitching", side, o]] = @(G6SkinSurface);
    }
    G6UISkinRegister(images);
}

static BOOL gActive;
static char kCoverColorKey;

// Ảnh chân dung: có ảnh thật (-hasImageToDisplay) thì view ảnh (_personImageView) giữ đúng màu dưới bộ lọc tối; đang hiện
// hình bóng mặc định thì để nó tối theo như mọi thứ khác (bản đầu giữ màu cả ô → ô hình bóng sáng chói ở chế độ tối).
static void G6ContactsStylePhoto(UIView *photo) {
    SEL has = NSSelectorFromString(@"hasImageToDisplay");
    BOOL real = [photo respondsToSelector:has] && ((BOOL (*)(id, SEL))objc_msgSend)(photo, has);
    Ivar iv = class_getInstanceVariable([photo class], "_personImageView");
    id imageView = iv ? object_getIvar(photo, iv) : nil;
    if ([imageView isKindOfClass:[UIView class]]) G6UISkinKeepColors(imageView, real);
}

static void (*orig_photoLayout)(UIView *, SEL);
static void repl_photoLayout(UIView *self, SEL _cmd) {
    orig_photoLayout(self, _cmd);
    @try {
        G6ContactsStylePhoto(self);
    } @catch (NSException *e) {
    }
}

// Bìa sổ: các mảnh mép không phủ kín (còn hở vài điểm ở mép dưới) → tô luôn nền của view bìa bằng màu nền chung
static void G6ContactsStyleBackground(UIView *view) {
    UIColor *saved = objc_getAssociatedObject(view, &kCoverColorKey);
    if (gActive && !saved) {
        objc_setAssociatedObject(view, &kCoverColorKey, view.backgroundColor ?: [UIColor clearColor], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        view.backgroundColor = G6UISkinBackdropColor();
    } else if (!gActive && saved) {
        view.backgroundColor = saved;
        objc_setAssociatedObject(view, &kCoverColorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

// Bìa sổ và mọi thứ nằm sau nó (view gốc, cửa sổ): máy đứng thì cuốn sổ không phủ kín màn hình — hai dải trên / dưới lộ nền
// đen của view gốc (đã gặp: dải đen ở chế độ sáng, thành dải trắng ở chế độ tối)
static void G6ContactsStyleCover(UIView *cover) {
    for (UIView *v = cover; v; v = v.superview) G6ContactsStyleBackground(v);
}

static void (*orig_coverDidMove)(UIView *, SEL);
static void repl_coverDidMove(UIView *self, SEL _cmd) {
    orig_coverDidMove(self, _cmd);
    @try {
        G6ContactsStyleCover(self);
    } @catch (NSException *e) {
    }
}

static void G6ContactsRefresh(UIView *view, Class cover, int depth) {
    if (cover && [view isKindOfClass:cover]) G6ContactsStyleCover(view);
    if (depth <= 0) return;
    for (UIView *sub in view.subviews) G6ContactsRefresh(sub, cover, depth - 1);
}

void G6UIAppContactsApply(BOOL active) {
    Class cover = objc_getClass("ABBookCoverView");
    if (!orig_photoLayout && !orig_coverDidMove) {
        if (!active) return;
        G6HookNamed("ABPersonImageView", @selector(layoutSubviews), (IMP)repl_photoLayout, (IMP *)&orig_photoLayout);
        if (cover) G6Hook(cover, @selector(didMoveToWindow), (IMP)repl_coverDidMove, (IMP *)&orig_coverDidMove);
        G6Log(@"danh bạ (app): vẽ lại");
    }
    gActive = active;
    for (UIWindow *window in [UIApplication sharedApplication].windows) G6ContactsRefresh(window, cover, 4);
}

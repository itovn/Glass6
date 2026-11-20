// App Ghi chú (com.apple.mobilenotes) trên iPad — bỏ da, giấy vàng, đường khâu.
//
// Bố cục iOS 6 (máy ngang; tra 19/11/2026 bằng `imglog` + cây view đã bỏ chữ):
//   UIImageView 1024×748          «back LS»      nền da đen
//   trái:  UIImageView 336×737    «index LS»     thẻ giấy có đường khâu, chứa thanh tiêu đề + ô tìm kiếm + danh sách
//          NotesPouchView         «pouch LS»     túi da góc dưới
//   phải:  thanh điều hướng       «LStop bar»    thanh da nâu, nút «header button»
//          NotesBackgroundView    «LSbodyMarginThin» giấy vàng có lề đỏ; «LSedgeTop» mép giấy rách; «LSgradBottom…» dải mờ
//            NotesRuleView        dòng kẻ ngang (app tự vẽ)
//            NoteTextView         nội dung ghi chú
//          NoteNavigationView     mũi tên qua lại, chia sẻ, thùng rác (hình nâu)
//   dòng đang chọn trong danh sách: chuỗi ảnh «selectionA-B» (vòng tròn đỏ vẽ tay, chạy thành hoạt hình)
// Máy đứng dùng các hình cùng tên không có «LS».
//
// Vẽ lại: nền một màu, thẻ danh sách trắng bo góc, trang trắng không dòng kẻ, thanh phẳng, nút bo tròn, dòng đang chọn là
// viên mờ. Phần tối do bộ lọc của khung chung lo (G6UISkin.m) — KHÔNG đổi màu chữ của trang ghi chú.
#import "G6UI.h"

#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

#import "G6Hook.h"
#import "G6Log.h"

static BOOL gActive;
static char kRuleHiddenKey, kListBorderKey;

void G6UIAppNotesPrepare(void) {
    NSMutableDictionary *images = [@{
        @"back LS" : @(G6SkinBackdrop),
        @"pouch LS" : @(G6SkinClear),
        @"index LS" : @[@(G6SkinCard), @6, @10],
        @"top bar" : @(G6SkinBar),
        @"LStop bar" : @(G6SkinBar),
        @"bodyMarginThin" : @(G6SkinSurface),
        @"LSbodyMarginThin" : @(G6SkinSurface),
        @"edgeTop" : @(G6SkinClear),
        @"LSedgeTop" : @(G6SkinClear),
        @"gradBottomMarginThin" : @(G6SkinClear),
        @"LSgradBottomMarginThin" : @(G6SkinClear),
        @"header button" : @(G6SkinButton),
        @"header button pressed" : @(G6SkinButtonDown),
        @"header back" : @(G6SkinButton),
        @"header back pressed" : @(G6SkinButtonDown),
        @"sidebar header back" : @(G6SkinButton),
        @"sidebar header back pressed" : @(G6SkinButtonDown),
        @"searchFieldStretchableImage" : @(G6SkinField),
        @"arrow left" : @(G6SkinGlyph),
        @"arrow right" : @(G6SkinGlyph),
        @"action" : @(G6SkinGlyph),
        @"trash" : @(G6SkinGlyph),
        @"trash can" : @(G6SkinGlyph),
        @"trash lid" : @(G6SkinGlyph),
        @"arrow pressed" : @(G6SkinPressed),
        // iPhone (tra bằng imglog 20/11/2026): trang giấy vàng «body» (danh sách lẫn trang ghi chú), mép giấy dưới, nền ô tìm
        // kiếm, mũi tên của dòng
        @"body" : @(G6SkinSurface),
        @"edgeBottom" : @(G6SkinClear),
        @"SearchBar" : @(G6SkinBar),
        @"list arrow" : @(G6SkinGlyph),
    } mutableCopy];
    // Vòng tròn vẽ tay quanh dòng đang chọn: ba kiểu, mỗi kiểu 10–11 khung hình → cùng một viên mờ (hết hoạt hình)
    for (int style = 1; style <= 3; style++) {
        for (int frame = 1; frame <= 11; frame++) images[[NSString stringWithFormat:@"selection%d-%d", style, frame]] = @(G6SkinSelection);
    }
    G6UISkinRegister(images);
}

// Dòng kẻ ngang của trang: app tự vẽ trong NotesRuleView → ẩn view đó
static void G6NotesStyleRule(UIView *rule) {
    BOOL mine = objc_getAssociatedObject(rule, &kRuleHiddenKey) != nil;
    if (gActive && !rule.hidden) {
        rule.hidden = YES;
        objc_setAssociatedObject(rule, &kRuleHiddenKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else if (!gActive && mine) {
        rule.hidden = NO;
        objc_setAssociatedObject(rule, &kRuleHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void (*orig_ruleDidMove)(UIView *, SEL);
static void repl_ruleDidMove(UIView *self, SEL _cmd) {
    orig_ruleDidMove(self, _cmd);
    @try {
        G6NotesStyleRule(self);
    } @catch (NSException *e) {
    }
}

// Danh sách ghi chú: app kẻ một khung viền quanh bảng (viền của lớp vẽ) cho giống ô kẻ trên thẻ giấy → bỏ viền
static void G6NotesStyleList(UIView *list) {
    NSNumber *saved = objc_getAssociatedObject(list, &kListBorderKey);
    if (gActive && !saved && list.layer.borderWidth > 0) {
        objc_setAssociatedObject(list, &kListBorderKey, @(list.layer.borderWidth), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        list.layer.borderWidth = 0;
    } else if (!gActive && saved) {
        list.layer.borderWidth = saved.floatValue;
        objc_setAssociatedObject(list, &kListBorderKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void (*orig_listDidMove)(UIView *, SEL);
static void repl_listDidMove(UIView *self, SEL _cmd) {
    orig_listDidMove(self, _cmd);
    @try {
        G6NotesStyleList(self);
    } @catch (NSException *e) {
    }
}

static void G6NotesRefresh(UIView *view, Class ruleClass, int depth) {
    if ([view isKindOfClass:ruleClass]) {
        G6NotesStyleRule(view);
        return;
    }
    Class listClass = objc_getClass("NotesListTableView");
    if (listClass && [view isKindOfClass:listClass]) G6NotesStyleList(view);
    if (depth <= 0) return;
    for (UIView *sub in view.subviews) G6NotesRefresh(sub, ruleClass, depth - 1);
}

void G6UIAppNotesApply(BOOL active) {
    Class ruleClass = objc_getClass("NotesRuleView");
    if (!ruleClass) return;
    if (!orig_ruleDidMove) {
        if (!active) return;
        if (!G6Hook(ruleClass, @selector(didMoveToWindow), (IMP)repl_ruleDidMove, (IMP *)&orig_ruleDidMove)) return;
        G6HookNamed("NotesListTableView", @selector(didMoveToWindow), (IMP)repl_listDidMove, (IMP *)&orig_listDidMove);
        G6Log(@"ghi chú (app): vẽ lại");
    }
    gActive = active;
    for (UIWindow *window in [UIApplication sharedApplication].windows) G6NotesRefresh(window, ruleClass, 16);
}

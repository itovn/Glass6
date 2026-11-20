// App Lịch trên iPhone — lịch tháng dạng lưới (CalendarMonthControl) và dải tên ngày của màn Ngày (EKDayBannerView):
// kiểu iOS 26 + âm lịch Việt Nam.
//
// Cấu trúc iOS 6 (tra 20/11/2026 trên iPhone 5 bằng `methods` / `inspect` / cây view đã bỏ chữ):
//   EKLayoutContainerView (0 64; 320 460)
//     CalendarMonthControl (0 64; 320 309)   UIControl, KHÔNG có layoutSubviews — dựng hết trong initWithFrame / setFrame /
//                                            _setDisplayedMonth:animating:force:
//       _bannerBkgnd   UIImageView 320×44    nền dải đầu lịch (vân xám)
//       _leftArrow / _rightArrow             CalendarArrowButton 13×16 (UIButton có hình)
//       _nameView      CalendarGradientLabel tên tháng (UILabel, chữ tô bằng màu vân + bóng)
//       _headingsView  CalendarMonthDayHeadingsView 320×13 — 7 CalendarGradientLabel (_titles) «Th 2 … CN»
//       _tilesClipView UIImageView 320×265   khung lưới; bên trong _tilesView chứa 35 / 42 CalendarMonthDayTile + một vạch đáy
//     UIImageView (0 373; 320 7)             bóng đổ dưới lịch
//     UITableView (0 373; 320 151)           sự kiện của ngày đang chọn
//   CalendarMonthDayTile 47×45, đặt chồng 1 điểm lên ô bên cạnh (x = −1 + 46·cột, y = 44·hàng). Tự vẽ hết trong drawRect:
//   (nền gradient, viền, số, dấu sự kiện). Biến: _day (số ngày), _state, _marked (có sự kiện). _state đo bằng cú chạm giả:
//   1 = ngày thường, 2 = hôm nay, 3 = hôm nay đang chọn, 4 = đang chọn, 5 = ngày của tháng trước / sau (mờ).
//   Ô không biết tháng của nó: hỏi lịch bằng -[CalendarMonthControl _dateForTile:] (trả CFGregorianDate).
//   Lịch giữ HAI bộ ô (_tiles[2], _disabledTiles[2], _currentSet) để trượt từ tháng này sang tháng kia; ô của một số ngày được
//   dùng lại qua các tháng (ô «ngày 5» vẫn là «ngày 5») nên app KHÔNG vẽ lại ô khi đổi tháng nếu trạng thái không đổi.
//
// Việc làm (thành phần «app_skins»; âm lịch theo công tắc riêng «lunar»):
//   - Ô ngày vẽ lại hoàn toàn: nền trắng, vạch mảnh giữa các tuần, số ngày dương ở giữa; hôm nay chữ đỏ, ngày đang chọn đĩa
//     tròn đen (hôm nay: đĩa đỏ); cuối tuần chữ xám; có sự kiện: chấm xám nhỏ. Âm lịch: số ngày âm nhỏ dưới số dương (mùng 1 và
//     ngày 1 dương kèm tháng «1/10», tháng nhuận «N»), ngày hoàng đạo chữ vàng cam; mùng 1, rằm và ngày lễ âm lịch chữ đỏ.
//   - Mỗi lần đổi tháng: gắn ngày cho từng ô của bộ ô MỚI rồi bắt vẽ lại (bộ ô cũ đang trượt đi giữ ngày cũ).
//   - Đầu lịch: nền trắng, tên tháng đậm tối (viết hoa chữ đầu), tên thứ chữ xám nhỏ, mũi tên kiểu «‹ ›» màu đỏ; bỏ bóng đổ.
//   - Màn Ngày: tên ngày «Thứ Ba, 1 tháng 12, 2026» + dòng âm lịch nhỏ bên dưới; nền dải phẳng, mũi tên đỏ.
//   - Thẻ âm lịch của ngày đang chọn nằm ở đầu bảng sự kiện (tableHeaderView): ngày tháng năm âm, can chi ngày / tháng, tiết
//     khí, hoàng đạo / hắc đạo (tên thần), giờ hoàng đạo, lễ.
// Mọi thứ vẽ theo bảng màu SÁNG; chế độ tối do bộ lọc đảo của cửa sổ lo (G6UISkin.h) — riêng số trong đĩa tròn phải biết đang
// bị đảo để vẫn ra chữ trắng. Tắt công tắc thì trả lại hình / màu / chữ gốc đã nhớ.
#import "G6UI.h"

#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "G6Font.h"
#import "G6Hook.h"
#import "G6Log.h"
#import "G6UICalendarLunar.h"

void G6UIAppCalendarPhoneApply(BOOL active, BOOL lunar);

static BOOL gActive, gLunar;
static char kTileDateKey, kSavedKey, kLabelSavedKey, kCardKey;

// Cùng bố cục với CFGregorianDate (SInt32 year; SInt8 month, day, hour, minute; double second)
typedef struct {
    int32_t year;
    int8_t month, day, hour, minute;
    double second;
} G6CalDate;

// ---- Đọc biến của app ----

static id G6CalIvar(id obj, const char *name) {
    Ivar iv = class_getInstanceVariable(object_getClass(obj), name);
    const char *type = iv ? ivar_getTypeEncoding(iv) : NULL;
    return (type && type[0] == '@') ? object_getIvar(obj, iv) : nil;
}

static int G6CalInt(id obj, const char *sel) {
    SEL s = sel_registerName(sel);
    return [obj respondsToSelector:s] ? ((int (*)(id, SEL))objc_msgSend)(obj, s) : 0;
}

static UIView *G6CalControlOf(UIView *tile) {
    Class cls = objc_getClass("CalendarMonthControl");
    for (UIView *v = tile.superview; v; v = v.superview) {
        if ([v isKindOfClass:cls]) return v;
    }
    return nil;
}

// Tháng lịch đang hiện (biến _month — đã là tháng MỚI ngay khi app bắt đầu dựng bộ ô mới)
static BOOL G6CalShownMonth(UIView *control, int *m, int *y) {
    Ivar iv = class_getInstanceVariable(object_getClass(control), "_month");
    if (!iv) return NO;
    const G6CalDate *g = (const G6CalDate *)((const uint8_t *)(__bridge void *)control + ivar_getOffset(iv));
    if (g->month < 1 || g->month > 12 || g->year < 1 || g->year > 9999) return NO;
    *m = g->month;
    *y = g->year;
    return YES;
}

// Ngày của một ô theo tháng đang hiện: hỏi app (_dateForTile:), lệch số ngày thì tự tính (ô mờ ở hàng đầu thuộc tháng trước,
// ở hàng sau thuộc tháng sau).
static BOOL G6CalComputeTileDate(UIView *control, UIView *tile, int day, int state, int *d, int *m, int *y) {
    SEL sel = sel_registerName("_dateForTile:");
    Method meth = class_getInstanceMethod(object_getClass(control), sel);
    if (meth) {
        G6CalDate (*f)(id, SEL, id) = (G6CalDate(*)(id, SEL, id))method_getImplementation(meth);
        G6CalDate g = f(control, sel, tile);
        if (g.day == day && g.month >= 1 && g.month <= 12 && g.year > 0) {
            *d = g.day;
            *m = g.month;
            *y = g.year;
            return YES;
        }
    }
    int mm, yy;
    if (!G6CalShownMonth(control, &mm, &yy)) return NO;
    if (state >= 5) {
        BOOL before = tile.frame.origin.y < 22;
        mm += before ? -1 : 1;
        if (mm < 1) mm = 12, yy--;
        if (mm > 12) mm = 1, yy++;
    }
    *d = day;
    *m = mm;
    *y = yy;
    return YES;
}

static void G6CalStoreTileDate(UIView *tile, int d, int m, int y) {
    objc_setAssociatedObject(tile, &kTileDateKey, @((y * 100 + m) * 100 + d), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// Ngày đã gắn cho ô (lúc đổi tháng hoặc lần vẽ đầu); chưa có thì tính theo tháng đang hiện rồi gắn
static BOOL G6CalTileDate(UIView *tile, int day, int state, int *d, int *m, int *y) {
    NSNumber *saved = objc_getAssociatedObject(tile, &kTileDateKey);
    if (saved) {
        int v = saved.intValue;
        if (v % 100 == day) {
            *d = v % 100;
            *m = (v / 100) % 100;
            *y = v / 10000;
            return YES;
        }
    }
    UIView *control = G6CalControlOf(tile);
    if (!control || !G6CalComputeTileDate(control, tile, day, state, d, m, y)) return NO;
    G6CalStoreTileDate(tile, *d, *m, *y);
    return YES;
}

// Các ô thuộc bộ ô ĐANG dùng của lịch (nil = không đọc được biến → coi mọi ô là của tháng hiện tại)
static NSArray *G6CalCurrentTiles(UIView *control) {
    Class cls = object_getClass(control);
    Ivar ti = class_getInstanceVariable(cls, "_tiles"), di = class_getInstanceVariable(cls, "_disabledTiles"),
         ci = class_getInstanceVariable(cls, "_currentSet");
    const char *tt = ti ? ivar_getTypeEncoding(ti) : NULL, *dt = di ? ivar_getTypeEncoding(di) : NULL;
    if (!tt || !dt || !ci || strncmp(tt, "[2@", 3) != 0 || strncmp(dt, "[2^", 3) != 0) return nil;
    uint8_t *base = (uint8_t *)(__bridge void *)control;
    // _currentSet là trường bit 1 bit đứng riêng (giữa hai biến int) → bit thấp của byte tại vị trí của nó
    int cur = base[ivar_getOffset(ci)] & 1;
    void **sets = (void **)(base + ivar_getOffset(ti));
    CFDictionaryRef *disabled = (CFDictionaryRef *)(base + ivar_getOffset(di));
    NSMutableArray *out = [NSMutableArray array];
    id tiles = (__bridge id)sets[cur];
    if ([tiles isKindOfClass:[NSArray class]]) [out addObjectsFromArray:tiles];
    CFDictionaryRef dict = disabled[cur];
    if (dict) {
        CFIndex n = CFDictionaryGetCount(dict);
        if (n > 0 && n <= 64) {
            const void *keys[64], *vals[64];
            CFDictionaryGetKeysAndValues(dict, keys, vals);
            Class tileClass = objc_getClass("CalendarMonthDayTile");
            for (CFIndex i = 0; i < n; i++) {
                id v = (__bridge id)vals[i];
                if ([v isKindOfClass:tileClass]) [out addObject:v];
            }
        }
    }
    return out;
}

static void G6CalCollectTiles(UIView *view, NSMutableArray *out, int depth) {
    static Class tileClass;
    if (!tileClass) tileClass = objc_getClass("CalendarMonthDayTile");
    if ([view isKindOfClass:tileClass]) {
        [out addObject:view];
        return;
    }
    if (depth <= 0) return;
    for (UIView *sub in view.subviews) G6CalCollectTiles(sub, out, depth - 1);
}

// ---- Vẽ ô ngày ----

static UIFont *G6CalFont(G6FontWeight weight, CGFloat size) {
    static NSMutableDictionary *cache;
    if (!cache) cache = [NSMutableDictionary dictionary];
    NSString *key = [NSString stringWithFormat:@"%d-%.1f", weight, size];
    UIFont *font = cache[key];
    if (!font) {
        font = G6Font(weight, size);
        if (font) cache[key] = font;
    }
    return font;
}

// Vẽ chữ căn giữa theo chiều ngang tại cx, phần thân chữ số (cao bằng chữ hoa) căn giữa quanh cy
static void G6CalDrawCentered(NSString *text, UIFont *font, UIColor *color, CGFloat cx, CGFloat cy, CGFloat scale) {
    if (!text.length || !font) return;
    CGSize size = [text sizeWithFont:font];
    CGFloat x = cx - size.width / 2, y = cy - (font.ascender - font.capHeight / 2);
    x = round(x * scale) / scale;
    y = round(y * scale) / scale;
    [color set];
    [text drawAtPoint:CGPointMake(x, y) withFont:font];
}

// Vẽ một đoạn chữ từ x, trả x sau đoạn đó (cắt đuôi nếu tràn `right`)
static CGFloat G6CalDrawRun(NSString *text, UIFont *font, UIColor *color, CGFloat x, CGFloat y, CGFloat right) {
    if (!text.length || x >= right) return x;
    [color set];
    return x + [text drawInRect:CGRectMake(x, y, right - x, font.lineHeight) withFont:font lineBreakMode:NSLineBreakByTruncatingTail].width;
}

static void G6CalDrawTile(UIView *tile) {
    CGRect b = tile.bounds;
    CGFloat scale = tile.window.screen.scale ?: [UIScreen mainScreen].scale;
    int state = G6CalInt(tile, "state"), day = G6CalInt(tile, "dayNumber");
    BOOL marked = G6CalInt(tile, "isMarked") != 0;
    BOOL other = state >= 5, today = state == 2 || state == 3, selected = state == 3 || state == 4;
    // Cửa sổ đang mang bộ lọc đảo (chế độ tối): chữ trong đĩa tròn vẽ ĐEN để qua bộ lọc thành trắng
    BOOL inverted = tile.window.layer.filters.count > 0;

    [[UIColor whiteColor] setFill];
    UIRectFill(b);
    // Vạch mảnh ở mép trên: ngăn các tuần (ô hàng sau đè 1 điểm lên đáy ô hàng trước nên mép trên là chỗ luôn thấy)
    [[UIColor colorWithWhite:0.86 alpha:1] setFill];
    UIRectFill(CGRectMake(0, 0, b.size.width, 1 / scale));

    int d = 0, m = 0, y = 0;
    BOOL known = day > 0 && G6CalTileDate(tile, day, state, &d, &m, &y);
    int weekday = known ? G6LunarWeekday(d, m, y) : 1;
    BOOL weekend = weekday == 0 || weekday == 6;
    G6LunarCell lunar = {0};
    if (gLunar && known) lunar = G6LunarCellFor(d, m, y);

    CGFloat cx = b.size.width / 2;
    CGFloat cy = lunar.valid ? 15.5 : 17;  // tâm số ngày dương (và đĩa tròn)
    if (selected) {
        UIColor *disc = today ? G6LunarAccentColor() : [UIColor colorWithWhite:0.08 alpha:1];
        [disc setFill];
        CGFloat r = 14;
        CGContextFillEllipseInRect(UIGraphicsGetCurrentContext(), CGRectMake(cx - r, cy - r, 2 * r, 2 * r));
    }
    UIColor *numberColor;
    if (selected) numberColor = inverted ? [UIColor blackColor] : [UIColor whiteColor];
    else if (today) numberColor = G6LunarAccentColor();
    else if (other) numberColor = [UIColor colorWithWhite:0.74 alpha:1];
    else if (weekend) numberColor = [UIColor colorWithWhite:0.50 alpha:1];
    else numberColor = [UIColor colorWithWhite:0.08 alpha:1];
    UIFont *numberFont = G6CalFont((today || selected) ? G6FontSemiBold : G6FontRegular, 18);
    G6CalDrawCentered([NSString stringWithFormat:@"%d", day], numberFont, numberColor, cx, cy, scale);

    if (lunar.valid) {
        BOOL first = lunar.ld == 1;
        NSString *text = G6LunarShortText(lunar, d == 1 && !other);
        UIColor *color;
        if (other) color = [UIColor colorWithWhite:0.80 alpha:1];
        else if (lunar.fest || lunar.ld == 1 || lunar.ld == 15) color = G6LunarFestColor();
        else if (lunar.good) color = G6LunarGoodColor();
        else color = [UIColor colorWithWhite:0.55 alpha:1];
        UIFont *font = G6CalFont(first && !other ? G6FontSemiBold : G6FontRegular, 10);
        G6CalDrawCentered(text, font, color, cx, 34, scale);
    }
    if (marked && !other) {
        [[UIColor colorWithWhite:0.55 alpha:1] setFill];
        CGFloat r = 1.75, dy = lunar.valid ? 41.5 : 35;
        CGContextFillEllipseInRect(UIGraphicsGetCurrentContext(), CGRectMake(cx - r, dy - r, 2 * r, 2 * r));
    }
}

static void (*orig_tileDraw)(UIView *, SEL, CGRect);
static void repl_tileDraw(UIView *self, SEL _cmd, CGRect rect) {
    if (!gActive) {
        orig_tileDraw(self, _cmd, rect);
        return;
    }
    @try {
        G6CalDrawTile(self);
    } @catch (NSException *e) {
        orig_tileDraw(self, _cmd, rect);
    }
}

// ---- Đầu lịch ----

static UIImage *G6CalChevron(BOOL right) {
    CGSize size = CGSizeMake(13, 16);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetStrokeColorWithColor(ctx, G6LunarAccentColor().CGColor);
    CGContextSetLineWidth(ctx, 2.2);
    CGContextSetLineCap(ctx, kCGLineCapRound);
    CGContextSetLineJoin(ctx, kCGLineJoinRound);
    CGFloat x0 = right ? 4 : 9, x1 = right ? 9.5 : 3.5;
    CGContextMoveToPoint(ctx, x0, 2.5);
    CGContextAddLineToPoint(ctx, x1, 8);
    CGContextAddLineToPoint(ctx, x0, 13.5);
    CGContextStrokePath(ctx);
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

static id G6CalOrNull(id v) {
    return v ?: [NSNull null];
}

static id G6CalUnNull(id v) {
    return v == [NSNull null] ? nil : v;
}

static void G6CalStyleLabel(UILabel *label, UIFont *font, UIColor *color) {
    if (![label isKindOfClass:[UILabel class]]) return;
    if (gActive) {
        if (!objc_getAssociatedObject(label, &kLabelSavedKey)) {
            objc_setAssociatedObject(label, &kLabelSavedKey,
                                     @[G6CalOrNull(label.textColor), G6CalOrNull(label.shadowColor), G6CalOrNull(label.font),
                                       @(label.adjustsFontSizeToFitWidth), @(label.minimumScaleFactor)],
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (font && ![label.font isEqual:font]) label.font = font;
        label.textColor = color;
        label.shadowColor = nil;
        label.adjustsFontSizeToFitWidth = YES;
        label.minimumScaleFactor = 0.7;
    } else {
        NSArray *saved = objc_getAssociatedObject(label, &kLabelSavedKey);
        if (!saved) return;
        label.textColor = G6CalUnNull(saved[0]);
        label.shadowColor = G6CalUnNull(saved[1]);
        if (G6CalUnNull(saved[2])) label.font = saved[2];
        label.adjustsFontSizeToFitWidth = [saved[3] boolValue];
        label.minimumScaleFactor = [saved[4] floatValue];
        objc_setAssociatedObject(label, &kLabelSavedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void G6CalStyleHeadings(UIView *headings) {
    NSArray *titles = G6CalIvar(headings, "_titles");
    if (![titles isKindOfClass:[NSArray class]]) titles = headings.subviews;
    for (UILabel *label in titles) G6CalStyleLabel(label, G6CalFont(G6FontMedium, 11), [UIColor colorWithWhite:0.50 alpha:1]);
}

// Tên tháng: viết hoa chữ đầu («tháng mười một 2026» → «Tháng mười một 2026») — chỉ đổi chữ hiển thị
static void G6CalCapitalize(UILabel *label) {
    NSString *text = label.text;
    if (gActive && text.length > 1) {
        NSString *head = [[text substringToIndex:1] uppercaseString];
        if (![head isEqualToString:[text substringToIndex:1]]) label.text = [head stringByAppendingString:[text substringFromIndex:1]];
    }
}

// Bóng đổ dưới lịch: UIImageView anh em, cao vài điểm, nằm sát đáy lịch
static UIView *G6CalShadowView(UIView *control) {
    for (UIView *v in control.superview.subviews) {
        if ([v isKindOfClass:[UIImageView class]] && v.frame.size.height <= 10 && fabs(v.frame.origin.y - CGRectGetMaxY(control.frame)) < 2) {
            return v;
        }
    }
    return nil;
}

// Nền vân (UIImageView) → mặt trắng; nhớ ảnh + màu nền gốc để trả
static void G6CalStyleImage(UIImageView *view) {
    if (![view isKindOfClass:[UIImageView class]]) return;
    NSArray *saved = objc_getAssociatedObject(view, &kLabelSavedKey);
    if (gActive) {
        if (!saved) {
            objc_setAssociatedObject(view, &kLabelSavedKey, @[G6CalOrNull(view.image), G6CalOrNull(view.backgroundColor)],
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        view.image = nil;
        view.backgroundColor = [UIColor whiteColor];
    } else if (saved) {
        view.image = G6CalUnNull(saved[0]);
        view.backgroundColor = G6CalUnNull(saved[1]);
        objc_setAssociatedObject(view, &kLabelSavedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

// Vạch ngăn (view cao 1 điểm tô màu) → màu vạch mảnh chung
static void G6CalStyleLine(UIView *view) {
    NSArray *saved = objc_getAssociatedObject(view, &kLabelSavedKey);
    if (gActive) {
        if (!saved) objc_setAssociatedObject(view, &kLabelSavedKey, @[G6CalOrNull(view.backgroundColor)], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        view.backgroundColor = [UIColor colorWithWhite:0.86 alpha:1];
    } else if (saved) {
        view.backgroundColor = G6CalUnNull(saved[0]);
        objc_setAssociatedObject(view, &kLabelSavedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

// Mũi tên lật tháng / ngày (CalendarArrowButton — UIButton có hình) → «‹ ›» đỏ
static void G6CalStyleArrow(UIButton *button, BOOL right) {
    if (![button isKindOfClass:[UIButton class]]) return;
    NSArray *saved = objc_getAssociatedObject(button, &kLabelSavedKey);
    if (gActive) {
        if (!saved) {
            objc_setAssociatedObject(button, &kLabelSavedKey,
                                     @[G6CalOrNull([button imageForState:UIControlStateNormal]),
                                       G6CalOrNull([button imageForState:UIControlStateHighlighted])],
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        static UIImage *images[2];
        int k = right ? 1 : 0;
        if (!images[k]) images[k] = G6CalChevron(right);
        [button setImage:images[k] forState:UIControlStateNormal];
        [button setImage:images[k] forState:UIControlStateHighlighted];
    } else if (saved) {
        [button setImage:G6CalUnNull(saved[0]) forState:UIControlStateNormal];
        [button setImage:G6CalUnNull(saved[1]) forState:UIControlStateHighlighted];
        objc_setAssociatedObject(button, &kLabelSavedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void G6CalStyleControl(UIView *control) {
    G6CalStyleImage(G6CalIvar(control, "_bannerBkgnd"));
    G6CalStyleImage(G6CalIvar(control, "_tilesClipView"));
    G6CalStyleArrow(G6CalIvar(control, "_leftArrow"), NO);
    G6CalStyleArrow(G6CalIvar(control, "_rightArrow"), YES);
    // Bóng đổ dưới lịch: ẩn (nhớ để trả)
    UIView *shadow = G6CalShadowView(control);
    UIView *hidden = objc_getAssociatedObject(control, &kSavedKey);
    if (gActive && shadow && !shadow.hidden) {
        shadow.hidden = YES;
        objc_setAssociatedObject(control, &kSavedKey, shadow, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else if (!gActive && hidden) {
        hidden.hidden = NO;
        objc_setAssociatedObject(control, &kSavedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    // Vạch đáy của lưới (view con không phải ô, cao 1 điểm) → màu vạch mảnh như các vạch giữa tuần
    Class tileClass = objc_getClass("CalendarMonthDayTile");
    UIView *tiles = G6CalIvar(control, "_tilesView");
    for (UIView *v in tiles.subviews) {
        if (![v isKindOfClass:tileClass] && v.frame.size.height <= 1.5) G6CalStyleLine(v);
    }
    UILabel *name = G6CalIvar(control, "_nameView");
    G6CalStyleLabel(name, G6CalFont(G6FontBold, 19), [UIColor colorWithWhite:0.08 alpha:1]);
    G6CalCapitalize(name);
    UIView *headings = G6CalIvar(control, "_headingsView");
    if (headings) G6CalStyleHeadings(headings);
}

// ---- Màn Ngày: dải tên ngày (EKDayBannerView của EventKitUI, 320×45) ----
// Con: UIImageView nền vân 320×44, vạch 1 điểm ở đáy, hai CalendarArrowButton, EKDayBannerNameView (tự vẽ tên ngày trong
// drawRect: từ biến _day — NSDateComponents). Vẽ lại tên ngày: «Thứ Ba, 1 tháng 12, 2026» đậm (hôm nay: đỏ) + dòng âm lịch
// nhỏ «23 tháng 10 Bính Ngọ · Hắc đạo» (hoàng đạo: vàng cam; lễ: đỏ).

static void G6CalStyleDayBanner(UIView *banner) {
    Class nameClass = objc_getClass("EKDayBannerNameView");
    for (UIView *v in banner.subviews) {
        if ([v isKindOfClass:[UIImageView class]] && v.frame.size.height >= 30) {
            G6CalStyleImage((UIImageView *)v);
        } else if (![v isKindOfClass:[UIControl class]] && ![v isKindOfClass:[UIImageView class]] &&
                   (!nameClass || ![v isKindOfClass:nameClass]) && v.frame.size.height <= 1.5) {
            G6CalStyleLine(v);
        }
    }
    G6CalStyleArrow(G6CalIvar(banner, "_leftArrow"), NO);
    G6CalStyleArrow(G6CalIvar(banner, "_rightArrow"), YES);
    [G6CalIvar(banner, "_nameView") setNeedsDisplay];
}

static NSString *G6CalDayTitle(int d, int m, int y) {
    NSString *lang = [[NSLocale preferredLanguages] firstObject] ?: @"";
    if ([lang hasPrefix:@"vi"]) {
        static NSString *const names[] = {@"Chủ Nhật", @"Thứ Hai", @"Thứ Ba", @"Thứ Tư", @"Thứ Năm", @"Thứ Sáu", @"Thứ Bảy"};
        return [NSString stringWithFormat:@"%@, %d tháng %d, %d", names[G6LunarWeekday(d, m, y)], d, m, y];
    }
    NSDateComponents *c = [[NSDateComponents alloc] init];
    c.day = d;
    c.month = m;
    c.year = y;
    NSDate *date = [[NSCalendar currentCalendar] dateFromComponents:c];
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    f.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"EEEEdMMMMy" options:0 locale:[NSLocale currentLocale]];
    return date ? [f stringFromDate:date] : nil;
}

static BOOL G6CalIsToday(int d, int m, int y) {
    NSDateComponents *c = [[NSCalendar currentCalendar] components:NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit
                                                           fromDate:[NSDate date]];
    return c.day == d && c.month == m && c.year == y;
}

static BOOL G6CalDrawDayName(UIView *view) {
    NSDateComponents *c = G6CalIvar(view, "_day");
    if (![c isKindOfClass:[NSDateComponents class]]) return NO;
    NSInteger d = c.day, m = c.month, y = c.year;
    if (d == NSUndefinedDateComponent || m == NSUndefinedDateComponent || y == NSUndefinedDateComponent || m < 1 || m > 12) return NO;
    NSString *title = G6CalDayTitle((int)d, (int)m, (int)y);
    if (!title.length) return NO;
    CGRect b = view.bounds;
    CGFloat scale = view.window.screen.scale ?: [UIScreen mainScreen].scale;
    NSDictionary *x = gLunar ? G6LunarDayDetail((int)d, (int)m, (int)y) : nil;

    UIFont *tf = G6CalFont(G6FontSemiBold, 17);
    CGFloat ty = x ? 5 : round((b.size.height - tf.lineHeight) / 2);
    UIColor *tc = G6CalIsToday((int)d, (int)m, (int)y) ? G6LunarAccentColor() : [UIColor colorWithWhite:0.08 alpha:1];
    CGSize ts = [title sizeWithFont:tf];
    CGFloat tw = MIN(ts.width, b.size.width - 4);
    [tc set];
    [title drawInRect:CGRectMake(round((b.size.width - tw) / 2 * scale) / scale, ty, tw, tf.lineHeight)
             withFont:tf
        lineBreakMode:NSLineBreakByTruncatingTail];
    if (!x) return YES;

    // Dòng âm lịch: các đoạn chữ khác màu, căn giữa cả dòng
    BOOL good = [x[@"good"] boolValue];
    NSString *festival = [x[@"festival"] isKindOfClass:[NSString class]] ? x[@"festival"] : nil;
    UIFont *f = G6CalFont(G6FontRegular, 11.5), *fm = G6CalFont(G6FontMedium, 11.5);
    UIColor *secondary = [UIColor colorWithWhite:0.45 alpha:1];
    NSMutableArray *runs = [NSMutableArray array];
    [runs addObject:@[[NSString stringWithFormat:@"%@ tháng %@%@ %@", x[@"ld"], x[@"lm"], [x[@"leap"] boolValue] ? @" nhuận" : @"",
                                                x[@"can_chi_year"] ?: @""], f, secondary]];
    [runs addObject:@[@" · ", f, secondary]];
    [runs addObject:@[good ? @"Hoàng đạo" : @"Hắc đạo", fm, good ? G6LunarGoodColor() : secondary]];
    if (festival.length) {
        [runs addObject:@[@" · ", f, secondary]];
        [runs addObject:@[festival, fm, G6LunarFestColor()]];
    }
    CGFloat total = 0;
    for (NSArray *r in runs) total += [r[0] sizeWithFont:r[1]].width;
    CGFloat x0 = MAX(2, (b.size.width - total) / 2), ly = ty + tf.lineHeight + 0.5;
    x0 = round(x0 * scale) / scale;
    for (NSArray *r in runs) x0 = G6CalDrawRun(r[0], r[1], r[2], x0, ly, b.size.width - 2);
    return YES;
}

static void (*orig_dayNameDraw)(UIView *, SEL, CGRect);
static void repl_dayNameDraw(UIView *self, SEL _cmd, CGRect rect) {
    if (!gActive) {
        orig_dayNameDraw(self, _cmd, rect);
        return;
    }
    @try {
        if (!G6CalDrawDayName(self)) orig_dayNameDraw(self, _cmd, rect);
    } @catch (NSException *e) {
    }
}

static void (*orig_dayBannerLayout)(UIView *, SEL);
static void repl_dayBannerLayout(UIView *self, SEL _cmd) {
    orig_dayBannerLayout(self, _cmd);
    @try {
        G6CalStyleDayBanner(self);
    } @catch (NSException *e) {
    }
}

// ---- Thẻ âm lịch của ngày đang chọn (đầu bảng sự kiện) ----

@interface G6CalLunarCardView : UIView
@property(nonatomic, strong) NSDictionary *detail;
@property(nonatomic, assign) int day, month, year;
+ (CGFloat)heightForDetail:(NSDictionary *)detail;
@end

@implementation G6CalLunarCardView

+ (CGFloat)heightForDetail:(NSDictionary *)detail {
    return 90;
}

static NSString *G6CalHourNames(NSArray *hours) {
    NSMutableArray *names = [NSMutableArray array];
    for (NSString *h in hours) {
        if (![h isKindOfClass:[NSString class]]) continue;
        NSRange r = [h rangeOfString:@" ("];
        [names addObject:r.location == NSNotFound ? h : [h substringToIndex:r.location]];
    }
    return [names componentsJoinedByString:@", "];
}


// Bốn dòng: ngày tháng năm âm + viên «Hoàng đạo / Hắc đạo»; can chi ngày, tháng + thần trực ngày; giờ hoàng đạo; tiết khí
// (+ lễ âm lịch, chữ đỏ)
- (void)drawRect:(CGRect)rect {
    CGRect b = self.bounds;
    [[UIColor whiteColor] setFill];
    UIRectFill(b);
    NSDictionary *x = self.detail;
    if (!x) return;
    CGFloat scale = self.window.screen.scale ?: [UIScreen mainScreen].scale;
    CGFloat left = 15, right = b.size.width - 15, y = 9;
    UIColor *primary = [UIColor colorWithWhite:0.08 alpha:1], *secondary = [UIColor colorWithWhite:0.45 alpha:1];
    BOOL good = [x[@"good"] boolValue];
    UIColor *tone = good ? G6LunarGoodColor() : secondary;

    NSString *pill = good ? @"Hoàng đạo" : @"Hắc đạo";
    UIFont *pillFont = G6CalFont(G6FontSemiBold, 11);
    CGSize ps = [pill sizeWithFont:pillFont];
    CGRect pr = CGRectMake(right - ps.width - 16, y + 1, ps.width + 16, 19);
    [[tone colorWithAlphaComponent:0.14] setFill];
    [[UIBezierPath bezierPathWithRoundedRect:pr cornerRadius:9.5] fill];
    [tone set];
    [pill drawAtPoint:CGPointMake(round((pr.origin.x + 8) * scale) / scale, round((pr.origin.y + (19 - pillFont.lineHeight) / 2) * scale) / scale)
             withFont:pillFont];

    NSString *line1 = [NSString stringWithFormat:@"%@ tháng %@%@ năm %@", x[@"ld"], x[@"lm"], [x[@"leap"] boolValue] ? @" nhuận" : @"",
                                                 x[@"can_chi_year"] ?: @""];
    G6CalDrawRun(line1, G6CalFont(G6FontSemiBold, 15), primary, left, y, pr.origin.x - 8);
    y += 23;

    UIFont *f = G6CalFont(G6FontRegular, 12.5), *fm = G6CalFont(G6FontMedium, 12.5);
    NSString *than = [x[@"than"] isKindOfClass:[NSString class]] ? x[@"than"] : nil;
    CGFloat tx = G6CalDrawRun([NSString stringWithFormat:@"Ngày %@ · tháng %@%@", x[@"can_chi_day"] ?: @"", x[@"can_chi_month"] ?: @"",
                                                        than.length ? @" · " : @""],
                              f, secondary, left, y, right);
    G6CalDrawRun(than, fm, tone, tx, y, right);
    y += 17;

    NSString *hours = [x[@"hours"] isKindOfClass:[NSArray class]] ? G6CalHourNames(x[@"hours"]) : @"";
    G6CalDrawRun([@"Giờ tốt: " stringByAppendingString:hours], f, secondary, left, y, right);
    y += 17;

    NSString *festival = [x[@"festival"] isKindOfClass:[NSString class]] ? x[@"festival"] : nil;
    NSString *tiet = [x[@"tiet_khi"] isKindOfClass:[NSString class]] ? [@"Tiết " stringByAppendingString:x[@"tiet_khi"]] : @"";
    tx = G6CalDrawRun(tiet, f, secondary, left, y, right);
    if (festival.length) {
        if (tiet.length) tx = G6CalDrawRun(@" · ", f, secondary, tx, y, right);
        G6CalDrawRun(festival, fm, G6LunarFestColor(), tx, y, right);
    }

    // Vạch mảnh ở đáy thẻ, ngăn với các dòng sự kiện
    [[UIColor colorWithWhite:0.86 alpha:1] setFill];
    UIRectFill(CGRectMake(0, b.size.height - 1 / scale, b.size.width, 1 / scale));
}

@end

static void G6CalPlaceEmptyLabel(UITableView *table, UIView *card);

static UITableView *G6CalEventTable(UIView *control) {
    for (UIView *v in control.superview.subviews) {
        if ([v isKindOfClass:[UITableView class]]) return (UITableView *)v;
    }
    return nil;
}

// Ngày đang chọn: ô (của bộ ô đang dùng) ở trạng thái 3 / 4
static BOOL G6CalSelectedDate(UIView *control, int *d, int *m, int *y) {
    NSArray *tiles = G6CalCurrentTiles(control);
    if (!tiles) {
        NSMutableArray *all = [NSMutableArray array];
        G6CalCollectTiles(G6CalIvar(control, "_tilesView") ?: control, all, 3);
        tiles = all;
    }
    for (UIView *tile in tiles) {
        int state = G6CalInt(tile, "state");
        if (state != 3 && state != 4) continue;
        return G6CalTileDate(tile, G6CalInt(tile, "dayNumber"), state, d, m, y);
    }
    return NO;
}

static void G6CalUpdateCard(UIView *control) {
    UITableView *table = G6CalEventTable(control);
    if (!table) return;
    G6CalLunarCardView *card = objc_getAssociatedObject(table, &kCardKey);
    BOOL want = gActive && gLunar;
    int d = 0, m = 0, y = 0;
    NSDictionary *detail = want && G6CalSelectedDate(control, &d, &m, &y) ? G6LunarDayDetail(d, m, y) : nil;
    if (!detail) {
        // Không có ngày chọn trong tháng đang hiện (vừa lật tháng): giữ thẻ cũ; tắt tính năng thì gỡ thẻ
        if (!want && card) {
            if (table.tableHeaderView == card) table.tableHeaderView = nil;
            objc_setAssociatedObject(table, &kCardKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return;
    }
    if (table.tableHeaderView && table.tableHeaderView != card) return;  // app có đầu bảng riêng: không chen vào
    if (!card) {
        card = [[G6CalLunarCardView alloc] initWithFrame:CGRectZero];
        card.opaque = YES;
        card.contentMode = UIViewContentModeRedraw;
        objc_setAssociatedObject(table, &kCardKey, card, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    BOOL same = card.day == d && card.month == m && card.year == y && table.tableHeaderView == card;
    card.detail = detail;
    card.day = d;
    card.month = m;
    card.year = y;
    CGRect f = CGRectMake(0, 0, table.bounds.size.width, [G6CalLunarCardView heightForDetail:detail]);
    if (!same || !CGRectEqualToRect(card.frame, f)) {
        card.frame = f;
        table.tableHeaderView = card;  // gán lại để bảng tính lại chiều cao đầu bảng
    }
    [card setNeedsDisplay];
    G6CalPlaceEmptyLabel(table, card);
}

// Nhãn «Không có sự kiện» là UILabel con trực tiếp của bảng, app đặt ở khoảng giữa bảng mà không tính đầu bảng → đè lên thẻ.
// Sau mỗi lượt xếp của bảng có thẻ: dời nhãn xuống giữa phần còn lại bên dưới thẻ.
static void G6CalPlaceEmptyLabel(UITableView *table, UIView *card) {
    CGFloat top = CGRectGetMaxY(card.frame);
    for (UIView *v in table.subviews) {
        if (![v isMemberOfClass:[UILabel class]] || v.hidden) continue;
        CGRect f = v.frame;
        if (f.origin.y >= top + 2) continue;
        CGFloat room = table.bounds.size.height - top;
        f.origin.y = round(top + MAX(6, (room - f.size.height) / 2));
        v.frame = f;
    }
}

static void (*orig_tableLayout)(UITableView *, SEL);
static void repl_tableLayout(UITableView *self, SEL _cmd) {
    orig_tableLayout(self, _cmd);
    UIView *card = objc_getAssociatedObject(self, &kCardKey);
    if (!card || self.tableHeaderView != card) return;
    @try {
        G6CalPlaceEmptyLabel(self, card);
    } @catch (NSException *e) {
    }
}

// ---- Móc hàm của lịch ----

// Sau khi app dựng bộ ô cho tháng mới: gắn ngày cho từng ô của bộ MỚI, bắt vẽ lại (app không tự vẽ lại ô cùng trạng thái)
static void G6CalAfterMonthChange(UIView *control) {
    NSArray *tiles = G6CalCurrentTiles(control);
    if (!tiles) {
        NSMutableArray *all = [NSMutableArray array];
        G6CalCollectTiles(G6CalIvar(control, "_tilesView") ?: control, all, 3);
        tiles = all;
    }
    for (UIView *tile in tiles) {
        int day = G6CalInt(tile, "dayNumber"), state = G6CalInt(tile, "state"), d, m, y;
        if (day > 0 && G6CalComputeTileDate(control, tile, day, state, &d, &m, &y)) G6CalStoreTileDate(tile, d, m, y);
        if (gActive) [tile setNeedsDisplay];
    }
#if G6_DEBUG
    {
        int mm = 0, yy = 0;
        G6CalShownMonth(control, &mm, &yy);
        NSMutableArray *all = [NSMutableArray array];
        G6CalCollectTiles(G6CalIvar(control, "_tilesView") ?: control, all, 3);
        int inView = 0;
        for (UIView *t in tiles) inView += t.superview != nil;
        G6Log(@"[thử] lịch: tháng %d/%d, bộ ô đang dùng %d ô (%d đang hiện), trong lưới có %d ô", mm, yy, (int)tiles.count, inView,
              (int)all.count);
    }
#endif
    if (gActive) G6CalStyleControl(control);
    G6CalUpdateCard(control);
}

static void (*orig_setMonth)(UIView *, SEL, G6CalDate, BOOL, BOOL);
static void repl_setMonth(UIView *self, SEL _cmd, G6CalDate month, BOOL animating, BOOL force) {
    orig_setMonth(self, _cmd, month, animating, force);
    @try {
        G6CalAfterMonthChange(self);
    } @catch (NSException *e) {
    }
}

static void (*orig_setSelectedTile)(UIView *, SEL, int);
static void repl_setSelectedTile(UIView *self, SEL _cmd, int tile) {
    orig_setSelectedTile(self, _cmd, tile);
    @try {
        G6CalUpdateCard(self);
    } @catch (NSException *e) {
    }
}

static void (*orig_setSelectedDate)(UIView *, SEL, G6CalDate);
static void repl_setSelectedDate(UIView *self, SEL _cmd, G6CalDate date) {
    orig_setSelectedDate(self, _cmd, date);
    @try {
        G6CalUpdateCard(self);
    } @catch (NSException *e) {
    }
}

static void (*orig_controlSetFrame)(UIView *, SEL, CGRect);
static void repl_controlSetFrame(UIView *self, SEL _cmd, CGRect frame) {
    orig_controlSetFrame(self, _cmd, frame);
    @try {
        if (gActive) G6CalStyleControl(self);
    } @catch (NSException *e) {
    }
}

static void (*orig_headingsLayout)(UIView *, SEL);
static void repl_headingsLayout(UIView *self, SEL _cmd) {
    orig_headingsLayout(self, _cmd);
    @try {
        if (gActive) G6CalStyleHeadings(self);
    } @catch (NSException *e) {
    }
}

static void (*orig_headingsUpdate)(UIView *, SEL);
static void repl_headingsUpdate(UIView *self, SEL _cmd) {
    orig_headingsUpdate(self, _cmd);
    @try {
        if (gActive) G6CalStyleHeadings(self);
    } @catch (NSException *e) {
    }
}

static void G6CalRefresh(UIView *view, Class controlClass, Class bannerClass, int depth) {
    if (controlClass && [view isKindOfClass:controlClass]) {
        G6CalStyleControl(view);
        NSMutableArray *tiles = [NSMutableArray array];
        G6CalCollectTiles(view, tiles, 4);
        for (UIView *tile in tiles) [tile setNeedsDisplay];
        G6CalUpdateCard(view);
        return;
    }
    if (bannerClass && [view isKindOfClass:bannerClass]) {
        G6CalStyleDayBanner(view);
        return;
    }
    if (depth <= 0) return;
    for (UIView *sub in view.subviews) G6CalRefresh(sub, controlClass, bannerClass, depth - 1);
}

void G6UIAppCalendarPhoneApply(BOOL active, BOOL lunar) {
    Class control = objc_getClass("CalendarMonthControl"), tile = objc_getClass("CalendarMonthDayTile");
    Class banner = objc_getClass("EKDayBannerView");
    if (!control && !banner) return;
    static BOOL hooked;
    if (!hooked) {
        if (!active) return;
        hooked = YES;
        BOOL ok = tile && G6Hook(tile, @selector(drawRect:), (IMP)repl_tileDraw, (IMP *)&orig_tileDraw);
        if (control) {
            G6Hook(control, sel_registerName("_setDisplayedMonth:animating:force:"), (IMP)repl_setMonth, (IMP *)&orig_setMonth);
            G6Hook(control, sel_registerName("_setSelectedTile:"), (IMP)repl_setSelectedTile, (IMP *)&orig_setSelectedTile);
            G6Hook(control, sel_registerName("setSelectedDate:"), (IMP)repl_setSelectedDate, (IMP *)&orig_setSelectedDate);
            G6Hook(control, @selector(setFrame:), (IMP)repl_controlSetFrame, (IMP *)&orig_controlSetFrame);
            G6Hook([UITableView class], @selector(layoutSubviews), (IMP)repl_tableLayout, (IMP *)&orig_tableLayout);
        }
        G6HookNamed("CalendarMonthDayHeadingsView", @selector(layoutSubviews), (IMP)repl_headingsLayout, (IMP *)&orig_headingsLayout);
        G6HookNamed("CalendarMonthDayHeadingsView", sel_registerName("_updateTitles"), (IMP)repl_headingsUpdate,
                    (IMP *)&orig_headingsUpdate);
        BOOL day = banner && G6Hook(banner, @selector(layoutSubviews), (IMP)repl_dayBannerLayout, (IMP *)&orig_dayBannerLayout) &&
                   G6HookNamed("EKDayBannerNameView", @selector(drawRect:), (IMP)repl_dayNameDraw, (IMP *)&orig_dayNameDraw);
        G6Log(@"lịch (app): lịch tháng %@, dải tên ngày %@%@", ok ? @"kiểu mới" : @"giữ nguyên (thiếu hàm vẽ ô)",
              day ? @"kiểu mới" : @"giữ nguyên", lunar ? @" + âm lịch" : @"");
    }
    gActive = active;
    gLunar = lunar;
    for (UIWindow *window in [UIApplication sharedApplication].windows) G6CalRefresh(window, control, banner, 14);
}

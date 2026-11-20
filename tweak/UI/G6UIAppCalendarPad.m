// App Lịch trên iPad — lịch tháng: số ngày kiểu iPadOS 26 + âm lịch Việt Nam; màn Ngày: khối âm lịch trên trang trái.
//
// Cấu trúc iOS 6 (tra 21/11/2026 trên iPad 4 bằng `methods` / cây view đã bỏ chữ; máy ngang):
//   CalendarMonthPadView › CalendarMonthPageView (7 70; 1010 651)
//     _title         UILabel (77 79; 430 59)   tên tháng, chữ mảnh xám cỡ lớn
//     _calendarView  CalendarMonthViewCalendar (27 144; 970 553) — tự vẽ cả lưới trong drawRect:; mỗi ô là một
//                    CalendarMonthViewDay (NSObject, không phải view) tự vẽ vào ngữ cảnh của lưới bằng drawInFrame:visibleRect:
//   CalendarMonthViewDay: _date (CFGregorianDate), _dayNumberLabelString («26»), _weekdayString («Th 2», chỉ hàng đầu),
//   _isToday (ô hôm nay vẽ dải xanh «H.nay … 21 thg 11»), _dayIsThisMonth, _isWeekend, _selected, _labelRectInFrame: (chỗ số).
//   Sự kiện là view riêng (CalendarMonthViewOccurrence) nằm dưới hàng số — không đụng.
//
// Việc làm (thành phần «app_skins»; âm lịch theo công tắc «lunar»):
//   - Cho app vẽ ô như cũ nhưng TẠM bỏ chữ số, tên thứ và cờ hôm nay (đặt lại ngay sau lượt vẽ): nền ô, chữ «+n nữa», vạch lưới
//     vẫn của app. Rồi tự vẽ số ngày ở đúng chỗ cũ: hôm nay đĩa đỏ chữ trắng, cuối tuần chữ xám, ngày tháng khác chữ nhạt; hàng
//     đầu kèm tên thứ. Âm lịch: ngày âm nhỏ ở góc trái cùng hàng (mùng 1 kèm tháng), hoàng đạo vàng cam, mùng 1 / rằm / lễ đỏ.
//   - Tên tháng: chữ đậm tối, viết hoa chữ đầu.
// Vẽ theo bảng màu SÁNG (chế độ tối do bộ lọc đảo của cửa sổ — G6UISkin.h); số trong đĩa đỏ vẽ đen khi cửa sổ đang bị đảo.
#import "G6UI.h"

#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "G6Font.h"
#import "G6Hook.h"
#import "G6Log.h"
#import "G6UICalendarLunar.h"

void G6UIAppCalendarPadApply(BOOL active, BOOL lunar);

static BOOL gActive, gLunar;
static char kTitleSavedKey;

typedef struct {
    int32_t year;
    int8_t month, day, hour, minute;
    double second;
} G6PadDate;

static UIFont *G6PadFont(G6FontWeight weight, CGFloat size) {
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

static Ivar G6PadIvar(Class cls, const char *name, char type) {
    Ivar iv = class_getInstanceVariable(cls, name);
    const char *t = iv ? ivar_getTypeEncoding(iv) : NULL;
    return (t && t[0] == type) ? iv : NULL;
}

static BOOL G6PadChar(id obj, const char *sel) {
    SEL s = sel_registerName(sel);
    return [obj respondsToSelector:s] ? ((char (*)(id, SEL))objc_msgSend)(obj, s) != 0 : NO;
}

// Chữ căn phải tại `right`, thân chữ số căn giữa quanh cy; trả bề rộng
static CGFloat G6PadDrawRight(NSString *text, UIFont *font, UIColor *color, CGFloat right, CGFloat cy, CGFloat scale) {
    if (!text.length || !font) return 0;
    CGSize size = [text sizeWithFont:font];
    CGFloat x = round((right - size.width) * scale) / scale, y = round((cy - (font.ascender - font.capHeight / 2)) * scale) / scale;
    [color set];
    [text drawAtPoint:CGPointMake(x, y) withFont:font];
    return size.width;
}

static void G6PadDrawLabels(id day, CGRect frame, NSString *weekday, BOOL today, UIView *canvas) {
    Class cls = object_getClass(day);
    Ivar dateIv = G6PadIvar(cls, "_date", '{');
    if (!dateIv) return;
    G6PadDate date = *(const G6PadDate *)((const uint8_t *)(__bridge void *)day + ivar_getOffset(dateIv));
    if (date.month < 1 || date.month > 12 || date.day < 1) return;
    CGRect lr = frame;
    SEL sel = sel_registerName("_labelRectInFrame:");
    Method m = class_getInstanceMethod(cls, sel);
    if (m) lr = ((CGRect(*)(id, SEL, CGRect))method_getImplementation(m))(day, sel, frame);
    if (lr.size.height < 8 || lr.size.width < 8) lr = CGRectMake(frame.origin.x, frame.origin.y + 2, frame.size.width - 6, 18);
    CGFloat scale = canvas.window.screen.scale ?: [UIScreen mainScreen].scale;
    BOOL inverted = canvas.window.layer.filters.count > 0;
    BOOL thisMonth = G6PadChar(day, "dayIsThisMonth"), weekend = G6PadChar(day, "isWeekend");
    CGFloat right = CGRectGetMaxX(lr), cy = CGRectGetMidY(lr);

    NSString *number = [NSString stringWithFormat:@"%d", date.day];
    UIFont *nf = G6PadFont(today ? G6FontSemiBold : G6FontRegular, 15);
    CGFloat used;
    if (today) {
        CGFloat r = 12.5, w = MAX(2 * r, [number sizeWithFont:nf].width + 10);
        CGRect disc = CGRectMake(right - w, cy - r, w, 2 * r);
        [G6LunarAccentColor() setFill];
        [[UIBezierPath bezierPathWithRoundedRect:disc cornerRadius:r] fill];
        UIColor *ink = inverted ? [UIColor blackColor] : [UIColor whiteColor];
        CGFloat nw = [number sizeWithFont:nf].width;
        G6PadDrawRight(number, nf, ink, CGRectGetMidX(disc) + nw / 2, cy, scale);
        used = w;
    } else {
        UIColor *c = !thisMonth ? [UIColor colorWithWhite:0.72 alpha:1]
                                : weekend ? [UIColor colorWithWhite:0.50 alpha:1] : [UIColor colorWithWhite:0.10 alpha:1];
        used = G6PadDrawRight(number, nf, c, right, cy, scale);
    }
    if (weekday.length) {
        G6PadDrawRight(weekday, G6PadFont(G6FontMedium, 13), [UIColor colorWithWhite:0.50 alpha:1], right - used - 6, cy, scale);
    }

    if (!gLunar) return;
    G6LunarCell lunar = G6LunarCellFor(date.day, date.month, date.year);
    if (!lunar.valid) return;
    NSString *text = G6LunarShortText(lunar, date.day == 1 && thisMonth);
    UIColor *color;
    if (!thisMonth) color = [UIColor colorWithWhite:0.78 alpha:1];
    else if (lunar.fest || lunar.ld == 1 || lunar.ld == 15) color = G6LunarFestColor();
    else if (lunar.good) color = G6LunarGoodColor();
    else color = [UIColor colorWithWhite:0.55 alpha:1];
    UIFont *lf = G6PadFont(lunar.ld == 1 && thisMonth ? G6FontSemiBold : G6FontRegular, 12);
    CGSize ls = [text sizeWithFont:lf];
    CGFloat lx = round((frame.origin.x + 8) * scale) / scale;
    // Hàng đầu có tên thứ ở bên phải: chừa chỗ, không đè
    if (lx + ls.width > right - used - (weekday.length ? 50 : 6)) return;
    CGFloat ly = round((cy - (lf.ascender - lf.capHeight / 2)) * scale) / scale;
    [color set];
    [text drawAtPoint:CGPointMake(lx, ly) withFont:lf];
}

// Cho app vẽ ô (nền, «+n nữa») với số / tên thứ / chữ «21 thg 11» / cờ hôm nay tạm bỏ, rồi tự vẽ phần chữ
static void (*orig_dayDraw)(id, SEL, CGRect, CGRect);
static void repl_dayDraw(id self, SEL _cmd, CGRect frame, CGRect visible) {
    if (!gActive) {
        orig_dayDraw(self, _cmd, frame, visible);
        return;
    }
    Class cls = object_getClass(self);
    Ivar numIv = G6PadIvar(cls, "_dayNumberLabelString", '@'), wdIv = G6PadIvar(cls, "_weekdayString", '@');
    Ivar todayIv = G6PadIvar(cls, "_isToday", 'c'), monthIv = G6PadIvar(cls, "_todayMonthString", '@');
    if (!numIv || !wdIv || !todayIv) {
        orig_dayDraw(self, _cmd, frame, visible);
        return;
    }
    // Lớp của app không dùng ARC: object_setIvar chỉ gán con trỏ — đặt chuỗi hằng rồi trả đúng con trỏ cũ là cân bằng
    __unsafe_unretained id number = object_getIvar(self, numIv), weekday = object_getIvar(self, wdIv);
    __unsafe_unretained id todayText = monthIv ? object_getIvar(self, monthIv) : nil;
    char *todayPtr = (char *)(__bridge void *)self + ivar_getOffset(todayIv);
    char today = *todayPtr;
    object_setIvar(self, numIv, @"");
    object_setIvar(self, wdIv, @"");
    if (monthIv) object_setIvar(self, monthIv, @"");
    *todayPtr = 0;
    @try {
        orig_dayDraw(self, _cmd, frame, visible);
    } @finally {
        object_setIvar(self, numIv, number);
        object_setIvar(self, wdIv, weekday);
        if (monthIv) object_setIvar(self, monthIv, todayText);
        *todayPtr = today;
    }
    @try {
        // Ngữ cảnh đang vẽ là của lưới (CalendarMonthViewCalendar); cửa sổ để biết có bộ lọc đảo không
        UIView *canvas = nil;
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            if ([w isMemberOfClass:[UIWindow class]] && !w.hidden) {
                canvas = w;
                break;
            }
        }
        G6PadDrawLabels(self, frame, [weekday isKindOfClass:[NSString class]] ? weekday : nil, today != 0, canvas);
    } @catch (NSException *e) {
    }
}

// Tên tháng: đậm tối, viết hoa chữ đầu (chỉ đổi cách hiển thị)
static void G6PadStyleTitle(UIView *page) {
    Ivar iv = G6PadIvar(object_getClass(page), "_title", '@');
    UILabel *title = iv ? object_getIvar(page, iv) : nil;
    if (![title isKindOfClass:[UILabel class]]) return;
    NSArray *saved = objc_getAssociatedObject(title, &kTitleSavedKey);
    if (gActive) {
        if (!saved) {
            objc_setAssociatedObject(title, &kTitleSavedKey, @[title.font ?: [NSNull null], title.textColor ?: [NSNull null]],
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        UIFont *font = G6PadFont(G6FontBold, 34);
        if (font && ![title.font isEqual:font]) title.font = font;
        title.textColor = [UIColor colorWithWhite:0.08 alpha:1];
        NSString *text = title.text;
        if (text.length > 1) {
            NSString *head = [[text substringToIndex:1] uppercaseString];
            if (![head isEqualToString:[text substringToIndex:1]]) title.text = [head stringByAppendingString:[text substringFromIndex:1]];
        }
    } else if (saved) {
        if (saved[0] != [NSNull null]) title.font = saved[0];
        if (saved[1] != [NSNull null]) title.textColor = saved[1];
        objc_setAssociatedObject(title, &kTitleSavedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void (*orig_pageLayout)(UIView *, SEL);
static void repl_pageLayout(UIView *self, SEL _cmd) {
    orig_pageLayout(self, _cmd);
    @try {
        G6PadStyleTitle(self);
    } @catch (NSException *e) {
    }
}

static void (*orig_pageSetDate)(UIView *, SEL, G6PadDate, id, BOOL);
static void repl_pageSetDate(UIView *self, SEL _cmd, G6PadDate date, id zone, BOOL force) {
    orig_pageSetDate(self, _cmd, date, zone, force);
    @try {
        G6PadStyleTitle(self);
    } @catch (NSException *e) {
    }
}

// ---- Màn Ngày của iPad: khối âm lịch trên trang trái ----
// CalendarDayLeftPageView (trang trái của «cuốn sổ», máy ngang 492×648): _bigDateLabel / _secondDateLineLabel /
// _thirdDateLineLabel (ngày to, thứ + ngày, năm) bên trái, CalendarMiniMonth bên phải, _lineView (vạch ngang dưới cụm ngày),
// khung danh sách sự kiện (_detailView + bốn viền _top/_bottom/_left/_rightListBorder). Ngày đang hiện đến qua
// setDisplayedDate:timeZone:. Khối âm lịch ba dòng nằm giữa vạch và khung danh sách; khung danh sách được hạ xuống vừa đủ chỗ
// (mỗi lượt xếp của app đặt lại khung gốc — nhớ khung đã hạ để không hạ hai lần, tắt thì trả).

static char kPadDateKey, kPadLunarKey, kPadShiftKey;

@interface G6CalPadLunarView : UIView
@property(nonatomic, strong) NSDictionary *detail;
@end

@implementation G6CalPadLunarView

static CGFloat G6PadRun(NSString *text, UIFont *font, UIColor *color, CGFloat x, CGFloat y, CGFloat right) {
    if (!text.length || x >= right) return x;
    [color set];
    return x + [text drawInRect:CGRectMake(x, y, right - x, font.lineHeight) withFont:font lineBreakMode:NSLineBreakByTruncatingTail].width;
}

- (void)drawRect:(CGRect)rect {
    NSDictionary *x = self.detail;
    if (!x) return;
    CGRect b = self.bounds;
    CGFloat scale = self.window.screen.scale ?: [UIScreen mainScreen].scale;
    UIColor *primary = [UIColor colorWithWhite:0.08 alpha:1], *secondary = [UIColor colorWithWhite:0.45 alpha:1];
    BOOL good = [x[@"good"] boolValue];
    UIColor *tone = good ? G6LunarGoodColor() : secondary;
    CGFloat right = b.size.width;

    NSString *pill = good ? @"Hoàng đạo" : @"Hắc đạo";
    UIFont *pf = G6PadFont(G6FontSemiBold, 12);
    CGSize ps = [pill sizeWithFont:pf];
    CGRect pr = CGRectMake(right - ps.width - 18, 0, ps.width + 18, 21);
    [[tone colorWithAlphaComponent:0.14] setFill];
    [[UIBezierPath bezierPathWithRoundedRect:pr cornerRadius:10.5] fill];
    [tone set];
    [pill drawAtPoint:CGPointMake(round((pr.origin.x + 9) * scale) / scale, round(((21 - pf.lineHeight) / 2) * scale) / scale) withFont:pf];

    UIFont *f1 = G6PadFont(G6FontSemiBold, 16), *f = G6PadFont(G6FontRegular, 13.5), *fm = G6PadFont(G6FontMedium, 13.5);
    NSString *date = [NSString stringWithFormat:@"%@ tháng %@%@ năm %@", x[@"ld"], x[@"lm"], [x[@"leap"] boolValue] ? @" nhuận" : @"",
                                                x[@"can_chi_year"] ?: @""];
    CGFloat tx = G6PadRun(@"Âm lịch ", G6PadFont(G6FontRegular, 16), secondary, 0, 0, pr.origin.x - 8);
    tx = G6PadRun(date, f1, primary, tx, 0, pr.origin.x - 8);
    NSString *festival = [x[@"festival"] isKindOfClass:[NSString class]] ? x[@"festival"] : nil;
    if (festival.length) {
        tx = G6PadRun(@" · ", f1, secondary, tx, 0, pr.origin.x - 8);
        G6PadRun(festival, f1, G6LunarFestColor(), tx, 0, pr.origin.x - 8);
    }

    CGFloat y = 24;
    NSString *than = [x[@"than"] isKindOfClass:[NSString class]] ? x[@"than"] : nil;
    NSString *tiet = [x[@"tiet_khi"] isKindOfClass:[NSString class]] ? x[@"tiet_khi"] : nil;
    tx = G6PadRun([NSString stringWithFormat:@"Ngày %@ · tháng %@%@%@", x[@"can_chi_day"] ?: @"", x[@"can_chi_month"] ?: @"",
                                             tiet.length ? [@" · tiết " stringByAppendingString:tiet] : @"", than.length ? @" · " : @""],
                  f, secondary, 0, y, right);
    G6PadRun(than, fm, tone, tx, y, right);

    y += 19;
    NSArray *hours = [x[@"hours"] isKindOfClass:[NSArray class]] ? x[@"hours"] : @[];
    NSMutableArray *names = [NSMutableArray array];
    for (NSString *h in hours) {
        if (![h isKindOfClass:[NSString class]]) continue;
        NSRange r = [h rangeOfString:@" ("];
        [names addObject:r.location == NSNotFound ? h : [h substringToIndex:r.location]];
    }
    // Đủ chỗ thì kèm khung giờ («Tý (23–1)»), không thì chỉ tên chi
    NSString *full = [@"Giờ tốt: " stringByAppendingString:[hours componentsJoinedByString:@", "]];
    NSString *line = [full sizeWithFont:f].width <= right ? full : [@"Giờ tốt: " stringByAppendingString:[names componentsJoinedByString:@", "]];
    G6PadRun(line, f, secondary, 0, y, right);
}

@end

static const CGFloat kPadLunarHeight = 60;

static UIView *G6PadObj(id obj, const char *name) {
    Ivar iv = G6PadIvar(object_getClass(obj), name, '@');
    id v = iv ? object_getIvar(obj, iv) : nil;
    return [v isKindOfClass:[UIView class]] ? v : nil;
}

static void G6PadShift(UIView *v, CGFloat dy, BOOL shrink) {
    if (!v) return;
    CGRect f = v.frame;
    f.origin.y += dy;
    if (shrink) f.size.height -= dy;
    v.frame = f;
}

static void G6PadLayoutLunar(UIView *page) {
    UIView *line = G6PadObj(page, "_lineView"), *list = G6PadObj(page, "_detailView");
    UIView *top = G6PadObj(page, "_topListBorder"), *left = G6PadObj(page, "_leftListBorder"), *right = G6PadObj(page, "_rightListBorder");
    G6CalPadLunarView *block = objc_getAssociatedObject(page, &kPadLunarKey);
    NSNumber *date = objc_getAssociatedObject(page, &kPadDateKey);
    NSArray *shifted = objc_getAssociatedObject(page, &kPadShiftKey);  // @[khung danh sách sau khi hạ, số điểm đã hạ]
    // Lượt xếp vừa rồi của app có đặt lại khung gốc không (khung danh sách khác khung đã hạ = đã bị đặt lại)
    BOOL stillShifted = shifted && list && CGRectEqualToRect(list.frame, [shifted[0] CGRectValue]);
    CGFloat was = stillShifted ? [shifted[1] floatValue] : 0;
    NSDictionary *detail = nil;
    if (gActive && gLunar && date && line && list) {
        int v = date.intValue;
        detail = G6LunarDayDetail(v % 100, (v / 100) % 100, v / 10000);
    }
    if (!detail) {
        if (stillShifted) {
            G6PadShift(list, -was, YES);
            G6PadShift(top, -was, NO);
            G6PadShift(left, -was, YES);
            G6PadShift(right, -was, YES);
        }
        objc_setAssociatedObject(page, &kPadShiftKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        block.hidden = YES;
        return;
    }
    CGFloat blockTop = CGRectGetMaxY(line.frame) + 10;
    CGFloat listTop = (top ? top.frame.origin.y : list.frame.origin.y) - was;  // mép trên gốc của khung danh sách
    CGFloat need = MAX(0, blockTop + kPadLunarHeight + 8 - listTop);
    if (need > 90 || list.frame.size.height + was - need < 150) {
        // Không đủ chỗ (máy dựng đứng / trang hẹp): thôi khối âm lịch, trả khung danh sách
        if (stillShifted) {
            G6PadShift(list, -was, YES);
            G6PadShift(top, -was, NO);
            G6PadShift(left, -was, YES);
            G6PadShift(right, -was, YES);
        }
        objc_setAssociatedObject(page, &kPadShiftKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        block.hidden = YES;
        return;
    }
    CGFloat delta = need - was;
    if (fabs(delta) > 0.25) {
        G6PadShift(list, delta, YES);
        G6PadShift(top, delta, NO);
        G6PadShift(left, delta, YES);
        G6PadShift(right, delta, YES);
    }
    objc_setAssociatedObject(page, &kPadShiftKey, @[[NSValue valueWithCGRect:list.frame], @(need)], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!block) {
        block = [[G6CalPadLunarView alloc] initWithFrame:CGRectZero];
        block.opaque = NO;
        block.backgroundColor = [UIColor clearColor];
        block.contentMode = UIViewContentModeRedraw;
        block.userInteractionEnabled = NO;
        objc_setAssociatedObject(page, &kPadLunarKey, block, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (block.superview != page) [page addSubview:block];
    block.frame = CGRectMake(list.frame.origin.x, blockTop, list.frame.size.width, kPadLunarHeight);
    block.hidden = NO;
    if (block.detail != detail) {
        block.detail = detail;
        [block setNeedsDisplay];
    }
}

static void (*orig_leftPageLayout)(UIView *, SEL);
static void repl_leftPageLayout(UIView *self, SEL _cmd) {
    orig_leftPageLayout(self, _cmd);
    @try {
        G6PadLayoutLunar(self);
    } @catch (NSException *e) {
    }
}

static void (*orig_leftPageSetDate)(UIView *, SEL, G6PadDate, id);
static void repl_leftPageSetDate(UIView *self, SEL _cmd, G6PadDate date, id zone) {
    orig_leftPageSetDate(self, _cmd, date, zone);
    @try {
        if (date.month >= 1 && date.month <= 12 && date.day >= 1) {
            objc_setAssociatedObject(self, &kPadDateKey, @((date.year * 100 + date.month) * 100 + date.day), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        G6PadLayoutLunar(self);
    } @catch (NSException *e) {
    }
}

static void G6PadRefresh(UIView *view, Class pageClass, Class gridClass, Class leftClass, int depth) {
    if (pageClass && [view isKindOfClass:pageClass]) G6PadStyleTitle(view);
    if (leftClass && [view isKindOfClass:leftClass]) G6PadLayoutLunar(view);
    if (gridClass && [view isKindOfClass:gridClass]) {
        [view setNeedsDisplay];
        return;
    }
    if (depth <= 0) return;
    for (UIView *sub in view.subviews) G6PadRefresh(sub, pageClass, gridClass, leftClass, depth - 1);
}

void G6UIAppCalendarPadApply(BOOL active, BOOL lunar) {
    Class day = objc_getClass("CalendarMonthViewDay"), page = objc_getClass("CalendarMonthPageView");
    Class grid = objc_getClass("CalendarMonthViewCalendar"), leftPage = objc_getClass("CalendarDayLeftPageView");
    if (!day && !leftPage) return;
    static BOOL hooked;
    if (!hooked) {
        if (!active) return;
        hooked = YES;
        BOOL ok = day && G6Hook(day, sel_registerName("drawInFrame:visibleRect:"), (IMP)repl_dayDraw, (IMP *)&orig_dayDraw);
        BOOL left = leftPage && G6Hook(leftPage, @selector(layoutSubviews), (IMP)repl_leftPageLayout, (IMP *)&orig_leftPageLayout) &&
                    G6Hook(leftPage, sel_registerName("setDisplayedDate:timeZone:"), (IMP)repl_leftPageSetDate, (IMP *)&orig_leftPageSetDate);
        if (page) {
            G6Hook(page, @selector(layoutSubviews), (IMP)repl_pageLayout, (IMP *)&orig_pageLayout);
            G6Hook(page, sel_registerName("setDisplayedDate:timeZone:forceUpdate:"), (IMP)repl_pageSetDate, (IMP *)&orig_pageSetDate);
        }
        G6Log(@"lịch (app, iPad): lịch tháng %@, khối âm lịch màn Ngày %@%@", ok ? @"kiểu mới" : @"giữ nguyên (thiếu hàm vẽ ô)",
              left ? @"có" : @"không", lunar ? @" + âm lịch" : @"");
    }
    gActive = active;
    gLunar = lunar;
    for (UIWindow *window in [UIApplication sharedApplication].windows) G6PadRefresh(window, page, grid, leftPage, 14);
}

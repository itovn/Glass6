// Âm lịch Việt Nam cho app Lịch — xem G6UICalendarLunar.h.
//
// Mỗi tháng dương hỏi lõi MỘT lần («lunar.month» trả đủ ngày của tháng), giữ lại trong bộ đệm: lịch tháng vẽ 42 ô thuộc tối
// đa ba tháng, cuộn qua lại nhiều tháng cũng chỉ vài chục mục. Chi tiết một ngày («lunar.day») chỉ hỏi khi ngày được chọn.
#import "G6UICalendarLunar.h"

#import "G6Core.h"

static NSMutableDictionary *gMonths;  // @(năm·100 + tháng) → NSArray các ô (NSDictionary) theo ngày dương 1…n

static NSArray *G6LunarMonth(int m, int y) {
    if (m < 1 || m > 12 || y < 1800 || y > 2199) return nil;
    if (!gMonths) gMonths = [NSMutableDictionary dictionary];
    NSNumber *key = @(y * 100 + m);
    NSArray *days = gMonths[key];
    if (days) return days.count ? days : nil;
    NSDictionary *r = G6CoreCall(@{@"cmd" : @"lunar.month", @"month" : @(m), @"year" : @(y)});
    days = [r[@"ok"] boolValue] && [r[@"days"] isKindOfClass:[NSArray class]] ? r[@"days"] : @[];
    // Bộ đệm nhỏ: quá 36 tháng thì làm lại từ đầu (người dùng hiếm khi lật xa như vậy trong một lần mở app)
    if (gMonths.count > 36) [gMonths removeAllObjects];
    gMonths[key] = days;
    return days.count ? days : nil;
}

G6LunarCell G6LunarCellFor(int d, int m, int y) {
    G6LunarCell c = {0};
    NSArray *days = G6LunarMonth(m, y);
    if (d < 1 || d > (int)days.count) return c;
    NSDictionary *cell = days[d - 1];
    if (![cell isKindOfClass:[NSDictionary class]] || [cell[@"d"] intValue] != d) return c;
    c.valid = YES;
    c.ld = [cell[@"ld"] intValue];
    c.lm = [cell[@"lm"] intValue];
    c.ly = [cell[@"ly"] intValue];
    c.leap = [cell[@"leap"] boolValue];
    c.good = [cell[@"good"] boolValue];
    c.fest = [cell[@"fest"] boolValue];
    return c;
}

NSString *G6LunarShortText(G6LunarCell c, BOOL withMonth) {
    if (!c.valid) return nil;
    if (c.ld == 1 || withMonth) return [NSString stringWithFormat:@"%d/%d%@", c.ld, c.lm, c.leap ? @"N" : @""];
    return [NSString stringWithFormat:@"%d", c.ld];
}

NSDictionary *G6LunarDayDetail(int d, int m, int y) {
    static NSMutableDictionary *cache;
    if (!cache) cache = [NSMutableDictionary dictionary];
    NSNumber *key = @((y * 100 + m) * 100 + d);
    NSDictionary *day = cache[key];
    if (day) return day;
    NSDictionary *r = G6CoreCall(@{@"cmd" : @"lunar.day", @"day" : @(d), @"month" : @(m), @"year" : @(y)});
    day = [r[@"ok"] boolValue] && [r[@"day"] isKindOfClass:[NSDictionary class]] ? r[@"day"] : nil;
    if (!day) return nil;
    if (cache.count > 64) [cache removeAllObjects];
    cache[key] = day;
    return day;
}

// Thuật toán Sakamoto: 0 = Chủ nhật
int G6LunarWeekday(int d, int m, int y) {
    static const int t[] = {0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4};
    if (m < 3) y -= 1;
    return (y + y / 4 - y / 100 + y / 400 + t[(m - 1) % 12] + d) % 7;
}

UIColor *G6LunarGoodColor(void) {
    return [UIColor colorWithRed:0.82 green:0.47 blue:0.0 alpha:1];
}

UIColor *G6LunarFestColor(void) {
    return [UIColor colorWithRed:0.90 green:0.16 blue:0.12 alpha:1];
}

UIColor *G6LunarAccentColor(void) {
    return [UIColor colorWithRed:1.0 green:0.23 blue:0.19 alpha:1];
}

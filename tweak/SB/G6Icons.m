// Biểu tượng app — iOS 6 → kiểu iPadOS 26.
//
// SpringBoard iOS 6 tạo ảnh biểu tượng thế nào (tra trên máy 19/11/2026, lệnh thử `iconprobe` / `iconshot`):
//   -[SBIcon getIconImage:định dạng]            nhớ trong _cachedIconImages[12]; chưa có thì gọi generateIconImage:
//     -[SBApplicationIcon generateIconImage:]
//       -[SBApplicationIcon __loadIconImage:mã app format:scale:]
//         +[UIImage _applicationIconImageForBundleIdentifier:format:scale:]   ← MobileIcons: ảnh đã cắt góc + phủ lớp bóng
//                                                                               kính, nhớ trên đĩa (Caches/com.apple.IconsCache)
//   Định dạng 2 (màn hình chính, iPad @1x) là ảnh 74×78: biểu tượng 72×72 nằm ở (1, 2), bên dưới có bóng vẽ liền.
//   SBIconView: _shadow (UIImageView, ảnh riêng: 130×130 ở màn hình chính, 74×76 trong dock) nằm dưới SBIconImageView.
//   SBFolderIconView: _iconBackgroundView (ảnh 74×78 từ -_folderBackgroundImage) + lưới biểu tượng nhỏ.
//
// Cách làm — chèn ở TRÊN bộ nhớ đệm của MobileIcons nên bộ đệm trên đĩa vẫn là ảnh gốc của máy (gỡ Glass 6 là hết dấu):
//   - __loadIconImage:format:scale: → dựng ảnh mới cùng cỡ: lấy tệp ảnh gốc của app (chưa cắt, chưa phủ bóng kính) vẽ vào
//     đúng vùng chứa biểu tượng, lõi cắt theo hình bo góc liên tục + viền sáng. Không tìm được tệp gốc thì cắt lại từ ảnh
//     của máy (còn lớp bóng kính nhưng đúng hình).
//   - Vùng chứa biểu tượng của từng định dạng không ghi cứng: đo một lần bằng cách cho UIKit cắt một ảnh trắng.
//   - -[SBIconView _shadowImage] / _updateShadowFrameForShadow: → bóng đổ mềm của lõi, đặt quanh vùng chứa biểu tượng.
//   - -[SBFolderIconView _folderBackgroundImage] → ô kính cùng hình với biểu tượng.
//   - Ảnh đã dựng nhớ trên đĩa (Caches/Glass6/icons, tệp điểm ảnh thô ánh xạ vào bộ nhớ như bộ đệm của máy): tìm + đọc tệp
//     gốc của 60 app mất ~1 giây trên A5, có bộ đệm thì gần như không tốn gì. Tệp đệm gắn với dấu của ảnh máy tạo ra (app
//     đổi biểu tượng → ảnh của máy đổi → dựng lại) và dấu của kiểu dáng (đổi cấu hình / bản mới → dựng lại).
//   - Nhãn: SBIconView vẽ nhãn thành ảnh theo SBIconLabelImageParameters (gốc: Helvetica đậm 13, chữ trắng, bóng đen 60%
//     lệch 1 điểm, không nhoè). Đổi -font (Inter vừa 12,5), -shadowBlur, -shadowColor → chữ thanh hơn, bóng mềm.
//   - Bốn kiểu biểu tượng (khoá cấu hình `iconStyle`: 0 mặc định, 1 tối, 2 trong, 3 nhuộm màu + `iconTint`): lõi đổi màu
//     ảnh của app ngay trong g6_icon_render (đọc cấu hình hiện hành), vỏ ObjC chỉ cần tạo lại ảnh khi kiểu / màu đổi.
// Mọi hàm thay thế gọi hàm gốc trước và trả đúng kết quả gốc khi thành phần tắt. Ảnh biểu tượng có thể được tạo ở luồng nền
// nên phần dựng ảnh không đụng tới UIKit / đối tượng của SpringBoard.
#import "G6Icons.h"

#import <ImageIO/ImageIO.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <pthread.h>

#import "G6Clock.h"
#import "G6Core.h"
#import "G6Font.h"
#import "G6Glass.h"
#import "G6Hook.h"
#import "G6Log.h"
#import "G6Prefs.h"

#ifndef G6_VERSION
#define G6_VERSION "?"
#endif

// Định dạng ảnh của biểu tượng trên màn hình chính
static const int kHomeFormat = 2;
enum { kMaxFormat = 16, kMaxScale = 3 };

typedef struct {
    BOOL known;        // đã đo
    BOOL ok;           // là biểu tượng vuông bo góc → thay được
    int w, h;          // cỡ ảnh SpringBoard chờ nhận (điểm ảnh)
    int x, y, cw, ch;  // vùng chứa biểu tượng trong ảnh đó, gốc ở góc trên trái
} G6IconGeometry;

// Đọc ở mọi luồng, chỉ ghi ở luồng chính
static volatile BOOL gActive;
static volatile BOOL gDark;
// Tăng mỗi lần cấu hình đổi — ảnh nhớ lại (ô kính, bóng đổ) gắn số này để biết đã cũ
static volatile NSUInteger gGeneration;
static BOOL gPad;
static G6IconGeometry gGeometry[kMaxFormat][kMaxScale];
static pthread_mutex_t gGeometryLock = PTHREAD_MUTEX_INITIALIZER;

// Chỉ dùng ở luồng chính
static Class gIconViewClass, gFolderIconViewClass;
static NSString *gSignature;
static NSMutableDictionary *gTiles;
static UIImage *gShadow;
static CGFloat gShadowMargin;
static NSUInteger gShadowGeneration;
static BOOL gShadowDark;
static char kShadowMarginKey;

// Thời gian cộng dồn của hai bước dựng ảnh (để biết chỗ nào chậm) và số lần lấy được từ bộ đệm — số gần đúng, không khoá
static double gTimeLookup, gTimeCompose;
static unsigned gCacheHits;
// Dấu của kiểu dáng hiện hành (bản lõi, bản tweak, thông số kính) — tệp đệm khác dấu là tệp cũ
static volatile uint32_t gStyleHash;

// ---- Tiện ích ----

// Tỉ lệ màn hình — hỏi lần đầu lúc cần (luồng chính), không hỏi lúc nạp: khi đó UIKit của SpringBoard chưa khởi động xong
static CGFloat G6ScreenScale(void) {
    static CGFloat scale;
    if (scale < 1) scale = MAX([UIScreen mainScreen].scale, 1);
    return scale;
}

static id G6Get(id obj, NSString *selName) {
    SEL sel = NSSelectorFromString(selName);
    return [obj respondsToSelector:sel] ? ((id (*)(id, SEL))objc_msgSend)(obj, sel) : nil;
}

static void G6Do(id obj, NSString *selName) {
    SEL sel = NSSelectorFromString(selName);
    if ([obj respondsToSelector:sel]) ((void (*)(id, SEL))objc_msgSend)(obj, sel);
}

// Vùng vẽ BGRA nhân sẵn alpha; hàng đầu của vùng nhớ là hàng trên cùng của ảnh
static CGContextRef G6BitmapContext(void *data, size_t w, size_t h) {
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(data, w, h, 8, w * 4, cs, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    CGColorSpaceRelease(cs);
    return ctx;
}

// ---- Vùng chứa biểu tượng của từng định dạng ----

// Cho UIKit cắt một ảnh trắng đặc theo định dạng `format`: vùng đặc kín của kết quả chính là chỗ của biểu tượng.
static G6IconGeometry G6IconMeasure(int format, float scale) {
    G6IconGeometry g = {.known = YES};
    SEL sel = NSSelectorFromString(@"_applicationIconImageForFormat:precomposed:scale:");
    if (![UIImage instancesRespondToSelector:sel]) return g;
    const size_t n = 144;
    CGContextRef wctx = G6BitmapContext(NULL, n, n);
    if (!wctx) return g;
    CGContextSetRGBFillColor(wctx, 1, 1, 1, 1);
    CGContextFillRect(wctx, CGRectMake(0, 0, n, n));
    CGImageRef wcg = CGBitmapContextCreateImage(wctx);
    CGContextRelease(wctx);
    if (!wcg) return g;
    UIImage *white = [UIImage imageWithCGImage:wcg];
    CGImageRelease(wcg);
    UIImage *masked = ((id (*)(id, SEL, int, BOOL, float))objc_msgSend)(white, sel, format, YES, scale);
    CGImageRef cg = [masked isKindOfClass:[UIImage class]] ? masked.CGImage : NULL;
    if (!cg) return g;
    size_t w = CGImageGetWidth(cg), h = CGImageGetHeight(cg);
    if (!w || !h || w > 1024 || h > 1024) return g;
    NSMutableData *buf = [NSMutableData dataWithLength:w * h * 4];
    CGContextRef ctx = G6BitmapContext(buf.mutableBytes, w, h);
    if (!ctx) return g;
    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), cg);
    CGContextRelease(ctx);
    const uint8_t *p = buf.bytes;
    int x0 = (int)w, y0 = (int)h, x1 = -1, y1 = -1;
    for (int y = 0; y < (int)h; y++) {
        for (int x = 0; x < (int)w; x++) {
            // Bóng đổ vẽ liền quanh biểu tượng luôn nhạt hơn mức này
            if (p[((size_t)y * w + x) * 4 + 3] < 250) continue;
            if (x < x0) x0 = x;
            if (x > x1) x1 = x;
            if (y < y0) y0 = y;
            if (y > y1) y1 = y;
        }
    }
    g.w = (int)w;
    g.h = (int)h;
    if (x1 < 0) return g;
    g.x = x0;
    g.y = y0;
    g.cw = x1 - x0 + 1;
    g.ch = y1 - y0 + 1;
    // Chỉ nhận ô vuông chiếm phần đáng kể của ảnh (loại định dạng «tài liệu» có góc gấp)
    g.ok = abs(g.cw - g.ch) <= 1 && g.cw >= 12 && g.cw * g.ch * 100 >= 30 * g.w * g.h;
    return g;
}

static G6IconGeometry G6IconGeometryFor(int format, float scale) {
    G6IconGeometry none = {0};
    int si = (int)lroundf(scale) - 1;
    if (format < 0 || format >= kMaxFormat || si < 0 || si >= kMaxScale) return none;
    pthread_mutex_lock(&gGeometryLock);
    G6IconGeometry g = gGeometry[format][si];
    if (!g.known) {
        @try {
            g = G6IconMeasure(format, scale);
        } @catch (NSException *e) {
            g = none;
            g.known = YES;
        }
        gGeometry[format][si] = g;
        G6Log(@"biểu tượng: định dạng %d @%dx → ảnh %d×%d, biểu tượng %d×%d ở (%d, %d)%@", format, si + 1, g.w, g.h, g.cw, g.ch, g.x,
              g.y, g.ok ? @"" : @" — không thay");
    }
    pthread_mutex_unlock(&gGeometryLock);
    return g;
}

// ---- Tệp ảnh gốc của app ----

static void G6AddNames(NSMutableArray *names, id value) {
    if ([value isKindOfClass:[NSString class]]) {
        if ([value length] && ![names containsObject:value]) [names addObject:value];
    } else if ([value isKindOfClass:[NSArray class]]) {
        for (id v in value) G6AddNames(names, v);
    }
}

// Các tệp có thể ứng với một tên ảnh ghi trong Info.plist («Icon-72», «Icon.png»…): thêm đuôi @2x / ~ipad
static void G6AddCandidates(NSMutableArray *paths, NSString *dir, NSString *name) {
    // Tên có dấu «/» hoặc «..» là tệp ngoài gói app — không đọc
    if ([name rangeOfString:@"/"].location != NSNotFound || [name rangeOfString:@".."].location != NSNotFound) return;
    NSString *ext = name.pathExtension.length ? name.pathExtension : @"png";
    NSString *base = name.pathExtension.length ? name.stringByDeletingPathExtension : name;
    NSMutableArray *variants = [NSMutableArray array];
    BOOL has2x = [base rangeOfString:@"@2x"].location != NSNotFound, hasIdiom = [base rangeOfString:@"~"].location != NSNotFound;
    NSString *idiom = gPad ? @"~ipad" : @"~iphone";
    // Bản riêng cho loại máy đứng trước: hai ảnh cùng cỡ thì ảnh gặp trước được chọn
    if (!hasIdiom) [variants addObject:[base stringByAppendingString:idiom]];
    [variants addObject:base];
    if (!has2x && !hasIdiom) {
        [variants addObject:[NSString stringWithFormat:@"%@@2x%@", base, idiom]];
        [variants addObject:[base stringByAppendingString:@"@2x"]];
    }
    for (NSString *v in variants) {
        NSString *path = [dir stringByAppendingPathComponent:[v stringByAppendingPathExtension:ext]];
        if (![paths containsObject:path]) [paths addObject:path];
    }
}

// Trong các tệp ứng viên, chọn ảnh vuông nhỏ nhất mà vẫn ≥ `wantPx` (không có thì ảnh lớn nhất). Trả ảnh đã mở, hoặc NULL.
static CGImageRef G6CopyBestImage(NSArray *paths, int wantPx) CF_RETURNS_RETAINED {
    CGImageSourceRef best = NULL;
    int bestPx = 0;
    for (NSString *path in paths) {
        CGImageSourceRef src = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], NULL);
        if (!src) continue;
        NSDictionary *props = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(src, 0, NULL));
        int pw = [props[(__bridge id)kCGImagePropertyPixelWidth] intValue], ph = [props[(__bridge id)kCGImagePropertyPixelHeight] intValue];
        BOOL better = NO;
        if (pw >= 16 && abs(pw - ph) <= 2) {
            if (!best) better = YES;
            else if (bestPx < wantPx) better = pw > bestPx;
            else better = pw >= wantPx && pw < bestPx;
        }
        if (better) {
            if (best) CFRelease(best);
            best = src;
            bestPx = pw;
        } else {
            CFRelease(src);
        }
    }
    if (!best) return NULL;
    CGImageRef img = CGImageSourceCreateImageAtIndex(best, 0, NULL);
    CFRelease(best);
    return img;
}

// Ảnh biểu tượng gốc của app (tệp trong gói app: chưa cắt góc, chưa phủ lớp bóng kính). Gọi được từ luồng nền: chỉ hỏi
// LaunchServices và đọc tệp.
static CGImageRef G6CopyAppSource(NSString *bundleID, int wantPx) CF_RETURNS_RETAINED {
    Class LS = objc_getClass("LSApplicationProxy");
    SEL make = NSSelectorFromString(@"applicationProxyForIdentifier:");
    if (!LS || ![LS respondsToSelector:make] || ![bundleID isKindOfClass:[NSString class]]) return NULL;
    id proxy = ((id (*)(id, SEL, id))objc_msgSend)(LS, make, bundleID);
    NSURL *url = G6Get(proxy, @"boundResourcesDirectoryURL") ?: G6Get(proxy, @"resourcesDirectoryURL") ?: G6Get(proxy, @"bundleURL");
    NSString *dir = [url isKindOfClass:[NSURL class]] ? url.path : nil;
    if (!dir.length) return NULL;

    // Tên ảnh app khai: LaunchServices đã đọc sẵn + các khoá của Info.plist (bản riêng cho iPad đứng trước)
    NSMutableArray *names = [NSMutableArray array];
    G6AddNames(names, G6Get(proxy, @"boundIconFileNames"));
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[dir stringByAppendingPathComponent:@"Info.plist"]];
    for (NSString *suffix in @[gPad ? @"~ipad" : @"~iphone", @""]) {
        id icons = info[[@"CFBundleIcons" stringByAppendingString:suffix]];
        if ([icons isKindOfClass:[NSDictionary class]]) {
            id primary = icons[@"CFBundlePrimaryIcon"];
            if ([primary isKindOfClass:[NSDictionary class]]) G6AddNames(names, primary[@"CFBundleIconFiles"]);
        }
        G6AddNames(names, info[[@"CFBundleIconFiles" stringByAppendingString:suffix]]);
        G6AddNames(names, info[[@"CFBundleIconFile" stringByAppendingString:suffix]]);
    }
    NSMutableArray *paths = [NSMutableArray array];
    for (NSString *name in names) G6AddCandidates(paths, dir, name);
    CGImageRef img = G6CopyBestImage(paths, wantPx);
    if (img) return img;
    // App không khai gì: tên mặc định của iOS
    [paths removeAllObjects];
    for (NSString *name in @[@"Icon", @"icon", @"Icon-72", @"Icon-76", @"Icon-60"]) G6AddCandidates(paths, dir, name);
    return G6CopyBestImage(paths, wantPx);
}

// ---- Bộ nhớ đệm trên đĩa ----

static NSString *const kCacheDir = @"/var/mobile/Library/Caches/Glass6/icons";
// «G6CI»
enum { kCacheMagic = 0x49433647, kCacheVersion = 1 };

// Đầu tệp đệm (32 byte), theo sau là h hàng × w × 4 byte BGRA nhân sẵn alpha
typedef struct {
    uint32_t magic, version, w, h;
    uint64_t origHash;
    uint32_t style, reserved;
} G6IconCacheHeader;

// Dấu (FNV-1a 64 bit, mỗi lần 4 byte) của điểm ảnh ảnh máy tạo ra — ảnh đổi thì biết biểu tượng của app đã đổi
static uint64_t G6HashImage(CGImageRef cg) {
    CFDataRef data = CGDataProviderCopyData(CGImageGetDataProvider(cg));
    if (!data) return 0;
    uint64_t h = 1469598103934665603ULL ^ ((uint64_t)CGImageGetWidth(cg) << 32 | CGImageGetHeight(cg));
    const uint8_t *p = CFDataGetBytePtr(data);
    size_t n = (size_t)CFDataGetLength(data) / 4;
    for (size_t i = 0; i < n; i++) {
        uint32_t word;
        memcpy(&word, p + i * 4, 4);
        h = (h ^ word) * 1099511628211ULL;
    }
    CFRelease(data);
    return h ? h : 1;
}

static uint32_t G6HashString(NSString *s) {
    uint32_t h = 2166136261u;
    for (const char *p = s.UTF8String ?: ""; *p; p++) h = (h ^ (uint8_t)*p) * 16777619u;
    return h;
}

// nil = không nhớ được (mã app có ký tự lạ)
static NSString *G6IconCachePath(NSString *bundleID, int format, CGFloat scale) {
    static NSCharacterSet *bad;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        bad = [[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_"] invertedSet];
    });
    if (!bundleID.length || bundleID.length > 150 || [bundleID rangeOfCharacterFromSet:bad].location != NSNotFound) return nil;
    return [NSString stringWithFormat:@"%@/%@~%d@%dx~%@.g6i", kCacheDir, bundleID, format, (int)lround(scale), gDark ? @"d" : @"l"];
}

static UIImage *G6IconCacheRead(NSString *path, G6IconGeometry g, CGFloat scale, uint64_t origHash) {
    NSData *file = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:NULL];
    G6IconCacheHeader hd;
    if (file.length != sizeof(hd) + (size_t)g.w * g.h * 4) return nil;
    memcpy(&hd, file.bytes, sizeof(hd));
    if (hd.magic != kCacheMagic || hd.version != kCacheVersion || hd.w != (uint32_t)g.w || hd.h != (uint32_t)g.h ||
        hd.origHash != origHash || hd.style != gStyleHash) {
        return nil;
    }
    return G6ImageFromPixelsAt(file, sizeof(hd), (uint32_t)g.w, (uint32_t)g.h, scale);
}

// Ghi ở luồng nền (không vội); ghi qua tệp tạm rồi đổi tên nên tệp đang được ánh xạ vẫn nguyên vẹn
static void G6IconCacheWrite(NSString *path, G6IconGeometry g, uint64_t origHash, NSData *pixels) {
    G6IconCacheHeader hd = {kCacheMagic, kCacheVersion, (uint32_t)g.w, (uint32_t)g.h, origHash, gStyleHash, 0};
    NSMutableData *file = [NSMutableData dataWithBytes:&hd length:sizeof(hd)];
    [file appendData:pixels];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            [[NSFileManager defaultManager] createDirectoryAtPath:kCacheDir withIntermediateDirectories:YES attributes:nil error:NULL];
        });
        [file writeToFile:path atomically:YES];
    });
}

// Bỏ tệp đệm của app không còn trên máy. `known` = mã của mọi biểu tượng đang có.
static void G6IconCachePrune(NSSet *known) {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        NSFileManager *fm = [NSFileManager defaultManager];
        NSUInteger removed = 0;
        for (NSString *name in [fm contentsOfDirectoryAtPath:kCacheDir error:NULL]) {
            NSRange tilde = [name rangeOfString:@"~"];
            if (tilde.location == NSNotFound || [known containsObject:[name substringToIndex:tilde.location]]) continue;
            if ([fm removeItemAtPath:[kCacheDir stringByAppendingPathComponent:name] error:NULL]) removed++;
        }
        if (removed) G6Log(@"biểu tượng: bỏ %lu tệp đệm của app đã gỡ", (unsigned long)removed);
    });
}

// ---- Dựng ảnh ----

// Ô kính cỡ `w × h` điểm ảnh, cùng hình với biểu tượng (BGRA nhân sẵn alpha, mỗi hàng w × 4 byte). Kính giả — không có nền
// mờ: biểu tượng trượt theo trang còn hình nền đứng yên, nên để hình nền thật lọt qua. Nhớ lại ô gần nhất; gọi được từ mọi luồng.
static NSData *G6TilePixels(int w, int h, CGFloat scale, BOOL dark) {
    static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
    static NSData *cached;
    static NSString *cachedKey;
    NSString *key = [NSString stringWithFormat:@"%d|%d|%.0f|%d|%lu", w, h, scale, dark, (unsigned long)gGeneration];
    pthread_mutex_lock(&lock);
    NSData *tile = [key isEqualToString:cachedKey] ? cached : nil;
    pthread_mutex_unlock(&lock);
    if (tile) return tile;
    NSMutableData *buf = [NSMutableData dataWithLength:(size_t)w * h * 4];
    if (G6CoreGlassRender("icon", (uint32_t)w, (uint32_t)h, (float)scale, dark, NULL, NULL, buf.mutableBytes, (uint32_t)w * 4) != 0) return nil;
    pthread_mutex_lock(&lock);
    cached = buf;
    cachedKey = key;
    pthread_mutex_unlock(&lock);
    return buf;
}

// Biểu tượng có nền trong suốt (hình tròn, hình rời…): đặt lên ô kính để mọi biểu tượng cùng một hình. `content` là vùng
// chứa biểu tượng đã qua lõi cắt hình. Ảnh kín (hoặc gần kín) thì giữ nguyên.
static void G6IconBackWithTile(uint8_t *content, size_t stride, G6IconGeometry g, CGFloat scale) {
    NSData *tileData = G6TilePixels(g.cw, g.ch, scale, gDark);
    if (!tileData) return;
    const uint8_t *tile = tileData.bytes;
    size_t inside = 0, clear = 0;
    for (int y = 0; y < g.ch; y++) {
        const uint8_t *s = content + (size_t)y * stride, *t = tile + (size_t)y * g.cw * 4;
        for (int x = 0; x < g.cw; x++) {
            // Chỉ xét điểm nằm hẳn trong hình (alpha của ô kính ở đó là mức đục của kính, luôn > 0)
            if (t[x * 4 + 3] < 96) continue;
            inside++;
            if (s[x * 4 + 3] < 128) clear++;
        }
    }
    // Dưới 4% diện tích: coi như ảnh kín (góc bo sẵn của nhà phát triển…)
    if (!inside || clear * 25 < inside) return;
    for (int y = 0; y < g.ch; y++) {
        uint8_t *s = content + (size_t)y * stride;
        const uint8_t *t = tile + (size_t)y * g.cw * 4;
        for (int x = 0; x < g.cw * 4; x += 4) {
            unsigned k = 255 - s[x + 3];
            if (!k) continue;
            // Biểu tượng đè lên ô kính (cả hai đã nhân sẵn alpha)
            for (int c = 0; c < 4; c++) s[x + c] = (uint8_t)MIN(255u, s[x + c] + (t[x + c] * k + 127) / 255);
        }
    }
}

// Vẽ `src` (cả ảnh, hoặc vùng `crop` nếu không rỗng) vào vùng chứa biểu tượng của một ảnh cỡ `g`, rồi nhờ lõi cắt hình.
// Trả điểm ảnh của cả ảnh (g.w × g.h).
static NSData *G6IconCompose(CGImageRef src, CGRect crop, G6IconGeometry g, CGFloat scale) {
    if (!src || !g.ok) return nil;
    size_t stride = (size_t)g.w * 4;
    NSMutableData *buf = [NSMutableData dataWithLength:stride * g.h];
    CGContextRef ctx = G6BitmapContext(buf.mutableBytes, g.w, g.h);
    if (!ctx) return nil;
    CGImageRef part = CGRectIsEmpty(crop) ? NULL : CGImageCreateWithImageInRect(src, crop);
    CGContextSetInterpolationQuality(ctx, kCGInterpolationHigh);
    // Toạ độ của CoreGraphics: gốc ở góc dưới trái
    CGContextDrawImage(ctx, CGRectMake(g.x, g.h - g.y - g.ch, g.cw, g.ch), part ?: src);
    if (part) CGImageRelease(part);
    CGContextRelease(ctx);
    uint8_t *content = (uint8_t *)buf.mutableBytes + (size_t)g.y * stride + (size_t)g.x * 4;
    int rc = G6CoreIconRender(content, (uint32_t)g.cw, (uint32_t)g.ch, (uint32_t)stride, (float)scale, gDark);
    if (rc != 0) {
        G6Log(@"biểu tượng: lõi báo lỗi %d", rc);
        return nil;
    }
    G6IconBackWithTile(content, stride, g, scale);
    return buf;
}

// Ảnh mới thay cho `orig` (ảnh SpringBoard vừa tạo cho định dạng `format`). `bundleID` nil = không tìm tệp gốc;
// `cacheID` nil = không nhớ trên đĩa. Trả nil = giữ ảnh của máy.
static UIImage *G6IconRestyle(UIImage *orig, NSString *bundleID, NSString *cacheID, int format) {
    CGImageRef ocg = orig.CGImage;
    if (!ocg) return nil;
    CGFloat scale = orig.scale >= 1 ? orig.scale : 1;
    G6IconGeometry g = G6IconGeometryFor(format, (float)scale);
    if (!g.ok || (int)CGImageGetWidth(ocg) != g.w || (int)CGImageGetHeight(ocg) != g.h) return nil;
    // Đã dựng lần trước và ảnh của máy chưa đổi: lấy từ bộ đệm
    NSString *cachePath = cacheID ? G6IconCachePath(cacheID, format, scale) : nil;
    uint64_t hash = cachePath ? G6HashImage(ocg) : 0;
    if (hash) {
        UIImage *hit = G6IconCacheRead(cachePath, g, scale, hash);
        if (hit) {
            gCacheHits++;
            return hit;
        }
    }
    NSData *out = nil;
    if (bundleID) {
        double t0 = G6NowMs();
        CGImageRef src = G6CopyAppSource(bundleID, MAX(g.cw, g.ch));
        double t1 = G6NowMs();
        if (src) {
            out = G6IconCompose(src, CGRectZero, g, scale);
            CGImageRelease(src);
        }
        gTimeLookup += t1 - t0;
        gTimeCompose += G6NowMs() - t1;
    }
    // Không có tệp gốc: cắt lại từ ảnh của máy (hình mới nằm lọt trong hình cũ)
    if (!out) out = G6IconCompose(ocg, CGRectMake(g.x, g.y, g.cw, g.ch), g, scale);
    if (!out) return nil;
    if (hash) G6IconCacheWrite(cachePath, g, hash, out);
    return G6ImageFromPixels(out, (uint32_t)g.w, (uint32_t)g.h, scale);
}

// ---- Cho thành phần khác ----

int G6IconContentPixels(int format, CGFloat scale) {
    G6IconGeometry g = G6IconGeometryFor(format, (float)scale);
    return g.ok ? MAX(g.cw, g.ch) : 0;
}

CGRect G6IconContentRect(int format, CGFloat scale) {
    G6IconGeometry g = G6IconGeometryFor(format, (float)scale);
    if (!g.ok || scale < 1) return CGRectZero;
    return CGRectMake(g.x / scale, g.y / scale, g.cw / scale, g.ch / scale);
}

UIImage *G6IconImageFromSource(CGImageRef src, int format, CGFloat scale) {
    if (!src) return nil;
    if (gActive) {
        G6IconGeometry g = G6IconGeometryFor(format, (float)scale);
        NSData *pixels = g.ok ? G6IconCompose(src, CGRectZero, g, scale) : nil;
        if (pixels) return G6ImageFromPixels(pixels, (uint32_t)g.w, (uint32_t)g.h, scale);
    }
    // Kiểu gốc của máy: UIKit cắt góc và thêm bóng vẽ liền; «precomposed» = không phủ lớp bóng kính
    SEL sel = NSSelectorFromString(@"_applicationIconImageForFormat:precomposed:scale:");
    if (![UIImage instancesRespondToSelector:sel]) return nil;
    UIImage *masked = ((id (*)(id, SEL, int, BOOL, float))objc_msgSend)([UIImage imageWithCGImage:src], sel, format, YES, (float)scale);
    return [masked isKindOfClass:[UIImage class]] ? masked : nil;
}

// ---- Hàm thay thế ----

static id (*o_loadIconImage)(id, SEL, id, int, float);
static id g6_loadIconImage(id self, SEL _cmd, NSString *bundleID, int format, float scale) {
    UIImage *orig = o_loadIconImage(self, _cmd, bundleID, format, scale);
    if (![orig isKindOfClass:[UIImage class]]) return orig;
    // Biểu tượng Đồng hồ sống tự vẽ ảnh của mình (kể cả khi «Biểu tượng kiểu mới» tắt)
    UIImage *clock = nil;
    @autoreleasepool {
        @try {
            clock = G6ClockIconImage(bundleID, format, orig);
        } @catch (NSException *e) {
            G6Log(@"đồng hồ: lỗi khi vẽ ảnh: %@", e);
        }
    }
    if (clock) return clock;
    if (!gActive) return orig;
    UIImage *mine = nil;
    @autoreleasepool {
        @try {
            // Biểu tượng Thời tiết đổi theo vai (°C / °F) — tệp gốc tự tìm có thể lệch, dùng ảnh của máy
            BOOL plain = ![self isKindOfClass:objc_getClass("SBWeatherApplicationIcon")];
            mine = G6IconRestyle(orig, plain ? bundleID : nil, bundleID, format);
        } @catch (NSException *e) {
            G6Log(@"biểu tượng «%@»: %@", bundleID, e);
        }
    }
    return mine ?: orig;
}

// Biểu tượng trang web lưu ra màn hình chính
static id (*o_bookmarkImage)(id, SEL, int);
static id g6_bookmarkImage(id self, SEL _cmd, int format) {
    UIImage *orig = o_bookmarkImage(self, _cmd, format);
    if (!gActive || ![orig isKindOfClass:[UIImage class]]) return orig;
    UIImage *mine = nil;
    @autoreleasepool {
        @try {
            mine = G6IconRestyle(orig, nil, nil, format);
        } @catch (NSException *e) {
        }
    }
    return mine ?: orig;
}

// Vùng chứa biểu tượng (toạ độ điểm) trong một view đang hiện ảnh định dạng màn hình chính
static BOOL G6ContentRect(UIView *imageView, CGRect *out) {
    CGFloat s = G6ScreenScale();
    G6IconGeometry g = G6IconGeometryFor(kHomeFormat, (float)s);
    CGSize size = imageView.bounds.size;
    if (!g.ok || lround(size.width * s) != g.w || lround(size.height * s) != g.h) return NO;
    CGPoint o = imageView.frame.origin;
    *out = CGRectMake(o.x + g.x / s, o.y + g.y / s, g.cw / s, g.ch / s);
    return YES;
}

static UIImage *G6IconShadow(void) {
    if (gShadow && gShadowGeneration == gGeneration && gShadowDark == gDark) return gShadow;
    CGFloat s = G6ScreenScale();
    G6IconGeometry g = G6IconGeometryFor(kHomeFormat, (float)s);
    if (!g.ok) return nil;
    CGFloat margin = 0;
    UIImage *img = G6ShadowImage(@"icon", CGSizeMake(g.cw / s, g.ch / s), gDark, &margin);
    if (!img) return nil;
    // Bản riêng để gắn dấu «của Glass 6» + lề (ảnh trong bộ nhớ đệm của G6ShadowImage dùng chung)
    img = [UIImage imageWithCGImage:img.CGImage scale:img.scale orientation:UIImageOrientationUp];
    objc_setAssociatedObject(img, &kShadowMarginKey, @(margin), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    gShadow = img;
    gShadowMargin = margin;
    gShadowGeneration = gGeneration;
    gShadowDark = gDark;
    return img;
}

static id (*o_shadowImage)(id, SEL);
static id g6_shadowImage(id self, SEL _cmd) {
    id orig = o_shadowImage(self, _cmd);
    // Hàm gốc trả nil = biểu tượng này không có bóng: giữ nguyên
    if (!gActive || !orig) return orig;
    return G6IconShadow() ?: orig;
}

// Đặt bóng đổ của Glass 6 quanh vùng chứa biểu tượng. Bóng và ảnh biểu tượng cùng nằm trong _iconImageContainer; lúc hàm
// này chạy bóng có thể chưa được gắn vào view cha.
static void G6PlaceShadow(UIView *iconView, UIImageView *shadow) {
    if (![shadow isKindOfClass:[UIImageView class]]) return;
    NSNumber *margin = objc_getAssociatedObject(shadow.image, &kShadowMarginKey);
    if (!margin) return;
    // Thư mục: ảnh cỡ đầy đủ là ô nền; SBIconImageView của nó chỉ là lưới biểu tượng nhỏ
    UIView *ref = [iconView isKindOfClass:gFolderIconViewClass] ? G6Get(iconView, @"iconBackgroundView") : G6Get(iconView, @"iconImageView");
    CGRect content;
    if (![ref isKindOfClass:[UIView class]] || !G6ContentRect(ref, &content)) return;
    CGFloat m = margin.floatValue;
    shadow.frame = CGRectInset(content, -m, -m);
}

static Ivar gShadowIvar;

static void (*o_updateShadowFrame)(id, SEL, id);
static void g6_updateShadowFrame(UIView *self, SEL _cmd, UIImageView *shadow) {
    o_updateShadowFrame(self, _cmd, shadow);
    G6PlaceShadow(self, shadow);
}

// SpringBoard đặt khung bóng ở vài chỗ khác nhau (tạo bóng, đổi chỗ biểu tượng, xếp lại ảnh) — chặn ở chỗ cuối cùng
static void (*o_updateShadow)(id, SEL);
static void g6_updateShadow(UIView *self, SEL _cmd) {
    o_updateShadow(self, _cmd);
    if (gShadowIvar) G6PlaceShadow(self, object_getIvar(self, gShadowIvar));
}

static void (*o_updateShadowFrame0)(id, SEL);
static void g6_updateShadowFrame0(UIView *self, SEL _cmd) {
    o_updateShadowFrame0(self, _cmd);
    if (gShadowIvar) G6PlaceShadow(self, object_getIvar(self, gShadowIvar));
}

static void (*o_positionIconImageView)(id, SEL);
static void g6_positionIconImageView(UIView *self, SEL _cmd) {
    o_positionIconImageView(self, _cmd);
    if (gShadowIvar) G6PlaceShadow(self, object_getIvar(self, gShadowIvar));
}

// Thư mục / Quầy báo: bóng được tạo trước khi có ô nền (lúc đó chưa biết đặt bóng vào đâu — đã gặp: bóng lệch sang trái
// cho tới lần xếp lại kế tiếp). Gắn biểu tượng xong là có ô nền → đặt lại.
static void (*o_folderSetIcon)(id, SEL, id);
static void g6_folderSetIcon(UIView *self, SEL _cmd, id icon) {
    o_folderSetIcon(self, _cmd, icon);
    if (gShadowIvar) G6PlaceShadow(self, object_getIvar(self, gShadowIvar));
}

// Ô kính làm nền cho biểu tượng thư mục: cùng cỡ ảnh, cùng vùng, cùng hình với biểu tượng app
static UIImage *G6FolderTile(UIImage *orig) {
    CGImageRef ocg = orig.CGImage;
    if (!ocg) return nil;
    CGFloat scale = orig.scale >= 1 ? orig.scale : 1;
    G6IconGeometry g = G6IconGeometryFor(kHomeFormat, (float)scale);
    if (!g.ok || (int)CGImageGetWidth(ocg) != g.w || (int)CGImageGetHeight(ocg) != g.h) return nil;
    NSString *key = [NSString stringWithFormat:@"%d|%d|%d|%lu", g.w, g.h, gDark, (unsigned long)gGeneration];
    UIImage *tile = gTiles[key];
    if (tile) return tile;
    NSData *pixels = G6TilePixels(g.cw, g.ch, scale, gDark);
    if (!pixels) return nil;
    size_t stride = (size_t)g.w * 4, row = (size_t)g.cw * 4;
    NSMutableData *buf = [NSMutableData dataWithLength:stride * g.h];
    uint8_t *content = (uint8_t *)buf.mutableBytes + (size_t)g.y * stride + (size_t)g.x * 4;
    for (int y = 0; y < g.ch; y++) memcpy(content + (size_t)y * stride, (const uint8_t *)pixels.bytes + (size_t)y * row, row);
    tile = G6ImageFromPixels(buf, (uint32_t)g.w, (uint32_t)g.h, scale);
    if (!tile) return nil;
    if (!gTiles) gTiles = [NSMutableDictionary dictionary];
    [gTiles removeAllObjects];
    gTiles[key] = tile;
    return tile;
}

static id (*o_folderBackground)(id, SEL);
static id g6_folderBackground(id self, SEL _cmd) {
    UIImage *orig = o_folderBackground(self, _cmd);
    // Quầy báo (SBNewsstandIconView) là lớp con, có kệ gỗ riêng — chưa đụng
    if (!gActive || ![orig isKindOfClass:[UIImage class]] || [self class] != gFolderIconViewClass) return orig;
    return G6FolderTile(orig) ?: orig;
}

// Quầy báo (SBNewsstandIconView, lớp con của thư mục): nền là kệ gỗ, phía trước là khung viền gỗ theo hình góc cũ.
// Cắt kệ gỗ theo hình mới và bỏ khung viền.
static UIImage *gNewsstandBg, *gNewsstandFg;
static NSUInteger gNewsstandGeneration;

static void G6NewsstandForget(void) {
    if (gNewsstandGeneration == gGeneration) return;
    gNewsstandBg = gNewsstandFg = nil;
    gNewsstandGeneration = gGeneration;
}

static id (*o_newsstandBackground)(id, SEL);
static id g6_newsstandBackground(id self, SEL _cmd) {
    UIImage *orig = o_newsstandBackground(self, _cmd);
    if (!gActive || ![orig isKindOfClass:[UIImage class]]) return orig;
    G6NewsstandForget();
    if (!gNewsstandBg) gNewsstandBg = G6IconRestyle(orig, nil, nil, kHomeFormat);
    return gNewsstandBg ?: orig;
}

static id (*o_newsstandForeground)(id, SEL);
static id g6_newsstandForeground(id self, SEL _cmd) {
    UIImage *orig = o_newsstandForeground(self, _cmd);
    if (!gActive || ![orig isKindOfClass:[UIImage class]] || !o_newsstandBackground) return orig;
    G6NewsstandForget();
    if (!gNewsstandFg) {
        // Ảnh trong suốt cùng cỡ (SpringBoard lấy khung của view từ cỡ ảnh)
        CGImageRef cg = orig.CGImage;
        uint32_t w = (uint32_t)CGImageGetWidth(cg), h = (uint32_t)CGImageGetHeight(cg);
        if (w && h && w <= 1024 && h <= 1024) {
            gNewsstandFg = G6ImageFromPixels([NSMutableData dataWithLength:(size_t)w * h * 4], w, h, orig.scale >= 1 ? orig.scale : 1);
        }
    }
    return gNewsstandFg ?: orig;
}

// ---- Nhãn ----

// Cỡ chữ nhãn (điểm). Inter có chiều cao chữ thường lớn hơn Helvetica nên cỡ nhỏ hơn một chút mà vẫn dễ đọc bằng.
static const CGFloat kLabelFontSize = 12.5;
static const float kLabelShadowBlur = 3.5;

static id (*o_labelFont)(id, SEL);
static id g6_labelFont(id self, SEL _cmd) {
    id orig = o_labelFont(self, _cmd);
    if (!gActive || !G6FontAvailable()) return orig;
    return G6Font(G6FontMedium, kLabelFontSize) ?: orig;
}

static float (*o_labelShadowBlur)(id, SEL);
static float g6_labelShadowBlur(id self, SEL _cmd) {
    float orig = o_labelShadowBlur(self, _cmd);
    return gActive ? kLabelShadowBlur : orig;
}

// Bóng nhoè loãng hơn bóng cứng cùng độ đậm → tăng độ đậm để chữ vẫn nổi trên hình nền sáng
static id G6LabelShadowColor(id orig) {
    return gActive ? [UIColor colorWithWhite:0 alpha:0.9] : orig;
}

static id (*o_labelShadowColor)(id, SEL);
static id g6_labelShadowColor(id self, SEL _cmd) {
    return G6LabelShadowColor(o_labelShadowColor(self, _cmd));
}

// Nhãn trong dock có bản riêng của -shadowColor
static id (*o_dockLabelShadowColor)(id, SEL);
static id g6_dockLabelShadowColor(id self, SEL _cmd) {
    return G6LabelShadowColor(o_dockLabelShadowColor(self, _cmd));
}

// SpringBoard nhớ ảnh nhãn theo bộ thông số (chữ, cỡ tối đa…): hai bộ bằng nhau thì dùng chung một ảnh. Phông không nằm
// trong phép so nên tắt / bật Glass 6 lúc đang chạy nhãn vẫn giữ ảnh cũ (đã gặp 19/11/2026). Đánh dấu bộ thông số tạo lúc
// đang bật, và coi bộ có dấu khác bộ không dấu — đổi trạng thái là nhãn được vẽ lại.
static char kLabelStyleKey;

static BOOL G6LabelMarked(id params) {
    return objc_getAssociatedObject(params, &kLabelStyleKey) != nil;
}

// Hàm init: nhận self đã giữ, trả đối tượng đã giữ — khai đúng để ARC không giữ / thả thừa
static id (*o_labelInit)(__attribute__((ns_consumed)) id, SEL, id, BOOL, CGSize) __attribute__((ns_returns_retained));
__attribute__((ns_returns_retained)) static id g6_labelInit(__attribute__((ns_consumed)) id self, SEL _cmd, id text, BOOL ellipsize,
                                                            CGSize maxSize) {
    id obj = o_labelInit(self, _cmd, text, ellipsize, maxSize);
    if (obj && gActive) objc_setAssociatedObject(obj, &kLabelStyleKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return obj;
}

static id (*o_labelCopy)(id, SEL, NSZone *) __attribute__((ns_returns_retained));
__attribute__((ns_returns_retained)) static id g6_labelCopy(id self, SEL _cmd, NSZone *zone) {
    id copy = o_labelCopy(self, _cmd, zone);
    if (copy && copy != self && G6LabelMarked(self)) {
        objc_setAssociatedObject(copy, &kLabelStyleKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return copy;
}

static BOOL (*o_labelIsEqual)(id, SEL, id);
static BOOL g6_labelIsEqual(id self, SEL _cmd, id other) {
    if (!o_labelIsEqual(self, _cmd, other)) return NO;
    return G6LabelMarked(self) == G6LabelMarked(other);
}

// ---- Bật / tắt / đổi cấu hình lúc đang chạy ----

static id G6IconModel(void) {
    Class cls = objc_getClass("SBIconController");
    SEL shared = NSSelectorFromString(@"sharedInstance");
    if (!cls || ![cls respondsToSelector:shared]) return nil;
    return G6Get(((id (*)(id, SEL))objc_msgSend)(cls, shared), @"model");
}

static void G6CollectIconViews(UIView *view, NSMutableArray *out) {
    if ([view isKindOfClass:gIconViewClass]) {
        [out addObject:view];
        return;
    }
    for (UIView *sub in view.subviews) G6CollectIconViews(sub, out);
}

// Bóng đổ + nền thư mục của các biểu tượng đang có trên màn hình
static void G6IconsRefreshViews(void) {
    NSMutableArray *views = [NSMutableArray array];
    for (UIWindow *w in [UIApplication sharedApplication].windows) G6CollectIconViews(w, views);
    Ivar shadowIvar = gShadowIvar;
    SEL shadowImage = NSSelectorFromString(@"_shadowImage"), folderBg = NSSelectorFromString(@"_folderBackgroundImage");
    SEL folderFg = NSSelectorFromString(@"_folderForegroundImage");
    Ivar fgIvar = gFolderIconViewClass ? class_getInstanceVariable(gFolderIconViewClass, "_iconForegroundView") : NULL;
    for (UIView *v in views) {
        // Thư mục và Quầy báo: nền (và khung viền phía trước, nếu có)
        if (gFolderIconViewClass && [v isKindOfClass:gFolderIconViewClass] && [v respondsToSelector:folderBg]) {
            UIImageView *bg = G6Get(v, @"iconBackgroundView");
            UIImage *img = ((id (*)(id, SEL))objc_msgSend)(v, folderBg);
            if ([bg isKindOfClass:[UIImageView class]] && img) bg.image = img;
            id fg = fgIvar ? object_getIvar(v, fgIvar) : nil;
            if ([fg isKindOfClass:[UIImageView class]] && [v respondsToSelector:folderFg]) {
                UIImage *fimg = ((id (*)(id, SEL))objc_msgSend)(v, folderFg);
                if (fimg) [(UIImageView *)fg setImage:fimg];
            }
        }
        G6Do(v, @"updateLabel");
        id shadow = shadowIvar ? object_getIvar(v, shadowIvar) : nil;
        if ([shadow isKindOfClass:[UIImageView class]] && [v respondsToSelector:shadowImage]) {
            UIImage *img = ((id (*)(id, SEL))objc_msgSend)(v, shadowImage);
            if (img) [(UIImageView *)shadow setImage:img];
            G6Do(v, @"_updateShadowFrame");
        }
    }
    // View đang nằm chờ dùng lại còn giữ ảnh cũ — bỏ đi, lần sau SpringBoard tạo mới
    Class mapClass = objc_getClass("SBIconViewMap");
    SEL home = NSSelectorFromString(@"homescreenMap"), purge = NSSelectorFromString(@"purgeRecycledIconViewsForClass:");
    id map = [mapClass respondsToSelector:home] ? ((id (*)(id, SEL))objc_msgSend)(mapClass, home) : nil;
    if ([map respondsToSelector:purge]) {
        for (NSString *name in @[@"SBIconView", @"SBFolderIconView", @"SBNewsstandIconView"]) {
            Class c = objc_getClass(name.UTF8String);
            if (c) ((void (*)(id, SEL, Class))objc_msgSend)(map, purge, c);
        }
    }
}

// Bắt mọi biểu tượng tạo lại ảnh (SpringBoard tự báo cho các view đang hiện)
static void G6IconsReloadImages(void) {
    id icons = G6Get(G6IconModel(), @"leafIcons");
    NSArray *list = [icons isKindOfClass:[NSSet class]] ? [icons allObjects] : ([icons isKindOfClass:[NSArray class]] ? [icons copy] : nil);
    SEL reload = NSSelectorFromString(@"reloadIconImagePurgingImageCache:");
    double t0 = G6NowMs();
    NSUInteger n = 0;
    gTimeLookup = gTimeCompose = 0;
    gCacheHits = 0;
    for (id icon in list) {
        if (![icon respondsToSelector:reload]) continue;
        ((void (*)(id, SEL, BOOL))objc_msgSend)(icon, reload, YES);
        n++;
    }
    G6Log(@"biểu tượng: tạo lại ảnh của %lu biểu tượng %.0f ms (%@; %u ảnh lấy từ bộ đệm, tìm tệp gốc %.0f ms, vẽ + cắt %.0f ms)",
          (unsigned long)n, G6NowMs() - t0, gActive ? @"kiểu mới" : @"kiểu gốc", gCacheHits, gTimeLookup, gTimeCompose);
}

// Đọc cấu hình; thứ gì ảnh hưởng tới hình thì dựng lại đúng phần đó.
static void G6IconsApply(BOOL initial) {
    BOOL active = G6Feature(@"icons"), dark = G6IsDark();
    NSDictionary *cfg = G6Config();
    // Những thứ làm ảnh biểu tượng đổi: bật / tắt, viền sáng (chế độ tối viền dịu hơn). Bóng đổ và nền thư mục thì đổi theo
    // sáng / tối ngay cả khi ảnh biểu tượng giữ nguyên.
    NSString *signature = [NSString stringWithFormat:@"%d|%@|%d|%@|%@", active, cfg[@"rim"], active && dark, cfg[@"icon_style"], cfg[@"icon_tint"]];
    BOOL imagesChanged = ![signature isEqualToString:gSignature], viewsChanged = imagesChanged || dark != gDark;
    gSignature = signature;
    // Đặt dấu kiểu dáng trước khi bật: luồng nào dựng ảnh cũng thấy dấu mới
    gStyleHash = G6HashString([NSString stringWithFormat:@"%@|%s|%@|%@|%@|%@|%@|%@", G6CoreVersion(), G6_VERSION, cfg[@"rim"],
                                                         cfg[@"clarity"], cfg[@"tint"], cfg[@"reduce"], cfg[@"icon_style"],
                                                         cfg[@"icon_tint"]]);
    gActive = active;
    gDark = dark;
    gGeneration++;
    if (initial) return;
    if (imagesChanged) G6IconsReloadImages();
    if (viewsChanged) G6IconsRefreshViews();
}

void G6IconsInstall(void) {
    gIconViewClass = objc_getClass("SBIconView");
    gFolderIconViewClass = objc_getClass("SBFolderIconView");
    gPad = UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad;
    if (!gIconViewClass || !objc_getClass("SBApplicationIcon")) {
        G6Log(@"biểu tượng: thiếu lớp SBIconView / SBApplicationIcon — bỏ qua");
        return;
    }
    G6IconsApply(YES);
    BOOL load = G6HookNamed("SBApplicationIcon", NSSelectorFromString(@"__loadIconImage:format:scale:"), (IMP)g6_loadIconImage,
                            (IMP *)&o_loadIconImage);
    if (!load) {
        // Không có đường tạo ảnh quen thuộc: không đổi bóng / nền thư mục kẻo lệch kiểu với biểu tượng
        gActive = NO;
        return;
    }
    G6HookNamed("SBBookmarkIcon", NSSelectorFromString(@"generateIconImage:"), (IMP)g6_bookmarkImage, (IMP *)&o_bookmarkImage);
    // Chỉ đổi ảnh bóng khi đặt lại được khung của nó (ảnh mới khác cỡ ảnh gốc)
    gShadowIvar = class_getInstanceVariable(gIconViewClass, "_shadow");
    if (gShadowIvar && G6Hook(gIconViewClass, NSSelectorFromString(@"_updateShadowFrameForShadow:"), (IMP)g6_updateShadowFrame,
                              (IMP *)&o_updateShadowFrame)) {
        G6Hook(gIconViewClass, NSSelectorFromString(@"_updateShadow"), (IMP)g6_updateShadow, (IMP *)&o_updateShadow);
        G6Hook(gIconViewClass, NSSelectorFromString(@"_updateShadowFrame"), (IMP)g6_updateShadowFrame0, (IMP *)&o_updateShadowFrame0);
        G6Hook(gIconViewClass, NSSelectorFromString(@"positionIconImageView"), (IMP)g6_positionIconImageView,
               (IMP *)&o_positionIconImageView);
        G6Hook(gIconViewClass, NSSelectorFromString(@"_shadowImage"), (IMP)g6_shadowImage, (IMP *)&o_shadowImage);
        if (gFolderIconViewClass) {
            G6Hook(gFolderIconViewClass, NSSelectorFromString(@"setIcon:"), (IMP)g6_folderSetIcon, (IMP *)&o_folderSetIcon);
        }
    }
    // Nhãn. Lớp con cho biểu tượng trong Quầy báo có phông riêng — không đụng (G6Hook chỉ sửa đúng lớp được gọi tên).
    Class params = objc_getClass("SBIconLabelImageParameters");
    if (params && G6Hook(params, @selector(font), (IMP)g6_labelFont, (IMP *)&o_labelFont)) {
        G6Hook(params, NSSelectorFromString(@"shadowBlur"), (IMP)g6_labelShadowBlur, (IMP *)&o_labelShadowBlur);
        G6Hook(params, NSSelectorFromString(@"shadowColor"), (IMP)g6_labelShadowColor, (IMP *)&o_labelShadowColor);
        G6HookNamed("SBDockIconLabelImageParameters", NSSelectorFromString(@"shadowColor"), (IMP)g6_dockLabelShadowColor,
                    (IMP *)&o_dockLabelShadowColor);
        // Để nhãn vẽ lại khi tắt / bật lúc đang chạy — cả ba hàm có đủ mới gắn
        SEL init = NSSelectorFromString(@"initWithText:canEllipsize:maxSize:"), copy = @selector(copyWithZone:);
        if (class_getInstanceMethod(params, init) && class_getInstanceMethod(params, copy) && class_getInstanceMethod(params, @selector(isEqual:))) {
            G6Hook(params, init, (IMP)g6_labelInit, (IMP *)&o_labelInit);
            G6Hook(params, copy, (IMP)g6_labelCopy, (IMP *)&o_labelCopy);
            G6Hook(params, @selector(isEqual:), (IMP)g6_labelIsEqual, (IMP *)&o_labelIsEqual);
        }
    }
    if (gFolderIconViewClass) {
        G6Hook(gFolderIconViewClass, NSSelectorFromString(@"_folderBackgroundImage"), (IMP)g6_folderBackground,
               (IMP *)&o_folderBackground);
        // Quầy báo có bản riêng của hai hàm này (nếu máy nào không có thì G6Hook thêm bản ghi đè lên lớp con, vẫn đúng)
        if (G6HookNamed("SBNewsstandIconView", NSSelectorFromString(@"_folderBackgroundImage"), (IMP)g6_newsstandBackground,
                        (IMP *)&o_newsstandBackground)) {
            G6HookNamed("SBNewsstandIconView", NSSelectorFromString(@"_folderForegroundImage"), (IMP)g6_newsstandForeground,
                        (IMP *)&o_newsstandForeground);
        }
    }
}

void G6IconsStart(void) {
    if (!o_loadIconImage) return;
    [[NSNotificationCenter defaultCenter] addObserverForName:G6ConfigDidChangeNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
                                                      @try {
                                                          G6IconsApply(NO);
                                                      } @catch (NSException *e) {
                                                          G6Log(@"biểu tượng: lỗi khi áp cấu hình: %@", e);
                                                      }
                                                  }];
    // Lúc gắn hàm chưa biết thành phần nào bị chặn vì xung đột — giờ mới biết
    G6IconsApply(NO);
    // Một lúc sau khi SpringBoard lên: dọn tệp đệm của app đã gỡ
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        @try {
            id icons = G6Get(G6IconModel(), @"leafIcons");
            if (![icons conformsToProtocol:@protocol(NSFastEnumeration)]) return;
            NSMutableSet *known = [NSMutableSet set];
            for (id icon in icons) {
                id ident = G6Get(icon, @"leafIdentifier");
                if ([ident isKindOfClass:[NSString class]]) [known addObject:ident];
            }
            if (known.count) G6IconCachePrune(known);
        } @catch (NSException *e) {
        }
    });
}

#import "G6Glass.h"

#import "G6Core.h"
#import "G6Log.h"
#import <dlfcn.h>
#import <mach/mach.h>

// ---- Chụp màn hình: IOSurface + CARenderServerRenderDisplay (API riêng, tra lúc chạy — cách của tools/cbscreen) ----

typedef void *G6SurfaceRef;

static struct {
    G6SurfaceRef (*create)(CFDictionaryRef);
    void *(*base)(G6SurfaceRef);
    size_t (*rowBytes)(G6SurfaceRef);
    int (*lock)(G6SurfaceRef, uint32_t, uint32_t *);
    int (*unlock)(G6SurfaceRef, uint32_t, uint32_t *);
    void (*render)(mach_port_t, CFStringRef, G6SurfaceRef, int, int);
    BOOL ok;
} gCapture;

static void G6CaptureLoad(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *ios = dlopen("/System/Library/PrivateFrameworks/IOSurface.framework/IOSurface", RTLD_NOW);
        void *qc = dlopen("/System/Library/Frameworks/QuartzCore.framework/QuartzCore", RTLD_NOW);
        if (!ios || !qc) return;
        gCapture.create = dlsym(ios, "IOSurfaceCreate");
        gCapture.base = dlsym(ios, "IOSurfaceGetBaseAddress");
        gCapture.rowBytes = dlsym(ios, "IOSurfaceGetBytesPerRow");
        gCapture.lock = dlsym(ios, "IOSurfaceLock");
        gCapture.unlock = dlsym(ios, "IOSurfaceUnlock");
        gCapture.render = dlsym(qc, "CARenderServerRenderDisplay");
        gCapture.ok = gCapture.create && gCapture.base && gCapture.rowBytes && gCapture.lock && gCapture.unlock &&
                      gCapture.render;
    });
}

// Một IOSurface cỡ màn hình, giữ lại dùng cho các lần chụp sau (cấp mới mỗi lần tốn ~3 MB và vài mili giây)
static G6SurfaceRef G6ScreenSurface(int w, int h) {
    static G6SurfaceRef surface;
    static int sw, sh;
    if (surface && sw == w && sh == h) return surface;
    if (surface) {
        CFRelease(surface);
        surface = NULL;
    }
    int bpe = 4, bpr = w * bpe, fmt = 'BGRA', size = bpr * h;
    NSDictionary *props = @{
        @"IOSurfaceIsGlobal" : @YES,
        @"IOSurfaceBytesPerElement" : @(bpe),
        @"IOSurfaceBytesPerRow" : @(bpr),
        @"IOSurfaceWidth" : @(w),
        @"IOSurfaceHeight" : @(h),
        @"IOSurfacePixelFormat" : @(fmt),
        @"IOSurfaceAllocSize" : @(size),
    };
    surface = gCapture.create((__bridge CFDictionaryRef)props);
    sw = w;
    sh = h;
    return surface;
}

@implementation G6Backdrop

- (instancetype)initWithPixels:(NSData *)pixels width:(uint32_t)w height:(uint32_t)h factor:(CGFloat)factor {
    if ((self = [super init])) {
        _pixels = pixels;
        _width = w;
        _height = h;
        _factor = factor;
    }
    return self;
}

+ (instancetype)backdropWithPixels:(const uint8_t *)data width:(uint32_t)w height:(uint32_t)h stride:(uint32_t)stride fast:(BOOL)fast {
    return [self backdropWithPixels:data width:w height:h stride:stride fast:fast prescale:1];
}

+ (instancetype)backdropWithPixels:(const uint8_t *)data width:(uint32_t)w height:(uint32_t)h stride:(uint32_t)stride fast:(BOOL)fast prescale:(uint32_t)prescale {
    if (!data || !w || !h || !prescale) return nil;
    float scale = (float)[UIScreen mainScreen].scale;
    uint32_t ow = 0, oh = 0;
    if (G6CoreBackdropSize(w, h, scale, fast, prescale, &ow, &oh) != 0 || !ow || !oh) return nil;
    NSMutableData *out = [NSMutableData dataWithLength:(NSUInteger)ow * oh * 4];
    G6Image src = {data, w, h, stride};
    int rc = G6CoreBackdropPrepare(&src, scale, fast, prescale, out.mutableBytes, ow, oh, ow * 4);
    if (rc != 0) {
        G6Log(@"chuẩn bị nền lỗi %d (%ux%u)", rc, w, h);
        return nil;
    }
    // Một điểm ảnh nền = (thu nhỏ sẵn) × (lõi thu nhỏ thêm) điểm ảnh màn hình
    return [[G6Backdrop alloc] initWithPixels:out width:ow height:oh factor:(CGFloat)prescale * w / ow];
}

+ (instancetype)backdropWithScreen:(BOOL)fast {
    G6CaptureLoad();
    if (!gCapture.ok) return nil;
    UIScreen *screen = [UIScreen mainScreen];
    // bounds của UIScreen trên iOS 6 luôn theo hệ dọc
    int w = (int)lround(screen.bounds.size.width * screen.scale);
    int h = (int)lround(screen.bounds.size.height * screen.scale);
    G6SurfaceRef surface = G6ScreenSurface(w, h);
    if (!surface) return nil;
    gCapture.lock(surface, 0, NULL);
    gCapture.render(0, CFSTR("LCD"), surface, 0, 0);
    G6Backdrop *b = [self backdropWithPixels:gCapture.base(surface)
                                       width:(uint32_t)w
                                      height:(uint32_t)h
                                      stride:(uint32_t)gCapture.rowBytes(surface)
                                        fast:fast];
    gCapture.unlock(surface, 0, NULL);
    return b;
}

@end

UIImage *G6ScreenImage(G6Backdrop *__autoreleasing *backdrop, BOOL fast) {
    if (backdrop) *backdrop = nil;
    G6CaptureLoad();
    if (!gCapture.ok) return nil;
    UIScreen *screen = [UIScreen mainScreen];
    int w = (int)lround(screen.bounds.size.width * screen.scale);
    int h = (int)lround(screen.bounds.size.height * screen.scale);
    G6SurfaceRef surface = G6ScreenSurface(w, h);
    if (!surface) return nil;
    gCapture.lock(surface, 0, NULL);
    gCapture.render(0, CFSTR("LCD"), surface, 0, 0);
    const uint8_t *base = gCapture.base(surface);
    size_t stride = gCapture.rowBytes(surface);
    // Chép ra vùng nhớ riêng: mặt phẳng chụp được dùng lại cho lần chụp sau
    NSMutableData *copy = [NSMutableData dataWithLength:(NSUInteger)w * h * 4];
    uint8_t *dst = copy.mutableBytes;
    for (int y = 0; y < h; y++) memcpy(dst + (size_t)y * w * 4, base + (size_t)y * stride, (size_t)w * 4);
    if (backdrop) *backdrop = [G6Backdrop backdropWithPixels:base width:(uint32_t)w height:(uint32_t)h stride:(uint32_t)stride fast:fast];
    gCapture.unlock(surface, 0, NULL);
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)copy);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    // BGRA, bỏ qua kênh alpha (ảnh chụp màn hình luôn đặc)
    CGImageRef cg = CGImageCreate((size_t)w, (size_t)h, 8, 32, (size_t)w * 4, space, kCGBitmapByteOrder32Little | kCGImageAlphaNoneSkipFirst, provider,
                                  NULL, false, kCGRenderingIntentDefault);
    UIImage *image = cg ? [UIImage imageWithCGImage:cg scale:screen.scale orientation:UIImageOrientationUp] : nil;
    if (cg) CGImageRelease(cg);
    CGColorSpaceRelease(space);
    CGDataProviderRelease(provider);
    return image;
}

// ---- Điểm ảnh thô → UIImage ----

static void G6ReleasePixels(void *info, const void *data, size_t size) {
    CFRelease((CFTypeRef)info);
}

UIImage *G6ImageFromPixels(NSData *pixels, uint32_t w, uint32_t h, CGFloat scale) {
    return G6ImageFromPixelsAt(pixels, 0, w, h, scale);
}

UIImage *G6ImageFromPixelsAt(NSData *pixels, size_t offset, uint32_t w, uint32_t h, CGFloat scale) {
    size_t size = (size_t)w * h * 4;
    if (!pixels || !w || !h || pixels.length < offset + size) return nil;
    // Ảnh giữ `pixels` cho tới khi bị huỷ; không chép (tệp ánh xạ vào bộ nhớ thì vẫn là trang sạch)
    CGDataProviderRef provider = CGDataProviderCreateWithData((void *)CFBridgingRetain(pixels), (const uint8_t *)pixels.bytes + offset,
                                                              size, G6ReleasePixels);
    if (!provider) return nil;
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    // BGRA nhân sẵn alpha — đúng thứ lõi dựng ra, CoreAnimation dùng thẳng không phải đổi
    CGImageRef cg = CGImageCreate(w, h, 8, 32, (size_t)w * 4, cs, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst,
                                  provider, NULL, false, kCGRenderingIntentDefault);
    CGColorSpaceRelease(cs);
    CGDataProviderRelease(provider);
    if (!cg) return nil;
    UIImage *img = [UIImage imageWithCGImage:cg scale:scale orientation:UIImageOrientationUp];
    CGImageRelease(cg);
    return img;
}

// Dựng `w × h` điểm ảnh kính vào `out`. `toScreen` đưa toạ độ điểm của tấm kính sang toạ độ điểm màn hình.
static int G6GlassRenderPixels(NSString *surface, uint32_t w, uint32_t h, CGFloat scale, BOOL dark, G6Backdrop *backdrop,
                               CGAffineTransform toScreen, uint8_t *out, uint32_t stride) {
    if (!backdrop) return G6CoreGlassRender(surface.UTF8String, w, h, (float)scale, dark, NULL, NULL, out, stride);
    // Điểm ảnh kính → điểm (÷ scale) → điểm màn hình (toScreen) → điểm ảnh màn hình (× scale) → điểm ảnh nền (÷ factor).
    // Phần tuyến tính: scale triệt tiêu; phần dời còn × scale.
    CGFloat f = backdrop.factor;
    G6Affine m = {
        (float)(toScreen.a / f),  (float)(toScreen.b / f),          (float)(toScreen.c / f),
        (float)(toScreen.d / f),  (float)(toScreen.tx * scale / f), (float)(toScreen.ty * scale / f),
    };
    G6Image bd = {backdrop.pixels.bytes, backdrop.width, backdrop.height, backdrop.width * 4};
    return G6CoreGlassRender(surface.UTF8String, w, h, (float)scale, dark, &bd, &m, out, stride);
}

UIImage *G6GlassImage(NSString *surface, CGSize size, BOOL dark, G6Backdrop *backdrop, CGAffineTransform toScreen) {
    CGFloat scale = [UIScreen mainScreen].scale;
    uint32_t w = (uint32_t)lround(size.width * scale), h = (uint32_t)lround(size.height * scale);
    if (!w || !h || w > 4096 || h > 4096) return nil;
    NSMutableData *out = [NSMutableData dataWithLength:(NSUInteger)w * h * 4];
    int rc = G6GlassRenderPixels(surface, w, h, scale, dark, backdrop, toScreen, out.mutableBytes, w * 4);
    if (rc != 0) {
        G6Log(@"dựng kính «%@» %ux%u lỗi %d", surface, w, h, rc);
        return nil;
    }
    return G6ImageFromPixels(out, w, h, scale);
}

// Phép biến đổi đưa toạ độ điểm của vùng `rect` (gốc ở góc vùng) trong `view` sang toạ độ điểm màn hình: lấy ba điểm — góc
// vùng, góc + (1,0), góc + (0,1) — đổi sang toạ độ màn hình (xoay bội 90° + dời)
// Cửa sổ chứa `view`. Chính UIWindow thì -window của nó trả nil (chưa nằm trong cửa sổ nào khác) → lấy chính nó; không xét
// trường hợp này thì tấm kính đặt theo toạ độ của một cửa sổ sẽ thành kính giả không nền (đã gặp với hộp thoại, 19/11/2026).
static UIWindow *G6WindowOf(UIView *view) {
    return [view isKindOfClass:[UIWindow class]] ? (UIWindow *)view : view.window;
}

static CGAffineTransform G6RectToScreen(UIView *view, CGRect rect) {
    UIWindow *window = G6WindowOf(view);
    CGPoint (^toScreen)(CGPoint) = ^(CGPoint p) {
        return [window convertPoint:[view convertPoint:p toView:nil] toWindow:nil];
    };
    CGPoint p0 = rect.origin;
    CGPoint o = toScreen(p0), x = toScreen(CGPointMake(p0.x + 1, p0.y)), y = toScreen(CGPointMake(p0.x, p0.y + 1));
    return CGAffineTransformMake(x.x - o.x, x.y - o.y, y.x - o.x, y.y - o.y, o.x, o.y);
}

int G6GlassRenderForRect(NSString *surface, UIView *view, CGRect rect, BOOL dark, G6Backdrop *backdrop, uint8_t *out, uint32_t stride) {
    CGFloat scale = [UIScreen mainScreen].scale;
    uint32_t w = (uint32_t)lround(rect.size.width * scale), h = (uint32_t)lround(rect.size.height * scale);
    if (!out || !w || !h || w > 4096 || h > 4096 || stride < w * 4) return -3;
    BOOL placed = G6WindowOf(view) != nil && backdrop != nil;
    return G6GlassRenderPixels(surface, w, h, scale, dark, placed ? backdrop : nil, placed ? G6RectToScreen(view, rect) : CGAffineTransformIdentity,
                               out, stride);
}

UIImage *G6GlassImageForView(NSString *surface, UIView *view, BOOL dark, G6Backdrop *backdrop) {
    return G6GlassImageForRect(surface, view, view.bounds, dark, backdrop);
}

UIImage *G6GlassImageForRect(NSString *surface, UIView *view, CGRect rect, BOOL dark, G6Backdrop *backdrop) {
    if (!G6WindowOf(view)) return G6GlassImage(surface, rect.size, dark, nil, CGAffineTransformIdentity);
    return G6GlassImage(surface, rect.size, dark, backdrop, G6RectToScreen(view, rect));
}

UIImage *G6ShadowImage(NSString *surface, CGSize size, BOOL dark, CGFloat *margin) {
    CGFloat scale = [UIScreen mainScreen].scale;
    uint32_t w = (uint32_t)lround(size.width * scale), h = (uint32_t)lround(size.height * scale);
    if (!w || !h) return nil;
    NSDictionary *m = G6CoreCall(@{@"cmd" : @"glass.metrics", @"surface" : surface, @"w" : @(w), @"h" : @(h),
                                   @"scale" : @(scale), @"dark" : dark ? @YES : @NO});
    uint32_t pad = [m[@"shadowMargin"] unsignedIntValue];
    // Cỡ nhỏ nhất giữ nguyên bốn góc, và phần góc không được kéo giãn
    uint32_t cw = [m[@"canonW"] unsignedIntValue], ch = [m[@"canonH"] unsignedIntValue], cap = [m[@"cap"] unsignedIntValue];
    if (![m[@"ok"] boolValue] || !pad || !cw || !ch) return nil;
    if (margin) *margin = pad / scale;

    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [[NSCache alloc] init];
    });
    NSString *key = [NSString stringWithFormat:@"%@|%u|%u|%d", surface, cw, ch, dark];
    UIImage *img = [cache objectForKey:key];
    if (img) return img;

    uint32_t ow = cw + 2 * pad, oh = ch + 2 * pad;
    NSMutableData *out = [NSMutableData dataWithLength:(NSUInteger)ow * oh * 4];
    int rc = G6CoreShadowRender(surface.UTF8String, cw, ch, (float)scale, dark, out.mutableBytes, ow, oh, ow * 4);
    if (rc != 0) {
        G6Log(@"dựng bóng «%@» lỗi %d", surface, rc);
        return nil;
    }
    img = G6ImageFromPixels(out, ow, oh, scale);
    // Chiều nào đã rút thì chừa lề + góc làm phần cố định; chiều giữ nguyên cỡ thì không cần (khung ảnh vừa khít)
    CGFloat capX = cw < w ? (pad + cap) / scale : 0, capY = ch < h ? (pad + cap) / scale : 0;
    if (capX > 0 || capY > 0) img = [img resizableImageWithCapInsets:UIEdgeInsetsMake(capY, capX, capY, capX)];
    if (img) [cache setObject:img forKey:key];
    return img;
}

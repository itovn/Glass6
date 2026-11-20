#import "G6GlassFill.h"

#import <objc/runtime.h>

#import "G6Glass.h"
#import "G6Log.h"
#import "G6Prefs.h"
#import "G6Wallpaper.h"

static char kGlassKey, kDrawnKey;

BOOL G6GlassFill(UIView *host, BOOL active, NSString *surface) {
    if (!host) return NO;
    UIImageView *glass = objc_getAssociatedObject(host, &kGlassKey);
    if (!active) {
        if (!glass) return NO;
        for (UIView *sub in host.subviews) {
            if (sub != glass) sub.hidden = NO;
        }
        [glass removeFromSuperview];
        objc_setAssociatedObject(host, &kGlassKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(host, &kDrawnKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return NO;
    }
    for (UIView *sub in host.subviews) {
        if (sub != glass) sub.hidden = YES;
    }
    if (!glass) {
        glass = [[UIImageView alloc] initWithFrame:host.bounds];
        glass.userInteractionEnabled = NO;
        [host insertSubview:glass atIndex:0];
        objc_setAssociatedObject(host, &kGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    glass.frame = host.bounds;
    CGSize size = glass.bounds.size;
    // Chưa vào cửa sổ thì chưa biết view nằm ở đâu trên hình nền (và cũng chưa ai thấy nó) — vào cửa sổ mới dựng
    UIWindow *window = glass.window;
    if (size.width < 1 || size.height < 1 || !window) return YES;

    BOOL dark = G6IsDark();
    G6Backdrop *backdrop = G6WallpaperBackdrop();
    CGPoint origin = [window convertPoint:[glass convertPoint:CGPointZero toView:nil] toWindow:nil];
    NSString *drawn = [NSString stringWithFormat:@"%@|%.0f|%.0f|%.0f|%.0f|%d|%lu|%d|%d", surface, size.width, size.height, origin.x,
                                                 origin.y, dark, (unsigned long)G6WallpaperGeneration(), backdrop != nil,
                                                 (int)[UIApplication sharedApplication].statusBarOrientation];
    if (glass.image && [drawn isEqualToString:objc_getAssociatedObject(host, &kDrawnKey)]) return YES;
    double t0 = G6NowMs();
    UIImage *img = G6GlassImageForView(surface, glass, dark, backdrop);
    if (!img) return YES;
    glass.image = img;
    objc_setAssociatedObject(host, &kDrawnKey, drawn, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    G6Log(@"kính «%@» trên %@: %.0f×%.0f (%@, %@ nền) %.1f ms", surface, NSStringFromClass([host.superview class] ?: [host class]),
          size.width, size.height, dark ? @"tối" : @"sáng", backdrop ? @"có" : @"KHÔNG", G6NowMs() - t0);
    return YES;
}

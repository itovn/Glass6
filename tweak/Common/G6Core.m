#import "G6Core.h"

#import "G6Log.h"
#import <dlfcn.h>

static const char *const kCorePath = "/usr/lib/libglass6core.dylib";

static const char *(*p_version)(void);
static char *(*p_call)(const char *);
static void (*p_free)(char *);
static int (*p_backdrop_size)(uint32_t, uint32_t, float, int, uint32_t, uint32_t *, uint32_t *);
static int (*p_backdrop_prepare)(const G6Image *, float, int, uint32_t, uint8_t *, uint32_t, uint32_t, uint32_t);
static int (*p_glass_render)(const char *, uint32_t, uint32_t, float, int, const G6Image *, const G6Affine *, uint8_t *,
                             uint32_t);
static int (*p_shadow_render)(const char *, uint32_t, uint32_t, float, int, uint8_t *, uint32_t, uint32_t, uint32_t);
static int (*p_icon_render)(uint8_t *, uint32_t, uint32_t, uint32_t, float, int);
static BOOL gLoaded;

BOOL G6CoreLoad(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *h = dlopen(kCorePath, RTLD_NOW | RTLD_LOCAL);
        if (!h) {
            G6Log(@"không nạp được lõi: %s", dlerror() ?: "?");
            return;
        }
        p_version = dlsym(h, "g6_version");
        p_call = dlsym(h, "g6_call");
        p_free = dlsym(h, "g6_free");
        p_backdrop_size = dlsym(h, "g6_backdrop_size");
        p_backdrop_prepare = dlsym(h, "g6_backdrop_prepare");
        p_glass_render = dlsym(h, "g6_glass_render");
        p_shadow_render = dlsym(h, "g6_shadow_render");
        p_icon_render = dlsym(h, "g6_icon_render");
        if (!p_version || !p_call || !p_free || !p_backdrop_size || !p_backdrop_prepare || !p_glass_render ||
            !p_shadow_render || !p_icon_render) {
            G6Log(@"lõi thiếu hàm — bản lõi và bản tweak không khớp");
            return;
        }
        gLoaded = YES;
    });
    return gLoaded;
}

NSString *G6CoreVersion(void) {
    if (!G6CoreLoad()) return nil;
    const char *v = p_version();
    return v ? [NSString stringWithUTF8String:v] : nil;
}

NSDictionary *G6CoreCall(NSDictionary *cmd) {
    if (!G6CoreLoad() || ![NSJSONSerialization isValidJSONObject:cmd]) return nil;
    NSData *json = [NSJSONSerialization dataWithJSONObject:cmd options:0 error:NULL];
    if (!json) return nil;
    // Lõi cần C string kết thúc bằng 0
    NSMutableData *z = [json mutableCopy];
    [z appendBytes:"" length:1];
    char *out = p_call(z.bytes);
    if (!out) return nil;
    NSData *reply = [NSData dataWithBytes:out length:strlen(out)];
    p_free(out);
    id obj = [NSJSONSerialization JSONObjectWithData:reply options:0 error:NULL];
    return [obj isKindOfClass:[NSDictionary class]] ? obj : nil;
}

int G6CoreBackdropSize(uint32_t srcW, uint32_t srcH, float scale, BOOL fast, uint32_t pre, uint32_t *outW, uint32_t *outH) {
    return G6CoreLoad() ? p_backdrop_size(srcW, srcH, scale, fast ? 1 : 0, pre, outW, outH) : -100;
}

int G6CoreBackdropPrepare(const G6Image *src, float scale, BOOL fast, uint32_t pre, uint8_t *out, uint32_t outW,
                          uint32_t outH, uint32_t outStride) {
    return G6CoreLoad() ? p_backdrop_prepare(src, scale, fast ? 1 : 0, pre, out, outW, outH, outStride) : -100;
}

int G6CoreGlassRender(const char *surface, uint32_t w, uint32_t h, float scale, BOOL dark, const G6Image *backdrop,
                      const G6Affine *place, uint8_t *out, uint32_t outStride) {
    return G6CoreLoad() ? p_glass_render(surface, w, h, scale, dark ? 1 : 0, backdrop, place, out, outStride) : -100;
}

int G6CoreShadowRender(const char *surface, uint32_t w, uint32_t h, float scale, BOOL dark, uint8_t *out, uint32_t outW,
                       uint32_t outH, uint32_t outStride) {
    return G6CoreLoad() ? p_shadow_render(surface, w, h, scale, dark ? 1 : 0, out, outW, outH, outStride) : -100;
}

int G6CoreIconRender(uint8_t *pixels, uint32_t w, uint32_t h, uint32_t stride, float scale, BOOL dark) {
    return G6CoreLoad() ? p_icon_render(pixels, w, h, stride, scale, dark ? 1 : 0) : -100;
}

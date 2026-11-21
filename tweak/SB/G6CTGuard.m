#import "G6CTGuard.h"

#import "G6Log.h"
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <pthread.h>

typedef void (*G6CTAddObserverFn)(CFNotificationCenterRef center, const void *observer, CFNotificationCallback callback, CFStringRef name,
                                  const void *object, CFNotificationSuspensionBehavior behavior);

// Bảng (observer, tên thông báo) → callback gốc của SpringBoard. Không bao giờ xoá dòng: thông báo đến muộn sau khi
// SpringBoard gỡ observer vẫn tìm được hàm (SBTelephonyManager sống suốt đời SpringBoard). SpringBoard đăng ký vài chục cặp.
#define G6CT_MAX 128
typedef struct {
    const void *observer;
    CFStringRef name;  // NULL = mọi thông báo
    CFNotificationCallback callback;
} G6CTEntry;

static G6CTEntry gEntries[G6CT_MAX];
static int gCount;
static pthread_mutex_t gLock = PTHREAD_MUTEX_INITIALIZER;
static G6CTAddObserverFn gOrigAdd;
static int gHops;  // số lần đã chuyển thông báo sang luồng chính (chỉ ghi nhật ký vài lần đầu)

static BOOL G6CTSameName(CFStringRef a, CFStringRef b) {
    if (a == b) return YES;
    if (!a || !b) return NO;
    return CFEqual(a, b);
}

static CFNotificationCallback G6CTLookup(const void *observer, CFStringRef name) {
    CFNotificationCallback found = NULL, any = NULL;
    pthread_mutex_lock(&gLock);
    for (int i = 0; i < gCount; i++) {
        if (gEntries[i].observer != observer) continue;
        if (G6CTSameName(gEntries[i].name, name)) {
            found = gEntries[i].callback;
            break;
        }
        if (!gEntries[i].name) any = gEntries[i].callback;
    }
    pthread_mutex_unlock(&gLock);
    return found ?: any;
}

// Nhớ callback gốc; NO nếu bảng đầy (khi đó để nguyên callback của SpringBoard)
static BOOL G6CTRemember(const void *observer, CFStringRef name, CFNotificationCallback callback) {
    BOOL ok = NO;
    pthread_mutex_lock(&gLock);
    for (int i = 0; i < gCount; i++) {
        if (gEntries[i].observer == observer && G6CTSameName(gEntries[i].name, name)) {
            gEntries[i].callback = callback;  // đăng ký lại cùng cặp: dùng hàm mới
            ok = YES;
            break;
        }
    }
    if (!ok && gCount < G6CT_MAX) {
        gEntries[gCount].observer = observer;
        gEntries[gCount].name = name ? (CFStringRef)CFRetain(name) : NULL;
        gEntries[gCount].callback = callback;
        gCount++;
        ok = YES;
    }
    pthread_mutex_unlock(&gLock);
    return ok;
}

static void G6CTTrampoline(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    CFNotificationCallback callback = G6CTLookup(observer, name);
    if (!callback) return;
    if (pthread_main_np()) {
        callback(center, observer, name, object, userInfo);
        return;
    }
    if (name) CFRetain(name);
    if (userInfo) CFRetain(userInfo);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (gHops++ < 5) G6Log(@"CoreTelephony: thông báo «%@» đến ngoài luồng chính — đã chuyển sang luồng chính", (__bridge NSString *)name);
        callback(center, observer, name, object, userInfo);
        if (name) CFRelease(name);
        if (userInfo) CFRelease(userInfo);
    });
}

// Hàm có nằm trong chính tệp chạy của SpringBoard không (ảnh số 0 của dyld)
static BOOL G6CTIsSpringBoardCode(const void *fn) {
    Dl_info info;
    if (!fn || !dladdr(fn, &info)) return NO;
    return info.dli_fbase == (const void *)_dyld_get_image_header(0);
}

static void G6CTAddObserver(CFNotificationCenterRef center, const void *observer, CFNotificationCallback callback, CFStringRef name,
                            const void *object, CFNotificationSuspensionBehavior behavior) {
    if (callback && callback != G6CTTrampoline && G6CTIsSpringBoardCode((const void *)callback) &&
        G6CTRemember(observer, name, callback)) {
        callback = G6CTTrampoline;
    }
    gOrigAdd(center, observer, callback, name, object, behavior);
}

#if G6_DEBUG
NSString *G6CTGuardDebugFire(NSString *part) {
    NSMutableArray *names = [NSMutableArray array];
    const void *observer = NULL;
    CFStringRef name = NULL;
    pthread_mutex_lock(&gLock);
    for (int i = 0; i < gCount; i++) {
        NSString *n = gEntries[i].name ? (__bridge NSString *)gEntries[i].name : @"(mọi thông báo)";
        [names addObject:n];
        if (part.length && !name && gEntries[i].name && [n rangeOfString:part].location != NSNotFound) {
            observer = gEntries[i].observer;
            name = gEntries[i].name;
        }
    }
    pthread_mutex_unlock(&gLock);
    if (!part.length) return [NSString stringWithFormat:@"%lu thông báo đã bọc: %@", (unsigned long)names.count, [names componentsJoinedByString:@", "]];
    if (!name) return [NSString stringWithFormat:@"không có thông báo nào chứa «%@» (%lu đã bọc)", part, (unsigned long)names.count];
    CFNotificationCenterRef (*getDefault)(void) = (CFNotificationCenterRef (*)(void))dlsym(RTLD_DEFAULT, "CTTelephonyCenterGetDefault");
    CFNotificationCenterRef center = getDefault ? getDefault() : NULL;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        G6CTTrampoline(center, (void *)observer, name, NULL, NULL);
    });
    return [NSString stringWithFormat:@"đã gọi «%@» từ một luồng phụ", (__bridge NSString *)name];
}
#endif

void G6CTGuardInstall(void) {
    static BOOL done;
    if (done) return;
    done = YES;
    void *ct = dlopen("/System/Library/Frameworks/CoreTelephony.framework/CoreTelephony", RTLD_NOW);
    void *add = ct ? dlsym(ct, "CTTelephonyCenterAddObserver") : NULL;
    // MSHookFunction nằm trong CydiaSubstrate.framework. MobileSubstrate chỉ nạp nó khi một tweak liên kết tới; tweak nạp theo thứ
    // tự chữ cái nên trên máy ít tweak (chỉ có MobileSafety — chữ M, sau Glass6SB) lúc này nó CHƯA có → dlsym(RTLD_DEFAULT) trả
    // NULL và chốt im lặng không chạy (gặp 21/11/2026 trên iPhone 5 đen). Tự mở framework (đã nằm sẵn trên máy có Substrate).
    void *substrate = dlopen("/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate", RTLD_LAZY);
    void *hookSym = substrate ? dlsym(substrate, "MSHookFunction") : NULL;
    if (!hookSym) hookSym = dlsym(RTLD_DEFAULT, "MSHookFunction");
    void (*hook)(void *, void *, void **) = (void (*)(void *, void *, void **))hookSym;
    if (!add || !hook) {
        G6Log(@"CoreTelephony: không móc được CTTelephonyCenterAddObserver (%@) — bỏ qua phần giữ luồng chính",
              !add ? @"thiếu hàm" : @"thiếu MSHookFunction");
        return;
    }
    hook(add, (void *)G6CTAddObserver, (void **)&gOrigAdd);
    if (!gOrigAdd) G6Log(@"CoreTelephony: MSHookFunction không trả hàm gốc");
}

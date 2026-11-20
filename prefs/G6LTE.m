#import "G6LTE.h"

#import "G6Lang.h"
#import "G6Log.h"
#import <dlfcn.h>
#import <fcntl.h>
#import <objc/message.h>
#import <signal.h>
#import <spawn.h>
#import <sys/stat.h>
#import <sys/wait.h>
#import <unistd.h>

int G6LTERun(NSString *command, NSString **output) {
    if (output) *output = nil;
    if (access(G6_LTE_TOOL, X_OK) != 0) return -1;
    int fds[2];
    if (pipe(fds) != 0) return -1;
    char *argv[] = {(char *)G6_LTE_TOOL, (char *)command.UTF8String, NULL};
    char *envp[] = {(char *)"PATH=/usr/bin:/bin:/usr/sbin:/sbin", NULL};
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0);
    posix_spawn_file_actions_adddup2(&actions, fds[1], 1);
    posix_spawn_file_actions_adddup2(&actions, fds[1], 2);
    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    // Luồng nền của GCD chặn tín hiệu, tiến trình con thừa hưởng mặt nạ đó → đặt lại (như G6OTA.m)
    sigset_t none, all;
    sigemptyset(&none);
    sigfillset(&all);
    posix_spawnattr_setsigmask(&attr, &none);
    posix_spawnattr_setsigdefault(&attr, &all);
    posix_spawnattr_setflags(&attr, POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF);
    pid_t pid = 0;
    int rc = posix_spawn(&pid, G6_LTE_TOOL, &actions, &attr, argv, envp);
    posix_spawnattr_destroy(&attr);
    posix_spawn_file_actions_destroy(&actions);
    close(fds[1]);
    if (rc != 0) {
        close(fds[0]);
        return -1;
    }
    NSMutableData *data = [NSMutableData data];
    char buf[1024];
    ssize_t n;
    while ((n = read(fds[0], buf, sizeof(buf))) > 0 && data.length < 64 * 1024) [data appendBytes:buf length:(NSUInteger)n];
    close(fds[0]);
    int status = 0;
    while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {
    }
    int code = WIFEXITED(status) ? WEXITSTATUS(status) : -1;
    if (output) *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (![command isEqualToString:@"status"]) {
        NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        G6Log(@"4G: g6lte %@ → %d %@", command, code, [text stringByReplacingOccurrencesOfString:@"\n" withString:@" | "]);
    }
    return code;
}

BOOL G6LTEAvailable(void) {
    struct stat st;
    return stat(G6_LTE_TOOL, &st) == 0 && st.st_uid == 0 && (st.st_mode & S_ISUID) != 0;
}

BOOL G6LTEIsOn(void) {
    NSString *out = nil;
    if (G6LTERun(@"status", &out) != 0) return NO;
    for (NSString *line in [out componentsSeparatedByString:@"\n"]) {
        if ([line hasPrefix:@"452"] && [line hasSuffix:@"\ton"]) return YES;
    }
    return NO;
}

NSString *G6LTEErrorText(int code) {
    switch (code) {
        case 3:
            return G6L(@"Chỉ dùng được trên iPhone 5 chạy iOS 6.");
        case 4:
            return G6L(@"Không tìm thấy cấu hình LTE gốc của iOS 6 trên máy (thư mục gói nhà mạng đã bị thay đổi).");
        case 5:
            return G6L(@"Cài đặt nhà mạng trên máy đã bị một công cụ khác sửa — Glass 6 để nguyên phần đó.");
        case 6:
            return G6L(@"Nhà mạng của SIM này không nhận cấu hình 4G. Máy đã tự trở về 3G như cũ.");
        case 66:
        case -1:
            return G6L(@"Thiếu công cụ bật 4G (g6lte) hoặc công cụ thiếu quyền root. Cài lại Glass 6 bằng Cydia.");
        default:
            return [NSString stringWithFormat:G6L(@"Không đổi được cấu hình mạng di động (mã %d)."), code];
    }
}

// ---- Mạng đang dùng (CoreTelephony, hàm C riêng — tra bằng dlsym) ----

typedef struct {
    int domain;
    int error;
} G6CTResult;

static void *G6CT(void) {
    static void *ct;
    if (!ct) ct = dlopen("/System/Library/Frameworks/CoreTelephony.framework/CoreTelephony", RTLD_NOW);
    return ct;
}

static void G6CTCallback(void *conn, CFStringRef name, CFDictionaryRef info, void *ctx) {
    (void)conn, (void)name, (void)info, (void)ctx;
}

// kCTRegistrationRadioAccessTechnology… của mạng đang đăng ký (nil nếu không đọc được)
static NSString *G6RadioTechnology(void) {
    static void *conn;
    void *ct = G6CT();
    if (!ct) return nil;
    if (!conn) {
        void *(*create)(CFAllocatorRef, void *, void *) = (void *(*)(CFAllocatorRef, void *, void *))dlsym(ct, "_CTServerConnectionCreate");
        if (create) conn = create(kCFAllocatorDefault, (void *)G6CTCallback, NULL);
    }
    G6CTResult (*getRAT)(void *, void **) = (G6CTResult (*)(void *, void **))dlsym(ct, "_CTServerConnectionGetRadioAccessTechnology");
    if (!conn || !getRAT) return nil;
    void *out = NULL;
    getRAT(conn, &out);
    if ((uintptr_t)out < 0x10000 || CFGetTypeID((CFTypeRef)out) != CFStringGetTypeID()) return nil;
    return (__bridge_transfer NSString *)out;
}

NSString *G6CellularSummary(void) {
    void *ct = G6CT();
    if (!ct) return @"—";
    CFStringRef (*simStatus)(void) = (CFStringRef (*)(void))dlsym(ct, "CTSIMSupportGetSIMStatus");
    CFStringRef (*regStatus)(void) = (CFStringRef (*)(void))dlsym(ct, "CTRegistrationGetStatus");
    CFStringRef (*copyName)(CFAllocatorRef) = (CFStringRef (*)(CFAllocatorRef))dlsym(ct, "CTRegistrationCopyLocalizedOperatorName");
    NSString *sim = simStatus ? (__bridge NSString *)simStatus() : nil;
    if ([sim isEqualToString:@"kCTSIMSupportSIMStatusNotInserted"]) return G6L(@"Không có SIM");
    NSString *reg = regStatus ? (__bridge NSString *)regStatus() : nil;
    if (![reg hasPrefix:@"kCTRegistrationStatusRegistered"]) {
        if ([reg isEqualToString:@"kCTRegistrationStatusSearching"] || [reg isEqualToString:@"kCTRegistrationStatusUnknown"]) {
            return G6L(@"Đang tìm mạng…");
        }
        return G6L(@"Không có sóng");
    }
    NSString *name = copyName ? (__bridge_transfer NSString *)copyName(kCFAllocatorDefault) : nil;
    NSString *rat = G6RadioTechnology();
    NSString *tech = nil;
    if ([rat hasSuffix:@"LTE"]) tech = @"4G (LTE)";
    else if ([rat hasSuffix:@"UTRAN"] || [rat hasSuffix:@"UTRAN2"]) tech = @"3G";
    else if ([rat hasSuffix:@"GSM"] || [rat hasSuffix:@"GSMCompact"]) tech = @"2G";
    if (name.length && tech) return [NSString stringWithFormat:@"%@ · %@", name, tech];
    return name.length ? name : (tech ?: @"—");
}

// ---- APN / MMS: trả lại như trước khi bật 4G (trang «Mạng dữ liệu di động» — EdgeSettingsController của iOS) ----
//
// Gói 4G phải mang nguyên cặp carrier.plist + overrides có chữ ký của gói nguồn (lte/g6lte.c) nên APN / MMS mặc định của nó là
// của nhà mạng 3 Hồng Kông. iOS cho người dùng sửa các ô này; giá trị đã sửa đè lên gói và iOS tự bỏ chúng khi đổi gói (tắt 4G,
// đổi SIM). Glass 6 sửa đúng như người dùng sửa: gọi getter / setter của từng dòng trong «EDGE Settings.plist» (đo trên iPhone 5
// iOS 6.1.4: ghi xong là ngữ cảnh dữ liệu dùng ngay, kể cả APN trống).

// Thứ tự ghi: Internet trước (dịch vụ chính), rồi MMS, thư thoại hình ảnh — mỗi ô có thể tách ngữ cảnh dùng chung của gói nguồn
static NSArray *G6APNFields(void) {
    return @[@"internet_apn", @"internet_username", @"internet_password", @"mms_apn", @"mms_username", @"mms_password",
             @"mms_mmsc", @"mms_proxy", @"mms_maxmessagesize", @"mms_uaprofurl", @"vvm_apn", @"vvm_username", @"vvm_password",
             @"tethering_apn", @"tethering_username", @"tethering_password"];
}

static BOOL G6APNIsMMSValueField(NSString *field) {
    return [field isEqualToString:@"mms_mmsc"] || [field isEqualToString:@"mms_proxy"] || [field isEqualToString:@"mms_uaprofurl"];
}

// Bộ điều khiển của trang APN (nạp EDGESettings.bundle nếu chưa); nil nếu máy không có
static id G6EdgeController(void) {
    static BOOL loaded;
    if (!loaded) loaded = [[NSBundle bundleWithPath:@"/System/Library/PreferenceBundles/EDGESettings.bundle"] load];
    Class cls = NSClassFromString(@"EdgeSettingsController");
    return cls ? [[cls alloc] init] : nil;
}

static NSDictionary *G6EdgeSpecifiers(id controller) {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    NSArray *specs = nil;
    @try {
        specs = ((NSArray * (*)(id, SEL)) objc_msgSend)(controller, @selector(specifiers));
    } @catch (NSException *e) {
        G6Log(@"4G: không đọc được trang APN: %@", e.reason);
    }
    for (id spec in specs) {
        NSString *sid = [spec valueForKey:@"identifier"];
        if ([sid isKindOfClass:[NSString class]]) out[sid] = spec;
    }
    return out;
}

static NSString *G6APNGet(id controller, id spec, NSString *field) {
    NSString *getter = [field isEqualToString:@"mms_maxmessagesize"] ? @"getMMSNumericValueForSpecifier:"
                       : G6APNIsMMSValueField(field)                ? @"getMMSValueForSpecifier:"
                                                                    : @"getAPNDataForSpecifier:";
    id v = ((id (*)(id, SEL, id))objc_msgSend)(controller, NSSelectorFromString(getter), spec);
    if ([v isKindOfClass:[NSNumber class]]) return [v stringValue];
    return [v isKindOfClass:[NSString class]] ? v : @"";
}

static void G6APNSet(id controller, id spec, NSString *field, NSString *value) {
    NSString *setter = [field isEqualToString:@"mms_maxmessagesize"] ? @"setMMSNumericValue:forSpecifier:"
                       : G6APNIsMMSValueField(field)                ? @"setMMSValue:forSpecifier:"
                                                                    : @"setAPNData:forSpecifier:";
    ((void (*)(id, SEL, id, id))objc_msgSend)(controller, NSSelectorFromString(setter), value, spec);
}

// 5 chữ số đầu của IMSI (MCC + MNC thật của SIM — gói 4G làm CoreTelephony báo MCC/MNC theo gói nguồn, xem lte/g6lte.c).
// Không giữ / ghi phần còn lại của IMSI.
NSString *G6SIMCode(void) {
    void *ct = G6CT();
    CFStringRef (*status)(void) = ct ? (CFStringRef (*)(void))dlsym(ct, "CTSIMSupportGetSIMStatus") : NULL;
    CFStringRef (*imsi)(CFAllocatorRef) = ct ? (CFStringRef (*)(CFAllocatorRef))dlsym(ct, "CTSIMSupportCopyMobileSubscriberIdentity") : NULL;
    CFStringRef (*mcc)(CFAllocatorRef) = ct ? (CFStringRef (*)(CFAllocatorRef))dlsym(ct, "CTSIMSupportCopyMobileSubscriberCountryCode") : NULL;
    CFStringRef (*mnc)(CFAllocatorRef) = ct ? (CFStringRef (*)(CFAllocatorRef))dlsym(ct, "CTSIMSupportCopyMobileSubscriberNetworkCode") : NULL;
    if (!status || ![(__bridge NSString *)status() isEqualToString:@"kCTSIMSupportSIMStatusReady"]) return nil;
    if (imsi) {
        NSString *full = (__bridge_transfer NSString *)imsi(kCFAllocatorDefault);
        if (full.length >= 5) return [full substringToIndex:5];
    }
    if (!mcc || !mnc) return nil;
    NSString *a = (__bridge_transfer NSString *)mcc(kCFAllocatorDefault);
    NSString *b = (__bridge_transfer NSString *)mnc(kCFAllocatorDefault);
    return a.length && b.length ? [a stringByAppendingString:b] : nil;
}

// Gói gốc iOS 6 của mỗi nhà mạng (MobiFone không có gói riêng → Unknown)
static NSString *G6OriginalBundle(NSString *sim) {
    if ([sim isEqualToString:@"45201"]) return @"Unknown.bundle";
    if ([sim isEqualToString:@"45202"]) return @"VinaPhone_vn.bundle";
    if ([sim isEqualToString:@"45204"]) return @"Viettel_vn.bundle";
    return nil;
}

// Giá trị gốc của các ô theo gói gốc của nhà mạng. Dịch vụ theo bit «type-mask» của gói Apple: 1 Internet, 2 thư thoại hình
// ảnh, 4 MMS, 16 / 32 chia sẻ mạng (gói Viettel / VinaPhone: «v-mms», «m3-mms» mang type-mask 4; APN Internet mang 49 = 1|16|32).
// MobiFone: gói Unknown không có MMS, mà iOS không cho ô MMSC đè bằng chữ trống (vẫn hiện MMSC của gói nguồn) → dùng cấu hình MMS
// công bố của MobiFone (APN m-wap, MMSC 203.162.21.114) thay vì để lại địa chỉ của nhà mạng nước ngoài.
static NSDictionary *G6APNDefaults(NSString *sim) {
    NSString *bundle = G6OriginalBundle(sim);
    if (!bundle) return nil;
    NSString *path = [NSString stringWithFormat:@"/System/Library/Carrier Bundles/iPhone/%@/carrier.plist", bundle];
    NSDictionary *carrier = [NSDictionary dictionaryWithContentsOfFile:path];
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    for (NSString *field in G6APNFields()) out[field] = @"";
    NSDictionary *services = @{@"internet" : @1, @"vvm" : @2, @"mms" : @4, @"tethering" : @16};
    for (NSString *svc in services) {
        NSUInteger bit = [services[svc] unsignedIntegerValue];
        for (NSDictionary *apn in carrier[@"apns"]) {
            if (![apn isKindOfClass:[NSDictionary class]] || !([apn[@"type-mask"] unsignedIntegerValue] & bit)) continue;
            for (NSString *key in @[@"apn", @"username", @"password"]) {
                id v = apn[key];
                if ([v isKindOfClass:[NSString class]]) out[[NSString stringWithFormat:@"%@_%@", svc, key]] = v;
            }
            break;
        }
    }
    NSDictionary *mms = carrier[@"MMS"];
    NSDictionary *mmsKeys = @{@"MMSC" : @"mms_mmsc", @"Proxy" : @"mms_proxy", @"MaxMessageSize" : @"mms_maxmessagesize", @"UAProf" : @"mms_uaprofurl"};
    for (NSString *key in mmsKeys) {
        id v = [mms isKindOfClass:[NSDictionary class]] ? mms[key] : nil;
        if ([v isKindOfClass:[NSNumber class]]) v = [v stringValue];
        if ([v isKindOfClass:[NSString class]]) out[mmsKeys[key]] = v;
    }
    if ([sim isEqualToString:@"45201"] && ![out[@"mms_mmsc"] length]) {
        [out addEntriesFromDictionary:@{@"mms_apn" : @"m-wap", @"mms_username" : @"mms", @"mms_password" : @"mms",
                                        @"mms_mmsc" : @G6_MOBIFONE_MMSC, @"mms_proxy" : @G6_MOBIFONE_MMS_PROXY}];
    }
    return out;
}

// Nhóm của ô có hiện trên trang APN không (EdgeSettingsController tự quyết theo gói: vd nhóm chia sẻ mạng của gói nguồn bị ẩn).
// Ô ẩn vẫn được ghi (cố gắng) nhưng không chụp / so / dò giá trị lạ — ghi vào nhóm ẩn có thể không ăn, đừng ghi lại mãi
static BOOL G6APNFieldShown(id controller, NSString *field) {
    int service = [field hasPrefix:@"internet_"] ? 1 : [field hasPrefix:@"vvm_"] ? 2 : [field hasPrefix:@"mms_"] ? 4 : 16;
    SEL sel = NSSelectorFromString(@"_shouldShowUIForServiceType:");
    if (![controller respondsToSelector:sel]) return YES;
    return ((BOOL (*)(id, SEL, int))objc_msgSend)(controller, sel, service);
}

// Tiến trình Cài đặt giữ bộ đệm cấu hình nhà mạng (com.apple.carrier / operator — liên kết tới carrier.plist của gói hoặc bản
// ghép) và MMS sửa tay: sau khi g6lte đổi gói, trang APN vẫn đọc giá trị của gói CŨ cho tới khi app mở lại (đo 20/11/2026) →
// đồng bộ lại trước mỗi lần đọc
static void G6CarrierPrefsSync(void) {
    for (NSString *domain in @[@"com.apple.carrier", @"com.apple.operator", @"com.apple.mms_override"]) {
        CFPreferencesAppSynchronize((__bridge CFStringRef)domain);
    }
}

NSDictionary *G6APNSnapshot(void) {
    G6CarrierPrefsSync();
    id controller = G6EdgeController();
    if (!controller) return nil;
    NSDictionary *specs = G6EdgeSpecifiers(controller);
    if (!specs.count) return nil;
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    for (NSString *field in G6APNFields()) {
        id spec = specs[field];
        if (spec && G6APNFieldShown(controller, field)) out[field] = G6APNGet(controller, spec, field);
    }
    return out;
}

// Ô MMSC / proxy / cỡ tin / UAProf: iOS bỏ qua chữ trống (giữ giá trị của gói) → không ghi, không so
static BOOL G6APNUnsettable(NSString *field, NSString *value) {
    return !value.length && (G6APNIsMMSValueField(field) || [field isEqualToString:@"mms_maxmessagesize"]);
}

// Giá trị cần có của từng ô: ảnh chụp trước khi bật thắng giá trị gốc của nhà mạng — trừ MMS khi ảnh chụp không có MMSC (iOS không
// đè được MMSC bằng chữ trống)
static NSDictionary *G6APNWanted(NSDictionary *values, NSString *sim) {
    NSMutableDictionary *want = [G6APNDefaults(sim) mutableCopy] ?: [NSMutableDictionary dictionary];
    BOOL keepMMSDefaults = ![values[@"mms_mmsc"] length];
    for (NSString *field in values) {
        if (keepMMSDefaults && [field hasPrefix:@"mms_"]) continue;
        want[field] = values[field];
    }
    return want;
}

// Số ô đang khác giá trị cần có (ô không hiện trên trang thì bỏ qua)
static int G6APNMismatch(NSDictionary *want) {
    NSDictionary *now = G6APNSnapshot();
    int n = 0;
    for (NSString *field in want) {
        NSString *value = want[field];
        if (G6APNUnsettable(field, value) || !now[field]) continue;
        if (![now[field] isEqualToString:value]) n++;
    }
    return n;
}

int G6APNRestore(NSDictionary *values, NSString *sim) {
    NSDictionary *want = G6APNWanted(values, sim);
    if (!want.count) return -1;
    G6CarrierPrefsSync();
    int changed = 0;
    for (NSString *field in G6APNFields()) {
        // Mỗi lần ghi có thể đổi cách chia ngữ cảnh → đọc lại trang trước mỗi ô
        id controller = G6EdgeController();
        id spec = controller ? G6EdgeSpecifiers(controller)[field] : nil;
        NSString *value = want[field];
        if (!spec || !value || G6APNUnsettable(field, value)) continue;
        NSString *current = G6APNGet(controller, spec, field);
        if ([current isEqualToString:value]) continue;
        @try {
            G6APNSet(controller, spec, field, value);
            changed++;
        } @catch (NSException *e) {
            G6Log(@"4G: không ghi được ô %@: %@", field, e.reason);
        }
    }
    // MMS của MobiFone là do Glass 6 điền (ảnh chụp không có MMSC) → đặt dấu để lúc tắt 4G / gỡ gói còn biết mà gỡ
    if ([sim isEqualToString:@"45201"] && ![values[@"mms_mmsc"] length] && [want[@"mms_mmsc"] isEqualToString:@G6_MOBIFONE_MMSC]) {
        [[NSData data] writeToFile:@G6_LTE_MMS_MARKER atomically:YES];
    }
    G6Log(@"4G: trả APN / MMS cho SIM %@ — %d ô đã ghi", sim ?: @"?", changed);
    return changed;
}

static void G6After(double seconds, dispatch_block_t block) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), block);
}

// CommCenter đã chạy lại xong: máy đã đăng ký mạng
static BOOL G6CellularSettled(void) {
    void *ct = G6CT();
    CFStringRef (*reg)(void) = ct ? (CFStringRef (*)(void))dlsym(ct, "CTRegistrationGetStatus") : NULL;
    NSString *status = reg ? (__bridge NSString *)reg() : nil;
    return [status hasPrefix:@"kCTRegistrationStatusRegistered"];
}

// Đợi máy đăng ký mạng (tối đa 60 giây — không có sóng thì thôi đợi) rồi thêm 3 giây
static void G6WaitSettled(int waited, dispatch_block_t then) {
    if (G6CellularSettled() || waited >= 60) {
        G6After(3, then);
        return;
    }
    G6After(2, ^{
        G6WaitSettled(waited + 2, then);
    });
}

// Kiểm lại ở các mốc `delays` (giây, tính từ mốc trước); ô nào bị CommCenter đổi về giá trị của gói thì ghi lại
static void G6APNWatch(NSDictionary *values, NSString *sim, NSDictionary *want, NSArray *delays, NSUInteger index, int total,
                       void (^done)(int changed)) {
    if (index >= delays.count) {
        if (total > 0) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                G6CellularDataRefresh();
            });
        }
        if (done) done(total);
        return;
    }
    G6After([delays[index] doubleValue], ^{
        int left = G6APNMismatch(want), changed = 0;
        if (left > 0) {
            G6Log(@"4G: %d ô APN / MMS bị đổi lại — ghi lại", left);
            changed = MAX(0, G6APNRestore(values, sim));
        }
        // Báo xong ngay sau lần kiểm đầu (hộp «Đang bật 4G…» không phải đợi hết); các lần kiểm sau chạy tiếp ở nền
        void (^next)(int) = done;
        if (index == 0 && done) {
            done(total + changed);
            next = nil;
        }
        G6APNWatch(values, sim, want, delays, index + 1, total + changed, next);
    });
}

void G6APNRestoreSettled(NSDictionary *values, NSString *sim, void (^done)(int changed)) {
    // Đợi CommCenter chạy lại xong (máy đăng ký mạng) rồi mới ghi; kiểm lại ba lần trong khoảng một phút sau đó (baseband khởi động
    // lại và bám LTE trong khoảng này) — ô nào bị đổi về giá trị của gói thì ghi lại. Mọi lần đọc đều đồng bộ lại bộ đệm cấu hình
    // nhà mạng (G6CarrierPrefsSync) — thiếu bước đó, trang APN đọc giá trị của gói cũ và bỏ sót ô (đo 20/11/2026)
    NSDictionary *want = G6APNWanted(values, sim);
    G6WaitSettled(0, ^{
        int changed = MAX(0, G6APNRestore(values, sim));
        G6APNWatch(values, sim, want, @[@5, @20, @40], 0, changed, done);
    });
}

// Tắt 4G: «g6lte off» đã gỡ cấu hình MMS mà Glass 6 điền cho SIM MobiFone (có dấu G6_LTE_MMS_MARKER) khỏi tệp; ở đây đồng bộ lại
// bộ đệm của app Cài đặt cho trang APN đọc đúng, và (phòng khi dấu bị mất giữa chừng mà ô còn đúng giá trị Glass 6 điền) gỡ qua
// trang. Ghi chữ trống = bỏ giá trị sửa tay, trang về giá trị của gói gốc.
void G6APNClearInjected(NSString *sim) {
    G6CarrierPrefsSync();
    if (![sim isEqualToString:@"45201"] || access(G6_LTE_MMS_MARKER, F_OK) != 0) return;
    NSDictionary *injected = @{@"mms_mmsc" : @G6_MOBIFONE_MMSC, @"mms_proxy" : @G6_MOBIFONE_MMS_PROXY};
    id controller = G6EdgeController();
    NSDictionary *specs = controller ? G6EdgeSpecifiers(controller) : nil;
    int n = 0;
    for (NSString *field in injected) {
        id spec = specs[field];
        if (spec && [G6APNGet(controller, spec, field) isEqualToString:injected[field]]) {
            G6APNSet(controller, spec, field, @"");
            n++;
        }
    }
    if (n) G6Log(@"4G: đã gỡ %d ô MMS do Glass 6 điền", n);
    unlink(G6_LTE_MMS_MARKER);
}

int G6APNRepairIfForeign(void) {
    NSString *sim = G6SIMCode();
    if (!G6OriginalBundle(sim)) return 0;
    NSString *link = [[NSFileManager defaultManager]
        destinationOfSymbolicLinkAtPath:[@"/System/Library/Carrier Bundles/iPhone" stringByAppendingPathComponent:sim]
                                  error:NULL];
    if (![link hasPrefix:@"Glass6LTE_"]) return 0;  // SIM này đang không dùng gói 4G
    NSDictionary *now = G6APNSnapshot();
    BOOL foreign = NO;
    for (NSString *field in now) {
        if ([now[field] rangeOfString:@"three.com.hk"].location != NSNotFound) foreign = YES;
    }
    if (!foreign) return 0;
    G6APNRestoreSettled(nil, sim, ^(int changed) {
        if (changed > 0) G6Log(@"4G: đã trả APN / MMS về giá trị gốc của nhà mạng");
    });
    return 1;
}

void G6CellularDataRefresh(void) {
    void *ct = G6CT();
    BOOL (*get)(void) = ct ? (BOOL (*)(void))dlsym(ct, "CTCellularDataPlanGetIsEnabled") : NULL;
    void (*set)(BOOL) = ct ? (void (*)(BOOL))dlsym(ct, "CTCellularDataPlanSetIsEnabled") : NULL;
    if (!get || !set || !get()) return;
    set(NO);
    sleep(2);
    set(YES);
}

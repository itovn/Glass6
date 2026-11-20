// g6lte — bật / tắt 4G (LTE dữ liệu) cho SIM MobiFone, Viettel, VinaPhone trên iPhone 5 chạy iOS 6 (setuid root; postinst đặt
// chown root + chmod 4755). Xem docs/DECISIONS.md D47.
//   g6lte status     mỗi dòng «<mã nhà mạng>\t<on|off|other>», thêm «#sim\t<mã MCC+MNC của SIM đang lắp>» và «#active\t<0|1>»
//   g6lte on         dựng gói 4G cho ba nhà mạng, trỏ mã nhà mạng sang gói đó, nạp lại CommCenter
//   g6lte off        trả ba mã nhà mạng về đúng như iOS 6 gốc, xoá các gói đã dựng, nạp lại CommCenter
//
// Cơ chế (iOS 6, đo trên iPhone 5 iOS 6.1.4 ngày 20/11/2026):
// - LTE của iPhone 5 bật theo gói nhà mạng: overrides_N41_N42.plist (Show4GSwitch, tên + chữ ký tệp PRI, APN lúc bám LTE) + tệp
//   PRI (cấu hình baseband có chữ ký Apple). iOS 6 không có gói LTE cho nhà mạng Việt Nam.
// - CommCenter KIỂM CHỮ KÝ: carrier.plist và overrides_N41_N42.plist phải là một cặp nguyên vẹn của CÙNG một gói Apple (mỗi tệp
//   có khoá `signature`; trộn carrier.plist gói này với overrides gói khác, hay tự viết overrides, đều bị loại: CommCenter gỡ
//   liên kết gói và chạy 3G). Bản ghép (Overlay/device+carrier+…) cũng bị đối chiếu — sửa tay là bị loại. Info.plist /
//   version.plist thì không bị kiểm.
// - Vì vậy gói 4G của Glass 6 = Info.plist + version.plist của gói GỐC nhà mạng (danh tính, số bản) + cặp carrier.plist /
//   overrides_N41_N42.plist / .pri NGUYÊN của gói 3 Hồng Kông (Hutchison_hk) có sẵn trong iOS 6: PRI LTE dùng chung bản
//   00.01.071, APN lúc bám LTE để trống (mạng tự cấp), không có số hộp thư thoại hay danh sách dịch vụ của nhà mạng đó.
// - APN / MMS mà gói đó mang theo được bảng Cài đặt của Glass 6 trả lại như trước khi bật (prefs/G6LTE.m — ghi qua chính trang
//   «Mạng dữ liệu di động» của iOS, như người dùng tự sửa). Tắt 4G: CommCenter đổi gói → iOS tự bỏ các giá trị đã sửa.
// - Nạp lại CommCenter bằng launchctl (tắt êm: CommCenter tắt modem, lúc chạy lại đẩy PRI mới xuống baseband → tự bám LTE).
//   `kill -9` thì modem không được khởi động lại.
//
// An toàn (công cụ quyền root mà tiến trình nào chạy quyền mobile cũng gọi được):
// - chỉ ba lệnh cố định, không nhận đường dẫn / mã nhà mạng từ bên gọi; mọi đường dẫn viết cứng;
// - bỏ môi trường của bên gọi, umask 022, đóng tệp thừa, lấp fd 0–2; chỉ app Cài đặt, SpringBoard hoặc root gọi được;
// - chỉ chạy trên iPhone 5 (iPhone5,1 / 5,2) với iOS 6; tệp PRI phải đúng mã SHA-1 đã kiểm;
// - chỉ đổi liên kết của mã nhà mạng khi nó đang ở đúng trạng thái gốc hoặc đang trỏ vào gói của Glass 6 — khác thế (người dùng
//   tự sửa) thì để nguyên và báo;
// - «off» trả đúng ba liên kết như iOS 6 gốc (45201 không có, 45202 → VinaPhone_vn.bundle, 45204 → Viettel_vn.bundle) và xoá
//   các gói đã dựng → hệ thống tệp như chưa từng bật. Gỡ gói Glass 6 (prerm) cũng chạy «off».
// Mã thoát: 0 được · 2 sai cách dùng · 3 máy không hỗ trợ · 4 thiếu / sai gói nguồn LTE · 5 có mã nhà mạng ở trạng thái lạ (bỏ
// qua) · 6 CommCenter không nhận gói 4G cho SIM đang lắp (đã tự trả nhà mạng đó về gốc) · 66 thiếu quyền root · 69 bên gọi không
// được phép · 70 lỗi ghi tệp.
#include <CommonCrypto/CommonDigest.h>
#include <CoreFoundation/CoreFoundation.h>
#include <dirent.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/param.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define CB_DIR "/System/Library/Carrier Bundles/iPhone"
#define OVERLAY_DIR "/var/mobile/Library/Carrier Bundles/Overlay"
#define MOBILE_PREFS "/var/mobile/Library/Preferences"
#define WIRELESS_PREFS "/var/wireless/Library/Preferences"
#define BUNDLE_CACHE WIRELESS_PREFS "/com.apple.commcenter.carrier_bundle.plist"
#define COMMCENTER_PLIST WIRELESS_PREFS "/com.apple.commcenter.plist"
#define CURRENT_BUNDLE "/var/mobile/Library/Carrier Bundle.bundle"
#define OVERRIDES_PLIST "overrides_N41_N42.plist"
#define OVERRIDES_PRI "overrides_N41_N42.pri"
#define COMMCENTER_JOB "/System/Library/LaunchDaemons/com.apple.CommCenter.plist"
// Cấu hình MMS mà bảng Cài đặt điền cho SIM MobiFone khi bật 4G (prefs/G6LTE.h — cùng giá trị) + dấu «đã điền»
#define MMS_OVERRIDE MOBILE_PREFS "/com.apple.mms_override.plist"
#define MMS_MARKER "/var/mobile/Library/Glass6/lte-mms-injected"
#define MOBIFONE_MMSC "http://203.162.21.114/mmsc"
#define MOBIFONE_MMS_PROXY "203.162.21.114:3130"

extern char **environ;
int proc_pidpath(int pid, void *buffer, uint32_t buffersize);

struct carrier {
    const char *code;      // mã MCC+MNC (tên liên kết trong CB_DIR)
    const char *original;  // đích liên kết của iOS 6 gốc (NULL = không có liên kết → gói Unknown)
    const char *base;      // gói gốc cho danh tính (Info.plist, version.plist) của gói 4G
    const char *ours;      // tên gói 4G của Glass 6
};

static const struct carrier kCarriers[] = {
    {"45201", NULL, "Unknown.bundle", "Glass6LTE_MobiFone.bundle"},
    {"45202", "VinaPhone_vn.bundle", "VinaPhone_vn.bundle", "Glass6LTE_VinaPhone.bundle"},
    {"45204", "Viettel_vn.bundle", "Viettel_vn.bundle", "Glass6LTE_Viettel.bundle"},
};
#define CARRIER_COUNT (sizeof(kCarriers) / sizeof(kCarriers[0]))

// Gói nguồn của phần LTE (cặp carrier.plist + overrides có chữ ký, xem đầu tệp). Chọn trong 24 gói iOS 6.1 mang PRI LTE dùng
// chung: chỉ ba gói có APN lúc bám LTE trống (Hutchison_hk, CSL_hk, SmarTone_hk); hai gói sau có số hộp thư thoại của Hồng Kông
// (bấm «Thư thoại» sẽ gọi số đó) → chỉ dùng Hutchison_hk.
static const char kDonor[] = "Hutchison_hk.bundle";
static const char kPriSha1[] = "9dabe0b5a6197a9161f4c5140566edd18f3e4429";
// Các tệp lấy NGUYÊN từ gói nguồn / từ gói gốc của nhà mạng
static const char *const kDonorFiles[] = {"carrier.plist", OVERRIDES_PLIST, OVERRIDES_PRI};
static const char *const kBaseFiles[] = {"Info.plist", "version.plist"};

static const char *const kCallers[] = {
    "/Applications/Preferences.app/Preferences",
    "/System/Library/CoreServices/SpringBoard.app/SpringBoard",
};

static char *gEnv[] = {"PATH=/usr/bin:/bin:/usr/sbin:/sbin", "HOME=/var/root", NULL};

// ---- Tiện ích ----

static void join(char *out, size_t size, const char *dir, const char *name) {
    snprintf(out, size, "%s/%s", dir, name);
}

static int run(char *const argv[]) {
    pid_t pid;
    posix_spawn_file_actions_t fa;
    posix_spawn_file_actions_init(&fa);
    posix_spawn_file_actions_addopen(&fa, 1, "/dev/null", O_WRONLY, 0);
    posix_spawn_file_actions_addopen(&fa, 2, "/dev/null", O_WRONLY, 0);
    int rc = posix_spawn(&pid, argv[0], &fa, NULL, argv, gEnv);
    posix_spawn_file_actions_destroy(&fa);
    if (rc != 0) return -1;
    int status = 0;
    while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {
    }
    return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}

// Đích của một liên kết tượng trưng (rỗng nếu không phải liên kết / không có)
static void link_target(const char *path, char *out, size_t size) {
    ssize_t n = readlink(path, out, size - 1);
    out[n > 0 ? n : 0] = 0;
}

static int is_link(const char *path) {
    struct stat st;
    return lstat(path, &st) == 0 && S_ISLNK(st.st_mode);
}

static int is_dir(const char *path) {
    struct stat st;
    return lstat(path, &st) == 0 && S_ISDIR(st.st_mode);
}

static CFDataRef read_file(const char *path, size_t limit) {
    int fd = open(path, O_RDONLY);
    if (fd < 0) return NULL;
    struct stat st;
    if (fstat(fd, &st) != 0 || !S_ISREG(st.st_mode) || st.st_size <= 0 || (size_t)st.st_size > limit) {
        close(fd);
        return NULL;
    }
    UInt8 *buf = malloc((size_t)st.st_size);
    size_t got = 0;
    ssize_t r;
    while (buf && got < (size_t)st.st_size && (r = read(fd, buf + got, (size_t)st.st_size - got)) > 0) got += (size_t)r;
    close(fd);
    if (!buf || got != (size_t)st.st_size) {
        free(buf);
        return NULL;
    }
    CFDataRef data = CFDataCreate(NULL, buf, (CFIndex)got);
    free(buf);
    return data;
}

static int write_file(const char *path, const UInt8 *bytes, size_t len, mode_t mode) {
    char tmp[PATH_MAX];
    snprintf(tmp, sizeof(tmp), "%s.g6tmp", path);
    unlink(tmp);
    int fd = open(tmp, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode);
    if (fd < 0) return 0;
    size_t done = 0;
    while (done < len) {
        ssize_t w = write(fd, bytes + done, len - done);
        if (w <= 0) {
            close(fd);
            unlink(tmp);
            return 0;
        }
        done += (size_t)w;
    }
    if (close(fd) != 0 || rename(tmp, path) != 0) {
        unlink(tmp);
        return 0;
    }
    return 1;
}

static CFPropertyListRef read_plist(const char *path, CFOptionFlags options) {
    CFDataRef data = read_file(path, 4 * 1024 * 1024);
    if (!data) return NULL;
    CFPropertyListRef plist = CFPropertyListCreateWithData(NULL, data, options, NULL, NULL);
    CFRelease(data);
    return plist;
}

static int write_plist(const char *path, CFPropertyListRef plist, mode_t mode) {
    CFDataRef data = CFPropertyListCreateData(NULL, plist, kCFPropertyListBinaryFormat_v1_0, 0, NULL);
    if (!data) return 0;
    int ok = write_file(path, CFDataGetBytePtr(data), (size_t)CFDataGetLength(data), mode);
    CFRelease(data);
    return ok;
}

static int copy_file(const char *from, const char *to) {
    CFDataRef data = read_file(from, 16 * 1024 * 1024);
    if (!data) return 0;
    int ok = write_file(to, CFDataGetBytePtr(data), (size_t)CFDataGetLength(data), 0644);
    CFRelease(data);
    return ok;
}

static int sha1_matches(const char *path, const char *hex) {
    CFDataRef data = read_file(path, 1024 * 1024);
    if (!data) return 0;
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(CFDataGetBytePtr(data), (CC_LONG)CFDataGetLength(data), digest);
    CFRelease(data);
    char got[CC_SHA1_DIGEST_LENGTH * 2 + 1];
    for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) snprintf(got + i * 2, 3, "%02x", digest[i]);
    return strcmp(got, hex) == 0;
}

// Xoá một thư mục gói do Glass 6 dựng (chỉ một cấp: tệp + liên kết; không theo liên kết)
static void remove_bundle_dir(const char *path) {
    DIR *dir = opendir(path);
    if (dir) {
        struct dirent *e;
        char p[PATH_MAX];
        while ((e = readdir(dir))) {
            if (!strcmp(e->d_name, ".") || !strcmp(e->d_name, "..")) continue;
            join(p, sizeof(p), path, e->d_name);
            unlink(p);
        }
        closedir(dir);
    }
    rmdir(path);
}

// ---- Máy, bên gọi ----

static int device_supported(void) {
    char machine[32] = "";
    size_t len = sizeof(machine);
    if (sysctlbyname("hw.machine", machine, &len, NULL, 0) != 0) return 0;
    if (strcmp(machine, "iPhone5,1") != 0 && strcmp(machine, "iPhone5,2") != 0) return 0;
    CFDictionaryRef sv = read_plist("/System/Library/CoreServices/SystemVersion.plist", kCFPropertyListImmutable);
    int ok = 0;
    if (sv && CFGetTypeID(sv) == CFDictionaryGetTypeID()) {
        CFStringRef v = CFDictionaryGetValue(sv, CFSTR("ProductVersion"));
        ok = v && CFGetTypeID(v) == CFStringGetTypeID() && CFStringHasPrefix(v, CFSTR("6."));
    }
    if (sv) CFRelease(sv);
    return ok;
}

static int caller_allowed(uid_t realUid) {
    if (realUid == 0) return 1;
    char got[4 * MAXPATHLEN];
    memset(got, 0, sizeof(got));
    pid_t parent = getppid();
    if (parent <= 1 || proc_pidpath(parent, got, sizeof(got)) <= 0) return 0;
    for (size_t i = 0; i < sizeof(kCallers) / sizeof(kCallers[0]); i++) {
        char want[PATH_MAX];
        if (realpath(kCallers[i], want) && strcmp(got, want) == 0) return 1;
    }
    return 0;
}

// ---- Trạng thái ----

enum state { STATE_OFF, STATE_ON, STATE_OTHER };

static enum state carrier_state(const struct carrier *c) {
    char path[PATH_MAX], target[PATH_MAX];
    join(path, sizeof(path), CB_DIR, c->code);
    struct stat st;
    if (lstat(path, &st) != 0) return c->original ? STATE_OTHER : STATE_OFF;
    if (!S_ISLNK(st.st_mode)) return STATE_OTHER;
    link_target(path, target, sizeof(target));
    if (!strcmp(target, c->ours)) return STATE_ON;
    if (c->original && !strcmp(target, c->original)) return STATE_OFF;
    return STATE_OTHER;
}

// Tên gói của SIM đang lắp (vd «45201», «Unknown.bundle»); rỗng nếu chưa có
static void current_bundle(char *out, size_t size) {
    char target[PATH_MAX];
    link_target(CURRENT_BUNDLE, target, sizeof(target));
    const char *slash = strrchr(target, '/');
    snprintf(out, size, "%s", slash ? slash + 1 : target);
}

static const struct carrier *carrier_for_code(const char *code) {
    for (size_t i = 0; i < CARRIER_COUNT; i++) {
        if (!strcmp(kCarriers[i].code, code)) return &kCarriers[i];
    }
    return NULL;
}

// ---- Dựng gói 4G ----

// Gói nguồn có đủ cặp tệp và PRI đúng mã kiểm không
static int donor_ok(void) {
    char dir[PATH_MAX], path[PATH_MAX];
    join(dir, sizeof(dir), CB_DIR, kDonor);
    if (!is_dir(dir)) return 0;
    for (size_t i = 0; i < sizeof(kDonorFiles) / sizeof(kDonorFiles[0]); i++) {
        join(path, sizeof(path), dir, kDonorFiles[i]);
        if (access(path, R_OK) != 0) return 0;
    }
    join(path, sizeof(path), dir, OVERRIDES_PRI);
    return sha1_matches(path, kPriSha1);
}

// Dựng <CB_DIR>/<c->ours> trong thư mục tạm rồi đổi tên: danh tính của gói gốc + cặp tệp LTE nguyên của gói nguồn. Không chép
// ảnh logo của gói nguồn (thanh trạng thái hiện tên nhà mạng thật).
static int build_bundle(const struct carrier *c) {
    char baseDir[PATH_MAX], donorDir[PATH_MAX], finalDir[PATH_MAX], tmpDir[PATH_MAX], from[PATH_MAX], to[PATH_MAX];
    join(baseDir, sizeof(baseDir), CB_DIR, c->base);
    join(donorDir, sizeof(donorDir), CB_DIR, kDonor);
    join(finalDir, sizeof(finalDir), CB_DIR, c->ours);
    snprintf(tmpDir, sizeof(tmpDir), "%s.g6tmp", finalDir);
    if (!is_dir(baseDir)) return 0;
    remove_bundle_dir(tmpDir);
    if (mkdir(tmpDir, 0755) != 0) return 0;
    int ok = 1;
    for (size_t i = 0; ok && i < sizeof(kBaseFiles) / sizeof(kBaseFiles[0]); i++) {
        join(from, sizeof(from), baseDir, kBaseFiles[i]);
        join(to, sizeof(to), tmpDir, kBaseFiles[i]);
        ok = copy_file(from, to);
    }
    for (size_t i = 0; ok && i < sizeof(kDonorFiles) / sizeof(kDonorFiles[0]); i++) {
        join(from, sizeof(from), donorDir, kDonorFiles[i]);
        join(to, sizeof(to), tmpDir, kDonorFiles[i]);
        ok = copy_file(from, to);
    }
    if (ok) {
        join(to, sizeof(to), tmpDir, OVERRIDES_PRI);
        ok = sha1_matches(to, kPriSha1);
    }
    if (ok) {
        remove_bundle_dir(finalDir);
        ok = rename(tmpDir, finalDir) == 0;
    }
    if (!ok) remove_bundle_dir(tmpDir);
    return ok;
}

// Đặt liên kết <CB_DIR>/<code> → target (NULL = gỡ liên kết); thay nguyên tử bằng rename
static int set_link(const char *code, const char *target) {
    char path[PATH_MAX], tmp[PATH_MAX];
    join(path, sizeof(path), CB_DIR, code);
    if (!target) return (unlink(path) == 0 || errno == ENOENT);
    snprintf(tmp, sizeof(tmp), "%s/.g6link-%s", CB_DIR, code);
    unlink(tmp);
    if (symlink(target, tmp) != 0) return 0;
    if (rename(tmp, path) != 0) {
        unlink(tmp);
        return 0;
    }
    return 1;
}

// ---- Nạp lại CommCenter ----

// Bỏ khoá CarrierBundleName (CommCenter nhớ cặp SIM ↔ gói ở đây và giữ gói cũ nếu còn khoá) — giữ nguyên các khoá khác
static void forget_bundle_choice(void) {
    struct stat st;
    if (stat(COMMCENTER_PLIST, &st) != 0) return;
    CFMutableDictionaryRef d = (CFMutableDictionaryRef)read_plist(COMMCENTER_PLIST, kCFPropertyListMutableContainers);
    if (!d) return;
    if (CFGetTypeID(d) == CFDictionaryGetTypeID() && CFDictionaryContainsKey(d, CFSTR("CarrierBundleName"))) {
        CFDictionaryRemoveValue(d, CFSTR("CarrierBundleName"));
        if (write_plist(COMMCENTER_PLIST, d, st.st_mode & 0777)) chown(COMMCENTER_PLIST, st.st_uid, st.st_gid);
    }
    CFRelease(d);
}

// Xoá bản ghép cấu hình (Overlay) của ba mã nhà mạng — CommCenter dựng lại từ gói đang dùng
static void remove_overlays(void) {
    DIR *dir = opendir(OVERLAY_DIR);
    if (!dir) return;
    struct dirent *e;
    char path[PATH_MAX], prefix[64];
    while ((e = readdir(dir))) {
        for (size_t i = 0; i < CARRIER_COUNT; i++) {
            snprintf(prefix, sizeof(prefix), "device+carrier+%s+", kCarriers[i].code);
            if (!strncmp(e->d_name, prefix, strlen(prefix))) {
                join(path, sizeof(path), OVERLAY_DIR, e->d_name);
                unlink(path);
            }
        }
    }
    closedir(dir);
}

// Bản ghép cấu hình hiện có của một mã nhà mạng (đường dẫn đầy đủ), rỗng nếu chưa có
static void find_overlay(const char *code, char *out, size_t size) {
    out[0] = 0;
    DIR *dir = opendir(OVERLAY_DIR);
    if (!dir) return;
    struct dirent *e;
    char prefix[64];
    snprintf(prefix, sizeof(prefix), "device+carrier+%s+", code);
    while ((e = readdir(dir))) {
        if (!strncmp(e->d_name, prefix, strlen(prefix))) {
            join(out, size, OVERLAY_DIR, e->d_name);
            break;
        }
    }
    closedir(dir);
}

static void launchctl(const char *verb) {
    char *argv[] = {"/bin/launchctl", (char *)verb, COMMCENTER_JOB, NULL};
    run(argv);
}

// CommCenter đã ghi nhớ gói cho SIM chưa (khoá CarrierBundleName — chỉ ghi khi gói qua được bước kiểm)
static int bundle_choice_saved(void) {
    CFDictionaryRef d = read_plist(COMMCENTER_PLIST, kCFPropertyListImmutable);
    int saved = d && CFGetTypeID(d) == CFDictionaryGetTypeID() && CFDictionaryContainsKey(d, CFSTR("CarrierBundleName"));
    if (d) CFRelease(d);
    return saved;
}

// Mã MCC+MNC của SIM đang lắp (vd «45201»), đọc qua CoreTelephony khi SIM đã sẵn sàng; rỗng nếu không có SIM / chưa đọc được.
// Lấy 5 chữ số đầu của IMSI (ba nhà mạng Việt Nam dùng MNC hai chữ số): khi gói 4G đang dùng, CTSIMSupportCopyMobileSubscriber…
// Code trả MCC/MNC theo gói nguồn (454 / 01, đo 20/11/2026), IMSI thì không. IMSI không được in / ghi ra đâu — chỉ giữ tiền tố.
static void sim_code(char *out, size_t size) {
    out[0] = 0;
    static void *ct;
    if (!ct) ct = dlopen("/System/Library/Frameworks/CoreTelephony.framework/CoreTelephony", RTLD_NOW);
    if (!ct) return;
    CFStringRef (*status)(void) = (CFStringRef (*)(void))dlsym(ct, "CTSIMSupportGetSIMStatus");
    CFStringRef (*imsi)(CFAllocatorRef) = (CFStringRef (*)(CFAllocatorRef))dlsym(ct, "CTSIMSupportCopyMobileSubscriberIdentity");
    CFStringRef (*mcc)(CFAllocatorRef) = (CFStringRef (*)(CFAllocatorRef))dlsym(ct, "CTSIMSupportCopyMobileSubscriberCountryCode");
    CFStringRef (*mnc)(CFAllocatorRef) = (CFStringRef (*)(CFAllocatorRef))dlsym(ct, "CTSIMSupportCopyMobileSubscriberNetworkCode");
    if (!status) return;
    CFStringRef st = status();
    if (!st || !CFEqual(st, CFSTR("kCTSIMSupportSIMStatusReady"))) return;
    if (imsi) {
        CFStringRef id = imsi(kCFAllocatorDefault);
        char buf[32] = "";
        if (id) {
            CFStringGetCString(id, buf, sizeof(buf), kCFStringEncodingUTF8);
            CFRelease(id);
        }
        if (strlen(buf) >= 5) {
            buf[5] = 0;
            snprintf(out, size, "%s", buf);
            memset(buf, 0, sizeof(buf));
            return;
        }
        memset(buf, 0, sizeof(buf));
    }
    if (!mcc || !mnc) return;
    CFStringRef a = mcc(kCFAllocatorDefault), b = mnc(kCFAllocatorDefault);
    char ca[8] = "", cb[8] = "";
    if (a) CFStringGetCString(a, ca, sizeof(ca), kCFStringEncodingUTF8);
    if (b) CFStringGetCString(b, cb, sizeof(cb), kCFStringEncodingUTF8);
    if (a) CFRelease(a);
    if (b) CFRelease(b);
    if (ca[0] && cb[0]) snprintf(out, size, "%s%s", ca, cb);
}

// Gói mà CommCenter phải chọn cho SIM này: tên liên kết của mã (nếu có) hoặc Unknown.bundle
static void expected_bundle(const char *sim, char *out, size_t size) {
    char path[PATH_MAX];
    join(path, sizeof(path), CB_DIR, sim);
    snprintf(out, size, "%s", (sim[0] && is_link(path)) ? sim : "Unknown.bundle");
}

// Nạp lại CommCenter để nó chọn lại gói cho SIM đang lắp: dừng hẳn CommCenter (launchctl — tắt êm, modem tắt theo), bỏ bộ đệm
// danh sách mã, bản ghép cũ và lựa chọn đã nhớ, chạy lại rồi đợi tới khi CommCenter lập liên kết «Carrier Bundle.bundle» tới
// đúng gói VÀ ghi nhớ lựa chọn (= gói đã qua bước kiểm chữ ký). `sim` vào: mã SIM đọc trước khi dừng (rỗng nếu chưa đọc được);
// ra: mã SIM. Trả 1 nếu CommCenter đã nhận gói (hoặc không có SIM để nhận), 0 nếu hết giờ mà chưa nhận.
static int reload_commcenter(char *sim, size_t size) {
    launchctl("unload");
    sleep(1);
    unlink(BUNDLE_CACHE);
    remove_overlays();
    forget_bundle_choice();
    launchctl("load");
    char want[PATH_MAX], cur[PATH_MAX];
    for (int i = 0; i < 60; i++) {
        sleep(2);
        if (!sim[0]) sim_code(sim, size);
        if (!sim[0]) {
            if (i >= 15) return 1;  // không có SIM / không đọc được sau 30 giây: không có gì để đợi
            continue;
        }
        current_bundle(cur, sizeof(cur));
        if (!carrier_for_code(sim)) {
            // SIM của nhà mạng khác: không biết trước tên gói (mã MNC có thể ba chữ số) — chỉ đợi CommCenter nhận xong
            if (cur[0] && bundle_choice_saved()) return 1;
            continue;
        }
        expected_bundle(sim, want, sizeof(want));
        if (!strcmp(cur, want) && bundle_choice_saved()) return 1;
    }
    return 0;
}

// Bản ghép cấu hình của mã này có bật công tắc 4G không (CommCenter đã nhận phần LTE của gói)
static int overlay_has_lte(const char *code) {
    char overlay[PATH_MAX];
    find_overlay(code, overlay, sizeof(overlay));
    if (!overlay[0]) return 0;
    CFDictionaryRef d = read_plist(overlay, kCFPropertyListImmutable);
    int ok = 0;
    if (d && CFGetTypeID(d) == CFDictionaryGetTypeID()) {
        CFTypeRef v = CFDictionaryGetValue(d, CFSTR("Show4GSwitch"));
        ok = v && CFGetTypeID(v) == CFBooleanGetTypeID() && CFBooleanGetValue(v);
    }
    if (d) CFRelease(d);
    return ok;
}

// ---- Lệnh ----

static int cmd_status(void) {
    for (size_t i = 0; i < CARRIER_COUNT; i++) {
        enum state s = carrier_state(&kCarriers[i]);
        printf("%s\t%s\n", kCarriers[i].code, s == STATE_ON ? "on" : s == STATE_OFF ? "off" : "other");
    }
    char sim[16];
    sim_code(sim, sizeof(sim));
    printf("#sim\t%s\n", sim);
    const struct carrier *c = carrier_for_code(sim);
    printf("#active\t%d\n", c && carrier_state(c) == STATE_ON && overlay_has_lte(sim));
    return 0;
}

static int restore_carrier(const struct carrier *c) {
    if (carrier_state(c) == STATE_ON && !set_link(c->code, c->original)) return 0;
    char dir[PATH_MAX];
    join(dir, sizeof(dir), CB_DIR, c->ours);
    if (carrier_state(c) != STATE_ON) remove_bundle_dir(dir);
    return 1;
}

// Gỡ cấu hình MMS mà bảng Cài đặt đã điền cho SIM MobiFone (chỉ khi có dấu, chỉ các ô còn đúng giá trị đó — người dùng tự sửa
// thì để nguyên). iOS giữ MMS sửa tay qua lần đổi gói, nên phải gỡ thì mới về đúng iOS 6 gốc (gói Unknown không có MMS).
static void clear_injected_mms(void) {
    if (access(MMS_MARKER, F_OK) != 0) return;
    struct stat st;
    if (lstat(MMS_OVERRIDE, &st) == 0 && S_ISREG(st.st_mode)) {
        CFMutableDictionaryRef d = (CFMutableDictionaryRef)read_plist(MMS_OVERRIDE, kCFPropertyListMutableContainers);
        if (d && CFGetTypeID(d) == CFDictionaryGetTypeID()) {
            CFMutableDictionaryRef mms = (CFMutableDictionaryRef)CFDictionaryGetValue(d, CFSTR("MMS"));
            int changed = 0;
            if (mms && CFGetTypeID(mms) == CFDictionaryGetTypeID()) {
                CFTypeRef v = CFDictionaryGetValue(mms, CFSTR("MMSC"));
                if (v && CFEqual(v, CFSTR(MOBIFONE_MMSC))) {
                    CFDictionaryRemoveValue(mms, CFSTR("MMSC"));
                    changed = 1;
                }
                v = CFDictionaryGetValue(mms, CFSTR("Proxy"));
                if (v && CFEqual(v, CFSTR(MOBIFONE_MMS_PROXY))) {
                    CFDictionaryRemoveValue(mms, CFSTR("Proxy"));
                    changed = 1;
                }
            }
            if (changed && write_plist(MMS_OVERRIDE, d, st.st_mode & 0777)) chown(MMS_OVERRIDE, st.st_uid, st.st_gid);
        }
        if (d) CFRelease(d);
    }
    unlink(MMS_MARKER);
}

static int cmd_off(void) {
    int rc = 0;
    clear_injected_mms();
    for (size_t i = 0; i < CARRIER_COUNT; i++) {
        const struct carrier *c = &kCarriers[i];
        enum state s = carrier_state(c);
        if (s == STATE_OTHER) {
            fprintf(stderr, "%s: liên kết không phải của Glass 6 — để nguyên\n", c->code);
            rc = 5;
            continue;
        }
        if (!restore_carrier(c)) {
            fprintf(stderr, "%s: không trả được liên kết gốc\n", c->code);
            rc = 70;
        }
    }
    char sim[16], cur[PATH_MAX];
    sim_code(sim, sizeof(sim));
    int accepted = reload_commcenter(sim, sizeof(sim));
    current_bundle(cur, sizeof(cur));
    printf("off: SIM %s, gói đang dùng %s%s\n", sim[0] ? sim : "-", cur[0] ? cur : "-", accepted ? "" : " (CommCenter chưa xong)");
    return rc;
}

static int cmd_on(void) {
    if (!donor_ok()) {
        fprintf(stderr, "không có gói nguồn LTE %s đúng mã kiểm\n", kDonor);
        return 4;
    }
    int rc = 0, changed = 0;
    for (size_t i = 0; i < CARRIER_COUNT; i++) {
        const struct carrier *c = &kCarriers[i];
        enum state s = carrier_state(c);
        if (s == STATE_OTHER) {
            fprintf(stderr, "%s: liên kết không phải của iOS gốc / Glass 6 — để nguyên\n", c->code);
            rc = 5;
            continue;
        }
        if (!build_bundle(c)) {
            fprintf(stderr, "%s: không dựng được gói 4G\n", c->code);
            rc = 70;
            continue;
        }
        if (!set_link(c->code, c->ours)) {
            fprintf(stderr, "%s: không đặt được liên kết\n", c->code);
            restore_carrier(c);
            rc = 70;
            continue;
        }
        changed++;
    }
    char sim[16], cur[PATH_MAX];
    sim_code(sim, sizeof(sim));
    int accepted = reload_commcenter(sim, sizeof(sim));
    current_bundle(cur, sizeof(cur));
    printf("on: SIM %s, gói đang dùng %s\n", sim[0] ? sim : "-", cur[0] ? cur : "-");
    // SIM đang lắp là một trong ba mạng: CommCenter phải nhận gói 4G (lập liên kết + nhớ lựa chọn) và bản ghép phải có phần LTE;
    // không thì trả mạng đó về gốc
    const struct carrier *active = carrier_for_code(sim);
    if (changed && active && carrier_state(active) == STATE_ON && (!accepted || !overlay_has_lte(active->code))) {
        fprintf(stderr, "%s: CommCenter không nhận gói 4G — trả về gốc\n", active->code);
        restore_carrier(active);
        reload_commcenter(sim, sizeof(sim));
        return 6;
    }
    return rc;
}

int main(int argc, char **argv) {
    // Không mang gì của bên gọi theo
    uid_t realUid = getuid();
    environ = gEnv;
    umask(022);
    for (int fd = 0; fd < 3; fd++) {
        if (fcntl(fd, F_GETFD) < 0) {
            int n = open("/dev/null", O_RDWR);
            if (n >= 0 && n != fd) {
                dup2(n, fd);
                close(n);
            }
        }
    }
    for (int fd = 3; fd < 256; fd++) close(fd);
    sigset_t none;
    sigemptyset(&none);
    sigprocmask(SIG_SETMASK, &none, NULL);
    for (int sig = 1; sig < NSIG; sig++) {
        if (sig != SIGKILL && sig != SIGSTOP) signal(sig, SIG_DFL);
    }
    if (argc != 2) {
        fprintf(stderr, "cách dùng: g6lte status | on | off\n");
        return 2;
    }
    int wantStatus = !strcmp(argv[1], "status"), wantOn = !strcmp(argv[1], "on"), wantOff = !strcmp(argv[1], "off");
    if (!wantStatus && !wantOn && !wantOff) {
        fprintf(stderr, "cách dùng: g6lte status | on | off\n");
        return 2;
    }
    if (wantStatus) return cmd_status();  // chỉ đọc, ai gọi cũng được
    if (!caller_allowed(realUid)) {
        fprintf(stderr, "chỉ bảng Cài đặt của Glass 6 được gọi công cụ này\n");
        return 69;
    }
    if (setgid(0) != 0 || setuid(0) != 0) {
        fprintf(stderr, "g6lte cần quyền root (setuid) — cài lại gói vn.glass6.tweak\n");
        return 66;
    }
    // «off» luôn được (để gỡ được trên mọi máy); «on» chỉ trên máy được hỗ trợ
    if (wantOn && !device_supported()) {
        fprintf(stderr, "chỉ dùng được trên iPhone 5 chạy iOS 6\n");
        return 3;
    }
    return wantOn ? cmd_on() : cmd_off();
}

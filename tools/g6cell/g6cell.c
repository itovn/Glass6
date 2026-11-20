// g6cell — trạng thái mạng di động trên máy iOS 6 thử (đăng ký mạng, công nghệ vô tuyến, tốc độ dữ liệu tối đa, sóng).
//   g6cell            in một lần
//   g6cell <giây>     in mỗi 2 giây trong chừng ấy giây (theo dõi lúc baseband khởi động lại / bắt LTE)
//   g6cell http <máy> [đường dẫn]   bật ngữ cảnh dữ liệu di động rồi tải http://<máy><đường dẫn> qua socket GẮN CỨNG vào
//                     giao diện di động (pdp_ip0, IP_BOUND_IF) — thử dữ liệu 4G / 3G mà không phải tắt Wi-Fi. In dòng trạng thái
//                     HTTP, số byte, thời gian, tốc độ. (DNS vẫn hỏi qua đường mặc định.)
// Gọi các hàm C của CoreTelephony (tra bằng dlsym — thiếu hàm nào thì bỏ dòng đó). Không in số máy, IMSI, ICCID.
// Công cụ thử, không đóng vào gói. Dựng: clang của Theos, -framework CoreFoundation (xem cuối tệp).
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <net/if.h>
#include <netdb.h>
#include <netinet/in.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <stdint.h>
#include <unistd.h>

static void *gCT;

static void *sym(const char *name) {
    return gCT ? dlsym(gCT, name) : NULL;
}

static void printCF(const char *label, CFTypeRef value) {
    char buf[512] = "(không có)";
    if (value) {
        CFStringRef text = CFGetTypeID(value) == CFStringGetTypeID() ? CFRetain(value) : CFCopyDescription(value);
        if (text) {
            CFStringGetCString(text, buf, sizeof(buf), kCFStringEncodingUTF8);
            CFRelease(text);
        }
    }
    printf("%-26s %s\n", label, buf);
}

// Hàm _CTServerConnection… trả cấu trúc lỗi 8 byte (trả qua bộ nhớ trên armv7 — khai đúng kiểu thì trình dịch lo)
typedef struct {
    int domain;
    int error;
} CTResult;
static void *gConn;

static void connCallback(void *conn, CFStringRef name, CFDictionaryRef info, void *ctx) {
    (void)conn, (void)name, (void)info, (void)ctx;
}

// Gọi một hàm «CTResult f(conn, void **out)»: out là đối tượng CF (in mô tả) hoặc một số nhỏ (in số)
static void connValue(const char *label, const char *name) {
    CTResult (*fn)(void *, void **) = (CTResult (*)(void *, void **))sym(name);
    if (!fn || !gConn) return;
    void *out = NULL;
    CTResult r = fn(gConn, &out);
    if ((uintptr_t)out < 0x10000) {
        printf("%-26s %ld (lỗi %d/%d)\n", label, (long)(intptr_t)out, r.domain, r.error);
    } else {
        printCF(label, (CFTypeRef)out);
        CFRelease((CFTypeRef)out);
    }
}

static void once(void) {
    time_t now = time(NULL);
    char ts[16];
    strftime(ts, sizeof(ts), "%H:%M:%S", localtime(&now));
    printf("== %s\n", ts);
    CFStringRef (*getString)(void);
    if ((getString = (CFStringRef (*)(void))sym("CTSIMSupportGetSIMStatus"))) printCF("SIM", getString());
    if ((getString = (CFStringRef (*)(void))sym("CTRegistrationGetStatus"))) printCF("đăng ký mạng", getString());
    CFStringRef (*copyName)(CFAllocatorRef) = (CFStringRef (*)(CFAllocatorRef))sym("CTRegistrationCopyOperatorName");
    if (copyName) {
        CFStringRef name = copyName(kCFAllocatorDefault);
        printCF("nhà mạng", name);
        if (name) CFRelease(name);
    }
    // Mã nhà mạng của SIM (MCC / MNC — không phải số riêng) và của mạng đang đăng ký
    CFStringRef (*copyCode)(CFAllocatorRef);
    if ((copyCode = (CFStringRef (*)(CFAllocatorRef))sym("CTSIMSupportCopyMobileSubscriberCountryCode"))) {
        CFStringRef v = copyCode(kCFAllocatorDefault);
        printCF("SIM: MCC", v);
        if (v) CFRelease(v);
    }
    if ((copyCode = (CFStringRef (*)(CFAllocatorRef))sym("CTSIMSupportCopyMobileSubscriberNetworkCode"))) {
        CFStringRef v = copyCode(kCFAllocatorDefault);
        printCF("SIM: MNC", v);
        if (v) CFRelease(v);
    }
    connValue("mạng đăng ký: MCC", "_CTServerConnectionCopyMobileCountryCode");
    connValue("mạng đăng ký: MNC", "_CTServerConnectionCopyMobileNetworkCode");
    connValue("công nghệ vô tuyến", "_CTServerConnectionGetRadioAccessTechnology");
    if ((copyCode = (CFStringRef (*)(CFAllocatorRef))sym("CTRegistrationCopyLocalizedOperatorName"))) {
        CFStringRef v = copyCode(kCFAllocatorDefault);
        printCF("tên mạng (bản địa)", v);
        if (v) CFRelease(v);
    }
    int (*getInt)(void);
    if ((getInt = (int (*)(void))sym("CTRegistrationGetDataIndicator"))) printf("%-26s %d\n", "chỉ báo dữ liệu (số)", getInt());
    if ((getInt = (int (*)(void))sym("CTGetSignalStrength"))) printf("%-26s %d\n", "sóng (dBm / mức)", getInt());
    if ((getString = (CFStringRef (*)(void))sym("CTRegistrationGetCurrentMaxAllowedDataRate"))) printCF("tốc độ tối đa cho phép", getString());
    CFArrayRef (*copyRates)(void) = (CFArrayRef (*)(void))sym("CTRegistrationCopySupportedDataRates");
    if (copyRates) {
        CFArrayRef rates = copyRates();
        printCF("tốc độ hỗ trợ", rates);
        if (rates) CFRelease(rates);
    }
    Boolean (*getBool)(void);
    if ((getBool = (Boolean (*)(void))sym("CTRegistrationGetDataAttached"))) printf("%-26s %d\n", "đã gắn dữ liệu", getBool());
    if ((getBool = (Boolean (*)(void))sym("CTRegistrationGetCellularDataIsEnabled"))) printf("%-26s %d\n", "dữ liệu di động bật", getBool());
    CFDictionaryRef (*copyDict)(void) = (CFDictionaryRef (*)(void))sym("CTRegistrationCopyDataStatus");
    if (copyDict) {
        CFDictionaryRef status = copyDict();
        printCF("trạng thái dữ liệu", status);
        if (status) CFRelease(status);
    }
    fflush(stdout);
}

static double nowMs(void) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return tv.tv_sec * 1000.0 + tv.tv_usec / 1000.0;
}

// Bật ngữ cảnh dữ liệu số 0 (internet) và chờ giao diện di động có địa chỉ. Trả tên giao diện (tĩnh) hoặc NULL.
static const char *bringUp(void) {
    CTResult (*setActive)(void *, int, Boolean) = (CTResult (*)(void *, int, Boolean))sym("_CTServerConnectionSetPacketContextActive");
    CTResult (*copyName)(void *, int, CFStringRef *) = (CTResult (*)(void *, int, CFStringRef *))sym("_CTServerConnectionCopyPacketContextInterfaceName");
    if (setActive && gConn) {
        CTResult r = setActive(gConn, 0, true);
        printf("bật ngữ cảnh dữ liệu 0: lỗi %d/%d\n", r.domain, r.error);
    }
    static char name[IFNAMSIZ] = "pdp_ip0";
    for (int i = 0; i < 30; i++) {
        CFStringRef cf = NULL;
        if (copyName && gConn) {
            copyName(gConn, 0, &cf);
            if (cf) {
                CFStringGetCString(cf, name, sizeof(name), kCFStringEncodingUTF8);
                CFRelease(cf);
            }
        }
        // Có địa chỉ IPv4 chưa: thử gắn một socket UDP vào giao diện và «connect» (không gửi gì)
        unsigned idx = if_nametoindex(name);
        if (idx) {
            int fd = socket(AF_INET, SOCK_DGRAM, 0);
            setsockopt(fd, IPPROTO_IP, IP_BOUND_IF, &idx, sizeof(idx));
            struct sockaddr_in to = {.sin_len = sizeof(to), .sin_family = AF_INET, .sin_port = htons(53)};
            to.sin_addr.s_addr = htonl(0x01010101);
            int ok = connect(fd, (struct sockaddr *)&to, sizeof(to)) == 0;
            struct sockaddr_in me;
            socklen_t len = sizeof(me);
            if (ok && getsockname(fd, (struct sockaddr *)&me, &len) == 0 && me.sin_addr.s_addr != 0) {
                close(fd);
                printf("giao diện %s có địa chỉ (sau %d giây)\n", name, i / 2);
                return name;
            }
            close(fd);
        }
        usleep(500000);
    }
    printf("giao diện %s chưa có địa chỉ sau 15 giây\n", name);
    return NULL;
}

static int httpOverCell(const char *host, const char *path) {
    const char *ifname = bringUp();
    if (!ifname) return 1;
    unsigned idx = if_nametoindex(ifname);
    struct addrinfo hints = {.ai_family = AF_INET, .ai_socktype = SOCK_STREAM}, *ai = NULL;
    if (getaddrinfo(host, "80", &hints, &ai) != 0 || !ai) {
        printf("không phân giải được %s\n", host);
        return 1;
    }
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (setsockopt(fd, IPPROTO_IP, IP_BOUND_IF, &idx, sizeof(idx)) != 0) {
        printf("không gắn được socket vào %s\n", ifname);
        return 1;
    }
    struct timeval tmo = {20, 0};
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tmo, sizeof(tmo));
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tmo, sizeof(tmo));
    double t0 = nowMs();
    if (connect(fd, ai->ai_addr, ai->ai_addrlen) != 0) {
        printf("không kết nối được tới %s qua %s\n", host, ifname);
        return 1;
    }
    double t1 = nowMs();
    char req[512];
    snprintf(req, sizeof(req), "GET %s HTTP/1.0\r\nHost: %s\r\nUser-Agent: g6cell\r\nConnection: close\r\n\r\n", path, host);
    send(fd, req, strlen(req), 0);
    static char buf[65536];
    long total = 0;
    char status[128] = "";
    ssize_t n;
    while ((n = recv(fd, buf, sizeof(buf), 0)) > 0) {
        if (!total) {
            size_t k = 0;
            while (k < (size_t)n && k < sizeof(status) - 1 && buf[k] != '\r' && buf[k] != '\n') {
                status[k] = buf[k];
                k++;
            }
            status[k] = 0;
        }
        total += n;
    }
    double t2 = nowMs();
    close(fd);
    freeaddrinfo(ai);
    printf("qua %s: kết nối %.0f ms | «%s» | %ld byte trong %.0f ms", ifname, t1 - t0, status, total, t2 - t1);
    if (t2 > t1 && total > 100000) printf(" | %.0f KB/s", total / 1024.0 / ((t2 - t1) / 1000.0));
    printf("\n");
    return total > 0 ? 0 : 1;
}

int main(int argc, char **argv) {
    gCT = dlopen("/System/Library/Frameworks/CoreTelephony.framework/CoreTelephony", RTLD_NOW);
    if (!gCT) {
        fprintf(stderr, "không nạp được CoreTelephony\n");
        return 1;
    }
    void *(*create)(CFAllocatorRef, void *, void *) = (void *(*)(CFAllocatorRef, void *, void *))sym("_CTServerConnectionCreate");
    if (create) gConn = create(kCFAllocatorDefault, (void *)connCallback, NULL);
    if (argc > 2 && strcmp(argv[1], "http") == 0) return httpOverCell(argv[2], argc > 3 ? argv[3] : "/");
    int seconds = argc > 1 ? atoi(argv[1]) : 0;
    once();
    for (int t = 2; t <= seconds; t += 2) {
        sleep(2);
        once();
    }
    return 0;
}

// Dựng trên máy dựng (Theos):
//   ~/theos/toolchain/linux/iphone/bin/clang -target armv7-apple-ios6.0 -isysroot ~/theos/sdks/iPhoneOS9.3.sdk \
//       -framework CoreFoundation -o g6cell g6cell.c && ~/theos/toolchain/linux/iphone/bin/ldid -S g6cell

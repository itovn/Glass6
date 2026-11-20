#include "G6Device.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/sysctl.h>

// Bảng mẫu máy được phép. KHÔNG thêm mã máy vào đây khi chưa làm và thử giao diện trên đúng máy đó.
static const struct {
    const char *machine;
    G6DeviceKind kind;
} kDevices[] = {
    {"iPad2,5", G6DevicePadMini1},   // iPad mini 1 Wi-Fi
    {"iPad2,6", G6DevicePadMini1},   // iPad mini 1 GSM
    {"iPad2,7", G6DevicePadMini1},   // iPad mini 1 toàn cầu — máy thử
    {"iPhone5,1", G6DevicePhone5},   // iPhone 5 GSM
    {"iPhone5,2", G6DevicePhone5},   // iPhone 5 toàn cầu — máy thử
    {"iPad3,4", G6DevicePad4},       // iPad 4 Wi-Fi — máy thử (20/11/2026)
    {"iPad3,5", G6DevicePad4},       // iPad 4 GSM
    {"iPad3,6", G6DevicePad4},       // iPad 4 toàn cầu
};

// Số đầu của mã bản dựng iOS: 10 = iOS 6 (10A… = 6.0, 10B… = 6.1); 9 = iOS 5; 11 = iOS 7
#define G6_IOS6_BUILD_MAJOR 10

static char gMachine[32];
static int gKind = -1;

#if G6_DEBUG
// Bản thử: giả một mã máy khác để thử hàng rào ngay trên máy thật (tệp chứa mã máy, vd «iPad3,1»)
static void g6_device_fake(char *machine, size_t size) {
    static const char *const paths[] = {"/var/mobile/Library/Glass6/fake-machine", "/var/tmp/vn.glass6/fake-machine"};
    for (int i = 0; i < 2; i++) {
        FILE *f = fopen(paths[i], "r");
        if (!f) continue;
        char buf[32] = "";
        if (fgets(buf, sizeof(buf), f)) {
            buf[strcspn(buf, "\r\n ")] = 0;
            if (buf[0]) {
                strncpy(machine, buf, size - 1);
                machine[size - 1] = 0;
            }
        }
        fclose(f);
        return;
    }
}
#endif

static void g6_device_probe(void) {
    size_t size = sizeof(gMachine);
    if (sysctlbyname("hw.machine", gMachine, &size, NULL, 0) != 0) gMachine[0] = 0;
    gMachine[sizeof(gMachine) - 1] = 0;
#if G6_DEBUG
    g6_device_fake(gMachine, sizeof(gMachine));
#endif
    char build[32] = "";
    size = sizeof(build);
    if (sysctlbyname("kern.osversion", build, &size, NULL, 0) != 0) build[0] = 0;
    build[sizeof(build) - 1] = 0;
    int kind = G6DeviceUnsupported;
    if (atoi(build) == G6_IOS6_BUILD_MAJOR) {
        for (size_t i = 0; i < sizeof(kDevices) / sizeof(kDevices[0]); i++) {
            if (strcmp(gMachine, kDevices[i].machine) == 0) {
                kind = kDevices[i].kind;
                break;
            }
        }
    }
    gKind = kind;
}

G6DeviceKind g6_device_kind(void) {
    if (gKind < 0) g6_device_probe();
    return (G6DeviceKind)gKind;
}

const char *g6_device_machine(void) {
    if (gKind < 0) g6_device_probe();
    return gMachine;
}

const char *g6_device_name(G6DeviceKind kind) {
    switch (kind) {
        case G6DevicePadMini1:
            return "ipad-mini-1";
        case G6DevicePhone5:
            return "iphone-5";
        case G6DevicePad4:
            return "ipad-4";
        default:
            return "unsupported";
    }
}

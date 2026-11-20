// Rào theo mẫu máy (anh yêu cầu 19/11/2026): Glass 6 chỉ chạy trên các mẫu máy ĐÃ ĐƯỢC LÀM VÀ THỬ. Mỗi mẫu là một bộ giao
// diện được khai rõ; máy lạ thì mọi phần của tweak đứng yên (SpringBoard, app, bảng Cài đặt chỉ báo «chưa hỗ trợ») — không
// suy ra bố cục cho máy chưa thử. Thêm mẫu máy = thêm dòng vào bảng trong G6Device.c + làm phần giao diện của mẫu đó.
//
// Viết bằng C thuần (libc), không phụ thuộc lõi: phải trả lời được trước khi nạp bất cứ thứ gì.
#ifndef G6_DEVICE_H
#define G6_DEVICE_H

typedef enum {
    G6DeviceUnsupported = 0,
    G6DevicePadMini1,  // iPad mini 1 (iPad2,5 / 2,6 / 2,7), iOS 6 — giao diện kiểu iPadOS 26
    G6DevicePhone5,    // iPhone 5 (iPhone5,1 / 5,2), iOS 6 — giao diện kiểu iOS 26 của iPhone
} G6DeviceKind;

// Mẫu máy đang chạy (tra một lần rồi nhớ). Unsupported nếu mã máy không có trong bảng HOẶC bản iOS không phải iOS 6.
G6DeviceKind g6_device_kind(void);
// Mã máy thật («iPad2,7», «iPhone5,2»…); chuỗi rỗng nếu không đọc được
const char *g6_device_machine(void);
// Tên ngắn của mẫu, dùng trong cấu hình / nhật ký: «ipad-mini-1», «iphone-5», «unsupported»
const char *g6_device_name(G6DeviceKind kind);
// Tiện dùng
static inline int g6_device_supported(void) {
    return g6_device_kind() != G6DeviceUnsupported;
}
static inline int g6_device_is_pad(void) {
    return g6_device_kind() == G6DevicePadMini1;
}
static inline int g6_device_is_phone(void) {
    return g6_device_kind() == G6DevicePhone5;
}

#endif

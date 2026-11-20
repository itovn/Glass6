// Bộ gác an toàn — chỉ dùng libc, chạy TRƯỚC mọi việc khác (trước cả khi nạp lõi Rust): công tắc tổng bằng tệp và bộ đếm
// «khởi động mà chưa chạy ổn». Xem docs/THIET-KE.md mục 8.
#ifndef G6_GUARD_H
#define G6_GUARD_H

#ifdef __cplusplus
extern "C" {
#endif

// Thư mục dữ liệu của Glass 6 (postinst tạo, chủ là mobile)
#define G6_DIR "/var/mobile/Library/Glass6"
// Có tệp này thì Glass 6 không làm gì — tạo qua SSH (`touch`) để tắt hẳn
#define G6_OFF_FILE G6_DIR "/off"
// Glass 6 tự tạo khi tiến trình khởi động G6_BOOT_LIMIT lần liền mà không lần nào chạy ổn; Cài đặt xoá khi người dùng bật lại
#define G6_AUTO_OFF_FILE G6_DIR "/off.auto"
// Thư mục dùng chung cho phần nạp vào app (Glass6UI): bộ đếm / dấu «bỏ qua» của từng app, nhật ký và tệp công cụ thử của app
// trong hộp cát. Nằm ở /var/tmp vì hộp cát của Mail, Safari, Ảnh… không cho đụng G6_DIR nhưng cho ghi /var/tmp.
#define G6_APP_DIR "/var/tmp/vn.glass6"
// Số lần khởi động liền chưa xác nhận thì tự tắt. 3 chứ không 2: khởi động lại SpringBoard hai lần sát nhau là chuyện thường.
#define G6_BOOT_LIMIT 3

enum {
    G6GuardRun = 0,      // được chạy
    G6GuardOffFile = 1,  // có tệp «off»
    G6GuardAutoOff = 2,  // đã tự tắt vì sập liên tiếp
    G6GuardAppSkip = 3,  // riêng app này bị bỏ qua vì nó sập liên tiếp lúc có Glass 6
};

// Gọi đầu tiên khi được nạp vào tiến trình `process` (vd "SpringBoard"). Trả G6GuardRun nếu được chạy và tăng bộ đếm;
// khác thì phải thôi ngay.
int g6_guard_begin(const char *process);

// Tiến trình đã chạy ổn (SpringBoard: 20 giây sau khi mở xong) → bộ đếm về 0.
void g6_guard_confirm(const char *process);

// Như trên cho một app (Glass6UI), bộ đếm riêng G6_APP_DIR/app.<tên>: app mở G6_BOOT_LIMIT lần liền mà không lần nào chạy ổn
// thì CHỈ app đó bị bỏ qua (tệp skip.<tên>) — các app khác và SpringBoard không bị ảnh hưởng. «Đặt lại bộ gác» trong Cài
// đặt xoá. App không ghi được vào G6_APP_DIR thì cũng bị bỏ qua (không gác được thì không đụng).
int g6_guard_app_begin(const char *process);
void g6_guard_app_confirm(const char *process);

#ifdef __cplusplus
}
#endif

#endif

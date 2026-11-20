// glass6ctl — công cụ dòng lệnh (quyền mobile) kiểm và tải bản cập nhật của Glass 6 qua HTTPS. Toàn bộ nằm ở lõi Rust
// (core/crates/g6-ctl → libg6_ctl.a); tệp này chỉ là điểm vào. Xem docs/THIET-KE.md mục 10.
extern int g6ctl_main(int argc, char **argv);

int main(int argc, char **argv) {
    return g6ctl_main(argc, argv);
}

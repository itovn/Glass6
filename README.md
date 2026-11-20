# Glass 6

**Liquid Glass (iOS 26 / iPadOS 26) cho iOS 6.** Tweak cho **iPhone 5** và **iPad mini 1** chạy iOS 6 đã jailbreak: đổi giao
diện hệ thống sang kính trong — màn hình chính, màn khoá, thông báo, Control Center, khay đa nhiệm, thanh và bảng trong app —
có chế độ sáng / tối, kèm tinh chỉnh dịch vụ nền của iOS 6 và bảng điều khiển trong Cài đặt. Lõi viết bằng **Rust**, vỏ
**Objective-C** thuần (móc hàm lúc chạy, không Logos) nạp bằng MobileSubstrate, dựng bằng Theos.

*English: Glass 6 brings the Liquid Glass look of iOS 26 to jailbroken iPhone 5 and iPad mini 1 on iOS 6 — Home screen, lock
screen, notifications, a Control Center, a card app switcher, restyled bars and tables inside Apple's apps, light / dark mode.
Rust core, plain Objective-C shell. The interface is available in English and Vietnamese; the source comments and docs are in
Vietnamese.*

- Trang giới thiệu: <https://itovn.github.io/Glass6/> · English: <https://itovn.github.io/Glass6/en.html>
- Nguồn Cydia: `https://itovn.github.io/Glass6/cydia/`
- Gói `.deb`: [Releases](https://github.com/itovn/Glass6/releases)

## Có gì

- **Màn hình chính**: dock, thư mục, ô tìm kiếm bằng kính; bốn kiểu biểu tượng (mặc định, tối, trong, nhuộm màu); biểu tượng
  Đồng hồ có kim chạy thật.
- **Màn khoá** kiểu iOS 26: đồng hồ lớn, rãnh trượt kính, thông báo dạng thẻ.
- **Control Center** (iOS 6 chưa có), Trung tâm thông báo, băng thông báo, hộp thoại, bảng chọn, bảng âm lượng.
- **Khay đa nhiệm**: dạng thẻ trên iPhone, dải kính trên iPad.
- **Trong app**: thanh điều hướng, thanh thẻ, bảng, công tắc, thanh trượt, bàn phím; vẽ lại riêng Cài đặt, Đồng hồ, Ghi chú,
  Lời nhắc, Lịch, Danh bạ, Ảnh, Tin nhắn và (iPhone) Điện thoại, Máy tính, La bàn, Ghi âm. App không phải của Apple giữ nguyên.
- **Sáng / tối / tự động theo giờ**; nút AssistiveTouch riêng; dải hiệu suất (CPU, RAM, mạng) trên thanh trạng thái.
- **Dịch vụ hệ thống**: tắt các dịch vụ nền của iOS 6 đã ngừng từ lâu, chặn cập nhật iOS — từng mục một, bật lại được.
- **Bật 4G** (iPhone 5): LTE cho SIM MobiFone, Viettel, VinaPhone bằng phần LTE có sẵn trong iOS 6; APN / MMS giữ như trước;
  tắt là về đúng 3G gốc. Gọi điện vẫn qua 3G (iOS 6 không có VoLTE).
- **Tự cập nhật (OTA)** trong Cài đặt › Glass 6: chỉ cài gói có chữ ký số đúng.
- Mọi thành phần có công tắc riêng. Giao diện tiếng Việt và tiếng Anh.

## Máy chạy được

**iPhone 5** (iPhone5,1 / 5,2) và **iPad mini 1** (iPad2,5 / 2,6 / 2,7), iOS 6.0 – 6.1.x đã jailbreak, có MobileSubstrate và
PreferenceLoader. Đã làm và thử trên iPhone 5 (iOS 6.1.4) và iPad mini 1 (iOS 6.1.3). Trên mẫu máy khác Glass 6 không nạp
thành phần nào (bảng Cài đặt nói rõ lý do) — mỗi mẫu máy phải được làm và thử riêng.

## Cài

Thêm nguồn `https://itovn.github.io/Glass6/cydia/` vào Cydia, cài «Glass 6», bấm «Restart SpringBoard». Hoặc tải `.deb` ở
Releases rồi `dpkg -i` qua SSH và khởi động lại SpringBoard. Tuỳ chỉnh ở Cài đặt › Glass 6.

## An toàn

- SpringBoard sập thì Substrate Safe Mode tắt mọi tweak như thường lệ.
- Tắt hẳn Glass 6 qua SSH: `touch /var/mobile/Library/Glass6/off` rồi khởi động lại SpringBoard. Bật lại: xoá tệp đó.
- SpringBoard khởi động 3 lần liền mà Glass 6 chưa lần nào chạy ổn thì Glass 6 tự tắt; bật lại trong Cài đặt › Glass 6 ›
  «Đặt lại bộ gác». Mỗi app cũng có bộ đếm riêng: app sập liên tiếp lúc mở thì Glass 6 bỏ qua app đó.
- Glass 6 không sửa tệp nào của hệ thống — gỡ gói là sạch. Ngoại lệ duy nhất là «Bật 4G» (iPhone 5, phải tự bật): thêm gói
  nhà mạng `Glass6LTE_*.bundle` và đổi ba liên kết mã nhà mạng (452-01 / 02 / 04) trong `/System/Library/Carrier Bundles/iPhone`;
  tắt công tắc hoặc gỡ gói thì trả đúng ba liên kết gốc và xoá các gói đó.
- Cập nhật OTA: gói tải từ GitHub Releases của repo này; công cụ cài (`g6update`, quyền root) kiểm chữ ký RSA-3072 của gói
  bằng khoá công khai gắn sẵn rồi mới cài. Nguồn Cydia ký GPG, khoá công khai đi kèm gói.

## Cấu trúc mã

| Thư mục | Nội dung |
| --- | --- |
| `core/` | Lõi Rust: `g6-core` (vật liệu kính, bảng màu, cấu hình, danh mục dịch vụ, bộ gác), `g6-ffi` (mặt C → `libglass6core.dylib`), `g6-ctl` (`glass6ctl`: kiểm / tải bản mới qua HTTPS bằng rustls) |
| `tweak/SB/` | `Glass6SB.dylib` — nạp vào SpringBoard |
| `tweak/UI/` | `Glass6UI.dylib` — nạp vào các app của Apple trong phạm vi |
| `tweak/Common/` | Mã dùng chung (móc hàm, kính, cấu hình, hộp thoại, ngôn ngữ…) |
| `tweak/Debug/` | Công cụ thử — chỉ có trong bản thử, bản phát hành không dịch |
| `prefs/` | Bảng Cài đặt › Glass 6 |
| `svc/`, `helper/`, `ctl/` | `g6svc` (bật / tắt dịch vụ, setuid root), `g6update` (cài bản cập nhật đã kiểm chữ ký, setuid root), điểm vào của `glass6ctl` |
| `lte/` | `g6lte` (iPhone 5: bật / tắt 4G cho ba nhà mạng Việt Nam, setuid root) |
| `data/` | Danh mục dịch vụ, bảng dịch tiếng Anh |
| `tools/` | Dựng, sinh mã, phát hành |

## Dựng từ mã nguồn

Máy Ubuntu có [Theos](https://theos.dev) (SDK iPhoneOS 9.3) và Rust nightly (`rust-src`):

```sh
bash tools/build.sh                    # bản thử (có công cụ thử tweak/Debug/)
bash tools/build-release.sh            # bản phát hành + danh sách ký hiệu để tra trên máy iOS 6
```

Lõi dựng cho armv7 bằng target tự định nghĩa (`tools/rust/armv7-apple-ios6.json`, `-Z build-std`). `glass6ctl` dùng rustls +
ring; ring cần bản vá cho ARM 32-bit của Apple — `tools/rust/cargo-ios6.sh` tự vá lần đầu (`tools/rust/vendor-ring.sh`).
Chạy thử lõi trên PC:

```sh
cd core
cargo test
cargo run --release -p g6-core --example preview -- ./out [hình-nền.png]   # ảnh mẫu các tấm kính
```

Bản tự dựng không cập nhật OTA được từ repo này (chữ ký của gói phải khớp `helper/ota_cert.h`); muốn tự phát hành thì tạo
khoá riêng và sinh lại tệp đó bằng `tools/gen_ota_cert.py`.

## Tài liệu

| Tệp | Nội dung |
| --- | --- |
| [docs/THIET-KE.md](docs/THIET-KE.md) | Phương án thiết kế: kiến trúc, vật liệu kính, các đợt giao diện, dịch vụ, an toàn, phát hành |
| [docs/IPHONE.md](docs/IPHONE.md) | Bản cho iPhone 5: khảo sát và kế hoạch |
| [docs/DECISIONS.md](docs/DECISIONS.md) | Các quyết định kỹ thuật và kết quả kiểm chứng |
| [docs/FFI.md](docs/FFI.md) | Hợp đồng giữa vỏ ObjC và lõi Rust, khoá cấu hình |

## Giấy phép

[GPL-3.0](LICENSE) (như GramMini). `corelib/G6Shims.c`, `tools/rust/` chép từ GramMini / Côn Bằng TV Legacy (GPL-3.0).

Phông [Inter](https://github.com/rsms/inter) đóng kèm trong `layout/Library/Application Support/Glass6/Fonts/` theo giấy phép
SIL Open Font License 1.1 (`LICENSE-Inter.txt` cùng thư mục). `glass6ctl` liên kết các thư viện Rust rustls, ring,
rustls-webpki, webpki-roots, serde_json (giấy phép Apache-2.0 / MIT / ISC / CDLA-Permissive-2.0 — xem từng crate).

Glass 6 là dự án độc lập, không liên quan tới Apple. «Liquid Glass», iOS, iPadOS là nhãn hiệu của Apple Inc.

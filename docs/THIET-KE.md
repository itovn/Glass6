# Glass 6 — Phương án thiết kế (chốt 19/11/2026)

Tweak cho **iPad chạy iOS 6 đã jailbreak**: đổi giao diện hệ thống sang phong cách iPadOS 26 (Liquid Glass), có chế độ sáng /
tối, tinh chỉnh dịch vụ nền của iOS 6, bảng điều khiển trong Cài đặt. Lõi viết bằng **Rust**, vỏ **Objective-C** nạp bằng
MobileSubstrate — cùng bộ dựng đã chạy thật ở Côn Bằng TV Legacy và GramMini.

Tham khảo (các dự án cùng tác giả):

| Nguồn | Lấy gì |
| --- | --- |
| Côn Bằng TV Legacy | Bộ dựng Rust cho armv7 iOS 5 / 6 (target JSON, build-std), cầu FFI JSON, bẫy iOS 6 (bo góc làm giật), công cụ thử qua SSH (`cbscreen`, `cblaunch`, `cbsymcheck`), tweak `CBFloat` |
| GramMini | Cách phát hành: repo riêng tư + repo công khai `itovn/…`, nguồn Cydia ký GPG trên gh-pages, OTA qua GitHub Releases có chữ ký số (`gmupdate`) |
| GramMusic (tweak `GramLockControl`) | Tweak màn khoá đang nạp trên máy thử — phải chung sống |

---

## 0. Tóm tắt các quyết định

1. **Phạm vi nạp:** mặc định chỉ SpringBoard và app của Apple. App bên thứ ba bật tay từng app trong Cài đặt.
2. **Phát hành công khai lên Cydia.** Phông dùng **Inter** (giấy phép OFL, đủ dấu tiếng Việt) thay cho SF của Apple; biểu
   tượng xử lý bằng thuật toán (bo góc, viền kính, nhuộm màu), không đóng kèm ảnh của Apple.
3. **Dịch vụ:** cài xong không tắt gì. Người dùng tự chọn hồ sơ hoặc tắt từng dịch vụ.
4. **Máy đích trước mắt: iPad** (1024×768 @1x). Lõi dựng ảnh theo tỉ lệ màn hình nên thêm iPhone sau không phải viết lại.
5. **Không có kính mờ thời gian thực** (iOS 6 thiếu `CABackdropLayer`) → kính dựng từ ảnh mờ sẵn hoặc ảnh chụp một lần (mục 2).
6. **Không sửa tệp hệ thống.** Mọi thay đổi giao diện làm lúc chạy; dịch vụ tắt qua `overrides.plist` của launchd. Gỡ gói là sạch.
7. **Vỏ ObjC thuần, không Logos:** tra lớp / hàm lúc chạy, thiếu thì bỏ qua, luôn gọi hàm gốc.
8. **Repo và OTA theo GramMini:** repo phát triển riêng tư, repo công khai `itovn/Glass6` (mã sạch +
   Releases + gh-pages làm trang giới thiệu và nguồn Cydia), cập nhật OTA có chữ ký số.

---

## 1. Máy đích và hiện trạng (khảo sát 19/11/2026)

| | |
| --- | --- |
| Máy | iPad mini 1 (iPad2,7), iOS 6.1.3 (10B329), jailbreak p0sixspwn |
| Chip / RAM | A5 hai nhân, 512 MB — còn trống ~113 MB khi 9 app nằm nền |
| Màn hình | 1024×768 @1x (786 nghìn điểm ảnh — nhẹ cho việc làm mờ) |
| Đĩa | phân vùng hệ thống còn ~745 MB |
| Nền tảng tweak | MobileSubstrate 0.9.6301, Substrate Safe Mode 0.9.6001, PreferenceLoader 2.2.6 |
| Không có | WinterBoard, Activator, Flipswitch, libstatusbar, tweak giao diện nào khác |

API đã tra trên máy bằng `cbsymcheck`:

- **Thiếu:** `CABackdropLayer`, `_UIBackdropView`, `CARenderServerCaptureLayer`.
- **Có:** `CAFilter`, `CARenderServerRenderDisplay`, `CARenderServerRenderLayer`, `_UIImageWithName`, `UIGetScreenImage`,
  `UICreateScreenImage`, vImage (`vImageBoxConvolve_ARGB8888`…), `CIFilter`.

Tweak đang nạp và cách chung sống:

| Tweak | Đụng vào | Glass 6 làm gì |
| --- | --- | --- |
| CBFloat | Cửa sổ mức 1050 trong SpringBoard, không móc hàm | Không dùng mức 1050 cho cửa sổ của mình |
| GMNotify, RZNotify | 3 hàm danh sách của `SBPushStore` / `SBRemoteNotificationServer` | Không móc các hàm đó |
| GramLockControl | `SBAwayView` (`didMoveToWindow`, `layoutSubviews`) — thêm khung nhạc lên màn khoá | Không thay `SBAwayView`; chỉ trang điểm, chừa chỗ cho khung nhạc |
| App tự vẽ giao diện (app bên thứ ba) | Giao diện riêng của app | Mặc định không nạp phần UIKit vào |

Ngân sách hiệu năng (đo trên iPad mini 1):

- SpringBoard: Glass 6 thêm ≤ 12 MB RAM; vuốt trang màn hình chính giữ ≥ 55 khung/s.
- Mở một tấm kính (Control Center, thông báo, hộp thoại): từ lúc chạm tới lúc hiện ≤ 120 ms. Đo 19/11/2026: khối 320×400
  mất ~80 ms (chụp + làm mờ 1/8: 45 ms; dựng kính: 35 ms; bóng đổ lấy từ bộ nhớ đệm: 0,5 ms).
- App được nạp: thêm ≤ 60 ms lúc mở, ≤ 2 MB RAM; cuộn danh sách không chậm đi.
- Không dùng `layer.cornerRadius` + `clipsToBounds` trên thứ chuyển động (bài học của Côn Bằng TV: 14 → 50 khung/s khi bỏ).

---

## 2. Vật liệu kính trên iOS 6

iOS 6 không làm mờ được thứ nằm dưới một lớp ngay lúc vẽ. Ba cách thay, tuỳ bề mặt:

| Bề mặt | Nền bên dưới | Cách dựng |
| --- | --- | --- |
| Dock, thư mục, màn khoá, thông báo trên màn hình chính | Hình nền (đứng yên) | Làm mờ sẵn hình nền **một lần**, lưu đệm; mỗi tấm kính cắt đúng vùng của nó |
| Control Center, thông báo kéo xuống trên app, hộp thoại, HUD âm lượng | App đang mở | **Chụp màn hình một lần** lúc sắp hiện (`CARenderServerRenderDisplay`), thu nhỏ 1/8, làm mờ; đứng yên trong lúc mở |
| Thanh điều hướng, thanh công cụ, thanh tab trong app | Nội dung cuộn | Kính giả: nền trong mờ + viền sáng + bóng, không làm mờ nội dung chạy dưới |

Một tấm kính gồm các lớp, lõi Rust dựng thành **một ảnh** rồi giao cho CALayer (không bắt GPU cắt bo góc):

1. Nền: ảnh đã mờ (3 lượt box blur ≈ Gauss), tăng bão hoà, phủ màu sáng hoặc tối theo chế độ.
2. **Khúc xạ viền:** trong dải vài điểm sát mép, lấy mẫu nền lệch vào trong theo pháp tuyến của mép — cho cảm giác thấu kính
   của Liquid Glass. Làm được vì nền đứng yên; tốn một lần lúc dựng, không tốn gì lúc vẽ.
3. Mặt nạ hình: bo góc liên tục (siêu elip) hoặc viên thuốc, khử răng cưa.
4. Viền sáng (specular) trên trái, viền tối dưới phải, bóng trong.
5. Bóng đổ: ảnh 9 mảnh riêng, đặt dưới tấm kính.

Ảnh dựng xong lưu ở `/var/mobile/Library/Caches/Glass6/` dạng điểm ảnh thô BGRA có đầu tệp ngắn — nạp bằng `mmap`, không
giải mã, các tiến trình dùng chung trang nhớ. Khoá đệm gồm: mã bề mặt, kích thước, chế độ sáng / tối, thông số kính, dấu
của hình nền, số bản. Đổi hình nền hoặc đổi thông số thì dựng lại.

Hiệu ứng động của Liquid Glass thật (khúc xạ theo nội dung chạy, kính biến hình) **không làm**. Thay bằng chuyển cảnh mờ dần
và co giãn nhẹ.

---

## 3. Kiến trúc

```text
Glass6SB.dylib        SpringBoard — ObjC, móc hàm lúc chạy            ─┐
Glass6UI.dylib        app được chọn — ObjC mỏng, chỉ đọc ảnh dựng sẵn  ─┼─► libglass6core.dylib (Rust)
Glass6Prefs.bundle    Cài đặt › Glass 6 (PreferenceLoader)             ─┤
glass6ctl             công cụ dòng lệnh quyền mobile: kiểm bản mới, tải ─┘
g6update, g6svc       hai công cụ setuid root, nhỏ: cài bản cập nhật / bật tắt dịch vụ
```

| Tệp cài | Vai trò |
| --- | --- |
| `/usr/lib/libglass6core.dylib` | Lõi Rust (không có mạng). Nạp bằng `dlopen` khi cần — lõi hỏng thì tweak tự tắt, SpringBoard vẫn lên |
| `/Library/MobileSubstrate/DynamicLibraries/Glass6SB.dylib` | Lọc `com.apple.springboard`. Mọi bề mặt của SpringBoard, Control Center, bộ gác |
| `/Library/MobileSubstrate/DynamicLibraries/Glass6UI.dylib` | Lọc `com.apple.UIKit` (từ Đợt 2). Việc đầu tiên: hỏi danh sách app được nạp, không có tên thì thoát ngay |
| `/Library/PreferenceBundles/Glass6Prefs.bundle` | Bảng điều khiển |
| `/usr/bin/glass6ctl` | Kiểm / tải bản mới qua HTTPS (rustls — iOS 6 không tự vào được GitHub). Quét xung đột và dựng ảnh kính nằm ở lõi, không ở đây |
| `/usr/libexec/glass6/g6update` | setuid root: kiểm chữ ký số của gói rồi `dpkg -i`, khởi động lại SpringBoard |
| `/usr/libexec/glass6/g6svc` | setuid root: bật / tắt dịch vụ có trong danh mục của lõi, không nhận đường dẫn tuỳ ý |
| `/etc/apt/trusted.gpg.d/vn.glass6.gpg` | Khoá công khai của nguồn Cydia |

Không có tiến trình thường trú riêng: mọi công cụ chạy theo lệnh rồi thoát.

Định danh: gói `vn.glass6.tweak`; cấu hình `/var/mobile/Library/Preferences/vn.glass6.plist`; dữ liệu
`/var/mobile/Library/Glass6/`; thông báo Darwin tiền tố `vn.glass6/`.

Các tiến trình báo nhau bằng thông báo Darwin: Cài đặt ghi cấu hình rồi gửi `vn.glass6/prefs` → SpringBoard và app đọc lại.

---

## 4. Lõi Rust (`core/`)

| Crate | Nội dung |
| --- | --- |
| `g6-core` | `material` (làm mờ, màu, mặt nạ, viền, ghép lớp), `theme` (bảng màu và số đo sáng / tối), `config` (lược đồ, mặc định, kiểm, nâng cấp), `services` (danh mục dịch vụ, hồ sơ, kế hoạch áp / hoàn tác), `guard` (quét xung đột, đếm sập). Không phụ thuộc mạng. Chạy thử được trên PC |
| `g6-ffi` | Mặt C của lõi → `libg6_ffi.a` → bọc thành `libglass6core.dylib` |
| `g6-ctl` | `glass6ctl`: HTTPS (rustls + gốc Mozilla đóng kèm) cho OTA — tách riêng để SpringBoard không phải gánh TLS |

Cầu FFI (chi tiết ở [FFI.md](FFI.md)):

- Điều khiển bằng JSON như `cbtv_call`: `g6_call(json) → json`, `g6_free`.
- Điểm ảnh đi bằng hàm nhị phân riêng (không bọc JSON): `g6_glass_render`, `g6_blur_bgra`…
- Vỏ ObjC tra từng hàm bằng `dlsym`; thiếu hàm nào thì tính năng tương ứng tắt.

Dựng: target `tools/rust/armv7-apple-ios6.json` (Cortex-A8 + NEON), nightly `-Z build-std`, `panic = abort`, tối ưu kích thước.

---

## 5. Giao diện — chia đợt

Mỗi đợt ra một gói `.deb` chạy được. Mỗi thành phần có công tắc riêng trong Cài đặt.

| Đợt | Nội dung |
| --- | --- |
| **0a** | Khung dự án, lõi (vật liệu kính), bộ gác an toàn, mục Cài đặt, công cụ thử (xem cây view, chụp ảnh) |
| **0b** | Phát hành: repo, nguồn Cydia, OTA |
| **0c** | Dịch vụ hệ thống (mục 7) |
| **1** | **SpringBoard:** dock nổi dạng viên thuốc; biểu tượng bo góc liên tục, bỏ lớp bóng, viền kính, 4 kiểu (Mặc định / Tối / Trong / Nhuộm màu); nhãn; thư mục; chấm trang; thanh trạng thái; màn khoá (đồng hồ lớn); Trung tâm thông báo và băng thông báo; hộp thoại, bảng chọn; HUD âm lượng; khay đa nhiệm; Spotlight; **Control Center mới** (iOS 6 chưa có): Wi-Fi, Bluetooth, Máy bay, khoá xoay, độ sáng, âm lượng, nhạc, sáng / tối |
| **2** | **Thành phần UIKit** trong app được nạp: thanh điều hướng, thanh công cụ, thanh tab, ô tìm kiếm, nút, công tắc, thanh trượt, nút phân đoạn, bảng nhóm (thẻ bo góc, bỏ sọc), popover, bàn phím, bánh xe chọn, menu chép / dán. Thay artwork qua `_UIImageWithName`, móc lớp để đổi số đo và phông |
| **3** | **App Apple** bỏ da / gỗ / vải: Cài đặt, Ghi chú, Danh bạ, Lịch, Nhắc việc, Game Center, Nhạc, Mail, Safari, Tin nhắn, Ảnh, App Store, Đồng hồ |
| **4** | Chế độ tối tầng 2 và 3, hẹn giờ sáng / tối |

Phông: Inter đăng ký bằng `CTFontManagerRegisterFontsForURL`. Bề mặt do Glass 6 tự vẽ (đồng hồ màn khoá, Control Center,
nhãn biểu tượng) dùng Inter ngay từ Đợt 1; thay phông hệ thống trong app là công tắc riêng ở Đợt 2 (đổi phông làm lệch số đo
chữ, cần thử từng app).

---

## 6. Chế độ tối

iOS 6 không có màu ngữ nghĩa — app gán màu cứng. Chia ba tầng:

| Tầng | Phạm vi | Mức chắc chắn |
| --- | --- | --- |
| 1 | SpringBoard và mọi bề mặt của Glass 6 (dock, Control Center, thông báo, hộp thoại, bàn phím) | Chắc chắn — Đợt 1, 2 |
| 2 | App Apple: bảng màu riêng từng app | Làm dần — Đợt 4 |
| 3 | App bên thứ ba: bật từng app, đổi màu theo quy tắc chung | Có thể lỗi màu |

Trang web trong Safari không đổi. Chuyển chế độ: công tắc trong Cài đặt, nút trong Control Center, hoặc hẹn giờ. SpringBoard
đổi ngay; app đổi khi trở lại trước màn hình.

---

## 7. Dịch vụ hệ thống

Cách tắt: `launchctl unload -w <plist>` — launchd ghi vào `/private/var/db/launchd.db/com.apple.launchd/overrides.plist`
(trên máy thử đang rỗng). Không xoá, không sửa tệp nào của hệ thống; bật lại bằng `launchctl load -w`.

| Nhóm | Dịch vụ | Mặc định |
| --- | --- | --- |
| A — đã chết phía máy chủ | `twitterd`, `weibod`, `sociald`, `mstreamd` (Photo Stream), `ubd` + `librariand` (iCloud Documents cũ) | Tắt trong hồ sơ «Cân bằng» |
| B — chẩn đoán gửi Apple | `aggregated` (+ `dbservice`, `addaily`), `awdd`, `powerlog`, `OTATaskingAgent`, `OTACrashCopier` | Tắt trong hồ sơ «Cân bằng». Giữ `ReportCrash` và các việc dọn / chép báo cáo sập |
| C — tuỳ nhu cầu | Game Center, AirPrint, Siri + Đọc chính tả, iTunes Match, Điểm truy cập cá nhân, WAPI | Giữ; người dùng tự tắt, có ghi rõ mất gì |

Danh mục thật là `data/services.tsv` (15 dịch vụ đã thử trên máy — D22 ghi vì sao có mục vào, mục không).
| Cấm đụng | `backboardd`, `SpringBoard`, `configd`, `notifyd`, `lockdown`, `installd`, `mediaserverd`, `securityd`, `fairplayd`, `lsd`, `wifid`, `CommCenter`, `locationd`, `powerd`, `kbd`, `syslogd`, `mDNSResponder`, `accountsd`, `tccd`, `assistivetouchd`, `sshd`… | Khoá cứng trong lõi |

Ba hồ sơ: **Nguyên bản** (mặc định khi cài), **Cân bằng** (A + B), **Tuỳ chỉnh**.

Quy tắc đưa một dịch vụ vào danh mục: phải thử trên máy thật — tắt, khởi động lại, mở từng ô của Cài đặt, Mail, Safari,
App Store, Cydia. Tắt một dịch vụ mà app khác còn hỏi tới thì app đó đứng chờ: đây là nguồn treo máy chính.

**Bộ gác khởi động:** áp hồ sơ mới thì ghi dấu «chưa xác nhận». SpringBoard lên ổn 60 giây thì xác nhận. Hai lần khởi động
liền không xác nhận được → tự hoàn tác về trạng thái trước.

---

## 8. An toàn

1. **Substrate Safe Mode** (đã có): SpringBoard sập thì mọi tweak tắt.
2. **Công tắc tổng bằng tệp:** có `/var/mobile/Library/Glass6/off` thì Glass 6 không làm gì — tạo qua SSH là tắt hẳn. Kiểm
   bằng libc, trước mọi việc khác.
3. **Đếm khởi động chưa ổn:** mỗi lần SpringBoard nạp Glass 6 thì tăng bộ đếm; chạy ổn 20 giây thì về 0. Ba lần khởi động
   liền mà không lần nào ổn → Glass 6 tự tắt (tệp `off.auto`), Cài đặt báo và có nút «Đặt lại bộ gác». Tránh vòng lặp vào
   Safe Mode mãi. (Ba chứ không hai: khởi động lại SpringBoard hai lần sát nhau là chuyện thường.)
4. **App sập lúc nạp:** lần sau tự bỏ Glass 6 cho riêng app đó.
5. **Từng tính năng độc lập:** thiếu lớp / hàm đích thì bỏ qua và ghi nhật ký; tính năng này lỗi không kéo tính năng khác.
6. **Quét xung đột** lúc cài và khi mở Cài đặt: gói giao diện đã biết là đụng (WinterBoard, tweak đổi dock, màn khoá, thanh
   trạng thái…) → cảnh báo, tự tắt phần trùng.
7. Nhật ký `/var/mobile/Library/Glass6/glass6.log`, có giới hạn cỡ.

---

## 9. Bảng điều khiển (Cài đặt › Glass 6)

| Mục | Có gì |
| --- | --- |
| Đầu trang | Bật / tắt tổng; Sáng / Tối / Tự động |
| Kính | Độ mờ, độ trong, màu nhuộm, viền sáng, giảm hiệu ứng |
| Màn hình chính | Dock, kiểu biểu tượng, nhãn, thư mục |
| Màn khoá | Đồng hồ, kiểu trượt mở khoá |
| Control Center | Chọn và xếp nút |
| Thông báo và hộp thoại | Từng thành phần |
| Thanh và nút hệ thống | Công tắc từng thành phần UIKit, phông Inter |
| App | Danh sách app: áp giao diện / áp chế độ tối |
| Hệ thống | Hồ sơ dịch vụ, từng dịch vụ kèm trạng thái đang chạy |
| An toàn | Kết quả quét xung đột, nhật ký, đặt lại, khởi động lại SpringBoard |
| Phiên bản | Bản đang cài, kiểm bản mới, tự kiểm |

---

## 10. Phát hành (theo GramMini)

| Thứ | Ở đâu |
| --- | --- |
| Repo phát triển | riêng tư, đủ lịch sử |
| Repo công khai | `itovn/Glass6` — ảnh chụp mã sạch mỗi bản, thẻ `v<bản>`, giấy phép GPL-3.0 (phông Inter giữ OFL-1.1) |
| Gói | GitHub Releases của `itovn/Glass6`: `vn.glass6.tweak_<bản>_iphoneos-arm.deb` + `.deb.sig` |
| Trang giới thiệu, nguồn Cydia | nhánh `gh-pages`: `https://itovn.github.io/Glass6/`, nguồn `https://itovn.github.io/Glass6/cydia/` |

**Nguồn Cydia:** `tools/update-cydia-repo.sh` (giữ 3 bản, `Packages` bỏ dấu vì Cydia 1.1.30 đọc US-ASCII) rồi
`tools/sign-cydia-repo.sh` ký `Release` → `Release.gpg` + `InRelease`. Khoá GPG riêng của dự án ở `keys/cydia-gnupg`; khoá
công khai đi kèm gói. Trang mô tả phải chạy trên Safari iOS 6 (không biến CSS, flex gap, grid).

**OTA:**

1. `glass6ctl update check` hỏi `https://api.github.com/repos/itovn/Glass6/releases/latest` — SpringBoard gọi tối đa một lần
   mỗi 24 giờ (tắt được), hoặc người dùng chạm «Kiểm bản mới».
2. Có bản mới hơn kèm đủ `.deb` và `.deb.sig` → Cài đặt hiện «Có bản mới». Chỉ nhận link bắt đầu bằng
   `https://github.com/itovn/Glass6/releases/download/`.
3. `glass6ctl update download` tải về `/var/mobile/Library/Glass6/update/`, kiểm kích thước và SHA-256.
4. `g6update` (setuid root, C, viết lại từ `gmupdate.c`): chép gói vào `/var/root/Glass6-update` (0700), kiểm chữ ký
   RSA-3072 PKCS#1 v1.5 + SHA-256 bằng chứng chỉ gắn trong `helper/ota_cert.h`, chỉ nhận gói `vn.glass6.tweak` bản mới hơn,
   bỏ môi trường của bên gọi, chỉ cho Cài đặt hoặc SpringBoard gọi, `dpkg -i`, khởi động lại SpringBoard.
5. Khoá ký `keys/ota-sign.key` chỉ ở máy phát hành, không lên git. `tools/sign-release.sh` ký.

Cài qua Cydia: `postinst` xin nút «Restart SpringBoard».

---

## 11. Dựng và thử

- Máy dựng Ubuntu (Theos + SDK 9.3, Rust nightly + `rust-src`): `bash tools/build.sh` → `packages/*.deb`.
- `tools-local/deploy.sh` (không lên git): chép mã lên máy dựng, dựng, cài lên iPad, khởi động lại SpringBoard.
- Lõi chạy thử trên PC: `cargo test -p g6-core`; `cargo run -p g6-core --example preview` xuất ảnh mẫu các tấm kính.
- Bản thử có `Debug/`: nhận lệnh qua thông báo Darwin `vn.glass6/debug` + tệp lệnh — in cây view, liệt kê lớp / hàm của
  SpringBoard, bật tấm kính thử. Bản phát hành bỏ hẳn.
- Trước khi phát hành: tra ký hiệu mọi tệp chạy bằng `cbsymcheck` trên máy iOS 6.

---

## 12. Không làm

- Kính mờ theo nội dung đang chạy; hiệu ứng kính biến hình của Liquid Glass.
- Thay tệp artwork của hệ thống trên đĩa.
- Đóng kèm phông SF, biểu tượng hay hình nền của Apple.
- Chế độ tối cho trang web.
- Đụng vào jetsam, bộ nhớ ảo, nhân.

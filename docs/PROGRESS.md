# Glass 6 — Tiến độ

## 19/11/2026 — Đợt 0a: nền móng

- Khảo sát iPad mini 1 (iOS 6.1.3) qua SSH, chốt thiết kế với anh: [THIET-KE.md](THIET-KE.md); quyết định:
  [DECISIONS.md](DECISIONS.md) (D1–D8); hợp đồng lõi: [FFI.md](FFI.md).
- **Lõi Rust** (`core/`, 41 phép thử chạy trên PC):
  - `g6-core`: ảnh BGRA (`bitmap`), box blur 3 lượt (`blur`), hình bo góc liên tục có khoảng cách + pháp tuyến (`shape`),
    dựng tấm kính có khúc xạ viền / viền sáng / bóng đổ (`glass`), số đo 7 bề mặt sáng / tối (`theme`), cấu hình chịu được
    tệp hỏng (`config`), quét xung đột (`guard`), cửa JSON (`api`);
  - `g6-ffi`: 7 hàm C;
  - `cargo run -p g6-core --example preview -- <thư mục> [hình nền]` xuất ảnh mẫu và biểu tượng mục Cài đặt.
- **Gói `vn.glass6.tweak` 0.1.0** (167 KB) — `bash tools/build.sh` trên máy dựng:
  - `/usr/lib/libglass6core.dylib` (lõi, 252 KB, chỉ xuất `g6_*`);
  - `Glass6SB.dylib` nạp vào SpringBoard: bộ gác → nạp lõi → cấu hình → quét xung đột → ghi `status.plist`;
  - `Glass6Prefs.bundle`: Cài đặt › Glass 6 (bật / tắt, Sáng / Tối / Tự động, độ mờ, độ trong, viền sáng, giảm hiệu ứng,
    trạng thái, đặt lại bộ gác, khởi động lại SpringBoard).
- **Đã thử trên iPad mini 1:**
  - tra ký hiệu ba tệp chạy: 164, thiếu 0;
  - SpringBoard nạp Glass 6 và lõi, chạy ổn; bảng Cài đặt hiện đúng, dòng trạng thái «Đang chạy»;
  - lệnh thử `panel sang` / `panel toi`: 7 tấm kính + 1 kính giả trên màn hình thật, làm mờ đúng thứ nằm dưới;
  - tệp `off` → không chạy; bộ đếm = 3 → tự tắt; `appearance = 1` trong tệp cấu hình → chế độ tối;
  - tốc độ: mở khối kính 320×400 ~80 ms (D5).
- **Chưa có thành phần giao diện nào được đổi** — Đợt 0a chỉ là khung. Tấm kính mới hiện qua lệnh thử.

## 19/11/2026 — Đợt 1 (bắt đầu): dock kính

Anh muốn thấy dock kính trước nên làm Đợt 1 trước 0b / 0c. Chi tiết: [DECISIONS.md](DECISIONS.md) D9.

- `tweak/SB/G6Dock.m`: bỏ kệ dock và bóng phản chiếu, ẩn nhãn trong dock, dồn biểu tượng vào giữa, tấm kính nổi bo góc +
  bóng đổ phía sau; nền là hình nền mờ sẵn.
- Lõi: nền dưới kính nhận ảnh đã thu nhỏ sẵn (`pre`); góc dock tròn hơn (0,38 chiều cao).
- Lệnh thử mới: `inspect <lớp> [hàm…]` (lớp vẽ + số đo bố cục), `orient <1–4>` (giả xoay máy).
- **Đã thử trên iPad mini 1:** dock kính sáng / tối; đổi sáng ↔ tối và tắt ↔ bật dock ngay lúc đang chạy; xoay dọc, hai
  chiều ngang; tra ký hiệu 187, thiếu 0; không có crash log.
- **Chưa thử:** kéo thả biểu tượng vào / ra dock, dock ít hơn 6 biểu tượng, dock lúc mở thư mục / mở app (chỉ nhìn bằng mắt
  trên máy mới thấy chuyển động).
- Cài đặt › Glass 6 › Màn hình chính có công tắc «Dock kính» (`featDock`): tắt / bật là đổi ngay.
- ~~Còn thiếu của dock: lần mở khoá đầu sau khi SpringBoard lên, kính giả hiện ~0,1 giây rồi mới thành kính thật.~~ Đã
  hết từ khi hình nền mờ tự vẽ được lúc máy còn khoá (D15).

## 19/11/2026 — Đợt 1: biểu tượng

Chi tiết: [DECISIONS.md](DECISIONS.md) D10.

- Lõi: `icon.rs` + `g6_icon_render` — cắt ảnh theo hình bo góc liên tục (siêu elip bậc 5), viền sáng; 46 phép thử.
- `tweak/SB/G6Icons.m`: ảnh biểu tượng dựng lại từ tệp gốc của app (hết lớp bóng kính của iOS 6), biểu tượng nền trong
  suốt đặt lên ô kính, bóng đổ mềm, nền thư mục thành ô kính, Quầy báo cắt theo hình mới; bộ đệm trên đĩa.
- Cài đặt › Glass 6 › Màn hình chính có thêm công tắc «Biểu tượng kiểu mới» (`featIcons`), đổi ngay không cần khởi động lại.
- Gói có thêm `postrm` (gỡ thì xoá ảnh đã dựng; gỡ sạch thì xoá cả cấu hình).
- **Đã thử trên iPad mini 1:** hai trang + dock, sáng / tối, tắt / bật trực tiếp, chế độ sắp xếp, mở thư mục, khay đa
  nhiệm. Tạo lại 60 biểu tượng: 1,2 giây lần đầu, ~0,1 giây khi đã có bộ đệm.
- **Chưa thử:** cài / gỡ / cập nhật một app lúc Glass 6 đang chạy; biểu tượng trang web lưu ra màn hình chính.

## 19/11/2026 — Đợt 1: nhãn biểu tượng, phông Inter

Chi tiết: [DECISIONS.md](DECISIONS.md) D11.

- Gói có thêm phông Inter (4 độ đậm) ở `/Library/Application Support/Glass6/Fonts/`; `tweak/Common/G6Font.m` đăng ký và cấp phông.
- Nhãn dưới biểu tượng: Inter Medium 12,5, bóng chữ mềm; theo công tắc «Biểu tượng kiểu mới», tắt / bật là nhãn vẽ lại ngay.
- **Đã thử trên iPad mini 1:** nhãn tiếng Việt có dấu, màn hình ngang / dọc, tắt ↔ bật trực tiếp.
- Sự cố lúc làm: lệnh thử `labels` bản đầu gọi sai kiểu hàm trả `CGSize` làm SpringBoard sập một lần; đã sửa (D11).

## 19/11/2026 — Đợt 1: thư mục mở

Chi tiết: [DECISIONS.md](DECISIONS.md) D12.

- `tweak/SB/G6Folders.m`: dải thư mục mở thành kính mờ (nền = hình nền đã mờ đúng chỗ), bỏ vải / bóng trong / mũi nhọn, tên
  thư mục phông Inter. Công tắc «Thư mục kính» (`featFolders`).
- `tweak/SB/G6Wallpaper.m`: hình nền mờ dùng chung cho dock và thư mục.
- **Đã thử trên iPad mini 1:** sáng / tối, ngang / dọc, tắt → lần mở sau về kiểu gốc.
- **Chưa thử:** đổi tên thư mục, kéo biểu tượng vào / ra thư mục (thêm hàng), thư mục ở hàng dưới cùng (mở lên trên).

## 19/11/2026 — Đợt 1: biểu tượng Đồng hồ sống

Anh yêu cầu thêm. Chi tiết và số đo: [DECISIONS.md](DECISIONS.md) D13.

- `tweak/SB/G6Clock.m`: mặt đồng hồ tự vẽ; kim giờ / phút / giây chạy theo giờ và múi giờ của máy; chỉ chạy khi biểu tượng
  đang nằm trên màn hình, máy không khoá. «Giảm hiệu ứng»: bỏ kim giây, nhích mỗi phút.
- Cài đặt › Glass 6 › Màn hình chính: công tắc «Đồng hồ chạy thật» (`featClock`); tắt là về ảnh tĩnh của máy ngay.
- Lõi: thêm thành phần `clock` vào cấu hình.
- `tools/g6cpu`: công cụ đo CPU của tiến trình trên máy thử (máy iOS 6 không có `ps` / `top`).
- **Đã thử trên iPad mini 1:** xem D13. Kim chạy tốn thêm ~4 điểm phần trăm CPU so với không có (5,8% so với 1,6%), chỉ lúc
  biểu tượng Đồng hồ đang hiện.

## 19/11/2026 — Đợt 1: thanh trạng thái, khay đa nhiệm

Chi tiết: [DECISIONS.md](DECISIONS.md) D14, D15.

- `tweak/SB/G6StatusBar.m`: thanh trạng thái của SpringBoard bỏ dải nền đen, chữ trắng rõ, phông Inter (`featStatusBar`).
- `tweak/SB/G6Switcher.m`: khay đa nhiệm thành dải kính mờ (`featSwitcher`, thành phần mới trong lõi).
- `tweak/SB/G6GlassFill.m`: hàm phủ kính lên nền vải, thư mục và khay dùng chung.
- `G6Wallpaper`: tự vẽ được hình nền khi nó không nằm trong cửa sổ → khay mở trong app vẫn có kính thật; dock có kính thật
  ngay lúc SpringBoard vừa lên.
- **Đã thử trên iPad mini 1:** xem D14, D15.

## 19/11/2026 — Đợt 1: màn khoá

Chi tiết: [DECISIONS.md](DECISIONS.md) D16.

- `tweak/SB/G6Lock.m`: bỏ hai thanh bóng kính, giờ / ngày phông Inter, rãnh trượt + nút khung ảnh bằng kính, núm trượt mới.
- Theo yêu cầu của anh: ẩn nút khung ảnh (công tắc «Ẩn nút khung ảnh», mặc định ẩn); nằm ngang hạ đồng hồ xuống 24 điểm;
  ẩn mục «Chưa cài đặt Thẻ SIM» trên màn khoá (công tắc `lockHideNoSIM`, mặc định ẩn).
- Cài đặt › Glass 6 có nhóm «Màn khoá»: «Màn khoá kiểu mới» (`featLockScreen`), «Ẩn nút khung ảnh» (`lockHidePictureFrame`).
- Khung danh sách thông báo trên màn khoá → kính đậm bo góc (bề mặt `list` mới trong lõi).
- **Đã thử trên iPad mini 1:** xem D16.

## 19/11/2026 — Đợt 1: bảng âm lượng, băng thông báo

Chi tiết: [DECISIONS.md](DECISIONS.md) D17.

- `tweak/SB/G6HUD.m`: bảng âm lượng thành tấm kính, các nấc vẽ lại (`featHUD`).
- `tweak/SB/G6Banner.m`: băng thông báo thành tấm kính, chữ Inter, màu theo sáng / tối (`featNotifications`).
- Cài đặt › Glass 6 có nhóm «Thông báo và bảng nổi».
- **Đã thử trên iPad mini 1:** xem D17.

## 19/11/2026 — Đợt 1: Trung tâm thông báo

Chi tiết: [DECISIONS.md](DECISIONS.md) D18.

- `tweak/SB/G6NotificationCenter.m`: cả bảng (nền, đầu mục, mảnh lấp) thành một tấm kính liền; chữ trong ô phông Inter.
- Lõi: thêm bề mặt `sheet`, `hud` (kính đậm cho bề mặt mang chữ trắng của máy); 47 phép thử.
- `G6Glass`: `G6GlassImageForRect`, `G6GlassRenderForRect` (dựng kính cho một vùng / thẳng vào vùng nhớ của bên gọi).
- **Đã thử trên iPad mini 1:** xem D18.

## 19/11/2026 — Đợt 1: hộp thoại

Chi tiết: [DECISIONS.md](DECISIONS.md) D19.

- `tweak/Common/G6Alert.m`: hộp thoại của hệ thống thành tấm kính, chữ Inter theo sáng / tối, nút dạng viên (`featAlerts`).
- Lõi: bề mặt `alert`, `list`. `G6Glass`: sửa lỗi dựng kính giả khi view tham chiếu là `UIWindow`.
- **Đã thử trên iPad mini 1:** xem D19.

## 19/11/2026 — Đợt 1: Control Center

Chi tiết: [DECISIONS.md](DECISIONS.md) D20.

- `tweak/SB/G6ControlCenter.m`: bảng kính ở góc trên phải — Máy bay, Wi-Fi, Bluetooth, khoá xoay, sáng / tối, độ sáng, âm
  lượng, nhạc. Mở bằng kéo từ mép trên xuống ở một phần ba bên phải (phần còn lại vẫn là Trung tâm thông báo).
- Cài đặt › Glass 6 có nhóm «Control Center» (`featControlCenter`).
- **Đã tự thử trên iPad mini 1:** xem D20 (Wi-Fi và Máy bay chưa bấm thử vì sẽ mất SSH).

## 19/11/2026 — Đợt 1: bốn kiểu biểu tượng

Chi tiết: [DECISIONS.md](DECISIONS.md) D21.

- Lõi (`icon.rs`): kiểu Mặc định / Tối / Trong / Nhuộm màu, đổi màu ngay trên ảnh của app trước khi cắt hình.
- Cài đặt › Glass 6 có nhóm «Kiểu biểu tượng» (`iconStyle`, `iconTint`).
- **Đã tự thử trên iPad mini 1:** xem D21.

## 19/11/2026 — Đợt 0c: dịch vụ hệ thống

Chi tiết: [DECISIONS.md](DECISIONS.md) D22.

- `data/services.tsv`: danh mục 15 dịch vụ (A đã ngừng phía máy chủ, B chẩn đoán gửi Apple, C tuỳ nhu cầu) — nguồn chung của
  lõi (`services.rs`, lệnh `services.catalog`) và của công cụ quyền root `svc/g6svc.c` (danh sách trắng sinh lúc dựng).
- Bộ gác khởi động: `/Library/LaunchDaemons/vn.glass6.svcguard.plist` → `g6svc boot`; SpringBoard xác nhận sau 60 giây
  (`tweak/Common/G6Services.m`); hai lần khởi động máy chưa xác nhận thì tự hoàn tác. `prerm` bật lại mọi dịch vụ khi gỡ.
- Cài đặt › Glass 6 › Dịch vụ hệ thống (`prefs/G6ServicesController.m`): hồ sơ Nguyên bản / Cân bằng, công tắc từng dịch
  vụ kèm ghi chú «tắt thì mất gì». Cài Glass 6 không tự tắt dịch vụ nào.
- `tools/g6cpu -l`: liệt kê mọi tiến trình kèm RAM và giây CPU (máy iOS 6 không có `ps`).
- **Đã tự thử trên iPad mini 1:** áp hồ sơ, khởi động lại máy, tự hoàn tác, tắt cả 15 — xem bảng ở D22.

## 19/11/2026 — Chế độ Tự động đổi đúng giờ

- `tweak/Common/G6Prefs.m`: ở chế độ Tự động, hẹn giờ (theo giờ thật — máy ngủ qua mốc thì thức dậy là đổi) tới mốc sáng ↔ tối
  kế tiếp rồi báo như một lần đổi cấu hình; xét lại khi qua nửa đêm / đổi múi giờ / chỉnh đồng hồ.
- Cài đặt › Glass 6 › Giao diện có thêm «Tự động: tối từ» và «Tự động: sáng từ» (`darkFrom`, `darkTo`).
- **Đã tự thử trên iPad mini 1:** đặt khoảng tối 08:29–08:31 → 08:29:02 dock + biểu tượng sang tối, 08:31:01 về sáng.

## 19/11/2026 — Đợt 2 (bắt đầu): giao diện trong app

Chi tiết: [DECISIONS.md](DECISIONS.md) D23.

- `tweak/UI/` → `Glass6UI.dylib`, nạp vào app của Apple: `main.m` (phạm vi, bộ gác riêng từng app, điểm cài sau
  `-[UIApplication setDelegate:]`), `G6UIBars.m` (thanh + nút trên thanh), `G6UIControls.m` (công tắc, thanh trượt, nút chọn
  đoạn), `G6UITables.m` (bảng nhóm; chế độ tối đổi cả chữ trong ô; cột trái của Cài đặt).
- Lõi: `apps.rs` + lệnh `app.policy` (app tự vẽ giao diện giữ thanh và bảng); công tắc `featApps`, `featBars`, `featTables`,
  `featControls`. Cài đặt › Glass 6 có nhóm «Trong app».
- Tệp của phần trong-app ở `/var/tmp/vn.glass6` (hộp cát). Công cụ thử chạy được trong app: `g6.sh @Preferences dump`.
- **Đã tự thử trên iPad mini 1:** xem D23.

## 19/11/2026 — Theo góp ý: biểu tượng Cài đặt, hình sáng ở chế độ tối, nút AssistiveTouch

Chi tiết: [DECISIONS.md](DECISIONS.md) D23 (hai mục đầu), D24.

- `tweak/UI/G6UISettingsIcons.m`: biểu tượng các mục của app Cài đặt kiểu ô màu bo góc, hình trắng tự vẽ (`featSettingsIcons`).
- `tweak/UI/G6UITables.m`: ổ khoá, vạch sóng Wi-Fi, dấu chọn trong ô đổi sang màu sáng ở chế độ tối.
- `tweak/SB/G6Assist.m` + lõi `assist.rs` + `prefs/G6AssistController.m`: nút AssistiveTouch của Glass 6 — bảng 1–8 ô tự chọn chức
  năng, thao tác chạm / chạm hai lần / nhấn giữ, kéo thả hít mép, tự tắt nút của iOS (`featAssist`, mặc định tắt).
- **Đã tự thử trên iPad mini 1:** xem D24.

## 19/11/2026 — Bổ sung AssistiveTouch / Control Center, ẩn Quầy báo, bảng thường ở chế độ tối

Chi tiết: [DECISIONS.md](DECISIONS.md) D24 (phần bổ sung), D25.

- AssistiveTouch: bảng vuông 3×3 tối đa 9 ô, tự ẩn sau thời gian chờ, ô có trạng thái, Respring / khoá xoay / khởi động lại có
  sẵn; sửa khoá xoay không ăn khi máy nằm phẳng. Control Center: vuốt lên để đóng, tự ẩn.
- `tweak/SB/G6Newsstand.m`: ẩn biểu tượng Quầy báo (`hideNewsstand`), đổi sống.
- `tweak/UI/G6UITables.m`: bảng thường toàn ô chuẩn được tô tối ở chế độ tối; bảng có ô tự vẽ giữ sáng.

## 19/11/2026 — Dải hiệu suất trên màn hình chính; thanh trạng thái kiểu iPadOS

Chi tiết: [DECISIONS.md](DECISIONS.md) D26.

- `core/crates/g6-core/src/perf.rs` + lệnh `perf.reading`: tính CPU / RAM / đĩa / mạng từ số đếm thô, dựng chuỗi hiển thị.
- `tweak/SB/G6Perf.m`: dải kính trên màn hình chính (`featPerf`), trên cùng giữa thanh trạng thái hoặc dưới thanh trạng thái,
  bản đầy đủ / bản gọn theo chỗ trống; chỉ đo khi màn hình chính đang hiện.
- `tweak/SB/G6StatusBar.m`: giờ + mặt trăng sang trái, hình pin vẽ lại với tia sét xanh lá khi sạc, ẩn «Không có SIM».
- `tweak/Common/G6StatusItems.m` + `tweak/UI/G6UIStatusBar.m`: cùng kiểu thanh trạng thái đó bên trong các app của Apple.
- `tweak/SB/G6Screen.m`: theo dõi khoá / tắt màn hình dùng chung (tách từ `G6Clock.m`).
- Cài đặt: nhóm «Thanh trạng thái» (3 công tắc), nhóm «Hiệu suất hệ thống» (công tắc, vị trí, nhịp đo).
- Lệnh thử mới: `perf`, `statusbar`, `sbitems` (chạy được trong app: `g6.sh @Preferences sbitems`).

## 19/11/2026 — Chế độ tối trong app: phần còn sót của thành phần chuẩn

Chi tiết: [DECISIONS.md](DECISIONS.md) D27.

- `G6UITables.m`: dấu chọn / mũi tên cuối dòng, chữ nút bo góc, thanh tiêu đề nhóm của bảng thường.
- `G6UIControls.m`: ô nhập bo góc, công tắc đang tắt.
- `G6UIBars.m`: hình của nút trơn trên thanh công cụ.

## 19/11/2026 — Đợt 3 (bắt đầu): vẽ lại riêng từng app — app Đồng hồ

Chi tiết: [DECISIONS.md](DECISIONS.md) D28.

- `tweak/UI/G6UIAppSkins.m` (khung chung, `featAppSkins`) + `tweak/UI/G6UIAppClock.m` (thanh thẻ dưới cùng của app Đồng hồ).
- `G6UIControlsStyleSegmented` / `G6UIBarSurfaceImage`: cho phần vẽ lại từng app mượn kiểu nút chọn đoạn và mặt thanh.
- Khảo sát Video (không cần sửa), Nhạc (gác lại: thư viện trống).

## 19/11/2026 — Bánh xe chọn kiểu mới

Chi tiết: [DECISIONS.md](DECISIONS.md) D29.

- `tweak/UI/G6UIPickers.m`: UIPickerView / UIDatePicker phẳng, viên chọn bo góc, theo sáng / tối; bánh xe có dòng app tự vẽ
  luôn giữ mặt sáng.
- Sửa `G6UITables.m`: phần làm mới cột trái của Cài đặt chỉ nhận đúng `PSGradientView`.
- Cửa sổ trưng bày: `gallery 4` (ba loại bánh xe).

## 19/11/2026 — Bàn phím tối

Chi tiết: [DECISIONS.md](DECISIONS.md) D30.

- `tweak/Common/G6Keyboard.m`: bộ lọc `colorMatrix` (CAFilter) trên lớp vẽ của bàn phím ở chế độ tối (`featKeyboard`).
- `G6UIRefreshAppearance`: giữ con trỏ nhập qua bước làm mới (bàn phím không thu xuống khi đổi sáng ↔ tối).
- Lệnh thử mới: `cafilter` (thử bộ lọc CAFilter trên một view; `bg` / `bgclip` / `bgwin` = thử lọc thứ nằm sau một ô),
  `focus 1|0` (đưa con trỏ vào ô nhập đầu tiên).
- Phát hiện (D31): mờ sống làm được trong phạm vi một cửa sổ (`backgroundFilters` + `masksToBounds`) nhưng đắt — chưa dùng.

## 19/11/2026 — Đợt 3: Ghi chú, Lời nhắc, Lịch, Danh bạ

Chi tiết: [DECISIONS.md](DECISIONS.md) D32.

- `tweak/UI/G6UISkin.m`: khung chung — thay vân theo tên hình, chế độ tối bằng bộ lọc trên cửa sổ, «vùng vốn tối», ảnh thật
  giữ đúng màu, `G6UIDark()`.
- `tweak/UI/G6UIAppNotes.m`, `G6UIAppReminders.m`, `G6UIAppCalendar.m`, `G6UIAppContacts.m`: bảng thay hình + vài hàm móc nhỏ.
- Công cụ thử: tệp cờ `imglog` (tên + cỡ mọi hình app nạp); `press @x,y` (bấm nút chỉ có hình theo toạ độ).
- Cách kiểm app có dữ liệu riêng: `thumbs.py` (ảnh thu nhỏ + dải thanh), thống kê màu điểm ảnh theo dải, cắt đúng khung bảng
  nổi lấy từ cây view — không cần nhìn nội dung.
- Lượt ba (màn hình thêm mới, bảng nổi, bảng chọn): bảng chọn trong app đang vẽ lại theo bảng màu của app
  (`G6AlertSetSheetDarkProvider`); nút tròn xoá / thêm của bảng đang sửa giữ đúng màu (`G6UISkinKeepColors` tính chẵn lẻ số
  lần đảo); Lời nhắc: nhãn đầu mục ở cột trái, hai nút ở đầu thẻ (bỏ kiểu «khắc chìm» của app cho nút chữ, dựng lại hình cho
  nút hình). Công cụ: `tools-local/probe.sh`, `tools-local/ctl.py` (khung nút không kèm chữ).

## 19/11/2026 — SpringBoard, phần còn sót

Chi tiết: [DECISIONS.md](DECISIONS.md) D33.

- `tweak/SB/G6Spotlight.m`: ô tìm kiếm của trang Tìm kiếm thành viên kính (`featSearch`, công tắc «Ô tìm kiếm kính»).
- `tweak/SB/G6ControlCenter.m`: nút «Không làm phiền» (BBSettingsGateway; trạng thái đọc từ mục trăng khuyết của thanh trạng
  thái); hàng nút tự thu nhỏ khi nhiều nút.
- Chấm trang: giữ nguyên.

## 19/11/2026 — App Ảnh và Tin nhắn; chốt phạm vi app

Chi tiết: [DECISIONS.md](DECISIONS.md) D35.

- Anh chốt: app bên thứ ba để nguyên; Mail, Game Center, Nhạc để nguyên; làm Ảnh và Tin nhắn.
- `tweak/UI/G6UIAppPhotos.m`: nền lưới ảnh + nhãn album theo sáng / tối, xếp lại và tô hình các nút trên thanh của trình xem.
- `tweak/UI/G6UIAppMessages.m`: bong bóng phẳng, nền trò chuyện, cột danh sách, thanh nhập, nút hình trên thanh.
- Dùng chung: nút lớn trong bảng nổi (`UIPopoverButton`), chữ đỏ cho nút «phá huỷ» trên thanh, sửa việc làm mới giao diện làm
  mất thanh nhập của Tin nhắn.
- Công cụ thử: `row`, `gtap`, `vcsend`, `balloons`; `tools-local/inst.sh` (cài không respring), `photos_check.*`, `sms_check.*`.

## 19/11/2026 — Bản tiếng Anh

Chi tiết: [DECISIONS.md](DECISIONS.md) D36.

- `tweak/Common/G6Lang.m` (`G6L`, khoá `language`), mục «Ngôn ngữ» trong Cài đặt; từ điển `prefs/Resources/Strings-en.plist`
  sinh từ `data/strings-en.txt` bằng `tools/gen_strings.py` (224 chuỗi, dịch đủ).
- Thêm / sửa chuỗi hiển thị: viết tiếng Việt trong `G6L(@"…")` (hoặc trong `Root.plist`), chạy `python tools/gen_strings.py`,
  điền bản tiếng Anh vào mục trống trong `data/strings-en.txt`, chạy lại.

## 19/11/2026 — Rào theo mẫu máy; bắt đầu bản iPhone 5

Chi tiết: [DECISIONS.md](DECISIONS.md) D37, D38, D39; kế hoạch: [IPHONE.md](IPHONE.md).

- `tweak/Common/G6Device.c`: chỉ chạy trên iPad mini 1 và iPhone 5 dùng iOS 6; máy khác không gắn hàm nào, Cài đặt nói rõ.
- iPhone thử: đã gỡ 10 gói xung đột (có sao lưu), cài bản thử, bật dần từng thành phần.
- **P1 xong phần chính**: thanh trạng thái kiểu iOS 26 (giờ trái; sóng, mạng, pin phải; ẩn tên nhà mạng), dock viên kính nổi,
  viên «Tìm kiếm» trên dock, thư mục, trang Tìm kiếm.
- **P2 bắt đầu — màn khoá**: bỏ hình viên pin lớn lúc sạc (thay bằng dòng «Đã sạc N%»), ngày trên – giờ lớn dưới, rãnh trượt
  kính, nút máy ảnh tròn bằng kính.
- Bảng dịch: 232 chuỗi, dịch đủ.

## 19/11/2026 — iPhone: dải hiệu suất trên thanh trạng thái; sửa nền đen màn khoá sau respring

Chi tiết: [DECISIONS.md](DECISIONS.md) D40, D39.

- Dải hiệu suất thu gọn nằm giữa giờ và cụm sóng – pin, hai kiểu (`perfStyle`): hai hàng «CPU · RAM · mạng ↓↑» và một hàng
  «CPU · RAM»; viên kính giãn vừa khít khoảng trống.
- Màn khoá lúc sạc: hết nền đen 3–7 giây sau respring (trả hình nền ngay khi ẩn hình pin).
- Lệnh thử mới `send <lớp> <hàm lớp | view> <hàm> [0|1]` — gọi một hàm của đối tượng dùng chung hay của view đang hiện, để tái
  hiện sự kiện (vd `send SBAwayController sharedAwayController _batteryStatusChanged`).
- Bảng dịch: 236 chuỗi, dịch đủ.

## 19/11/2026 — iPhone: Control Center dạng lưới

Chi tiết: [DECISIONS.md](DECISIONS.md) D41.

- Bảng lưới 2 × 2 ô kính (máy ngang 1 × 4): kết nối, nhạc, chế độ, hai thanh trượt đứng; thêm nút dữ liệu di động và đèn pin.
- Các tấm kính khác của iPad (Trung tâm thông báo, HUD, khay đa nhiệm) chạy được trên iPhone không phải sửa; khay đa nhiệm
  dạng thẻ là việc kế tiếp.

## 19/11/2026 — iPhone: khay đa nhiệm dạng thẻ

Chi tiết: [DECISIONS.md](DECISIONS.md) D42.

- `tweak/SB/G6CardSwitcher.m`: thẻ ảnh chụp cuộn ngang, chạm để mở, vuốt lên để thoát, bấm Home để đóng; lệnh thử `cards`.
- Còn lại của P2 trên iPhone: băng thông báo, hộp thoại, bảng chọn kiểu iPhone, nút AssistiveTouch, màn khoá có thông báo;
  sau đó P3 (trong app) và P4 (app của Apple + Điện thoại, Máy tính, La bàn, Ghi âm).
- Việc cần anh thử bằng tay trên iPhone (SSH không giả được cử chỉ thật): bấm Home hai lần, vuốt thẻ, kéo hai thanh trượt đứng
  của Control Center, kéo từ góc trên phải để mở Control Center.

## 20/11/2026 — iPhone: xong phần còn lại của P2, P3 và phần chính của P4

Chi tiết: [DECISIONS.md](DECISIONS.md) D43 (băng thông báo, bảng chọn, thông báo màn khoá), D44 (trong app), D45 (Điện
thoại, Máy tính, La bàn, Ghi âm + các app khác).

- Còn lại trên iPhone: lưới tháng của Lịch (vẫn ô bạc gốc; tiêu đề tháng tiếng Việt bị cắt chữ như bản gốc); màn chào của
  Mail ở chế độ tối (vài logo chữ đen); Safari (khung gốc); bàn phím mật mã, màn hình cuộc gọi, Siri (để nguyên theo
  IPHONE.md 3.9).
- Đã làm thêm trong ngày: bàn phím khoa học của Máy tính (máy ngang); tiêu đề thanh của thẻ đang ẩn vẽ lại khi đổi sáng ↔ tối
  lúc app đang chạy; viên nút thấp cho thanh 32 điểm lúc iPhone nằm ngang; bảng gác của lõi nhận libstatusbar / Zephyr /
  Speed Intensifier / Activator theo tên thư viện.
- **iPad — đã cài bản `445df1d` và soát lại (20/11/2026, một lần respring, anh đã được báo trước)**: màn khoá nằm ngang (giờ
  Inter, rãnh kính, dòng «Đã sạc 58%» thay dòng ngày, không còn hình pin lớn), màn hình chính, băng thông báo (480×40 như
  cũ), hộp thoại, bảng chọn trong bảng nổi, cửa sổ trưng bày thành phần ở chế độ tối và sáng (tiêu đề nhóm của bảng thường
  nay phẳng ở chế độ sáng — đúng ý), Ghi chú / Lời nhắc / Đồng hồ (chỉ xem phần khung + thống kê màu). Không thấy chỗ nào
  lùi. Chưa soát lại trên iPad: Lịch, Danh bạ, Ảnh, Tin nhắn, Control Center, Trung tâm thông báo (mã không đổi từ bản trước).
- Việc cần anh thử bằng tay trên iPhone: bấm Home hai lần; vuốt / cuộn thẻ ở khay đa nhiệm; kéo từ góc trên phải mở Control
  Center; một cuộc gọi thật (màn đang gọi không bị đụng, nhưng dải xanh «đang gọi» + thanh trạng thái phẳng chưa được thấy
  cùng nhau); La bàn khi hết nhiễu.

## 20/11/2026 — Chuẩn bị phát hành 1.0.0: OTA có chữ ký, nguồn Cydia, trang giới thiệu

Chi tiết kỹ thuật: [DECISIONS.md](DECISIONS.md) D46.

- **OTA**: `g6update` (setuid root, kiểm chữ ký RSA-3072 của gói), `glass6ctl` (Rust, HTTPS tự viết trên rustls + ring, 1,0 MB),
  tự kiểm bản mới ở SpringBoard (một lần / 24 giờ, báo một lần cho mỗi bản), nhóm «Cập nhật» + nhóm «Có bản mới» trong
  Cài đặt › Glass 6 (tải có tiến độ, huỷ, cài, báo lỗi). Bản dịch tiếng Anh đủ 276 / 276 chuỗi.
- **Đã thử trọn chuỗi trên iPhone 5** bằng máy chủ thử trong mạng nội bộ (bản thử cho đổi nguồn; bản phát hành thì không):
  báo bản mới → Cài đặt → tải → kiểm chữ ký → cài → tự khởi động lại (0.1.0 → 0.1.1). Qua giao diện, các nhánh lỗi báo
  đúng và không cài gì: sai chữ ký (72), gói không mới hơn (73), sai SHA-256, huỷ giữa chừng. `glass6ctl` đọc được GitHub
  thật qua TLS trên iOS 6.
- **Lỗi gặp khi thử và đã sửa**: (1) bấm «Huỷ» mà `glass6ctl` vẫn tải nốt — tiến trình con thừa hưởng mặt nạ tín hiệu của
  luồng GCD, nay đặt lại; (2) tiêu đề nhóm của bảng Cài đặt về kiểu gốc (chữ xanh xám, bóng trắng) ngay sau khi bảng nạp
  lại — lỗi có sẵn của phần bảng, nay móc thêm lượt xếp của tiêu đề nhóm; (3) tên thư mục bị cắt («Tiệ…ch») vì khung nhãn
  đo theo phông gốc; (4) chữ số đồng hồ màn khoá có viền bóng tối trên hình nền sáng. (3) và (4) thấy lúc chụp ảnh giới thiệu
  với hình nền sáng.
- **Kịch bản phát hành**: `tools/set-version.sh`, `build-release.sh`, `sign-release.sh`, `update-cydia-repo.sh`,
  `sign-cydia-repo.sh`; `tools-local/release.sh` chạy cả chuỗi ở máy phát hành. Bản 1.0.0 dựng thử: gói 1,9 MB, 458 ký hiệu.
  Khoá ký OTA và khoá GPG của nguồn Cydia nằm ở `keys/` (không lên git).
- **Trang giới thiệu** (thư mục `Glass6-site` cạnh repo — sẽ là nhánh `gh-pages` của `itovn/Glass6`): trang tiếng Việt + tiếng Anh,
  trang mô tả cho Cydia, nguồn Cydia đã ký. Ảnh chụp trên iPhone 5 với **hình nền dải màu tự vẽ và một trang chủ tạm chỉ
  gồm app gốc của Apple** (không dùng hình nền / cách sắp xếp riêng của máy; đã sao lưu và trả lại nguyên trạng sau khi
  chụp). Không có ảnh iPad (máy đang dùng thật).

## 20/11/2026 — Đã phát hành Glass 6 1.0.0

- **Nơi phát hành**: repo công khai <https://github.com/itovn/Glass6> (mã sạch, một commit, thẻ `v1.0.0`), Release `v1.0.0` kèm
  `vn.glass6.tweak_1.0.0_iphoneos-arm.deb` (1,9 MB) + `.deb.sig`, trang <https://itovn.github.io/Glass6/> (tiếng Việt,
  `en.html` tiếng Anh) và nguồn Cydia `https://itovn.github.io/Glass6/cydia/` (đã ký GPG) trên nhánh `gh-pages`.
- **Soát bản phát hành trước khi đưa lên** (gói dựng bằng `tools-local/release.sh`, 458 ký hiệu — đủ trên cả hai máy):
  iPhone 5: cài đè bản thử, SpringBoard lên đủ thành phần, Cài đặt › Glass 6, Máy tính, Đồng hồ, không có báo cáo sập mới;
  **bấm Home hai lần bằng sự kiện nút thật mở khay đa nhiệm dạng thẻ (12 thẻ, 61 ms), bấm lần nữa thì đóng** — mục «chưa
  thử» từ D42 nay đã thử. iPad mini: cài đè, một lần respring (đã báo anh và phiên dùng chung máy), cấu hình của anh không
  đổi, bảng Cài đặt › Glass 6 + màn hình chính đúng, không có báo cáo sập mới.
- **Soát sau khi đưa lên**: trên iPhone `glass6ctl update check` đọc được bản 1.0.0 từ GitHub thật («đang dùng bản mới
  nhất»); giả làm bản cũ thì tải được gói qua HTTPS (khớp kích thước + SHA-256) và `g6update --verify` báo chữ ký đúng;
  `apt-get update` với riêng nguồn mới: tải `Release.gpg` / `Release` / `Packages`, không báo lỗi chữ ký. Trang giới thiệu
  và trang mô tả hiển thị đúng trên Safari iOS 6 (thử qua máy chủ nội bộ trước khi đưa lên).
- **Cài mới từ nguồn công khai** (iPhone 5, sau phát hành): `dpkg --purge` gỡ sạch mọi tệp của Glass 6 → `apt-get update` với
  riêng nguồn mới báo `NO_PUBKEY` (đúng dự kiến: máy chưa có khoá của nguồn — đã ghi chú trên trang) → `apt-get install` tải
  gói từ github.io và cài, quyền tệp + thư mục dữ liệu đúng → không có tệp cấu hình: giao diện sáng mặc định, đủ thành phần
  (nút AssistiveTouch và dải hiệu suất tắt như thiết kế), Cài đặt › Glass 6, Điện thoại, Đồng hồ hiển thị đúng. Xong đã trả
  lại cấu hình thử cũ của máy. Chỉ chưa bấm «Cài đặt» ngay trong app Cydia.
- Anh bấm Home hai lần bằng tay trên iPhone (4 lượt, thấy trong nhật ký): khay thẻ mở đủ cả 4.
- **Cử chỉ kéo từ mép trên** (iPhone, lệnh thử `pull` — đi qua đúng hàm định tuyến của Glass 6, không phải ngón tay thật): bắt
  đầu ở x = 280 → Control Center; ở x = 80 → Trung tâm thông báo (kính 320×568, 97 ms).
- Ảnh Control Center trên trang đã chụp lại với nền trung tính + trang chủ tạm (ảnh đầu có dock thật của máy thử). Việc thay
  nền / sắp xếp biểu tượng / trả lại nay chạy bằng một kịch bản ngay trên máy (máy rớt Wi-Fi giữa chừng vẫn trả được nguyên
  trạng, có đối chiếu `cmp`).
- **Chưa ai thử bằng tay** (không giả lập được): vuốt / cuộn thẻ ở khay đa nhiệm, kéo mở Control Center bằng ngón tay thật,
  một cuộc gọi thật, La bàn khi hết nhiễu (20/11 máy vẫn báo nhiễu); iPad: Lịch, Danh bạ, Ảnh, Tin nhắn, Control Center với
  bản 1.0.0.

### Công cụ thử (bản thử, `tweak/Debug/G6Debug.m`)

```sh
bash tools-local/deploy.sh ipad          # chép mã → dựng → cài → khởi động lại SpringBoard → in nhật ký
bash tools-local/g6.sh dump              # cây view của mọi cửa sổ → dump.txt
bash tools-local/g6.sh classes SBDock    # lớp theo tiền tố → classes.txt
bash tools-local/g6.sh methods SBIconView
bash tools-local/g6.sh inspect SBDockIconListView sideIconInset horizontalIconPadding   # lớp vẽ + số đo → inspect.txt
bash tools-local/g6.sh orient 1          # giả xoay máy: 1 đứng, 3 / 4 nằm ngang
bash tools-local/g6.sh panel sang|toi|off
bash tools-local/g6.sh bench
bash tools-local/g6.sh goto 1            # lật tới trang biểu tượng thứ n (0 = trang đầu)
bash tools-local/g6.sh labels            # thông số vẽ nhãn (phông, màu, bóng chữ) → nhật ký
bash tools-local/g6.sh hud               # hiện bảng âm lượng (tăng rồi giảm lại một nấc)
bash tools-local/g6.sh alert 2           # hiện hộp thoại thử có 2 nút (1–3); alert 0 = đóng
bash tools-local/g6.sh cc 1|0            # mở / đóng Control Center
bash tools-local/g6.sh pull 900          # giả cử chỉ kéo từ mép trên xuống ở hoành độ x
bash tools-local/g6.sh cctest "tap bluetooth"    # bấm nút / kéo thanh trượt trong Control Center, ghi trạng thái thật của máy
bash tools-local/g6.sh banner            # hiện một băng thông báo thử
bash tools-local/g6.sh nc 1|0            # mở / đóng Trung tâm thông báo
bash tools-local/g6.sh sim               # trạng thái SIM + tiêu đề cảnh báo theo từng mã → nhật ký
bash tools-local/g6.sh lock              # khoá máy (như bấm nút nguồn — đèn màn hình tắt)
bash tools-local/g6.sh wake              # sáng màn hình mà không mở khoá (để chụp màn khoá)
# Đo CPU (công cụ tools/g6cpu, dựng tay bằng clang của Theos rồi chép vào /usr/bin của máy thử):
bash tools-local/ios.sh ipad ssh "g6cpu 15 backboardd SpringBoard"
bash tools-local/g6.sh edit 1|0          # vào / ra chế độ sắp xếp
bash tools-local/g6.sh folder 1|0        # mở thư mục đầu tiên trên màn hình / đóng
bash tools-local/g6.sh switcher 1|0      # mở / đóng khay đa nhiệm
bash tools-local/g6.sh iconprobe vn.grammini.app   # ghi nhật ký đường tạo ảnh biểu tượng của một app
bash tools-local/g6.sh iconshot vn.grammini.app    # lưu ảnh biểu tượng mọi định dạng + ảnh các lớp con → icons/
bash tools-local/g6.sh @Preferences dump           # lệnh có «@<tiến trình>» chạy TRONG app đó (dump, classes, methods, inspect)
bash tools-local/g6.sh appearance 0                # đặt sáng (0) / tối (1) / tự động (2): sửa đúng khoá appearance rồi báo đổi
bash tools-local/g6.sh @Preferences gallery 1      # cửa sổ trưng mọi thành phần UIKit chuẩn để soi kiểu (0 = đóng)
bash tools-local/g6.sh @Preferences popover 1      # bảng nổi thử (1 lên / 2 xuống / 3 trái, 0 đóng); sheet 1|0 = bảng chọn thử
bash tools-local/g6.sh @Preferences ui             # liệt kê thứ bấm được đang hiện → ui.txt; rồi tự bấm:
bash tools-local/g6.sh @Preferences select "Dịch vụ hệ thống"   # select <dòng> | toggle <dòng có công tắc> | press <nút> | seg <n> | back
bash tools-local/g6.sh assist menu 1               # nút AssistiveTouch: state | menu 1|0 | press <mã> | do <mã> | tap | double | hold | move <mép> <y>
bash tools-local/g6.sh svc status                  # chạy g6svc từ SpringBoard (quyền mobile): status | set twitter=1 …
bash tools-local/ios.sh ipad ssh "g6cpu -l"        # mọi tiến trình: pid, RAM (KB), giây CPU, tên
bash tools-local/g6.sh shot <tệp.png>    # chụp màn hình iPad
bash tools-local/g6.sh get dump.txt
```

## 20/11/2026 — iPhone 5: «Bật 4G» (MobiFone, Viettel, VinaPhone)

Chi tiết: [DECISIONS.md](DECISIONS.md) D47.

- `lte/g6lte.c` (setuid root): gói 4G = danh tính gói gốc của nhà mạng + cặp carrier.plist / overrides / PRI có chữ ký nguyên
  vẹn của gói 3 Hồng Kông có sẵn trong iOS 6 (CommCenter kiểm chữ ký — tự viết hay trộn tệp đều bị loại); nạp lại CommCenter
  bằng launchctl, đợi tới khi CommCenter nhận gói; `off` / gỡ gói trả đúng ba liên kết gốc.
- Bảng Cài đặt: nhóm «Mạng di động» (công tắc «Bật 4G», «Mạng đang dùng»); APN / MMS chụp trước khi bật và ghi lại qua trang
  APN của iOS (MobiFone: điền MMS của MobiFone, gỡ khi tắt); tự sửa APN khi mở bảng nếu còn giá trị của gói nguồn.
- `tweak/SB/G6CTGuard.m`: giữ callback CoreTelephony của SpringBoard ở luồng chính — chặn kiểu văng đã đưa iPhone vào safe mode
  (17/11, 20/11). Lệnh thử mới: `ctfire`, `apnprobe`, `apnget`, `apnui`, `apnset`.
- **Đã thử trên iPhone 5 + SIM MobiFone:** bật / tắt nhiều vòng từ công tắc, khởi động lại máy lúc đang bật, lệnh gỡ gói —
  LTE 500–800 KB/s, tắt về 3G gốc, trang APN đúng như trước ở cả hai chiều. Chưa thử với SIM Viettel / VinaPhone thật.

## 20/11/2026 — iPhone: sửa màu app Tin nhắn (anh báo bằng ảnh)

Chi tiết: [DECISIONS.md](DECISIONS.md) D48. Dải ngày giờ và nhãn «Tin nhắn Văn bản» không còn nền sáng; hàng nút «Gọi / Thêm vào
Danh bạ», nút «Xóa / Chuyển tiếp» ở chế độ Sửa, hàng «Đến:» và nút «+» của Tin nhắn Mới theo kiểu mới ở cả sáng lẫn tối.

### Việc tiếp theo

**Trước khi phát hành: bản cho iPhone 5 (iOS 6.1.4), giao diện theo iOS 26 của iPhone** — khảo sát máy và kế hoạch các đợt
P0–P5 ở [IPHONE.md](IPHONE.md) (19/11/2026, chờ anh duyệt danh sách tweak cần gỡ và phạm vi).

1. **Đợt 0b — phát hành:** xong — bản 1.0.0 đã lên `itovn/Glass6` ngày 20/11/2026 (mục «Đã phát hành Glass 6 1.0.0» ở
   trên). Bản sau: `tools/set-version.sh` → `tools-local/release.sh` → thử trên máy → commit vào repo công khai + Release +
   `gh-pages`; máy đang chạy 1.0.0 sẽ tự thấy bản mới (thử OTA thật lần đầu ở bản 1.0.1).
2. **Đợt 0c — dịch vụ:** đã có, thêm «Chặn cập nhật iOS» (D34: nhóm riêng trong Dịch vụ hệ thống, hồ sơ không đụng tới, dọn
   huy hiệu nhắc cập nhật trên biểu tượng Cài đặt). Hai máy thử iOS 6 đã bị gỡ sẵn hai tệp việc → ở đó hiện «Đã chặn sẵn»,
   CHƯA gạt thử được công tắc. Còn: thử tay các mục «chưa thử» ở D22; thử công tắc chặn trên máy iOS 6 còn nguyên.
3. **Đợt 1 — SpringBoard:** các bề mặt chính đã có, thêm ô tìm kiếm kính và nút «Không làm phiền» (D33). Còn: bảng kết quả
   tìm kiếm (cần gõ chữ — kết quả là dữ liệu riêng); AirPlay trong Control Center; thư mục Quầy báo (kệ gỗ); kính dock trong
   nửa dưới lúc mở thư mục (hiếm khi thấy: ở cả hai hướng dock thường bị đẩy khỏi màn hình).
4. **Đợt 2 — trong app:** thanh, nút trên thanh, bảng nổi, bảng chọn, hộp thoại, bảng nhóm, bảng thường toàn ô chuẩn, nút điều
   khiển, biểu tượng Cài đặt, thanh trạng thái, các thành phần chuẩn ở chế độ tối, bàn phím tối đã có (D23, D25, D26, D27,
   D30). App không phải của Apple: anh chốt để nguyên (D35) — không làm.
5. **Đợt 3 — app tự vẽ giao diện**: đã có Đồng hồ (D28), Ghi chú, Lời nhắc, Lịch, Danh bạ (D32 — màn hình chính của từng
   app, máy ngang và đứng, năm chế độ xem của Lịch, màn hình thêm mới, bảng nổi, bảng chọn), Ảnh và Tin nhắn (D35). Còn: sửa
   mục có sẵn (bảng chi tiết của lời nhắc, sửa liên hệ) — cần dữ liệu thử, em không tạo trên máy của anh; các mục «chưa thử»
   của Ảnh / Tin nhắn ở D35. Mail, Game Center, Nhạc: anh chốt để nguyên; còn lại giữ nguyên theo bảng chính sách trong lõi
   (`apps.rs`).
6. Nợ kỹ thuật: bản tiếng Anh đã có (D36) — còn phải respring để thử các chuỗi phía SpringBoard và nhờ người soát bản
   dịch; mã gói trong bảng xung đột (D6) chưa đối chiếu được với nguồn thật (máy thử không cài gói nào trong
   bảng); `library.mk` của Theos chép `libglass6core.dylib` vào `~/theos/lib` trên máy dựng (vô hại, nên tắt).

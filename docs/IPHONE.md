# Glass 6 trên iPhone 5 (iOS 6) — khảo sát và kế hoạch thiết kế

Ngày 19/11/2026. Anh yêu cầu mở rộng Glass 6 sang iPhone 5 **trước khi phát hành**, giao diện theo **iOS 26 (bản cho
iPhone)** — không phải iPadOS 26 như bản iPad. Tài liệu này gồm: kết quả khảo sát máy thử qua SSH (chỉ đọc, chưa cài hay đổi
gì), các tweak có sẵn nên gỡ / giữ, hướng thiết kế từng bề mặt, cách tổ chức mã, các đợt làm, rủi ro, và những điều cần anh
quyết. Thiết kế chung của dự án vẫn ở [THIET-KE.md](THIET-KE.md); quyết định đã có ở [DECISIONS.md](DECISIONS.md).

---

## 1. Máy thử (khảo sát 19/11/2026)

| | |
| --- | --- |
| Máy | iPhone 5 trắng (iPhone5,2), iOS 6.1.4 (10B350) — mục `iphone` của `tools-local/ios.sh` |
| Chip / RAM | A6 hai nhân (armv7s — chạy được mã armv7 hiện có), RAM 1 GB, đang trống ~550 MB |
| Màn hình | 640×1136 @2x = 320×568 điểm (727 nghìn điểm ảnh — xấp xỉ iPad mini 786 nghìn, nên chi phí làm mờ cả màn hình tương đương; A6 nhanh hơn A5) |
| Đĩa | hệ thống còn 310 MB, dữ liệu còn 8,1 GB |
| Nền tảng tweak | MobileSubstrate 0.9.6301, Substrate Safe Mode 0.9.6001, PreferenceLoader 2.2.6 — giống iPad |
| Công cụ thử có sẵn | `cbscreen`, `cblaunch`, `cbsymcheck`, `uiopen`, `sbreload`; **thiếu `g6cpu`** (phải chép sang) |
| API riêng | giống iPad: có `CAFilter`, `CARenderServerRenderDisplay`, `UIGetScreenImage`, vImage; thiếu `CABackdropLayer` → vẫn là kính dựng thành ảnh (D2) |
| SpringBoard | cùng bộ lớp với iPad (đã tra trong tệp chạy): `SBAwayView`, `SBAwayLockBar`, `SBAwayDateView`, `SBDockIconListView`, `SBIconController`, `SBSearchView`, `SBFolderSlidingView`, `SBAppSwitcherBarView`, `SBNowPlayingBar`, `SBBulletinListView`, `SBBulletinBannerView`, `SBHUDView`, `SBLinenView`, `SBStatusBarDataManager`… Thêm phần chỉ iPhone có: `SBDeviceLockView` (bàn phím mật mã), `SBSlidingAlertDisplay` (cuộc gọi đến / báo thức), `SBAssistantController` (Siri), `SBEmergencyCallView`, `SBSIMLockEntryAlert`, `SBUSSDAlert` |
| Artwork UIKit | `Shared@2x.artwork` (39 MB) + `Shared@2x~iphone.artwork` |
| Cập nhật iOS | hai tệp việc của dịch vụ cập nhật không còn (như iPad) + có sẵn một gói chặn cập nhật |
| Glass 6 | chưa cài |

Khác iPad ở chỗ quan trọng nhất: **máy này có sẵn nhiều tweak** (iPad gần như sạch) — mục 2.

Lưu ý: trong `ios.sh` mục này được ghi chú là «máy chính của anh (tài khoản chính)». Em coi nó là máy có dữ liệu thật: không
mở app chứa dữ liệu riêng, không đụng phần gọi điện, báo trước mọi lần respring (mục 7).

---

## 2. Tweak có sẵn: gỡ gì, giữ gì

Anh đã cho phép gỡ các tweak giao diện để hạn chế xung đột. Em **chưa gỡ gì** — dưới đây là danh sách em đề nghị, chờ anh
duyệt (gỡ là việc khó hoàn lại: vài gói chưa chắc tải lại được). Trước khi gỡ em sao lưu từng gói
(tệp + thông tin gói) về máy tính để cài lại được.

**Đề nghị gỡ** (đụng đúng bề mặt Glass 6 vẽ lại, hoặc nạp vào mọi tiến trình mà không dùng tới):

| Gói | Nạp vào | Lý do |
| --- | --- | --- |
| WinterBoard 0.9.3919 | mọi app UIKit + backboardd | Trình thay giao diện — móc việc nạp hình của cả hệ thống, đúng chỗ Glass 6 làm. Hiện **không bật gói giao diện nào** (không có tệp cấu hình) nên gỡ không mất gì. Đã nằm sẵn trong bảng xung đột của lõi |
| libstatusbar 0.9.9 | mọi app UIKit | Móc cách xếp mục của thanh trạng thái — trùng với phần «giờ bên trái / pin vẽ lại» của Glass 6. Không gói đang cài nào phụ thuộc nó |
| NCSettings 1.7.1 (+ WeeLoader, WeePreferenceLoader) | SpringBoard, Cài đặt | Hàng công tắc trong Trung tâm thông báo — Control Center của Glass 6 thay thế; nó chèn view vào đúng tấm thông báo mà Glass 6 phủ kính. Đã có trong bảng xung đột của lõi (mức «cần lưu ý») |
| Zephyr 1.6.4 (+ LayerSnapshotter) | SpringBoard | Cử chỉ vuốt để mở khay đa nhiệm / đổi app — can thiệp vào chính khay đa nhiệm và chuyển cảnh giữa các app, nơi Glass 6 phủ kính và bắt cử chỉ Control Center. **Anh cân nhắc**: nếu anh đang quen dùng cử chỉ này thì giữ, em sẽ thử chung sống |
| Speed Intensifier 5 | mọi app UIKit | Đổi tốc độ mọi hiệu ứng chuyển động — làm lệch thời gian các hiệu ứng mở / đóng tấm kính |
| Activator 1.9.13 + Flipswitch 1.0.16 | mọi app UIKit / SpringBoard | **Không có cử chỉ nào đang được gán** (đã đọc tệp cấu hình: 0 sự kiện), không gói đang cài nào phụ thuộc → đang nạp vào mọi app mà không làm gì; Activator cũng móc các cử chỉ hệ thống của SpringBoard. Gỡ cho nhẹ máy |

**Giữ** (không liên quan giao diện, hoặc là đồ của anh):

| Gói | Ghi chú |
| --- | --- |
| CBFloat, GMNotify, RZNotify, GramLockControl | Như trên iPad — Glass 6 đã chung sống ([THIET-KE.md](THIET-KE.md) mục 1, D16) |
| Gói chặn cập nhật iOS | Đang giữ việc chặn cập nhật iOS — đúng ý anh, giữ nguyên |
| Các gói còn lại (tiện ích hệ thống, thư viện phụ thuộc) | Không đụng giao diện; một gói trong số đó nạp vào mọi app UIKit — nếu gặp lỗi lạ trong app sẽ nghi nó đầu tiên |

---

## 3. Hướng thiết kế: iOS 26 trên màn hình 4 inch

Nguyên tắc như bản iPad: kính dựng thành ảnh, mỗi thành phần một công tắc, không sửa tệp hệ thống, tắt là về kiểu gốc. Cột
«Dùng lại» là phần mã iPad dùng được gần như nguyên; «Làm mới» là phần iPhone phải viết thêm.

### 3.1. Màn hình chính

| iOS 26 (iPhone) | Glass 6 trên iPhone 5 | Dùng lại / làm mới |
| --- | --- | --- |
| Biểu tượng bo góc nhiều lớp kính; 4 kiểu Mặc định / Tối / Trong / Nhuộm | Như iPad, lưới 4×5 | Dùng lại `G6Icons` (cỡ ảnh lấy lúc chạy; thêm bộ thử @2x) |
| Dock là viên kính chứa 4 biểu tượng, không nhãn, không bóng phản chiếu | Viên kính lùi vào ~10 điểm mỗi bên, bo ~28; bỏ kệ bóng + ảnh phản chiếu của iOS 6 | Dùng lại `G6Dock`; số đo riêng cho iPhone |
| Viên «Tìm kiếm» thay chấm trang, ngay trên dock | Viên kính nhỏ «Tìm kiếm»: chạm là sang trang Tìm kiếm của iOS 6; lúc lật trang hiện lại chấm | **Làm mới** (nhỏ); công tắc riêng |
| Thư mục mở thành khối kính bo góc giữa màn hình | Bước đầu: dải kính thay nền vải như iPad. Khối nổi giữa màn hình là việc để sau (đổi cả cách SpringBoard tách màn hình) | Dùng lại `G6Folders` |
| Trang Tìm kiếm | Ô tìm kiếm kính; trên iPhone thanh tìm kiếm chạy hết bề ngang và có nền riêng → bỏ nền, thêm phần bảng kết quả | Dùng lại `G6Spotlight` + chỉnh |
| Nhãn biểu tượng | Phông Inter | Dùng lại |

### 3.2. Thanh trạng thái

iOS 26: giờ ở bên trái; sóng + Wi-Fi + pin dồn bên phải; **không hiện tên nhà mạng** ở màn hình chính.

- Dùng lại `G6StatusItems` (giờ bên trái, pin vẽ lại, tia sét xanh).
- **Làm mới:** đưa cột sóng sang nhóm bên phải, ẩn tên nhà mạng (cùng cơ chế đổi vùng đã dùng cho mục giờ); tuỳ chọn hiện %
  pin bên trong hình pin như iOS 26.
- Trong app: iOS 6 trên iPhone nhuộm thanh trạng thái xám theo màu thanh điều hướng. Với thanh phẳng của Glass 6, thanh trạng
  thái phải liền một mặt với thanh điều hướng (chữ tối trên nền sáng / chữ sáng trên nền tối) — **làm mới**, là phần khó nhất
  của mục này vì mỗi app tự chọn kiểu thanh.
- Dải hiệu suất: bề ngang 320 điểm không đủ chỗ giữa thanh trạng thái → trên iPhone mặc định tắt, chỉ có kiểu «dưới thanh
  trạng thái» bản gọn.

### 3.3. Màn khoá

iOS 26: giờ rất lớn, ngày ở trên; thông báo xếp chồng phía dưới; hai nút tròn kính đèn pin / máy ảnh ở hai góc dưới.

- Dùng lại `G6Lock`: bỏ hai thanh bóng, giờ + ngày phông Inter, rãnh «trượt để mở khoá» bằng kính (vẫn trượt như cũ).
- **Làm mới:** bố cục giờ lớn kiểu iOS 26 cho màn dọc 320×568; nút máy ảnh thành nút tròn kính (vẫn kéo lên như iOS 6);
  danh sách thông báo trên màn khoá thành thẻ kính.
- Bàn phím mật mã (`SBDeviceLockView`), gọi khẩn cấp, mã PIN của SIM: **để nguyên ở bản đầu** (mục 6).
- Khung nhạc của GramLockControl: chừa chỗ như trên iPad.

### 3.4. Trung tâm thông báo, băng thông báo, HUD, hộp thoại, bảng chọn

- Dùng lại gần như nguyên: `G6NotificationCenter`, `G6Banner`, `G6HUD` (thêm HUD chuông / im lặng của iPhone), `G6Alert`.
- **Làm mới — bảng chọn kiểu iPhone:** trên iPhone `UIActionSheet` trượt từ đáy lên (không nằm trong bảng nổi như iPad) với nền
  xám bóng → tấm kính bo góc lùi vào hai bên, nút dạng viên, «Huỷ» tách riêng như iOS 26.

### 3.5. Control Center

iOS 26: vuốt từ góc trên phải; cả màn hình là lưới ô kính — cụm kết nối, ô đang phát, các nút tròn, hai thanh trượt đứng.

- Dùng lại: cửa sổ riêng, cử chỉ kéo từ mép trên ở một phần ba bên phải, mọi điều khiển đã có (Máy bay, Wi-Fi, Bluetooth,
  Không làm phiền, khoá xoay, sáng / tối, độ sáng, âm lượng, nhạc), tự ẩn.
- **Làm mới:** bố cục iPhone (bảng hiện rộng 340 điểm, không vừa màn 320): lưới hai cột kiểu iOS 26 — cụm kết nối 2×2, ô
  nhạc, hàng nút tròn, hai thanh trượt đứng. Nút mới chỉ iPhone có: **dữ liệu di động**, **đèn pin** (iPhone 5 có đèn LED),
  lối tắt Máy tính / Máy ảnh / Đồng hồ.

### 3.6. Khay đa nhiệm

iOS 26 dùng chồng thẻ ảnh chụp app. **Đã làm khay dạng thẻ** theo ý anh (DECISIONS D42, `tweak/SB/G6CardSwitcher.m`); dải
kính của `G6Switcher` vẫn còn cho lúc máy nằm ngang hoặc khi tắt «Khay đa nhiệm dạng thẻ».

### 3.7. Trong app (Glass6UI)

| iOS 26 | Glass 6 trên iPhone | |
| --- | --- | --- |
| Thanh điều hướng / công cụ phẳng, nút dạng viên | Như iPad; đã có sẵn cỡ thanh 32 điểm cho máy ngang | Dùng lại `G6UIBars` |
| **Thanh thẻ nổi** — viên kính ở đáy | Thanh thẻ thành viên bo tròn lùi vào hai bên, mục đang chọn có viên sáng; phần lề quanh viên tô cùng màu nền của app (iOS 6 không cho nội dung chui xuống dưới thanh thẻ) | **Làm mới** — iPhone dùng thanh thẻ ở rất nhiều app (Điện thoại, Đồng hồ, Nhạc, App Store) |
| Bảng nhóm dạng thẻ bo góc | Như iPad | Dùng lại `G6UITables` |
| Công tắc, thanh trượt, nút chọn đoạn, bánh xe | Như iPad | Dùng lại |
| Bàn phím | Bàn phím tối bằng bộ lọc màu (cùng lớp `UIKeyboardLayoutStar`) | Dùng lại `G6Keyboard` |
| Bảng chọn, hộp thoại trong app | Xem 3.4 | Làm mới phần bảng chọn |
| Thanh trạng thái trong app | Xem 3.2 | Làm mới |
| App Cài đặt | Một cột (không có cột trái như iPad); biểu tượng mục kiểu mới | Dùng lại, bỏ phần cột trái |

### 3.8. App của Apple

Theo phạm vi anh đã chốt cho iPad (D35): Đồng hồ, Ghi chú, Lời nhắc, Lịch, Danh bạ, Ảnh, Tin nhắn; Mail, Game Center, Nhạc và
app bên thứ ba để nguyên.

- **Tin nhắn**: cùng khung ChatKit — bong bóng phẳng, nền, thanh nhập dùng lại gần hết (`G6UIAppMessages`), bố cục một cột.
- **Ảnh**: bản iPhone dùng lớp `PLPhone…` — cùng ý (nền theo sáng / tối, nút trên thanh), phải dò lại tên lớp.
- **Đồng hồ**: thanh thẻ → theo thanh thẻ nổi ở 3.7.
- **Ghi chú, Lời nhắc**: bản iPhone dùng bộ hình khác (tên hình khác bản iPad) → khai bảng thay hình mới bằng công cụ `imglog`.
- **Lịch, Danh bạ**: bản iPhone vốn dùng thanh / bảng chuẩn (không có «cuốn sổ», «bọc da») → gần như chỉ cần kiểu chung.
- App chỉ iPhone có (**Điện thoại**, Máy tính, La bàn, Ghi âm, Thời tiết, Chứng khoán, Passbook): chưa có trong phạm vi — xem
  mục 8, câu 4.

### 3.9. Phần chỉ iPhone có — để nguyên ở bản đầu

Màn hình cuộc gọi đến / đang gọi, bàn phím số của app Điện thoại, bàn phím mật mã, Siri, gọi khẩn cấp, mã PIN của SIM, hộp
USSD. Lý do ở mục 6. Hộp thoại chuẩn của hệ thống (kể cả USSD) vẫn nhận kiểu kính chung như mọi `UIAlertView`.

---

## 4. Tổ chức mã

- **Một gói `vn.glass6.tweak` cho cả iPad lẫn iPhone** (mã armv7 chạy trên cả A5 và A6; không tách gói, không tách nhánh).
- Thêm `G6IsPad()` (Common). Mỗi mô-đun giữ một bảng số đo theo loại máy thay cho hằng số hiện tại — khảo sát mã cho thấy
  phần phụ thuộc iPad rất ít: `G6ControlCenter` (bề rộng bảng, vị trí), `G6Icons` (tên hình `~ipad`), vài chỗ ở dock, thông
  báo, khay đa nhiệm, hình nền. Lõi Rust đã nhận tỉ lệ màn hình (`scale`) cho mọi phép dựng kính.
- Thành phần chỉ có ở một loại máy đăng ký theo loại máy: thanh thẻ nổi, bảng chọn kiểu iPhone, viên «Tìm kiếm» (iPhone);
  cột trái của Cài đặt, bảng nổi (iPad).
- Bảng Cài đặt: một `Root.plist`; mục chỉ dành cho một loại máy được lọc lúc nạp (dải hiệu suất «trên cùng» chỉ iPad; ẩn tên
  nhà mạng, đèn pin, dữ liệu di động chỉ iPhone). Chuỗi mới đi qua `G6L` + `tools/gen_strings.py` (D36).
- Mặc định theo máy: lõi nhận thêm loại máy khi dựng cấu hình mặc định (vd dải hiệu suất tắt trên iPhone).
- Công cụ: `g6.sh`, `probe.sh`, `inst.sh` hiện ghi cứng `ipad` → nhận tên máy; chép `g6cpu` sang iPhone; `cbscreen` trên
  iPhone mặc định đã là 640×1136.

---

## 5. Các đợt làm

Mỗi đợt ra một bản cài được, thử trên cả hai máy (bản iPad không được lùi).

| Đợt | Nội dung | Kết quả kiểm |
| --- | --- | --- |
| **P0 — Chuẩn bị** | Sao lưu rồi gỡ các tweak đã duyệt ở mục 2; công cụ nhận tên máy; `G6IsPad()` + bảng số đo; cài bản hiện tại lên iPhone với **mọi thành phần tắt**, bật dần từng cái để lập danh sách chỗ lệch | SpringBoard lên ổn, bộ gác + Safe Mode chạy, gọi điện / nhắn tin vẫn bình thường (nhờ anh thử một cuộc), đo RAM và thời gian mở app |
| **P1 — Màn hình chính + thanh trạng thái** | Biểu tượng, dock viên kính 4 biểu tượng, nhãn, thư mục, viên «Tìm kiếm», trang Tìm kiếm, thanh trạng thái kiểu iOS 26 (giờ trái, sóng phải, ẩn nhà mạng), ẩn Quầy báo; sáng / tối | So ảnh trước – sau; vuốt trang mượt; đổi sáng ↔ tối |
| **P2 — Các tấm kính của hệ thống** | Màn khoá (giờ lớn, rãnh trượt, nút máy ảnh), Trung tâm thông báo, băng thông báo, HUD, hộp thoại, bảng chọn kiểu iPhone, Control Center bố cục iPhone (+ dữ liệu di động, đèn pin), khay đa nhiệm, nút AssistiveTouch | Từng tấm ở sáng / tối; khoá – mở khoá; các nút của Control Center đọc đúng trạng thái thật |
| **P3 — Trong app** | Thanh (cả máy ngang), thanh trạng thái trong app, thanh thẻ nổi, bảng, nút điều khiển, bánh xe, bàn phím tối, app Cài đặt một cột | Cửa sổ trưng bày thành phần chuẩn (lệnh thử `gallery`) + Cài đặt, ở cả hai chế độ và hai hướng máy |
| **P4 — App của Apple** | Đồng hồ, Ghi chú, Lời nhắc, Lịch, Danh bạ, Ảnh, Tin nhắn bản iPhone | Như D32 / D35: thống kê màu + bong bóng thử, không xem nội dung |
| **P5 — Tuỳ chọn, cần anh duyệt riêng** | Bàn phím mật mã, bàn phím số / màn hình cuộc gọi, trình đa nhiệm dạng thẻ, thư mục khối nổi | — |

Sau P4: quay lại phần phát hành (kho công khai, Cydia, OTA) cho cả hai loại máy.

Phần dùng lại nhiều nên P0–P1 nhanh; nặng nhất là P2 (bố cục Control Center, màn khoá) và P3 (thanh thẻ nổi, thanh trạng thái
trong app).

---

## 6. Rủi ro và cách giữ an toàn

- **Đây là điện thoại.** Không đụng tới phần gọi điện ở bản đầu (3.9); sau mỗi lần cài bản đổi SpringBoard, kiểm app Điện thoại
  mở được và nhờ anh thử một cuộc gọi. Bộ gác của Glass 6 (SpringBoard lên 3 lần liền không ổn → tự tắt) và Substrate Safe
  Mode đã có sẵn; thêm lối thoát bằng SSH (tệp «off»).
- **Xung đột tweak**: giảm bằng việc gỡ ở mục 2; các gói còn lại nạp vào SpringBoard (kể cả đồ của
  anh) không đụng giao diện. Bảng xung đột của lõi (D6) nay đã đối chiếu được hai mã gói với máy thật (`winterboard`,
  `com.jamied360.ncsettings` — đúng); bổ sung libstatusbar, Zephyr, Speed Intensifier, Activator ở P0.
- **Respring**: hôm nay trên iPad, respring nhiều đã làm iOS dừng GramMini (app nền kiểu VoIP) hai lần. Trên iPhone gom thay
  đổi của SpringBoard thành ít lần cài; phần trong app cài không cần respring (`inst.sh`).
- **Dữ liệu riêng**: quyền mở Danh bạ / Ghi chú / Lịch / Lời nhắc / Ảnh / Tin nhắn anh cho là trên iPad. Trên iPhone em mặc
  định KHÔNG mở các app đó; kiểm bằng cửa sổ trưng bày, bong bóng thử và thống kê màu; cần mở app nào em hỏi riêng. Ảnh chụp
  màn hình chỉ chụp khi biết máy đang ở màn hình chính / màn em vừa mở.
- **Retina**: mọi ảnh dựng theo tỉ lệ màn hình; phần tự vẽ bằng nét 1 điểm ảnh phải soát lại ở @2x.
- **Hai loại máy một gói**: mỗi thay đổi số đo có nguy cơ làm lệch bản iPad → sau mỗi đợt chạy lại lượt kiểm trên iPad.

---

## 7. Cách làm việc trên máy này

- Em chỉ điều khiển máy khi anh báo máy rảnh; báo trước mỗi lần respring, khoá máy, đổi sáng ↔ tối, mở app.
- Không đổi cài đặt của anh để thử; cấu hình Glass 6 (`vn.glass6.plist`) không bao giờ bị ghi đè.
- Mật khẩu máy vẫn chỉ đọc lúc chạy từ `info.txt` qua `ios.sh`.

---

## 8. Cần anh quyết — **anh đã trả lời 19/11/2026** (ghi ở DECISIONS D37)

Tóm tắt: (1) em toàn quyền gỡ; (2) em tự thiết kế, giống iOS 26 của iPhone nhất có thể — nên các mục P5 do em tự xếp; (3) khay
đa nhiệm làm **dạng thẻ** kiểu iOS 26 ngay; (4) nhận kiểu chung + làm riêng Điện thoại, Máy tính, La bàn, Ghi âm; (5) máy thử
không có gì quan trọng, mở và respring thoải mái. Tiến độ (20/11/2026): P0, P1 (D38), P2 (D39 – D43), P3 (D44) xong; P4 xong
phần chính (D45) — việc còn lại ghi ở PROGRESS.md mục 20/11/2026.

Các câu hỏi lúc lập kế hoạch:

1. **Danh sách gỡ ở mục 2** — anh duyệt nguyên danh sách, hay giữ lại gói nào (nhất là Zephyr và Activator)?
2. **Phần gọi điện, bàn phím mật mã, Siri** để nguyên ở bản đầu (em đề nghị vậy) — anh đồng ý chứ?
3. **Khay đa nhiệm**: bản đầu là dải kính như iPad; trình đa nhiệm dạng thẻ kiểu iOS 26 để sau phát hành — được không?
4. **App chỉ iPhone có**: có làm app nào trong số Điện thoại (danh sách, bàn phím số), Máy tính, La bàn, Ghi âm, Thời tiết,
   Chứng khoán, Passbook không? Em đề nghị bản đầu chỉ nhận kiểu chung của thanh / bảng / thanh thẻ.
5. **Quyền trên máy này**: có app chứa dữ liệu riêng nào em được mở trên iPhone không (mặc định: không), và khung giờ nào máy
   rảnh để em respring?

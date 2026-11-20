# Glass 6 — Hợp đồng giữa vỏ ObjC và lõi Rust

Lõi: `core/crates/g6-ffi` → `/usr/lib/libglass6core.dylib`. Vỏ ObjC nạp bằng `dlopen`, tra hàm bằng `dlsym`
(`tweak/Common/G6Core.m`). Thư viện chỉ xuất các hàm `g6_*` dưới đây.

Quy ước chung:

- Chuỗi là C string UTF-8. Chuỗi lõi trả về phải trả lại bằng `g6_free`.
- Ảnh là BGRA 8 bit, alpha nhân sẵn (`kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little`), `stride` = số byte mỗi hàng.
- Hàm dựng ảnh trả `0` khi được, số âm khi lỗi. Không hàm nào được panic với tham số hỏng (lõi dựng `panic = abort`).

| Mã lỗi | Nghĩa |
| --- | --- |
| `-1` | Con trỏ rỗng / chuỗi không phải UTF-8 |
| `-2` | Kích thước bằng 0 hoặc quá 4096 |
| `-3` | Vùng nhớ ra không đủ / cỡ không khớp |
| `-4` | Ảnh nền hỏng |
| `-5` | Tên bề mặt lạ |
| `-100` | (vỏ ObjC tự trả) lõi chưa nạp được |

## Hàm

```c
typedef struct { const uint8_t *data; uint32_t w, h, stride; } G6Image;
// Điểm ảnh tấm kính → điểm ảnh ảnh nền: X = a·x + c·y + tx, Y = b·x + d·y + ty
typedef struct { float a, b, c, d, tx, ty; } G6Affine;

const char *g6_version(void);                 // chuỗi tĩnh
char *g6_call(const char *json);              // lệnh điều khiển, xem bảng dưới
void  g6_free(char *s);

// Nền dưới kính: thu nhỏ + làm mờ + tăng bão hoà theo cấu hình hiện hành. fast = 1: thu nhỏ 1/8, 0: 1/4.
// pre: ảnh gốc đã được thu nhỏ sẵn bấy nhiêu lần so với màn hình (1 = cỡ màn hình) — lõi chỉ thu nhỏ nốt phần còn thiếu.
int32_t g6_backdrop_size(uint32_t src_w, uint32_t src_h, float scale, int32_t fast, uint32_t pre,
                         uint32_t *out_w, uint32_t *out_h);
int32_t g6_backdrop_prepare(const G6Image *src, float scale, int32_t fast, uint32_t pre,
                            uint8_t *out, uint32_t out_w, uint32_t out_h, uint32_t out_stride);

// Một tấm kính w × h điểm ảnh. backdrop + place cùng NULL → kính giả (không có nền).
int32_t g6_glass_render(const char *surface, uint32_t w, uint32_t h, float scale, int32_t dark,
                        const G6Image *backdrop, const G6Affine *place, uint8_t *out, uint32_t out_stride);

// Bóng đổ: ảnh (w + 2·lề) × (h + 2·lề), lề = shadowMargin của lệnh glass.metrics.
int32_t g6_shadow_render(const char *surface, uint32_t w, uint32_t h, float scale, int32_t dark,
                         uint8_t *out, uint32_t out_w, uint32_t out_h, uint32_t out_stride);

// Biểu tượng app: `pixels` chứa ảnh gốc của app đã vẽ kín w × h; lõi cắt theo hình bo góc liên tục + viền sáng, tại chỗ.
// Cùng hình với bề mặt `icon` (ô kính nền thư mục, bóng đổ của biểu tượng). Gọi được từ mọi luồng.
int32_t g6_icon_render(uint8_t *pixels, uint32_t w, uint32_t h, uint32_t stride, float scale, int32_t dark);
```

Bề mặt (`surface`): `dock`, `panel`, `banner`, `capsule`, `bar`, `card`, `icon`, `sheet`, `hud`, `list`, `alert` — số đo ở
`core/crates/g6-core/src/theme.rs`. `sheet` (Trung tâm thông báo), `hud` (bảng âm lượng) và `list` (khung thông báo trên màn
khoá) là kính đậm cho bề mặt mang chữ trắng của hệ thống: mức phủ màu có sàn, không theo hết «độ trong». `alert` (hộp thoại)
cũng có sàn mức phủ, ở cả hai chế độ sáng / tối.

## Lệnh JSON (`g6_call`)

Vào: `{"cmd": "<tên>", …}`. Ra luôn có `ok`; hỏng thì `{"ok": false, "error": "json" | "cmd" | "surface"}`.

| Lệnh | Tham số | Trả về |
| --- | --- | --- |
| `version` | — | `version` |
| `config.set` | `prefs`: từ điển phẳng của tệp `vn.glass6.plist`; `device`: tên mẫu máy (`ipad-mini-1` / `iphone-5`, xem `tweak/Common/G6Device.c`) — vài mặc định lệch theo mẫu, thiếu = iPad mini 1 | `config`: cấu hình đã kiểm, điền mặc định, kẹp tầm |
| `config.get` | — | `config` |
| `theme.dark` | `minutes`: phút trong ngày theo giờ máy | `dark` |
| `glass.metrics` | `surface`, `w`, `h`, `scale`, `dark` | `radius`, `shadowMargin`, `shadowBlur`, `shadowDy`, `shadowAlpha`, `canonW`, `canonH`, `cap` (cỡ nhỏ nhất giữ nguyên bốn góc + phần góc không kéo giãn — cho ảnh 9 mảnh), `backdrop` / `backdropFast`: `{factor, radius}` |
| `guard.scan` | `packages`: mã gói; hoặc `dpkgStatus`: nội dung `/var/lib/dpkg/status`; `dylibs`: `[{name, filters}]` | `findings`: `[{id, name, level, note, features}]`, `blocked`: thành phần phải tự tắt |
| `assist.catalog` | — | `actions`: `[{id, title, short, slot, gesture}]` (chức năng gán được cho nút AssistiveTouch — D24), `defaults`: bố cục 8 ô mặc định, `maxSlots` |
| `perf.reading` | `prev`, `cur`: hai mẫu số đếm thô liên tiếp `{t (ms), cpuBusy, cpuTotal (tích tắc), memFree, memTotal, diskFree, diskTotal (byte), netIn, netOut (byte cộng dồn)}`; thiếu `prev` = mẫu đầu tiên | `reading`: `{cpu, ram, disk (0–1, cho thanh mức), down, up (byte / giây), text: {cpu, ram, disk, down, up}}` — chuỗi đã dựng sẵn; RAM và đĩa là phần còn trống (D26) |
| `app.policy` | `bundle`: mã gói của app | `bars`, `tables`, `controls` (app này được đổi phần nào), `skeuomorphic` (app tự vẽ giao diện — D23) |
| `services.catalog` | — | `services`: `[{id, group ("A" / "B" / "C"), files, labels, title, note}]` (từ `data/services.tsv`), `profiles`: `{stock: [], balanced: [mã phải tắt…]}`. Lõi chỉ mô tả; tắt / bật thật là việc của `g6svc` (D22) |
| `lunar.month` | `month` (1–12), `year` (1800–2199) | `days`: `[{d, ld, lm, ly, leap, good, fest}]` — mọi ngày của tháng dương: ngày / tháng / năm âm, tháng nhuận, hoàng đạo, có lễ âm lịch (D50); ngoài khoảng năm = mảng rỗng |
| `lunar.day` | `day`, `month`, `year` | `day`: `{ld, lm, ly, leap, month_days, can_chi_day, can_chi_month, can_chi_year, than, good, tiet_khi, hours, festival}` — `than`: thần trực ngày, `hours`: giờ hoàng đạo («Tý (23–1)» …), `festival`: tên lễ hoặc null; ngày sai = lỗi `date` (D50) |

## Khoá cấu hình (`vn.glass6.plist`)

Khoá thiếu, sai kiểu hay ngoài tầm đều về mặc định / bị kẹp — tệp hỏng không làm tweak ngừng chạy.

| Khoá | Kiểu | Mặc định | Nghĩa |
| --- | --- | --- | --- |
| `enabled` | bool | bật | Công tắc tổng |
| `appearance` | 0 / 1 / 2 | 0 | Sáng / Tối / Tự động |
| `darkFrom`, `darkTo` | phút 0–1439 | 1140, 360 | Khoảng tối khi Tự động (19:00 → 6:00); tweak hẹn giờ tới mốc kế tiếp rồi báo đổi (`G6Prefs.m`) |
| `glassBlur` | 0–1 | 0,6 | Độ mờ của nền dưới kính |
| `glassClarity` | 0–1 | 0,55 | Độ trong (lớp màu phủ mỏng dần) |
| `glassRim` | 0–1 | 0,7 | Viền sáng |
| `glassVibrancy` | 0–1 | 0,5 | Tăng bão hoà nền |
| `glassTint` | `#RRGGBB` | không | Màu nhuộm kính |
| `reduceEffects` | bool | tắt | Bỏ khúc xạ viền, vệt sáng |
| `iconStyle` | 0–3 | 0 | Kiểu biểu tượng: mặc định / tối / trong / nhuộm màu (lõi đổi màu trong `g6_icon_render`) |
| `iconTint` | `#RRGGBB` | xanh dương | Màu của kiểu «nhuộm màu» |
| `lockHidePictureFrame` | bool | bật | Màn khoá: ẩn nút khung ảnh (hình bông hoa) |
| `statusSignalRight` | bool | iPad tắt, iPhone bật | Thanh trạng thái: cột sóng + biểu tượng mạng dồn sang phải, cạnh pin (kiểu iOS 26 của iPhone) |
| `statusHideCarrier` | bool | iPad tắt, iPhone bật | Thanh trạng thái: ẩn tên nhà mạng |
| `lockHideNoSIM` | bool | bật | Màn khoá: ẩn mục «Chưa cài đặt Thẻ SIM» (cảnh báo SIM khác vẫn hiện) |
| `lockHideBattery` | bool | bật | Màn khoá: ẩn hình viên pin lớn lúc đang sạc; thay bằng dòng «Đã sạc N%» hiện vài giây ở chỗ dòng ngày |
| `featDock`, `featIcons`, `featFolders`, `featClock`, `featSwitcher`, `featStatusBar`, `featLockScreen`, `featNotifications`, `featAlerts`, `featHUD`, `featControlCenter` | bool | bật | Công tắc từng thành phần |
| `featApps` | bool | bật | Công tắc chung của phần nạp vào app (Glass6UI đọc thẳng từ tệp, trước khi nạp lõi) |
| `featBars`, `featTables`, `featControls` | bool | bật | Trong app: thanh và nút trên thanh / bảng kiểu nhóm / công tắc, thanh trượt, nút chọn đoạn |
| `featSettingsIcons` | bool | bật | App Cài đặt: biểu tượng các mục kiểu ô màu bo góc |
| `featAppSkins` | bool | bật | Phần vẽ lại riêng cho từng app của Apple: thanh thẻ của Đồng hồ (D28); Ghi chú, Lời nhắc, Lịch, Danh bạ (D32); Ảnh, Tin nhắn (D35) |
| `featLunar` | bool | bật | App Lịch: âm lịch Việt Nam — ngày âm dưới ngày dương, ngày hoàng đạo, lễ âm lịch, thẻ chi tiết ngày đang chọn (đi cùng `featAppSkins`, D50) |
| `featKeyboard` | bool | bật | Bàn phím tối ở chế độ tối (SpringBoard + app trong phạm vi Glass6UI, D30) |
| `featSearch` | bool | bật | Ô tìm kiếm của trang Tìm kiếm (Spotlight) trên màn hình chính thành viên kính (D33) |
| `featAssist` | bool | **tắt** | Nút AssistiveTouch của Glass 6 (thay nút của iOS) |
| `assistCount` | 1–9 | 9 | Số ô của bảng nút (bảng luôn là lưới 3×3) |
| `assistSlot1` … `assistSlot9` | mã chức năng | thông báo, Control Center, màn hình chính, đa nhiệm, khoá, chụp màn hình, respring, khoá xoay, khởi động lại | Chức năng từng ô (`none` = để trống) |
| `assistMenuTimeout` | 0–60 giây | 5 | Bảng nút tự ẩn sau chừng này giây không bấm (0 = không tự ẩn) |
| `hideNewsstand` | bool | tắt | Màn hình chính: ẩn biểu tượng Quầy báo |
| `featPerf` | bool | **tắt** | Màn hình chính: dải hiệu suất (CPU, RAM, đĩa, mạng) |
| `perfPosition` | 0–1 | 0 | Dải hiệu suất: 0 = trên cùng, giữa thanh trạng thái (cần `statusTimeLeft`; chật thì tự xuống); 1 = dưới thanh trạng thái |
| `perfInterval` | 1–10 giây | 2 | Dải hiệu suất: nhịp đo |
| `switcherCards` | bool | iPad tắt, iPhone bật | Khay đa nhiệm dạng thẻ ảnh chụp (kiểu iOS 26 của iPhone) thay cho dải biểu tượng; chỉ iPhone có |
| `perfStyle` | 0–1 | 0 | Dải hiệu suất thu gọn trên thanh trạng thái của iPhone: 0 = hai hàng (CPU, RAM, mạng ↓↑), 1 = một hàng (CPU, RAM) |
| `statusTimeLeft` | bool | bật | Thanh trạng thái (SpringBoard + app trong phạm vi Glass6UI): giờ + mặt trăng «Không làm phiền» nằm bên trái |
| `statusBattery` | bool | bật | Thanh trạng thái (SpringBoard + app trong phạm vi Glass6UI): hình pin vẽ lại, tia sét xanh lá khi cắm sạc |
| `statusHideNoSIM` | bool | bật | Thanh trạng thái (mọi app): ẩn chữ «Không có SIM» |
| `ccTimeout` | 0–120 giây | 8 | Control Center tự ẩn sau chừng này giây không đụng tới (0 = không tự ẩn) |
| `updateAutoCheck` | bool | bật | Tự kiểm bản mới của Glass 6: SpringBoard chạy `glass6ctl update check` tối đa một lần mỗi 24 giờ |
| `assistTap`, `assistDouble`, `assistHold` | mã chức năng | `menu`, `none`, `none` | Chạm một lần / hai lần / nhấn giữ trên nút |
| `assistIdleAlpha` | 0,15–1 | 0,5 | Độ rõ của nút lúc nghỉ |
| `language` | chuỗi | `auto` | Ngôn ngữ hiển thị: `auto` (máy tiếng Việt → tiếng Việt, còn lại tiếng Anh) / `vi` / `en`. Lõi không đọc khoá này — `tweak/Common/G6Lang.m` đọc thẳng (D36) |
| `appsThirdParty` | bool | tắt | Áp cả cho app không phải của Apple. Khoá ẩn, không có trong Cài đặt và sẽ không có: anh chốt để nguyên app bên thứ ba (D35) |

Sau khi ghi tệp, Cài đặt gửi thông báo Darwin `vn.glass6/prefs`; tweak đọc lại và gửi `G6ConfigDidChangeNotification` trong tiến trình.

## Tệp trong `/var/mobile/Library/Glass6/`

| Tệp | Ai ghi | Nghĩa |
| --- | --- | --- |
| `off` | người dùng (SSH) | Có tệp là Glass 6 không làm gì |
| `off.auto` | bộ gác | Đã tự tắt sau 3 lần khởi động chưa ổn; Cài đặt xoá khi «Đặt lại bộ gác» |
| `boot.<tiến trình>` | bộ gác | Số lần khởi động liền chưa xác nhận |
| `status.plist` | tweak | `running`, `reason` (`off` / `auto` / `core` / `disabled`), `version`, `core`, `findings`, `blocked` |
| `glass6.log` | mọi tiến trình | Nhật ký, tối đa 256 KB |
| `assist.plist` | SpringBoard | Vị trí nút AssistiveTouch: `edge` (0 trái, 1 phải), `y` (tỉ lệ chiều cao) |
| `assist.sysat` | SpringBoard | Dấu «Glass 6 đã tắt AssistiveTouch của hệ thống» — tắt nút của Glass 6 thì bật lại |
| `cmd.txt`, `dump.txt`, `classes.txt`, `methods.txt`, `inspect.txt`, `icons/` | bản thử | Lệnh và kết quả của công cụ thử |

Phần nạp vào app dùng `/var/tmp/vn.glass6/` (`G6_APP_DIR` — hộp cát của Mail, Safari, Ảnh… không cho đụng thư mục trên):

| Tệp | Nghĩa |
| --- | --- |
| `app.<tiến trình>` | Số lần app mở liền mà chưa chạy ổn |
| `skip.<tiến trình>` | App này bị bỏ qua vì sập liên tiếp lúc có Glass 6; «Đặt lại bộ gác» xoá |
| `glass6.log`, `cmd.txt`, `dump.txt`… | Nhật ký và tệp công cụ thử của app trong hộp cát |

Trạng thái của bộ gác dịch vụ ở `/var/db/glass6/` (chỉ root ghi — `g6svc`; `postrm` xoá khi gỡ):

| Tệp | Nghĩa |
| --- | --- |
| `pending` | Có lần đổi dịch vụ chưa được xác nhận; nội dung = số lần máy đã khởi động kể từ lần đổi |
| `previous` | Trạng thái từng dịch vụ trước lần đổi đó (`<mã>\t<0|1>`) — để hoàn tác |
| `reverted` | Bộ gác vừa tự hoàn tác; bảng Cài đặt báo một lần rồi `g6svc ack` |

Ảnh đã dựng nhớ ở `/var/mobile/Library/Caches/Glass6/` (xoá lúc nào cũng được; `postinst` xoá mỗi lần cài bản mới, `postrm` xoá khi gỡ):

| Tệp | Nghĩa |
| --- | --- |
| `icons/<mã app>~<định dạng>@<tỉ lệ>x~<l hoặc d>.g6i` | Ảnh biểu tượng đã dựng (sáng / tối). Đầu tệp 32 byte (`G6CI`, bản, rộng, cao, dấu của ảnh máy tạo ra, dấu của kiểu dáng) + điểm ảnh BGRA thô; nạp bằng ánh xạ bộ nhớ |

# Glass 6 — Các quyết định kỹ thuật

Thiết kế đầy đủ: [THIET-KE.md](THIET-KE.md).

## D1. Phạm vi và cách phát hành (anh chốt 19/11/2026)

- Mặc định chỉ nạp vào SpringBoard và app của Apple; app bên thứ ba bật tay từng app.
- Phát hành công khai lên Cydia → phông **Inter** (OFL) thay SF, biểu tượng xử lý bằng thuật toán, không đóng kèm ảnh của Apple.
- Cài xong không tắt dịch vụ nào; người dùng tự chọn hồ sơ.
- Làm trên iPad trước (1024×768 @1x); iPhone tính sau.
- Máy thử (iPad mini 1 iOS 6.1.3) dùng tự do: được khởi động lại SpringBoard / máy tuỳ ý.
- Repo, nguồn Cydia, OTA làm theo GramMini (D7).

## D2. Kính không mờ thời gian thực — dựng thành ảnh (19/11/2026)

Tra trên máy bằng `cbsymcheck`: iOS 6.1.3 **thiếu** `CABackdropLayer`, `_UIBackdropView`; **có** `CARenderServerRenderDisplay`,
`_UIImageWithName`, vImage. Nên mỗi tấm kính là một ảnh lõi dựng sẵn:

- nền = hình nền mờ sẵn (bề mặt trên màn hình chính) hoặc ảnh chụp màn hình một lần lúc sắp hiện (bề mặt trên app);
- lõi ghép nền + khúc xạ viền + màu phủ + viền sáng + mặt nạ bo góc thành **một** ảnh BGRA → CALayer chỉ vẽ ảnh, không
  cắt bo góc (bài học của Côn Bằng TV: `cornerRadius` + `clipsToBounds` làm cuộn giật).

Đã chạy thật trên iPad mini 1: 7 tấm kính + 1 kính giả, sáng và tối, làm mờ đúng biểu tượng nằm dưới.

## D3. Lõi Rust là thư viện động dùng chung, nạp bằng `dlopen` (19/11/2026)

- `g6-ffi` dựng thành `libg6_ffi.a` (**chỉ** `staticlib` — thêm `rlib` thì cargo tắt LTO, GramMini đã gặp), bọc bằng Theos
  `library.mk` thành `/usr/lib/libglass6core.dylib` (252 KB) với `-force_load` + `-exported_symbols_list` (`_g6_*`) + `-dead_strip`.
- Hàm iOS 6 thiếu mà thư viện chuẩn Rust cần (`clock_gettime`, `__exp10`, `__sincos_stret`, `CCRandomGenerateBytes`…) chép từ
  `GMShims.c` vào `corelib/G6Shims.c`. Chúng **không xuất** ra ngoài thư viện → SpringBoard / Cài đặt không thấy.
- Tweak và bảng Cài đặt `dlopen` + `dlsym` từng hàm: lõi thiếu / lệch bản thì Glass 6 tự tắt, tiến trình chủ không sao.
- Lõi không có mạng. Phần HTTPS cho OTA sẽ nằm ở công cụ riêng `glass6ctl` để SpringBoard không gánh TLS.
- Tra ký hiệu cả ba tệp chạy trên iPad: 164 ký hiệu, thiếu 0.

## D4. Toạ độ: mọi ảnh nền theo khung hình dọc, kính lấy nền qua phép biến đổi affine (19/11/2026)

iPad nằm ngang thì giao diện SpringBoard xoay 90° so với khung hình (ảnh chụp màn hình và toạ độ cửa sổ iOS 6 luôn theo hệ
dọc). Vì vậy `g6_glass_render` nhận một phép biến đổi affine «điểm ảnh kính → điểm ảnh nền» thay cho một hình chữ nhật;
vỏ ObjC tính nó từ ba điểm của view đổi sang toạ độ màn hình (`G6GlassImageForView`). Có phép thử nền xoay 90°.

## D5. Tốc độ dựng kính trên A5 (đo 19/11/2026, iPad mini 1)

| | Bản đầu | Sau tối ưu |
| --- | --- | --- |
| Chụp màn hình + thu nhỏ 1/8 + làm mờ | 54 ms | 43–53 ms |
| Kính 320×400 | 100 ms | 33–36 ms |
| Kính dock 700×100 | 50 ms | 31–34 ms |
| Bóng đổ 320×400 | 161 ms | 63 ms lần đầu, 0,5 ms các lần sau |

Hai thay đổi:

1. **Đường số nguyên cho phần giữa tấm kính** (`glass::render`): mỗi hàng chia ba đoạn; hai đoạn sát mép tính đủ bằng số
   thực (khúc xạ, viền sáng, khử răng cưa), đoạn giữa chỉ lấy mẫu song tuyến + phủ màu bằng số nguyên. Có phép thử so hai
   đường (lệch ≤ 2 mức màu).
2. **Bóng đổ là ảnh 9 mảnh có nhớ lại**: lõi cho cỡ nhỏ nhất giữ nguyên bốn góc (`canonW` / `canonH` / `cap` của
   `glass.metrics`); vỏ ObjC dựng ở cỡ đó, kéo giãn bằng `resizableImageWithCapInsets:`, giữ trong `NSCache`.

Còn để ngỏ: chụp màn hình thẳng vào IOSurface cỡ nhỏ (để GPU thu nhỏ hộ) — chưa thử; dải sát mép vẫn là số thực.

## D6. Bộ gác an toàn (19/11/2026)

- Viết bằng libc (`tweak/Common/G6Guard.c`), chạy trước khi nạp lõi: tệp `off` (công tắc tổng), bộ đếm
  `boot.<tiến trình>`, tệp `off.auto`.
- Tự tắt sau **3** lần khởi động liền chưa xác nhận (xác nhận sau 20 giây chạy ổn). Thiết kế ban đầu ghi 2 lần / 30 giây;
  đổi vì khởi động lại SpringBoard hai lần sát nhau là chuyện thường lúc cài đặt.
- `postinst` xoá bộ đếm và `off.auto` (bản mới là khởi đầu mới), giữ tệp `off` của người dùng.
- Đã thử trên máy: tệp `off` → không chạy; bộ đếm = 3 → tự tắt và tạo `off.auto`; xoá đi → chạy lại.
- Quét xung đột (`guard::scan`): hiện trạng máy thử cho 4 mục mức «info», không chặn gì. **Mã gói trong bảng `KNOWN`
  (WinterBoard, DreamBoard, Springtomize 2, Auxo, Zeppelin, SBSettings, NCSettings) ghi theo trí nhớ — phải đối chiếu với
  nguồn Cydia thật trước khi phát hành.**

## D7. Repo, nguồn Cydia, OTA theo GramMini (anh chốt 19/11/2026)

- Repo phát triển riêng tư (đủ lịch sử); repo công khai `itovn/Glass6` (ảnh chụp mã sạch mỗi bản + Releases +
  nhánh gh-pages làm trang giới thiệu và nguồn Cydia `https://itovn.github.io/Glass6/cydia/`).
- OTA: như `gmupdate` của GramMini — gói ký RSA-3072 PKCS#1 v1.5 + SHA-256, chứng chỉ gắn trong công cụ cài setuid root,
  chỉ nhận link `github.com/itovn/Glass6/releases/download/`, chỉ cài bản mới hơn. Khác GramMini ở chỗ Glass 6 là tweak:
  việc kiểm / tải do công cụ `glass6ctl` (Rust, rustls) làm theo lệnh của SpringBoard hoặc Cài đặt, không nằm trong lõi.
- Khoá ký OTA và khoá GPG của nguồn Cydia tạo riêng cho Glass 6, để ở `keys/` (không lên git).
- Chưa làm — Đợt 0b.

## D9. Dock kính (anh muốn thấy dock trước — 19/11/2026)

Bản đồ SpringBoard iOS 6 trên iPad (tra bằng `g6.sh dump` / `methods` / `inspect`):

```text
SBAppWindow (mức -1) › SBUIRootView (xoay theo máy) › UIView
  SBWallpaperView (-[SBUIController wallpaperView]; ảnh 1024×1024 cắt giữa; hai lớp con là dải tối trên / dưới)
  SBIconContentView
    UIView = -[SBIconController dockContainerView]
      SBDockIconListView = -[SBIconController dock]   ← ảnh kệ dock là layer.contents của chính view này
        SBIconView (74×93): ảnh, bóng (_shadow), bóng phản chiếu (_reflection), nhãn (_labelView)
      SBIconListPageControl
    SBIconScrollView › SBIconListView (mỗi trang)
```

Cách làm (`tweak/SB/G6Dock.m`), mọi hàm thay thế gọi lại hàm gốc và trả đúng kết quả gốc khi thành phần tắt:

| Móc | Để làm gì |
| --- | --- |
| `+[SBDockIconListView backgroundImageForOrientation:]` | Trả ảnh **trong suốt cùng cỡ** → mất kệ dock. Không trả `nil`: SpringBoard lấy khung của dock từ cỡ ảnh này, trả `nil` thì xoay ngang → dọc dock vẫn rộng 1024 và biểu tượng xếp tràn ra ngoài màn hình |
| `-[SBDockIconListView sideIconInset]` | Lề lớn hơn → SpringBoard tự dồn biểu tượng vào giữa (khoảng hở 26 pt). Khoảng cách giữa các ô SpringBoard tự suy từ lề và bề rộng dock, nên bố cục và chỗ thả biểu tượng vẫn khớp. Bề rộng tính theo `_orientation` của dock, không theo `bounds` (lúc xoay, biểu tượng được xếp trước khi khung đổi) |
| `-[SBIconView showsReflection]` | `NO` → mất bóng phản chiếu |
| `layoutIconsNow`, `layoutIconsIfNeeded:domino:`, `_updateForOrientation:duration:` | Sau khi SpringBoard xếp xong thì cập nhật tấm kính (gom về vòng lặp kế) |
| `-[SBWallpaperView _wallpaperChanged]`, `didMoveToWindow` | Đổi hình nền / hình nền vừa vào cửa sổ → dựng lại nền của kính |

- Nhãn của biểu tượng trong dock ẩn bằng `setLabelHidden:` (iPadOS không có nhãn trong dock).
- Tấm kính và bóng đổ là hai `UIImageView` chèn vào `dockContainerView`, dưới `SBDockIconListView` → dock trượt đi đâu kính theo
  đó. Khung kính = hợp các khung biểu tượng, nới 18 × 12 pt (6 biểu tượng: 610×100).
- Nền = `SBWallpaperView` vẽ vào ảnh nhỏ hơn màn hình 4 lần theo hệ toạ độ khung hình, nội suy mức thấp, rồi lõi làm mờ
  (`pre = 4`). Vẽ đủ cỡ rồi thu: 185 ms → vẽ thẳng cỡ nhỏ: ~70 ms. Giữ lại tới khi xoay máy / đổi hình nền / đổi cấu hình.
- Lúc SpringBoard vừa lên (máy còn ở màn khoá) hình nền chưa vào cửa sổ → tạm dựng kính giả, mở khoá xong thì thay bằng kính thật.
- Tắt thành phần (`featDock`) lúc đang chạy: trả lại kệ, bóng phản chiếu, nhãn, bố cục gốc — không cần khởi động lại SpringBoard.

Đã thử trên iPad mini 1: sáng / tối, tắt / bật trực tiếp, xoay dọc và hai chiều ngang (giả xoay bằng lệnh thử `orient`).
**Chưa thử được từ SSH:** kéo thả biểu tượng vào / ra dock trong chế độ sắp xếp, dock có ít hơn 6 biểu tượng.

## D10. Biểu tượng app (19/11/2026)

SpringBoard iOS 6 tạo ảnh biểu tượng (tra bằng lệnh thử `iconprobe` / `iconshot`):

```text
-[SBIcon getIconImage:định dạng]                 nhớ trong _cachedIconImages[12]
  -[SBApplicationIcon generateIconImage:]
    -[SBApplicationIcon __loadIconImage:mã app format:scale:]
      +[UIImage _applicationIconImageForBundleIdentifier:format:scale:]   MobileIcons: cắt góc + phủ lớp bóng kính,
                                                                          nhớ trên đĩa ở Caches/com.apple.IconsCache
```

- Định dạng 2 (màn hình chính, iPad @1x): ảnh 74×78, biểu tượng 72×72 ở (1, 2). Bóng đổ là `UIImageView` riêng
  (`_shadow`: ảnh 130×130 ở màn hình chính, 74×76 trong dock). Thư mục: `_iconBackgroundView` (ảnh 74×78) + lưới biểu tượng nhỏ.
- **Chèn ở `__loadIconImage:format:scale:`, phía trên bộ đệm của MobileIcons** → bộ đệm của máy vẫn là ảnh gốc, gỡ Glass 6
  là hết dấu. Không móc `-[UIImage _applicationIconImageForFormat:precomposed:scale:]`: SpringBoard không đi qua hàm đó.
- **Ảnh nguồn là tệp biểu tượng gốc của app** (chưa cắt góc, chưa phủ bóng kính), tìm qua `LSApplicationProxy`
  (`boundResourcesDirectoryURL`, `boundIconFileNames`) + các khoá `CFBundleIcon*` của Info.plist; chọn ảnh vuông nhỏ nhất
  ≥ cỡ cần. Chỉ hỏi LaunchServices và đọc tệp nên chạy được ở luồng nền. Không tìm được (hoặc biểu tượng Thời tiết, đổi
  theo vai °C / °F) thì cắt lại từ ảnh của máy — còn lớp bóng kính nhưng đúng hình.
- **Vùng chứa biểu tượng của từng định dạng không ghi cứng:** cho UIKit cắt một ảnh trắng đặc, vùng đặc kín của kết quả là
  chỗ của biểu tượng. Định dạng nào không ra ô vuông (ảnh kiểu tài liệu có góc gấp) thì không đụng.
- Hình: siêu elip bậc 5 phủ kín ô vuông (hình biểu tượng của iOS 7 trở đi) — nằm lọt trong hình góc tròn của iOS 6 nên
  cắt lại từ ảnh của máy cũng không hở. Viền sáng mảnh ở mép hướng về nguồn sáng.
- **Biểu tượng có nền trong suốt** (hình tròn, hình rời — quá 4% diện tích trong suốt) được đặt lên ô kính, để mọi biểu
  tượng cùng một hình. iOS 6 để các biểu tượng này lơ lửng.
- Nền thư mục = cùng ô kính đó (kính giả, không có nền mờ: biểu tượng trượt theo trang còn hình nền đứng yên). Quầy báo:
  cắt kệ gỗ theo hình mới, bỏ khung viền gỗ.
- Bóng đổ: `_shadowImage` trả bóng mềm của lõi; khung của nó đặt lại quanh vùng chứa biểu tượng ở bốn chỗ SpringBoard đặt
  khung (`_updateShadowFrameForShadow:`, `_updateShadowFrame`, `_updateShadow`, `positionIconImageView`) — chỉ móc
  `_updateShadowFrameForShadow:` là không đủ (đã gặp: bóng lệch 28 điểm).
- **Bộ đệm trên đĩa** (`Caches/Glass6/icons`): tìm + đọc tệp gốc của 60 app mất ~1,2 giây trên A5; có bộ đệm còn ~0,1 giây
  (nhanh hơn cả đường gốc 0,15 giây). Tệp đệm hợp lệ khi dấu của ảnh máy tạo ra (FNV-1a 64 bit trên điểm ảnh) và dấu
  của kiểu dáng (bản lõi, bản tweak, viền sáng, độ trong, màu nhuộm, giảm hiệu ứng) đều khớp. Bản sáng và bản tối là hai
  tệp riêng nên đổi sáng ↔ tối không phải dựng lại.
- Hàm gắn **lúc nạp** (trước khi SpringBoard tạo ảnh đầu tiên) để khỏi tạo hai lần; sau khi quét xung đột mà thành phần
  bị chặn thì tạo lại theo kiểu gốc. Tắt / bật `featIcons` lúc đang chạy: mọi biểu tượng tạo lại ảnh ngay.

- Thư mục / Quầy báo tạo bóng trước khi có ô nền → phải đặt lại bóng sau `-[SBFolderIconView setIcon:]`.

Đã thử trên iPad mini 1: hai trang biểu tượng + dock, sáng / tối, tắt / bật trực tiếp, chế độ sắp xếp (nút xoá đúng
chỗ), mở thư mục, khay đa nhiệm, xoay dọc / ngang. **Chưa làm:** 4 kiểu biểu tượng (Mặc định / Tối / Trong / Nhuộm màu) của thiết kế — mới
có kiểu Mặc định; biểu tượng đang tải về (`SBDownloadingIcon`) giữ kiểu gốc.

## D11. Nhãn biểu tượng và phông Inter (19/11/2026)

- **Phông:** Inter 4.1 (OFL), bốn tệp TTF tĩnh Regular / Medium / SemiBold / Bold lấy từ bản phát hành chính thức
  (`extras/ttf`), cài ở `/Library/Application Support/Glass6/Fonts/` kèm `LICENSE-Inter.txt`. `tweak/Common/G6Font.m`
  đăng ký bằng `CTFontManagerRegisterFontsForURL` cho riêng tiến trình (lần đầu cần tới), thiếu thì trả phông hệ thống.
  Gói nặng thêm ~0,9 MB; chưa cắt bớt ký tự (giữ cả Kirin, Hy Lạp cho tên app nước ngoài) — nếu cần nhẹ thì cắt bằng fonttools.
- **Nhãn:** SpringBoard vẽ nhãn thành ảnh theo `SBIconLabelImageParameters`. Gốc (đo bằng lệnh thử `labels`): Helvetica
  đậm 13, chữ trắng, bóng đen 60% lệch (0, 1) không nhoè, tối đa 112×18. Mới: Inter Medium 12,5, bóng đen 90% nhoè 3,5.
  Móc `-font`, `-shadowBlur`, `-shadowColor` (lớp gốc + `SBDockIconLabelImageParameters`); lớp con của biểu tượng trong
  Quầy báo có phông riêng, không đụng.
- **Ảnh nhãn được nhớ theo bộ thông số** (chữ, cỡ tối đa…), phông không nằm trong phép so → tắt / bật lúc đang chạy nhãn vẫn
  giữ ảnh cũ. Cách xử lý: bộ thông số tạo lúc Glass 6 đang bật được đánh dấu (đối tượng liên kết, gắn ở `initWithText:…`,
  chép theo ở `copyWithZone:`), và `isEqual:` coi bộ có dấu khác bộ không dấu. Đổi trạng thái rồi gọi `updateLabel` là nhãn vẽ lại.
- Nhãn đi theo công tắc «Biểu tượng kiểu mới» (`featIcons`).
- **Bẫy armv7:** hàm trả struct lớn hơn 4 byte (`CGSize`, `CGRect`…) phải gọi qua `objc_msgSend_stret`; ép kiểu `objc_msgSend`
  là sập. Lệnh thử `labels` bản đầu mắc lỗi này và làm SpringBoard sập một lần (05:09 ngày 19/11/2026, Substrate Safe Mode
  đỡ). Gọi hàm gốc qua con trỏ hàm có kiểu đúng (như trong các hàm thay thế) thì không sao.

## D12. Thư mục mở, hình nền mờ dùng chung (19/11/2026)

SpringBoard iOS 6 mở thư mục bằng cách xẻ màn hình làm hai nửa trượt ra (tra bằng `g6.sh folder 1` + `dump`):

```text
SBIconContentView › UIView (_slidingViewsContainer)
  SBFolderSlidingView (nửa trên, _upperSlidingView) › UIView
    UIView › SBWallpaperView (bản sao hình nền, chỉ phủ phần PHÍA TRÊN thư mục)
    SBLinenNotchView                    mũi nhọn bằng vải chỉ lên biểu tượng thư mục
    SBFolderView (_folderView)          dải thư mục suốt bề rộng màn hình
      SBLinenView (_backgroundView)     hai ảnh vải
      SBFolderTitleLabel, SBFolderIconListView, UIImageView × 6 (bóng trong ở bốn mép)
  SBSlidingViewHighlight, SBFolderNotchHighlightView
  SBWallpaperNotchView
  SBFolderSlidingView (nửa dưới): bản sao hình nền + ảnh kệ dock + biểu tượng của dock
```

- **Giữ nguyên cách xẻ / trượt của SpringBoard, chỉ đổi vật liệu** (`tweak/SB/G6Folders.m`). Đổi sang khối nổi ở giữa màn hình
  kiểu iPadOS là viết lại cả bố cục lẫn chuyển động mở thư mục — chưa làm, để sau khi các bề mặt khác xong.
- Phía sau `SBFolderView` không có gì, nên tấm kính (bề mặt `bar`) lấy nền là hình nền đã mờ đúng chỗ dải nằm → trông như dải
  kính mờ phủ trên hình nền. Tấm kính đặt **trong** `SBLinenView`: SpringBoard đổi khung / độ mờ của nền thư mục thế nào kính
  theo thế ấy. Vải, bóng trong, mũi nhọn, nét sáng: ẩn. Tên thư mục: Inter SemiBold cùng cỡ.
- Kính chỉ dựng khi view đã vào cửa sổ (trước đó chưa biết dải nằm đâu trên hình nền): móc `_placeBackgroundView`,
  `didMoveToWindow` (dựng ngay + dựng lại ở vòng lặp kế), `-[SBFolderSlidingView _placeNotchAndHighlights]`. Dải 1024×289: ~45 ms.
- Quầy báo (`SBNewsstandFolderView`, kệ gỗ) chưa đụng.
- **Hình nền mờ tách thành mô-đun dùng chung** `tweak/SB/G6Wallpaper.m` (trước nằm trong dock): `G6WallpaperBackdrop()`,
  `G6WallpaperGeneration()`, thông báo `G6WallpaperDidChangeNotification`. Chỉ theo dõi hình nền chính
  (`-[SBUIController wallpaperView]`) — lúc mở thư mục SpringBoard tạo thêm các bản sao `SBWallpaperView`.

Đã thử trên iPad mini 1: sáng / tối, ngang / dọc, tắt `featFolders` thì lần mở sau về nền vải + mũi nhọn như gốc.
**Còn thiếu:** lúc thư mục mở, biểu tượng của dock nằm trong nửa dưới và không có tấm kính dock đi theo (thấy khi thư mục
ít hàng nên dock chưa trượt khỏi màn hình); chế độ tối dải gần như đen đặc trên hình nền tối.

## D13. Biểu tượng Đồng hồ sống (anh yêu cầu 19/11/2026)

Yêu cầu: biểu tượng Đồng hồ chạy như iOS đời cao — kim giờ, phút, giây theo giờ và múi giờ của máy; bật / tắt trong Cài đặt.

- **Ảnh tĩnh** (mọi định dạng: màn hình chính, ô nhỏ trong thư mục, tìm kiếm): mặt đồng hồ tự vẽ bằng CoreGraphics — nền than,
  mặt trắng, 12 vạch giờ, kim đứng ở 10:09:30 — đưa qua cùng khâu cắt hình với mọi biểu tượng (`G6IconImageFromSource`: kiểu
  mới nếu `featIcons` bật, không thì nhờ UIKit cắt theo kiểu gốc của máy). Không dùng ảnh của Apple. Chỉ vạch, không có chữ
  số: ảnh có thể được tạo ở luồng nền, vẽ chữ bằng UIKit trên iOS 6 thì phải ở luồng chính.
- **Kim sống:** trên mỗi `SBIconView` đang hiện biểu tượng `com.apple.mobiletimer`, thêm vào `SBIconImageView` một lớp phủ =
  mặt đồng hồ không kim + ba lớp kim (ảnh vẽ gấp đôi độ phân giải, có lề trong suốt để xoay không răng cưa) + chốt giữa.
  Lớp phủ nằm trong lớp vẽ của ảnh biểu tượng nên rung / mờ / tối theo biểu tượng. Móc `setIcon:`, `iconImageDidUpdate:`,
  `didMoveToWindow` của `SBIconView`.
- **Cách cho kim chạy — đã đo trên iPad mini 1** bằng `tools/g6cpu` (màn hình chính đứng yên, % của một nhân CPU):

  | Cách | backboardd | SpringBoard |
  | --- | --- | --- |
  | Không có đồng hồ sống | 1,5% | 0,1% |
  | `CABasicAnimation` xoay đều lặp mãi | 13,1% | 0,2% |
  | `CADisplayLink` cách 6 khung hình (10 lần / giây) | 4,9% | 1,5% |
  | **`NSTimer` 10 lần / giây (đang dùng)** | **4,9%** | **0,9%** |
  | Như trên, Đồng hồ ở trang khác (nhịp dò 4 lần / giây) | 1,5% | 0,2% |
  | Đồng hồ bật, đang ở trong app | 1,6% | 0,1% |
  | «Giảm hiệu ứng» (không kim giây, nhích mỗi phút) | 1,4% | 0,1% |

  Chuyển động liên tục của CoreAnimation bắt tiến trình vẽ dựng lại cả màn hình 60 lần mỗi giây; giờ của nó lại đứng khi máy
  ngủ nên còn phải chỉnh kim sau mỗi lần thức. `CADisplayLink` có `frameInterval` vẫn đánh thức tiến trình ở mọi khung hình.
  Nhịp 10 lần / giây tính từ tốc độ đầu kim giây: mỗi lần nhích không quá ~0,3 điểm ảnh (màn @2x sẽ tự ra ~19 lần / giây).
  Mỗi nhịp đọc giờ thật (`CFAbsoluteTimeGetCurrent` + độ lệch múi giờ đã nhớ) nên không bao giờ lệch.
- **Chỉ chạy khi có người nhìn:** SpringBoard gỡ hẳn màn hình chính khỏi cửa sổ lúc mở app (`tearDownIconListAndBar`) →
  `didMoveToWindow` cho biết; khoá / tắt màn hình: móc `-[SBAwayController activate / deactivate / finishedDimmingScreen /
  undimScreen: / _finishedUnlockAttemptWithStatus:]` rồi hỏi `isLocked` / `isDimmed`. Đổi giờ / múi giờ:
  `UIApplicationSignificantTimeChangeNotification`, `NSSystemTimeZoneDidChangeNotification`.
- Công tắc «Đồng hồ chạy thật» (`featClock`, khoá `clock` trong cấu hình của lõi), độc lập với «Biểu tượng kiểu mới».

Đã thử trên iPad mini 1: kim đúng giờ (đối chiếu `date` trên máy, múi ICT) ở các lần chụp cách nhau vài giây; sau khi mở app
rồi về; sau khoá 20 giây rồi mở khoá; tắt / bật công tắc; kiểu biểu tượng gốc; chế độ tối; chế độ sắp xếp; màn hình dọc;
giảm hiệu ứng (kim phút nhích khi sang phút mới). **Chưa thử:** Đồng hồ nằm trong dock / thư mục / khay đa nhiệm; chạm giữ
biểu tượng; đổi múi giờ lúc đang chạy; máy ngủ lâu (cắm sạc + SSH nên máy không ngủ sâu).

## D14. Thanh trạng thái của SpringBoard (19/11/2026)

- iOS 6 trên iPad: `UIStatusBarWindow` (mức 999) › `UIStatusBar` › `UIStatusBarBackgroundView` (lớp vẽ mang ảnh kéo giãn 5×20
  từ `-_baseImageForStyle:` — dải đen mờ) + `UIStatusBarForegroundView` (alpha 0,75, chứa các `UIStatusBarItemView` tự vẽ
  thành ảnh). Thanh của SpringBoard **luôn ở kiểu 1**, kể cả lúc có app đang mở — khi đó thanh của chính app (do app vẽ) nằm
  đè lên. Nên đổi ở SpringBoard chỉ thấy ở màn hình chính, màn khoá, khay đa nhiệm, lúc chuyển cảnh.
- `tweak/SB/G6StatusBar.m`: `_baseImageForStyle:` → ảnh cùng cỡ, đen 30% ở mép trên nhạt dần tới trong suốt (giữ cho chữ
  trắng đọc được trên hình nền sáng mà không thành một dải); `-[UIStatusBar _foregroundAlphaForStatusBarStyle:]` → 1;
  `-[UIStatusBarItemView textFont]` → Inter SemiBold cùng cỡ. Bật / tắt lúc đang chạy: gán lại ảnh nền + độ rõ, gọi
  `updateContentsAndWidth` từng mục rồi `reflowItemViews:`.
- Thanh trạng thái bên trong app là việc của Đợt 2 (`Glass6UI`).

## D15. Khay đa nhiệm, hàm phủ kính dùng chung (19/11/2026)

- Khay: `SBShowcaseWindow` (mức 2005) › … › `SBAppSwitcherBarView` › `UIView` › `SBLinenView` (`_backgroundView`) + trang
  biểu tượng. `tweak/SB/G6Switcher.m` móc `layoutSubviews` / `didMoveToWindow` rồi phủ kính lên nền vải. Thành phần mới
  `switcher` (`featSwitcher`).
- **`G6GlassFill(host, active, surface)`** (`tweak/SB/G6GlassFill.m`) — dùng chung cho thư mục và khay: ẩn các view con của
  view nền, đặt bên trong một `UIImageView` kính phủ kín, nền là hình nền đã mờ đúng chỗ view nằm trên màn hình; không gì
  đổi thì không dựng lại; `active = NO` trả lại nguyên trạng. Bề mặt vải nào khác của SpringBoard cũng dùng được hàm này.
- **Hình nền mờ dựng được cả khi hình nền không nằm trong cửa sổ** (đang ở trong app, máy còn ở màn khoá): tự vẽ ảnh của
  `SBWallpaperView` (là `UIImageView`) vào giữa khung hình, xoay theo hướng giao diện (1: 0°, 2: 180°, 3: +90°, 4: −90°).
  Bản tự vẽ thiếu hai dải tối trên / dưới của hình nền nên chỉ dùng tạm: về màn hình chính là dựng lại bản thật và tăng số
  thế hệ để các tấm kính dựng lại. Nhờ vậy lúc SpringBoard vừa lên dock đã có kính thật (hết cảnh «kính giả 0,1 giây»).

Đã thử trên iPad mini 1: thanh trạng thái tắt ↔ bật trực tiếp; khay ở màn hình chính và trong app Cài đặt; thư mục vẫn
đúng sau khi gom mã. **Chưa thử:** khay khi xoay dọc, trang điều khiển nhạc của khay, mở khay trong app rồi xoay máy.

## D16. Màn khoá (19/11/2026)

iOS 6 trên iPad (tra bằng `g6.sh lock` + `wake` + `dump`): `SBAlertWindow` (mức 1050) › `UIView` (xoay theo máy) › `SBAwayView`:

```text
SBWallpaperView                          hình nền màn khoá
SBAwayBulletinListView                   danh sách thông báo (chưa đụng)
TPLCDView : TPLCDBar : UIImageView       thanh trên: ảnh nền bóng kính là image của chính nó, nét bóng ở -shadowView
  … SBAwayDateView (_dateHeaderView): TPLCDTextView _timeLabel, _dateAndTetheringLabel (đổi phông bằng -setLCDTextFont:)
GLCPanel                                 của GramLockControl — không đụng
SBAwayLockBar : TPBottomLockBar : TPBottomBar (_lockBar)
  nền vẽ trong drawRect (-setSuppressDrawingBackground:), _backgroundView, -shadowView
  TPWell (_well) › TPLockTextView, TPLockKnobView (_knobView);  UIButton _slideshowButton (nút khung ảnh)
```

- **Chỉ đổi vật liệu, giữ nguyên bố cục và cách trượt mở khoá** (`tweak/SB/G6Lock.m`). Đồng hồ lớn kiểu iPadOS (ngày ở trên, giờ
  rất to ở dưới) sẽ đè lên chỗ SpringBoard đặt tên bài hát đang phát và điều khiển nhạc trong thanh trên → chưa làm.
- Thanh trên: bỏ ảnh nền + nét bóng; giờ → Inter SemiBold, ngày → Inter Medium, cùng cỡ chữ gốc. Dòng ngày phải nới bề rộng
  theo phông mới (SpringBoard đặt khung theo phông gốc → chữ bị cắt «…»), làm lại sau mỗi `updateClock`.
- Thanh dưới: bỏ nền; rãnh trượt → viên kính (bề mặt `capsule`, nền = hình nền màn khoá đã mờ đúng chỗ — `G6WallpaperRender`
  trên `SBWallpaperView` của màn khoá, nhớ theo hướng máy); núm trượt vẽ lại (viên trắng có mũi tên, cùng cỡ ảnh gốc); nút
  khung ảnh → nền kính tròn.
- **Nút khung ảnh (hình bông hoa) ẩn theo yêu cầu của anh**: khoá cấu hình `lockHidePictureFrame` (mặc định ẩn). Ẩn bằng chính
  `-[SBAwayLockBar setShowsSlideshowButton:]` (gỡ nút khỏi thanh, mất luôn vùng chạm); móc hàm đó để nhớ ý SpringBoard muốn và
  ép «không hiện» khi đang ẩn. Chỉ có tác dụng khi `featLockScreen` bật.
- **Nằm ngang hạ cụm giờ + ngày xuống 24 điểm theo yêu cầu của anh** (`kLandscapeClockDrop`): dùng phép dời (`transform`) trên
  cả thanh trên — SpringBoard đặt lại khung mỗi lần xếp nhưng không đụng tới phép dời. Màn dọc giữ vị trí gốc.
- **Mục «Chưa cài đặt Thẻ SIM» ẩn theo yêu cầu của anh**: khoá cấu hình `lockHideNoSIM` (mặc định ẩn). Mục đó là một
  `SBSIMLockAlertItem` trạng thái 3 (đo bằng lệnh thử `sim`: 3 chưa có SIM, 4 lỗi SIM, 5 khoá SIM, 6 khoá PUK, 7 PUK hết hạn,
  8 quay số cố định, 9 SIM không đúng), vào danh sách thông báo của màn khoá qua
  `-[SBAwayBulletinListController activateAlertItem:didUndimScreen:]`. Móc hàm đó và bỏ qua **đúng** trạng thái 3; mục đã lỡ
  hiện (màn khoá dựng trước khi Glass 6 gắn hàm) thì gỡ bằng `-deactivateAlertItem:`; tắt tuỳ chọn thì đưa lại vào danh sách.
  Dòng «Không có SIM» trên thanh trạng thái không đổi. Chỉ có tác dụng khi `featLockScreen` bật.
- **Khung danh sách thông báo** (`SBAwayBulletinListView`: ảnh khung đen bóng phủ kín + bảng các ô + hai ảnh bóng): ảnh khung
  → tấm kính đậm (bề mặt `list`, nền = hình nền màn khoá đã mờ), hai ảnh bóng ẩn; móc `layoutSubviews` của nó để dựng lại khi
  khung đổi cỡ. Chữ trong ô đã là Inter nhờ D18. Lệnh thử `banner` không tạo được thông báo lúc máy khoá → thử bằng chính mục
  «Chưa cài đặt Thẻ SIM» (tạm tắt `lockHideNoSIM`).
- Ảnh / phông gốc cất trên chính view (đối tượng liên kết); tắt `featLockScreen` lúc đang chạy là trả lại nguyên trạng.
- Móc `-[SBAwayView layoutSubviews / didMoveToWindow]` (GramLockControl cũng móc hai hàm này — hai bên nối chuỗi, không giẫm nhau)
  và `-[SBAwayDateView updateClock]`.
- Lệnh thử: `lock` (khoá như bấm nút nguồn — **đèn màn hình tắt**), `wake` (sáng lại mà không mở khoá: `undimScreen` chưa đủ
  sau khi khoá hẳn, phải gọi thêm `-[SpringBoard resetIdleTimerAndUndim:]` + `setBacklightFactor:`).

Đã thử trên iPad mini 1: kiểu mới / kiểu gốc đổi trực tiếp, sáng / tối, ngang / dọc, ẩn ↔ hiện nút khung ảnh, vị trí đồng hồ
ngang / dọc, ẩn ↔ hiện mục «Chưa cài đặt Thẻ SIM» (ngay sau khi SpringBoard lên, và sau một vòng mở khoá → khoá lại). **Chưa thử:** trượt mở khoá bằng tay (núm mới), màn khoá có mật mã, lúc đang phát nhạc (tên bài trong thanh trên,
bảng GramLockControl), thông báo thật trên màn khoá (nhiều ô, trượt ô để mở app), cắm sạc (hình pin lớn).

## D17. Bảng âm lượng và băng thông báo — kính trên ảnh chụp màn hình (19/11/2026)

Hai bề mặt đầu tiên nổi trên app, nên nền của kính là **ảnh chụp màn hình một lần lúc sắp hiện**
(`+[G6Backdrop backdropWithScreen:YES]`, thu nhỏ 1/8), không phải hình nền.

- **Bảng âm lượng** (`tweak/SB/G6HUD.m`, `featHUD`): `SBHUDView` tự vẽ nền đen + các nấc trong `-drawRect:`; tên và hình loa là
  view con màu trắng. Móc `-[SBHUDController presentHUDView:autoDismissWithDelay:]` để chụp nền TRƯỚC khi bảng hiện (bảng
  đang hiện mà bấm tiếp thì dùng lại ảnh cũ — chụp lại sẽ dính chính nó) và `-[SBHUDView drawRect:]` để vẽ tấm kính (bề mặt
  `panel`) + tự vẽ các nấc, không gọi hàm gốc. Luôn dùng kính tối vì chữ / hình loa của máy màu trắng. Bảng 160×160: 13 ms.
  Chưa vẽ nấc vàng của giới hạn âm lượng EU.
- **Băng thông báo** (`tweak/SB/G6Banner.m`, `featNotifications`): `SBBulletinBannerView` có `_backgroundImageView`,
  `_titleLabel`, `_messageLabel`, `_accessoryImageView`. Trước khi SpringBoard xếp chỗ: đổi phông Inter + màu chữ theo sáng /
  tối; sau khi xếp: nới tiêu đề cho vừa chữ (SpringBoard chừa bề rộng theo phông gốc chứ không theo phông đang gắn → bị cắt
  «…») và đẩy hình phụ theo; vào cửa sổ thì thay ảnh nền bằng tấm kính (bề mặt `banner`). Mỗi băng dựng một lần; tắt thành
  phần thì băng kế tiếp là kiểu gốc. Băng 480×40: ~56 ms kể cả chụp màn hình.
- Lệnh thử: `hud` (tăng rồi giảm lại một nấc âm lượng), `banner` (`-[SBBulletinBannerController showTestBanner]`).

Đã thử trên iPad mini 1: cả hai ở màn hình chính và trong app Cài đặt; băng ở sáng / tối. **Chưa thử:** băng của thông báo
thật (có hình đính kèm, tin nhắn dài), băng lúc máy nằm dọc, bảng chuông / tắt tiếng, bấm nút âm lượng thật liên tiếp.
**Chưa làm:** Trung tâm thông báo (kéo từ mép trên xuống — nền vải, ô thông báo cũng vẽ bằng vải) và thông báo trên màn khoá.

## D18. Trung tâm thông báo, kính đậm cho bề mặt mang chữ trắng (19/11/2026)

iOS 6 trên iPad (tra bằng `g6.sh nc 1` + `dump` / `inspect`): cửa sổ `SBBulletinWindow` (mức 1049, chỉ có lúc bảng mở) ›
`SBBulletinListView` › bảng 480 điểm (`-slidingView`) gồm `-linenView` (ảnh vải), `SBBulletinTableView` (đầu mục
`SBBulletinHeaderView`, ô `SBBulletinListCell`, mảnh lấp `SBBulletinLinenSegmentView`), `SBFakeStatusBarView`, tay nắm, viền.

- **Mọi mảnh vải mang THẲNG ảnh vải chung** (`+[SBBulletinListView linen]`, 480×1024) trên lớp vẽ của mình, gắn một lần lúc tạo,
  với `contentsRect` chọn phần của mình; `-linenView` hiện phần trên của chính ảnh đó. Nên dựng một ảnh **cùng khổ** mà phần
  trên (cao bằng bảng) là tấm kính, rồi đổi ảnh trên `-linenView` và trên từng mảnh (cả mảnh mới tạo lúc cuộn: móc
  `-adjustContents`, `-didMoveToWindow` của `SBBulletinLinenSegmentView`). Hai cách đã thử mà không được: thay riêng ảnh của
  `-linenView` bằng ảnh cỡ bảng (đầu mục và mảnh lấp vẫn là vải); móc `+linen` rồi gọi `-adjustContents` (không đọc lại ảnh).
- Nền của kính = ảnh chụp màn hình lúc bảng sắp vào cửa sổ (`-willMoveToWindow:`); kính dựng cho chỗ bảng nằm khi đã kéo
  xuống hết (`-onscreenY`), không phải chỗ đang trượt. Bảng đóng thì trả ảnh vải (nhả ~2 MB), lần mở sau dựng lại. 480×543: ~46 ms
  (+ ~45 ms chụp màn hình).
- Lớp phủ tối của vải: `-_linenGradientAlphaForHeight:` → 0, `_gradientView` của đầu mục ẩn; viền vải ẩn; dải bóng của đầu
  mục còn 35%.
- Chữ: năm hàm phông của `SBBulletinCellContentView` (`_titleFont`, `_subtitleFont`, `_messageFont`, `_dateFont`,
  `_attachmentFont`) → Inter; lớp này dùng chung cho ô thông báo trên màn khoá. Nhãn đầu mục → Inter + nới bề rộng.
- **Bề mặt `sheet` và `hud` (kính đậm):** chữ trong Trung tâm thông báo và bảng âm lượng do máy vẽ màu trắng. Kính thường ở
  «độ trong» mặc định chỉ phủ 46% → trên app nền trắng ra xám nhạt, chữ trắng khó đọc (đã gặp). Hai bề mặt này có sàn mức phủ
  (70% / 66%), không theo hết «độ trong»; vỏ ObjC luôn dựng chúng ở chế độ tối.
- Cùng công tắc với băng thông báo (`featNotifications`, nhãn «Thông báo kính»).

Đã thử trên iPad mini 1: mở ở màn hình chính và trong app Cài đặt, màn dọc, tắt công tắc → lần mở sau về vải.
**Chưa thử:** kéo bằng tay (kính đứng yên trong lúc bảng trượt theo ngón tay), nhiều mục app, xoá thông báo, tiện ích
(thời tiết / chứng khoán) trong bảng, xoay máy lúc bảng đang mở.

## D19. Hộp thoại (UIAlertView) (19/11/2026)

iOS 6 (lệnh thử `alert <số nút>`): cửa sổ `_UIAlertNormalizingOverlayWindow` (mức 1996) › `UIAlertView` với
`_backgroundImageView` (ảnh nền xanh bóng), `_titleLabel`, `_bodyTextLabel`, `_subtitleLabel`, `_taglineTextLabel`, `_buttons`
(các `UIAlertButton : UIButton` theo thứ tự chỉ số nút).

- Mã ở **`tweak/Common/G6Alert.m`** (mức UIKit, không phụ thuộc SpringBoard) — Đợt 2 nạp vào app dùng lại nguyên tệp này. Hiện
  mới nạp trong SpringBoard nên chỉ hộp thoại của hệ thống đổi; hộp thoại trong app thì chưa.
- Chụp màn hình lúc hộp thoại sắp vào cửa sổ (`-willMoveToWindow:`, mỗi hộp thoại một lần) làm nền; ảnh nền → tấm kính bề mặt
  `alert` (kính đậm ở cả hai chế độ: sáng trắng đục, tối than — sàn mức phủ 72%), dựng theo **khung cuối** (tâm + cỡ trong
  cửa sổ phủ) vì lúc hiện hộp thoại đang bị co giãn bởi hiệu ứng «bật ra».
- **Đường xếp chỗ thật là `-_layoutPopupAlertWithOrientation:animated:`**; `-layoutAnimated:` không được gọi trong đường này (móc
  riêng nó thì hộp thoại không đổi — đã gặp). Móc cả ba (`_layoutPopup…`, `layoutAnimated:`, `layout`) + `didMoveToWindow`.
- Chữ: Inter, màu theo sáng / tối, bỏ bóng chữ. Nút: nền viên bo tròn (ảnh kéo giãn, nhớ theo chiều cao / chế độ / trạng thái
  bấm); nút Huỷ chữ màu thường, nút khác chữ màu nhấn (xanh) đậm.
- **Bẫy đã gặp ở hàm dựng kính dùng chung:** view cha của hộp thoại chính là một `UIWindow`, mà `-[UIWindow window]` trả `nil`
  → hàm tưởng view chưa vào cửa sổ và dựng kính giả không nền (chữ của app phía sau lọt qua). `G6Glass` giờ coi `UIWindow` là
  cửa sổ của chính nó (`G6WindowOf`).

Đã thử trên iPad mini 1: 1 / 2 / 3 nút, sáng / tối, ở màn hình chính và trong app Cài đặt, tắt `featAlerts` → hộp thoại kế là
kiểu gốc. **Chưa thử:** bấm nút bằng tay (trạng thái bấm), hộp thoại có ô nhập chữ (mật khẩu Wi-Fi…), hộp thoại thật của hệ
thống (pin yếu, xoá app), hộp thoại lúc máy nằm dọc; bảng chọn (`UIActionSheet`) chưa làm.

## D20. Control Center (19/11/2026)

iOS 6 chưa có Control Center. `tweak/SB/G6ControlCenter.m` (`featControlCenter`):

- **Mở bằng cử chỉ có sẵn của hệ thống.** SpringBoard iOS 6 có cử chỉ «kéo từ mép trên xuống» chạy cả trong app (mở Trung tâm
  thông báo), đi qua năm hàm của `SBUIController`: `_showNotificationsGestureBeganWithLocation:`,
  `…ChangedWithLocation:velocity:`, `…EndedWithLocation:velocity:`, `_showNotificationsGestureCancelled`, `…Failed`. Móc cả
  năm: cử chỉ bắt đầu ở **một phần ba bên phải** (toạ độ theo hướng giao diện) thì giữ lại trọn cử chỉ cho Control Center, kéo
  xuống > 24 điểm hoặc vuốt nhanh thì mở; bắt đầu ở chỗ khác thì gọi hàm gốc → Trung tâm thông báo như cũ. Không móc đủ cả năm
  thì không gắn cử chỉ (giữ «bắt đầu» mà để lọt «kết thúc» là SpringBoard nhận cử chỉ cụt đầu).
- **Đóng:** chạm ra ngoài bảng, nút Home (`-[SBUIController clickedMenuButton]`), xoay máy, máy khoá (bảng tự kiểm mỗi 2 giây).
- **Bảng:** `UIWindow` riêng mức 1055, khung xoay theo hướng giao diện như cửa sổ của SpringBoard (1: 0°, 2: 180°, 3: +90°,
  4: −90°); nền = tấm kính đậm (bề mặt `hud`) trên ảnh chụp màn hình lúc sắp mở, đặt ở góc trên phải. Hình trên nút tự vẽ bằng
  `UIBezierPath`. Dựng lại mỗi lần mở, huỷ khi đóng (không giữ gì trong bộ nhớ lúc không dùng).
- **Điều khiển** — lớp của SpringBoard, thiếu thì nút đó không hiện:

  | Nút | Lớp / hàm |
  | --- | --- |
  | Máy bay | `SBTelephonyManager +sharedTelephonyManager`: `isInAirplaneMode`, `setIsInAirplaneMode:` |
  | Wi-Fi | `SBWiFiManager +sharedInstance`: `wiFiEnabled`, `setWiFiEnabled:` |
  | Bluetooth | `BluetoothManager +sharedInstance`: `powered`, `setPowered:` + `setEnabled:` |
  | Khoá xoay | `SBOrientationLockManager +sharedInstance`: `isLocked`, `lock`, `unlock` |
  | Sáng / tối | ghi `appearance` vào `vn.glass6.plist` rồi `notify_post("vn.glass6/prefs")` |
  | Độ sáng | `SBBrightnessController +sharedBrightnessController setBrightnessLevel:`; đọc `BKSDisplayBrightnessGetCurrent()` |
  | Âm lượng | `SBMediaController +sharedInstance`: `volume`, `setVolume:` |
  | Nhạc | `SBMediaController`: `nowPlayingTitle`, `nowPlayingArtist`, `isPlaying`, `togglePlayPause`, `changeTrack:` (±1) |

- Lệnh thử: `cc 1|0`, `pull <x>` (gọi đúng ba hàm cử chỉ của `SBUIController`), `cctest state | tap <nút> | brightness <v> | volume <v>`.

Đã tự thử trên iPad mini 1 (đọc trạng thái thật của máy sau mỗi lần bấm): cử chỉ ở x = 900 / 700 (dọc) mở Control Center, ở
x = 400 mở Trung tâm thông báo; Bluetooth bật ↔ tắt; khoá xoay khoá ↔ mở; độ sáng 0,30 / 0,60; âm lượng 0,40 / 0,70; nút
sáng / tối; mở trong app Cài đặt; màn dọc. **Chưa thử:** cử chỉ bằng ngón tay thật (toạ độ điểm bắt đầu SpringBoard đưa vào có
đúng là toạ độ giao diện không — bản thử ghi toạ độ vào nhật ký), **nút Wi-Fi và Máy bay** (tắt là mất SSH tới máy thử), ba nút
nhạc (bấm phát sẽ bật nhạc), nút Home để đóng, mở trên màn khoá. Chưa có: AirPlay, đèn pin (iPad mini 1 không có đèn);
«Không làm phiền» đã thêm — xem D33.

## D21. Bốn kiểu biểu tượng (19/11/2026)

Khoá cấu hình `iconStyle` (0 mặc định, 1 tối, 2 trong, 3 nhuộm màu) + `iconTint`. Đổi màu bằng thuật toán trên ảnh của app,
trong lõi (`icon.rs`, hàm `restyle`, chạy trước khi cắt hình) — không cần app cấp ảnh riêng, không đóng kèm ảnh của ai:

| Kiểu | Cách tính trên từng điểm ảnh (L = độ sáng) |
| --- | --- |
| Tối | nhân màu với `0,82 − 0,30·L²`: trắng còn ~52%, màu đậm gần như giữ nguyên |
| Trong | màu thành trắng, độ đục = `0,20 + 0,72·smoothstep(L)`: chỗ sáng đục, chỗ tối để hình nền lọt qua |
| Nhuộm màu | pha từ nền than (28, 28, 30) tới màu nhuộm (làm sáng 20%) theo `L^0,85` |

Vỏ ObjC không đổi gì ở đường dựng ảnh: `g6_icon_render` đọc cấu hình hiện hành; chỉ thêm `icon_style` / `icon_tint` vào dấu
kiểu dáng của bộ đệm và vào điều kiện «tạo lại mọi ảnh». Mặt đồng hồ sống cũng đi qua cùng khâu nên đổi theo.
Đã thử trên iPad mini 1: ba kiểu + hai màu nhuộm, đổi trực tiếp từ tệp cấu hình. **Chưa thử:** gạt mục chọn trong Cài đặt bằng
tay; kiểu «Tối» chưa tự bật theo chế độ tối (là lựa chọn riêng).

## D22. Dịch vụ hệ thống: danh mục, `g6svc`, bộ gác khởi động (19/11/2026)

**Ba mảnh, một nguồn.** `data/services.tsv` là danh mục duy nhất (mã, nhóm A / B / C, việc launchd, tên, «tắt thì mất gì»):

- lõi Rust (`services.rs`, `include_str!`) → lệnh `services.catalog` cho bảng Cài đặt + hai hồ sơ dựng sẵn (`stock` = không
  tắt gì, `balanced` = nhóm A + B); phép thử chặn nhãn sai dạng, nhãn trùng, dịch vụ sống còn (`FORBIDDEN`);
- `svc/g6svc.c` — công cụ **setuid root** ở `/usr/libexec/glass6/g6svc`; danh sách trắng cứng `catalog.h` sinh từ cùng tệp
  lúc dựng (`tools/gen_catalog.py`, kiểm lại đúng các điều kiện của lõi). Tham số chỉ là **mã** dịch vụ — không có cách nào
  bảo nó đụng tới việc ngoài danh mục. Môi trường bị xoá, `/bin/launchctl` gọi bằng đường dẫn tuyệt đối;
- `tweak/Common/G6Services.m` — cầu nối cho SpringBoard và bảng Cài đặt (`posix_spawn` với `POSIX_SPAWN_CLOEXEC_DEFAULT`:
  không tệp đang mở nào của tiến trình chủ lọt sang công cụ quyền root).

Không có khoá cấu hình cho dịch vụ: trạng thái thật là của launchd, hồ sơ «đang dùng» suy ra từ đó.

| Lệnh | Việc |
| --- | --- |
| `g6svc status` | `<mã>\t<0|1>` từng dịch vụ có trên máy (1 = đang tắt), `#pending\t<n>`, `#reverted\t1` |
| `g6svc set <mã>=<0|1> …` | tắt (`launchctl unload -w`) / bật (`load -w`); một tham số sai là không làm gì (mã thoát 2) |
| `g6svc revert` | bật lại tất cả — `prerm` gọi khi gỡ gói |
| `g6svc boot` | launchd gọi mỗi lần máy khởi động (`/Library/LaunchDaemons/vn.glass6.svcguard.plist`) |
| `g6svc confirm` | SpringBoard gọi 60 giây sau khi mở xong |
| `g6svc ack` | bảng Cài đặt gọi sau khi đã báo «đã tự hoàn tác» |

**Bộ gác** (tệp trong `/var/db/glass6/`): lần `set` đầu ghi `previous` (trạng thái trước) và `pending` = 0; mỗi lần `set` sau
đặt lại `pending` = 0. `boot` tăng `pending`; tới 2 thì trả mọi dịch vụ về `previous` và để dấu `reverted`. `confirm` chỉ có
tác dụng khi `pending` ≥ 1 — tức máy **đã khởi động lại** với đúng cấu hình đó rồi SpringBoard chạy ổn 60 giây; respring không
tính (lỗi chỉ lộ lúc khởi động máy thì respring không thử được). Xác nhận không phụ thuộc lõi hay công tắc «Bật Glass 6»; có
tệp `off` thì không xác nhận (hai lần khởi động sau, dịch vụ tự về như trước).

**Khảo sát trên iPad mini 1 (161 tệp việc trong `/System/Library/LaunchDaemons`) — vì sao danh mục như hiện nay:**

- Nhãn không phải lúc nào cũng trùng tên tệp: `com.apple.aggregated.addaily.plist` có nhãn `com.apple.addaily` → danh mục ghi
  «tệp:nhãn».
- Việc `LaunchOnlyOnce` (`com.apple.CrashHousekeeping`: dọn báo cáo sập cũ lúc khởi động) chạy xong là launchd bỏ khỏi danh
  sách → không đọc được trạng thái bằng `launchctl list`, mà tắt nó còn có hại (báo cáo sập không ai dọn) → **không đưa vào**.
- `crashreportcopymobile`, `crash_mover` chỉ chạy khi iTunes / Xcode xin chép báo cáo sập, tắt không lợi gì → **không đưa vào**.
- `com.apple.sociald` (Facebook tích hợp của iOS 6) → thêm vào nhóm A.
- Phần lớn dịch vụ trong danh mục là «chạy khi có yêu cầu» (không có tiến trình thường trực). Lợi thật: `aggregated` không
  còn chạy thường trực (~0,6 MB), không còn gom / gửi chẩn đoán, và hết cảnh `ubd` bị bật lại: lúc khảo sát launchd bật `ubd`
  **12 lần trong 2 phút** (tệp `ubiquity.keepalive` còn đó thì launchd cứ bật, `ubd` không có máy chủ nên thoát ngay; máy
  không đăng nhập iCloud). Gỡ rồi nạp lại thì vòng lặp dừng — nó chỉ nổi lên khi có app gọi tới iCloud Documents.
- Cập nhật iOS qua mạng (OTA) không nằm trong `/System/Library/LaunchDaemons` của iOS 6.1.3 → chưa có trong danh mục.

**Đã tự thử trên iPad mini 1 (iOS 6.1.3, p0sixspwn):**

| Việc thử | Kết quả |
| --- | --- |
| `g6svc` gọi từ SpringBoard (uid 501) | bit setuid có tác dụng; `status` 45 ms; mã lạ / sai dạng / `../x` → mã thoát 2, không đổi gì |
| Áp «Cân bằng» (9 dịch vụ, 13 việc) từ SpringBoard | 0,67–0,71 giây; `overrides.plist` được ghi; 13 việc biến khỏi `launchctl list` |
| Mở khi đang «Cân bằng» | Cài đặt: iCloud, Ảnh & Camera, Twitter, Facebook, Giới thiệu, Sử dụng, Bảo mật; app: Ảnh, Safari, Cydia, Mail, Nhạc, Game Center, Bản đồ — đều lên bình thường |
| **Khởi động lại máy** | 9 dịch vụ vẫn tắt; bộ gác đếm 1; SpringBoard xác nhận sau 60 giây (`pending`, `previous` bị xoá); không có báo cáo sập mới |
| Giả hai lần `boot` chưa xác nhận | tự trả về trạng thái trước (dịch vụ vừa tắt bật lại, vừa bật tắt lại), `#reverted 1`, `ack` xoá dấu |
| Tắt cả 15 (thêm nhóm C) rồi respring | Cài đặt: Cài đặt chung, Điểm truy cập cá nhân, Siri, Nhạc, Wi-Fi, Bàn phím; app: Game Center, Nhạc, Ghi chú, Ảnh — đều lên; 30 giây đứng yên không tiến trình nào tự bật lại, CPU các dịch vụ còn lại ~0% |
| `revert` | 15 dịch vụ bật lại, thư mục trạng thái rỗng |

App Store báo «Không thể kết nối với iTunes Store» và ô Sử dụng không có số giờ dùng pin — **cả ở trạng thái nguyên bản**, không
liên quan tới việc tắt dịch vụ.

**Chưa thử (cần tay người):** bấm công tắc / nút hồ sơ trong Cài đặt › Glass 6 › Dịch vụ hệ thống (mới xem màn hiện đúng trạng
thái); bảng chia sẻ khi Twitter / Facebook / Weibo đã tắt; hộp thoại In khi AirPrint tắt; giữ nút Home và phím micro khi Siri
tắt; đăng nhập Game Center khi `gamed` tắt; phát Điểm truy cập khi có SIM; gỡ gói (`prerm` → `revert`).

## D23. Đợt 2: Glass6UI — thanh, bảng, nút điều khiển trong app (19/11/2026)

**Thư viện thứ hai.** `Glass6UI.dylib` lọc theo `com.apple.UIKit` nên được nạp vào mọi tiến trình có UIKit; hàm khởi tạo thôi
ngay nếu là SpringBoard (đã có Glass6SB), không phải gói `.app` trong `/Applications` hay thư mục app người dùng (AssistiveTouch
nằm ở `/System/Library/CoreServices` cũng là «app» — bỏ), app ngoài phạm vi (mặc định chỉ `com.apple.*`; `appsThirdParty` mở
cho app khác), công tắc tổng / «Giao diện trong app» tắt. Lớp ObjC dùng chung với Glass6SB được đổi tên lúc dịch
(`-DG6Backdrop=G6UIBackdrop`) vì cả hai thư viện cùng có mặt trong SpringBoard.

**Bẫy đã dính: không đụng UIKit trong hàm khởi tạo của thư viện.** Lúc đó `UIApplicationMain` chưa chạy, GraphicsServices chưa
khởi động phông: gọi `UIFont` là app sập `EXC_BREAKPOINT` ngay lúc mở (Cài đặt, Ghi chú, Nhạc sập 2 lần liền ở bản thử đầu).
Kiểu UIAppearance lại phải đặt trước khi view đầu tiên vào cửa sổ, nên điểm cài là ngay sau `-[UIApplication setDelegate:]`
(UIApplicationMain gọi, trước `application:didFinishLaunching…`). Không móc được thì đặt muộn ở thông báo «mở xong» rồi gỡ –
gắn lại view gốc.

**Bộ gác riêng từng app** (`g6_guard_app_begin`): bộ đếm `app.<tên>`; 3 lần mở liền không lần nào chạy ổn (1,5 giây sau khi
mở xong, hoặc lui về nền được) → tệp `skip.<tên>`, từ đó chỉ app ấy bị bỏ qua. Lần sập ở trên là phép thử thật: mỗi app sập
đúng số lần giới hạn rồi lẽ ra tự được bỏ qua.

**Hộp cát của app Apple trên iOS 6.1.3** (dò bằng cách ghi kết quả vào chính tệp cấu hình của từng app):

| App | Đọc `vn.glass6.plist` | Đọc / ghi `/var/mobile/Library/Glass6` | Ghi `/var/tmp` | Đọc phông Inter, lõi |
| --- | --- | --- | --- | --- |
| Mail, Safari, Ảnh, Lịch, Bản đồ, Camera | được | **không** | được | được |
| Cài đặt, Tin nhắn, App Store, iTunes, Danh bạ, Đồng hồ, Lời nhắc, Video, Game Center, Photo Booth, Ghi chú, Nhạc | được | được | được | được |

→ Mọi tệp của phần trong-app (bộ đếm, dấu «bỏ qua», nhật ký và tệp công cụ thử của app trong hộp cát) nằm ở
`G6_APP_DIR` = `/var/tmp/vn.glass6`. App không ghi được cả chỗ đó thì bộ gác bỏ qua nó (không gác được thì không đụng).

**Chính sách theo app nằm trong lõi** (`apps.rs`, lệnh `app.policy`): app «giả vật liệu» của iOS 6 (Lịch, Danh bạ, Ghi chú,
Lời nhắc, Game Center, Nhạc, Photo Booth, Camera, iBooks…) tự vẽ thanh bằng ảnh riêng — đổi một nửa (viên kính trên thanh da)
trông hỏng hơn để nguyên → giữ thanh và bảng, chỉ đổi nút điều khiển chuẩn, cho tới khi có bản vẽ lại riêng (Đợt 3).

**Ba thành phần** (công tắc `featBars`, `featTables`, `featControls`, cùng công tắc chung `featApps`):

- *Thanh* (`G6UIBars.m`, UIAppearance): thanh điều hướng / công cụ / thẻ / tìm kiếm thành mặt phẳng sáng (tối: màu than) có nét
  mảnh; tiêu đề Inter SemiBold 18 không bóng chữ; nút trên thanh là viên bo tròn (nút «Xong» màu nhấn, nút lùi có mũi tên vẽ
  sẵn). App tự đặt ảnh nền cho thanh của mình thì kiểu của app thắng. Hình trên nút: iOS 6 tô trắng + bóng chìm qua
  `-[UIImage _bezeledImageWithShadowRed:green:blue:alpha:fillRed:green:blue:alpha:drawShadow:]` — móc hàm này để tô theo màu
  chữ của thanh, bỏ bóng (đặt lại ảnh sau `-[UINavigationButton setImage:]` không ăn: UIKit chạy lại hiệu ứng mỗi lần xếp
  nút). Trong app không có nền động để làm kính thật nên ảnh ở đây vẽ bằng CoreGraphics (vài ảnh nhỏ kéo giãn được), không
  qua lõi.
- *Nút điều khiển* (`G6UIControls.m`, UIAppearance): công tắc xanh lục bỏ chữ «I / O»; thanh trượt rãnh mảnh + núm trắng; nút
  chọn đoạn là rãnh xám bo tròn với viên chọn nổi (bo cả nút bằng lớp vẽ trong `layoutSubviews`); thanh tiến độ; nút tăng
  giảm. Nút chọn đoạn: UIKit chỉ dùng hai mép của ảnh nền ở hai đầu nút, đoạn ở giữa lấy phần giữa ảnh → hai đầu tròn của
  viên chọn phải vẽ vào ảnh vách ngăn «chọn | thường» và «thường | chọn».
- *Bảng nhóm* (`G6UITables.m`, móc lớp riêng): `UIGroupTableViewCellBackground` lấy màu qua `_fillColor`,
  `_sectionBorderColor`, `_separatorColor`, `_topShadowColor`, `_bottomShadowColor` và hình qua
  `_roundedRectBezierPathInRect:…` → ô phẳng, không viền, bo rộng hơn 3 điểm; ảnh ô được UIKit nhớ theo khoá nên đổi kiểu
  phải gọi `+_flushCacheOnNotification:`. Nền bảng (`UITableViewBackgroundView`): ẩn ảnh, đặt màu phẳng.
  **Chế độ tối** (bước đầu của Đợt 4): nền đen, ô màu than; chữ sẫm trong ô nhóm đổi sang màu sáng cùng sắc độ (nhớ màu gốc
  để trả lại) ở `-[UITableViewCell layoutSubviews]`; app đặt lại màu mà không xếp lại ô thì bắt ở `-[UILabel setTextColor:]`
  (chỉ nhãn đã từng đổi); nền đục của nhãn theo `-[UITableViewCell _contentBackgroundColor]`; tiêu đề / chú thích nhóm đổi
  ở `-[UITableView layoutSubviews]`. Riêng app Cài đặt: cột trái (bảng thường trên `PSGradientView`) cũng đổi.
  Nền nhãn phải trùng màu ô ở **cả hai** chế độ: ô nhóm của iOS 6 trên iPad màu 0,97 chứ không trắng tinh, nên ở chế độ sáng
  (ô của Glass 6 trắng 1,0) nền nhãn 0,97 lộ thành dải lệch màu sau chữ — người dùng báo «màu bị lẹm» khi về chế độ sáng.
  `_contentBackgroundColor` và lượt sửa nền nhãn vì thế chạy cả ở chế độ sáng; kiểm bằng ảnh chụp khuếch đại tương phản.
  Hai lỗi đã gặp: `getWhite:alpha:` trả NO với màu hệ RGB (phải thử `getRed:` trước); nhớ «nền gốc» của nhãn ở cột trái lúc
  nó đang mang màu trắng tạm của UIKit thì khi về sáng nhãn thành hộp trắng → không đụng nền nhãn của ô bảng thường.
- *Bảng nổi và bảng chọn* (`G6UIPopover.m`, đi cùng `featBars`; nút của bảng chọn ở `Common/G6Alert.m`, đi cùng `featAlerts`):
  khung bảng nổi thay bằng lớp con của `UIPopoverBackgroundView` (API công khai `popoverBackgroundViewClass`, đặt ngay sau
  `-[UIPopoverController initWithContentViewController:]`; app tự đặt lớp khung thì của app thắng) — tấm phẳng cùng màu thanh,
  bo góc 12, viền mảnh, bóng mềm, mũi tên cùng màu. Bảng chọn (`UIActionSheet`, trên iPad nằm trong bảng nổi) dùng cùng họ nút
  với hộp thoại (`UIAlertButton`, biến `_buttons`) → viên bo tròn; việc phá huỷ chữ đỏ, «Huỷ» chữ thường, còn lại màu nhấn.
- *Biểu tượng trong app Cài đặt* (`G6UISettingsIcons.m`, `featSettingsIcons`): 15 mục hệ thống (mã mục `AIRPLANE_MODE`, `WIFI`,
  `Bluetooth`, `MOBILE_DATA_SETTINGS_ID`, `INTERNET_TETHERING`, `VPN`, `DND_TOP_LEVEL`, `NOTIFICATIONS_ID`, `General`, `Sounds`,
  `Wallpaper`, `PICTURE_FRAME`, `Privacy`, `CASTLE`, `ACCOUNT_SETTINGS`) + mục Glass 6 dùng ô màu với hình trắng do Glass 6 tự vẽ
  bằng CoreGraphics (khung 24×24, không dùng hình của Apple); các mục còn lại (app, tweak) giữ ảnh sẵn có. Tất cả đi qua
  `g6_icon_render` của lõi nên cùng hình bo góc / viền / kiểu biểu tượng với màn hình chính. Gắn ở `-[PSTableCell setIcon:]`
  (+ `refreshCellContentsWithSpecifier:` cho mục không có ảnh).
- *Hình nhỏ trong ô ở chế độ tối* (`G6UITables.m`): ổ khoá, vạch sóng Wi-Fi, dấu chọn của iOS 6 màu đen viền sáng chìm → ảnh
  ≤ 24 điểm mà ≥ 60% điểm ảnh sẫm được đổi thành bản màu sáng (bỏ viền chìm), nhớ theo từng `UIImage`; bắt cả ở
  `-[UIImageView setImage:]` vì danh sách Wi-Fi gán lại ảnh mà không xếp lại ô.
- Đổi sống: kiểu UIAppearance chỉ áp lúc view vào cửa sổ → gỡ – gắn lại view gốc; tiêu đề thanh (`UINavigationItemView`) tự vẽ
  chữ nên phải `setNeedsDisplay` riêng.

**Chi phí lúc mở app** (iPad mini 1, đo bằng nhật ký của chính Glass6UI):

| | Nạp thư viện + lõi + cấu hình | Đặt kiểu lần đầu (thanh / nút / bảng) | Cộng |
| --- | --- | --- | --- |
| Cài đặt (không hộp cát) | 14 ms | 50 ms (24 / 18 / 8) | ~65 ms |
| Ảnh, Bản đồ, Mail (hộp cát) | 12–13 ms | 66–78 ms | ~80–90 ms |

Hai việc đã làm để tới con số này: phông Inter đăng ký lẻ từng kiểu đậm nhạt khi có nơi dùng (app chỉ dùng hai kiểu); nhật ký
chọn tệp ghi **một lần** cho cả tiến trình — trước đó mỗi dòng nhật ký trong app hộp cát đều thử mở tệp ở thư mục bị chặn, mỗi
lần bị chặn tốn cả chục mili giây (hộp cát ghi lại vi phạm), cộng lại ~210 ms.

**Công cụ thử tự bấm** (`G6Debug.m`, chạy trong app nhờ «@<tiến trình>»): `ui` (liệt kê dòng + trạng thái công tắc, nút, nút
chọn đoạn), `select <chữ>`, `toggle <chữ>`, `press <chữ>`, `seg <n>`, `back` — gọi thẳng hành động của nút / hàm chọn dòng của
bảng (không giả sự kiện chạm). Nhờ đó tự thử được màn «Dịch vụ hệ thống» bằng đúng đường bấm của người dùng: «Áp hồ sơ Cân
bằng» → 9 dịch vụ tắt, «Đang dùng: Cân bằng»; gạt Game Center + Twitter → «Tuỳ chỉnh», launchd khớp; «Về Nguyên bản» → bật lại
hết. `g6svc set` giờ xoá trạng thái chờ xác nhận khi máy đã về đúng trạng thái trước lần đổi đầu. Hộp thoại trong app
(«Đặt lại bộ gác») hiện kiểu kính, nút OK tự bấm được.

**Đã tự thử trên iPad mini 1:** Cài đặt (Cài đặt chung, Wi-Fi, Âm thanh, Giới thiệu, Glass 6) ở chế độ sáng và tối, mở mới và
đổi sống tối → sáng → tối → sáng; Ảnh, Bản đồ, Mail, App Store nhận thanh mới; Lịch, Ghi chú, Danh bạ, Nhạc giữ nguyên theo
chính sách; không có báo cáo sập mới sau bản sửa. **Chưa làm / chưa thử:** hình của nút trơn trên thanh công cụ ở chế độ tối còn
xám (đường tô khác, chưa tìm ra), bảng thường (danh sách thư, danh sách tin nhắn…) và ô tự vẽ ở chế độ tối, bảng chọn dạng trượt từ dưới lên (iPhone), bàn phím, app ngoài Apple, nút tròn
`UIRoundedRectButton`, biểu tượng ổ khoá / mũi tên sẫm màu trên ô tối.

## D24. Nút AssistiveTouch của Glass 6 (19/11/2026)

Yêu cầu: viết lại nút AssistiveTouch, tuỳ biến được các nút bên trong như iOS đời sau. Làm thành thành phần `assist`
(`featAssist`, **mặc định tắt** — bật là có thêm một nút nổi), `tweak/SB/G6Assist.m`.

- **Danh mục chức năng nằm ở lõi** (`assist.rs`, lệnh `assist.catalog`): mã, tên, tên ngắn, gán được vào ô / vào thao tác. Bảng
  Cài đặt liệt kê từ đó, SpringBoard thực thi theo mã; cấu hình hỏng / mã lạ rơi về mặc định của ô. Luôn còn một cách mở
  bảng nút (chạm một lần = «không làm gì» mà không thao tác nào mở bảng thì chạm một lần mở bảng).
- **Cấu hình** (`config.assist`): `assistCount` (1–9, mặc định 9), `assistSlot1…9`, `assistMenuTimeout`, `assistTap` / `assistDouble` /
  `assistHold` (mặc định mở bảng / không / không), `assistIdleAlpha`. Màn Cài đặt › Glass 6 › Nút AssistiveTouch
  (`prefs/G6AssistController.m`) dựng động từ danh mục của lõi.
- **Cửa sổ riêng mức 1070** (trên app, màn khoá, Control Center 1055; dưới hộp thoại): `hitTest:` chỉ nhận chạm ở đúng nút, chỗ
  khác lọt xuống dưới; lúc bảng nút mở thì nhận cả màn hình để chạm ra ngoài là đóng. Khung trong xoay theo
  `-[SpringBoard activeInterfaceOrientation]` (đổi theo thông báo xoay). Vị trí nút = mép trái / phải + tung độ theo tỉ lệ,
  nhớ ở `G6_DIR/assist.plist`; thả ra thì hít vào mép gần hơn; nghỉ 3 giây thì mờ.
- **Bảng nút**: tấm kính `hud` (nền chụp màn hình một lần lúc mở, như Control Center), lưới 1 / 2 / 3 / 4 cột theo số ô, hình
  trắng tự vẽ bằng CoreGraphics. Âm lượng và độ sáng bấm liên tiếp được; chức năng khác bấm xong bảng tự đóng. Chỉ nhận cử
  chỉ «chạm hai lần» khi nó có việc (không thì chạm một lần phản hồi ngay). Nút Home lúc bảng mở: đóng bảng.
- **Chức năng → hàm của SpringBoard** (đều tra lúc chạy; đã kiểm có trên iOS 6.1.3):

  | Mã | Gọi |
  | --- | --- |
  | `home`, `switcher`, `lock` | `SBUIController`: `clickedMenuButton`, `activateSwitcher`, `lockFromSource:` |
  | `notifications` | `SBBulletinListController showListViewAnimated:` |
  | `controlcenter` | `G6ControlCenterSetVisible` |
  | `screenshot` | `SBScreenShotter saveScreenshot:` (ẩn cửa sổ nút trước khi chụp) |
  | `volup`, `voldown` | `VolumeControl increaseVolume` / `decreaseVolume` + `cancelVolumeEvent` |
  | `mute`, `rotate` | `SBMediaController setRingerMuted:`; `SBOrientationLockManager lock` / `unlock` |
  | `dark` | ghi `appearance` vào `vn.glass6.plist` + báo như Cài đặt |
  | `brightup`, `brightdown` | `SBBrightnessController setBrightnessLevel:` (±0,1) |
  | `respring` | `SpringBoard relaunchSpringBoard` — làm ngay, không hỏi lại; có sẵn ở ô thứ 7 của bố cục mặc định |
  | `reboot`, `poweroff` | `SpringBoard reboot` / `powerDown` — có hộp hỏi lại |

- **Nút của iOS**: bật nút của Glass 6 thì gọi `_AXSAssistiveTouchSetEnabled(false)` (libAccessibility, tra bằng `dlsym`) và để
  dấu `G6_DIR/assist.sysat`; tắt nút của Glass 6 mà còn dấu thì bật lại nút của hệ thống. Gỡ gói lúc nút của Glass 6 đang bật
  thì nút của hệ thống vẫn tắt — bật lại trong Cài đặt chung › Trợ năng.

**Đã tự thử trên iPad mini 1** (bật bằng công tắc trong Cài đặt qua công cụ tự bấm): nút của hệ thống tự tắt, nút mới hiện; bảng
6 ô và 8 ô; bấm ô «Màn hình chính»; Thông báo, Control Center, Đa nhiệm mở đúng; tăng / giảm âm (bảng âm lượng 3 → 2 vạch),
khoá xoay 0 → 1 → 0, độ sáng 0,80 → 0,90 → 0,80, sáng ↔ tối hai lần; «Khởi động lại SpringBoard» hiện hộp hỏi lại (bấm
Huỷ); dời nút sang mép trái + giả xoay dọc; khoá màn hình (nút vẫn hiện trên màn khoá); đổi «Số nút» và «Chạm hai lần» qua
màn Cài đặt rồi trả lại. Bấm ô «Respring» trong bảng: 1 giây sau Glass 6 đã nạp lại vào SpringBoard mới, 3 giây sau sẵn sàng, nút ở nguyên chỗ.
**Chưa thử:** kéo nút bằng ngón tay thật, chạm / chạm hai lần / nhấn giữ thật, chụp màn hình (sẽ
thêm ảnh vào thư viện), bật / tắt tiếng (đã gọi, chưa đọc lại trạng thái), khởi động lại / tắt máy thật, nút khi bàn phím hiện.

**Bổ sung theo góp ý sau khi dùng thử (cùng ngày):**

- *Bảng nút luôn là ô vuông 3×3* như AssistiveTouch của iOS đời sau; tối đa 9 ô (`MAX_SLOTS`). Ít hơn 9 ô thì xếp đối xứng quanh
  tâm theo bảng `G6AssistCells` (8 ô: chừa ô giữa; 4 ô: chữ thập; 1 ô: chính giữa). Mặc định 9 ô: thông báo, Control Center,
  màn hình chính / đa nhiệm, khoá, chụp màn hình / respring, khoá xoay, khởi động lại.
- *Đổi mặc định của một ô là đổi luôn ô đó trên máy người chưa tự chọn ô ấy* — lần thêm «khoá xoay» em đổi mặc định ô 6 nên ô
  6 của người dùng (đang là «chụp màn hình» theo mặc định cũ) thành trùng với ô khoá xoay họ đã tự đặt. Từ đó: thêm chức năng
  mặc định thì thêm vào ô mới ở cuối, không đổi ô cũ.
- *Tự ẩn bảng nút* (`assistMenuTimeout`, mặc định 5 giây, 0 = không): đồng hồ đặt lại mỗi lần chạm vào ô.
- *Ô có trạng thái* (khoá xoay, tắt tiếng, sáng / tối): nhãn là việc lần bấm tới sẽ làm («Khoá xoay» ↔ «Mở khoá xoay»), ô có đĩa
  xanh khi đang bật — đọc trạng thái thật của máy mỗi lần mở bảng.
- **Lỗi khoá xoay:** `-[SBOrientationLockManager lock]` khoá theo hướng của cảm biến; máy nằm phẳng trên bàn (hướng «ngửa mặt»)
  thì không khoá được gì, bấm bao nhiêu lần cũng «y nguyên» (người dùng báo). Lần tự thử trước đó máy đang được giả hướng ngang
  nên không lộ. Sửa: `G6SetRotationLocked` gọi `lock:` với `activeInterfaceOrientation` — dùng chung cho Control Center.
- *Control Center* (D20): vuốt lên ở bất cứ đâu là đóng (`UISwipeGestureRecognizer` trên khung xoay); tự ẩn sau `ccTimeout` giây
  không ai đụng tới (mặc định 8, 0 = không) — chạm vào bảng hoặc đang kéo thanh trượt thì tính lại từ đầu.
- Đã kiểm bằng nhật ký trên máy: «bảng nút tự ẩn (hết thời gian chờ)», «control center: tự ẩn (hết thời gian chờ)»; gọi thẳng
  chức năng khoá xoay lúc máy nằm phẳng: 0 → 1 → 0 → 1 → 0. **Chưa kiểm:** vuốt lên bằng ngón tay thật (không giả được cử chỉ);
  bấm ô khoá xoay bằng tay (lúc tự thử người dùng cũng đang bấm nên kết quả lẫn vào nhau).

**Tắt dịch vụ có nhẹ máy không** (đo ngày 19/11/2026 lúc máy ở trạng thái nguyên bản, 51 tiến trình, tổng RAM thường trú ~200 MB):
trong 18 tiến trình nền của 15 dịch vụ chỉ `aggregated` đang chạy, 0,6 MB (0,3%); số còn lại chỉ bật khi có việc gọi tới.
Tốn RAM thật là app nền (Telegram 20 MB, Mail 9, Roza 8,6, GramMini 7) và các tiến trình hệ thống không tắt được
(SpringBoard 20, mediaserverd 10,6, backboardd 9,5). Lợi của việc tắt dịch vụ là hết gom / gửi chẩn đoán và hết các lần
bật lại vô ích (`ubd`), không phải máy nhanh lên thấy rõ — bảng Cài đặt không được hứa điều đó.

## D25. Ẩn Quầy báo; chế độ tối cho bảng thường (19/11/2026)

**Ẩn Quầy báo** (`hideNewsstand`, mặc định tắt, `tweak/SB/G6Newsstand.m`): iOS 6 không cho xoá hay cho Quầy báo vào thư mục.
SpringBoard hỏi `-[SBIconModel isIconVisible:]` cho từng biểu tượng → trả NO cho `SBNewsstandIcon`. Đổi lúc đang chạy: gọi
`-[SBIconModel _postIconVisibilityChangedNotificationShowing:hiding:]` (đúng thông báo SpringBoard dùng khi ẩn / hiện app theo
hạn chế) với biểu tượng `newsstandIcon` → `SBIconController` gỡ / thêm và dồn biểu tượng ngay, không cần respring. Hàm móc gắn
sớm (cùng lúc với biểu tượng) để lượt xếp đầu tiên đã không có Quầy báo. Hiện lại thì Quầy báo về ô trống đầu tiên.
Đã thử: gạt công tắc trong Cài đặt → biểu tượng biến mất, hàng dồn lại.

**Bảng thường (không chia nhóm) ở chế độ tối** (`G6UITables.m`, cùng công tắc `featTables`):

- Bảng nền sáng đục → nền đen, nét ngăn sáng mờ; chữ sẫm trong ô đổi sáng (cùng bộ máy với ô nhóm). Bảng trong suốt (đè lên nền
  riêng của app) hay có màu riêng không bị đụng.
- **Chỉ tô khi mọi ô chỉ gồm thành phần chuẩn của UIKit.** Ô có view của riêng app (lớp không thuộc gói UIKit) hoặc lớp ô tự
  ghi đè `drawRect:` là ô tự vẽ chữ — Glass 6 không đổi màu được. Gặp một ô như vậy thì cả bảng được trả về sáng và đánh dấu
  «bỏ qua»: sáng đều còn hơn nền đen chữ đen. (Danh sách thư, danh sách tin nhắn rơi vào loại này cho tới khi có bản riêng.)
- iOS 6 **tự lan màu nền của bảng thường xuống ô và nền nhãn của ô** → không đặt màu nền ô. Lần đầu em «nhớ màu gốc của ô rồi
  đặt đen»: màu nhớ được đã là màu đen vừa lan xuống, lúc trả lại thành tô đen lần nữa (lần ra bằng nhật ký tạm).
- Việc «ô này có đang được tô tối không» gom về một hàm (`G6ApplyCell`): ô nhóm / ô bảng thường đạt chuẩn / ô cột trái của Cài
  đặt (bảng trong suốt). Chữ, nền nhãn, hình nhỏ chỉ đổi theo quyết định đó — không còn tự suy từ «máy đang ở chế độ tối».
- Lỗi đã gặp khi trả màu chữ: gán lại `textColor` đi qua chính hàm móc `setTextColor:` của Glass 6; nhãn còn dấu «màu gốc» + máy
  đang tối → hàm móc làm sáng màu vừa trả (chữ trắng trên ô vừa về trắng). Phải xoá dấu trước khi gán.
- Thử bằng bảng trong cửa sổ trưng bày (`gallery 1`: toàn ô chuẩn → tối; `gallery 3`: có một ô tự vẽ → cả bảng giữ sáng, chữ
  sẫm) và quét điểm ảnh lại app Cài đặt ở cả sáng lẫn tối. **Chưa thử** trên bảng thật của app khác; dấu chọn màu xanh sẫm của
  iOS 6 trên nền đen còn khó thấy; thanh tiêu đề nhóm của bảng thường chưa đổi.

## D26. Dải hiệu suất trên màn hình chính; thanh trạng thái kiểu iPadOS (19/11/2026)

Anh yêu cầu: hiện hiệu suất hệ thống (CPU, RAM, đĩa, mạng) ngay trên màn hình chính; rồi sau khi thấy bản đầu: ẩn chữ «Không có
SIM», đưa mặt trăng + giờ sang chỗ đó, đẩy dải hiệu suất lên trên cùng; tia sét lúc sạc pin màu xanh lá.

**Dải hiệu suất** (`featPerf`, mặc định tắt; `tweak/SB/G6Perf.m`, lõi `perf.rs`):

- Phân vai: vỏ chỉ đọc số đếm thô của nhân — `host_statistics` (tích tắc CPU, số trang nhớ), `statfs("/private/var")`,
  `getifaddrs` (byte qua `en*` + `pdp_ip*`); lõi (`perf.reading`) nhận hai mẫu liên tiếp, tính phần trăm / tốc độ và dựng sẵn
  chuỗi («23%», «148 MB», «51,0 GB», «12 KB/s», «1,2 MB/s»). Số đếm mạng 32 bit quay vòng ở 4 GB, số đếm bị đặt lại khi tắt /
  bật mạng, mẫu đầu tiên, đồng hồ lùi: đều có bài thử trên PC.
- RAM: con số là phần **còn dùng được** (trang trống + trang không hoạt động); thanh = tổng − còn dùng được. Bản đầu lấy thanh
  = trang hoạt động + trang ghim: lệch con số tới 13% (65 MB nhân và bộ xử lý hình giữ riêng không nằm trong bảng đếm trang)
  → thanh một đằng, số một nẻo. Đĩa: phân vùng dữ liệu, con số là phần còn trống.
- Dải là một view không nhận chạm gắn vào `SBIconContentView` (đứng yên khi lật trang); kính bề mặt `capsule` trên nền hình
  nền mờ dùng chung, dựng lại khi đổi khung / sáng-tối / hình nền / hướng máy. Chữ vẽ một lượt bằng `drawRect:`; mỗi số có ô
  rộng cố định nên số đổi không xô lệch các mục khác; chỉ vẽ lại khi thứ hiện trên màn hình thật sự đổi.
- **Chỉ đo khi có người nhìn**: dải đang trong cửa sổ (SpringBoard gỡ màn hình chính khỏi cửa sổ lúc mở app), máy mở khoá, màn
  hình sáng — ngoài ra không có đồng hồ hẹn nào chạy. Về lại màn hình chính: lấy mốc mới, 0,7 giây sau có số (CPU / mạng tính
  trên khoảng từ mốc đó chứ không phải từ lần đo trước khi rời đi). Đồng hồ hẹn ở chế độ mặc định của vòng lặp: lúc ngón tay
  đang kéo trang thì nghỉ. Nhịp đo `perfInterval` 1–10 giây, mặc định 2.
- Sang trang Tìm kiếm: mờ dần rồi ẩn (móc `scrollViewDidScroll:`, chỉ đụng view khi độ hiện đổi). Mở thư mục: ẩn (iOS 6 xẻ đôi
  màn hình chính, dải đứng yên đè lên trông sai).
- **Hai chỗ đặt** (`perfPosition`): *trên cùng* (mặc định, theo ý anh) = giữa thanh trạng thái, cao 20 điểm — dải nằm trong màn
  hình chính, dưới cửa sổ thanh trạng thái (thanh của Glass 6 trong suốt), nên chỉ có ở màn hình chính. Chỗ trống giữa hai cụm
  mục của thanh trạng thái đo lúc chạy (`G6StatusBarCenterFree`), nghe `G6StatusBarDidReflowNotification` để đo lại khi có
  mục thêm / bớt: đủ rộng → bản đầy đủ (564 điểm); không đủ → bản gọn bỏ ba thanh mức (444 điểm — máy đứng rơi vào đây); vẫn
  không đủ, hoặc giờ không nằm bên trái → *dưới thanh trạng thái* (cao 28 điểm, lệch lên trên trong dải trống trước hàng biểu
  tượng đầu — đặt chính giữa thì trông như sát biểu tượng, anh bảo nhích lên).
- Chi phí đo trên máy: 1,9 ms mỗi lần đo (đọc số đếm + một lệnh JSON sang lõi). 30 giây ở màn hình chính, nhịp 2 giây:
  SpringBoard 0,4%, backboardd 2,3% CPU — không có dải là 0,1% + 1,5% (D13). Lần đo này anh đang dùng máy nên coi là mức trần.
- Tách `tweak/SB/G6Screen.m`: năm hàm móc `SBAwayController` (khoá / mở khoá / tắt / sáng màn hình) trước nằm trong
  `G6Clock.m`, nay phát `G6ScreenStateDidChangeNotification` cho cả đồng hồ sống lẫn dải hiệu suất.

**Thanh trạng thái** (`tweak/SB/G6StatusBar.m` cho SpringBoard, `tweak/UI/G6UIStatusBar.m` cho app, phần chung ở
`tweak/Common/G6StatusItems.m`; cùng công tắc `featStatusBar`):

- **Giờ + mặt trăng sang trái** (`statusTimeLeft`, mặc định bật — iPadOS đặt giờ ở góc trái): mỗi loại mục của thanh trạng thái
  (`UIStatusBarItem`) tự khai thuộc vùng nào (trái / phải / giữa) và đứng thứ mấy. Móc `+itemType:appearsInRegion:`,
  `-appearsInRegion:`, `-appearsOnLeft`, `-appearsOnRight`, `-compareLeftOrder:`: hai loại Giờ và Không-làm-phiền trả lời «vùng
  trái, đứng đầu». Loại mục và số vùng **tra lúc chạy** (theo lớp view của từng loại, theo vùng mà mục «dịch vụ» khai) chứ không
  viết cứng; đo được trên máy: giờ 0, trăng 1, dịch vụ 4, vùng trái 0. Gắn không đủ năm hàm thì coi như không có.
- Đổi lúc đang chạy: `-[UIStatusBar forceUpdateData:]` là đủ để thanh hỏi lại vùng; view cũ ở vùng cũ không bị gỡ mà chuyển
  sang ẩn (`isVisible` = NO) — mọi phép đo chỗ trống phải bỏ qua view ẩn. Sau đó vẫn phải cho **từng mục vẽ lại**: bản đầu
  dừng ngay sau `forceUpdateData:` nên hình pin mới chỉ hiện khi phần trăm pin đổi (dò ra bằng nhật ký tạm trong hàm vẽ pin).
- **Hình pin** (`statusBattery`, mặc định bật): `-[UIStatusBarBatteryItemView contentsImageForStyle:]` → hình tự vẽ (viền mờ,
  ruột theo `_capacity`, đỏ khi ≤ 20% và không cắm sạc); `_state` ≠ 0 (đang nạp hoặc đã đầy) thì thêm **tia sét xanh lá** bên
  phải. Không tô xanh ngay trên tia sét cũ: tia sét của iOS 6 là hình khoét giữa ruột pin trắng, xanh lá trên trắng thì chìm —
  đưa ra cạnh pin như iOS 7 trở đi. Màn hình 1x: nét mảnh dưới 2 điểm ảnh bị nhoè nên tia sét vẽ trong khung 8×13.
- **Ẩn «Không có SIM»** (`statusHideNoSIM`, mặc định bật như `lockHideNoSIM`): làm ở nguồn dữ liệu. `SBStatusBarDataManager`
  của SpringBoard phát trạng thái cho thanh của mọi app; nó bật mục «dịch vụ» qua `-setStatusBarItem:enabled:` → móc hàm đó,
  khi `-[SBTelephonyManager SIMStatus]` là `kCTSIMSupportSIMStatusNotInserted` thì đổi «bật» thành «tắt». Vì vậy chữ mất ở
  **mọi app**, không riêng SpringBoard. Có SIM thì tên nhà mạng hiện như cũ; các trạng thái SIM khác (khoá, lỗi) không đụng.
- Đã thử trong app: Cài đặt và Đồng hồ mở mới — các mục nằm đúng chỗ như ở màn hình chính (trăng 4–17, giờ 19–56, Wi-Fi
  62–82, pin có tia sét 986–1021), không sập (số tệp báo lỗi không tăng).
- Đã thử trên máy: ba công tắc gạt sống trong Cài đặt (giờ về giữa → dải tự xuống dưới thanh trạng thái, bật lại → lên trên
  cùng; pin cũ ↔ mới; «Không có SIM» hiện ↔ ẩn); máy đứng / ngang; sáng / tối; mở app → dừng đo, về → đo lại; trang Tìm kiếm
  và thư mục → dải ẩn. **Chưa thử**: máy có SIM; pin ≤ 20% (ruột đỏ); trạng thái «đã đầy» (`_state` 2); nhiều biểu tượng
  trạng thái cùng lúc (báo thức, Bluetooth, định vị) ở máy đứng — khi đó dải phải tự xuống dưới.
- **Trong app**: thanh trạng thái của iOS 6 do từng tiến trình tự vẽ (SpringBoard chỉ phát dữ liệu) — chỉ đổi ở SpringBoard
  thì cứ mở app là giờ «nhảy» từ góc trái về giữa, pin về kiểu cũ. Phần đổi vùng / vẽ pin / phông vì vậy nằm ở mã dùng chung
  và Glass6UI gắn nó vào mọi app trong phạm vi của mình (kể cả app tự vẽ giao diện: thanh trạng thái là của hệ thống). Nền
  của thanh trong app (dải đen) giữ nguyên; màu nét pin lấy từ `-textColorForStyle:` của chính mục pin nên đúng trên cả hai nền.
- **Gắn sớm, tra muộn.** Trong app, thanh trạng thái được tạo ngay trong `UIApplicationMain`, TRƯỚC `-[UIApplication
  setDelegate:]` (chỗ Glass6UI đặt kiểu). Bản đầu gắn ở đó: thanh đã dựng xong kiểu gốc, phải xếp và vẽ lại lần nữa — đo trên
  app Cài đặt, bước đặt kiểu lúc mở app từ 50 ms lên 73 ms. Sửa: `G6StatusItemsInstall` chỉ làm việc của runtime (đổi hàm) nên
  gọi được ngay từ hàm khởi tạo của thư viện; việc tra loại mục (phải gọi vào UIKit — điều cấm ở hàm khởi tạo, xem D23) hoãn
  tới lần đầu một hàm thay thế được gọi, tức là lúc chính UIKit đang dựng thanh. Đo lại: Cài đặt 47 ms, Đồng hồ 62 ms, không
  còn view giờ ẩn bỏ lại ở giữa thanh.
- Giới hạn: app ngoài phạm vi của Glass6UI (app không phải của Apple, cho tới khi có kênh cấu hình cho chúng) vẫn vẽ thanh
  kiểu cũ — giờ ở giữa, pin cũ; riêng «Không có SIM» thì đã ẩn ở mọi app. Gói xung đột về thanh trạng thái: SpringBoard tự tắt
  thành phần `status_bar` của mình khi quét thấy, nhưng kết quả quét chưa được báo cho app.

## D27. Chế độ tối trong app: phần còn sót của các thành phần chuẩn (19/11/2026)

Soi bằng cửa sổ trưng bày (`gallery`) ở chế độ tối thấy sáu chỗ còn sai; sửa từng chỗ ở đúng thành phần của nó. Tất cả đều
trả lại nguyên trạng khi về chế độ sáng hoặc tắt thành phần.

- **Dấu chọn và mũi tên cuối dòng** (`G6UITables.m`): UIKit đặt phụ kiện chuẩn của ô trong một `UIButton` không nhận chạm, con
  trực tiếp của ô; phần «hình nhỏ» cố ý không vào nút nên hai hình này bị bỏ sót — dấu chọn xanh sẫm (50, 79, 133), mũi tên
  trên ô đen thì mất hẳn. Đổi ảnh trạng thái thường của nút: hình có màu → xanh sáng, hình xám / đen → trắng mờ 42%, viền
  sáng chìm bỏ. Nút «chi tiết» (nhận chạm) không đụng. Áp cho mọi ô đang được Glass 6 tô tối (ô nhóm, ô bảng thường, cột trái
  Cài đặt).
- **Nút bo góc** (`UIRoundedRectButton`): nền của nó chính là một `UIGroupTableViewCellBackground` nên đã thành màu than nhờ
  các hàm của bảng nhóm, còn chữ vẫn xanh sẫm mặc định (0,22 – 0,33 – 0,53). Chữ đang đúng màu mặc định thì đổi sang xanh
  sáng; app tự đặt màu khác thì để nguyên.
- **Ô nhập bo góc** (`G6UIControls.m`): nền là `UITextFieldRoundedRectBackgroundView` gồm ba `UIImageView` (đầu trái 8 điểm,
  khúc giữa, đầu phải). Thay ba ảnh bằng ba mảnh của một viên bo góc màu than viền mờ (móc `-layoutSubviews` và
  `-_updateImages`); chữ đang sẫm thì đổi sáng. Trả lại: gọi hàm gốc `-_updateImages` cho UIKit nạp lại ảnh của nó.
- **Hình của nút trơn trên thanh công cụ** (`G6UIBars.m`; mục «còn sót» từ D23): hàm `_flatImageWithWhite:alpha:` móc trước đây
  không phải đường các hình này đi. `UISwappableImageView` tự dựng ảnh hiển thị trong `-updateImageIfNeededWithTintColor:`
  (xám xanh 108, 115, 122 có nét chìm). Sau mỗi lần nó dựng xong, tô lại ảnh đang hiện bằng màu chữ của thanh (cả hai chế
  độ, cho cùng màu với hình trên nút có viền); gán bằng hàm của `UIImageView` vì `-[UISwappableImageView setImage:]` coi ảnh
  nhận vào là hình gốc mới. Ảnh lúc đang bấm để nguyên. Ảnh đã tô mang dấu chế độ để biết khi nào tô lại.
- **Công tắc đang tắt**: rãnh trắng chói → `tintColor` xám than qua UIAppearance. Màu rãnh kéo núm xám theo (thấy trên ảnh
  chụp) nên đặt thêm `thumbTintColor` trắng.
- **Thanh tiêu đề nhóm của bảng thường**: `UITableViewHeaderFooterView` = nền `_UITableViewHeaderFooterViewBackground` (dải xám
  xanh nhạt) + nhãn chữ trắng có bóng; trên bảng đã tô đen thì chói. Thử `tintColor` có sẵn của lớp này: iOS 6 dựng từ màu đó
  một dải **bóng chuyển màu** (mép dưới sáng lên gần xám vừa), không ra mặt phẳng → ẩn nền gốc, đặt một view phẳng màu than
  của Glass 6 xuống dưới cùng; chữ xám sáng không bóng. Chỉ với bảng đang được tô tối; hết tô thì gỡ view, hiện lại nền gốc.
- **Đổi sống sáng ↔ tối** (thử thì lộ ra ba lỗi của chính đợt này và của D23):
  - hình trên nút CÓ VIỀN của thanh điều hướng (dấu cộng, chia sẻ) được tô một lần lúc nút sinh ra; đổi chế độ thì vẫn màu cũ —
    tối → sáng là hình trắng trên viên nút sáng, mất hút. Bắt nút xếp lại không làm UIKit tô lại → lúc làm mới, tô lại chính
    ảnh trạng thái thường của nút (ảnh chỉ còn hình + độ đục vì bóng chìm đã bỏ từ lần tô đầu);
  - chữ nút bo góc chỉ đổi / trả ở lượt xếp của nút → lúc làm mới phải bắt nút xếp lại;
  - tô lại bằng màu chữ CÓ độ đục (0,96 / 0,88) thì mỗi lần đổi chế độ hình nhạt thêm (độ đục nhân dồn: sau ba lần còn
    ~0,81) → luôn tô bằng màu đặc, độ đục để nguyên như ảnh đang có.
- Đã thử bằng cửa sổ trưng bày trong app Cài đặt (ảnh chụp): cả sáu mục ở chế độ tối; vòng tối → sáng → tối → sáng → tối lúc
  cửa sổ đang mở — mọi mục đổi và trả đúng, điểm ảnh sáng nhất của hình trên thanh sau bốn lần đổi vẫn (255, 255, 255) /
  (248, 248, 248); số tệp báo lỗi không tăng. **Chưa thử**: bảng thật của app khác, ô nhập trong hộp thoại, nút có viền mang
  hình trên thanh công cụ (cửa sổ trưng bày chưa có loại này).
- Còn lại của chế độ tối: bàn phím (iPad iOS 6 không có kiểu bàn phím tối — phải tự vẽ phím, việc lớn), bảng có ô tự vẽ
  (danh sách thư / tin nhắn) theo từng app, `UITextView` nền trắng của từng app.

## D28. Đợt 3 (bắt đầu): vẽ lại riêng từng app của Apple — app Đồng hồ (19/11/2026)

**Khung chung** (`featAppSkins`, mặc định bật; `tweak/UI/G6UIAppSkins.m`): kiểu chung của Glass6UI đi qua UIAppearance nên chỉ
tới được chỗ app dùng thành phần chuẩn và không tự đặt ảnh. Chỗ app tự vẽ bằng ảnh riêng phải xử theo từng app: mỗi app một
tệp `G6UIApp<Tên>.m`, chọn theo mã gói, gọi sau các hàm Apply của thanh và nút điều khiển (dùng lại mặt thanh
`G6UIBarSurfaceImage` và kiểu nút chọn đoạn `G6UIControlsStyleSegmented` hiện hành). Nguyên tắc: làm ở lượt xếp của chính view
đó, cất ảnh / kiểu gốc trên view để trả lại khi tắt; không sửa ảnh trong gói app, không móc việc nạp ảnh.

**Khảo sát các app không chứa dữ liệu riêng** (ảnh chụp + cây view, chế độ tối):

- *Đồng hồ* (iPad): vốn đã phẳng và tối; thanh điều hướng là thanh chuẩn nên đã theo Glass 6. Lệch tông: thanh thẻ dưới cùng —
  dải kim loại sáng (`navigation_bg`) + `ClockSegmentedControl` (lớp con của UISegmentedControl tự đặt ảnh nút bạc, tự vẽ
  đoạn đang chọn bằng một UIImageView riêng, tự đặt ba vạch ngăn sáng). → đã vẽ lại (dưới).
- *Video*: thư viện trống thì chỉ có nền tối + thanh chuẩn — không có gì phải sửa; màn hình có phim chưa xem được.
- *Nhạc*: gần như toàn bộ là hình riêng (`MusicPlaybackControlsView`, `MusicGridView`, viền gỗ), nền sáng kể cả ở chế độ
  tối. Thư viện trên máy thử trống nên không xem được lưới album / danh sách bài — **gác lại** cho tới khi có nhạc để soi.
- Chưa mở: Danh bạ, Ghi chú, Lịch, Lời nhắc, Ảnh, Mail, Tin nhắn (dữ liệu riêng của anh — chờ anh cho phép), Game Center (màn
  đăng nhập có thể hiện Apple ID), Camera / Photo Booth (hình từ máy ảnh).

**App Đồng hồ** (`tweak/UI/G6UIAppClock.m`), móc `-layoutSubviews` và `-setSelectedSegmentIndex:` của `ClockSegmentedControl`:

- nút chọn thẻ nhận thẳng kiểu nút chọn đoạn của Glass 6 (ảnh nền, vách ngăn, kiểu chữ đặt trên chính nút đó — bản gốc cất
  lại); view «đoạn đang chọn» và ba vạch ngăn của app ẩn đi — đoạn đang chọn do UIKit vẽ bằng ảnh trạng thái «đang chọn»;
- dải nền (UIImageView anh em phủ kín chỗ nút nằm) đổi sang mặt thanh phẳng của Glass 6, nét mảnh ở mép trên;
- theo chế độ sáng / tối như các thanh khác; ở chế độ sáng phần nội dung vẫn tông tối sẵn có của app (bản đồ, lưới, mặt bấm
  giờ) — chấp nhận.
- Đã thử trên máy: bốn thẻ, đổi thẻ, tối → sáng → tối lúc app đang mở; không sập. Bước đặt kiểu lúc mở app Đồng hồ 78 ms
  (trước khi có phần này 62 ms — chênh do lần đầu vẽ ảnh nút chọn đoạn + mặt thanh).
- Chưa làm trong app Đồng hồ: bánh xe chọn giờ (UIDatePicker bạc), nền sáng của dải đồng hồ ở thẻ Giờ quốc tế và thẻ Báo thức.

## D29. Bánh xe chọn (UIPickerView, UIDatePicker) (19/11/2026)

Thành phần chuẩn cuối cùng còn nguyên kiểu iOS 6: khung xanh than, bánh xe bạc bóng, thanh chọn kính xanh — ở chế độ tối thì
chói. Thuộc thành phần «controls» (`tweak/UI/G6UIPickers.m`).

- Cấu trúc (tra bằng `gallery 4`): `UIPickerView` = mặt nền (UIView) + cho mỗi cột {vạch ngăn `_UIOnePartImageView`, mặt bánh
  xe `_UIPickerWheelView`, thanh chọn `_UIPickerViewSelectionBar`, bảng `UIPickerTableView`, hai ảnh bóng} + khung
  `_UIPickerViewTopFrame` phủ trên cùng. `UIDatePicker` bọc một `_UIDatePickerView` là lớp con của `UIPickerView`.
- Kiểu mới (như iPadOS): mặt phẳng một màu (trắng / than), không khung, không bóng; dòng đang chọn nằm trên một viên bo góc
  mờ đặt ngay dưới bảng của cột; hai dải mờ dần vào mặt nền ở mép trên / dưới; chữ theo chế độ. Mọi view của iOS 6 chỉ bị
  ẨN (có dấu «do Glass 6 ẩn») chứ không gỡ → tắt thành phần là hiện lại nguyên.
- **Chữ của các dòng đổi ở lượt xếp của `UIPickerTableView`**, không đổi một lần rồi thôi: dòng được dùng lại liên tục khi
  cuộn và UIDatePicker đặt lại màu mỗi lần (dòng «Hôm nay» xanh, thứ trong tuần xám). Mỗi nhãn nhớ «màu Glass 6 đã đặt»; màu
  đang có khác màu đó tức UIKit vừa đặt màu mới → lấy làm màu gốc và đổi lại: đen / xám sẫm → màu chữ chính, xám vừa → màu
  chữ phụ, chữ có màu → xanh sáng ở chế độ tối.
- Hai trường hợp chừa ra, đều vì không đoán được thứ nằm ngoài tầm của mình:
  - bánh xe mà app tự cấp view cho từng dòng (`viewForRow:` — không phải nhãn chuẩn hay view của UIDatePicker): chữ app tự
    vẽ, Glass 6 không đổi màu được → bánh xe đó **luôn dùng mặt sáng**, kể cả ở chế độ tối. Phát hiện lúc gặp dòng đầu tiên
    như vậy, đổi ở lượt xếp kế;
  - bánh xe không còn khung / mặt nền của iOS 6 (app đã tự đặt nó lên hình riêng — thẻ Hẹn giờ của app Đồng hồ): để nguyên.
- Lỗi lộ ra khi thử đổi sáng → tối trong app Cài đặt: hai dải mờ dần bị tô đặc. Thủ phạm là đoạn làm mới cột trái của Cài
  đặt trong `G6UITables.m` — nó nhận **mọi** view có lớp vẽ `CAGradientLayer` là «dải màu của cột trái» rồi tô dải than đặc
  lên. Sửa: chỉ nhận đúng lớp `PSGradientView`.
- Đã thử bằng `gallery 4` trong app Cài đặt (ảnh chụp): bánh xe chuẩn hai cột, chọn ngày giờ, bánh xe có dòng app tự vẽ; tối →
  sáng → tối lúc đang mở; Cài đặt đứng yên 0,1% CPU (không có vòng xếp lại thừa); không sập. Sau đó đã thử trong app thật:
  bánh xe ngày giờ trong bảng nổi «Bắt đầu & Kết thúc» của Lịch, cả hai chế độ (D32). **Chưa thử**: lúc đang quay nhanh (độ
  mượt).

## D30. Bàn phím tối bằng bộ lọc màu của CoreAnimation (19/11/2026)

iPad iOS 6 chỉ có một bàn phím sáng (kiểu «cảnh báo» tối màu chỉ có trên iPhone). Phím do UIKit tự vẽ thành ảnh từ dữ liệu bố
cục — vẽ lại từng phím là viết lại cả bộ vẽ bàn phím.

- **Phát hiện**: máy có lớp riêng `CAFilter` với các loại `multiplyColor, multiplyGradient, colorAdd, colorSubtract,
  colorMonochrome, colorMatrix, colorHueRotate, colorSaturate, luminanceToAlpha, gaussianBlur, lanczosResize, pageCurl`
  (`+filterTypes`), và trình dựng hình của iOS 6 **có áp** bộ lọc màu gắn vào `layer.filters`: thử bằng lệnh `cafilter` với
  `colorHueRotate` góc π trên cửa sổ trưng bày — nút xanh thành cam, công tắc xanh lá thành hồng. (Loại «colorInvert» không
  có. `gaussianBlur` chưa thử; dù chạy được nó cũng chỉ làm mờ nội dung của chính lớp đó, không phải thứ nằm sau — không
  thay được lớp nền mờ sống mà máy này thiếu, xem D2.)
- **Cách làm** (`tweak/Common/G6Keyboard.m`, thành phần `keyboard`, khoá `featKeyboard`, mặc định bật): một bộ lọc
  `colorMatrix` gắn vào lớp vẽ của `UIKeyboardLayoutStar` (view bố cục phím: nền + các phím) lúc nó vào cửa sổ, khi đang ở
  chế độ tối. Ma trận «đảo sáng tối, giữ sắc màu» = đảo màu rồi xoay sắc 180°, gộp lại: `màu mới = 1 + màu − (2/3)(đỏ + lục
  + lam)` — trắng ↔ đen, xám sáng ↔ xám tối, phím xanh vẫn xanh. Thêm bước tăng tương phản (× 1,4 − 0,45) vì đảo đơn thuần
  thì viền bàn phím (xám vừa) vẫn xám vừa: sau bước này chữ trên phím ~0,95, viền ~0,25, mặt phím đen.
- Hằng số của ma trận đặt ở **cột alpha** chứ không ở cột hằng số: điểm ảnh trong suốt (khe giữa hai nửa bàn phím tách đôi)
  vẫn trong suốt thay vì thành xám.
- Gắn vào `UIKeyboardLayoutStar` chứ không vào `UIPeripheralHostView`: view sau chứa cả thanh phụ kiện của app nằm trên bàn
  phím — thứ đó không được đảo màu.
- Dùng chung cho SpringBoard (ô Tìm kiếm) và các app trong phạm vi của Glass6UI; app khác vẫn bàn phím sáng.
- Kèm theo: bước làm mới giao diện lúc đổi sáng ↔ tối (`G6UIRefreshAppearance` gỡ – gắn lại view gốc) làm ô đang gõ mất con
  trỏ, bàn phím thu xuống → nay nhớ view đang giữ con trỏ và trả lại sau khi gắn.
- Đã thử (cửa sổ trưng bày trong Cài đặt, ô nhập đang có con trỏ): tối → sáng → tối, bàn phím đổi theo và không thu xuống;
  không sập. Bàn phím trong SpringBoard (trang Tìm kiếm) đã xem ở D33: tối đúng. **Chưa thử**: bàn phím tách đôi / tháo rời,
  bàn phím số, thanh gợi ý chữ, độ mượt khi gõ nhanh (bộ lọc chạy ở trình dựng hình mỗi lần bàn phím vẽ lại).

## D31. Mờ sống LÀM ĐƯỢC trong phạm vi một cửa sổ — nhưng đắt (bổ sung cho D2, 19/11/2026)

D2 chốt «kính không mờ thời gian thực» vì iOS 6.1.3 thiếu `CABackdropLayer`. Thử tiếp sau D30 (lệnh thử `cafilter`):

- `layer.filters = [gaussianBlur]`: trình dựng hình làm mờ **nội dung của chính lớp đó** (cả cửa sổ trưng bày mờ đi). Chạy.
- `layer.backgroundFilters = [gaussianBlur]` trên một ô gần trong suốt: thứ **nằm sau** ô bị làm mờ — nhưng lan ra cả cửa sổ,
  không gói trong ô. Thêm `masksToBounds = YES` + `cornerRadius`: phần mờ được **cắt đúng theo khung bo góc** của ô. Tức là
  có nền mờ sống thật, bo góc được, ngay trên iOS 6. `colorHueRotate` đặt ở `backgroundFilters` cũng chạy.
- **Giới hạn 1 — chỉ trong cùng một cửa sổ.** Ô đặt trong một UIWindow riêng (của SpringBoard) nằm trên app, hoặc trên chính
  màn hình chính (cửa sổ khác của cùng tiến trình): thứ bên dưới KHÔNG mờ. Vậy không dùng được cho các tấm kính nằm ở cửa sổ
  riêng đè lên app: Control Center, Trung tâm thông báo, băng thông báo, bảng âm lượng, nút trợ năng, hộp thoại, bàn phím.
- **Giới hạn 2 — đắt.** Đo bằng `g6cpu` 10 giây, cửa sổ trưng bày trong app Cài đặt (trong cửa sổ có một vòng xoay đang
  quay nên cửa sổ được dựng lại liên tục), ô mờ 440×300 điểm bán kính 8:

  | Trạng thái | backboardd |
  |---|---|
  | Không có ô mờ | 5,8% CPU |
  | Có ô mờ, nội dung sau ô đứng yên | 19,9% |
  | Có ô mờ + con trỏ nhập nhấp nháy sau ô | 33,4% |

  Mỗi lần cửa sổ dựng lại là mờ lại cả vùng. Ô cỡ nửa màn hình trên màn hình chính (đồng hồ sống nhích 10 lần / giây, dải
  hiệu suất…) sẽ ngốn gần hết một nhân. D2 vì vậy **vẫn đúng** cho mọi tấm kính đang có: dựng thành ảnh một lần rẻ hơn hẳn.
- Chỗ có thể dùng (chưa làm): vùng nhỏ nằm trên nền đứng yên trong cùng cửa sổ, hoặc hiệu ứng ngắn lúc chuyển cảnh — ví dụ
  nền của thư mục kiểu khối nổi (việc còn lại của Đợt 1) nếu chịu tạm dừng mọi chuyển động của màn hình chính lúc thư mục mở.
  Phải đo lại trước khi dùng thật.

## D32. Đợt 3: khung vẽ lại app «giả vật liệu» — Ghi chú, Lời nhắc, Lịch, Danh bạ (19/11/2026)

Anh cho phép mở bốn app chứa dữ liệu riêng. Cách giữ riêng tư khi làm: ảnh chụp chỉ xem ở dạng thu nhỏ (1/3; Danh bạ 1/6 –
1/10 vì tên in đậm vẫn đọc được ở 1/3) hoặc cắt riêng phần khung; cây view lấy về thì bỏ hết phần chữ trước khi đọc; mọi tệp
tạm xoá ngay sau khi dùng, cả trên máy thử. Không chép hay mô tả nội dung nào vào mã / tài liệu.

**Phát hiện mở đường** (công cụ `imglog` — tệp cờ `/var/tmp/vn.glass6/imglog`, ghi tên + cỡ mọi hình nạp bằng
`+[UIImage imageNamed:]`): cả bốn app dựng giao diện từ hình trong gói app, nạp qua đúng một cửa đó, tên rõ ràng — Ghi chú 40
hình («back LS», «index LS», «LStop bar», «selection1-10»…), Lời nhắc 42 («backgroundPattern», «card», «wellTop»…), Lịch 43
(«Calendar-Day-Nav-LS», «button-normal», «TimeScrubber…»), Danh bạ 25 («BookLeftEdge», «LeftPage_landscape_noStitching»…).

**Khung chung** (`tweak/UI/G6UISkin.m`, vẫn dưới công tắc `featAppSkins`):

1. *Thay vân theo tên hình.* Móc `+[UIImage imageNamed:]`; tên có trong bảng của app thì trả một ảnh phẳng **cùng cỡ** với
   ảnh gốc (bố cục app tính theo cỡ ảnh; app tự gọi `stretchable…` trên ảnh nhận về). Các «vai»: nền, mặt giấy, thẻ bo góc,
   thanh trên / dưới, nút, ô tìm kiếm, hình một màu, dòng đang chọn, lớp phủ, nét mảnh, trong suốt. Không sửa tệp nào trong gói
   app. Bảng được khai ngay trong hàm khởi tạo của thư viện (chỉ việc của runtime) vì app nạp hình trước lượt đặt kiểu đầu.
2. *Chế độ tối bằng bộ lọc.* Mọi ảnh thay thế theo bảng màu SÁNG; ở chế độ tối cửa sổ của app (lớp `UIWindow` thuần) mang
   bộ lọc `colorMatrix` «đảo sáng tối, giữ sắc màu» (D30). Đo: bộ lọc phủ cả cửa sổ 1024×768 làm backboardd tốn thêm ~5% CPU
   lúc đang có chuyển động (5,9% → 10,8%). Lý do chọn cách này thay vì đổi màu từng thứ:
   - chữ app tự vẽ, trang ghi chú, ô lịch… tối theo mà không cần biết từng lớp view;
   - **không đổi màu chữ trong tài liệu của người dùng**: đổi `textColor` của trang ghi chú (UITextView dựng trên WebKit) có
     nguy cơ lọt vào nội dung được lưu / đồng bộ — bộ lọc chỉ đổi cách hiển thị;
   - đổi sáng ↔ tối lúc app đang mở chỉ là gắn / gỡ bộ lọc: tức thì, không dựng lại hình nào.
   Ma trận ở đây là phép đảo thuần (không thêm tương phản như bàn phím) nên là phép **đối hợp** — áp hai lần về màu gốc. Dùng
   điều đó cho hai việc: view chứa ảnh thật mang thêm đúng bộ lọc đó thì giữ nguyên màu (`G6UISkinKeepColors` — ảnh chân
   dung trong Danh bạ, chỉ khi `-hasImageToDisplay`; hình bóng mặc định thì để tối theo); và «vùng vốn tối».
3. *«Vùng vốn tối»* (`G6UISkinInvertRegion`): phần app vẽ chữ SÁNG trên nền tối (cột trái của Lời nhắc: danh sách và lịch
   tháng, chữ trắng trên da) mang bộ lọc đảo suốt lúc đang vẽ lại → ở chế độ sáng thành chữ tối trên nền sáng; ở chế độ tối
   bộ lọc của cửa sổ đảo thêm lần nữa → về dạng gốc. Hình thay thế nằm trong vùng khai kèm cờ `G6SkinInverted` (vẽ bằng màu
   đảo). Không dùng cách này cho hai thanh của Lịch: hình trên nút ở đó đi qua bộ tô hình của thanh (cho ra hình tối) — đảo
   cả vùng thì hình thành sáng trên nút sáng; nên ở Lịch đổi thẳng màu chữ của nút / nhãn (ít phần tử, đều là lớp chuẩn).
4. *Thành phần chuẩn trong app đang vẽ lại* hỏi `G6UIDark()` thay cho `G6IsDark()` — luôn trả «sáng» (phần tối do bộ lọc
   lo; không thì công tắc, bánh xe… bị tối hai lần thành sáng). App đang vẽ lại cũng được bật lại thanh / bảng / nút chuẩn
   (chính sách «giả vật liệu» của lõi vốn chừa ra): không bật thì hình trên nút của thanh vẫn trắng như trên thanh da →
   mất hút trên nút sáng (gặp ở dấu cộng của Ghi chú). Bàn phím nằm ở cửa sổ khác, vẫn theo chế độ thật.
5. Hệ quả phải nhớ khi vẽ ảnh thay thế: bóng đổ tối sẽ thành quầng sáng dưới bộ lọc → không dùng bóng, chỉ nét mảnh.

**Từng app** (mỗi app một tệp `G6UIApp<Tên>.m`: bảng thay hình + vài hàm móc nhỏ cho thứ app tự vẽ không qua hình):

- *Ghi chú*: nền, thẻ danh sách trắng bo góc, trang trắng, thanh phẳng, nút bo tròn; vòng tròn đỏ vẽ tay quanh dòng đang
  chọn (ba kiểu × 10–11 khung hình) → một viên mờ; ẩn `NotesRuleView` (dòng kẻ app tự vẽ); bỏ viền lớp vẽ của
  `NotesListTableView` (khung ô kẻ quanh danh sách).
- *Lời nhắc*: nền; thẻ giấy chín mảnh → thẻ trắng (lề 2, bán kính 8 để góc nằm gọn trong mảnh góc); cột trái là vùng vốn tối.
- *Lịch*: hai thanh, nút, ô tìm kiếm, rãnh thanh trượt ngày, mép sổ → màu nền, trang → trắng; bộ chọn chế độ xem nhận kiểu
  nút chọn đoạn của Glass 6; chữ nút / nhãn trên hai thanh đổi sang tối. Hình của Tuần / Tháng / Năm / D.sách khai theo cùng
  quy tắc tên («Calendar-<kiểu>-…-LS/PT») — lượt hai đã soi cả năm chế độ xem và sửa:
  - núm của thanh trượt ngày (vàng da) → viên mờ; hình trên nút (nâu) → một màu;
  - thanh ngày của D.sách («list-header»): view của nó nền ĐEN, ảnh gốc đục — thay bằng lớp phủ mờ thì lộ nền đen. Tìm ra
    bằng thống kê màu điểm ảnh theo dải (các dải 24 điểm màu (0,0,0) ở chế độ sáng), không nhìn ảnh vì D.sách có tên sự
    kiện chữ to. → mặt đục màu nền;
  - nút «Lịch» vừa có hình vừa có chữ: khi nút trên thanh mang kiểu Glass 6, UIKit chỉ giữ hình và thu nhãn về bề rộng 0 mà
    vẫn chừa chỗ (`inspect`: nhãn (40 5; 0 18), nút 58 điểm, hình lệch trái). Không giành lại chỗ cho chữ (phải móc cả
    `sizeThatFits:` lẫn bố cục của UINavigationButton) mà bỏ chữ của nút, cho nó co về nút chỉ có hình.
- *Danh bạ*: mép bìa → màu nền, hai trang trắng, bỏ gáy / đường khâu / bóng / dải ruy băng, nút bo tròn; nền của
  `ABBookCoverView` **và mọi view nằm sau nó tới cửa sổ** tô màu nền chung (các mảnh mép không phủ kín; máy đứng thì cuốn sổ
  không phủ kín màn hình, hai dải trên / dưới lộ nền đen của view gốc — thành dải trắng ở chế độ tối); ảnh chân dung như mục 2.

**Đã thử trên máy** (ảnh thu nhỏ / cắt khung / thống kê màu): cả bốn app mở mới ở chế độ tối, đổi sang sáng rồi về tối lúc
đang mở — đổi tức thì, không sập; máy ngang và máy đứng (xoay bằng lệnh thử `orient` chạy ngay trong app); năm chế độ xem của
Lịch. Lời nhắc ở máy đứng vẫn hai cột như máy ngang (không phải bảng nổi như em đoán lúc đầu). Bảng nổi «Thêm Sự kiện» của Lịch
(mở bằng lệnh thử `press @x,y`, biểu mẫu trống, bấm «Hủy» — không lưu gì): khung bảng nổi, bảng nhóm, nút, công tắc và **bánh
xe ngày giờ kiểu mới (D29)** đều đúng ở cả hai chế độ — các thành phần chuẩn dựng theo bảng màu sáng rồi được bộ lọc của cửa sổ
đảo, đúng như thiết kế; bàn phím tối (D30) cũng hiện đúng trong app này.

**Lượt ba — màn hình thêm mới, bảng nổi, bảng chọn** (không tạo hay sửa dữ liệu nào: biểu mẫu để trống rồi «Hủy» / «Xong»;
bảng nổi và bảng chọn dùng lệnh thử `popover 1`, `sheet 1` — nội dung thử, chạy ngay trong app đang vẽ lại):

- *Đạt ngay*: bảng nổi danh sách ghi chú ở máy đứng (Ghi chú); biểu mẫu «thêm liên hệ» của Danh bạ (nút, ô nhập, bàn phím
  tối); bảng nổi thử có thanh điều hướng + nút «Xong» trong Ghi chú.
- *Bảng chọn trong app đang vẽ lại* (lỗi chung của cả bốn app): tiêu đề mất hút, chữ nút nhạt. `G6Alert.m` (mã chung với
  SpringBoard) chọn bảng màu theo chế độ THẬT, trong khi bảng chọn nằm ngay trong cửa sổ của app — nơi mọi thứ phải dựng theo
  bảng màu sáng (mục 4). → `G6AlertSetSheetDarkProvider`: Glass6UI trao `G6UIDark` cho phần bảng chọn. Hộp thoại
  (UIAlertView) nằm ở cửa sổ riêng không mang bộ lọc nên vẫn theo chế độ thật.
- *Nút tròn xoá / thêm ở đầu dòng lúc bảng đang sửa* (Lời nhắc › «Sửa» ở cột trái): đĩa đỏ viền trắng thành hồng nhạt viền
  đen ở chế độ sáng (cột trái là vùng vốn tối: đảo một lần). Màu ở đây là tín hiệu nên phải giữ → khung chung móc
  `-[UITableViewCellEditControl didMoveToWindow]` (và nút xác nhận «Xoá») gọi `G6UISkinKeepColors`. Hàm đó trước chỉ xét bộ
  lọc của cửa sổ; nay tính **chẵn lẻ số lần đảo ở phía trên** (bộ lọc cửa sổ + mỗi vùng vốn tối bao quanh): lẻ thì view mang
  thêm một lần đảo. Trong vùng vốn tối điều đó xảy ra ở chế độ sáng, ngoài vùng thì ở chế độ tối.
- *Nhãn đầu mục trong danh sách của cột trái Lời nhắc* (tên tài khoản): chữ tối khắc chìm trên dải sáng «listHeader» — dải
  đã thành trong suốt nên chữ tối rơi lên nền tối, mất hút ở cả hai chế độ. → đổi màu nhãn (xám sáng trong hệ màu gốc của
  vùng) ở lượt xếp chỗ của bảng nằm trong `RemindersWellView`.
- *Hai nút ở đầu thẻ Lời nhắc* (dấu cộng, «Xong»): nhạt gần mất trên viên nút trắng. Mất ba lượt mới ra — ghi lại để lần sau
  ĐO TRƯỚC KHI SỬA: (1) đổi màu chữ của nút — không ăn; (2) `inspect` cho thấy nội dung lớp vẽ của nhãn là một CGImage chứ
  không phải vùng vẽ thường, điểm đục nhất chỉ 82%, màu đã bị pha lại (đo điểm ảnh: xám 0,61 dù màu nhãn là 0,22);
  (3) `methods RemindersListHeaderView` lộ ra `-cardButtonLetterpressStyle` và `-cardButtonForegroundColor`: app vẽ chữ nút
  theo kiểu «khắc chìm» của UIKit. → hai hàm đó trả «không khắc chìm» + màu chữ tối; riêng nút hình
  (`-newHiconButtonWithImage:`) vẫn để app khắc chìm (bỏ thì dấu cộng ra nhoè) rồi dựng lại hình ở lượt xếp chỗ của nút: giữ
  kênh đục, kéo điểm đục nhất lên đục hẳn, tô xám tối.
- *Nút «Xong» ở cột trái Lời nhắc lúc đang sửa* (hình «ButtonSilver», không mang cờ đảo): viên ĐEN chữ sáng ở chế độ sáng,
  viên trắng chữ tối ở chế độ tối — để nguyên làm nút «nổi bật»; khai cờ đảo thì chữ của app (tối, hợp nút bạc) sau khi đảo
  thành chữ sáng trên viên trắng, không đọc được.
- *Ghi chú không có ghi chú nào* trên máy thử: nút chia sẻ / thùng rác bị tắt nên không mở được bảng chọn thật của app.

Công cụ kiểm thêm ở lượt này (`tools-local/`, không vào kho): `probe.sh` (mở app / chạy lệnh thử / chụp tối + sáng + lấy cây
view / đóng app và xoá tệp tạm trên máy thử) và `ctl.py` — đọc cây view rồi chỉ in LỚP + KHUNG TUYỆT ĐỐI (đúng hệ toạ độ của
`press @x,y`), không in chữ nào. Ảnh chụp chỉ cắt đúng cột nút / biểu mẫu trống; cột tên thì không lấy (lỡ nới khung cắt
rộng hơn cột nút là dính mấy chữ đầu của tên danh sách — giữ khung cắt ≤ bề rộng cột nút).

**Chưa thử**: sửa một liên hệ / lời nhắc có sẵn (bảng chi tiết của lời nhắc; nút xoá đỏ trong app không có vùng vốn tối);
bảng chọn thật của Ghi chú; gõ chữ trong Ghi chú; ảnh chân dung thật trong Danh bạ; tắt công tắc lúc app đang mở (hình đã
nạp giữ tới lần mở sau — đúng thiết kế, chưa xem tận mắt).

**Còn lệch so với iPadOS**: chữ nội dung vẫn phông và màu của app (nâu ở Ghi chú, hồng ở Lời nhắc); ô lõm của cột trái Lời
nhắc thành hình chữ nhật không bo; ở chế độ tối thẻ đen hơn nền (đảo thuần: trắng → đen, nền 0,93 → 0,07) — ngược với iPadOS
(thẻ sáng hơn nền) nhưng vẫn tách được nhờ nét viền; lớp phủ mờ đen (bảng nổi, hộp chọn) dưới bộ lọc thành mờ sáng — bóng
đổ quanh bảng nổi vì thế thành quầng sáng mảnh ở chế độ tối. Nút «Xong» kiểu nổi bật trên thanh (viên xanh) mang chữ tối ở
chế độ sáng — iPadOS dùng chữ trắng; có từ D23 và áp cho mọi app, chưa đổi.

**Việc ngoài lề phải nhớ**: bản ghi lỗi `GramMini … 0xbad22222` lúc 16:17 không phải lỗi mã — đó là iOS dừng một app nền kiểu
VoIP vì nó bị khởi động lại quá nhiều lần, hệ quả của việc respring liên tục trong ngày. Gom thay đổi để respring ít hơn.

## D33. SpringBoard, phần còn sót: ô tìm kiếm kính, nút «Không làm phiền», chấm trang (19/11/2026)

**Ô tìm kiếm của trang Tìm kiếm (Spotlight)** — thành phần `search` (khoá `featSearch`, công tắc «Ô tìm kiếm kính»),
`tweak/SB/G6Spotlight.m`. iOS 6: `SBSearchView` là một trang của khung cuộn biểu tượng, chứa `UISearchBar` 344×44 (nền vốn đã
ẩn) › `UISearchBarTextField` 334×31 (viên trắng bóng, giống hệt nhau ở sáng lẫn tối) và một `UITableView` kết quả.

- Nền ô = tấm kính `capsule` (cùng bề mặt với dải hiệu suất), đặt qua hàm công khai
  `-[UISearchBar setSearchFieldBackgroundImage:forState:]` — trả lại kiểu gốc chỉ là đặt `nil`.
- Tấm kính dựng theo **vị trí nghỉ** của ô (lúc trang Tìm kiếm hiện trọn), tính trong view cha đứng yên của khung cuộn
  (`G6GlassImageForRect`), không theo chỗ ô đang nằm lúc dựng — lúc đó trang còn ở ngoài màn hình. Lật tới nơi là khớp nền;
  trong lúc đang lật nền của kính đi theo ô (lệch thoáng qua, chấp nhận). Dựng 334×31 mất ~7 ms.
- Chữ gõ, chữ gợi ý (`_placeholderLabel`), kính lúp (`leftView`, tô lại theo kênh đục): theo sáng / tối; phông Inter. Ở chế
  độ sáng trên hình nền tối, kính sáng ra màu trung tính → chữ gợi ý dùng độ đục 0,62 thay cho 0,45 quen dùng.
- Dựng lại khi khung nghỉ đổi (xoay máy), đổi sáng ↔ tối, đổi hình nền (khoá nhớ = khung + chế độ + đời hình nền).
- Đã thử trên máy: tối, sáng, máy đứng, tắt ↔ bật công tắc trong Cài đặt (về đúng viên trắng gốc rồi lên kính lại), bàn phím
  bật trong trang này — **bàn phím tối (D30) chạy đúng trong SpringBoard**. **Chưa làm**: bảng kết quả — muốn soi phải gõ
  chữ, mà kết quả là dữ liệu riêng của người dùng (danh bạ, tin nhắn…); nút xoá chữ trong ô vẫn là hình gốc.

**Nút «Không làm phiền» trong Control Center** (bổ sung D20):

- Bật / tắt: `-[BBSettingsGateway setBehaviorOverrideStatus:]` với 1 / 0 (khung BulletinBoard) — đúng việc công tắc «Không làm
  phiền» của app Cài đặt làm. Cổng tạo một lần, giữ suốt.
- Trạng thái: `BBSettingsGateway` của iOS 6.1.3 không có hàm hỏi tức thời (chỉ có hàm báo khi đổi) → đọc mục «trăng khuyết»
  của thanh trạng thái: mảng `_itemIsEnabled` (kiểu `[24c]`, kiểm đúng kiểu trước khi đọc) của `SBStatusBarDataManager`, chỉ
  số = số loại của `UIStatusBarQuietModeItemView` (tra lúc chạy, D26). Đó là «đang có hiệu lực», gồm cả lúc bật theo lịch hẹn.
  Hệ quả: đang trong giờ hẹn mà bấm tắt thì nút vẫn sáng (lịch hẹn vẫn giữ hiệu lực) — chưa xử.
- Hàng nút tròn nay sáu nút: cỡ 54 không vừa bề ngang bảng → cả hàng tự thu nhỏ sao cho khe giữa các nút còn ít nhất 8 điểm
  (sáu nút: 45 điểm; máy thiếu nút nào thì các nút còn lại to trở lại). Hình trăng khuyết tự vẽ, nút bật màu tím.
- Đã thử trên máy: đọc đúng trạng thái đang bật; bấm → tắt (mục trăng khuyết tắt theo) → bấm → bật lại.
  **Vẫn chưa có**: AirPlay.

**Chấm trang**: giữ nguyên — chấm trắng nhỏ + kính lúp của iOS 6 vốn đã cùng dạng với iPadOS, không có gì để đổi.

## D34. Chặn cập nhật iOS qua mạng (OTA) — một mục trong danh mục dịch vụ (19/11/2026)

**Tra trên máy** (bổ sung D22 — trước đây ghi «không nằm trong LaunchDaemons của iOS 6.1.3»):

- Trên iOS 5 / 6 nguyên bản, cập nhật qua mạng do hai việc launchd lo, đều chạy theo yêu cầu (MachServices):
  `com.apple.softwareupdateservicesd` (`SoftwareUpdateServices.framework/Support/softwareupdateservicesd` — kiểm tra, hiện huy
  hiệu, tải) và `com.apple.mobile.softwareupdated` (`MobileSoftwareUpdate.framework` — cài). Tên tệp = nhãn; đọc từ máy thử
  iOS 5.1.1 (chỉ đọc).
- **Cả hai máy iOS 6 dùng để thử (iPad mini 1 — 6.1.3, iPhone — 6.1.4) đều không còn hai tệp đó** trong
  `/System/Library/LaunchDaemons` (thư mục trên iPad đổi lần cuối 14/11/2026): máy đã được chặn cập nhật từ trước theo cách cũ
  là gỡ tệp. Hệ quả nhìn thấy: Cài đặt › Cài đặt chung › Cập nhật phần mềm đứng mãi ở «Kiểm tra Cập nhật…», không tiến trình
  cập nhật nào chạy, danh mục bản cập nhật tải về từ 14/11 không đổi. Ngoài màn đó ra máy chạy bình thường nhiều ngày —
  tức trạng thái «hai việc này không chạy» là an toàn.
- Đã cân nhắc rồi bỏ: chặn tên miền `mesu.apple.com` bằng `/etc/hosts`. Phải để công cụ quyền root sửa một tệp hệ thống
  (g6svc hiện không sửa tệp nào), lại chặn luôn mọi thứ khác tải qua MobileAsset (phông, giọng đọc, từ điển) — trong khi tắt
  hai việc trên là đủ và trả lại được bằng một lệnh.

**Quyết định:** thêm mục `iosupdate` («Cập nhật iOS qua mạng (OTA)», nhóm C — không nằm trong hồ sơ «Cân bằng», người dùng tự
chọn) vào `data/services.tsv` với hai việc trên. Tắt / bật bằng đúng cơ chế sẵn có của g6svc (`launchctl unload -w` /
`load -w`, có bộ gác khởi động D22) — không xoá tệp, khác cách gỡ tệp kiểu cũ ở chỗ bật lại được ngay trong Cài đặt.

**Ngoại lệ của quy tắc «đã thử trên máy thật» (D22):** không tắt / bật thử được mục này vì máy thử không còn tệp việc. Căn cứ
để vẫn đưa vào: (1) trạng thái «tắt» đã có sẵn trên hai máy và vô hại; (2) cơ chế tắt / bật giống hệt 15 mục đã thử; (3) máy
không có tệp thì mục tự ẩn (`g6svc status` chỉ in dịch vụ có trên máy — đã xem: vẫn 15 dòng, không có `iosupdate`), nên bản
dựng mới không đổi gì trên máy của anh. **Cần thử khi có máy iOS 6 còn nguyên hai tệp**: tắt, mở màn Cập nhật phần mềm, khởi
động lại, bật lại.

**Anh chốt (19/11/2026): «Chặn cập nhật, anh giữ phiên bản iOS 6».** Làm thêm cho mục này thành một tính năng trọn vẹn:

- *Nhóm riêng trong Cài đặt › Glass 6 › Dịch vụ hệ thống* («Cập nhật iOS», ngay dưới phần hồ sơ), không lẫn vào nhóm «Tuỳ nhu
  cầu». Máy còn dịch vụ cập nhật: công tắc **«Chặn cập nhật iOS»** — nghĩa ngược với các công tắc dịch vụ khác cho dễ hiểu
  (BẬT = đang chặn). Máy đã bị gỡ sẵn tệp việc: một dòng «Chặn cập nhật iOS — Đã chặn sẵn» kèm lời giải thích, không có gì
  để gạt.
- *Hồ sơ không đụng tới mục này*: áp «Cân bằng» / «Về Nguyên bản» không tắt cũng không âm thầm mở lại cập nhật; dòng «Đang
  dùng» cũng không tính nó khi so hồ sơ.
- *Dọn dấu nhắc còn sót* (`tweak/SB/G6UpdateBlock.m`): dịch vụ cập nhật để lại huy hiệu «1» trên biểu tượng Cài đặt
  (SpringBoard giữ trong trạng thái app) và khoá `kBadgedForSoftwareUpdateKey` / `kBadgedForSoftwareUpdateJumpOnceKey` trong
  cấu hình của app Cài đặt (số «1» ở dòng «Cài đặt chung»). Chính dịch vụ đó mới gỡ chúng — đã chặn nó thì dấu nhắc nằm lại
  mãi. Khi cập nhật ĐANG BỊ CHẶN (`G6SvcUpdateBlock`: mục `iosupdate` đang tắt, hoặc g6svc không báo mục này và hai tệp việc
  đúng là không còn) **và** khoá `kBadgedForSoftwareUpdateKey` đang bật → tắt hai khoá, gỡ huy hiệu của biểu tượng Cài đặt
  (`-[SBIcon setBadge:nil]`). Chỉ gỡ huy hiệu khi chính khoá đó nói huy hiệu là của việc cập nhật; cập nhật không bị chặn thì
  không đụng gì. Xét 20 giây sau khi SpringBoard mở xong và mỗi lần màn «Dịch vụ hệ thống» đổi dịch vụ xong (thông báo
  Darwin `vn.glass6/svc`).
- Đã thử trên iPad mini 1 (trường hợp «đã bị gỡ sẵn»): nhật ký «đang bị chặn — đã dọn dấu nhắc (huy hiệu trên Cài đặt: gỡ)»,
  biểu tượng Cài đặt hết huy hiệu, nhóm «Cập nhật iOS» hiện dòng «Đã chặn sẵn». **Chưa thử** (cần máy iOS 6 còn nguyên hai tệp
  việc): gạt công tắc «Chặn cập nhật iOS», dọn dấu nhắc ngay sau khi gạt, bật lại.

## D35. Phạm vi app (anh chốt) và hai app Ảnh, Tin nhắn (19/11/2026)

**Anh chốt phạm vi:** app bên thứ ba **để nguyên** (không nạp giao diện Glass 6 vào chúng — khoá ẩn `appsThirdParty` giữ tắt,
không làm kênh cấu hình riêng cho app trong hộp cát); trong các app của Apple còn lại chỉ làm tiếp **Ảnh** và **Tin nhắn**;
Mail, Game Center, Nhạc để nguyên (Mail vẫn nhận kiểu chung của thanh / bảng như mọi app chuẩn; Game Center, Nhạc vẫn nằm
trong danh sách «giả vật liệu» của lõi).

Cả hai app đều KHÔNG nạp hình giao diện qua `+[UIImage imageNamed:]` (`imglog` không ghi được tên nào) nên không dùng khung
thay hình của D32; cũng không dùng bộ lọc đảo màu: nội dung là ảnh / tin nhắn của người dùng — sót một lớp view là ảnh hiện
thành âm bản. Cách làm ở đây là móc đúng chỗ app đặt ảnh / màu, có ghi nhớ để trả lại.

**Cách giữ riêng tư** (siết thêm so với D32): không xem vùng nội dung nào, kể cả ảnh thu nhỏ. Kịch bản kiểm
(`tools-local/photos_check.*`, `sms_check.*`) chụp từng bước, rồi chỉ (a) in thống kê màu — màu trội theo vùng, (b) ghép ảnh từ
đúng các khung lấy trong cây view đã bỏ chữ: thanh, bảng nổi, hàng nút — và chỉ khi kiểm được vùng đó đúng là thứ mong đợi
(thanh phải đồng màu đúng màu mặt thanh; dải thanh nhập chỉ lấy khi cây view của chính lượt chụp đó có thanh nhập và ô nhập
trống). Bong bóng tin nhắn soi bằng **bong bóng thử** (lệnh thử `balloons`, chữ của em) chứ không nhìn tin nhắn thật. Ba lần sơ
suất trong lúc dựng kịch bản (một mép ảnh thu nhỏ lọt vào khung cắt bảng nổi đã tự đóng; hai hàng điểm ảnh của ảnh dưới thanh;
một dòng tin nhắn hiện ra ở chỗ thanh nhập vừa biến mất) đã báo anh, ảnh xoá ngay; quy tắc «kiểm rồi mới cắt» ở trên là từ đó.

**App Ảnh** (`tweak/UI/G6UIAppPhotos.m`; iPad: thẻ «Ảnh» / «Album», trình xem `WPhotoViewController`):

- Thanh trên vốn đã theo kiểu chung. Nền lưới ảnh của app ĐEN ở cả sáng lẫn tối → chế độ sáng đổi nền của `PLTableView` và
  mọi view cha tới cửa sổ sang trắng, nhãn album (`PLLabel` trong `PLStackItemViewCell`) sang chữ tối không bóng; chế độ tối giữ
  nguyên bản. Trình xem một ảnh giữ nền đen ở cả hai chế độ (không có `PLTableView` nên không bị đụng).
- Trình xem: bốn nút bên phải của thanh nằm trong một `UIView` do app tự xếp theo bề rộng đo lúc nút chưa vào cửa sổ; nút nhận
  phông / viên nút của Glass 6 xong thì rộng ra («Bản trình chiếu» 118 → 131 điểm) và đè lên nút kế bên → xếp lại sau mỗi lượt
  xếp chỗ của thanh (khe 6 điểm, giữ mép phải). Hình thùng rác / chia sẻ là ảnh trắng app tự đặt → tô theo màu chữ của thanh.
- Dải ảnh thu nhỏ ở đáy trình xem: để nguyên — `+[PLPhotoScrubber _backgroundImage]` chỉ là một viên 86×14 ôm các ảnh thu nhỏ,
  không phải một thanh (đã thử thay rồi bỏ).
- Đã thử trên máy (tối + sáng): hai thẻ, chế độ «Sửa» có / không chọn ảnh, bảng «Bản trình chiếu», trình xem (mở bằng cú chạm
  giả). **Chưa thử**: bên trong một album, màn sửa ảnh (xoay / cắt), bảng chia sẻ, video, máy đứng.

**Hai thứ dùng chung sinh ra từ app Ảnh:**

- *Nút lớn trong bảng nổi* (`UIPopoverButton` — «Bắt đầu Trình chiếu»): nền xanh đen bóng → viên bo góc màu nhấn, chữ trắng
  Inter (`G6UIPopover.m`).
- *Nút «phá huỷ» trên thanh* («Xóa» lúc đang chọn ảnh): bản gốc là nút đỏ — `-[UINavigationButton _barButtonItemStyle]` = 7
  (đo trên máy; nút thường 1, «Xong» 2). Viên nút của Glass 6 dùng chung cho mọi kiểu nên mất dấu hiệu đó → giữ viên trung
  tính, chữ đỏ (`G6UIBars.m`, đặt lại sau mỗi lượt xếp chỗ của nút). Đã xem trên máy ở chế độ tối (chọn một ảnh rồi bỏ chọn).

**App Tin nhắn** (`tweak/UI/G6UIAppMessages.m`; khung ChatKit):

- Máy thử chưa đăng nhập iMessage nên app mở ra là bảng đăng nhập (`CNFReg…`, bảng nhóm chuẩn — đã theo kiểu chung, đạt ở cả
  hai chế độ; em không xem hai ô nhập vì ô ID Apple có thể đã điền sẵn). Để soi phần còn lại, bảng đó được đóng tạm bằng lệnh
  thử (`vcsend UINavigationController dismissModalViewControllerAnimated: 0`) — không đăng nhập, không gõ gì; mở lại app là
  bảng hiện lại.
- *Bong bóng chữ*: `-[CKColoredBalloonView updateImage]` / `-updateHighlightedImage` đặt ảnh bóng kéo giãn → thay ngay sau đó
  bằng ảnh phẳng **cùng cỡ, cùng mép kéo giãn** (bố cục chữ của ChatKit không đổi): thân bo tròn nằm trong khung bao phần đục
  của ảnh gốc, đuôi nhỏ ở góc dưới. Loại bóng (xám / lam iMessage / lục SMS) suy từ **màu trung bình của chính ảnh gốc**, bên
  có đuôi suy từ lề nội dung `+contentInsetsForBalloonOrientation:` — không dựa vào giá trị số của `outgoingColor` /
  `orientation`. Chữ (`-[_CKTextBalloonView textColor]`, `-textShadowColor`): trắng trên bóng màu; trên bóng xám thì đen (sáng) /
  trắng (tối); bỏ bóng chữ. Bong bóng ảnh (`CKImageBalloonView`) không đụng tới.
- *Nền trò chuyện* (xanh xám 212, 218, 228 ở cả hai chế độ) → trắng / đen; bỏ hai dải bóng đổ ở mép. Nhãn thời gian / trạng
  thái: bỏ bóng trắng «khắc chìm».
- *Cột danh sách* (trắng ở cả hai chế độ): chế độ tối đổi nền ô, nền bảng, vạch ngăn, chữ (tên trắng, tóm tắt xám, ngày lam
  nhạt); chế độ sáng trả màu gốc.
- *Thanh nhập* (`CKMessageEntryView`): mặt thanh của Glass 6; khung ô nhập (`_inputFieldCover` — ảnh có lỗ trong suốt) dựng
  lại phẳng với lỗ bo tròn đúng chỗ lỗ của ảnh gốc; nút máy ảnh tự vẽ một màu (ảnh gốc là cả một nút tròn bóng — tô theo kênh
  đục thì thành đĩa đặc, đã thử); nút «Gửi» là viên màu theo ảnh nền gốc của từng trạng thái (lam / lục / xám lúc tắt), dựng
  lại khi đổi chế độ. **Ô nhập ở chế độ tối vẫn là viên sáng chữ đen**: chữ đang gõ là nội dung của người dùng, không đổi màu.
- Hai nút hình trên thanh của cột phải (`CKTranscriptToolbarView`): tô theo màu chữ của thanh.
- Đã thử trên máy (tối, sáng, tối lại): thống kê màu của nền trò chuyện / cột danh sách / thanh nhập đúng như thiết kế; ảnh cắt
  thanh trái, hai nút góc phải, thanh nhập; bốn bong bóng thử (hai phía × hai màu). **Chưa thử**: máy đứng, soạn tin mới, nút
  «Gửi» lúc bật (máy chưa đăng nhập iMessage nên luôn tắt), bong bóng ảnh, chế độ sửa / xoá tin, tìm kiếm; phông chữ trong
  bong bóng vẫn là của ChatKit.

**Lỗi thật tìm ra nhờ Tin nhắn — sửa ở mã dùng chung** (`G6UIRefreshAppearance`, `G6UIBars.m`): đổi sáng ↔ tối lúc đang mở
cuộc trò chuyện làm thanh nhập biến mất cho tới khi chọn lại cuộc trò chuyện. Hàm làm mới gỡ – gắn mọi view gốc để UIAppearance
áp lại, và chỉ biết trả «con trỏ» cho một VIEW; ở Tin nhắn thứ giữ con trỏ là chính view controller (để thanh nhập — phụ kiện
bàn phím — luôn hiện). → hỏi thẳng `-[UIWindow firstResponder]`, trả lại cho cả đối tượng không phải view; và không gỡ – gắn
cửa sổ của bàn phím (`UITextEffectsWindow`). Đã thử: Tin nhắn giữ được thanh nhập qua hai lần đổi; app Cài đặt vẫn giữ bàn phím
khi đổi chế độ lúc đang gõ.

**Công cụ thử thêm** (`tweak/Debug/G6Debug.m`): `row <n> [lớp bảng]` (chọn dòng theo số thứ tự — không cần biết chữ),
`gtap <lớp> <hàm> @x,y` (cú chạm giả cho view tự bắt cử chỉ: mở ảnh trong lưới), `vcsend <lớp controller> <hàm> [0|1]` (gọi hàm
của view controller: hiện / ẩn thanh của trình xem, đóng bảng đang trình bày, lùi màn của bộ điều hướng tự viết), `balloons
1|0` (bong bóng thử), `back` biết thêm bộ điều hướng tự viết. `tools-local/inst.sh`: dựng + cài KHÔNG respring (đủ cho thay đổi
chỉ ở Glass6UI) — cả phần Ảnh và Tin nhắn làm xong mà không respring lần nào.

**Việc ngoài lề:** 19:25 lại có bản ghi `GramMini … 0xbad22222` (iOS dừng app nền kiểu VoIP vì bị khởi động lại quá nhiều
lần) — hệ quả của các lần respring trước đó trong ngày, không phải lỗi mã.

## D36. Bản tiếng Anh: một bảng dịch Việt → Anh, tự chọn theo máy, đổi được trong Cài đặt (19/11/2026)

Anh để em tự xếp việc này («Ok theo ý e»); em làm sau phần app.

- **Không dùng `.lproj`.** Cơ chế bản địa hoá của hệ thống chỉ theo ngôn ngữ của máy; ở đây cần (a) người dùng chọn được —
  tweak do người Việt viết, nhiều người dùng máy tiếng Anh vẫn muốn bản tiếng Việt và ngược lại, (b) thử được bản tiếng Anh mà
  không phải đổi ngôn ngữ iPad của anh. → mọi chuỗi trong mã vẫn viết bằng tiếng Việt, bọc trong `G6L(@"…")`
  (`tweak/Common/G6Lang.m`, dùng chung cho bảng Cài đặt và tweak); bản tiếng Anh tra trong MỘT từ điển
  `prefs/Resources/Strings-en.plist` (khoá = chuỗi tiếng Việt). Không có bản dịch thì hiện nguyên tiếng Việt.
- **Khoá `language`**: «auto» (mặc định) / «vi» / «en»; «auto» = máy đặt tiếng Việt thì tiếng Việt, mọi máy khác tiếng Anh.
  Mục «Ngôn ngữ» trong Cài đặt › Glass 6 (Tự động / Tiếng Việt / English); đổi là cả bảng dựng lại ngay bằng ngôn ngữ mới.
- **Nguồn dịch** `data/strings-en.txt`: mỗi mục «# <chuỗi tiếng Việt>» rồi «<mã> = <bản tiếng Anh>», mã = 8 ký tự đầu SHA-1 của
  chuỗi tiếng Việt (sửa chuỗi tiếng Việt thì mã đổi → bản dịch cũ bị coi là thiếu, phải dịch lại: đúng ý).
  `python tools/gen_strings.py` gom mọi chuỗi cần dịch — nhãn / chú thích / tên lựa chọn trong `Root.plist`, các lời gọi
  `G6L(…)` trong `prefs/*.m` và `tweak/**/*.m`, tên + ghi chú dịch vụ (`data/services.tsv`), tên chức năng của nút
  AssistiveTouch (`assist.rs`) — rồi ghi từ điển, ghi lại tệp nguồn theo thứ tự, in chuỗi còn thiếu (thoát mã 1). Hiện 224
  chuỗi, dịch đủ. Từ điển sinh ra được đưa vào kho (máy dựng không phải chạy công cụ).
- Chuỗi do lõi sinh (tên dịch vụ, tên chức năng) vẫn là tiếng Việt trong lõi, dịch ở chỗ hiển thị — lõi không phải biết ngôn
  ngữ. Số do lõi định dạng kiểu Việt («1,2 GB») qua `G6LDecimal` đổi dấu phẩy thành dấu chấm khi hiển thị tiếng Anh.
- Các mục khai trong `Root.plist` được dịch sau khi nạp (`G6LocalizeSpecifier`: tên, chú thích cuối nhóm, tên lựa chọn).
- Nhân tiện sửa ba chú thích tiếng Việt đã cũ trong `Root.plist` (hộp thoại trong app, danh sách app được vẽ lại, Control
  Center có «Không làm phiền»).
- **Đã thử trên iPad** (đổi mục «Ngôn ngữ» bằng lệnh thử rồi trả về «Tự động»): bảng chính, màn Dịch vụ hệ thống, màn nút
  AssistiveTouch hiện tiếng Anh đúng; về «Tự động» thì lại tiếng Việt; các khoá khác của anh không đổi. **Chưa thử**: các
  chuỗi phía SpringBoard (nhãn ô của nút AssistiveTouch, hộp hỏi tắt máy / khởi động lại, «Không phát» của Control Center, nhãn
  «Đĩa» + dấu thập phân của dải hiệu suất) — mã đã có nhưng SpringBoard chưa nạp lại (em tránh respring thêm vì hôm nay
  GramMini đã bị iOS dừng hai lần do respring nhiều); máy đặt ngôn ngữ khác tiếng Việt; chưa có người bản ngữ soát bản dịch.

## D37. Rào theo mẫu máy; các câu anh chốt cho bản iPhone (19/11/2026)

Anh nhấn mạnh: «Tweak phải nhận diện được máy để rào sẵn … những mã máy khác sẽ không chạy được tweak, sau này sẽ thi công bổ
sung thêm mẫu máy sau».

- **Danh sách cho phép, không đoán.** `tweak/Common/G6Device.c`: bảng mã máy → mẫu đã làm và thử — `iPad2,5–2,7` (iPad mini 1)
  và `iPhone5,1–5,2` (iPhone 5), kèm điều kiện iOS 6 (số bản dựng `kern.osversion` bắt đầu bằng 10). Máy ngoài bảng:
  SpringBoard ghi nhật ký + trạng thái «device» rồi không gắn hàm nào; phần trong app thoát ngay đầu hàm khởi tạo; bảng Cài
  đặt chỉ hiện một nhóm «Máy chưa được hỗ trợ» nói rõ lý do. Thêm mẫu máy = thêm một dòng vào bảng sau khi đã làm và thử.
- Mã phân nhánh theo **loại máy** hỏi `g6_device_is_pad()` / `g6_device_is_phone()`, không hỏi `UI_USER_INTERFACE_IDIOM()`
  (iPhone 4S hay iPod touch cũng là «phone» nhưng chưa ai thử). Lõi nhận tên mẫu máy trong `config.set` (`device`) để đặt mặc
  định lệch theo mẫu (`Config::default_for`).
- Bản thử (không phải bản phát hành) đọc tệp `fake-machine` để giả mã máy — thử nhánh «máy chưa hỗ trợ» mà không cần máy khác.
- **Anh chốt cho bản iPhone** (trả lời mục 8 của [IPHONE.md](IPHONE.md)): (1) em toàn quyền gỡ tweak xung đột trên máy thử;
  (2) em tự thiết kế, miễn giống iOS 26 của iPhone nhất có thể; (3) khay đa nhiệm **dạng thẻ** kiểu iOS 26; (4) app chỉ iPhone
  có: nhận kiểu chung, làm riêng Điện thoại, Máy tính, La bàn, Ghi âm; (5) máy thử không có gì quan trọng — mở app nào, respring
  lúc nào cũng được. Tiêu chí của anh: đẹp, chạy ổn định, không lỗi.
- Đã gỡ khỏi iPhone thử (sao lưu tệp trước, `tools-local/iphone-backup/`): WinterBoard, libstatusbar, NCSettings, WeeLoader,
  WeePreferenceLoader, Zephyr, LayerSnapshotter, Speed Intensifier, Activator, Flipswitch.
- **Đã thử**: iPad `mẫu máy: ipad-mini-1 (iPad2,7)`, iPhone `mẫu máy: iphone-5 (iPhone5,2)`, cả hai chạy bình thường.
  Nhánh «máy chưa hỗ trợ» thử trên iPhone bằng `fake-machine` = `iPhone4,1`: SpringBoard ghi «mẫu máy «iPhone4,1» chưa được hỗ
  trợ — Glass 6 đứng yên» + trạng thái `device`, màn hình chính và app Cài đặt về nguyên bản iOS 6 (thanh trạng thái, dock,
  thanh điều hướng gốc), bảng Glass 6 chỉ còn nhóm «Máy chưa được hỗ trợ» kèm lời giải thích; gỡ tệp + respring thì chạy lại
  bình thường.

## D38. iPhone, đợt P1: màn hình chính + thanh trạng thái kiểu iOS 26 (19/11/2026)

- **Thanh trạng thái**: giờ bên trái (đã có), thêm hai khoá `statusSignalRight` (cột sóng + Wi-Fi / 3G dồn sang phải, thứ tự
  từ mép phải: pin, %, mạng, sóng) và `statusHideCarrier` (ẩn tên nhà mạng) — mặc định bật trên iPhone, tắt trên iPad; công
  tắc chỉ hiện trên iPhone (mục có `g6Device` trong `Root.plist` chỉ hiện trên loại máy đó). Vùng của từng mục đổi bằng các
  hàm `…appearsInRegion:` / `compareRightOrder:` như phần «giờ bên trái».
- **Dock**: số đo theo máy (`G6DockMeasure`): iPhone khe 12, lề 14 × 9, biểu tượng 58 → viên kính nổi 300 × 76; biểu tượng
  hạ 6 điểm để chừa chỗ cho viên «Tìm kiếm».
- **Viên «Tìm kiếm»** (`tweak/SB/G6SearchPill.m`, chỉ iPhone, thuộc `featSearch`): viên kính có kính lúp nằm trên hàng chấm
  trang; màn hình đứng yên thì thấy viên, đang lật trang thì thấy chấm; chạm → sang trang Tìm kiếm (bàn phím lên luôn).
- Biểu tượng, nhãn, đồng hồ sống, thư mục (dải kính), ô tìm kiếm của trang Tìm kiếm: dùng lại mã iPad, không phải sửa.
- **Đã thử trên iPhone** (tối + sáng): thanh trạng thái, dock, viên «Tìm kiếm» (kể cả chạm và bản tiếng Anh «Search»), thư
  mục, trang Tìm kiếm. **Chưa thử**: chấm trang hiện lúc lật bằng tay (chụp không kịp), iPad với bản này.

## D39. iPhone: màn khoá kiểu iOS 26; bỏ hình viên pin lớn lúc sạc (19/11/2026)

Anh báo: «khi iphone đang sạc pin, respring xong nó hiện cái hình viên pin khá to, cái này không giống với ios 26».

- Hình đó là `SBAwayChargingView` của màn khoá iOS 6; lúc nó hiện, hình nền màn khoá còn bị che thành đen. **Bỏ** (khoá
  `lockHideBattery`, mặc định bật, công tắc «Ẩn hình pin lớn khi đang sạc»): móc `-[SBAwayView shouldShowChargingView]` trả NO
  và `-showChargingView` không làm gì; hình đã lỡ dựng (lúc vừa respring SpringBoard dựng nó theo đường khác) thì giấu ngay rồi
  gọi `-hideChargingView` của SpringBoard để nó dọn và trả hình nền. Tắt tuỳ chọn → hình pin gốc trở lại.
- **Thay bằng dòng «Đã sạc N%»** như iOS 26: lúc màn khoá hiện / sáng lên / vừa cắm sạc mà máy đang có điện, dòng ngày đổi
  thành «Đã sạc 94%» (tiếng Anh «94% Charged») trong 4 giây rồi mờ chéo về ngày. Áp cho cả iPad (cùng lớp).
- **Bố cục đồng hồ của iPhone**: dòng ngày nằm trên (Inter SemiBold 17), giờ nằm dưới thật lớn (Inter SemiBold 80) — đổi cỡ
  phông và đặt lại khung hai nhãn sau mỗi lần SpringBoard xếp; khung gốc được cất để trả lại. Lúc đang hiện nút điều khiển
  nhạc / đang phát nhạc thì giữ bố cục gốc (chỉ đổi phông, như iPad).
- **Nút máy ảnh**: ảnh tay nắm ba vạch của `_cameraGrabber` → nút tròn 48 điểm bằng kính có hình máy ảnh (ảnh to hơn view,
  hiện ở giữa); vẫn kéo lên để mở máy ảnh. Rãnh trượt + núm: dùng lại của iPad. «Ẩn nút khung ảnh» chỉ còn hiện trên iPad.
- **Nền đen sau respring** (đo bằng cách chụp liên tục): SpringBoard dựng màn khoá — kèm màn sạc, hình nền trong suốt hẳn —
  TRƯỚC khi Glass 6 kịp gắn hàm; `-hideChargingView` chỉ trả hình nền sau khi hình pin mờ xong, nên nền đen 3–7 giây. Sửa: lúc
  ẩn hình pin thì đặt luôn độ rõ của `SBWallpaperView` về 1. Đo lại: nền hiện ngay từ ảnh đầu tiên sau respring.
- **Đã thử trên iPhone**: sau respring không còn hình pin, hình nền hiện ngay; dòng «Đã sạc N%» hiện rồi về ngày (cả lúc sáng
  màn hình sau khi đèn đã tắt hẳn); tắt / bật tuỳ chọn lúc đang ở màn khoá; gọi `_batteryStatusChanged` không làm nền đen lại.
  **Chưa thử**: vừa cắm / rút sạc, màn khoá có thông báo (khung danh sách bắt đầu ngay dưới chữ số giờ), lúc phát nhạc, iPad.

## D40. iPhone: dải hiệu suất thu gọn nằm trong khoảng trống của thanh trạng thái (19/11/2026)

Anh yêu cầu: «phía trên cùng, ở khoảng giữa giờ và icon mạng đang có một khoảng trống, e sắp xếp phần hiệu suất hệ thống vào
khoảng này nhé, thiết kế thật vừa vẹn và hài hòa».

- **Số đo**: giờ (và hình trăng «Không làm phiền» nếu bật) ở trái tới x ≈ 44–59, cụm sóng / Wi-Fi / % / pin ở phải từ x ≈ 202
  → khoảng trống 143–158 điểm, lệch trái so với tâm màn hình. Bản đầy đủ và bản gọn của iPad (cần hơn 300 điểm) không thể
  vừa → làm **bản thu gọn riêng cho iPhone**, canh giữa KHOẢNG TRỐNG (không canh giữa màn hình như iPad).
- Em phác bốn phương án bằng phông Inter ngay trên ảnh thanh trạng thái thật (cỡ điểm ảnh thật) rồi mới viết mã. Một hàng đủ
  ba mục (CPU, RAM, mạng) cần 154 điểm — không vừa. Chọn làm hai kiểu, khoá `perfStyle`, mục «Kiểu hiển thị» (chỉ iPhone):
  - **0 — Đầy đủ (hai hàng), mặc định**: ba cột, nhãn nhỏ ở trên (Inter SemiBold 6,5, mờ), số ở dưới (9,5); cột mạng xếp
    nhận ↓ trên, gửi ↑ dưới (cỡ 8), mũi tên sáng lên khi có dữ liệu. Giữ đủ thông tin của dải iPad trừ đĩa (đổi rất chậm).
  - **1 — Gọn (một hàng)**: «CPU 6%  RAM 638M» (nhãn Medium 8,5, số SemiBold 10,5) — cùng dòng chữ với giờ và phần trăm pin.
- **Vừa khít**: viên kính cao 18 điểm (thanh trạng thái cao 20), cách cụm mục hai bên 7–8 điểm; chỗ thừa chia đều vào khe giữa
  các cột (mỗi khe nới tối đa 8), thừa nữa thì canh giữa. Mỗi cột rộng cố định theo chuỗi dài nhất hay gặp, chữ canh giữa cột
  → số đổi không làm bố cục xô lệch mà vẫn cân hai bên. Thanh trạng thái có thêm biểu tượng → khe hẹp lại → bỏ cột mạng → chỉ
  còn CPU → ẩn. RAM và tốc độ mạng dùng chuỗi ngắn do lõi dựng (`ram_short` «638M», `down_short` / `up_short` «12K», «1,2M»,
  không quá bốn ký tự — có kiểm thử).
- Vẫn là dải cũ (`tweak/SB/G6Perf.m`): nằm trong màn hình chính, dưới cửa sổ thanh trạng thái → chỉ có ở màn hình chính, mờ đi
  ở trang Tìm kiếm, ẩn lúc mở thư mục, chỉ đo khi có người nhìn. Trên iPhone không có chỗ đặt thứ hai (mục «Vị trí» chỉ còn
  hiện trên iPad); chú thích cuối nhóm trong Cài đặt viết riêng cho iPhone (`g6FooterPhone`).
- **Đã thử trên iPhone**: hai kiểu × sáng / tối, có hình trăng «Không làm phiền» (khoảng trống 143); đổi kiểu lúc đang chạy.
  **Chưa thử**: thanh trạng thái có thêm biểu tượng (các bậc bớt cột), không có hình trăng, trang Tìm kiếm / thư mục trên
  iPhone, iPad với bản này.

## D41. iPhone: Control Center dạng lưới ô kính; khảo sát các tấm kính còn lại (19/11/2026)

- **Khảo sát** (bật từng thành phần của iPad trên iPhone): Trung tâm thông báo, HUD âm lượng, khay đa nhiệm (dải kính), thư mục,
  trang Tìm kiếm chạy được nguyên mã iPad. Control Center thì tràn khỏi màn hình (bảng 340 điểm, màn 320) → làm bố cục riêng.
- **Bố cục iPhone** (kiểu iOS 26 của iPhone, `G6CCBuildPhonePanel`): lưới ô vuông bo góc trên một tấm kính đậm — máy đứng 2 × 2
  (ô 134, bảng 304 × 304, canh giữa ngay dưới thanh trạng thái), máy ngang 1 × 4 (ô 124, bảng 550 × 148):
  ô kết nối (máy bay · dữ liệu di động · Wi-Fi · Bluetooth), ô nhạc (tên bài + ba nút), ô chế độ (không làm phiền · khoá xoay
  · sáng / tối · đèn pin), ô hai thanh trượt ĐỨNG (độ sáng, âm lượng).
- **Thanh trượt đứng** `G6CCVSlider` (UIControl tự vẽ): viên bo tròn, phần đã tô dâng từ dưới lên, hình ở chân đổi màu theo
  phần tô; kéo tương đối như iOS 26. Cùng tên hàm `value` / `setValue:` / `tracking` với UISlider nên phần đọc – ghi độ sáng,
  âm lượng dùng chung với iPad. Cử chỉ «vuốt lên để đóng» bỏ qua ngón tay đặt trên thanh trượt đứng.
- **Hai nút mới, chỉ iPhone**: dữ liệu di động (`CTCellularDataPlanGetIsEnabled` / `…SetIsEnabled`, tìm bằng `dlsym`) và đèn
  pin (`AVCaptureDevice` — AVFoundation nạp bằng `dlopen` lúc dựng bảng lần đầu; `torchMode` đọc lại được trạng thái).
- iPad không đổi: vẫn một hàng sáu nút tròn + hai thanh trượt ngang (hai nút mới báo «không có» trên iPad).
- **Đã thử trên iPhone** (máy đứng, chế độ tối): bảng hiện đúng lưới, trạng thái các nút đúng với máy; bấm nút đèn pin → đèn
  bật (nút vàng), bấm lần nữa → tắt; tự ẩn sau thời gian chờ. **Chưa thử**: kéo hai thanh trượt đứng bằng tay, nút dữ liệu di
  động (không bấm thử kẻo đổi kết nối của máy), máy ngang, mở bằng cử chỉ kéo từ góc trên phải, iPad với bản này.
- **Còn lại của P2**: khay đa nhiệm dạng thẻ (anh yêu cầu), băng thông báo / hộp thoại / bảng chọn kiểu iPhone, nút
  AssistiveTouch, màn khoá có thông báo.

## D42. iPhone: khay đa nhiệm dạng thẻ (19/11/2026)

Anh chốt (câu 3 của IPHONE.md mục 8): «khay đa nhiệm kiểu iphone trên ios 26» — làm ngay, không để sau phát hành.

- **Dựng mới** (`tweak/SB/G6CardSwitcher.m`, chỉ iPhone; khoá `switcherCards`, mặc định bật trên iPhone, thuộc thành phần
  `featSwitcher`; công tắc «Khay đa nhiệm dạng thẻ»): một cửa sổ riêng mức 1045 (trên app và màn hình chính), nền là ảnh chụp
  màn hình đã mờ + lớp tối; mỗi app gần đây là một thẻ ảnh chụp bo góc cỡ 62% màn hình, trên thẻ có biểu tượng + tên; cuộn
  ngang dừng đúng từng thẻ, thẻ mới nhất ở bên phải và là thẻ đứng giữa lúc mở. Chạm thẻ → mở app; vuốt thẻ lên (quá 90 điểm
  hoặc nhanh hơn 700 điểm / giây) → thoát app; chạm chỗ trống hoặc bấm Home → đóng. Tối đa 12 thẻ.
- **Nguồn của SpringBoard iOS 6** (tra trên máy): danh sách `-[SBAppSwitcherModel identifiers]`; ảnh thẻ là ảnh SpringBoard
  dùng lúc phóng app ra (`-[SBApplication defaultImage:preferredScale:originalOrientation:currentOrientation:
  canUseIOSurface:]` — ảnh chụp lần lui về nền gần nhất, không có thì ảnh mở đầu); app đang đứng trước thì chụp thẳng màn
  hình lúc mở khay (`G6ScreenImage` mới trong G6Glass.m — một lần chụp cho cả ảnh thẻ lẫn nền mờ); mở app bằng
  `-[SBUIController activateApplicationFromSwitcher:]`; thoát bằng `BKSTerminateApplicationForReasonAndReportWithDescription`
  (lý do 1, như SpringBoard) + `-remove:` khỏi danh sách.
- **Chỗ gắn**: `-[SBUIController _toggleSwitcher]` (bấm Home hai lần, sau các phép kiểm của SpringBoard) → mở khay thẻ thay dải
  gốc; `-clickedMenuButton` → khay thẻ đang mở thì đóng. Máy đang nằm ngang (trong app) → dùng khay gốc của iOS 6.
- **Ảnh nạp dần**: khay hiện ngay với thẻ trống (đo: 37–78 ms tới lúc hiện, 12 thẻ), rồi mỗi vòng lặp nạp một ảnh, thẻ gần
  nhất trước; ảnh thu về đúng cỡ thẻ. Ảnh chụp thiếu phần thanh trạng thái → kéo hàng điểm ảnh trên cùng lên lấp (liền màu).
- **Lỗi đã gặp và sửa — thoát app ĐANG đứng trước**: iOS 6 không liệt kê app đang mở trong khay nên không có đường «thoát
  app đang mở»; dừng thẳng tiến trình thì SpringBoard không dựng lại màn hình chính — màn hình đen, bấm Home cũng không về
  (phải respring). Sửa: gọi hàm gốc của nút Home cho app lui về nền trước (khay thẻ che phía trên), 0,9 giây sau mới dừng.
- **Đã thử trên iPhone** (bằng lệnh thử `cards 1|0|tap n|quit n|list`): mở từ màn hình chính và từ trong app (thẻ đầu là ảnh
  chụp sống), chạm thẻ → app mở, thoát app đứng trước → về đúng màn hình chính, thoát app nền, danh sách cập nhật.
  **Chưa thử**: bấm Home hai lần thật, vuốt thẻ bằng tay (ngưỡng, độ mượt), cuộn tay qua 12 thẻ, app nằm ngang, lúc đang gọi
  điện, bộ nhớ khi mở nhiều lần. Dải nhạc / âm lượng của khay gốc (vuốt sang phải) không còn trong khay thẻ — đã có trong
  Control Center.

## D43. iPhone: băng thông báo dạng thẻ, bảng chọn nổi, thẻ thông báo trên màn khoá (20/11/2026)

Phần còn lại của đợt P2. Anh dặn: «Làm tiếp đi e. Tự động làm và hoàn thiện».

- **Băng thông báo** (`G6Banner.m`): băng gốc của iPhone chạy hết bề ngang và che thanh trạng thái → thẻ kính bo góc 304×54
  nằm dưới thanh trạng thái (khung trả từ `-[SBBannerController _normalBannerFrameForOrientation:]`; máy ngang: thẻ đứng
  giữa, rộng tối đa 380). Kính + bóng là hai view riêng dưới cùng của băng, nền gốc ẩn; biểu tượng lấy biểu tượng màn hình
  chính của app (32 điểm), chữ xếp lại 14 / 13 điểm; hình đính kèm (băng gốc vẽ vào ảnh nền) hiện ở mép phải — **chưa thử
  với thông báo có hình thật**.
- **Hiệu ứng**: iOS 6 lật băng bằng cách hiện lại cả màn hình của SpringBoard qua `SBSpringBoardMetaHostingWindow` rồi «bẻ»
  vùng của băng thành khối hộp quay (`CAMeshTransform`, khoá hình 0° / 45° / 90°, dài 0,5 giây). Với thẻ trong suốt bốn góc,
  khối hộp lộ nguyên hình chữ nhật đen. Cách làm: mọi khoá hình lấy lưới của 90° (màn hình đứng yên) và thẻ tự trượt xuống /
  trượt lên bằng hoạt hình thường trên `SBBannerAndShadowView`; các bước còn lại của SpringBoard (hẹn giờ cất, dọn view) giữ
  nguyên.
- **Bảng chọn** (`G6Alert.m`): bảng trượt từ đáy của iPhone → tấm kính bo góc lùi 8 điểm hai bên và nhấc 8 điểm khỏi đáy
  (bề mặt `alert`, dựng theo vị trí CUỐI của bảng); `-[UIActionSheet drawRect:]` gốc không vẽ nữa. Bố cục nút của UIKit giữ
  nguyên. Bảng này nằm ở cửa sổ phủ riêng nên theo chế độ thật của máy (không theo bộ lọc của app đang vẽ lại).
- **Thông báo trên màn khoá** (`G6Lock.m`): iPhone khác iPad — một thông báo mới là ô «nổi» (nền `_firstAlertBGView` →
  kính thật), nhiều thông báo là bảng dòng 44 điểm (mỗi dòng → một thẻ kính không nền, bỏ nền đen qua `-_hasBackgroundColor`
  + nét kẻ, nội dung thu 94% bằng `sublayerTransform`); cả danh sách hạ 8 điểm dưới chữ số giờ.
- Hộp thoại, bảng nút AssistiveTouch: dùng nguyên mã iPad, đã xem trên iPhone — không phải sửa.
- **Đã thử** bằng lệnh thử `banner`, `sheet`, `lockbulletin` ở cả hai chế độ. Chưa thử: băng lúc máy nằm ngang, lúc có dải
  «đang gọi» cao gấp đôi (thẻ sẽ đè lên nửa dưới của dải).

## D44. iPhone, trong app: thanh trạng thái liền thanh điều hướng, thanh thẻ nổi, bảng (20/11/2026)

- **Thanh trạng thái** (`G6UIStatusBar.m`): trên iPhone iOS 6 nhuộm thanh trạng thái theo thanh điều hướng (kiểu mã 107) và
  vẽ mục màu trắng mờ 65% → trên thanh phẳng sáng thành dải xám chữ nhạt. Khi app xin kiểu mặc định và thành phần «bars»
  đang bật: nền thanh tô đúng màu mặt thanh, lớp mục hết mờ, ở chế độ sáng ảnh của từng mục đổi «trắng + bóng» → «tối, không
  bóng» theo điểm ảnh (màu rõ như tia sét xanh, pin đỏ giữ nguyên). Không áp khi hệ thống đang phủ kiểu đặc biệt
  (`_styleOverrides` ≠ 0: dải xanh đang gọi, dải đỏ đang ghi âm…) và không áp cho kiểu đen (xem ảnh, máy ảnh) trừ app đã
  báo `G6UIStatusBarSetForceFlat` (app vốn tối nay được vẽ lại theo sáng / tối). Màn không có thanh điều hướng báo màu nền
  của mình qua `G6UIStatusBarSetOverride`.
- **Thanh thẻ nổi** (`G6UIBars.m`): iOS 6 không cho nội dung chui xuống dưới thanh thẻ nên không làm kính thật; ảnh nền của
  thanh vẽ sẵn một viên bo tròn (lề 6 điểm), viên dưới mục đang chọn, tên mục nhấc 2,5 điểm, các mục dồn về giữa 90% cho tên
  mục đầu / cuối nằm trong viên. Lề quanh viên: sáng = màu mặt thanh, tối = đen.
- **Bảng** (`G6UITables.m`): bảng nhóm của iPhone còn hoa văn sọc (một view con nữa của nền bảng) và nét ngăn «chạm khắc»
  (nét trắng thứ hai: kiểu nét 2 → 1 + ẩn `_topShadowView` của ô). Tiêu đề nhóm của bảng thường phẳng cả ở chế độ sáng (áp
  cho cả iPad).
- **Chế độ tối cho app có ô tự vẽ** (`G6UITablesSetInvertCustomCells`, hiện bật cho app Điện thoại): mọi bảng của app dựng
  theo bảng màu sáng rồi cả bảng mang bộ lọc «đảo sáng tối, giữ sắc màu»; ô tìm kiếm và ảnh thật giữ đúng màu; bảng lồng
  không đảo thêm. (Đã thử gắn bộ lọc vào từng ô: iOS 6 lan màu nền của bảng xuống ô nên hỏng.)
- Lưu ý kỹ thuật: trên armv7 mọi cấu trúc lớn hơn 4 byte — kể cả `CGPoint` — trả qua vùng nhớ; gọi hàm trả `CGPoint` bằng
  `objc_msgSend` thay vì `objc_msgSend_stret` làm app Điện thoại thoát ngay (đã gặp, đã sửa).

## D45. iPhone: app Điện thoại, Máy tính, La bàn, Ghi âm (20/11/2026)

Bốn app anh yêu cầu làm riêng (câu 4 của IPHONE.md mục 8). Nguyên tắc chung: **không đổi khung, vùng chạm hay cách bấm** —
chỉ đổi hình.

- **Điện thoại** (`G6UIAppPhone.m`): bàn phím số là MỘT ảnh do `-[DialerPhonePad _keypadImage]` trả (phím đang bấm cắt từ
  `-_pressedImage` theo `-_rectForKey:`) → trả ảnh tự vẽ cùng cỡ: 12 phím tròn, cột hai bên kéo gần cột giữa nhưng vẫn trong
  ô chạm của mình; ba nút hàng dưới = đĩa gọi xanh + hai hình trên nền trong; chế độ tối: cả màn nền đen. Các thẻ còn lại
  theo kiểu chung + đảo màu cả bảng ở chế độ tối (D44). Màn hình đang gọi / cuộc gọi đến: không đụng.
- **Máy tính** (`G6UIAppCalculator.m`): mỗi bàn phím là một ảnh trên lưới 6 × 4 (đọc từ ivar của `CalcKeypadView`) → ảnh
  tự vẽ: nền đen, phím tròn xám / cam, «0» và «=» là viên dài; phím đang bấm = lớp sáng mờ theo `_pressedTag` (ảnh «đang
  bấm» kiểu cũ app đặt ở view gốc bị ẩn); màn hình số nền đen chữ trắng. Máy nằm ngang: cả nửa khoa học lẫn nửa cơ bản
  (phím dẹt thành viên bo tròn); các «hình thay thế» của app (`2ndOn`, `asin`…`2x`, `deg`, `OperatorRing`) được nhớ theo mã
  phím và vẽ vào ảnh: nhãn hàm thứ hai, phím «2nd» sáng lên, phép tính đang chờ đảo màu. **Bài học**: ảnh thay thế phải
  cùng cỡ với ẢNH app đặt, không theo cỡ view — lúc xoay máy app tạm co view rồi tính khung mới từ cỡ ảnh; dựng theo cỡ
  view làm bố cục máy đứng hỏng sau khi xoay về (đã gặp, đã sửa; đã thử xoay qua lại hai lượt bằng lệnh `orient`).
- **La bàn** (`G6UIAppCompass.m`): hình nạp từ nib (không qua `+imageNamed:`) → đổi TẠI CHỖ từng `UIImageView` theo cỡ ảnh
  bằng bản biến đổi từ chính ảnh gốc: nền đen, bỏ vành đồng / bóng / vệt sáng / núm, mặt kem → đĩa than, vòng độ + mũi tên
  → trắng, hoa gió (chữ hướng theo ngôn ngữ) → trắng giữ tam giác Bắc đỏ. **Máy thử đang báo «nhiễu sóng» nên mặt la bàn
  đang quay chỉ được xem qua bản dựng thử ngoài máy tính từ đúng các hình đó.**
- **Ghi âm** (`G6UIAppVoiceMemos.m`, qua khung `G6UISkin` + kiểu hình tự vẽ `G6SkinMaker`): micro crôm → hình nét, bảng điều
  khiển phẳng, đồng hồ VU vẽ theo tâm quay thật của kim, nút ghi / tạm dừng / dừng / danh sách vẽ lại; danh sách bản ghi +
  bảng phát phẳng. `vumask` là mặt nạ của kim (không được thay). App nay theo sáng / tối của máy.
- **App khác trên iPhone**: Ghi chú, Lời nhắc (bảng thay hình có thêm tên bản iPhone, đuôi `-568h` được bỏ khi tra),
  Đồng hồ (bản iPhone vẽ lại bằng khung chung, giữ màu mặt đồng hồ ngày / đêm), Tin nhắn (khung ô nhập bản iPhone, ô nhập
  tối thật ở chế độ tối). Danh bạ, Ảnh, Lịch: dùng nguyên phần đã có, đã xem. Safari giữ khung gốc; màn chào của Mail ở chế
  độ tối còn vài logo chữ đen khó thấy.
- **Công cụ thử mới**: `tap` / `drag` (giả lập ngón tay: tự tạo `UITouch` + `GSEvent` giả gửi qua `-sendEvent:` — bấm phím,
  kéo núm khoá, kéo thanh trượt; **bộ nhận cử chỉ kéo — cuộn, vuốt thẻ — không nhận chạm giả**), `tab n`, `imgdump`,
  `lockbulletin n`, `banner ms`, `send` nhận chuỗi.
- **Đã tự thử bằng chạm giả**: bấm 7 + 2 = ra 9 trong Máy tính; gõ / xoá số ở bàn phím Điện thoại (không gọi); ghi – dừng –
  xoá bản ghi thử trong Ghi âm (ba bản ghi cũ của anh còn nguyên); trượt mở khoá; kéo thanh độ sáng của Control Center lên
  rồi về mức cũ.

## D46. Phát hành: cập nhật OTA có chữ ký, `glass6ctl`, nguồn Cydia (20/11/2026)

Làm theo THIET-KE mục 10, mẫu là GramMini (đã qua một lượt kiểm bảo mật ở đó).

- **`g6update`** (`helper/g6update.c`, setuid root, viết lại từ `gmupdate.c`): bỏ hết môi trường của bên gọi, chỉ nhận lời gọi
  khi tiến trình cha là app Cài đặt hoặc SpringBoard, chép gói vào `/var/root/Glass6-update` (0700) và băm SHA-256 lúc chép,
  kiểm chữ ký RSA-3072 PKCS#1 v1.5 trên chính bản chép bằng chứng chỉ gắn sẵn (`helper/ota_cert.h` — sinh bằng
  `tools/gen_ota_cert.py`; khoá riêng chỉ ở máy phát hành), chỉ nhận gói `vn.glass6.tweak` có số bản mới hơn bản đang cài
  (so bằng `dpkg --compare-versions`), tách nền rồi `dpkg -i` và khởi động lại SpringBoard. Có chế độ `--verify` (root chạy
  tay) để thử chữ ký mà không cài. Khác bản gốc: không có bước «mở lại app» (đây là tweak).
- **`glass6ctl`** (`core/crates/g6-ctl` → `libg6_ctl.a` → `ctl/main.c`, cài ở `/usr/bin`, quyền mobile): **không dùng reqwest /
  tokio** như GramMini mà tự viết một lớp HTTPS GET tối thiểu (~400 dòng, `http.rs`) trên rustls + ring: một kết nối cho mỗi
  yêu cầu, theo chuyển tiếp (chỉ https), thân theo `Content-Length` / `chunked` / tới khi đóng, có giới hạn cỡ. Lý do: công cụ
  chỉ cần hai lệnh GET; bỏ được cả runtime bất đồng bộ (mio trên iOS 6 phải vá cách đánh thức — D8 của GramMini) và tệp chạy
  còn 1,0 MB. ring vẫn phải vá cho ARM 32-bit của Apple (`tools/rust/vendor-ring.sh`, `cargo-ios6.sh` tự làm lần đầu).
  Lệnh: `update check` (một dòng JSON, ghi `update.json`), `update download` (các dòng `progress <đã tải> <tổng>` rồi một
  dòng JSON có đường dẫn `.deb` + `.deb.sig`), `update clean`. Chỉ nhận tệp có link bắt đầu bằng
  `https://github.com/itovn/Glass6/releases/download/`, tên tệp chỉ gồm ký tự an toàn; kiểm kích thước và SHA-256 mà GitHub
  ghi cho tệp. Tách khỏi `libglass6core.dylib` để SpringBoard và các app không phải gánh TLS.
- **Nguồn thử** (feature `test-source` của `g6-ctl`): bản thử cho đổi nguồn bằng tệp `update-source.txt` / biến môi trường
  và nhận cả `http://` — để chạy trọn chuỗi với một máy chủ trong mạng nội bộ trước khi có bản phát hành thật.
  `tools/build.sh` chỉ bật cho bản thử; `tools/build-release.sh` kiểm lại là bản phát hành không còn (tìm chuỗi
  `update-source.txt` trong tệp chạy) và không còn công cụ thử.
- **Tự kiểm** (`tweak/SB/G6OTACheck.m`, khoá `updateAutoCheck`, mặc định bật): SpringBoard chạy `glass6ctl update check` ở
  luồng nền, tối đa một lần / 24 giờ (hỏng thì thử lại sau 2 giờ) — xét lúc SpringBoard mở được 2 phút và mỗi lần mở khoá
  (chỉ một lệnh `stat`). Có bản mới → một hộp thoại, một lần cho mỗi bản; «Cập nhật» mở Cài đặt › Glass 6. Tệp
  `update.stamp`: giờ sửa = lần hỏi gần nhất, nội dung = bản đã báo. SpringBoard không tự tải hay cài gì.
- **Bảng Cài đặt**: nhóm «Cập nhật» (công tắc tự kiểm, nút «Kiểm bản mới»); khi lượt kiểm gần nhất thấy bản mới hơn bản
  đang chạy thì có nhóm «Có bản mới x.y.z» ngay đầu bảng. Tải có tiến độ + nút «Huỷ», rồi gọi `g6update` (phải gọi từ tiến
  trình Cài đặt). Hộp thoại dùng đối tượng nhận nút gắn theo hộp thoại (rời màn Glass 6 giữa chừng không sập).
- **Số bản một chỗ**: `control`; `tools/set-version.sh` đặt cả `core/Cargo.toml` + `Cargo.lock` + `Info.plist`,
  `build-release.sh` từ chối dựng nếu lệch. Vỏ ObjC luôn truyền `--current <bản của gói>` cho `glass6ctl`.
- **Gói**: thêm khoá công khai của nguồn Cydia (`/etc/apt/trusted.gpg.d/vn.glass6.gpg`); lúc đóng gói bỏ quyền ghi của
  nhóm / người khác trên mọi tệp (máy dựng để umask 002 → tệp trong gói từng là 775 / 664).
- **Kịch bản phát hành** (`tools/`): `build-release.sh` (kiểm số bản, không còn mã thử, xuất danh sách ký hiệu),
  `sign-release.sh` (đối chiếu vân tay chứng chỉ với `ota_cert.h` rồi ký), `update-cydia-repo.sh` (giữ 3 bản, `Packages`
  không dấu), `sign-cydia-repo.sh` (`Release.gpg` + `InRelease`).
- **Đã thử trên iPhone 5 (iOS 6.1.4)** với máy chủ thử trong mạng nội bộ: SpringBoard báo «Glass 6 có bản mới 0.1.1» →
  «Cập nhật» mở Cài đặt › Glass 6 → nhóm «Có bản mới» → hộp xác nhận → tải (tiến độ chạy) → `g6update` kiểm chữ ký → `dpkg
  -i` → tự khởi động lại, máy lên 0.1.1; `update.json` được dọn. `g6update --verify`: gói đúng → đạt; gói bị sửa một byte →
  72; gọi từ SSH (không phải Cài đặt) → 69; tệp ngoài thư mục tải → 65. `glass6ctl` nói chuyện được với GitHub thật qua TLS
  trên iOS 6 (API + tệp đính kèm qua một lần chuyển tiếp). 126 ký hiệu của hai công cụ đều có trên máy.

## D8. Bộ dựng Theos (19/11/2026)

- Dự án con không thừa hưởng `TARGET` / `ARCHS` của Makefile cha → Theos dựng thêm arm64 và hỏng lúc liên kết. Mọi Makefile
  `include g6.mk` (armv7, iOS 6.0, .deb nén gzip, chữ ký SHA-1).
- Tệp đầu `Preferences` của Theos dùng `API_AVAILABLE(…)` (macro của SDK iOS 11+, SDK 9.3 chưa có) → `prefs/Makefile` định
  nghĩa rỗng bằng `-D`.
- Mở thẳng bảng Glass 6 từ SSH: `uiopen "prefs:root=Glass%206"`; vào luôn màn con: thêm `&path=<id của ô>` (vd
  `&path=services`).
- `svc/catalog.h` sinh trong `before-all` của `svc/Makefile` (cần `python3` trên máy dựng), không lên git.

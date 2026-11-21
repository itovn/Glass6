#!/usr/bin/env python3
"""Sinh en.html (bản tiếng Anh) của trang giới thiệu từ index.html: giữ nguyên khung + CSS, thay phần chữ theo bảng dưới.

    python3 tools/site-make-en.py <thư mục trang — bản làm việc của nhánh gh-pages>

Sửa chữ trong index.html thì sửa cặp tương ứng ở đây rồi chạy lại; câu nào không còn khớp thì script dừng và chỉ ra.
"""
import io
import os
import re
import sys

SITE = sys.argv[1] if len(sys.argv) > 1 else "."
s = io.open(os.path.join(SITE, "index.html"), encoding="utf-8").read()

PAIRS = [
    ('<html lang="vi">', '<html lang="en">'),
    ("<title>Glass 6 — Liquid Glass cho iOS 6</title>", "<title>Glass 6 — Liquid Glass for iOS 6</title>"),
    ('content="Glass 6: tweak đưa giao diện Liquid Glass (kiểu iOS 26 / iPadOS 26) lên iPhone 5, iPad mini 1 và iPad 4 chạy iOS 6 đã jailbreak. Kính trong, chế độ sáng / tối, Control Center, tự cập nhật."',
     'content="Glass 6: a tweak that brings the Liquid Glass look of iOS 26 / iPadOS 26 to jailbroken iPhone 5, iPad mini 1 and iPad 4 on iOS 6. Glass surfaces, light / dark mode, Control Center, signed over-the-air updates."'),
    ('<div class="lang"><a href="en.html">English</a></div>', '<div class="lang"><a href="index.html">Tiếng Việt</a></div>'),
    ('alt="Biểu tượng Glass 6"', 'alt="Glass 6 icon"'),
    ("<p>Giao diện <b>Liquid Glass</b> kiểu iOS 26 cho <b>iPhone 5</b>, <b>iPad mini 1</b> và <b>iPad 4</b> chạy iOS 6 đã jailbreak.</p>",
     "<p>The <b>Liquid Glass</b> look of iOS 26 for jailbroken <b>iPhone 5</b>, <b>iPad mini 1</b> and <b>iPad 4</b> on iOS 6.</p>"),
    ('<span class="ver">Bản 1.0.4</span>', '<span class="ver">Version 1.0.4</span>'),
    (">Thêm nguồn vào Cydia</a>", ">Add Source to Cydia</a>"),
    (">Tải tệp .deb</a>", ">Download the .deb</a>"),
    ('<p class="note">Nguồn Cydia: ', '<p class="note">Cydia source: '),
    ('alt="Màn khoá">Màn khoá</div>', 'alt="Lock screen">Lock screen</div>'),
    ('alt="Hộp thoại">Hộp thoại kính</div>', 'alt="Alert">Glass alerts</div>'),
    ('alt="Cài đặt">Cài đặt, chế độ tối</div>', 'alt="Settings">Settings, dark mode</div>'),
    ('alt="Điện thoại">Điện thoại</div>', 'alt="Phone">Phone</div>'),
    ('alt="Máy tính">Máy tính</div>', 'alt="Calculator">Calculator</div>'),
    ("<h2>Có gì</h2>", "<h2>What You Get</h2>"),
    ("<b>Màn hình chính</b><span>Dock kính, thư mục kính, ô tìm kiếm dạng viên; biểu tượng bốn kiểu (mặc định, tối, trong, nhuộm màu); kim của biểu tượng Đồng hồ chạy thật.</span>",
     "<b>Home screen</b><span>Glass dock, glass folders, a pill-shaped search field; four icon styles (default, dark, clear, tinted); a live Clock icon.</span>"),
    ("<b>Màn khoá</b><span>Đồng hồ lớn, rãnh trượt mở khoá bằng kính, thông báo dạng thẻ, dòng «Đã sạc N%» thay cho hình viên pin.</span>",
     "<b>Lock screen</b><span>Large clock, glass slide-to-unlock track, notification cards, a “Charged N%” line instead of the big battery picture.</span>"),
    ("<span>iOS 6 chưa có — Glass 6 thêm vào: Máy bay, dữ liệu di động, Wi-Fi, Bluetooth, Không làm phiền, khoá xoay, sáng / tối, đèn pin, độ sáng, âm lượng, nhạc đang phát. Mở bằng cách kéo từ mép trên xuống ở phía bên phải.</span>",
     "<span>iOS 6 never had one — Glass 6 adds it: Airplane Mode, cellular data, Wi-Fi, Bluetooth, Do Not Disturb, rotation lock, light / dark, flashlight, brightness, volume, now playing. Pull down from the right side of the top edge.</span>"),
    ("<b>Thông báo, hộp thoại, bảng chọn</b><span>Băng thông báo dạng thẻ nổi, Trung tâm thông báo, hộp thoại, bảng chọn và bảng âm lượng đều là kính.</span>",
     "<b>Notifications, alerts, action sheets</b><span>Floating banner cards, Notification Center, alerts, action sheets and the volume HUD are all glass.</span>"),
    ("<b>Khay đa nhiệm</b><span>iPhone: các thẻ ảnh chụp app, vuốt lên để đóng. iPad: dải biểu tượng trên nền kính.</span>",
     "<b>App switcher</b><span>iPhone: app snapshot cards, swipe up to quit. iPad: the icon strip on glass.</span>"),
    ("<b>Trong app</b><span>Thanh điều hướng, thanh thẻ nổi, bảng, công tắc, thanh trượt, bàn phím — kiểu mới, theo sáng / tối. Vẽ lại riêng: Cài đặt, Đồng hồ, Ghi chú, Lời nhắc, Lịch, Danh bạ, Ảnh, Tin nhắn; trên iPhone thêm Điện thoại, Máy tính, La bàn, Ghi âm. App không phải của Apple giữ nguyên.</span>",
     "<b>Inside apps</b><span>Navigation bars, floating tab bars, tables, switches, sliders, keyboard — restyled, following light / dark. Redrawn individually: Settings, Clock, Notes, Reminders, Calendar, Contacts, Photos, Messages; on iPhone also Phone, Calculator, Compass, Voice Memos. Third-party apps are left untouched.</span>"),
    ("<b>Âm lịch trong app Lịch</b><span>Ngày âm nhỏ dưới mỗi ngày dương, ngày hoàng đạo, mùng 1, rằm, lễ âm lịch; ngày đang chọn có can chi, thần trực ngày, giờ hoàng đạo, tiết khí. Lịch tháng và màn Ngày vẽ lại kiểu iOS 26 — iPhone và iPad.</span>",
     "<b>Lunar calendar in Calendar</b><span>Vietnamese lunar dates under each solar date, auspicious (hoàng đạo) days, the 1st and 15th of each lunar month and lunar holidays; the selected day shows its sexagenary name, ruling spirit, auspicious hours and solar term. Month and Day views redrawn in the iOS 26 style — iPhone and iPad.</span>"),
    ("<b>Sáng / tối</b><span>Chế độ sáng, tối, hoặc tự đổi theo giờ — cả màn hình chính lẫn trong app.</span>",
     "<b>Light / dark</b><span>Light, dark, or automatic by time of day — on the Home screen and inside apps.</span>"),
    ("<b>Thanh trạng thái</b><span>Pin vẽ lại (tia sét xanh khi sạc), giờ nằm bên trái, ẩn tên nhà mạng; dải hiệu suất nhỏ: CPU, RAM, mạng.</span>",
     "<b>Status bar</b><span>Redrawn battery (green bolt while charging), time on the left, hidden carrier name; a small performance strip: CPU, RAM, network.</span>"),
    ("<b>Nút AssistiveTouch riêng</b><span>Nút nổi và bảng chín ô bằng kính, tự chọn chức năng cho từng ô: màn hình chính, đa nhiệm, Control Center, khoá máy, chụp màn hình, âm lượng, respring…</span>",
     "<b>Its own AssistiveTouch button</b><span>A floating button with a nine-slot glass menu; pick the action for each slot: Home, app switcher, Control Center, lock, screenshot, volume, respring…</span>"),
    ("<b>Dịch vụ hệ thống</b><span>Tắt các dịch vụ nền của iOS 6 đã ngừng hoạt động từ lâu, chặn cập nhật iOS — từng mục có công tắc, bật lại được.</span>",
     "<b>System services</b><span>Turn off iOS 6 background services that stopped working long ago, block iOS updates — each has its own switch and can be turned back on.</span>"),
    ("<b>Tự cập nhật</b><span>Tự báo bản mới, tải và cài ngay trong Cài đặt › Glass 6. Gói chỉ được cài khi chữ ký số đúng.</span>",
     "<b>Over-the-air updates</b><span>Tells you about new versions, downloads and installs them in Settings › Glass 6. A package is installed only if its digital signature is valid.</span>"),
    ('<p class="note">Mọi thành phần đều có công tắc riêng trong Cài đặt › Glass 6. Giao diện tiếng Việt và tiếng Anh.</p>',
     '<p class="note">Every part has its own switch in Settings › Glass 6. English and Vietnamese interface.</p>'),
    ("<h2>Trên iPhone 5</h2>", "<h2>On iPhone 5</h2>"),
    ('alt="Màn hình chính">Màn hình chính</div>', 'alt="Home screen">Home screen</div>'),
    ('alt="Thư mục">Thư mục kính</div>', 'alt="Folder">Glass folders</div>'),
    ('alt="Nút AssistiveTouch">Nút AssistiveTouch</div>', 'alt="AssistiveTouch button">AssistiveTouch menu</div>'),
    ("<h2>Sáng / tối, kiểu biểu tượng</h2>", "<h2>Light / Dark, Icon Styles</h2>"),
    ('alt="Cài đặt, chế độ sáng">Chế độ sáng</div>', 'alt="Settings, light mode">Light mode</div>'),
    ('alt="Điện thoại, chế độ sáng">Điện thoại, sáng</div>', 'alt="Phone, light mode">Phone, light</div>'),
    ('alt="Ghi âm">Ghi âm</div>', 'alt="Voice Memos">Voice Memos</div>'),
    ('alt="Biểu tượng trong">Biểu tượng trong</div>', 'alt="Clear icons">Clear icons</div>'),
    ('alt="Biểu tượng tối">Biểu tượng tối</div>', 'alt="Dark icons">Dark icons</div>'),
    ('alt="Biểu tượng nhuộm màu">Biểu tượng nhuộm màu</div>', 'alt="Tinted icons">Tinted icons</div>'),
    ('<p class="note">Ảnh chụp trên iPhone 5 (iOS 6.1.4). iPad mini 1 có cùng các thành phần, bố cục theo kiểu iPadOS 26.</p>',
     '<p class="note">Screenshots from an iPhone 5 (iOS 6.1.4). iPad mini 1 has the same parts, laid out the iPadOS 26 way.</p>'),
    ("<h2>Cài đặt</h2>", "<h2>Install</h2>"),
    ("<b>1. Thêm nguồn Cydia</b><span>Mở Cydia → Nguồn → Sửa → Thêm, nhập <code>https://itovn.github.io/Glass6/cydia/</code> (hoặc chạm nút «Thêm nguồn vào Cydia» ở trên).</span>",
     "<b>1. Add the Cydia source</b><span>Open Cydia → Sources → Edit → Add and enter <code>https://itovn.github.io/Glass6/cydia/</code> (or tap “Add Source to Cydia” above).</span>"),
    ("<b>2. Cài Glass 6</b><span>Tìm «Glass 6» → Cài đặt → Xác nhận, xong bấm «Restart SpringBoard».</span>",
     "<b>2. Install Glass 6</b><span>Search for “Glass 6” → Install → Confirm, then tap “Restart SpringBoard”.</span>"),
    ("<b>3. Tuỳ chỉnh</b><span>Mở Cài đặt › Glass 6: chọn sáng / tối, kiểu biểu tượng, bật tắt từng thành phần.</span>",
     "<b>3. Make it yours</b><span>Open Settings › Glass 6: choose light / dark, the icon style, and switch each part on or off.</span>"),
    ('<p class="note">Lần đầu thêm nguồn, Cydia có thể báo «NO_PUBKEY» ở màn làm mới — bình thường: máy chưa có khoá của '
     'nguồn, khoá nằm trong gói Glass 6; cài xong là hết báo. Các bản sau tự cập nhật: Cài đặt › Glass 6 › Kiểm bản mới.</p>',
     '<p class="note">The first time you add the source, Cydia may show “NO_PUBKEY” on the refresh screen — that is expected: '
     'the device does not have the source\'s key yet, it ships inside the Glass 6 package, and the warning is gone once Glass 6 '
     'is installed. Later versions update over the air: Settings › Glass 6 › Check for Update.</p>'),
    ("<h2>Máy chạy được</h2>", "<h2>Supported Devices</h2>"),
    ("<span><b>iPhone 5</b>, <b>iPad mini 1</b> và <b>iPad 4</b>, iOS 6.0 – 6.1.x đã jailbreak (cần MobileSubstrate và PreferenceLoader). Đã thử trên iPhone 5 (iOS 6.1.4), iPad mini 1 và iPad 4 (iOS 6.1.3). Trên mẫu máy khác Glass 6 không thay đổi gì; các mẫu khác sẽ được bổ sung dần.</span>",
     "<span><b>iPhone 5</b>, <b>iPad mini 1</b> and <b>iPad 4</b>, jailbroken iOS 6.0 – 6.1.x (requires MobileSubstrate and PreferenceLoader). Tested on iPhone 5 (iOS 6.1.4), iPad mini 1 and iPad 4 (iOS 6.1.3). On any other model Glass 6 changes nothing; more models will be added over time.</span>"),
    ("<h2>An toàn</h2>", "<h2>Safety</h2>"),
    ('<b>Bật 4G trên iPhone 5</b><span>LTE cho SIM MobiFone, Viettel, VinaPhone bằng phần LTE có sẵn trong iOS 6; APN và MMS giữ như trước khi bật; tắt công tắc là về đúng 3G gốc. Gọi điện vẫn qua 3G (iOS 6 không có VoLTE).</span>',
     '<b>4G on iPhone 5</b><span>LTE for MobiFone, Viettel and VinaPhone SIMs using the LTE support already in iOS 6; APN and MMS settings stay as they were; switching it off restores the original 3G setup. Calls still go over 3G (iOS 6 has no VoLTE).</span>'),
    ("<span>Glass 6 không sửa tệp nào của hệ thống — gỡ gói là sạch. Ngoại lệ duy nhất là «Bật 4G» (iPhone 5, phải tự bật): thêm gói nhà mạng và đổi ba liên kết mã nhà mạng; tắt công tắc hoặc gỡ gói thì trả lại nguyên như iOS 6 gốc. Nếu màn hình chính khởi động 3 lần liền mà Glass 6 chưa chạy ổn, Glass 6 tự tắt. Tắt tay qua SSH: <code>touch /var/mobile/Library/Glass6/off</code> rồi khởi động lại SpringBoard.</span>",
     "<span>Glass 6 modifies no system file — removing the package leaves nothing behind. The only exception is “Enable 4G” (iPhone 5, off until you turn it on): it adds carrier bundles and changes three carrier-code links; switching it off or removing the package puts back the original iOS 6 setup. If the Home screen restarts 3 times in a row before Glass 6 runs stably, Glass 6 turns itself off. To turn it off by hand over SSH: <code>touch /var/mobile/Library/Glass6/off</code>, then restart SpringBoard.</span>"),
    ("<h2>Mã nguồn</h2>", "<h2>Source Code</h2>"),
    ("<b>Mã nguồn mở — GPL-3.0</b><span><a href=\"https://github.com/itovn/Glass6\">github.com/itovn/Glass6</a> · lõi Rust (dựng vật liệu kính), vỏ Objective-C nạp bằng MobileSubstrate.</span>",
     "<b>Open source — GPL-3.0</b><span><a href=\"https://github.com/itovn/Glass6\">github.com/itovn/Glass6</a> · a Rust core (renders the glass material) with an Objective-C shell loaded by MobileSubstrate.</span>"),
    ("Glass 6 là dự án độc lập, không liên quan tới Apple. «Liquid Glass», iOS, iPadOS là nhãn hiệu của Apple Inc.<br>",
     "Glass 6 is an independent project and is not affiliated with Apple. “Liquid Glass”, iOS and iPadOS are trademarks of Apple Inc.<br>"),
    ("Báo lỗi, góp ý: ", "Bug reports and feedback: "),
]
for old, new in PAIRS:
    assert s.count(old) == 1, ("không thấy / trùng", old[:70], s.count(old))
    s = s.replace(old, new, 1)
# Hai chỗ «Control Center» là tên riêng — giữ nguyên. Không được còn chữ có dấu tiếng Việt ngoài nút đổi ngôn ngữ.
left = [m.group(0) for m in re.finditer(r"[^<>\n]*[ăâđêôơưáàảãạéèẻẽẹíìỉĩịóòỏõọúùủũụýỳỷỹỵ][^<>\n]*", s) if "Tiếng Việt" not in m.group(0)]
left = [l for l in left if not l.strip().startswith(("/*", "<!--", "html", "body"))]
print("còn tiếng Việt:", left[:10])
io.open(os.path.join(SITE, "en.html"), "w", encoding="utf-8", newline="\n").write(s)
print("đã ghi en.html")

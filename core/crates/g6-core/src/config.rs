//! Cấu hình: lược đồ, giá trị mặc định, kiểm và kẹp.
//!
//! Nguồn là tệp plist phẳng do Cài đặt ghi (`/var/mobile/Library/Preferences/vn.glass6.plist`) — vỏ ObjC đọc thành JSON rồi
//! đưa sang. Lõi là nơi duy nhất biết giá trị mặc định: khoá thiếu, sai kiểu hay ngoài tầm đều về mặc định / bị kẹp, không
//! báo lỗi (tệp cấu hình hỏng không được làm tweak ngừng chạy).

use serde::Serialize;
use serde_json::Value;

use crate::assist::Assist;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Appearance {
    Light,
    Dark,
    /// Tối trong khoảng `dark_from` – `dark_to`.
    Auto,
}

#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct Config {
    /// Công tắc tổng.
    pub enabled: bool,
    pub appearance: Appearance,
    /// Phút trong ngày (0–1439) bắt đầu / kết thúc chế độ tối khi `appearance` = Auto.
    pub dark_from: u32,
    pub dark_to: u32,
    /// Độ mờ của nền dưới kính 0–1.
    pub blur: f32,
    /// Độ trong 0–1: càng cao lớp màu phủ càng mỏng.
    pub clarity: f32,
    /// Cường độ viền sáng 0–1.
    pub rim: f32,
    /// Tăng bão hoà màu nền dưới kính 0–1.
    pub vibrancy: f32,
    /// Màu nhuộm kính (R, G, B); `None` = trắng / đen theo chế độ.
    pub tint: Option<[u8; 3]>,
    /// Giảm hiệu ứng: bỏ khúc xạ viền, vệt sáng.
    pub reduce: bool,
    /// Kiểu biểu tượng: 0 mặc định, 1 tối, 2 trong, 3 nhuộm màu.
    pub icon_style: u32,
    /// Màu nhuộm cho kiểu biểu tượng «nhuộm màu»; `None` = xanh dương.
    pub icon_tint: Option<[u8; 3]>,
    /// Màn khoá: ẩn nút khung ảnh (hình bông hoa) ở góc phải thanh mở khoá.
    pub lock_hide_frame: bool,
    /// Màn khoá: ẩn mục «Chưa cài đặt Thẻ SIM» trong danh sách thông báo.
    pub lock_hide_no_sim: bool,
    /// Màn khoá: ẩn hình viên pin lớn lúc đang sạc (thay bằng dòng «Đã sạc N%» hiện vài giây ở chỗ dòng ngày, kiểu iOS 26).
    pub lock_hide_battery: bool,
    /// Màn hình chính: ẩn biểu tượng Quầy báo (Newsstand).
    pub hide_newsstand: bool,
    /// Thanh trạng thái: giờ và mặt trăng «Không làm phiền» nằm bên trái (kiểu iPadOS) thay vì ở giữa.
    pub status_time_left: bool,
    /// Thanh trạng thái: ẩn chữ «Không có SIM» (tên nhà mạng khi có SIM vẫn hiện).
    pub status_hide_no_sim: bool,
    /// Thanh trạng thái: hình pin vẽ lại, tia sét xanh lá khi đang cắm sạc.
    pub status_battery: bool,
    /// Thanh trạng thái: cột sóng và biểu tượng mạng (Wi-Fi / 3G) dồn sang bên phải, cạnh pin (kiểu iOS 26 của iPhone).
    pub status_signal_right: bool,
    /// Thanh trạng thái: ẩn tên nhà mạng (kiểu iOS 26 của iPhone — chỉ còn cột sóng).
    pub status_hide_carrier: bool,
    /// Dải hiệu suất: cập nhật mỗi chừng này giây (1–10).
    pub perf_interval: u32,
    /// Dải hiệu suất nằm ở đâu: 0 = trên cùng, ngang hàng thanh trạng thái (cần giờ nằm bên trái); 1 = dưới thanh trạng thái.
    pub perf_position: u32,
    /// Dải hiệu suất thu gọn trên thanh trạng thái của iPhone: 0 = hai hàng (CPU, RAM, mạng), 1 = một hàng (CPU, RAM).
    pub perf_style: u32,
    /// Khay đa nhiệm dạng thẻ ảnh chụp (kiểu iOS 26 của iPhone) thay cho dải biểu tượng; chỉ iPhone có.
    pub switcher_cards: bool,
    /// Control Center tự ẩn sau chừng này giây không ai đụng tới; 0 = không tự ẩn. Tối đa 120.
    pub cc_timeout: u32,
    /// Tự kiểm bản mới của Glass 6 (SpringBoard hỏi GitHub tối đa một lần mỗi 24 giờ). Mặc định bật.
    pub update_auto_check: bool,
    /// Nút AssistiveTouch của Glass 6 (bật / tắt ở `features.assist`).
    pub assist: Assist,
    pub features: Features,
}

/// Công tắc từng thành phần. Thành phần chưa làm vẫn có khoá để cấu hình cũ không mất khi lên bản mới.
#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct Features {
    pub dock: bool,
    pub icons: bool,
    pub folders: bool,
    /// Biểu tượng Đồng hồ sống (kim chạy theo giờ máy).
    pub clock: bool,
    /// Khay đa nhiệm.
    pub switcher: bool,
    pub status_bar: bool,
    pub lock_screen: bool,
    pub notifications: bool,
    pub alerts: bool,
    pub hud: bool,
    pub control_center: bool,
    /// Công tắc chung của phần nạp vào app (Glass6UI). Tắt thì không app nào bị đổi giao diện.
    pub apps: bool,
    /// Trong app: thanh điều hướng, thanh công cụ, thanh thẻ, ô tìm kiếm.
    pub bars: bool,
    /// Trong app: nền và ô của bảng kiểu nhóm.
    pub tables: bool,
    /// Trong app: công tắc, thanh trượt, nút chọn đoạn.
    pub controls: bool,
    /// App Cài đặt: biểu tượng các mục kiểu ô màu bo góc.
    pub settings_icons: bool,
    /// Phần vẽ lại riêng cho từng app của Apple (thanh thẻ của app Đồng hồ…) — tách khỏi kiểu chung của thanh / bảng / nút.
    pub app_skins: bool,
    /// Bàn phím tối ở chế độ tối (SpringBoard và các app trong phạm vi của Glass6UI).
    pub keyboard: bool,
    /// Ô tìm kiếm của trang Tìm kiếm (Spotlight) trên màn hình chính: viên kính thay viên trắng bóng.
    pub search: bool,
    /// Nút AssistiveTouch của Glass 6 (thay nút của iOS). Mặc định tắt: bật là có thêm một nút nổi trên màn hình.
    pub assist: bool,
    /// Dải hiệu suất hệ thống (CPU, RAM, đĩa, mạng) trên màn hình chính. Mặc định tắt.
    pub perf: bool,
    /// App Lịch: âm lịch Việt Nam (ngày âm dưới ngày dương, ngày hoàng đạo, thẻ chi tiết ngày). Đi cùng «app_skins».
    pub lunar: bool,
}

impl Default for Config {
    fn default() -> Config {
        Config {
            enabled: true,
            appearance: Appearance::Light,
            dark_from: 19 * 60,
            dark_to: 6 * 60,
            blur: 0.6,
            clarity: 0.55,
            rim: 0.7,
            vibrancy: 0.5,
            tint: None,
            reduce: false,
            icon_style: 0,
            icon_tint: None,
            lock_hide_frame: true,
            lock_hide_no_sim: true,
            lock_hide_battery: true,
            hide_newsstand: false,
            status_time_left: true,
            status_hide_no_sim: true,
            status_battery: true,
            status_signal_right: false,
            status_hide_carrier: false,
            perf_interval: 2,
            perf_position: 0,
            perf_style: 0,
            switcher_cards: false,
            cc_timeout: 8,
            update_auto_check: true,
            assist: Assist::default(),
            features: Features::default(),
        }
    }
}

impl Default for Features {
    fn default() -> Features {
        Features {
            dock: true,
            icons: true,
            folders: true,
            clock: true,
            switcher: true,
            status_bar: true,
            lock_screen: true,
            notifications: true,
            alerts: true,
            hud: true,
            control_center: true,
            apps: true,
            bars: true,
            tables: true,
            controls: true,
            settings_icons: true,
            app_skins: true,
            keyboard: true,
            search: true,
            assist: false,
            perf: false,
            lunar: true,
        }
    }
}

/// Tên mẫu máy mà vỏ ObjC gửi kèm `config.set` (xem tweak/Common/G6Device.c).
pub const DEVICE_PHONE5: &str = "iphone-5";

impl Config {
    /// Cấu hình mặc định của một mẫu máy. `Config::default()` là của iPad mini 1 (mẫu đầu tiên); mẫu khác chỉ khai phần lệch.
    pub fn default_for(device: &str) -> Config {
        let mut c = Config::default();
        if device == DEVICE_PHONE5 {
            // iOS 26 trên iPhone: giờ bên trái; sóng + mạng + pin bên phải; không hiện tên nhà mạng
            c.status_signal_right = true;
            c.status_hide_carrier = true;
            c.switcher_cards = true;
        }
        c
    }

    /// Đọc từ từ điển phẳng của Cài đặt (mặc định của iPad mini 1). Bất cứ thứ gì không phải từ điển → cấu hình mặc định.
    pub fn from_prefs(v: &Value) -> Config {
        Config::from_prefs_for(v, "")
    }

    /// Như trên, với mặc định của mẫu máy `device`.
    pub fn from_prefs_for(v: &Value, device: &str) -> Config {
        let d = Config::default_for(device);
        let f = Features::default();
        Config {
            enabled: get_bool(v, "enabled", d.enabled),
            appearance: match v.get("appearance") {
                Some(Value::String(s)) => match s.as_str() {
                    "dark" => Appearance::Dark,
                    "auto" => Appearance::Auto,
                    _ => Appearance::Light,
                },
                // Ô chọn của Cài đặt lưu số
                Some(n) => match as_f64(n).map(|x| x as i64) {
                    Some(1) => Appearance::Dark,
                    Some(2) => Appearance::Auto,
                    _ => Appearance::Light,
                },
                None => d.appearance,
            },
            dark_from: get_minutes(v, "darkFrom", d.dark_from),
            dark_to: get_minutes(v, "darkTo", d.dark_to),
            blur: get_unit(v, "glassBlur", d.blur),
            clarity: get_unit(v, "glassClarity", d.clarity),
            rim: get_unit(v, "glassRim", d.rim),
            vibrancy: get_unit(v, "glassVibrancy", d.vibrancy),
            tint: v.get("glassTint").and_then(Value::as_str).and_then(parse_hex),
            reduce: get_bool(v, "reduceEffects", d.reduce),
            icon_style: match v.get("iconStyle").and_then(as_f64) {
                Some(x) if x.is_finite() && (0.0..=3.0).contains(&x) => x as u32,
                _ => d.icon_style,
            },
            icon_tint: v.get("iconTint").and_then(Value::as_str).and_then(parse_hex),
            lock_hide_frame: get_bool(v, "lockHidePictureFrame", d.lock_hide_frame),
            lock_hide_no_sim: get_bool(v, "lockHideNoSIM", d.lock_hide_no_sim),
            lock_hide_battery: get_bool(v, "lockHideBattery", d.lock_hide_battery),
            hide_newsstand: get_bool(v, "hideNewsstand", d.hide_newsstand),
            status_time_left: get_bool(v, "statusTimeLeft", d.status_time_left),
            status_hide_no_sim: get_bool(v, "statusHideNoSIM", d.status_hide_no_sim),
            status_battery: get_bool(v, "statusBattery", d.status_battery),
            status_signal_right: get_bool(v, "statusSignalRight", d.status_signal_right),
            status_hide_carrier: get_bool(v, "statusHideCarrier", d.status_hide_carrier),
            perf_interval: match v.get("perfInterval").and_then(as_f64) {
                Some(x) if x.is_finite() => (x as i64).clamp(1, 10) as u32,
                _ => d.perf_interval,
            },
            perf_position: match v.get("perfPosition").and_then(as_f64) {
                Some(x) if x.is_finite() && x >= 0.5 => 1,
                Some(_) => 0,
                _ => d.perf_position,
            },
            switcher_cards: get_bool(v, "switcherCards", d.switcher_cards),
            perf_style: match v.get("perfStyle").and_then(as_f64) {
                Some(x) if x.is_finite() && x >= 0.5 => 1,
                Some(_) => 0,
                _ => d.perf_style,
            },
            update_auto_check: get_bool(v, "updateAutoCheck", d.update_auto_check),
            cc_timeout: match v.get("ccTimeout").and_then(as_f64) {
                Some(x) if x.is_finite() && x >= 0.0 => (x as u32).min(120),
                _ => d.cc_timeout,
            },
            assist: Assist::from_prefs(v),
            features: Features {
                dock: get_bool(v, "featDock", f.dock),
                icons: get_bool(v, "featIcons", f.icons),
                folders: get_bool(v, "featFolders", f.folders),
                clock: get_bool(v, "featClock", f.clock),
                switcher: get_bool(v, "featSwitcher", f.switcher),
                status_bar: get_bool(v, "featStatusBar", f.status_bar),
                lock_screen: get_bool(v, "featLockScreen", f.lock_screen),
                notifications: get_bool(v, "featNotifications", f.notifications),
                alerts: get_bool(v, "featAlerts", f.alerts),
                hud: get_bool(v, "featHUD", f.hud),
                control_center: get_bool(v, "featControlCenter", f.control_center),
                apps: get_bool(v, "featApps", f.apps),
                bars: get_bool(v, "featBars", f.bars),
                tables: get_bool(v, "featTables", f.tables),
                controls: get_bool(v, "featControls", f.controls),
                settings_icons: get_bool(v, "featSettingsIcons", f.settings_icons),
                app_skins: get_bool(v, "featAppSkins", f.app_skins),
                keyboard: get_bool(v, "featKeyboard", f.keyboard),
                search: get_bool(v, "featSearch", f.search),
                assist: get_bool(v, "featAssist", f.assist),
                perf: get_bool(v, "featPerf", f.perf),
                lunar: get_bool(v, "featLunar", f.lunar),
            },
        }
    }

    /// Đang ở chế độ tối? `minutes` = phút trong ngày theo giờ máy.
    pub fn is_dark(&self, minutes: u32) -> bool {
        match self.appearance {
            Appearance::Light => false,
            Appearance::Dark => true,
            Appearance::Auto => {
                let m = minutes % 1440;
                let (a, b) = (self.dark_from, self.dark_to);
                if a == b {
                    false
                } else if a < b {
                    m >= a && m < b
                } else {
                    // Khoảng vắt qua nửa đêm, vd 19:00 → 6:00
                    m >= a || m < b
                }
            }
        }
    }
}

fn as_f64(v: &Value) -> Option<f64> {
    match v {
        Value::Number(n) => n.as_f64(),
        Value::Bool(b) => Some(if *b { 1.0 } else { 0.0 }),
        _ => None,
    }
}

fn get_bool(v: &Value, key: &str, default: bool) -> bool {
    match v.get(key) {
        Some(Value::Bool(b)) => *b,
        // plist qua JSON: công tắc có thể thành số 0 / 1
        Some(Value::Number(n)) => n.as_f64().map(|x| x != 0.0).unwrap_or(default),
        _ => default,
    }
}

fn get_unit(v: &Value, key: &str, default: f32) -> f32 {
    match v.get(key).and_then(as_f64) {
        Some(x) if x.is_finite() => (x as f32).clamp(0.0, 1.0),
        _ => default,
    }
}

fn get_minutes(v: &Value, key: &str, default: u32) -> u32 {
    match v.get(key).and_then(as_f64) {
        Some(x) if x.is_finite() && x >= 0.0 => (x as u32) % 1440,
        _ => default,
    }
}

/// `#RRGGBB` hoặc `RRGGBB`.
fn parse_hex(s: &str) -> Option<[u8; 3]> {
    let s = s.trim().trim_start_matches('#');
    if s.len() != 6 || !s.is_ascii() {
        return None;
    }
    let n = u32::from_str_radix(s, 16).ok()?;
    Some([(n >> 16) as u8, (n >> 8) as u8, n as u8])
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn thieu_het_thi_mac_dinh() {
        assert_eq!(Config::from_prefs(&json!({})), Config::default());
        assert_eq!(Config::from_prefs(&json!(null)), Config::default());
        assert_eq!(Config::from_prefs(&json!([1, 2, 3])), Config::default());
    }

    #[test]
    fn sai_kieu_va_ngoai_tam() {
        let c = Config::from_prefs(&json!({
            "enabled": "có", "glassBlur": 7.5, "glassClarity": -3, "glassRim": "x",
            "appearance": 99, "darkFrom": 5000, "glassTint": "xanh", "featDock": 0
        }));
        assert!(c.enabled, "sai kiểu → mặc định");
        assert_eq!(c.blur, 1.0);
        assert_eq!(c.clarity, 0.0);
        assert_eq!(c.rim, Config::default().rim);
        assert_eq!(c.appearance, Appearance::Light);
        assert_eq!(c.dark_from, 5000 % 1440);
        assert_eq!(c.tint, None);
        assert!(!c.features.dock, "số 0 là tắt");
    }

    #[test]
    fn doc_dung_gia_tri() {
        let c = Config::from_prefs(&json!({
            "enabled": false, "appearance": 1, "glassTint": "#3478F6", "reduceEffects": true
        }));
        assert!(!c.enabled);
        assert_eq!(c.appearance, Appearance::Dark);
        assert_eq!(c.tint, Some([0x34, 0x78, 0xF6]));
        assert!(c.reduce);
        assert_eq!(Config::from_prefs(&json!({"appearance": "auto"})).appearance, Appearance::Auto);
    }

    #[test]
    fn device_defaults() {
        // iPad mini 1 (mặc định): tên mạng và sóng ở chỗ cũ; iPhone 5: sóng sang phải, ẩn tên mạng — và người dùng vẫn đổi được
        let pad = Config::from_prefs_for(&json!({}), "ipad-mini-1");
        assert!(!pad.status_signal_right && !pad.status_hide_carrier);
        assert_eq!(pad, Config::default());
        let phone = Config::from_prefs_for(&json!({}), DEVICE_PHONE5);
        assert!(phone.status_signal_right && phone.status_hide_carrier);
        assert!(phone.switcher_cards && !pad.switcher_cards);
        let chosen = Config::from_prefs_for(&json!({"statusHideCarrier": false}), DEVICE_PHONE5);
        assert!(chosen.status_signal_right && !chosen.status_hide_carrier);
    }

    #[test]
    fn tu_dong_vat_qua_nua_dem() {
        let mut c = Config::default();
        c.appearance = Appearance::Auto;
        assert!(c.is_dark(23 * 60));
        assert!(c.is_dark(2 * 60));
        assert!(!c.is_dark(12 * 60));
        assert!(c.is_dark(19 * 60));
        assert!(!c.is_dark(6 * 60));
        c.dark_from = 60;
        c.dark_to = 120;
        assert!(c.is_dark(90) && !c.is_dark(130));
        c.dark_to = 60;
        assert!(!c.is_dark(60));
    }
}

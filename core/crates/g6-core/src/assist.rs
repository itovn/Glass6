//! Nút AssistiveTouch của Glass 6: danh mục chức năng gán được vào bảng nút / thao tác trên nút, và phần cấu hình.
//!
//! Danh mục nằm trong lõi để bảng Cài đặt (liệt kê cho người dùng chọn) và SpringBoard (thực thi) dùng chung một nguồn, và để
//! cấu hình hỏng / từ bản cũ (mã chức năng không còn) rơi về giá trị an toàn. Lõi không thực thi gì — vỏ ObjC tra mã rồi gọi
//! hàm của SpringBoard.

use serde::Serialize;
use serde_json::Value;

/// Số ô tối đa của bảng nút.
pub const MAX_SLOTS: usize = 9;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
pub struct Action {
    /// Mã ổn định — lưu trong cấu hình.
    pub id: &'static str,
    /// Tên đầy đủ (bảng Cài đặt).
    pub title: &'static str,
    /// Tên ngắn dưới ô trong bảng nút.
    pub short: &'static str,
    /// Gán được vào một ô của bảng nút.
    pub slot: bool,
    /// Gán được cho thao tác trên nút (chạm, chạm hai lần, nhấn giữ).
    pub gesture: bool,
}

const fn action(id: &'static str, title: &'static str, short: &'static str, slot: bool, gesture: bool) -> Action {
    Action { id, title, short, slot, gesture }
}

/// Không làm gì / ô để trống.
pub const NONE: &str = "none";
/// Mở bảng nút (chỉ dùng cho thao tác trên nút).
pub const MENU: &str = "menu";

pub const ACTIONS: &[Action] = &[
    action(NONE, "Không làm gì", "", true, true),
    action(MENU, "Mở bảng nút", "", false, true),
    action("home", "Màn hình chính", "Màn hình chính", true, true),
    action("switcher", "Đa nhiệm", "Đa nhiệm", true, true),
    action("notifications", "Trung tâm thông báo", "Thông báo", true, true),
    action("controlcenter", "Control Center", "Control Center", true, true),
    action("lock", "Khoá màn hình", "Khoá màn hình", true, true),
    action("screenshot", "Chụp màn hình", "Chụp màn hình", true, true),
    action("volup", "Tăng âm lượng", "Tăng âm", true, false),
    action("voldown", "Giảm âm lượng", "Giảm âm", true, false),
    action("mute", "Bật / tắt tiếng", "Tắt tiếng", true, true),
    action("rotate", "Khoá xoay màn hình", "Khoá xoay", true, true),
    action("dark", "Đổi sáng / tối", "Sáng / Tối", true, true),
    action("brightup", "Tăng độ sáng", "Tăng sáng", true, false),
    action("brightdown", "Giảm độ sáng", "Giảm sáng", true, false),
    action("respring", "Respring (khởi động lại SpringBoard)", "Respring", true, true),
    action("reboot", "Khởi động lại máy", "Khởi động lại", true, false),
    action("poweroff", "Tắt máy", "Tắt máy", true, false),
];

/// Bố cục mặc định của 9 ô — lưới 3×3 như bảng AssistiveTouch quen thuộc. Bảy ô đầu giữ nguyên như bản trước: đổi mặc định
/// của một ô là đổi luôn ô đó trên máy của người chưa tự chọn ô ấy (đã lỡ làm một ô thành trùng).
pub const DEFAULT_SLOTS: [&str; MAX_SLOTS] =
    ["notifications", "controlcenter", "home", "switcher", "lock", "screenshot", "respring", "rotate", "reboot"];

/// Số ô hiện mặc định.
pub const DEFAULT_COUNT: u32 = 9;

/// Bảng nút tự đóng sau chừng này giây không ai bấm (0 = không tự đóng).
pub const DEFAULT_MENU_TIMEOUT: u32 = 5;

pub fn find(id: &str) -> Option<&'static Action> {
    ACTIONS.iter().find(|a| a.id == id)
}

/// Mã hợp lệ cho một ô của bảng nút; mã lạ → `fallback`.
fn slot_id(id: Option<&str>, fallback: &'static str) -> &'static str {
    match id.and_then(find) {
        Some(a) if a.slot => a.id,
        _ => fallback,
    }
}

/// Mã hợp lệ cho một thao tác trên nút; mã lạ → `fallback`.
fn gesture_id(id: Option<&str>, fallback: &'static str) -> &'static str {
    match id.and_then(find) {
        Some(a) if a.gesture => a.id,
        _ => fallback,
    }
}

/// Cấu hình của nút (đã kiểm). Công tắc bật / tắt nằm ở `Features::assist`.
#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct Assist {
    /// Số ô đang dùng của bảng nút, 1–8.
    pub count: u32,
    /// Chức năng của 8 ô (ô ngoài `count` vẫn giữ để đổi số ô không mất lựa chọn).
    pub slots: Vec<&'static str>,
    /// Chạm một lần.
    pub tap: &'static str,
    /// Chạm hai lần.
    pub double: &'static str,
    /// Nhấn giữ.
    pub hold: &'static str,
    /// Độ rõ của nút lúc nghỉ, 0,15–1.
    pub idle: f32,
    /// Bảng nút tự đóng sau chừng này giây không ai bấm; 0 = không tự đóng. Tối đa 60.
    pub menu_timeout: u32,
}

impl Default for Assist {
    fn default() -> Assist {
        Assist {
            count: DEFAULT_COUNT,
            slots: DEFAULT_SLOTS.to_vec(),
            tap: MENU,
            double: NONE,
            hold: NONE,
            idle: 0.5,
            menu_timeout: DEFAULT_MENU_TIMEOUT,
        }
    }
}

impl Assist {
    /// Đọc từ từ điển phẳng của Cài đặt: `assistCount`, `assistSlot1`…`assistSlot9`, `assistTap`, `assistDouble`,
    /// `assistHold`, `assistIdleAlpha`, `assistMenuTimeout`.
    pub fn from_prefs(v: &Value) -> Assist {
        let d = Assist::default();
        let text = |key: &str| v.get(key).and_then(Value::as_str);
        let number = |key: &str| match v.get(key) {
            Some(Value::Number(n)) => n.as_f64(),
            // Ô chọn của Cài đặt có thể lưu số dưới dạng chuỗi
            Some(Value::String(s)) => s.trim().parse::<f64>().ok(),
            _ => None,
        };
        let count = match number("assistCount") {
            Some(x) if x.is_finite() => (x as i64).clamp(1, MAX_SLOTS as i64) as u32,
            _ => d.count,
        };
        let slots = (0..MAX_SLOTS).map(|i| slot_id(text(&format!("assistSlot{}", i + 1)), DEFAULT_SLOTS[i])).collect();
        let idle = match number("assistIdleAlpha") {
            Some(x) if x.is_finite() => (x as f32).clamp(0.15, 1.0),
            _ => d.idle,
        };
        let mut tap = gesture_id(text("assistTap"), d.tap);
        let double = gesture_id(text("assistDouble"), d.double);
        let hold = gesture_id(text("assistHold"), d.hold);
        // Không thao tác nào mở được bảng nút thì bảng nút thành vô dụng: chạm một lần luôn mở bảng trong trường hợp đó
        if tap != MENU && double != MENU && hold != MENU && tap == NONE {
            tap = MENU;
        }
        let menu_timeout = match number("assistMenuTimeout") {
            Some(x) if x.is_finite() && x >= 0.0 => (x as u32).min(60),
            _ => d.menu_timeout,
        };
        Assist { count, slots, tap, double, hold, idle, menu_timeout }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use std::collections::HashSet;

    #[test]
    fn danh_muc_hop_le() {
        let ids: HashSet<_> = ACTIONS.iter().map(|a| a.id).collect();
        assert_eq!(ids.len(), ACTIONS.len(), "mã trùng");
        for a in ACTIONS {
            assert!(a.id.chars().all(|c| c.is_ascii_lowercase()), "{}", a.id);
            assert!(!a.title.is_empty());
            // Chức năng gán được vào ô thì phải có tên ngắn (trừ «để trống»)
            assert!(!a.slot || a.id == NONE || !a.short.is_empty(), "{}", a.id);
        }
        assert!(!find(MENU).unwrap().slot && find(MENU).unwrap().gesture);
        for id in DEFAULT_SLOTS {
            assert!(find(id).is_some_and(|a| a.slot), "{id}");
        }
    }

    #[test]
    fn mac_dinh() {
        let a = Assist::from_prefs(&json!({}));
        assert_eq!(a, Assist::default());
        assert_eq!((a.count, a.tap, a.slots.len()), (DEFAULT_COUNT, MENU, MAX_SLOTS));
        // Respring có sẵn trong bảng mặc định và gán được cho thao tác trên nút
        for id in ["respring", "rotate", "reboot"] {
            assert!(a.slots[..a.count as usize].contains(&id), "{id}");
        }
        assert_eq!(a.menu_timeout, DEFAULT_MENU_TIMEOUT);
        let t = |v: serde_json::Value| Assist::from_prefs(&json!({ "assistMenuTimeout": v })).menu_timeout;
        assert_eq!((t(json!(0)), t(json!(10)), t(json!("15")), t(json!(999)), t(json!(-4))), (0, 10, 15, 60, DEFAULT_MENU_TIMEOUT));
        assert!(find("respring").is_some_and(|x| x.slot && x.gesture));
        // Không phải từ điển cũng không vỡ
        assert_eq!(Assist::from_prefs(&json!(5)), Assist::default());
    }

    #[test]
    fn cau_hinh_hong_roi_ve_an_toan() {
        let a = Assist::from_prefs(&json!({
            "assistCount": 99, "assistSlot1": "khong-co", "assistSlot2": "menu", "assistSlot3": "dark",
            "assistTap": "volup", "assistDouble": "lock", "assistHold": 7, "assistIdleAlpha": -3
        }));
        assert_eq!(a.count, MAX_SLOTS as u32);
        // Mã lạ và «mở bảng nút» không gán được vào ô → về mặc định của ô đó
        assert_eq!((a.slots[0], a.slots[1], a.slots[2]), (DEFAULT_SLOTS[0], DEFAULT_SLOTS[1], "dark"));
        // «Tăng âm lượng» không dùng được cho thao tác → về mặc định (mở bảng nút)
        assert_eq!((a.tap, a.double, a.hold), (MENU, "lock", NONE));
        assert_eq!(a.idle, 0.15);
        assert_eq!(Assist::from_prefs(&json!({"assistCount": "3", "assistIdleAlpha": "0.8"})).count, 3);
    }

    #[test]
    fn luon_co_cach_mo_bang_nut() {
        let a = Assist::from_prefs(&json!({"assistTap": "none", "assistDouble": "home", "assistHold": "none"}));
        assert_eq!(a.tap, MENU);
        // Đã có thao tác khác mở bảng thì chạm một lần được phép làm việc khác
        let a = Assist::from_prefs(&json!({"assistTap": "home", "assistHold": "menu"}));
        assert_eq!((a.tap, a.hold), ("home", MENU));
        // Chạm một lần làm việc khác mà không thao tác nào mở bảng: vẫn giữ (người dùng chủ động chọn nút một chức năng)
        let a = Assist::from_prefs(&json!({"assistTap": "home"}));
        assert_eq!(a.tap, "home");
    }
}

//! Bộ gác: quét xung đột với gói / tweak khác đang có trên máy.
//!
//! Đếm sập và công tắc tổng bằng tệp KHÔNG nằm ở đây: vỏ ObjC làm hai việc đó bằng libc trước khi nạp lõi (lõi hỏng thì vẫn
//! phải tắt được).

use serde::Serialize;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Level {
    /// Cùng đổi một thứ với Glass 6 — phần trùng của Glass 6 tự tắt.
    Conflict,
    /// Chạy được cùng nhau nhưng nên biết.
    Warn,
    /// Chỉ để hiển thị.
    Info,
}

#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct Finding {
    pub id: String,
    pub name: String,
    pub level: Level,
    pub note: String,
    /// Thành phần của Glass 6 bị ảnh hưởng (tên khoá trong `Features`).
    pub features: Vec<String>,
}

/// Một thư viện MobileSubstrate đang cài: tên tệp (không đuôi) và danh sách bundle / tên tiến trình nó lọc.
#[derive(Clone, Debug, Default)]
pub struct Dylib {
    pub name: String,
    pub filters: Vec<String>,
}

struct Known {
    id: &'static str,
    name: &'static str,
    level: Level,
    note: &'static str,
    features: &'static [&'static str],
}

/// Gói đã biết là đổi cùng thứ với Glass 6. Mã gói ghi theo trí nhớ về các nguồn Cydia thời iOS 6 — cần đối chiếu lại với
/// nguồn thật trước khi phát hành (DECISIONS D6).
const KNOWN: &[Known] = &[
    Known {
        id: "winterboard",
        name: "WinterBoard",
        level: Level::Conflict,
        note: "Thay ảnh giao diện và biểu tượng của hệ thống — trùng với dock, biểu tượng và thành phần UIKit của Glass 6.",
        features: &["dock", "icons", "folders", "status_bar"],
    },
    Known {
        id: "com.wyndwarrior.dreamboard",
        name: "DreamBoard",
        level: Level::Conflict,
        note: "Thay cả màn hình chính.",
        features: &["dock", "icons", "folders", "lock_screen"],
    },
    Known {
        id: "com.filippobiga.springtomize2",
        name: "Springtomize 2",
        level: Level::Conflict,
        note: "Đổi dock, biểu tượng, thanh trạng thái, màn khoá.",
        features: &["dock", "icons", "status_bar", "lock_screen"],
    },
    Known {
        id: "com.a3tweaks.auxo",
        name: "Auxo",
        level: Level::Warn,
        note: "Thay khay đa nhiệm — Glass 6 không đụng khay đa nhiệm khi có Auxo.",
        features: &[],
    },
    Known {
        id: "com.alexzielenski.zeppelin",
        name: "Zeppelin",
        level: Level::Warn,
        note: "Đổi logo nhà mạng trên thanh trạng thái.",
        features: &["status_bar"],
    },
    Known {
        id: "sbsettings",
        name: "SBSettings",
        level: Level::Warn,
        note: "Có bảng công tắc riêng — trùng chức năng với Control Center của Glass 6.",
        features: &["control_center"],
    },
    Known {
        id: "com.jamied360.ncsettings",
        name: "NCSettings",
        level: Level::Warn,
        note: "Thêm công tắc vào Trung tâm thông báo.",
        features: &["notifications"],
    },
];

/// Tweak nhận ra theo TÊN THƯ VIỆN MobileSubstrate (mã gói của chúng khác nhau tuỳ nguồn — trên iPhone thử, Zephyr và Speed
/// Intensifier mang mã `vn.gsm.…`). Thấy trên iPhone 5 thử ngày 19/11/2026 (docs/IPHONE.md mục 2).
const KNOWN_LIBS: &[Known] = &[
    Known {
        id: "libstatusbar",
        name: "libstatusbar",
        level: Level::Conflict,
        note: "Xếp lại các mục của thanh trạng thái — trùng với phần «giờ bên trái, sóng bên phải, pin vẽ lại» của Glass 6.",
        features: &["status_bar"],
    },
    Known {
        id: "Zephyr",
        name: "Zephyr",
        level: Level::Warn,
        note: "Cử chỉ vuốt để mở khay đa nhiệm / đổi app — có thể giành cử chỉ với khay đa nhiệm và Control Center của Glass 6.",
        features: &["switcher", "control_center"],
    },
    Known {
        id: "SpeedIntensifier",
        name: "Speed Intensifier",
        level: Level::Warn,
        note: "Đổi tốc độ mọi hiệu ứng chuyển động — thời gian mở / đóng các tấm kính của Glass 6 sẽ lệch.",
        features: &[],
    },
    Known {
        id: "Activator",
        name: "Activator",
        level: Level::Warn,
        note: "Gán cử chỉ hệ thống — cử chỉ đã gán ở mép trên màn hình có thể giành với Control Center của Glass 6.",
        features: &["control_center"],
    },
];

/// Thư viện đã xem mã, biết chắc chung sống được (xem THIET-KE mục 1).
const KNOWN_OK: &[(&str, &str)] = &[
    ("CBFloat", "Hình nổi của Côn Bằng TV — cửa sổ mức 1050, Glass 6 không dùng mức này."),
    ("GMNotify", "Thông báo của GramMini — chỉ sửa danh sách app có thông báo."),
    ("RZNotify", "Thông báo của Roza — chỉ sửa danh sách app có thông báo."),
    ("MasaNotify", "Thông báo của Masa — chỉ sửa danh sách app có thông báo."),
    ("GramLockControl", "Khung nhạc trên màn khoá của GramMusic — Glass 6 chừa chỗ cho khung này."),
];

/// Thư viện nền tảng, không cần nhắc tới.
const SILENT: &[&str] = &["MobileSafety", "PreferenceLoader", "Glass6SB", "Glass6UI"];

/// Tách mã các gói đang cài từ nội dung `/var/lib/dpkg/status`.
pub fn parse_dpkg_status(text: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut name: Option<&str> = None;
    let mut installed = false;
    for line in text.lines().chain(std::iter::once("")) {
        if line.trim().is_empty() {
            if let (Some(n), true) = (name, installed) {
                out.push(n.to_string());
            }
            name = None;
            installed = false;
        } else if let Some(v) = line.strip_prefix("Package:") {
            name = Some(v.trim());
        } else if let Some(v) = line.strip_prefix("Status:") {
            installed = v.trim().ends_with(" installed");
        }
    }
    out
}

/// Đối chiếu gói và thư viện đang cài với danh sách đã biết.
pub fn scan(packages: &[String], dylibs: &[Dylib]) -> Vec<Finding> {
    let mut out = Vec::new();
    for k in KNOWN {
        if packages.iter().any(|p| p == k.id) {
            out.push(Finding {
                id: k.id.to_string(),
                name: k.name.to_string(),
                level: k.level,
                note: k.note.to_string(),
                features: k.features.iter().map(|s| s.to_string()).collect(),
            });
        }
    }
    for d in dylibs {
        if SILENT.contains(&d.name.as_str()) {
            continue;
        }
        let ui = d.filters.iter().any(|f| f == "com.apple.springboard" || f == "com.apple.UIKit");
        if !ui {
            continue;
        }
        if let Some(k) = KNOWN_LIBS.iter().find(|k| k.id == d.name) {
            out.push(Finding {
                id: k.id.to_string(),
                name: k.name.to_string(),
                level: k.level,
                note: k.note.to_string(),
                features: k.features.iter().map(|s| s.to_string()).collect(),
            });
            continue;
        }
        let (level, note) = match KNOWN_OK.iter().find(|(n, _)| *n == d.name) {
            Some((_, note)) => (Level::Info, note.to_string()),
            None => (
                Level::Warn,
                "Tweak này cũng nạp vào SpringBoard hoặc mọi app. Glass 6 chưa biết nó đổi gì — nếu giao diện lỗi, thử tắt nó."
                    .to_string(),
            ),
        };
        let features = if d.name == "GramLockControl" { vec!["lock_screen".to_string()] } else { Vec::new() };
        out.push(Finding { id: d.name.clone(), name: d.name.clone(), level, note, features });
    }
    out
}

/// Thành phần phải tự tắt vì có gói xung đột.
pub fn blocked_features(findings: &[Finding]) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    for f in findings.iter().filter(|f| f.level == Level::Conflict) {
        for name in &f.features {
            if !out.contains(name) {
                out.push(name.clone());
            }
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    const STATUS: &str = "Package: winterboard\nStatus: install ok installed\nVersion: 0.9\n\n\
Package: da.go\nStatus: deinstall ok config-files\n\n\
Package: vn.grammini.app\nStatus: install ok installed\nDescription: a\n b\n";

    #[test]
    fn doc_dpkg_status() {
        let p = parse_dpkg_status(STATUS);
        assert_eq!(p, vec!["winterboard".to_string(), "vn.grammini.app".to_string()]);
        assert!(parse_dpkg_status("").is_empty());
        assert!(parse_dpkg_status("rác\n\n\nStatus: install ok installed\n").is_empty());
    }

    #[test]
    fn may_thu_hien_tai_khong_xung_dot() {
        // Đúng hiện trạng iPad mini 1 ngày 19/11/2026
        let dylibs: Vec<Dylib> = [
            ("AppSyncUnified-installd", vec!["installd"]),
            ("CBFloat", vec!["com.apple.springboard"]),
            ("GMNotify", vec!["com.apple.springboard"]),
            ("GramLockControl", vec!["com.apple.springboard"]),
            ("MobileSafety", vec!["com.apple.springboard"]),
            ("PreferenceLoader", vec!["com.apple.Preferences"]),
            ("RZNotify", vec!["com.apple.springboard"]),
            ("TubeRepair-Tweak", vec!["com.apple.youtube"]),
        ]
        .into_iter()
        .map(|(n, f)| Dylib { name: n.to_string(), filters: f.into_iter().map(String::from).collect() })
        .collect();
        let f = scan(&["vn.grammini.app".to_string()], &dylibs);
        assert_eq!(f.len(), 4, "{f:?}");
        assert!(f.iter().all(|x| x.level == Level::Info));
        assert!(blocked_features(&f).is_empty());
    }

    #[test]
    fn winterboard_chan_dock_va_bieu_tuong() {
        let f = scan(&parse_dpkg_status(STATUS), &[]);
        assert_eq!(f.len(), 1);
        let b = blocked_features(&f);
        assert!(b.contains(&"dock".to_string()) && b.contains(&"icons".to_string()));
    }

    #[test]
    fn tweak_cua_iphone_thu_nhan_theo_ten_thu_vien() {
        // iPhone 5 thử trước khi gỡ (19/11/2026): bốn thư viện này nạp vào SpringBoard / mọi app
        let dylibs: Vec<Dylib> = [
            ("libstatusbar", "com.apple.UIKit"),
            ("Zephyr", "com.apple.springboard"),
            ("SpeedIntensifier", "com.apple.UIKit"),
            ("Activator", "com.apple.UIKit"),
        ]
        .into_iter()
        .map(|(n, f)| Dylib { name: n.to_string(), filters: vec![f.to_string()] })
        .collect();
        // Mã gói của nguồn lạ không có trong bảng gói — vẫn nhận ra nhờ tên thư viện
        let f = scan(&["vn.gsm.zephyr".to_string(), "libstatusbar".to_string()], &dylibs);
        assert_eq!(f.len(), 4, "{f:?}");
        assert_eq!(f[0].level, Level::Conflict);
        assert!(f[1..].iter().all(|x| x.level == Level::Warn));
        // Chỉ libstatusbar làm một thành phần tự tắt
        assert_eq!(blocked_features(&f), vec!["status_bar".to_string()]);
    }

    #[test]
    fn tweak_la_nap_vao_springboard_thi_canh_bao() {
        let d = Dylib { name: "LaHoac".into(), filters: vec!["com.apple.UIKit".into()] };
        let f = scan(&[], &[d]);
        assert_eq!(f[0].level, Level::Warn);
    }
}

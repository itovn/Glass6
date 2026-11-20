//! Danh mục dịch vụ hệ thống mà Glass 6 được phép tắt / bật, và các hồ sơ dựng sẵn.
//!
//! Nguồn duy nhất là `data/services.tsv` ở gốc repo: lõi đọc nó để đưa tên + ghi chú cho bảng Cài đặt; công cụ quyền root
//! `g6svc` sinh danh sách trắng của mình từ cùng tệp đó lúc dựng. Lõi không tự tắt / bật gì — việc đó chỉ `g6svc` làm.

use serde::Serialize;

static CATALOG_TSV: &str = include_str!("../../../../data/services.tsv");

/// Dịch vụ sống còn của máy. Không bao giờ được có trong danh mục — phép thử ở cuối tệp chặn việc lỡ tay thêm vào.
pub const FORBIDDEN: &[&str] = &[
    "backboardd",
    "SpringBoard",
    "configd",
    "notifyd",
    "lockdown",
    "installd",
    "mediaserverd",
    "securityd",
    "fairplayd",
    "lsd",
    "wifid",
    "CommCenter",
    "locationd",
    "powerd",
    "kbd",
    "syslogd",
    "mDNSResponder",
    "accountsd",
    "tccd",
    "assistivetouchd",
    "sshd",
    "launchd",
    "apsd",
    "ReportCrash",
    "xpcd",
    "networkd",
    "keybagd",
    "MobileFileIntegrity",
    "sandboxd",
];

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct Service {
    /// Mã ngắn, ổn định — tên khoá trong cấu hình và tham số của `g6svc`.
    pub id: &'static str,
    /// `A` máy chủ đã đóng, `B` chẩn đoán gửi Apple, `C` tuỳ nhu cầu.
    pub group: char,
    /// Tên tệp việc launchd (bỏ đuôi): `/System/Library/LaunchDaemons/<tệp>.plist`.
    pub files: Vec<&'static str>,
    /// Nhãn launchd của từng tệp, cùng thứ tự (thường trùng tên tệp; danh mục ghi «tệp:nhãn» khi khác).
    pub labels: Vec<&'static str>,
    pub title: &'static str,
    /// Tắt thì mất gì.
    pub note: &'static str,
}

/// Đọc danh mục. Dòng hỏng (thiếu cột, nhóm lạ) bị bỏ qua — phép thử bảo đảm tệp trong repo không có dòng nào như vậy.
pub fn catalog() -> Vec<Service> {
    CATALOG_TSV.lines().filter_map(parse_line).collect()
}

fn parse_line(line: &'static str) -> Option<Service> {
    let line = line.trim_end_matches('\r');
    if line.trim().is_empty() || line.starts_with('#') {
        return None;
    }
    let mut cols = line.split('\t');
    let id = cols.next()?.trim();
    let group = cols.next()?.trim();
    let (mut files, mut labels) = (Vec::new(), Vec::new());
    for job in cols.next()?.split(',').map(str::trim).filter(|j| !j.is_empty()) {
        let (file, label) = job.split_once(':').unwrap_or((job, job));
        if file.is_empty() || label.is_empty() {
            return None;
        }
        files.push(file);
        labels.push(label);
    }
    let title = cols.next()?.trim();
    let note = cols.next()?.trim();
    let group = match group {
        "A" => 'A',
        "B" => 'B',
        "C" => 'C',
        _ => return None,
    };
    if id.is_empty() || labels.is_empty() || title.is_empty() {
        return None;
    }
    Some(Service { id, group, files, labels, title, note })
}

/// Mã các dịch vụ phải TẮT trong một hồ sơ. `stock` (nguyên bản) = không tắt gì; `balanced` (cân bằng) = nhóm A + B.
/// Tên lạ → `None`.
pub fn profile(name: &str) -> Option<Vec<&'static str>> {
    match name {
        "stock" => Some(Vec::new()),
        "balanced" => Some(catalog().into_iter().filter(|s| s.group != 'C').map(|s| s.id).collect()),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashSet;

    #[test]
    fn danh_muc_doc_du_moi_dong() {
        let rows = CATALOG_TSV.lines().filter(|l| !l.trim().is_empty() && !l.starts_with('#')).count();
        let cat = catalog();
        assert_eq!(cat.len(), rows, "có dòng trong services.tsv không đọc được");
        assert!(cat.len() >= 9);
        let ids: HashSet<_> = cat.iter().map(|s| s.id).collect();
        assert_eq!(ids.len(), cat.len(), "mã dịch vụ trùng nhau");
        let labels: Vec<_> = cat.iter().flat_map(|s| s.labels.iter().copied()).collect();
        assert_eq!(labels.iter().collect::<HashSet<_>>().len(), labels.len(), "một nhãn launchd nằm ở hai dịch vụ");
        let files: Vec<_> = cat.iter().flat_map(|s| s.files.iter().copied()).collect();
        assert_eq!(files.iter().collect::<HashSet<_>>().len(), files.len(), "một tệp việc nằm ở hai dịch vụ");
        assert!(cat.iter().all(|s| s.files.len() == s.labels.len()));
        // «tệp:nhãn»: nhãn khác tên tệp
        let usage = cat.iter().find(|s| s.id == "usage").unwrap();
        assert!(usage.files.contains(&"com.apple.aggregated.addaily") && usage.labels.contains(&"com.apple.addaily"));
    }

    #[test]
    fn ma_va_nhan_chi_gom_ky_tu_an_toan() {
        // g6svc ghép tên tệp thành đường dẫn và đưa cho launchctl: không được có khoảng trắng, dấu «/», «..»
        for s in catalog() {
            assert!(s.id.chars().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit()), "{}", s.id);
            for l in s.files.iter().chain(&s.labels) {
                assert!(l.starts_with("com.apple."), "{l}");
                assert!(l.chars().all(|c| c.is_ascii_alphanumeric() || c == '.' || c == '_' || c == '-'), "{l}");
                assert!(!l.contains(".."), "{l}");
            }
        }
    }

    #[test]
    fn khong_co_dich_vu_song_con() {
        for s in catalog() {
            for l in s.files.iter().chain(&s.labels) {
                for f in FORBIDDEN {
                    assert!(!l.to_ascii_lowercase().contains(&f.to_ascii_lowercase()), "{l} đụng dịch vụ cấm «{f}»");
                }
            }
        }
    }

    #[test]
    fn ho_so() {
        assert_eq!(profile("stock"), Some(vec![]));
        let balanced = profile("balanced").unwrap();
        let cat = catalog();
        assert!(balanced.contains(&"twitter") && balanced.contains(&"usage"));
        // Nhóm C (tuỳ nhu cầu) không bao giờ nằm trong hồ sơ dựng sẵn
        for s in cat.iter().filter(|s| s.group == 'C') {
            assert!(!balanced.contains(&s.id), "{}", s.id);
        }
        assert_eq!(profile("la"), None);
    }
}

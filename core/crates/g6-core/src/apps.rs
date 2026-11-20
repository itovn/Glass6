//! Chính sách theo từng app cho phần nạp vào app (Glass6UI): app nào được đổi thanh, bảng, nút điều khiển.
//!
//! Glass6UI đổi kiểu của UIKit chuẩn. App «giả vật liệu» của iOS 6 (Lịch bọc da, Danh bạ dạng sổ, Ghi chú giấy vàng, Game
//! Center nỉ xanh…) tự vẽ thanh và nút bằng ảnh riêng: đổi một nửa (nút thành viên kính trên thanh da) trông hỏng hơn là để
//! nguyên. Các app đó nằm trong bảng dưới và được chừa ra cho tới khi có bản vẽ lại riêng (Đợt 3).

use serde::Serialize;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
pub struct AppPolicy {
    /// Thanh điều hướng, thanh công cụ, thanh thẻ, ô tìm kiếm, nút trên thanh.
    pub bars: bool,
    /// Nền và ô của bảng kiểu nhóm.
    pub tables: bool,
    /// Công tắc, thanh trượt, nút chọn đoạn, thanh tiến độ.
    pub controls: bool,
    /// App tự vẽ giao diện bằng ảnh riêng (lý do bị chừa ra).
    pub skeuomorphic: bool,
}

const ALL: AppPolicy = AppPolicy { bars: true, tables: true, controls: true, skeuomorphic: false };
/// App giả vật liệu: giữ nguyên thanh và bảng; nút điều khiển chuẩn (công tắc trong bảng nổi…) vẫn đổi.
const SKEUO: AppPolicy = AppPolicy { bars: false, tables: false, controls: true, skeuomorphic: true };

/// Mã gói của các app Apple tự vẽ giao diện bằng ảnh riêng trên iOS 6 (iPad và iPhone).
const SKEUOMORPHIC: &[&str] = &[
    "com.apple.mobilecal",
    "com.apple.MobileAddressBook",
    "com.apple.mobilenotes",
    "com.apple.reminders",
    "com.apple.gamecenter",
    "com.apple.Music",
    "com.apple.mobileipod",
    "com.apple.Photo-Booth",
    "com.apple.camera",
    "com.apple.iBooks",
    "com.apple.podcasts",
    "com.apple.mobileme.fmf1",
    "com.apple.mobileme.fmip1",
    "com.apple.Passbook",
    "com.apple.compass",
    "com.apple.VoiceMemos",
    "com.apple.calculator",
    "com.apple.newsstand",
];

/// Chính sách cho app có mã gói `bundle`. App không có trong bảng: đổi tất cả.
pub fn policy(bundle: &str) -> AppPolicy {
    if SKEUOMORPHIC.contains(&bundle) {
        SKEUO
    } else {
        ALL
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn app_thuong_doi_tat_ca() {
        for id in ["com.apple.Preferences", "com.apple.mobilemail", "vn.example.app", ""] {
            assert_eq!(policy(id), ALL, "{id}");
        }
    }

    #[test]
    fn app_gia_vat_lieu_giu_thanh_va_bang() {
        for id in ["com.apple.mobilecal", "com.apple.mobilenotes", "com.apple.gamecenter"] {
            let p = policy(id);
            assert!(!p.bars && !p.tables && p.controls && p.skeuomorphic, "{id}");
        }
        // So đúng cả chữ hoa / thường: mã gói là định danh chính xác
        assert_eq!(policy("com.apple.MobileCal"), ALL);
    }

    #[test]
    fn bang_khong_trung() {
        let mut ids = SKEUOMORPHIC.to_vec();
        ids.sort_unstable();
        ids.dedup();
        assert_eq!(ids.len(), SKEUOMORPHIC.len());
    }
}

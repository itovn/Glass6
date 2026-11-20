//! Âm lịch Việt Nam cho app Lịch: đổi ngày dương → âm (có tháng nhuận), can chi, tiết khí, 12 thần trực nhật (ngày hoàng đạo /
//! hắc đạo), giờ hoàng đạo, ngày lễ âm lịch.
//!
//! Thuật toán đổi lịch: Hồ Ngọc Đức, «Thuật toán tính âm lịch» (tính điểm sóc và trung khí theo kinh độ Mặt Trời, giờ Hà Nội
//! UTC+7 — khác lịch Trung Quốc UTC+8 ở vài năm, vd Tết 1985, 2007). Dùng được cho khoảng năm 1800–2199.
//!
//! Ngày hoàng đạo: hệ 12 thần (Thanh Long, Minh Đường, Thiên Hình, Chu Tước, Kim Quỹ, Kim Đường, Bạch Hổ, Ngọc Đường, Thiên Lao,
//! Huyền Vũ, Tư Mệnh, Câu Trần) đi lần lượt theo địa chi của ngày; Thanh Long khởi ở ngày Tý (tháng 1, 7), Dần (2, 8), Thìn (3,
//! 9), Ngọ (4, 10), Thân (5, 11), Tuất (6, 12) theo tháng âm lịch (tháng nhuận tính như tháng thường cùng số). Sáu thần hoàng
//! đạo: Thanh Long, Minh Đường, Kim Quỹ, Kim Đường, Ngọc Đường, Tư Mệnh. Đối chiếu: 20/11/2026 (12/10 Bính Ngọ, ngày Mậu Tuất)
//! — trang lịch âm ghi «Kim Quỹ Hoàng Đạo».
//!
//! Giờ hoàng đạo: bảng theo địa chi của ngày (chu kỳ 6), như trong lịch của Hồ Ngọc Đức.

use std::f64::consts::PI;

use serde::Serialize;

/// Múi giờ của lịch Việt Nam
pub const TZ_VN: f64 = 7.0;

pub const CAN: [&str; 10] = ["Giáp", "Ất", "Bính", "Đinh", "Mậu", "Kỷ", "Canh", "Tân", "Nhâm", "Quý"];
pub const CHI: [&str; 12] = ["Tý", "Sửu", "Dần", "Mão", "Thìn", "Tỵ", "Ngọ", "Mùi", "Thân", "Dậu", "Tuất", "Hợi"];

/// 12 thần trực nhật theo thứ tự, bắt đầu từ Thanh Long
pub const THAN: [&str; 12] = [
    "Thanh Long", "Minh Đường", "Thiên Hình", "Chu Tước", "Kim Quỹ", "Kim Đường", "Bạch Hổ", "Ngọc Đường", "Thiên Lao", "Huyền Vũ",
    "Tư Mệnh", "Câu Trần",
];
/// Thần nào là hoàng đạo (theo chỉ số trong `THAN`)
const THAN_TOT: [bool; 12] = [true, true, false, false, true, true, false, true, false, false, true, false];

/// Giờ hoàng đạo theo (chi của ngày) % 6: chuỗi 12 ký tự từ giờ Tý tới giờ Hợi, '1' = hoàng đạo
const GIO_HD: [&str; 6] = ["110100101100", "001101001011", "110011010010", "101100110100", "001011001101", "010010110011"];

/// 24 tiết khí, bắt đầu từ Xuân phân (kinh độ Mặt Trời 0°)
pub const TIET_KHI: [&str; 24] = [
    "Xuân phân", "Thanh minh", "Cốc vũ", "Lập hạ", "Tiểu mãn", "Mang chủng", "Hạ chí", "Tiểu thử", "Đại thử", "Lập thu", "Xử thử",
    "Bạch lộ", "Thu phân", "Hàn lộ", "Sương giáng", "Lập đông", "Tiểu tuyết", "Đại tuyết", "Đông chí", "Tiểu hàn", "Đại hàn",
    "Lập xuân", "Vũ thủy", "Kinh trập",
];

/// Ngày lễ / tết theo âm lịch (ngày, tháng, tên) — không tính tháng nhuận
const LE: [(i64, i64, &str); 8] = [
    (1, 1, "Tết Nguyên đán"),
    (15, 1, "Rằm tháng Giêng"),
    (10, 3, "Giỗ Tổ Hùng Vương"),
    (15, 4, "Lễ Phật đản"),
    (5, 5, "Tết Đoan ngọ"),
    (15, 7, "Lễ Vu lan"),
    (15, 8, "Tết Trung thu"),
    (23, 12, "Ông Công Ông Táo"),
];

// ---- Ngày Julius ----

/// Số ngày Julius của một ngày dương lịch (lịch Gregory từ 15/10/1582, Julius trước đó)
pub fn jd_from_date(dd: i64, mm: i64, yy: i64) -> i64 {
    let a = (14 - mm) / 12;
    let y = yy + 4800 - a;
    let m = mm + 12 * a - 3;
    let jd = dd + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045;
    if jd < 2299161 {
        dd + (153 * m + 2) / 5 + 365 * y + y / 4 - 32083
    } else {
        jd
    }
}

/// Ngày dương lịch (ngày, tháng, năm) của một số ngày Julius
pub fn jd_to_date(jd: i64) -> (i64, i64, i64) {
    let (b, c) = if jd > 2299160 {
        let a = jd + 32044;
        let b = (4 * a + 3) / 146097;
        (b, a - (b * 146097) / 4)
    } else {
        (0, jd + 32082)
    };
    let d = (4 * c + 3) / 1461;
    let e = c - (1461 * d) / 4;
    let m = (5 * e + 2) / 153;
    let day = e - (153 * m + 2) / 5 + 1;
    let month = m + 3 - 12 * (m / 10);
    let year = b * 100 + d - 4800 + m / 10;
    (day, month, year)
}

// ---- Thiên văn ----

/// Thời điểm (ngày Julius, giờ quốc tế) của điểm sóc thứ k kể từ sóc 1/1/1900
fn new_moon(k: f64) -> f64 {
    let t = k / 1236.85;
    let t2 = t * t;
    let t3 = t2 * t;
    let dr = PI / 180.0;
    let mut jd1 = 2415020.75933 + 29.53058868 * k + 0.0001178 * t2 - 0.000000155 * t3;
    jd1 += 0.00033 * ((166.56 + 132.87 * t - 0.009173 * t2) * dr).sin();
    let m = 359.2242 + 29.10535608 * k - 0.0000333 * t2 - 0.00000347 * t3;
    let mpr = 306.0253 + 385.81691806 * k + 0.0107306 * t2 + 0.00001236 * t3;
    let f = 21.2964 + 390.67050646 * k - 0.0016528 * t2 - 0.00000239 * t3;
    let mut c1 = (0.1734 - 0.000393 * t) * (m * dr).sin() + 0.0021 * (2.0 * dr * m).sin();
    c1 = c1 - 0.4068 * (mpr * dr).sin() + 0.0161 * (dr * 2.0 * mpr).sin();
    c1 -= 0.0004 * (dr * 3.0 * mpr).sin();
    c1 = c1 + 0.0104 * (dr * 2.0 * f).sin() - 0.0051 * (dr * (m + mpr)).sin();
    c1 = c1 - 0.0074 * (dr * (m - mpr)).sin() + 0.0004 * (dr * (2.0 * f + m)).sin();
    c1 = c1 - 0.0004 * (dr * (2.0 * f - m)).sin() - 0.0006 * (dr * (2.0 * f + mpr)).sin();
    c1 = c1 + 0.0010 * (dr * (2.0 * f - mpr)).sin() + 0.0005 * (dr * (2.0 * mpr + m)).sin();
    let deltat = if t < -11.0 {
        0.001 + 0.000839 * t + 0.0002261 * t2 - 0.00000845 * t3 - 0.000000081 * t * t3
    } else {
        -0.000278 + 0.000265 * t + 0.000262 * t2
    };
    jd1 + c1 - deltat
}

/// Kinh độ Mặt Trời (radian, 0 … 2π) ở thời điểm jdn (ngày Julius, giờ quốc tế)
fn sun_longitude(jdn: f64) -> f64 {
    let t = (jdn - 2451545.0) / 36525.0;
    let t2 = t * t;
    let dr = PI / 180.0;
    let m = 357.52910 + 35999.05030 * t - 0.0001559 * t2 - 0.00000048 * t * t2;
    let l0 = 280.46645 + 36000.76983 * t + 0.0003032 * t2;
    let mut dl = (1.914600 - 0.004817 * t - 0.000014 * t2) * (dr * m).sin();
    dl += (0.019993 - 0.000101 * t) * (dr * 2.0 * m).sin() + 0.000290 * (dr * 3.0 * m).sin();
    let mut l = (l0 + dl) * dr;
    l -= PI * 2.0 * (l / (PI * 2.0)).floor();
    l
}

/// Ngày (số ngày Julius, theo múi giờ tz) chứa điểm sóc thứ k
fn new_moon_day(k: i64, tz: f64) -> i64 {
    (new_moon(k as f64) + 0.5 + tz / 24.0).floor() as i64
}

/// Cung kinh độ Mặt Trời (0 … 11, mỗi cung 30°) lúc 0 giờ (theo múi giờ tz) của ngày `day_number`
fn sun_sector(day_number: i64, tz: f64) -> i64 {
    (sun_longitude(day_number as f64 - 0.5 - tz / 24.0) / PI * 6.0).floor() as i64
}

/// Ngày bắt đầu tháng 11 âm lịch chứa ngày Đông chí của năm dương lịch yy
fn lunar_month11(yy: i64, tz: f64) -> i64 {
    let off = jd_from_date(31, 12, yy) - 2415021;
    let k = (off as f64 / 29.530588853).floor() as i64;
    let nm = new_moon_day(k, tz);
    if sun_sector(nm, tz) >= 9 {
        new_moon_day(k - 1, tz)
    } else {
        nm
    }
}

/// Vị trí tháng nhuận (số tháng sau tháng 11) trong năm âm có 13 tháng bắt đầu từ tháng 11 tại a11
fn leap_month_offset(a11: i64, tz: f64) -> i64 {
    let k = ((a11 as f64 - 2415021.076998695) / 29.530588853 + 0.5).floor() as i64;
    let mut i = 1;
    let mut arc = sun_sector(new_moon_day(k + i, tz), tz);
    loop {
        let last = arc;
        i += 1;
        arc = sun_sector(new_moon_day(k + i, tz), tz);
        if arc == last || i >= 14 {
            break;
        }
    }
    i - 1
}

/// Một ngày âm lịch
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct LunarDate {
    pub day: i64,
    pub month: i64,
    pub year: i64,
    pub leap: bool,
    /// Số ngày Julius của ngày dương lịch tương ứng
    pub jd: i64,
    /// Ngày Julius của mùng 1 tháng âm này và của mùng 1 tháng sau (độ dài tháng = hiệu)
    pub month_start: i64,
    pub next_month_start: i64,
}

/// Đổi ngày dương lịch (dd/mm/yy) sang âm lịch theo múi giờ tz
pub fn solar_to_lunar(dd: i64, mm: i64, yy: i64, tz: f64) -> LunarDate {
    let day_number = jd_from_date(dd, mm, yy);
    let k = ((day_number as f64 - 2415021.076998695) / 29.530588853).floor() as i64;
    let mut month_start = new_moon_day(k + 1, tz);
    if month_start > day_number {
        month_start = new_moon_day(k, tz);
    }
    // Mùng 1 tháng sau: điểm sóc kế tiếp sau month_start
    let mut next = new_moon_day(k + 1, tz);
    if next <= month_start {
        next = new_moon_day(k + 2, tz);
    }
    let mut a11 = lunar_month11(yy, tz);
    let mut b11 = a11;
    let mut lunar_year;
    if a11 >= month_start {
        lunar_year = yy;
        a11 = lunar_month11(yy - 1, tz);
    } else {
        lunar_year = yy + 1;
        b11 = lunar_month11(yy + 1, tz);
    }
    let lunar_day = day_number - month_start + 1;
    let diff = ((month_start - a11) as f64 / 29.0).floor() as i64;
    let mut leap = false;
    let mut lunar_month = diff + 11;
    if b11 - a11 > 365 {
        let leap_diff = leap_month_offset(a11, tz);
        if diff >= leap_diff {
            lunar_month = diff + 10;
            if diff == leap_diff {
                leap = true;
            }
        }
    }
    if lunar_month > 12 {
        lunar_month -= 12;
    }
    if lunar_month >= 11 && diff < 4 {
        lunar_year -= 1;
    }
    LunarDate { day: lunar_day, month: lunar_month, year: lunar_year, leap, jd: day_number, month_start, next_month_start: next }
}

// ---- Can chi, thần trực nhật, giờ hoàng đạo, tiết khí ----

pub fn can_chi_day(jd: i64) -> String {
    format!("{} {}", CAN[((jd + 9).rem_euclid(10)) as usize], CHI[((jd + 1).rem_euclid(12)) as usize])
}

pub fn can_chi_month(month: i64, year: i64) -> String {
    format!("{} {}", CAN[((year * 12 + month + 3).rem_euclid(10)) as usize], CHI[((month + 1).rem_euclid(12)) as usize])
}

pub fn can_chi_year(year: i64) -> String {
    format!("{} {}", CAN[((year + 6).rem_euclid(10)) as usize], CHI[((year + 8).rem_euclid(12)) as usize])
}

/// Chỉ số thần trực nhật (0 … 11 trong `THAN`) của ngày jd thuộc tháng âm `month`
pub fn than_index(jd: i64, month: i64) -> usize {
    let day_chi = (jd + 1).rem_euclid(12);
    let start = ((month - 1).rem_euclid(6)) * 2; // Thanh Long khởi: Tý, Dần, Thìn, Ngọ, Thân, Tuất
    ((day_chi - start).rem_euclid(12)) as usize
}

pub fn is_hoang_dao(jd: i64, month: i64) -> bool {
    THAN_TOT[than_index(jd, month)]
}

/// Giờ hoàng đạo của ngày jd: (tên chi, giờ bắt đầu, giờ kết thúc) — giờ Tý 23–1
pub fn gio_hoang_dao(jd: i64) -> Vec<(&'static str, u32, u32)> {
    let chi = (jd + 1).rem_euclid(12) as usize;
    GIO_HD[chi % 6]
        .bytes()
        .enumerate()
        .filter(|(_, b)| *b == b'1')
        .map(|(i, _)| (CHI[i], ((i as u32 * 2) + 23) % 24, (i as u32 * 2 + 1) % 24))
        .collect()
}

/// Tiết khí đang hiệu lực ngày jd (theo múi giờ tz)
pub fn tiet_khi(jd: i64, tz: f64) -> &'static str {
    let idx = (sun_longitude(jd as f64 + 0.5 - tz / 24.0) / PI * 12.0).floor() as i64;
    TIET_KHI[idx.rem_euclid(24) as usize]
}

/// Tên ngày lễ âm lịch (không có thì None). Tháng nhuận không có lễ.
pub fn le_am_lich(l: &LunarDate) -> Option<&'static str> {
    if l.leap {
        return None;
    }
    LE.iter().find(|(d, m, _)| *d == l.day && *m == l.month).map(|(_, _, n)| *n)
}

// ---- Gói cho vỏ ObjC ----

/// Một ô của lịch tháng
#[derive(Serialize, Debug)]
pub struct MonthCell {
    /// ngày dương
    pub d: i64,
    /// ngày / tháng / năm âm, tháng nhuận
    pub ld: i64,
    pub lm: i64,
    pub ly: i64,
    pub leap: bool,
    /// ngày hoàng đạo
    pub good: bool,
    /// có lễ âm lịch
    pub fest: bool,
}

/// Số ngày của tháng dương lịch
pub fn days_in_month(month: i64, year: i64) -> i64 {
    let next = if month == 12 { jd_from_date(1, 1, year + 1) } else { jd_from_date(1, month + 1, year) };
    next - jd_from_date(1, month, year)
}

/// Âm lịch cho mọi ngày của tháng dương lịch month/year. Năm ngoài 1800–2199 → rỗng.
pub fn month_cells(month: i64, year: i64) -> Vec<MonthCell> {
    if !(1..=12).contains(&month) || !(1800..=2199).contains(&year) {
        return Vec::new();
    }
    (1..=days_in_month(month, year))
        .map(|d| {
            let l = solar_to_lunar(d, month, year, TZ_VN);
            MonthCell {
                d,
                ld: l.day,
                lm: l.month,
                ly: l.year,
                leap: l.leap,
                good: is_hoang_dao(l.jd, l.month),
                fest: le_am_lich(&l).is_some(),
            }
        })
        .collect()
}

/// Chi tiết một ngày (cho đầu trang của chế độ xem Ngày)
#[derive(Serialize, Debug)]
pub struct DayDetail {
    pub ld: i64,
    pub lm: i64,
    pub ly: i64,
    pub leap: bool,
    /// tháng âm đủ (30 ngày) hay thiếu (29)
    pub month_days: i64,
    pub can_chi_day: String,
    pub can_chi_month: String,
    pub can_chi_year: String,
    pub than: &'static str,
    pub good: bool,
    pub tiet_khi: &'static str,
    /// giờ hoàng đạo: «Tý (23–1)» …
    pub hours: Vec<String>,
    pub festival: Option<&'static str>,
}

pub fn day_detail(d: i64, m: i64, y: i64) -> Option<DayDetail> {
    if !(1..=12).contains(&m) || !(1800..=2199).contains(&y) || d < 1 || d > days_in_month(m, y) {
        return None;
    }
    let l = solar_to_lunar(d, m, y, TZ_VN);
    Some(DayDetail {
        ld: l.day,
        lm: l.month,
        ly: l.year,
        leap: l.leap,
        month_days: l.next_month_start - l.month_start,
        can_chi_day: can_chi_day(l.jd),
        can_chi_month: can_chi_month(l.month, l.year),
        can_chi_year: can_chi_year(l.year),
        than: THAN[than_index(l.jd, l.month)],
        good: is_hoang_dao(l.jd, l.month),
        tiet_khi: tiet_khi(l.jd, TZ_VN),
        hours: gio_hoang_dao(l.jd).into_iter().map(|(n, a, b)| format!("{} ({}–{})", n, a, b)).collect(),
        festival: le_am_lich(&l),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn lunar(d: i64, m: i64, y: i64) -> (i64, i64, i64, bool) {
        let l = solar_to_lunar(d, m, y, TZ_VN);
        (l.day, l.month, l.year, l.leap)
    }

    #[test]
    fn julius_round_trip() {
        for &(d, m, y) in &[(1, 1, 1900), (29, 2, 2000), (20, 11, 2026), (31, 12, 2199), (15, 10, 1582)] {
            assert_eq!(jd_to_date(jd_from_date(d, m, y)), (d, m, y));
        }
        assert_eq!(jd_from_date(1, 1, 2000), 2451545);
    }

    #[test]
    fn tet_nguyen_dan() {
        assert_eq!(lunar(22, 1, 2023), (1, 1, 2023, false));
        assert_eq!(lunar(10, 2, 2024), (1, 1, 2024, false));
        assert_eq!(lunar(29, 1, 2025), (1, 1, 2025, false));
        assert_eq!(lunar(17, 2, 2026), (1, 1, 2026, false));
        assert_eq!(lunar(25, 1, 2020), (1, 1, 2020, false));
        // Tết Việt Nam lệch Tết Trung Quốc (giờ +7 so với +8)
        assert_eq!(lunar(21, 1, 1985), (1, 1, 1985, false));
        assert_eq!(lunar(17, 2, 2007), (1, 1, 2007, false));
        // Giao thừa: ngày cuối năm âm trước
        assert_eq!(lunar(16, 2, 2026).1, 12);
        assert_eq!(lunar(16, 2, 2026).2, 2025);
    }

    #[test]
    fn thang_nhuan() {
        // Nhuận tháng 2 Quý Mão 2023, tháng 4 Canh Tý 2020, tháng 6 Ất Tỵ 2025
        assert_eq!(lunar(22, 3, 2023), (1, 2, 2023, true));
        assert_eq!(lunar(21, 3, 2023).3, false);
        assert_eq!(lunar(23, 5, 2020), (1, 4, 2020, true));
        assert_eq!(lunar(25, 7, 2025), (1, 6, 2025, true));
        assert_eq!(lunar(23, 8, 2025), (1, 7, 2025, false));
    }

    #[test]
    fn ngay_20_11_2026() {
        // Đối chiếu trang lịch âm: 12/10 Bính Ngọ, ngày Mậu Tuất, tháng Kỷ Hợi, Lập đông, Kim Quỹ hoàng đạo,
        // giờ hoàng đạo Dần, Thìn, Tỵ, Thân, Dậu, Hợi
        let x = day_detail(20, 11, 2026).unwrap();
        assert_eq!((x.ld, x.lm, x.ly, x.leap), (12, 10, 2026, false));
        assert_eq!(x.can_chi_day, "Mậu Tuất");
        assert_eq!(x.can_chi_month, "Kỷ Hợi");
        assert_eq!(x.can_chi_year, "Bính Ngọ");
        assert_eq!(x.tiet_khi, "Lập đông");
        assert_eq!(x.than, "Kim Quỹ");
        assert!(x.good);
        let names: Vec<&str> = gio_hoang_dao(jd_from_date(20, 11, 2026)).iter().map(|h| h.0).collect();
        assert_eq!(names, vec!["Dần", "Thìn", "Tỵ", "Thân", "Dậu", "Hợi"]);
        assert_eq!(x.hours[0], "Dần (3–5)");
    }

    #[test]
    fn gio_ty_va_le() {
        // Giờ Tý viết 23–1
        let jd = (0..12).map(|i| jd_from_date(1, 1, 2026) + i).find(|jd| (jd + 1).rem_euclid(12) == 0).unwrap();
        assert_eq!(gio_hoang_dao(jd)[0], ("Tý", 23, 1));
        assert_eq!(day_detail(17, 2, 2026).unwrap().festival, Some("Tết Nguyên đán"));
        assert_eq!(day_detail(18, 2, 2026).unwrap().festival, None);
    }

    #[test]
    fn sau_than_hoang_dao_moi_vong() {
        // Mỗi vòng 12 ngày có đúng 6 ngày hoàng đạo, ở mọi tháng
        for m in 1..=12 {
            let base = jd_from_date(1, 1, 2026);
            assert_eq!((0..12).filter(|i| is_hoang_dao(base + i, m)).count(), 6);
        }
    }

    #[test]
    fn thang_duong_lich() {
        let cells = month_cells(2, 2026);
        assert_eq!(cells.len(), 28);
        assert_eq!((cells[16].d, cells[16].ld, cells[16].lm), (17, 1, 1));
        assert!(cells[16].fest);
        assert_eq!(month_cells(2, 2024).len(), 29);
        assert!(month_cells(13, 2026).is_empty());
        assert!(month_cells(1, 1700).is_empty());
        // Độ dài tháng âm: 29 hoặc 30
        let x = day_detail(20, 11, 2026).unwrap();
        assert!(x.month_days == 29 || x.month_days == 30);
    }
}

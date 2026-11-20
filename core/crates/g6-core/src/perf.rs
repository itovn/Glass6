//! Hiệu suất hệ thống cho dải kính trên màn hình chính: CPU, RAM, đĩa, mạng.
//!
//! Vỏ ObjC chỉ đọc các số đếm thô của hệ thống (tích tắc CPU, trang nhớ, khối đĩa, byte qua mạng) rồi đưa hai mẫu liên tiếp
//! vào đây; lõi tính phần trăm, tốc độ và dựng sẵn chuỗi hiển thị. Tách vậy để phép tính (số đếm quay vòng, chia cho 0, mạng
//! vừa bật lại…) thử được trên PC.

use serde::Serialize;
use serde_json::Value;

/// Một lần đọc số đếm thô. Mọi số là số đếm cộng dồn hoặc số byte tại thời điểm `t_ms`.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Sample {
    /// Thời điểm đọc, mili giây theo đồng hồ đơn điệu.
    pub t_ms: f64,
    /// Tích tắc CPU bận (người dùng + hệ thống + nice) và tổng tích tắc, cộng dồn từ lúc khởi động.
    pub cpu_busy: f64,
    pub cpu_total: f64,
    /// Bộ nhớ: còn dùng được (trang trống + trang không hoạt động) và tổng — byte.
    pub mem_free: f64,
    pub mem_total: f64,
    /// Phân vùng dữ liệu: còn trống / tổng — byte.
    pub disk_free: f64,
    pub disk_total: f64,
    /// Byte đã nhận / đã gửi qua Wi-Fi + di động, cộng dồn (số đếm 32 bit của nhân: quay vòng ở 4 GB).
    pub net_in: f64,
    pub net_out: f64,
}

impl Sample {
    pub fn from_json(v: &Value) -> Sample {
        let n = |key: &str| match v.get(key).and_then(Value::as_f64) {
            Some(x) if x.is_finite() && x >= 0.0 => x,
            _ => 0.0,
        };
        Sample {
            t_ms: n("t"),
            cpu_busy: n("cpuBusy"),
            cpu_total: n("cpuTotal"),
            mem_free: n("memFree"),
            mem_total: n("memTotal"),
            disk_free: n("diskFree"),
            disk_total: n("diskTotal"),
            net_in: n("netIn"),
            net_out: n("netOut"),
        }
    }
}

/// Kết quả hiển thị: tỉ lệ 0–1 cho các thanh, tốc độ byte / giây, và chuỗi đã dựng.
#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct Reading {
    /// CPU bận trong khoảng giữa hai mẫu.
    pub cpu: f32,
    /// Phần RAM không còn dùng được ngay (tổng − còn dùng được): gồm cả phần nhân và bộ xử lý hình giữ riêng, thứ mà bảng
    /// đếm trang của nhân không kể vào «đang hoạt động».
    pub ram: f32,
    /// Phần đĩa đã dùng.
    pub disk: f32,
    /// Tốc độ nhận / gửi, byte mỗi giây.
    pub down: f64,
    pub up: f64,
    pub text: Text,
}

#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct Text {
    /// «23%»
    pub cpu: String,
    /// RAM còn dùng được: «148 MB»
    pub ram: String,
    /// Đĩa còn trống: «51,0 GB»
    pub disk: String,
    /// «12 KB/s», «1,2 MB/s»
    pub down: String,
    pub up: String,
    /// Bản ngắn cho dải thu gọn trên thanh trạng thái của iPhone — RAM còn dùng được: «148M», «1,2G»
    pub ram_short: String,
    /// «12K», «1,2M», «12M»
    pub down_short: String,
    pub up_short: String,
}

const KB: f64 = 1024.0;
const MB: f64 = 1024.0 * 1024.0;
const GB: f64 = 1024.0 * 1024.0 * 1024.0;
/// Số đếm byte mạng của nhân iOS 6 là 32 bit.
const WRAP: f64 = 4_294_967_296.0;
/// Tốc độ cao hơn mức này (1 GB/s) trên iPad đời này là số đếm bị đặt lại (tắt / bật mạng), không phải tốc độ thật.
const MAX_RATE: f64 = GB;

fn fraction(part: f64, total: f64) -> f32 {
    if total > 0.0 {
        (part / total).clamp(0.0, 1.0) as f32
    } else {
        0.0
    }
}

/// Byte / giây giữa hai lần đọc một số đếm cộng dồn 32 bit.
fn rate(prev: f64, cur: f64, seconds: f64) -> f64 {
    if seconds <= 0.0 {
        return 0.0;
    }
    let delta = if cur >= prev {
        cur - prev
    } else if prev < WRAP {
        cur + WRAP - prev // số đếm vừa quay vòng
    } else {
        0.0
    };
    let r = delta / seconds;
    if r > MAX_RATE {
        0.0
    } else {
        r
    }
}

/// Số thập phân kiểu Việt (dấu phẩy), một chữ số lẻ.
fn one_decimal(x: f64) -> String {
    format!("{:.1}", x).replace('.', ",")
}

/// «512 MB», «1,2 GB» — cho RAM.
pub fn format_memory(bytes: f64) -> String {
    if bytes >= GB {
        format!("{} GB", one_decimal(bytes / GB))
    } else {
        format!("{:.0} MB", bytes / MB)
    }
}

/// «51,0 GB», «812 MB» — cho đĩa.
pub fn format_disk(bytes: f64) -> String {
    if bytes >= GB {
        format!("{} GB", one_decimal(bytes / GB))
    } else {
        format!("{:.0} MB", bytes / MB)
    }
}

/// «0 KB/s», «12 KB/s», «1,2 MB/s».
pub fn format_rate(bytes_per_second: f64) -> String {
    if bytes_per_second >= 1000.0 * KB {
        format!("{} MB/s", one_decimal(bytes_per_second / MB))
    } else {
        format!("{:.0} KB/s", bytes_per_second / KB)
    }
}

/// «148M», «1,2G» — bản ngắn của RAM.
pub fn format_memory_short(bytes: f64) -> String {
    if bytes >= GB {
        format!("{}G", one_decimal(bytes / GB))
    } else {
        format!("{:.0}M", bytes / MB)
    }
}

/// «0K», «12K», «1,2M», «12M» — bản ngắn của tốc độ mạng, không quá bốn ký tự.
pub fn format_rate_short(bytes_per_second: f64) -> String {
    if bytes_per_second >= 9.95 * MB {
        format!("{:.0}M", bytes_per_second / MB)
    } else if bytes_per_second >= 999.5 * KB {
        format!("{}M", one_decimal(bytes_per_second / MB))
    } else {
        format!("{:.0}K", bytes_per_second / KB)
    }
}

/// Tính kết quả hiển thị từ hai mẫu liên tiếp. Mẫu đầu tiên (chưa có mẫu trước): truyền chính nó làm `prev` — CPU và mạng ra 0.
pub fn reading(prev: &Sample, cur: &Sample) -> Reading {
    let seconds = (cur.t_ms - prev.t_ms) / 1000.0;
    let (busy, total) = (cur.cpu_busy - prev.cpu_busy, cur.cpu_total - prev.cpu_total);
    let cpu = if total > 0.0 && busy >= 0.0 { fraction(busy, total) } else { 0.0 };
    let ram = fraction(cur.mem_total - cur.mem_free, cur.mem_total);
    let disk = fraction(cur.disk_total - cur.disk_free, cur.disk_total);
    let down = rate(prev.net_in, cur.net_in, seconds);
    let up = rate(prev.net_out, cur.net_out, seconds);
    Reading {
        cpu,
        ram,
        disk,
        down,
        up,
        text: Text {
            cpu: format!("{:.0}%", cpu * 100.0),
            ram: format_memory(cur.mem_free),
            disk: format_disk(cur.disk_free),
            down: format_rate(down),
            up: format_rate(up),
            ram_short: format_memory_short(cur.mem_free),
            down_short: format_rate_short(down),
            up_short: format_rate_short(up),
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn sample(t_ms: f64) -> Sample {
        Sample {
            t_ms,
            cpu_busy: 1000.0,
            cpu_total: 10_000.0,
            mem_free: 148.0 * MB,
            mem_total: 503.0 * MB,
            disk_free: 51.0 * GB,
            disk_total: 57.5 * GB,
            net_in: 1_000_000.0,
            net_out: 500_000.0,
        }
    }

    #[test]
    fn tinh_tu_hai_mau() {
        let a = sample(0.0);
        let mut b = sample(2000.0);
        b.cpu_busy += 46.0;
        b.cpu_total += 200.0;
        b.net_in += 24.0 * KB;
        b.net_out += 6.0 * KB;
        let r = reading(&a, &b);
        assert!((r.cpu - 0.23).abs() < 1e-6);
        assert_eq!(r.text.cpu, "23%");
        assert_eq!(r.text.ram, "148 MB");
        assert_eq!(r.text.disk, "51,0 GB");
        assert_eq!((r.text.down.as_str(), r.text.up.as_str()), ("12 KB/s", "3 KB/s"));
        assert_eq!(r.text.ram_short, "148M");
        assert_eq!((r.text.down_short.as_str(), r.text.up_short.as_str()), ("12K", "3K"));
        assert!((r.ram - 355.0 / 503.0).abs() < 1e-4);
        assert!((r.disk - 6.5 / 57.5).abs() < 1e-4);
    }

    #[test]
    fn mau_dau_tien_va_du_lieu_ky_quac_khong_vo() {
        let a = sample(1000.0);
        // Chưa có mẫu trước: cùng một mẫu → CPU và mạng bằng 0, không chia cho 0
        let r = reading(&a, &a);
        assert_eq!((r.cpu, r.down, r.up), (0.0, 0.0, 0.0));
        assert_eq!(r.text.down, "0 KB/s");
        // Mọi số bằng 0 (không đọc được gì)
        let z = reading(&Sample::default(), &Sample::default());
        assert_eq!((z.cpu, z.ram, z.disk), (0.0, 0.0, 0.0));
        assert_eq!(z.text.ram, "0 MB");
        // «Còn dùng được» lớn hơn tổng (số đo lệch nhau): thanh về 0 chứ không âm
        let mut odd = sample(0.0);
        odd.mem_free = odd.mem_total * 2.0;
        assert_eq!(reading(&odd, &odd).ram, 0.0);
        // Đồng hồ lùi / số đếm CPU lùi
        let mut b = sample(500.0);
        b.cpu_busy -= 10.0;
        let r = reading(&a, &b);
        assert_eq!((r.cpu, r.down), (0.0, 0.0));
    }

    #[test]
    fn so_dem_mang_quay_vong_va_bi_dat_lai() {
        let mut a = sample(0.0);
        let mut b = sample(1000.0);
        // Quay vòng ở 4 GB: 4 294 960 000 → 5000 là đã đi 12 296 byte
        a.net_in = WRAP - 7296.0;
        b.net_in = 5000.0;
        assert!((reading(&a, &b).down - 12_296.0).abs() < 1.0);
        // Tắt / bật mạng: số đếm về 0 từ một giá trị lớn → «quay vòng» ra tốc độ vô lý → coi là 0
        a.net_in = 100.0 * MB;
        b.net_in = 0.0;
        assert_eq!(reading(&a, &b).down, 0.0);
    }

    #[test]
    fn dinh_dang() {
        assert_eq!(format_rate(0.0), "0 KB/s");
        // Bản ngắn: không quá bốn ký tự ở mọi mức
        assert_eq!(format_rate_short(0.0), "0K");
        assert_eq!(format_rate_short(999.0 * KB), "999K");
        assert_eq!(format_rate_short(999.7 * KB), "1,0M");
        assert_eq!(format_rate_short(1.25 * MB), "1,2M");
        assert_eq!(format_rate_short(9.96 * MB), "10M");
        assert_eq!(format_rate_short(87.4 * MB), "87M");
        assert_eq!(format_memory_short(148.0 * MB), "148M");
        assert_eq!(format_memory_short(1.25 * GB), "1,2G");
        assert_eq!(format_rate(999.0 * KB), "999 KB/s");
        assert_eq!(format_rate(1.25 * MB), "1,2 MB/s");
        assert_eq!(format_memory(1.5 * GB), "1,5 GB");
        assert_eq!(format_disk(812.0 * MB), "812 MB");
        assert_eq!(format_disk(51.04 * GB), "51,0 GB");
    }

    #[test]
    fn doc_tu_json() {
        let s = Sample::from_json(&json!({"t": 12.5, "cpuBusy": 3, "cpuTotal": 9, "memFree": -5, "netIn": "x"}));
        assert_eq!((s.t_ms, s.cpu_busy, s.cpu_total, s.mem_free, s.net_in), (12.5, 3.0, 9.0, 0.0, 0.0));
        assert_eq!(Sample::from_json(&json!(null)), Sample::default());
    }
}

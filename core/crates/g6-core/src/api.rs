//! Cửa vào của lõi cho vỏ ObjC.
//!
//! - [`call`]: lệnh điều khiển bằng JSON (như `cbtv_call` của Côn Bằng TV). Luôn trả một đối tượng JSON có `ok`.
//! - [`prepare_backdrop`], [`render_surface`], [`render_surface_shadow`]: đường điểm ảnh, không bọc JSON.
//!
//! Cấu hình hiện hành giữ trong lõi (đặt bằng `config.set`), nên vỏ ObjC chỉ cần nói «dựng bề mặt dock cỡ này».

use std::sync::{Mutex, OnceLock};

use serde_json::{json, Value};

use crate::apps;
use crate::assist;
use crate::bitmap::{downscale, saturate, Bitmap, View};
use crate::blur::box_blur;
use crate::config::Config;
use crate::glass::{self, Placement};
use crate::guard::{self, Dylib};
use crate::icon;
use crate::perf;
use crate::services;
use crate::theme::{self, BackdropPlan, Surface};

static CONFIG: OnceLock<Mutex<Config>> = OnceLock::new();

fn cell() -> &'static Mutex<Config> {
    CONFIG.get_or_init(|| Mutex::new(Config::default()))
}

/// Cấu hình hiện hành (bản chép).
pub fn config() -> Config {
    cell().lock().unwrap_or_else(|e| e.into_inner()).clone()
}

pub fn set_config(c: Config) {
    *cell().lock().unwrap_or_else(|e| e.into_inner()) = c;
}

fn err(msg: &str) -> String {
    json!({ "ok": false, "error": msg }).to_string()
}

/// Một lệnh JSON vào, một JSON ra. Lệnh lạ / JSON hỏng → `{"ok":false,"error":…}`.
pub fn call(input: &str) -> String {
    let v: Value = match serde_json::from_str(input) {
        Ok(v) => v,
        Err(_) => return err("json"),
    };
    let cmd = v.get("cmd").and_then(Value::as_str).unwrap_or("");
    match cmd {
        "version" => json!({ "ok": true, "version": crate::VERSION }).to_string(),
        "config.set" => {
            // `device`: tên mẫu máy (mặc định khác nhau theo mẫu); thiếu = iPad mini 1
            let device = v.get("device").and_then(Value::as_str).unwrap_or("");
            let c = Config::from_prefs_for(v.get("prefs").unwrap_or(&Value::Null), device);
            set_config(c.clone());
            json!({ "ok": true, "config": c }).to_string()
        }
        "config.get" => json!({ "ok": true, "config": config() }).to_string(),
        "theme.dark" => {
            let minutes = v.get("minutes").and_then(Value::as_u64).unwrap_or(0) as u32;
            json!({ "ok": true, "dark": config().is_dark(minutes) }).to_string()
        }
        "glass.metrics" => {
            let Some(surface) = v.get("surface").and_then(Value::as_str).and_then(Surface::parse) else {
                return err("surface");
            };
            let w = v.get("w").and_then(Value::as_u64).unwrap_or(0) as u32;
            let h = v.get("h").and_then(Value::as_u64).unwrap_or(0) as u32;
            let scale = v.get("scale").and_then(Value::as_f64).unwrap_or(1.0) as f32;
            let dark = v.get("dark").and_then(Value::as_bool).unwrap_or(false);
            let cfg = config();
            let spec = theme::glass_spec(surface, w.max(1), h.max(1), scale, dark, &cfg);
            let (blur, dy, alpha) = theme::shadow(surface, scale, dark);
            let slow = theme::backdrop_plan(&cfg, scale, false);
            let fast = theme::backdrop_plan(&cfg, scale, true);
            let (canon_w, canon_h, cap) = theme::canonical_size(surface, w, h, scale);
            json!({
                "ok": true,
                "radius": spec.radius,
                // Cỡ nhỏ nhất giữ nguyên hình góc + phần góc không kéo giãn: cho ảnh 9 mảnh (bóng đổ, kính giả)
                "canonW": canon_w, "canonH": canon_h, "cap": cap,
                "shadowMargin": glass::shadow_margin(blur, dy),
                "shadowBlur": blur, "shadowDy": dy, "shadowAlpha": alpha,
                "backdrop": { "factor": slow.factor, "radius": slow.radius },
                "backdropFast": { "factor": fast.factor, "radius": fast.radius },
            })
            .to_string()
        }
        "guard.scan" => {
            let mut packages: Vec<String> = v
                .get("packages")
                .and_then(Value::as_array)
                .map(|a| a.iter().filter_map(|x| x.as_str().map(String::from)).collect())
                .unwrap_or_default();
            if let Some(text) = v.get("dpkgStatus").and_then(Value::as_str) {
                packages.extend(guard::parse_dpkg_status(text));
            }
            let dylibs: Vec<Dylib> = v
                .get("dylibs")
                .and_then(Value::as_array)
                .map(|a| {
                    a.iter()
                        .filter_map(|d| {
                            Some(Dylib {
                                name: d.get("name")?.as_str()?.to_string(),
                                filters: d
                                    .get("filters")
                                    .and_then(Value::as_array)
                                    .map(|f| f.iter().filter_map(|x| x.as_str().map(String::from)).collect())
                                    .unwrap_or_default(),
                            })
                        })
                        .collect()
                })
                .unwrap_or_default();
            let findings = guard::scan(&packages, &dylibs);
            let blocked = guard::blocked_features(&findings);
            json!({ "ok": true, "findings": findings, "blocked": blocked }).to_string()
        }
        // Danh mục chức năng của nút AssistiveTouch: bảng Cài đặt liệt kê cho người dùng chọn, SpringBoard lấy tên ngắn
        "assist.catalog" => json!({
            "ok": true,
            "actions": assist::ACTIONS,
            "defaults": assist::DEFAULT_SLOTS,
            "defaultCount": assist::DEFAULT_COUNT,
            "maxSlots": assist::MAX_SLOTS,
        })
        .to_string(),
        // Dải hiệu suất trên màn hình chính: hai mẫu số đếm thô liên tiếp → phần trăm, tốc độ và chuỗi hiển thị
        "perf.reading" => {
            let cur = perf::Sample::from_json(v.get("cur").unwrap_or(&Value::Null));
            // Chưa có mẫu trước thì dùng chính mẫu hiện tại (CPU và mạng ra 0)
            let prev = v.get("prev").filter(|p| p.is_object()).map(perf::Sample::from_json).unwrap_or(cur);
            json!({ "ok": true, "reading": perf::reading(&prev, &cur) }).to_string()
        }
        // Glass6UI hỏi một lần lúc nạp vào app: app này được đổi những phần nào
        "app.policy" => {
            let p = apps::policy(v.get("bundle").and_then(Value::as_str).unwrap_or(""));
            json!({ "ok": true, "bars": p.bars, "tables": p.tables, "controls": p.controls, "skeuomorphic": p.skeuomorphic })
                .to_string()
        }
        // Danh mục dịch vụ cho bảng Cài đặt: tên, ghi chú, nhóm + mã các dịch vụ phải tắt của từng hồ sơ dựng sẵn.
        // Lõi chỉ mô tả; tắt / bật thật là việc của công cụ quyền root g6svc.
        "services.catalog" => json!({
            "ok": true,
            "services": services::catalog(),
            "profiles": {
                "stock": services::profile("stock").unwrap_or_default(),
                "balanced": services::profile("balanced").unwrap_or_default(),
            },
        })
        .to_string(),
        _ => err("cmd"),
    }
}

/// Chuẩn bị nền dưới kính từ ảnh gốc: thu nhỏ → làm mờ → tăng bão hoà, theo cấu hình hiện hành.
/// `fast` = ảnh chụp lúc mở tấm kính (thu nhỏ 1/8); không thì hình nền (1/4).
pub fn prepare_backdrop(src: View<'_>, scale: f32, fast: bool) -> Option<Bitmap> {
    prepare_backdrop_pre(src, scale, fast, 1)
}

/// Như [`prepare_backdrop`] cho ảnh gốc đã được thu nhỏ sẵn `pre` lần (vd hình nền vẽ thẳng vào ảnh 1/4 màn hình — nhanh
/// hơn nhiều so với vẽ đủ cỡ rồi mới thu): chỉ thu nhỏ nốt phần còn thiếu. Bán kính mờ tính trên ảnh ra nên không đổi.
pub fn prepare_backdrop_pre(src: View<'_>, scale: f32, fast: bool, pre: u32) -> Option<Bitmap> {
    let plan = backdrop_plan_pre(scale, fast, pre);
    prepare_backdrop_with(src, plan)
}

/// Kế hoạch chuẩn bị nền cho ảnh đã thu nhỏ sẵn `pre` lần.
pub fn backdrop_plan_pre(scale: f32, fast: bool, pre: u32) -> BackdropPlan {
    let mut plan = theme::backdrop_plan(&config(), scale, fast);
    plan.factor = (plan.factor / pre.max(1)).max(1);
    plan
}

pub fn prepare_backdrop_with(src: View<'_>, plan: BackdropPlan) -> Option<Bitmap> {
    let mut small = downscale(src, plan.factor)?;
    box_blur(&mut small, plan.radius, plan.passes);
    saturate(&mut small, plan.saturation);
    Some(small)
}

/// Dựng một bề mặt kính `w × h` điểm ảnh vào `out`, theo cấu hình hiện hành.
pub fn render_surface(
    surface: Surface,
    w: u32,
    h: u32,
    scale: f32,
    dark: bool,
    backdrop: Option<(View<'_>, Placement)>,
    out: &mut [u8],
    out_stride: usize,
) -> Result<(), glass::Error> {
    let spec = theme::glass_spec(surface, w, h, scale, dark, &config());
    glass::render(&spec, backdrop, out, out_stride)
}

/// Hoàn thiện ảnh biểu tượng app `w × h` đã vẽ sẵn trong `pixels`: cắt theo hình bo góc liên tục + viền sáng, tại chỗ.
pub fn finish_icon(w: u32, h: u32, scale: f32, dark: bool, pixels: &mut [u8], stride: usize) -> Result<(), glass::Error> {
    let spec = theme::icon_spec(w, h, scale, dark, &config());
    icon::finish(&spec, pixels, stride)
}

/// Bóng đổ của một bề mặt: ảnh + lề mỗi phía.
pub fn render_surface_shadow(surface: Surface, w: u32, h: u32, scale: f32, dark: bool) -> Option<(Bitmap, u32)> {
    let spec = theme::glass_spec(surface, w, h, scale, dark, &config());
    let (blur, dy, alpha) = theme::shadow(surface, scale, dark);
    glass::render_shadow(&spec, blur, dy, alpha)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parse(s: &str) -> Value {
        serde_json::from_str(s).unwrap()
    }

    #[test]
    fn lenh_hong_tra_loi_co_ok_false() {
        for bad in ["", "{", "[]", "{\"cmd\":5}", "{\"cmd\":\"khong-co\"}", "\"x\""] {
            let r = parse(&call(bad));
            assert_eq!(r["ok"], false, "{bad}");
        }
    }

    #[test]
    fn phien_ban() {
        let r = parse(&call(r#"{"cmd":"version"}"#));
        assert_eq!(r["version"], crate::VERSION);
    }

    #[test]
    fn so_do_be_mat() {
        let r = parse(&call(r#"{"cmd":"glass.metrics","surface":"dock","w":700,"h":96,"scale":1}"#));
        assert_eq!(r["ok"], true);
        assert!(r["radius"].as_f64().unwrap() > 20.0);
        assert!(r["shadowMargin"].as_u64().unwrap() > 10);
        assert_eq!(r["canonH"], 96);
        assert!(r["canonW"].as_u64().unwrap() <= 100 && r["cap"].as_u64().unwrap() > 20);
        assert_eq!(parse(&call(r#"{"cmd":"glass.metrics","surface":"x"}"#))["ok"], false);
        // Kích thước thiếu / bằng 0 không được làm vỡ
        assert_eq!(parse(&call(r#"{"cmd":"glass.metrics","surface":"panel"}"#))["ok"], true);
    }

    #[test]
    fn quet_xung_dot_qua_json() {
        let r = parse(&call(
            r#"{"cmd":"guard.scan","dpkgStatus":"Package: winterboard\nStatus: install ok installed\n",
                "dylibs":[{"name":"CBFloat","filters":["com.apple.springboard"]},{"name":5},{"filters":[]}]}"#,
        ));
        assert_eq!(r["findings"].as_array().unwrap().len(), 2);
        assert!(r["blocked"].as_array().unwrap().iter().any(|x| x == "dock"));
    }

    #[test]
    fn nut_tro_nang_qua_json() {
        let r = parse(&call(r#"{"cmd":"assist.catalog"}"#));
        assert_eq!(r["ok"], true);
        let actions = r["actions"].as_array().unwrap();
        assert!(actions.iter().any(|a| a["id"] == "home" && a["slot"] == true && a["gesture"] == true));
        assert!(actions.iter().any(|a| a["id"] == "menu" && a["slot"] == false));
        assert_eq!(r["maxSlots"], 9);
        // Cấu hình đi kèm trong config.set
        let c = parse(&call(r#"{"cmd":"config.set","prefs":{"featAssist":true,"assistCount":4,"assistSlot1":"dark"}}"#));
        assert_eq!(c["config"]["features"]["assist"], true);
        assert_eq!(c["config"]["assist"]["count"], 4);
        assert_eq!(c["config"]["assist"]["slots"][0], "dark");
        assert_eq!(c["config"]["assist"]["tap"], "menu");
        set_config(Config::default());
    }

    #[test]
    fn hieu_suat_qua_json() {
        let r = parse(&call(
            r#"{"cmd":"perf.reading",
                "prev":{"t":0,"cpuBusy":100,"cpuTotal":1000,"netIn":0,"netOut":0},
                "cur":{"t":1000,"cpuBusy":150,"cpuTotal":1100,"memFree":155189248,"memTotal":524288000,
                       "diskFree":54760833024,"diskTotal":61740154880,"netIn":20480,"netOut":0}}"#,
        ));
        assert_eq!(r["ok"], true);
        let t = &r["reading"]["text"];
        assert_eq!((t["cpu"].as_str(), t["ram"].as_str(), t["down"].as_str()), (Some("50%"), Some("148 MB"), Some("20 KB/s")));
        assert_eq!(t["disk"], "51,0 GB");
        assert!((r["reading"]["ram"].as_f64().unwrap() - 0.704).abs() < 1e-6);
        // Không có mẫu trước, thiếu cả mẫu hiện tại: vẫn trả kết quả bằng 0
        let z = parse(&call(r#"{"cmd":"perf.reading"}"#));
        assert_eq!(z["reading"]["text"]["cpu"], "0%");
    }

    #[test]
    fn chinh_sach_app_qua_json() {
        let r = parse(&call(r#"{"cmd":"app.policy","bundle":"com.apple.Preferences"}"#));
        assert_eq!((r["ok"].clone(), r["bars"].clone(), r["tables"].clone()), (json!(true), json!(true), json!(true)));
        let r = parse(&call(r#"{"cmd":"app.policy","bundle":"com.apple.mobilecal"}"#));
        assert_eq!((r["bars"].clone(), r["controls"].clone(), r["skeuomorphic"].clone()), (json!(false), json!(true), json!(true)));
        // Thiếu mã gói: coi như app thường
        assert_eq!(parse(&call(r#"{"cmd":"app.policy"}"#))["bars"], true);
    }

    #[test]
    fn danh_muc_dich_vu_qua_json() {
        let r = parse(&call(r#"{"cmd":"services.catalog"}"#));
        assert_eq!(r["ok"], true);
        let list = r["services"].as_array().unwrap();
        assert!(list.len() >= 9);
        let first = &list[0];
        assert!(first["id"].is_string() && first["title"].is_string() && first["note"].is_string());
        assert!(first["group"].as_str().is_some_and(|g| ["A", "B", "C"].contains(&g)));
        assert!(first["labels"].as_array().is_some_and(|l| !l.is_empty()));
        assert_eq!(first["files"].as_array().unwrap().len(), first["labels"].as_array().unwrap().len());
        assert!(r["profiles"]["stock"].as_array().unwrap().is_empty());
        assert!(r["profiles"]["balanced"].as_array().unwrap().iter().any(|x| x == "twitter"));
    }

    #[test]
    fn dung_be_mat_tren_nen() {
        let mut bg = Bitmap::new(256, 192).unwrap();
        for (i, p) in bg.data.chunks_exact_mut(4).enumerate() {
            p.copy_from_slice(&[(i % 251) as u8, (i % 127) as u8, (i % 83) as u8, 255]);
        }
        let small = prepare_backdrop(bg.view(), 1.0, false).unwrap();
        assert_eq!((small.w, small.h), (64, 48));
        let (w, h) = (120u32, 40u32);
        let mut out = vec![0u8; (w * h * 4) as usize];
        let place = Placement::scale_offset(4.0, 20.0, 0.25, 0.25);
        render_surface(Surface::Capsule, w, h, 1.0, false, Some((small.view(), place)), &mut out, w as usize * 4)
            .unwrap();
        assert_eq!(out[((h / 2 * w + w / 2) * 4 + 3) as usize], 255);
        let mut icon = vec![200u8; 72 * 72 * 4];
        finish_icon(72, 72, 1.0, false, &mut icon, 72 * 4).unwrap();
        assert_eq!((icon[3], icon[(36 * 72 + 36) * 4 + 3]), (0, 200));
        let (sh, m) = render_surface_shadow(Surface::Capsule, w, h, 1.0, true).unwrap();
        assert_eq!(sh.w, w + 2 * m);
        // Ảnh đã thu nhỏ sẵn 4 lần: không thu nữa, chỉ làm mờ
        let pre = prepare_backdrop_pre(small.view(), 1.0, false, 4).unwrap();
        assert_eq!((pre.w, pre.h), (small.w, small.h));
        let pre = prepare_backdrop_pre(small.view(), 1.0, true, 4).unwrap();
        assert_eq!((pre.w, pre.h), (small.w / 2, small.h / 2));
        assert_eq!(prepare_backdrop_pre(small.view(), 1.0, false, 0).unwrap().w, small.w / 4);
    }
}

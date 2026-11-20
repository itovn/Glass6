//! Số đo và màu của từng bề mặt kính, theo chế độ sáng / tối và thông số người dùng chọn.
//! Số đo ghi theo điểm (pt); nhân với tỉ lệ màn hình thành điểm ảnh lúc lập [`GlassSpec`].

use crate::config::Config;
use crate::glass::GlassSpec;
use crate::icon::{IconSpec, IconStyle};

/// Các bề mặt kính Glass 6 dựng.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Surface {
    /// Dock nổi của màn hình chính.
    Dock,
    /// Khối lớn: mô-đun Control Center, thư mục mở, hộp thoại.
    Panel,
    /// Băng thông báo, thẻ thông báo.
    Banner,
    /// Viên thuốc: HUD âm lượng, nút nổi, nhóm nút trên thanh.
    Capsule,
    /// Dải ngang suốt bề rộng (thanh điều hướng / công cụ kiểu cũ).
    Bar,
    /// Thẻ bo góc trong bảng nhóm.
    Card,
    /// Mặt nạ biểu tượng app.
    Icon,
    /// Tấm lớn suốt bề rộng mang chữ trắng của hệ thống (Trung tâm thông báo): kính đậm hơn để chữ đọc được cả khi nằm
    /// trên app nền trắng. Vỏ ObjC luôn dựng ở chế độ tối.
    Sheet,
    /// Bảng nổi giữa màn hình mang chữ / hình trắng của hệ thống (bảng âm lượng): như `Panel` nhưng kính đậm.
    Hud,
    /// Khung danh sách thông báo trên màn khoá (chữ trắng của hệ thống): bo góc vừa, kính đậm.
    List,
    /// Hộp thoại: kính đậm ở cả hai chế độ (sáng: trắng đục, tối: than) để chữ luôn đọc được trên mọi nền.
    Alert,
}

impl Surface {
    pub fn parse(name: &str) -> Option<Surface> {
        Some(match name {
            "dock" => Surface::Dock,
            "panel" => Surface::Panel,
            "banner" => Surface::Banner,
            "capsule" => Surface::Capsule,
            "bar" => Surface::Bar,
            "card" => Surface::Card,
            "icon" => Surface::Icon,
            "sheet" => Surface::Sheet,
            "hud" => Surface::Hud,
            "list" => Surface::List,
            "alert" => Surface::Alert,
            _ => return None,
        })
    }
}

enum Radius {
    /// Điểm.
    Abs(f32),
    /// Phần của cạnh ngắn.
    Rel(f32),
}

struct Style {
    radius: Radius,
    exponent: f32,
    bevel: f32,
    refraction: f32,
    rim_width: f32,
    /// Hệ số nhân cường độ viền sáng của người dùng.
    rim_gain: f32,
    /// Bóng đổ: độ nhoè, lệch xuống, độ đậm.
    shadow: (f32, f32, f32),
    /// Mức phủ màu tối thiểu (0 = theo «độ trong» của người dùng). Bề mặt mang chữ trắng của hệ thống cần kính đủ đậm.
    min_tint: f32,
}

fn style(surface: Surface) -> Style {
    match surface {
        Surface::Dock => Style {
            radius: Radius::Rel(0.38),
            exponent: 2.8,
            bevel: 14.0,
            refraction: 6.0,
            rim_width: 1.4,
            rim_gain: 1.0,
            shadow: (26.0, 8.0, 0.30),
            min_tint: 0.0,
        },
        Surface::Sheet => Style {
            radius: Radius::Abs(0.0),
            exponent: 2.0,
            bevel: 0.0,
            refraction: 0.0,
            rim_width: 1.0,
            rim_gain: 0.35,
            shadow: (10.0, 2.0, 0.18),
            min_tint: 0.70,
        },
        Surface::List => Style {
            radius: Radius::Abs(18.0),
            exponent: 2.8,
            bevel: 9.0,
            refraction: 3.5,
            rim_width: 1.3,
            rim_gain: 0.9,
            shadow: (20.0, 6.0, 0.28),
            min_tint: 0.60,
        },
        Surface::Alert => Style {
            radius: Radius::Abs(26.0),
            exponent: 2.8,
            bevel: 12.0,
            refraction: 4.5,
            rim_width: 1.4,
            rim_gain: 1.0,
            shadow: (30.0, 10.0, 0.32),
            min_tint: 0.72,
        },
        Surface::Hud => Style {
            radius: Radius::Abs(28.0),
            exponent: 2.8,
            bevel: 13.0,
            refraction: 5.0,
            rim_width: 1.4,
            rim_gain: 1.0,
            shadow: (30.0, 10.0, 0.32),
            min_tint: 0.66,
        },
        Surface::Panel => Style {
            radius: Radius::Abs(28.0),
            exponent: 2.8,
            bevel: 13.0,
            refraction: 5.0,
            rim_width: 1.4,
            rim_gain: 1.0,
            shadow: (30.0, 10.0, 0.32),
            min_tint: 0.0,
        },
        Surface::Banner => Style {
            radius: Radius::Abs(22.0),
            exponent: 2.8,
            bevel: 10.0,
            refraction: 4.0,
            rim_width: 1.3,
            rim_gain: 0.95,
            shadow: (22.0, 8.0, 0.28),
            min_tint: 0.0,
        },
        Surface::Capsule => Style {
            radius: Radius::Rel(0.5),
            exponent: 2.0,
            bevel: 9.0,
            refraction: 3.5,
            rim_width: 1.3,
            rim_gain: 1.0,
            shadow: (16.0, 5.0, 0.26),
            min_tint: 0.0,
        },
        Surface::Bar => Style {
            radius: Radius::Abs(0.0),
            exponent: 2.0,
            bevel: 0.0,
            refraction: 0.0,
            rim_width: 1.0,
            rim_gain: 0.35,
            shadow: (10.0, 2.0, 0.18),
            min_tint: 0.0,
        },
        Surface::Card => Style {
            radius: Radius::Abs(16.0),
            exponent: 2.8,
            bevel: 6.0,
            refraction: 0.0,
            rim_width: 1.0,
            rim_gain: 0.5,
            shadow: (12.0, 3.0, 0.14),
            min_tint: 0.0,
        },
        // Siêu elip bậc 5 phủ kín ô vuông (bán kính bị kẹp về nửa cạnh) — hình biểu tượng của iOS 7 trở đi
        Surface::Icon => Style {
            radius: Radius::Rel(0.37),
            exponent: 5.0,
            bevel: 5.0,
            refraction: 0.0,
            rim_width: 1.2,
            rim_gain: 0.55,
            shadow: (9.0, 3.0, 0.26),
            min_tint: 0.0,
        },
    }
}

/// Thông số tấm kính `w × h` điểm ảnh cho một bề mặt. `scale` = tỉ lệ màn hình (iPad mini 1: 1).
pub fn glass_spec(surface: Surface, w: u32, h: u32, scale: f32, dark: bool, cfg: &Config) -> GlassSpec {
    let st = style(surface);
    let scale = if scale.is_finite() { scale.clamp(1.0, 4.0) } else { 1.0 };
    let radius = radius_px(&st, w, h, scale);
    let (base, tint_alpha) = if dark {
        ([22.0, 22.0, 26.0], lerp(0.66, 0.30, cfg.clarity))
    } else {
        ([255.0, 255.0, 255.0], lerp(0.46, 0.10, cfg.clarity))
    };
    let tint = match cfg.tint {
        // Màu nhuộm của người dùng pha vào màu gốc — nhuộm thẳng 100% thì chữ trên kính khó đọc
        Some(c) => [
            lerp(base[0], c[0] as f32, 0.45),
            lerp(base[1], c[1] as f32, 0.45),
            lerp(base[2], c[2] as f32, 0.45),
        ],
        None => base,
    };
    let reduce = cfg.reduce;
    let tint_alpha = tint_alpha.max(st.min_tint);
    GlassSpec {
        w,
        h,
        radius,
        exponent: st.exponent,
        bevel: st.bevel * scale,
        refraction: if reduce { 0.0 } else { st.refraction * scale },
        rim: cfg.rim * st.rim_gain * if dark { 0.72 } else { 1.0 },
        rim_width: st.rim_width * scale,
        // Nguồn sáng ở trên, hơi lệch trái
        light: (-0.42, -0.91),
        tint,
        tint_alpha,
        sheen: if reduce {
            0.0
        } else if dark {
            0.05
        } else {
            0.10
        },
        fill_alpha: if dark { lerp(0.86, 0.62, cfg.clarity) } else { lerp(0.82, 0.55, cfg.clarity) },
    }
}

/// Thông số cắt + viền sáng cho ảnh biểu tượng app `w × h` điểm ảnh — cùng hình với bề mặt [`Surface::Icon`] (nền thư
/// mục, bóng đổ của biểu tượng) để hai thứ chồng khít nhau.
pub fn icon_spec(w: u32, h: u32, scale: f32, dark: bool, cfg: &Config) -> IconSpec {
    let st = style(Surface::Icon);
    let scale = if scale.is_finite() { scale.clamp(1.0, 4.0) } else { 1.0 };
    IconSpec {
        w,
        h,
        radius: radius_px(&st, w, h, scale),
        exponent: st.exponent,
        rim: cfg.rim * st.rim_gain * if dark { 0.8 } else { 1.0 },
        rim_width: st.rim_width * scale,
        light: (-0.42, -0.91),
        style: IconStyle::from_index(cfg.icon_style),
        // Chưa chọn màu nhuộm: xanh dương
        tint: match cfg.icon_tint {
            Some(c) => [c[0] as f32, c[1] as f32, c[2] as f32],
            None => [10.0, 132.0, 255.0],
        },
    }
}

/// Bán kính góc (điểm ảnh) của một bề mặt cỡ `w × h`.
fn radius_px(st: &Style, w: u32, h: u32, scale: f32) -> f32 {
    let radius = match st.radius {
        Radius::Abs(pt) => pt * scale,
        Radius::Rel(k) => w.min(h) as f32 * k,
    };
    // Góc siêu elip trông nhỏ hơn cung tròn cùng bán kính → nới bán kính để mắt thấy đúng cỡ
    radius * (1.0 + 0.12 * (st.exponent - 2.0))
}

/// Cỡ nhỏ nhất mà bề mặt vẫn giữ nguyên hình bốn góc — để dựng bóng đổ (hoặc kính giả) một lần ở cỡ nhỏ rồi kéo giãn
/// phần giữa (ảnh 9 mảnh). Trả `(rộng, cao, phần góc không được kéo giãn)` theo điểm ảnh.
pub fn canonical_size(surface: Surface, w: u32, h: u32, scale: f32) -> (u32, u32, u32) {
    let st = style(surface);
    let scale = if scale.is_finite() { scale.clamp(1.0, 4.0) } else { 1.0 };
    let (w, h) = (w.max(1), h.max(1));
    let short = w.min(h);
    // Bán kính thật sau khi kẹp vào nửa cạnh ngắn (như Shape::new)
    let cap = radius_px(&st, w, h, scale).min(short as f32 * 0.5).ceil() as u32;
    let core = cap * 2 + 2;
    match st.radius {
        Radius::Abs(_) => (w.min(core), h.min(core), cap),
        // Bán kính tính theo cạnh ngắn: giữ nguyên cạnh ngắn, chỉ rút cạnh dài (không ngắn hơn cạnh ngắn)
        Radius::Rel(_) => {
            let long = core.max(short);
            (w.min(long), h.min(long), cap)
        }
    }
}

/// Bóng đổ của một bề mặt (điểm ảnh): độ nhoè, lệch xuống, độ đậm.
pub fn shadow(surface: Surface, scale: f32, dark: bool) -> (f32, f32, f32) {
    let (blur, dy, alpha) = style(surface).shadow;
    let scale = if scale.is_finite() { scale.clamp(1.0, 4.0) } else { 1.0 };
    (blur * scale, dy * scale, if dark { (alpha * 1.35f32).min(0.6) } else { alpha })
}

/// Cách chuẩn bị nền dưới kính từ ảnh gốc (hình nền hoặc ảnh chụp màn hình).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct BackdropPlan {
    /// Thu nhỏ bao nhiêu lần trước khi làm mờ.
    pub factor: u32,
    /// Bán kính box blur trên ảnh đã thu nhỏ.
    pub radius: u32,
    pub passes: u32,
    pub saturation: f32,
}

/// `fast` = ảnh chụp lúc mở tấm kính (cần nhanh, thu nhỏ 1/8); không thì là hình nền (làm một lần, thu nhỏ 1/4 cho mịn).
pub fn backdrop_plan(cfg: &Config, scale: f32, fast: bool) -> BackdropPlan {
    let scale = if scale.is_finite() { scale.clamp(1.0, 4.0) } else { 1.0 };
    let factor = (if fast { 8.0 } else { 4.0 } * scale) as u32;
    // Độ lệch chuẩn theo điểm: 6 pt (gần như trong) → 30 pt (mờ hẳn)
    let sigma_pt = lerp(6.0, 30.0, cfg.blur);
    let radius = ((sigma_pt * scale / factor as f32).round() as u32).max(1);
    BackdropPlan { factor, radius, passes: 3, saturation: 1.0 + 0.9 * cfg.vibrancy }
}

#[inline]
fn lerp(a: f32, b: f32, t: f32) -> f32 {
    a + (b - a) * t.clamp(0.0, 1.0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ten_be_mat() {
        assert_eq!(Surface::parse("dock"), Some(Surface::Dock));
        assert_eq!(Surface::parse("Dock"), None);
        assert_eq!(Surface::parse(""), None);
    }

    #[test]
    fn toi_duc_hon_sang() {
        let cfg = Config::default();
        let l = glass_spec(Surface::Panel, 300, 200, 1.0, false, &cfg);
        let d = glass_spec(Surface::Panel, 300, 200, 1.0, true, &cfg);
        assert!(d.tint_alpha > l.tint_alpha);
        assert!(d.tint[0] < 60.0 && l.tint[0] > 200.0);
    }

    #[test]
    fn giam_hieu_ung_bo_khuc_xa() {
        let mut cfg = Config::default();
        cfg.reduce = true;
        let s = glass_spec(Surface::Dock, 700, 100, 1.0, false, &cfg);
        assert_eq!(s.refraction, 0.0);
        assert_eq!(s.sheen, 0.0);
    }

    #[test]
    fn so_do_nhan_theo_ti_le_man_hinh() {
        let cfg = Config::default();
        let a = glass_spec(Surface::Panel, 300, 200, 1.0, false, &cfg);
        let b = glass_spec(Surface::Panel, 600, 400, 2.0, false, &cfg);
        assert!((b.radius - a.radius * 2.0).abs() < 0.01);
        assert!((b.bevel - a.bevel * 2.0).abs() < 0.01);
        let nan = glass_spec(Surface::Panel, 300, 200, f32::NAN, false, &cfg);
        assert_eq!(nan.radius, a.radius);
    }

    #[test]
    fn co_nho_giu_nguyen_goc() {
        let cfg = Config::default();
        let all = [
            Surface::Dock,
            Surface::Panel,
            Surface::Banner,
            Surface::Capsule,
            Surface::Bar,
            Surface::Card,
            Surface::Icon,
            Surface::Sheet,
            Surface::Hud,
            Surface::List,
            Surface::Alert,
        ];
        for surface in all {
            for (w, h) in [(700u32, 100u32), (100, 700), (320, 400), (52, 52), (10, 6), (1, 1)] {
                let (cw, ch, cap) = canonical_size(surface, w, h, 1.0);
                assert!(cw <= w && ch <= h && cw >= 1 && ch >= 1, "{surface:?} {w}x{h} → {cw}x{ch}");
                let full = glass_spec(surface, w, h, 1.0, false, &cfg);
                let small = glass_spec(surface, cw, ch, 1.0, false, &cfg);
                // Bán kính sau khi kẹp vào nửa cạnh ngắn phải như nhau
                let clamp = |s: &GlassSpec| s.radius.min(s.w.min(s.h) as f32 * 0.5);
                let (rf, rs) = (clamp(&full), clamp(&small));
                assert!((rf - rs).abs() < 0.01, "{surface:?} {w}x{h}: {rf} / {rs}");
                assert!(cap as f32 >= rf - 0.001);
            }
        }
        // Khối lớn rút được nhiều
        let (cw, ch, _) = canonical_size(Surface::Panel, 320, 400, 1.0);
        assert!(cw < 100 && ch < 100);
    }

    #[test]
    fn bieu_tuong_cung_hinh_voi_be_mat_icon() {
        let cfg = Config::default();
        let icon = icon_spec(72, 72, 1.0, false, &cfg);
        let tile = glass_spec(Surface::Icon, 72, 72, 1.0, false, &cfg);
        assert_eq!((icon.radius, icon.exponent), (tile.radius, tile.exponent));
        assert!(icon.rim > 0.0 && icon.rim < cfg.rim);
        // Ảnh @2x: viền dày gấp đôi, hình không đổi tỉ lệ
        let big = icon_spec(144, 144, 2.0, false, &cfg);
        assert!((big.radius - icon.radius * 2.0).abs() < 0.01 && (big.rim_width - icon.rim_width * 2.0).abs() < 0.01);
    }

    #[test]
    fn be_mat_mang_chu_trang_luon_du_dam() {
        // Người dùng kéo «độ trong» hết cỡ thì tấm thường gần như trong, còn tấm mang chữ trắng của hệ thống vẫn đủ đậm
        let mut cfg = Config::default();
        cfg.clarity = 1.0;
        let bar = glass_spec(Surface::Bar, 480, 500, 1.0, true, &cfg);
        let sheet = glass_spec(Surface::Sheet, 480, 500, 1.0, true, &cfg);
        let hud = glass_spec(Surface::Hud, 160, 160, 1.0, true, &cfg);
        assert!(bar.tint_alpha < 0.4);
        assert!(sheet.tint_alpha >= 0.7 && hud.tint_alpha >= 0.66);
        assert_eq!(Surface::parse("sheet"), Some(Surface::Sheet));
        assert_eq!(Surface::parse("hud"), Some(Surface::Hud));
    }

    #[test]
    fn ke_hoach_nen() {
        let cfg = Config::default();
        let slow = backdrop_plan(&cfg, 1.0, false);
        let fast = backdrop_plan(&cfg, 1.0, true);
        assert_eq!((slow.factor, fast.factor), (4, 8));
        assert!(slow.radius >= fast.radius && fast.radius >= 1);
    }
}

//! Dựng một tấm kính thành một ảnh: nền đã mờ → khúc xạ viền → phủ màu → viền sáng → cắt theo hình, khử răng cưa.
//! CALayer chỉ việc vẽ ảnh này — không bắt GPU cắt bo góc hay vẽ ngoài màn hình.

use crate::bitmap::{Bitmap, View};
use crate::blur::box_blur_gray;
use crate::shape::Shape;
use crate::MAX_SIDE;

/// Thông số một tấm kính, đơn vị điểm ảnh (đã nhân tỉ lệ màn hình).
#[derive(Clone, Copy, Debug)]
pub struct GlassSpec {
    pub w: u32,
    pub h: u32,
    pub radius: f32,
    /// Số mũ góc bo (xem [`Shape`]).
    pub exponent: f32,
    /// Bề rộng dải vát sát mép — vùng có khúc xạ và sáng dần.
    pub bevel: f32,
    /// Độ lệch lấy mẫu nền ngay tại mép (điểm ảnh của tấm kính). 0 = không khúc xạ.
    pub refraction: f32,
    /// Cường độ viền sáng 0–1.
    pub rim: f32,
    /// Bề dày viền sáng.
    pub rim_width: f32,
    /// Véc-tơ đơn vị chỉ về phía nguồn sáng (toạ độ màn hình, y xuống dưới).
    pub light: (f32, f32),
    /// Màu phủ (R, G, B 0–255) và mức phủ 0–1.
    pub tint: [f32; 3],
    pub tint_alpha: f32,
    /// Vệt sáng mờ nửa trên 0–1.
    pub sheen: f32,
    /// Độ đục khi không có nền (kính giả cho thanh trong app) 0–1.
    pub fill_alpha: f32,
}

/// Tấm kính nằm ở đâu trên ảnh nền: phép biến đổi affine (cùng bố cục `CGAffineTransform`) đưa điểm ảnh `(px, py)` của
/// kính tới điểm `(a·px + c·py + tx, b·px + d·py + ty)` của nền. Cần affine đủ chứ không chỉ co + dời: iPad nằm ngang thì
/// giao diện xoay 90° so với khung hình mà ảnh nền chụp theo.
#[derive(Clone, Copy, Debug)]
pub struct Placement {
    pub a: f32,
    pub b: f32,
    pub c: f32,
    pub d: f32,
    pub tx: f32,
    pub ty: f32,
}

impl Placement {
    /// Không xoay: kính ở `(x, y)` trên nền, mỗi điểm ảnh kính ứng `sx × sy` điểm ảnh nền.
    pub fn scale_offset(x: f32, y: f32, sx: f32, sy: f32) -> Placement {
        Placement { a: sx, b: 0.0, c: 0.0, d: sy, tx: x, ty: y }
    }

    #[inline]
    pub fn map(&self, px: f32, py: f32) -> (f32, f32) {
        (self.a * px + self.c * py + self.tx, self.b * px + self.d * py + self.ty)
    }

    pub fn is_finite(&self) -> bool {
        [self.a, self.b, self.c, self.d, self.tx, self.ty].iter().all(|v| v.is_finite())
    }
}

#[derive(Debug, PartialEq, Eq)]
pub enum Error {
    /// Kích thước bằng 0 hoặc quá lớn.
    Size,
    /// Vùng nhớ ra không đủ cho kích thước đã khai.
    Buffer,
    /// Ảnh nền hỏng (thiếu dữ liệu, bước hàng sai).
    Backdrop,
}

/// Dựng tấm kính vào `out` (BGRA nhân sẵn alpha, bước hàng `out_stride`).
/// Có `backdrop` thì kính trong thật (alpha = độ phủ của hình); không có thì ra kính giả bán trong suốt.
pub fn render(
    spec: &GlassSpec,
    backdrop: Option<(View<'_>, Placement)>,
    out: &mut [u8],
    out_stride: usize,
) -> Result<(), Error> {
    let (w, h) = (spec.w as usize, spec.h as usize);
    if w == 0 || h == 0 || spec.w > MAX_SIDE || spec.h > MAX_SIDE {
        return Err(Error::Size);
    }
    let row = w * 4;
    if out_stride < row || out.len() < (h - 1) * out_stride + row {
        return Err(Error::Buffer);
    }
    if let Some((v, p)) = &backdrop {
        if !v.is_valid() || !p.is_finite() {
            return Err(Error::Backdrop);
        }
    }

    let shape = Shape::new(spec.w as f32, spec.h as f32, finite(spec.radius), spec.exponent);
    let bevel = finite(spec.bevel).clamp(0.0, shape.hw.min(shape.hh));
    // Ánh xạ độ sâu phải đơn điệu, không thì ảnh gấp ngược: lệch tối đa < nửa dải vát
    let refr = finite(spec.refraction).clamp(0.0, bevel * 0.45);
    let rim = finite(spec.rim).clamp(0.0, 1.0);
    let rim_w = finite(spec.rim_width).clamp(0.5, 16.0);
    let (lx, ly) = normalize(spec.light);
    let tint_a = finite(spec.tint_alpha).clamp(0.0, 1.0);
    let tint = [clamp255(spec.tint[2]), clamp255(spec.tint[1]), clamp255(spec.tint[0])]; // → B, G, R
    let sheen = finite(spec.sheen).clamp(0.0, 1.0);
    let fill_a = finite(spec.fill_alpha).clamp(0.0, 1.0);
    let margin = bevel.max(rim_w) + 1.5;
    // Hàng / cột gần mép hơn chừng này có thể rơi vào vùng góc bo
    let corner = margin.max(shape.r);
    let inv_h = 1.0 / spec.h as f32;
    let (wf, hf) = (spec.w as f32, spec.h as f32);
    // Thông số cho đường số nguyên (phần giữa tấm kính): hệ số 0–256
    let tint_i = [tint[0] as i32, tint[1] as i32, tint[2] as i32];
    let tint_k = (tint_a * 256.0 + 0.5) as i32;
    let src = backdrop.as_ref().map(|(v, p)| (Sampler::new(v), *p));

    for y in 0..h {
        let fy = y as f32 + 0.5;
        let line = &mut out[y * out_stride..y * out_stride + row];
        // Vệt sáng: mạnh nhất ở mép trên, tắt ở giữa
        let sy_t = (1.0 - fy * inv_h * 2.0).max(0.0);
        let sheen_k = sheen * sy_t * sy_t;

        // Chia hàng làm ba đoạn: hai đoạn sát mép trái / phải tính đủ (khúc xạ, viền sáng, khử răng cưa — số thực),
        // đoạn giữa chắc chắn nằm sâu trong kính nên chỉ lấy mẫu nền + phủ màu bằng số nguyên. Đoạn giữa là phần lớn
        // điểm ảnh của tấm kính.
        let edge_y = fy.min(hf - fy);
        let side = if edge_y < margin {
            wf
        } else if edge_y < corner {
            corner
        } else {
            margin
        };
        let x_lo = (side.ceil() as usize).min(w);
        let x_hi = w.saturating_sub(x_lo).max(x_lo);

        if x_hi > x_lo {
            let light_k = (sheen_k.min(1.0) * 256.0 + 0.5) as i32;
            match &src {
                Some((sampler, p)) => {
                    let (bx, by) = p.map(x_lo as f32 + 0.5, fy);
                    let mut u = to_fixed(bx - 0.5);
                    let mut v = to_fixed(by - 0.5);
                    let (du, dv) = (to_fixed(p.a), to_fixed(p.b));
                    let n = (x_hi - x_lo) as i64;
                    // Cả đoạn nằm gọn trong ảnh nền (đầu và cuối đều trong, ở giữa tuyến tính) thì khỏi kẹp từng điểm
                    let safe = sampler.inside(u, v) && sampler.inside(u + du * (n - 1), v + dv * (n - 1));
                    for px in line[x_lo * 4..x_hi * 4].chunks_exact_mut(4) {
                        let s = if safe { sampler.fetch(u, v) } else { sampler.fetch_clamped(u, v) };
                        for c in 0..3 {
                            // +128: làm tròn thay vì cắt bỏ (cắt hai lần liền lệch tới 2 mức so với đường số thực)
                            let mut val = s[c] + (((tint_i[c] - s[c]) * tint_k + 128) >> 8);
                            val += ((255 - val) * light_k + 128) >> 8;
                            px[c] = val.clamp(0, 255) as u8;
                        }
                        px[3] = 255;
                        u += du;
                        v += dv;
                    }
                }
                None => {
                    // Kính giả: cả đoạn một màu
                    let light = sheen_k.min(1.0);
                    let a = fill_a + (1.0 - fill_a) * light;
                    let mut px4 = [0u8; 4];
                    for c in 0..3 {
                        px4[c] = ((tint[c] + (255.0 - tint[c]) * light) * a + 0.5) as u8;
                    }
                    px4[3] = (255.0 * a + 0.5) as u8;
                    for px in line[x_lo * 4..x_hi * 4].chunks_exact_mut(4) {
                        px.copy_from_slice(&px4);
                    }
                }
            }
        }

        for x in (0..x_lo).chain(x_hi..w) {
            let fx = x as f32 + 0.5;
            let o = x * 4;
            let hit = shape.eval(fx, fy);
            let cov = Shape::coverage(hit.d);
            if cov <= 0.0 {
                line[o..o + 4].copy_from_slice(&[0, 0, 0, 0]);
                continue;
            }
            let inside = (-hit.d).max(0.0);
            let depth_t = if bevel > 0.0 { (inside / bevel).min(1.0) } else { 1.0 };
            let edge = 1.0 - smoothstep(inside / rim_w);
            let (nx, ny) = (hit.nx, hit.ny);

            // 1. Màu nền (có khúc xạ viền) hoặc màu phủ thuần
            let (mut c, mut alpha) = match &src {
                Some((sampler, p)) => {
                    let k = 1.0 - depth_t;
                    let disp = refr * k * k;
                    // Lấy mẫu lùi vào trong theo pháp tuyến: dải sát mép hiện phần nền nằm sâu hơn — như nhìn qua mép thấu kính
                    let (bx, by) = p.map(fx - nx * disp, fy - ny * disp);
                    let s = sampler.fetch_clamped(to_fixed(bx - 0.5), to_fixed(by - 0.5));
                    (
                        [
                            mix(s[0] as f32, tint[0], tint_a),
                            mix(s[1] as f32, tint[1], tint_a),
                            mix(s[2] as f32, tint[2], tint_a),
                        ],
                        1.0,
                    )
                }
                None => (tint, fill_a),
            };

            // 2. Ánh sáng: vệt sáng nửa trên, sáng dần trong dải vát, viền sáng theo hướng nguồn sáng
            let mut light = sheen_k;
            if depth_t < 1.0 {
                let k = 1.0 - depth_t;
                light += rim * 0.10 * k * k;
            }
            if edge > 0.0 {
                let ndl = nx * lx + ny * ly;
                let main = ndl.max(0.0);
                let back = (-ndl).max(0.0);
                light += rim * edge * (0.22 + 0.78 * main * main.sqrt() + 0.45 * back * back * back);
            }
            let light = light.min(1.0);
            if light > 0.0 {
                for ch in c.iter_mut() {
                    *ch += (255.0 - *ch) * light;
                }
                // Kính giả: chỗ có ánh sáng thì đục hơn, không thì viền sáng chìm vào nền
                alpha += (1.0 - alpha) * light;
            }

            // 3. Cắt theo hình, nhân sẵn alpha
            let a = alpha * cov;
            line[o] = (c[0] * a + 0.5) as u8;
            line[o + 1] = (c[1] * a + 0.5) as u8;
            line[o + 2] = (c[2] * a + 0.5) as u8;
            line[o + 3] = (255.0 * a + 0.5) as u8;
        }
    }
    Ok(())
}

/// Toạ độ ảnh nền dạng dấu phẩy tĩnh 48.16 (i64: phép biến đổi kỳ quặc cũng không tràn khi cộng dồn dọc một hàng).
#[inline]
fn to_fixed(v: f32) -> i64 {
    // Kẹp trước khi đổi: toạ độ xa hơn ±2^20 điểm ảnh đằng nào cũng bị kẹp về mép ảnh
    (v.clamp(-1_048_576.0, 1_048_576.0) * 65536.0) as i64
}

/// Lấy mẫu song tuyến bằng số nguyên trên ảnh nền (trọng số 8 bit). Trả B, G, R trong 0–255.
struct Sampler<'a> {
    data: &'a [u8],
    stride: usize,
    w: i64,
    h: i64,
}

impl<'a> Sampler<'a> {
    fn new(v: &View<'a>) -> Sampler<'a> {
        Sampler { data: v.data, stride: v.stride, w: v.w as i64, h: v.h as i64 }
    }

    /// Bốn điểm quanh `(u, v)` đều nằm trong ảnh.
    #[inline]
    fn inside(&self, u: i64, v: i64) -> bool {
        let (x, y) = (u >> 16, v >> 16);
        x >= 0 && y >= 0 && x + 1 < self.w && y + 1 < self.h
    }

    /// Chỉ gọi khi [`Sampler::inside`] đúng. (Vẫn kiểm tầm mảng — sai sót ở bên gọi thì ra màu đen chứ không đọc bậy.)
    #[inline]
    fn fetch(&self, u: i64, v: i64) -> [i32; 3] {
        let i = (v >> 16) as usize * self.stride + (u >> 16) as usize * 4;
        let (Some(p), Some(q)) = (self.data.get(i..i + 8), self.data.get(i + self.stride..i + self.stride + 8)) else {
            return [0; 3];
        };
        let wx = ((u >> 8) & 0xFF) as i32;
        let wy = ((v >> 8) & 0xFF) as i32;
        let mut out = [0i32; 3];
        for c in 0..3 {
            let top = p[c] as i32 * (256 - wx) + p[c + 4] as i32 * wx;
            let bot = q[c] as i32 * (256 - wx) + q[c + 4] as i32 * wx;
            out[c] = (top * (256 - wy) + bot * wy + (1 << 15)) >> 16;
        }
        out
    }

    /// Như [`Sampler::fetch`] nhưng toạ độ ngoài ảnh thì lặp lại điểm ngoài cùng.
    #[inline]
    fn fetch_clamped(&self, u: i64, v: i64) -> [i32; 3] {
        let (x, y) = (u >> 16, v >> 16);
        let x0 = x.clamp(0, self.w - 1) as usize;
        let x1 = (x + 1).clamp(0, self.w - 1) as usize;
        let y0 = y.clamp(0, self.h - 1) as usize;
        let y1 = (y + 1).clamp(0, self.h - 1) as usize;
        let at = |xx: usize, yy: usize| -> &[u8] {
            let i = yy * self.stride + xx * 4;
            self.data.get(i..i + 3).unwrap_or(&[0, 0, 0])
        };
        let (a, b, c, d) = (at(x0, y0), at(x1, y0), at(x0, y1), at(x1, y1));
        let wx = ((u >> 8) & 0xFF) as i32;
        let wy = ((v >> 8) & 0xFF) as i32;
        let mut out = [0i32; 3];
        for ch in 0..3 {
            let top = a[ch] as i32 * (256 - wx) + b[ch] as i32 * wx;
            let bot = c[ch] as i32 * (256 - wx) + d[ch] as i32 * wx;
            out[ch] = (top * (256 - wy) + bot * wy + (1 << 15)) >> 16;
        }
        out
    }
}

/// Bóng đổ của tấm kính: ảnh rộng hơn kính `margin` mỗi phía, phần nằm dưới kính đã khoét (kính trong, không để bóng lọt qua).
/// Trả về ảnh và `margin`.
pub fn render_shadow(spec: &GlassSpec, blur: f32, dy: f32, alpha: f32) -> Option<(Bitmap, u32)> {
    if spec.w == 0 || spec.h == 0 {
        return None;
    }
    let blur = finite(blur).clamp(0.0, 64.0);
    let dy = finite(dy).clamp(-64.0, 64.0);
    let alpha = finite(alpha).clamp(0.0, 1.0);
    let margin = shadow_margin(blur, dy);
    let (w, h) = (spec.w.checked_add(margin * 2)?, spec.h.checked_add(margin * 2)?);
    let mut out = Bitmap::new(w, h)?;
    let (wu, hu) = (w as usize, h as usize);
    let shape = Shape::new(spec.w as f32, spec.h as f32, finite(spec.radius), spec.exponent);
    let m = margin as f32;

    let mut gray = vec![0u8; wu * hu];
    for y in 0..hu {
        let fy = y as f32 + 0.5 - m - dy;
        for x in 0..wu {
            let fx = x as f32 + 0.5 - m;
            let cov = Shape::coverage(shape.eval(fx, fy).d);
            gray[y * wu + x] = (cov * 255.0) as u8;
        }
    }
    // 3 lượt box bán kính r cho độ lệch chuẩn ≈ r: lấy r = blur / 2
    box_blur_gray(&mut gray, wu, hu, (blur * 0.5).round() as u32, 3);
    for y in 0..hu {
        let fy = y as f32 + 0.5 - m;
        for x in 0..wu {
            let fx = x as f32 + 0.5 - m;
            let hole = Shape::coverage(shape.eval(fx, fy).d);
            let a = gray[y * wu + x] as f32 * alpha * (1.0 - hole);
            out.data[(y * wu + x) * 4 + 3] = (a + 0.5) as u8;
        }
    }
    Some((out, margin))
}

/// Lề mỗi phía của ảnh bóng đổ so với tấm kính — vỏ ObjC cần số này để đặt lớp bóng.
pub fn shadow_margin(blur: f32, dy: f32) -> u32 {
    let blur = finite(blur).clamp(0.0, 64.0);
    let dy = finite(dy).clamp(-64.0, 64.0);
    (blur * 1.5 + dy.abs()).ceil() as u32 + 1
}

#[inline]
pub(crate) fn finite(v: f32) -> f32 {
    if v.is_finite() {
        v
    } else {
        0.0
    }
}

#[inline]
fn clamp255(v: f32) -> f32 {
    finite(v).clamp(0.0, 255.0)
}

#[inline]
fn mix(a: f32, b: f32, t: f32) -> f32 {
    a + (b - a) * t
}

#[inline]
pub(crate) fn smoothstep(t: f32) -> f32 {
    let t = t.clamp(0.0, 1.0);
    t * t * (3.0 - 2.0 * t)
}

pub(crate) fn normalize(v: (f32, f32)) -> (f32, f32) {
    let (x, y) = (finite(v.0), finite(v.1));
    let len = (x * x + y * y).sqrt();
    if len < 1e-6 {
        (0.0, -1.0)
    } else {
        (x / len, y / len)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn spec(w: u32, h: u32) -> GlassSpec {
        GlassSpec {
            w,
            h,
            radius: 12.0,
            exponent: 3.0,
            bevel: 8.0,
            refraction: 3.0,
            rim: 0.8,
            rim_width: 1.5,
            light: (-0.5, -0.86),
            tint: [255.0, 255.0, 255.0],
            tint_alpha: 0.2,
            sheen: 0.08,
            fill_alpha: 0.6,
        }
    }

    fn backdrop() -> Bitmap {
        let mut b = Bitmap::new(32, 32).unwrap();
        for (i, p) in b.data.chunks_exact_mut(4).enumerate() {
            let v = ((i % 32) * 8) as u8;
            p.copy_from_slice(&[v, 100, 255 - v, 255]);
        }
        b
    }

    #[test]
    fn goc_trong_suot_tam_dac() {
        let s = spec(64, 40);
        let bg = backdrop();
        let mut out = vec![0u8; 64 * 40 * 4];
        let place = Placement::scale_offset(0.0, 0.0, 0.5, 0.5);
        render(&s, Some((bg.view(), place)), &mut out, 64 * 4).unwrap();
        assert_eq!(out[3], 0, "góc trên trái nằm ngoài hình bo");
        let c = (20 * 64 + 32) * 4;
        assert_eq!(out[c + 3], 255, "giữa tấm kính phải đặc");
    }

    #[test]
    fn nhan_san_alpha_dung() {
        // Kênh màu không bao giờ vượt alpha — CoreGraphics vẽ sai nếu vượt
        let s = spec(48, 48);
        let bg = backdrop();
        let mut out = vec![0u8; 48 * 48 * 4];
        render(&s, Some((bg.view(), Placement::scale_offset(0.0, 0.0, 0.6, 0.6))), &mut out, 48 * 4).unwrap();
        for p in out.chunks_exact(4) {
            assert!(p[0] <= p[3] && p[1] <= p[3] && p[2] <= p[3], "{p:?}");
        }
        let mut out = vec![0u8; 48 * 48 * 4];
        render(&s, None, &mut out, 48 * 4).unwrap();
        for p in out.chunks_exact(4) {
            assert!(p[0] <= p[3] && p[1] <= p[3] && p[2] <= p[3], "{p:?}");
        }
    }

    #[test]
    fn vung_nho_ra_thieu_thi_bao_loi() {
        let s = spec(10, 10);
        let mut out = vec![0u8; 10 * 10 * 4 - 1];
        assert_eq!(render(&s, None, &mut out, 40), Err(Error::Buffer));
        let mut out = vec![0u8; 400];
        assert_eq!(render(&s, None, &mut out, 39), Err(Error::Buffer));
    }

    #[test]
    fn tham_so_ky_quac_khong_vo() {
        let bg = backdrop();
        for (w, h) in [(1u32, 1u32), (2, 300), (300, 2), (7, 7)] {
            let mut s = spec(w, h);
            s.radius = f32::NAN;
            s.bevel = 1e9;
            s.refraction = f32::INFINITY;
            s.light = (0.0, 0.0);
            s.tint = [f32::NAN, -5.0, 9999.0];
            let mut out = vec![0u8; (w * h * 4) as usize];
            let place = Placement { a: 100.0, b: -7.0, c: 3.0, d: -3.0, tx: -1000.0, ty: 5000.0 };
            render(&s, Some((bg.view(), place)), &mut out, w as usize * 4).unwrap();
            render(&s, None, &mut out, w as usize * 4).unwrap();
            assert!(render_shadow(&s, 1e9, f32::NAN, 2.0).is_some());
        }
        let bad = Placement::scale_offset(f32::NAN, 0.0, 1.0, 1.0);
        let mut out = vec![0u8; 64];
        assert_eq!(render(&spec(4, 4), Some((bg.view(), bad)), &mut out, 16), Err(Error::Backdrop));
    }

    #[test]
    fn nen_xoay_90_do() {
        // Nền: nửa trái đỏ, nửa phải lam. Kính xoay 90° (trục x của kính chạy dọc trục y của nền) → kính phải thấy
        // đỏ ở nửa TRÊN và lam ở nửa DƯỚI… tức màu đổi theo trục y của kính.
        let mut bg = Bitmap::new(40, 40).unwrap();
        for (i, p) in bg.data.chunks_exact_mut(4).enumerate() {
            let left = (i % 40) < 20;
            p.copy_from_slice(if left { &[0, 0, 255, 255] } else { &[255, 0, 0, 255] });
        }
        let mut s = spec(40, 40);
        s.tint_alpha = 0.0;
        s.rim = 0.0;
        s.sheen = 0.0;
        s.refraction = 0.0;
        // (px, py) của kính → (py, px) của nền
        let place = Placement { a: 0.0, b: 1.0, c: 1.0, d: 0.0, tx: 0.0, ty: 0.0 };
        let mut out = vec![0u8; 40 * 40 * 4];
        render(&s, Some((bg.view(), place)), &mut out, 160).unwrap();
        let top = (8 * 40 + 20) * 4;
        let bottom = (32 * 40 + 20) * 4;
        assert!(out[top + 2] > 200 && out[top] < 50, "trên phải đỏ: {:?}", &out[top..top + 4]);
        assert!(out[bottom] > 200 && out[bottom + 2] < 50, "dưới phải lam: {:?}", &out[bottom..bottom + 4]);
    }

    #[test]
    fn duong_so_nguyen_khop_duong_so_thuc() {
        // Cùng một tấm kính, dựng hai lần: (1) dải vát mỏng → phần giữa đi đường số nguyên; (2) dải vát phủ kín →
        // mọi điểm đi đường số thực. Tắt khúc xạ và viền sáng thì hai đường phải ra cùng màu (lệch ≤ 2 do làm tròn).
        let mut bg = Bitmap::new(64, 48).unwrap();
        for (i, p) in bg.data.chunks_exact_mut(4).enumerate() {
            p.copy_from_slice(&[(i * 7 % 256) as u8, (i * 13 % 256) as u8, (i * 3 % 256) as u8, 255]);
        }
        crate::blur::box_blur(&mut bg, 2, 2);
        let (w, h) = (200u32, 120u32);
        for place in [
            Placement::scale_offset(3.0, 2.0, 0.25, 0.25),
            // xoay 90°
            Placement { a: 0.0, b: 0.2, c: 0.2, d: 0.0, tx: 5.0, ty: 4.0 },
            // lấy mẫu tràn ra ngoài ảnh nền → đường có kẹp
            Placement::scale_offset(-20.0, -10.0, 0.6, 0.6),
        ] {
            let mut fast = spec(w, h);
            fast.refraction = 0.0;
            fast.rim = 0.0;
            fast.bevel = 2.0;
            let mut slow = fast;
            slow.bevel = 1e6;
            let mut a = vec![0u8; (w * h * 4) as usize];
            let mut b = vec![0u8; (w * h * 4) as usize];
            render(&fast, Some((bg.view(), place)), &mut a, w as usize * 4).unwrap();
            render(&slow, Some((bg.view(), place)), &mut b, w as usize * 4).unwrap();
            for y in 20..(h as usize - 20) {
                for x in 20..(w as usize - 20) {
                    let i = (y * w as usize + x) * 4;
                    for c in 0..4 {
                        let (va, vb) = (a[i + c] as i32, b[i + c] as i32);
                        assert!((va - vb).abs() <= 2, "({x},{y}) kênh {c}: {va} / {vb}");
                    }
                }
            }
        }
        // Kính giả cũng vậy
        let mut fast = spec(w, h);
        fast.rim = 0.0;
        fast.bevel = 2.0;
        let mut slow = fast;
        slow.bevel = 1e6;
        let mut a = vec![0u8; (w * h * 4) as usize];
        let mut b = vec![0u8; (w * h * 4) as usize];
        render(&fast, None, &mut a, w as usize * 4).unwrap();
        render(&slow, None, &mut b, w as usize * 4).unwrap();
        let i = (60 * w as usize + 100) * 4;
        for c in 0..4 {
            assert!((a[i + c] as i32 - b[i + c] as i32).abs() <= 1);
        }
    }

    #[test]
    fn bong_do_khoet_phan_duoi_kinh() {
        let s = spec(60, 40);
        let (b, m) = render_shadow(&s, 12.0, 4.0, 0.4).unwrap();
        assert_eq!((b.w, b.h), (60 + 2 * m, 40 + 2 * m));
        let center = ((m as usize + 20) * b.w as usize + m as usize + 30) * 4;
        assert_eq!(b.data[center + 3], 0, "dưới tấm kính không có bóng");
        let below = ((m as usize + 40 + 3) * b.w as usize + m as usize + 30) * 4;
        assert!(b.data[below + 3] > 20, "ngay dưới mép dưới phải có bóng");
    }
}

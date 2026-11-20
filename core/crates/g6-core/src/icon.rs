//! Hoàn thiện ảnh biểu tượng app: cắt theo hình bo góc liên tục và thêm viền sáng kiểu kính.
//!
//! Vỏ ObjC vẽ ảnh gốc của app (chưa cắt, chưa phủ lớp bóng của iOS 6) kín một vùng `w × h`, rồi gọi [`finish`] sửa tại chỗ.
//! Chỉ dải sát mép phải tính (số thực); phần giữa giữ nguyên điểm ảnh của app.

use crate::glass::{finite, normalize, smoothstep, Error};
use crate::shape::Shape;
use crate::MAX_SIDE;

/// Kiểu biểu tượng (như bốn kiểu của iPadOS 26). Ba kiểu sau đổi màu ảnh của app bằng thuật toán — không cần app cấp ảnh riêng.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum IconStyle {
    /// Giữ màu của app.
    Default,
    /// Dịu bớt chỗ sáng (nền trắng thành xám), giữ màu đậm — cho chế độ tối.
    Dark,
    /// Kính trong một màu: chỗ sáng của ảnh thành trắng đục, chỗ tối để hình nền lọt qua.
    Clear,
    /// Một màu nhuộm trên nền than: độ sáng của ảnh quyết định đậm nhạt.
    Tinted,
}

impl IconStyle {
    pub fn from_index(i: u32) -> IconStyle {
        match i {
            1 => IconStyle::Dark,
            2 => IconStyle::Clear,
            3 => IconStyle::Tinted,
            _ => IconStyle::Default,
        }
    }
}

/// Thông số một biểu tượng, đơn vị điểm ảnh.
#[derive(Clone, Copy, Debug)]
pub struct IconSpec {
    pub w: u32,
    pub h: u32,
    pub radius: f32,
    /// Số mũ góc bo (xem [`Shape`]).
    pub exponent: f32,
    /// Cường độ viền sáng 0–1.
    pub rim: f32,
    /// Bề dày viền sáng.
    pub rim_width: f32,
    /// Véc-tơ chỉ về phía nguồn sáng (y xuống dưới).
    pub light: (f32, f32),
    pub style: IconStyle,
    /// Màu nhuộm (R, G, B 0–255) cho [`IconStyle::Tinted`].
    pub tint: [f32; 3],
}

/// Đổi màu mọi điểm ảnh theo kiểu biểu tượng (trước khi cắt hình). Ảnh nhân sẵn alpha, thứ tự B, G, R, A.
fn restyle(spec: &IconSpec, pixels: &mut [u8], stride: usize) {
    if spec.style == IconStyle::Default {
        return;
    }
    let (w, h) = (spec.w as usize, spec.h as usize);
    // Nền than của kiểu nhuộm màu; màu nhuộm làm sáng thêm một chút để chỗ sáng nhất của ảnh nổi lên
    const BASE: [f32; 3] = [28.0, 28.0, 30.0];
    let tint = [
        (finite(spec.tint[0]).clamp(0.0, 255.0) * 0.8 + 51.0).min(255.0),
        (finite(spec.tint[1]).clamp(0.0, 255.0) * 0.8 + 51.0).min(255.0),
        (finite(spec.tint[2]).clamp(0.0, 255.0) * 0.8 + 51.0).min(255.0),
    ];
    for y in 0..h {
        let line = &mut pixels[y * stride..y * stride + w * 4];
        for px in line.chunks_exact_mut(4) {
            let a = px[3] as f32;
            if a <= 0.0 {
                continue;
            }
            // Bỏ nhân sẵn alpha → màu thật 0–1
            let (b, g, r) = (px[0] as f32 / a, px[1] as f32 / a, px[2] as f32 / a);
            let l = (0.2126 * r + 0.7152 * g + 0.0722 * b).clamp(0.0, 1.0);
            let (nr, ng, nb, na) = match spec.style {
                IconStyle::Dark => {
                    // Càng sáng càng bị dịu nhiều: trắng → xám ~52%, màu đậm gần như giữ nguyên
                    let k = 0.82 - 0.30 * l * l;
                    (r * k, g * k, b * k, a)
                }
                IconStyle::Clear => {
                    let t = smoothstep(l);
                    (1.0, 1.0, 1.0, a * (0.20 + 0.72 * t))
                }
                IconStyle::Tinted => {
                    let t = l.powf(0.85);
                    (
                        (BASE[0] + (tint[0] - BASE[0]) * t) / 255.0,
                        (BASE[1] + (tint[1] - BASE[1]) * t) / 255.0,
                        (BASE[2] + (tint[2] - BASE[2]) * t) / 255.0,
                        a,
                    )
                }
                IconStyle::Default => (r, g, b, a),
            };
            px[0] = (nb.clamp(0.0, 1.0) * na + 0.5) as u8;
            px[1] = (ng.clamp(0.0, 1.0) * na + 0.5) as u8;
            px[2] = (nr.clamp(0.0, 1.0) * na + 0.5) as u8;
            px[3] = (na + 0.5) as u8;
        }
    }
}

/// Cắt `pixels` (BGRA nhân sẵn alpha, bước hàng `stride`) theo hình của biểu tượng và thêm viền sáng. Sửa tại chỗ.
pub fn finish(spec: &IconSpec, pixels: &mut [u8], stride: usize) -> Result<(), Error> {
    let (w, h) = (spec.w as usize, spec.h as usize);
    if w == 0 || h == 0 || spec.w > MAX_SIDE || spec.h > MAX_SIDE {
        return Err(Error::Size);
    }
    let row = w * 4;
    if stride < row || pixels.len() < (h - 1) * stride + row {
        return Err(Error::Buffer);
    }
    restyle(spec, pixels, stride);
    let shape = Shape::new(spec.w as f32, spec.h as f32, finite(spec.radius), spec.exponent);
    let rim = finite(spec.rim).clamp(0.0, 1.0);
    let rim_w = finite(spec.rim_width).clamp(0.5, 16.0);
    let (lx, ly) = normalize(spec.light);
    let margin = rim_w + 1.5;
    let corner = margin.max(shape.r);
    let (wf, hf) = (spec.w as f32, spec.h as f32);

    for y in 0..h {
        let fy = y as f32 + 0.5;
        let line = &mut pixels[y * stride..y * stride + row];
        // Hàng sát mép trên / dưới: tính cả hàng; hàng trong vùng góc: tính hai đoạn rộng bằng góc; còn lại chỉ dải viền
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
        for x in (0..x_lo).chain(x_hi..w) {
            let o = x * 4;
            let hit = shape.eval(x as f32 + 0.5, fy);
            let cov = Shape::coverage(hit.d);
            if cov <= 0.0 {
                line[o..o + 4].copy_from_slice(&[0, 0, 0, 0]);
                continue;
            }
            let inside = (-hit.d).max(0.0);
            let edge = 1.0 - smoothstep(inside / rim_w);
            let mut light = 0.0;
            if edge > 0.0 && rim > 0.0 {
                let ndl = hit.nx * lx + hit.ny * ly;
                let main = ndl.max(0.0);
                let back = (-ndl).max(0.0);
                // Mép hướng về nguồn sáng sáng nhất; mép đối diện hắt sáng nhẹ; hai bên chỉ một nét mảnh
                light = (rim * edge * (0.16 + 0.84 * main * main.sqrt() + 0.40 * back * back * back)).min(1.0);
            }
            if light <= 0.0 && cov >= 1.0 {
                continue;
            }
            let a = line[o + 3] as f32;
            for c in 0..3 {
                let v = line[o + c] as f32;
                // Ảnh nhân sẵn alpha: trắng của điểm này là `a`, không phải 255
                line[o + c] = ((v + (a - v).max(0.0) * light) * cov + 0.5) as u8;
            }
            line[o + 3] = (a * cov + 0.5) as u8;
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn spec(w: u32, h: u32) -> IconSpec {
        IconSpec {
            w,
            h,
            radius: w.min(h) as f32 * 0.5,
            exponent: 5.0,
            rim: 0.5,
            rim_width: 1.2,
            light: (-0.42, -0.91),
            style: IconStyle::Default,
            tint: [10.0, 132.0, 255.0],
        }
    }

    fn solid(w: usize, h: usize, px: [u8; 4]) -> Vec<u8> {
        px.iter().copied().cycle().take(w * h * 4).collect()
    }

    #[test]
    fn cat_goc_giu_giua() {
        let (w, h) = (72usize, 72usize);
        let mut img = solid(w, h, [40, 90, 200, 255]);
        finish(&spec(72, 72), &mut img, w * 4).unwrap();
        let at = |x: usize, y: usize| -> [u8; 4] { img[(y * w + x) * 4..(y * w + x) * 4 + 4].try_into().unwrap() };
        assert_eq!(at(0, 0), [0, 0, 0, 0], "góc khung phải trong suốt");
        assert_eq!(at(71, 71), [0, 0, 0, 0]);
        assert_eq!(at(36, 36), [40, 90, 200, 255], "giữa biểu tượng giữ nguyên");
        assert_eq!(at(36, 20), [40, 90, 200, 255]);
        // Giữa cạnh trên: phủ kín và sáng hơn nhờ viền
        let top = at(36, 0);
        assert_eq!(top[3], 255);
        assert!(top[0] > 40 && top[1] > 90, "{top:?}");
        // Cạnh trên (hướng về nguồn sáng) sáng hơn cạnh dưới
        assert!(top[0] > at(36, 71)[0]);
        // Nhân sẵn alpha: không kênh màu nào vượt alpha
        for p in img.chunks_exact(4) {
            assert!(p[0] <= p[3] && p[1] <= p[3] && p[2] <= p[3], "{p:?}");
        }
    }

    #[test]
    fn hinh_doi_xung() {
        let (w, h) = (60usize, 60usize);
        let mut img = solid(w, h, [255, 255, 255, 255]);
        let mut s = spec(60, 60);
        s.rim = 0.0;
        finish(&s, &mut img, w * 4).unwrap();
        for y in 0..h {
            for x in 0..w {
                let a = img[(y * w + x) * 4 + 3];
                let b = img[(y * w + (w - 1 - x)) * 4 + 3];
                let c = img[((h - 1 - y) * w + x) * 4 + 3];
                assert_eq!((a, a), (b, c), "({x}, {y})");
            }
        }
    }

    #[test]
    fn anh_nguon_trong_suot_van_trong_suot() {
        let (w, h) = (40usize, 40usize);
        let mut img = solid(w, h, [0, 0, 0, 0]);
        finish(&spec(40, 40), &mut img, w * 4).unwrap();
        assert!(img.iter().all(|&b| b == 0));
    }

    #[test]
    fn ba_kieu_doi_mau() {
        let (w, h) = (40usize, 40usize);
        let at = |img: &[u8], x: usize, y: usize| -> [u8; 4] { img[(y * w + x) * 4..(y * w + x) * 4 + 4].try_into().unwrap() };
        let run = |style: IconStyle, px: [u8; 4]| -> [u8; 4] {
            let mut img = solid(w, h, px);
            let mut s = spec(40, 40);
            s.style = style;
            s.rim = 0.0;
            finish(&s, &mut img, w * 4).unwrap();
            at(&img, 20, 20)
        };
        let white = [255, 255, 255, 255];
        let navy = [120, 30, 20, 255]; // B, G, R
        // Tối: trắng dịu hẳn, màu đậm gần như giữ
        let d = run(IconStyle::Dark, white);
        assert!(d[0] < 150 && d[0] > 110 && d[3] == 255, "{d:?}");
        let dn = run(IconStyle::Dark, navy);
        assert!(dn[0] >= 90, "{dn:?}");
        // Trong: ra trắng nhân sẵn alpha, chỗ sáng đục hơn chỗ tối, không điểm nào đặc hẳn
        let c = run(IconStyle::Clear, white);
        let cn = run(IconStyle::Clear, navy);
        assert!(c[3] > cn[3] && c[3] < 255 && c[0] == c[3] && cn[0] == cn[3], "{c:?} {cn:?}");
        // Nhuộm màu (xanh dương): chỗ sáng ra màu nhuộm (kênh B lớn nhất), chỗ tối về nền than; vẫn đặc
        let t = run(IconStyle::Tinted, white);
        assert!(t[0] > t[1] && t[1] > t[2] && t[3] == 255, "{t:?}");
        let tn = run(IconStyle::Tinted, [0, 0, 0, 255]);
        assert!(tn[0] < 40 && tn[2] < 40, "{tn:?}");
        // Mặc định: không đổi
        assert_eq!(run(IconStyle::Default, navy), navy);
        // Điểm trong suốt vẫn trong suốt ở mọi kiểu
        for style in [IconStyle::Dark, IconStyle::Clear, IconStyle::Tinted] {
            assert_eq!(run(style, [0, 0, 0, 0]), [0, 0, 0, 0]);
        }
        assert_eq!(IconStyle::from_index(9), IconStyle::Default);
    }

    #[test]
    fn tham_so_hong_tra_loi() {
        let mut img = vec![0u8; 16];
        assert_eq!(finish(&spec(0, 2), &mut img, 8), Err(Error::Size));
        assert_eq!(finish(&spec(2, 2), &mut img, 7), Err(Error::Buffer));
        assert_eq!(finish(&spec(4, 4), &mut img, 16), Err(Error::Buffer));
        let mut bad = spec(2, 2);
        bad.radius = f32::NAN;
        bad.rim_width = f32::INFINITY;
        bad.light = (f32::NAN, 0.0);
        assert_eq!(finish(&bad, &mut img, 8), Ok(()));
        // Bước hàng lớn hơn bề rộng: không đụng byte đệm
        let mut padded = vec![7u8; 3 * 20];
        finish(&spec(4, 3), &mut padded, 20).unwrap();
        assert!(padded[16..20].iter().all(|&b| b == 7));
    }
}

//! Làm mờ: box blur tách hai chiều, lặp 3 lượt ≈ Gauss. Tốn O(số điểm ảnh) bất kể bán kính (cửa sổ trượt).
//! Ảnh vào đã thu nhỏ 1/4 – 1/8 nên trên A5 chỉ vài mili giây.

use crate::bitmap::Bitmap;

/// Làm mờ tại chỗ. `radius` tính theo điểm ảnh của `bmp`; mép ảnh lặp lại điểm ngoài cùng.
pub fn box_blur(bmp: &mut Bitmap, radius: u32, passes: u32) {
    let (w, h) = (bmp.w as usize, bmp.h as usize);
    if radius == 0 || passes == 0 || w == 0 || h == 0 || bmp.data.len() < w * h * 4 {
        return;
    }
    // Bán kính lớn hơn ảnh không cho gì thêm, chỉ tốn vòng lặp
    let r = (radius as usize).min(w.max(h));
    let mut tmp = vec![0u8; bmp.data.len()];
    for _ in 0..passes.min(8) {
        blur_lines(&bmp.data, &mut tmp, w, h, r, 4, w * 4);
        blur_lines(&tmp, &mut bmp.data, h, w, r, w * 4, 4);
    }
}

/// Một lượt mờ theo một chiều. `len` = số điểm trên một dòng, `lines` = số dòng;
/// `step` = khoảng cách byte giữa hai điểm liền nhau trên dòng, `line_step` = giữa hai dòng.
fn blur_lines(src: &[u8], dst: &mut [u8], len: usize, lines: usize, r: usize, step: usize, line_step: usize) {
    // Chia bằng nhân nghịch đảo 8.24 — Cortex-A8 / A9 không có lệnh chia nguyên; nhân 32×32→64 là một lệnh (umull)
    let inv = recip(r);
    let last = len - 1;
    for line in 0..lines {
        let base = line * line_step;
        let mut acc = [0u32; 4];
        // Cửa sổ ban đầu quanh điểm 0: r điểm «bên trái» là điểm 0 lặp lại
        for k in 0..=2 * r {
            let idx = k.saturating_sub(r).min(last);
            let i = base + idx * step;
            for c in 0..4 {
                acc[c] += src[i + c] as u32;
            }
        }
        for x in 0..len {
            let o = base + x * step;
            for c in 0..4 {
                dst[o + c] = div(acc[c], inv);
            }
            let add = (x + r + 1).min(last);
            let sub = x.saturating_sub(r);
            let (ia, is) = (base + add * step, base + sub * step);
            for c in 0..4 {
                acc[c] = acc[c] + src[ia + c] as u32 - src[is + c] as u32;
            }
        }
    }
}

/// Nghịch đảo của bề rộng cửa sổ `2r + 1`, dấu phẩy tĩnh 8.24.
#[inline]
fn recip(r: usize) -> u64 {
    (1u64 << 24) / (2 * r as u64 + 1)
}

/// `acc / (2r + 1)` làm tròn, kẹp về 0–255.
#[inline]
fn div(acc: u32, inv: u64) -> u8 {
    ((acc as u64 * inv + (1 << 23)) >> 24).min(255) as u8
}

/// Làm mờ một kênh (dùng cho bóng đổ).
pub fn box_blur_gray(data: &mut [u8], w: usize, h: usize, radius: u32, passes: u32) {
    if radius == 0 || passes == 0 || w == 0 || h == 0 || data.len() < w * h {
        return;
    }
    let r = (radius as usize).min(w.max(h));
    let mut tmp = vec![0u8; data.len()];
    for _ in 0..passes.min(8) {
        gray_lines(data, &mut tmp, w, h, r, 1, w);
        gray_lines(&tmp, data, h, w, r, w, 1);
    }
}

fn gray_lines(src: &[u8], dst: &mut [u8], len: usize, lines: usize, r: usize, step: usize, line_step: usize) {
    let inv = recip(r);
    let last = len - 1;
    for line in 0..lines {
        let base = line * line_step;
        let mut acc = 0u32;
        for k in 0..=2 * r {
            acc += src[base + k.saturating_sub(r).min(last) * step] as u32;
        }
        for x in 0..len {
            dst[base + x * step] = div(acc, inv);
            let add = (x + r + 1).min(last);
            let sub = x.saturating_sub(r);
            acc = acc + src[base + add * step] as u32 - src[base + sub * step] as u32;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn anh_mot_mau_giu_nguyen() {
        let mut b = Bitmap::new(17, 9).unwrap();
        for p in b.data.chunks_exact_mut(4) {
            p.copy_from_slice(&[40, 80, 120, 255]);
        }
        box_blur(&mut b, 5, 3);
        for p in b.data.chunks_exact(4) {
            // Nghịch đảo dấu phẩy tĩnh làm lệch tối đa 1 đơn vị
            assert!((p[0] as i32 - 40).abs() <= 1 && (p[1] as i32 - 80).abs() <= 1 && (p[2] as i32 - 120).abs() <= 1);
        }
    }

    #[test]
    fn diem_sang_bi_trai_ra() {
        let mut b = Bitmap::new(21, 21).unwrap();
        let c = (10 * 21 + 10) * 4;
        b.data[c..c + 4].copy_from_slice(&[255, 255, 255, 255]);
        box_blur(&mut b, 3, 3);
        assert!(b.data[c] < 60, "tâm phải tối đi nhiều, còn {}", b.data[c]);
        let near = (10 * 21 + 13) * 4;
        assert!(b.data[near] > 0, "điểm cách 3 phải nhận được sáng");
    }

    #[test]
    fn ban_kinh_lon_hon_anh_khong_vo() {
        let mut b = Bitmap::new(3, 2).unwrap();
        box_blur(&mut b, 1000, 3);
        let mut b = Bitmap::new(1, 1).unwrap();
        box_blur(&mut b, 4, 3);
        let mut g = vec![255u8; 6];
        box_blur_gray(&mut g, 3, 2, 50, 3);
    }
}

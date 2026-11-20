//! Ảnh BGRA 8 bit, alpha nhân sẵn — đúng thứ tự byte CoreGraphics dùng trên iOS
//! (`kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little`), nên giao thẳng cho CALayer không phải đổi.

use crate::MAX_SIDE;

#[derive(Clone, Debug, PartialEq)]
pub struct Bitmap {
    pub w: u32,
    pub h: u32,
    /// `w * h * 4` byte, hàng nối hàng (không đệm cuối hàng).
    pub data: Vec<u8>,
}

/// Ảnh chỉ đọc do bên ngoài giữ (vỏ ObjC đưa sang), có thể đệm cuối hàng (`stride` ≥ `w * 4`).
#[derive(Clone, Copy)]
pub struct View<'a> {
    pub w: u32,
    pub h: u32,
    pub stride: usize,
    pub data: &'a [u8],
}

impl Bitmap {
    /// Ảnh trong suốt. `None` nếu kích thước bằng 0 hoặc quá [`MAX_SIDE`].
    pub fn new(w: u32, h: u32) -> Option<Bitmap> {
        if w == 0 || h == 0 || w > MAX_SIDE || h > MAX_SIDE {
            return None;
        }
        Some(Bitmap { w, h, data: vec![0u8; w as usize * h as usize * 4] })
    }

    pub fn view(&self) -> View<'_> {
        View { w: self.w, h: self.h, stride: self.w as usize * 4, data: &self.data }
    }

    /// Chép từ ảnh có đệm cuối hàng.
    pub fn from_view(v: View<'_>) -> Option<Bitmap> {
        let mut b = Bitmap::new(v.w, v.h)?;
        if !v.is_valid() {
            return None;
        }
        let row = v.w as usize * 4;
        for y in 0..v.h as usize {
            let s = y * v.stride;
            b.data[y * row..(y + 1) * row].copy_from_slice(&v.data[s..s + row]);
        }
        Some(b)
    }
}

impl<'a> View<'a> {
    /// Vùng nhớ đủ dài cho kích thước đã khai — kiểm một lần ở cửa vào, sau đó các vòng lặp không phải kiểm lại.
    pub fn is_valid(&self) -> bool {
        if self.w == 0 || self.h == 0 || self.w > MAX_SIDE || self.h > MAX_SIDE {
            return false;
        }
        let row = self.w as usize * 4;
        if self.stride < row {
            return false;
        }
        let need = (self.h as usize - 1) * self.stride + row;
        self.data.len() >= need
    }

    /// Một điểm ảnh, toạ độ kẹp vào trong ảnh.
    #[inline]
    pub fn px(&self, x: i32, y: i32) -> [u8; 4] {
        let x = x.clamp(0, self.w as i32 - 1) as usize;
        let y = y.clamp(0, self.h as i32 - 1) as usize;
        let i = y * self.stride + x * 4;
        match self.data.get(i..i + 4) {
            Some(p) => [p[0], p[1], p[2], p[3]],
            None => [0, 0, 0, 0],
        }
    }

    /// Lấy mẫu song tuyến tại toạ độ thực (tâm điểm ảnh ở +0.5). Trả B, G, R, A dạng số thực 0–255.
    #[inline]
    pub fn sample(&self, x: f32, y: f32) -> [f32; 4] {
        let fx = x - 0.5;
        let fy = y - 0.5;
        let x0 = fx.floor();
        let y0 = fy.floor();
        let tx = fx - x0;
        let ty = fy - y0;
        let (x0, y0) = (x0 as i32, y0 as i32);
        let a = self.px(x0, y0);
        let b = self.px(x0 + 1, y0);
        let c = self.px(x0, y0 + 1);
        let d = self.px(x0 + 1, y0 + 1);
        let mut out = [0f32; 4];
        for i in 0..4 {
            let top = a[i] as f32 + (b[i] as f32 - a[i] as f32) * tx;
            let bot = c[i] as f32 + (d[i] as f32 - c[i] as f32) * tx;
            out[i] = top + (bot - top) * ty;
        }
        out
    }
}

/// Thu nhỏ theo hệ số nguyên bằng trung bình khối. Phần lẻ ở mép phải / dưới gộp vào khối cuối.
pub fn downscale(src: View<'_>, factor: u32) -> Option<Bitmap> {
    if !src.is_valid() || factor == 0 {
        return None;
    }
    let f = factor as usize;
    let ow = (src.w as usize / f).max(1);
    let oh = (src.h as usize / f).max(1);
    let mut out = Bitmap::new(ow as u32, oh as u32)?;
    let (sw, sh) = (src.w as usize, src.h as usize);
    for oy in 0..oh {
        let y0 = oy * f;
        let y1 = if oy == oh - 1 { sh } else { (y0 + f).min(sh) };
        for ox in 0..ow {
            let x0 = ox * f;
            let x1 = if ox == ow - 1 { sw } else { (x0 + f).min(sw) };
            let mut acc = [0u32; 4];
            for y in y0..y1 {
                let row = y * src.stride;
                for x in x0..x1 {
                    let i = row + x * 4;
                    acc[0] += src.data[i] as u32;
                    acc[1] += src.data[i + 1] as u32;
                    acc[2] += src.data[i + 2] as u32;
                    acc[3] += src.data[i + 3] as u32;
                }
            }
            let n = ((y1 - y0) * (x1 - x0)).max(1) as u32;
            let o = (oy * ow + ox) * 4;
            out.data[o] = ((acc[0] + n / 2) / n) as u8;
            out.data[o + 1] = ((acc[1] + n / 2) / n) as u8;
            out.data[o + 2] = ((acc[2] + n / 2) / n) as u8;
            out.data[o + 3] = ((acc[3] + n / 2) / n) as u8;
        }
    }
    Some(out)
}

/// Tăng / giảm bão hoà quanh độ sáng (hệ số Rec. 601). `amount` = 1 giữ nguyên.
pub fn saturate(bmp: &mut Bitmap, amount: f32) {
    if (amount - 1.0).abs() < 0.001 {
        return;
    }
    for p in bmp.data.chunks_exact_mut(4) {
        let (b, g, r) = (p[0] as f32, p[1] as f32, p[2] as f32);
        let l = 0.114 * b + 0.587 * g + 0.299 * r;
        // Kẹp theo alpha: ảnh nhân sẵn alpha thì kênh màu không được vượt alpha
        let max = p[3] as f32;
        p[0] = (l + (b - l) * amount).clamp(0.0, max) as u8;
        p[1] = (l + (g - l) * amount).clamp(0.0, max) as u8;
        p[2] = (l + (r - l) * amount).clamp(0.0, max) as u8;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn kich_thuoc_vo_ly_bi_tu_choi() {
        assert!(Bitmap::new(0, 10).is_none());
        assert!(Bitmap::new(10, MAX_SIDE + 1).is_none());
        assert!(Bitmap::new(1, 1).is_some());
    }

    #[test]
    fn view_thieu_du_lieu_khong_hop_le() {
        let d = vec![0u8; 15];
        assert!(!View { w: 2, h: 2, stride: 8, data: &d }.is_valid());
        let d = vec![0u8; 16];
        assert!(View { w: 2, h: 2, stride: 8, data: &d }.is_valid());
        assert!(!View { w: 2, h: 2, stride: 4, data: &d }.is_valid());
    }

    #[test]
    fn thu_nho_lay_trung_binh() {
        let mut b = Bitmap::new(4, 2).unwrap();
        for (i, p) in b.data.chunks_exact_mut(4).enumerate() {
            let v = if i % 2 == 0 { 100 } else { 200 };
            p.copy_from_slice(&[v, v, v, 255]);
        }
        let s = downscale(b.view(), 2).unwrap();
        assert_eq!((s.w, s.h), (2, 1));
        assert_eq!(&s.data[0..4], &[150, 150, 150, 255]);
    }

    #[test]
    fn thu_nho_he_so_lon_hon_anh() {
        let b = Bitmap::new(3, 3).unwrap();
        let s = downscale(b.view(), 8).unwrap();
        assert_eq!((s.w, s.h), (1, 1));
    }

    #[test]
    fn lay_mau_ngoai_bien_khong_vo() {
        let mut b = Bitmap::new(2, 2).unwrap();
        b.data.copy_from_slice(&[10, 10, 10, 255, 20, 20, 20, 255, 30, 30, 30, 255, 40, 40, 40, 255]);
        let v = b.view();
        assert_eq!(v.sample(-100.0, -100.0)[0], 10.0);
        assert_eq!(v.sample(100.0, 100.0)[0], 40.0);
        assert!((v.sample(1.0, 1.0)[0] - 25.0).abs() < 0.01);
    }
}

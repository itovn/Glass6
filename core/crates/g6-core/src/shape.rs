//! Hình của tấm kính: chữ nhật bo góc, góc bo kiểu siêu elip («bo góc liên tục» của iOS 7 trở đi) hoặc tròn thường.
//! Cho khoảng cách có dấu tới mép (âm = bên trong) và pháp tuyến hướng ra ngoài — dùng để khử răng cưa, vẽ viền sáng và
//! tính khúc xạ viền.

#[derive(Clone, Copy, Debug)]
pub struct Shape {
    /// Nửa bề rộng, nửa bề cao (điểm ảnh).
    pub hw: f32,
    pub hh: f32,
    /// Bán kính góc, đã kẹp ≤ nửa cạnh ngắn.
    pub r: f32,
    /// Số mũ của góc: 2 = cung tròn; lớn hơn thì góc đầy hơn, chuyển tiếp vào cạnh thẳng mượt hơn.
    pub n: f32,
}

#[derive(Clone, Copy, Debug)]
pub struct Hit {
    /// Khoảng cách tới mép, âm ở bên trong.
    pub d: f32,
    /// Pháp tuyến đơn vị hướng ra ngoài.
    pub nx: f32,
    pub ny: f32,
}

impl Shape {
    pub fn new(w: f32, h: f32, radius: f32, exponent: f32) -> Shape {
        let hw = (w * 0.5).max(0.5);
        let hh = (h * 0.5).max(0.5);
        let r = if radius.is_finite() { radius.clamp(0.0, hw.min(hh)) } else { 0.0 };
        let n = if exponent.is_finite() { exponent.clamp(2.0, 8.0) } else { 2.0 };
        Shape { hw, hh, r, n }
    }

    /// Điểm chắc chắn nằm sâu bên trong hơn `margin` (không cần tính mép) — đường tắt cho phần lớn điểm ảnh.
    #[inline]
    pub fn deep_inside(&self, x: f32, y: f32, margin: f32) -> bool {
        let ax = (x - self.hw).abs();
        let ay = (y - self.hh).abs();
        let m = margin.max(self.r);
        ax < self.hw - m && ay < self.hh - m
    }

    /// Khoảng cách và pháp tuyến tại `(x, y)`, gốc toạ độ ở góc trên trái của khung.
    #[inline]
    pub fn eval(&self, x: f32, y: f32) -> Hit {
        let px = x - self.hw;
        let py = y - self.hh;
        let sx = if px < 0.0 { -1.0 } else { 1.0 };
        let sy = if py < 0.0 { -1.0 } else { 1.0 };
        let qx = px.abs() - (self.hw - self.r);
        let qy = py.abs() - (self.hh - self.r);
        if qx > 0.0 && qy > 0.0 && self.r > 0.0 {
            // Vùng góc
            if self.n <= 2.001 {
                let len = (qx * qx + qy * qy).sqrt().max(1e-6);
                return Hit { d: len - self.r, nx: sx * qx / len, ny: sy * qy / len };
            }
            // Chuẩn bậc n: f = (qx^n + qy^n)^(1/n); mép là f = r. Chia cho độ dài gradient để ra khoảng cách xấp xỉ
            // theo điểm ảnh (cần cho viền khử răng cưa đều bề dày).
            let f = (qx.powf(self.n) + qy.powf(self.n)).powf(1.0 / self.n).max(1e-6);
            let gx = (qx / f).powf(self.n - 1.0);
            let gy = (qy / f).powf(self.n - 1.0);
            let g = (gx * gx + gy * gy).sqrt().max(1e-6);
            return Hit { d: (f - self.r) / g, nx: sx * gx / g, ny: sy * gy / g };
        }
        // Cạnh thẳng: mép gần nhất
        if qx > qy {
            Hit { d: qx - self.r, nx: sx, ny: 0.0 }
        } else {
            Hit { d: qy - self.r, nx: 0.0, ny: sy }
        }
    }

    /// Độ phủ của một điểm ảnh (0–1) theo khoảng cách tới mép.
    #[inline]
    pub fn coverage(d: f32) -> f32 {
        (0.5 - d).clamp(0.0, 1.0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tam_o_trong_goc_o_ngoai() {
        let s = Shape::new(100.0, 60.0, 20.0, 2.0);
        assert!(s.eval(50.0, 30.0).d < -25.0);
        assert!(s.eval(0.5, 0.5).d > 0.0, "góc khung phải nằm ngoài hình bo");
        assert!(s.eval(50.0, 0.0).d.abs() < 0.01, "giữa cạnh trên nằm đúng mép");
    }

    #[test]
    fn phap_tuyen_huong_ra_ngoai() {
        let s = Shape::new(100.0, 60.0, 20.0, 2.0);
        let top = s.eval(50.0, 1.0);
        assert_eq!((top.nx, top.ny), (0.0, -1.0));
        let right = s.eval(99.0, 30.0);
        assert_eq!((right.nx, right.ny), (1.0, 0.0));
        let corner = s.eval(4.0, 4.0);
        assert!(corner.nx < 0.0 && corner.ny < 0.0);
    }

    #[test]
    fn sieu_elip_day_hon_cung_tron() {
        // Cùng bán kính, điểm trên đường chéo góc: siêu elip phủ ra xa hơn cung tròn
        let round = Shape::new(100.0, 100.0, 30.0, 2.0);
        let squircle = Shape::new(100.0, 100.0, 30.0, 4.0);
        let (x, y) = (7.0, 7.0);
        assert!(squircle.eval(x, y).d < round.eval(x, y).d);
    }

    #[test]
    fn tham_so_hong_khong_vo() {
        let s = Shape::new(0.0, 0.0, f32::NAN, f32::INFINITY);
        let h = s.eval(0.0, 0.0);
        assert!(h.d.is_finite() && h.nx.is_finite() && h.ny.is_finite());
        let s = Shape::new(10.0, 4.0, 1000.0, 5.0);
        assert!(s.r <= 2.0);
        for y in 0..4 {
            for x in 0..10 {
                let h = s.eval(x as f32 + 0.5, y as f32 + 0.5);
                assert!(h.d.is_finite() && h.nx.is_finite() && h.ny.is_finite());
            }
        }
    }
}

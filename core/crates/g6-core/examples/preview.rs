//! Xuất ảnh mẫu các tấm kính trên một hình nền, để xem trên PC trước khi đưa lên máy:
//!   cargo run -p g6-core --example preview -- <thư mục ra> [hình nền .png | .cpbitmap]
//! Không có hình nền thì dùng nền dải màu tự vẽ. Mỗi chế độ (sáng / tối) ra một tệp `preview-<chế độ>.png`.

use std::fs::File;
use std::io::BufWriter;
use std::path::{Path, PathBuf};

use g6_core::api;
use g6_core::bitmap::{Bitmap, View};
use g6_core::config::Config;
use g6_core::glass::Placement;
use g6_core::theme::Surface;

fn main() {
    let mut args = std::env::args().skip(1);
    let out_dir = PathBuf::from(args.next().unwrap_or_else(|| ".".into()));
    let wallpaper = match args.next() {
        Some(p) => load(Path::new(&p)).unwrap_or_else(|| {
            eprintln!("không đọc được {p}, dùng nền tự vẽ");
            synthetic(1024, 768)
        }),
        None => synthetic(1024, 768),
    };
    // Màn iPad nằm ngang: cắt giữa hình nền về 1024×768
    let screen = crop_center(&wallpaper, 1024, 768);
    std::fs::create_dir_all(&out_dir).expect("tạo thư mục ra");
    // Biểu tượng mục «Glass 6» trong Cài đặt (29 pt): chép vào layout/Library/PreferenceLoader/Preferences/
    save(&out_dir.join("Glass6.png"), &settings_icon(29, 1.0));
    save(&out_dir.join("Glass6@2x.png"), &settings_icon(58, 2.0));
    // Cùng hình đó ở cỡ lớn: biểu tượng của trang giới thiệu và của nguồn Cydia
    for size in [60u32, 120, 512] {
        save(&out_dir.join(format!("icon-{size}.png")), &settings_icon(size, size as f32 / 29.0));
    }

    for dark in [false, true] {
        api::set_config(Config::default());
        let t0 = std::time::Instant::now();
        let small = api::prepare_backdrop(screen.view(), 1.0, false).expect("nền");
        let t_backdrop = t0.elapsed();
        let mut frame = screen.clone();
        let factor = screen.w as f32 / small.w as f32;

        // (bề mặt, x, y, rộng, cao) — toạ độ màn hình
        let panels: [(Surface, i32, i32, u32, u32); 7] = [
            (Surface::Dock, 162, 652, 700, 100),
            (Surface::Panel, 660, 40, 320, 150),
            (Surface::Panel, 660, 204, 152, 152),
            (Surface::Panel, 828, 204, 152, 152),
            (Surface::Banner, 40, 40, 420, 72),
            (Surface::Capsule, 40, 140, 240, 52),
            (Surface::Capsule, 40, 216, 52, 52),
        ];
        let t1 = std::time::Instant::now();
        for (surface, x, y, w, h) in panels {
            if let Some((shadow, m)) = api::render_surface_shadow(surface, w, h, 1.0, dark) {
                blit(&mut frame, &shadow.data, shadow.w, shadow.h, x - m as i32, y - m as i32);
            }
            let mut tile = vec![0u8; (w * h * 4) as usize];
            let place = Placement::scale_offset(x as f32 / factor, y as f32 / factor, 1.0 / factor, 1.0 / factor);
            api::render_surface(surface, w, h, 1.0, dark, Some((small.view(), place)), &mut tile, w as usize * 4)
                .expect("dựng kính");
            blit(&mut frame, &tile, w, h, x, y);
        }
        // Kính giả (không có nền) — thanh trong app
        let (w, h) = (420u32, 44u32);
        let mut tile = vec![0u8; (w * h * 4) as usize];
        api::render_surface(Surface::Capsule, w, h, 1.0, dark, None, &mut tile, w as usize * 4).expect("kính giả");
        blit(&mut frame, &tile, w, h, 40, 300);
        let t_panels = t1.elapsed();

        let name = if dark { "preview-toi.png" } else { "preview-sang.png" };
        save(&out_dir.join(name), &frame);
        println!("{name}: nền {t_backdrop:?}, 8 tấm kính + bóng {t_panels:?}");
    }
}

/// Biểu tượng của Glass 6: ô kính bo góc liên tục trên dải màu lam → tím, có một viên kính nhỏ nổi ở giữa.
fn settings_icon(size: u32, scale: f32) -> Bitmap {
    let mut bg = Bitmap::new(size, size).unwrap();
    for y in 0..size {
        for x in 0..size {
            let t = (x as f32 + y as f32 * 1.4) / (size as f32 * 2.4);
            let (r, g, b) = (30.0 + 150.0 * t, 190.0 - 110.0 * t, 255.0 - 25.0 * t);
            let o = ((y * size + x) * 4) as usize;
            bg.data[o..o + 4].copy_from_slice(&[b as u8, g as u8, r as u8, 255]);
        }
    }
    let cfg = Config::default();
    let mut spec = g6_core::theme::glass_spec(Surface::Icon, size, size, scale, false, &cfg);
    spec.tint_alpha = 0.04;
    spec.rim = 0.9;
    let mut out = Bitmap::new(size, size).unwrap();
    let id = Placement::scale_offset(0.0, 0.0, 1.0, 1.0);
    g6_core::glass::render(&spec, Some((bg.view(), id)), &mut out.data, size as usize * 4).expect("biểu tượng");
    // Viên kính nhỏ ở giữa
    let (pw, ph) = ((size as f32 * 0.62) as u32, (size as f32 * 0.34) as u32);
    let mut pill = g6_core::theme::glass_spec(Surface::Capsule, pw, ph, scale, false, &cfg);
    pill.tint_alpha = 0.30;
    pill.bevel = 3.0 * scale;
    pill.refraction = 0.0;
    let mut tile = vec![0u8; (pw * ph * 4) as usize];
    let (px, py) = ((size - pw) / 2, (size - ph) / 2);
    let place = Placement::scale_offset(px as f32, py as f32, 1.0, 1.0);
    g6_core::glass::render(&pill, Some((bg.view(), place)), &mut tile, pw as usize * 4).expect("viên kính");
    blit(&mut out, &tile, pw, ph, px as i32, py as i32);
    out
}

/// Dán ảnh nhân sẵn alpha lên khung (phép «over»).
fn blit(dst: &mut Bitmap, src: &[u8], w: u32, h: u32, x0: i32, y0: i32) {
    for y in 0..h as i32 {
        let dy = y + y0;
        if dy < 0 || dy >= dst.h as i32 {
            continue;
        }
        for x in 0..w as i32 {
            let dx = x + x0;
            if dx < 0 || dx >= dst.w as i32 {
                continue;
            }
            let s = (y as usize * w as usize + x as usize) * 4;
            let d = (dy as usize * dst.w as usize + dx as usize) * 4;
            let inv = 255 - src[s + 3] as u32;
            for c in 0..4 {
                let v = src[s + c] as u32 + (dst.data[d + c] as u32 * inv + 127) / 255;
                dst.data[d + c] = v.min(255) as u8;
            }
        }
    }
}

fn crop_center(src: &Bitmap, w: u32, h: u32) -> Bitmap {
    let mut out = Bitmap::new(w, h).unwrap();
    let ox = (src.w as i32 - w as i32) / 2;
    let oy = (src.h as i32 - h as i32) / 2;
    let v = src.view();
    for y in 0..h {
        for x in 0..w {
            let p = v.px(x as i32 + ox, y as i32 + oy);
            let o = ((y * w + x) * 4) as usize;
            out.data[o..o + 4].copy_from_slice(&p);
        }
    }
    out
}

/// Nền tự vẽ: dải màu chéo + vài đốm sáng + sọc mảnh (để thấy rõ độ mờ và khúc xạ viền).
fn synthetic(w: u32, h: u32) -> Bitmap {
    let mut b = Bitmap::new(w, h).unwrap();
    for y in 0..h {
        for x in 0..w {
            let (fx, fy) = (x as f32 / w as f32, y as f32 / h as f32);
            let mut r = 40.0 + 180.0 * fx;
            let mut g = 60.0 + 90.0 * (1.0 - fy);
            let mut bl = 150.0 + 100.0 * fy;
            for (cx, cy, rad, col) in
                [(0.25, 0.3, 0.18, [255.0, 190.0, 60.0]), (0.7, 0.75, 0.22, [255.0, 70.0, 130.0]), (0.8, 0.2, 0.12, [80.0, 255.0, 200.0])]
            {
                let d = (((fx - cx) * (w as f32 / h as f32)).powi(2) + (fy - cy).powi(2)).sqrt();
                let k = (1.0 - d / rad).clamp(0.0, 1.0);
                r += (col[0] - r) * k;
                g += (col[1] - g) * k;
                bl += (col[2] - bl) * k;
            }
            if (x / 6) % 8 == 0 {
                r *= 0.6;
                g *= 0.6;
                bl *= 0.6;
            }
            let o = ((y * w + x) * 4) as usize;
            b.data[o..o + 4].copy_from_slice(&[bl as u8, g as u8, r as u8, 255]);
        }
    }
    b
}

fn load(path: &Path) -> Option<Bitmap> {
    let bytes = std::fs::read(path).ok()?;
    if path.extension().and_then(|e| e.to_str()) == Some("cpbitmap") {
        return load_cpbitmap(&bytes);
    }
    let dec = png::Decoder::new(std::io::Cursor::new(bytes));
    let mut reader = dec.read_info().ok()?;
    let mut buf = vec![0u8; reader.output_buffer_size()];
    let info = reader.next_frame(&mut buf).ok()?;
    let ch = match info.color_type {
        png::ColorType::Rgba => 4,
        png::ColorType::Rgb => 3,
        _ => return None,
    };
    let mut b = Bitmap::new(info.width, info.height)?;
    for (i, p) in buf[..info.width as usize * info.height as usize * ch].chunks_exact(ch).enumerate() {
        b.data[i * 4..i * 4 + 4].copy_from_slice(&[p[2], p[1], p[0], 255]);
    }
    Some(b)
}

/// `.cpbitmap` của SpringBoard iOS 6: điểm ảnh BGRA thô, cuối tệp là 6 số 32 bit (trong đó có rộng, cao).
fn load_cpbitmap(bytes: &[u8]) -> Option<Bitmap> {
    if bytes.len() < 24 {
        return None;
    }
    let tail = &bytes[bytes.len() - 24..];
    let word = |i: usize| u32::from_le_bytes([tail[i * 4], tail[i * 4 + 1], tail[i * 4 + 2], tail[i * 4 + 3]]);
    let words: Vec<u32> = (0..6).map(word).collect();
    eprintln!("cpbitmap: đuôi tệp = {words:?}");
    let body = bytes.len() - 24;
    // Tìm cặp (rộng, cao) trong đuôi tệp khớp với cỡ dữ liệu
    for i in 0..6 {
        for j in 0..6 {
            let (w, h) = (words[i] as usize, words[j] as usize);
            if i != j && w > 0 && h > 0 && w <= 4096 && h <= 4096 && w * h * 4 == body {
                let v = View { w: w as u32, h: h as u32, stride: w * 4, data: &bytes[..body] };
                let mut b = Bitmap::from_view(v)?;
                for p in b.data.chunks_exact_mut(4) {
                    p[3] = 255;
                }
                return Some(b);
            }
        }
    }
    // Hình vuông
    let side = ((body / 4) as f64).sqrt() as usize;
    if side * side * 4 == body {
        let v = View { w: side as u32, h: side as u32, stride: side * 4, data: &bytes[..body] };
        let mut b = Bitmap::from_view(v)?;
        for p in b.data.chunks_exact_mut(4) {
            p[3] = 255;
        }
        return Some(b);
    }
    None
}

fn save(path: &Path, b: &Bitmap) {
    let file = File::create(path).expect("tạo tệp ảnh");
    let mut enc = png::Encoder::new(BufWriter::new(file), b.w, b.h);
    enc.set_color(png::ColorType::Rgba);
    enc.set_depth(png::BitDepth::Eight);
    let mut writer = enc.write_header().expect("đầu tệp png");
    let mut rgba = vec![0u8; b.data.len()];
    for (i, p) in b.data.chunks_exact(4).enumerate() {
        rgba[i * 4..i * 4 + 4].copy_from_slice(&[p[2], p[1], p[0], p[3]]);
    }
    writer.write_image_data(&rgba).expect("ghi png");
}

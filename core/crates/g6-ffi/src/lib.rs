//! Mặt C của lõi — khai báo tương ứng ở `tweak/Common/G6Core.h`.
//!
//! Quy ước:
//! - Chuỗi vào là C string UTF-8; chuỗi ra do lõi cấp, bên gọi trả lại bằng [`g6_free`].
//! - Ảnh là BGRA 8 bit nhân sẵn alpha; `stride` = số byte mỗi hàng.
//! - Hàm dựng ảnh trả 0 khi được, số âm khi lỗi (xem `G6_ERR_*`). Không hàm nào panic với tham số hỏng — bản cho máy
//!   dựng `panic = abort`, panic là SpringBoard sập.

use std::ffi::{c_char, CStr, CString};
use std::ptr;
use std::slice;

use g6_core::api;
use g6_core::bitmap::View;
use g6_core::glass::{Error, Placement};
use g6_core::theme::Surface;

/// Con trỏ rỗng / chuỗi không phải UTF-8.
pub const G6_ERR_ARG: i32 = -1;
/// Kích thước bằng 0 hoặc quá lớn.
pub const G6_ERR_SIZE: i32 = -2;
/// Vùng nhớ ra không đủ.
pub const G6_ERR_BUFFER: i32 = -3;
/// Ảnh nền hỏng.
pub const G6_ERR_BACKDROP: i32 = -4;
/// Tên bề mặt lạ.
pub const G6_ERR_SURFACE: i32 = -5;

/// Ảnh do bên gọi giữ.
#[repr(C)]
pub struct G6Image {
    pub data: *const u8,
    pub w: u32,
    pub h: u32,
    pub stride: u32,
}

/// Phép biến đổi đưa điểm ảnh của tấm kính tới điểm ảnh của ảnh nền — cùng bố cục `CGAffineTransform` (số thực 32 bit):
/// `X = a·x + c·y + tx`, `Y = b·x + d·y + ty`.
#[repr(C)]
pub struct G6Affine {
    pub a: f32,
    pub b: f32,
    pub c: f32,
    pub d: f32,
    pub tx: f32,
    pub ty: f32,
}

static VERSION_C: &[u8] = concat!(env!("CARGO_PKG_VERSION"), "\0").as_bytes();

/// Số bản của lõi — chuỗi tĩnh, không phải trả lại.
#[no_mangle]
pub extern "C" fn g6_version() -> *const c_char {
    VERSION_C.as_ptr() as *const c_char
}

/// Lệnh điều khiển JSON. Trả chuỗi JSON (trả lại bằng `g6_free`), hoặc NULL nếu `json` rỗng / không phải UTF-8.
///
/// # Safety
/// `json` phải là C string hợp lệ hoặc NULL.
#[no_mangle]
pub unsafe extern "C" fn g6_call(json: *const c_char) -> *mut c_char {
    if json.is_null() {
        return ptr::null_mut();
    }
    let Ok(input) = CStr::from_ptr(json).to_str() else {
        return ptr::null_mut();
    };
    let out = api::call(input);
    // JSON không chứa byte 0; nếu có (không thể) thì trả NULL thay vì panic
    CString::new(out).map(CString::into_raw).unwrap_or(ptr::null_mut())
}

/// Trả lại chuỗi do `g6_call` cấp.
///
/// # Safety
/// `s` phải là con trỏ `g6_call` trả về, chưa trả lại lần nào, hoặc NULL.
#[no_mangle]
pub unsafe extern "C" fn g6_free(s: *mut c_char) {
    if !s.is_null() {
        drop(CString::from_raw(s));
    }
}

unsafe fn view<'a>(img: *const G6Image) -> Option<View<'a>> {
    let img = img.as_ref()?;
    if img.data.is_null() || img.w == 0 || img.h == 0 || img.w > g6_core::MAX_SIDE || img.h > g6_core::MAX_SIDE {
        return None;
    }
    let stride = img.stride as usize;
    if stride < img.w as usize * 4 {
        return None;
    }
    let len = (img.h as usize - 1) * stride + img.w as usize * 4;
    Some(View { w: img.w, h: img.h, stride, data: slice::from_raw_parts(img.data, len) })
}

unsafe fn out_slice<'a>(out: *mut u8, w: u32, h: u32, stride: u32) -> Result<&'a mut [u8], i32> {
    if out.is_null() {
        return Err(G6_ERR_ARG);
    }
    if w == 0 || h == 0 || w > g6_core::MAX_SIDE || h > g6_core::MAX_SIDE {
        return Err(G6_ERR_SIZE);
    }
    if (stride as usize) < w as usize * 4 {
        return Err(G6_ERR_BUFFER);
    }
    let len = (h as usize - 1) * stride as usize + w as usize * 4;
    Ok(slice::from_raw_parts_mut(out, len))
}

/// Cỡ ảnh nền sau khi chuẩn bị từ ảnh gốc `src_w × src_h` (để bên gọi cấp vùng nhớ). Trả 0 khi được.
/// `pre`: ảnh gốc đã được thu nhỏ sẵn bấy nhiêu lần so với màn hình (1 = ảnh cỡ màn hình).
///
/// # Safety
/// `out_w`, `out_h` phải trỏ tới vùng ghi được hoặc NULL.
#[no_mangle]
pub unsafe extern "C" fn g6_backdrop_size(
    src_w: u32,
    src_h: u32,
    scale: f32,
    fast: i32,
    pre: u32,
    out_w: *mut u32,
    out_h: *mut u32,
) -> i32 {
    if out_w.is_null() || out_h.is_null() {
        return G6_ERR_ARG;
    }
    if src_w == 0 || src_h == 0 || src_w > g6_core::MAX_SIDE || src_h > g6_core::MAX_SIDE {
        return G6_ERR_SIZE;
    }
    let plan = api::backdrop_plan_pre(scale, fast != 0, pre);
    *out_w = (src_w / plan.factor).max(1);
    *out_h = (src_h / plan.factor).max(1);
    0
}

/// Chuẩn bị nền dưới kính: thu nhỏ + làm mờ + tăng bão hoà ảnh gốc `src` vào `out` (cỡ lấy từ `g6_backdrop_size`
/// với cùng `pre`).
///
/// # Safety
/// `src` trỏ tới `G6Image` hợp lệ; `out` ghi được `out_h` hàng, mỗi hàng `out_stride` byte.
#[no_mangle]
pub unsafe extern "C" fn g6_backdrop_prepare(
    src: *const G6Image,
    scale: f32,
    fast: i32,
    pre: u32,
    out: *mut u8,
    out_w: u32,
    out_h: u32,
    out_stride: u32,
) -> i32 {
    let Some(v) = view(src) else {
        return G6_ERR_BACKDROP;
    };
    let dst = match out_slice(out, out_w, out_h, out_stride) {
        Ok(d) => d,
        Err(e) => return e,
    };
    let Some(small) = api::prepare_backdrop_pre(v, scale, fast != 0, pre) else {
        return G6_ERR_SIZE;
    };
    if small.w != out_w || small.h != out_h {
        return G6_ERR_BUFFER;
    }
    let row = out_w as usize * 4;
    for y in 0..out_h as usize {
        let d = y * out_stride as usize;
        dst[d..d + row].copy_from_slice(&small.data[y * row..(y + 1) * row]);
    }
    0
}

/// Dựng một bề mặt kính `w × h` điểm ảnh vào `out`.
/// `backdrop` + `place` NULL → kính giả (không có nền). `dark` khác 0 = chế độ tối.
///
/// # Safety
/// `surface` là C string; `backdrop`, `place` hợp lệ hoặc cùng NULL; `out` ghi được `h` hàng `out_stride` byte.
#[no_mangle]
pub unsafe extern "C" fn g6_glass_render(
    surface: *const c_char,
    w: u32,
    h: u32,
    scale: f32,
    dark: i32,
    backdrop: *const G6Image,
    place: *const G6Affine,
    out: *mut u8,
    out_stride: u32,
) -> i32 {
    if surface.is_null() {
        return G6_ERR_ARG;
    }
    let Some(surface) = CStr::from_ptr(surface).to_str().ok().and_then(Surface::parse) else {
        return G6_ERR_SURFACE;
    };
    let dst = match out_slice(out, w, h, out_stride) {
        Ok(d) => d,
        Err(e) => return e,
    };
    let bd = if backdrop.is_null() {
        None
    } else {
        let Some(v) = view(backdrop) else {
            return G6_ERR_BACKDROP;
        };
        let Some(m) = place.as_ref() else {
            return G6_ERR_ARG;
        };
        Some((v, Placement { a: m.a, b: m.b, c: m.c, d: m.d, tx: m.tx, ty: m.ty }))
    };
    match api::render_surface(surface, w, h, scale, dark != 0, bd, dst, out_stride as usize) {
        Ok(()) => 0,
        Err(Error::Size) => G6_ERR_SIZE,
        Err(Error::Buffer) => G6_ERR_BUFFER,
        Err(Error::Backdrop) => G6_ERR_BACKDROP,
    }
}

/// Hoàn thiện ảnh biểu tượng app: `pixels` chứa ảnh gốc của app đã vẽ kín `w × h` (BGRA nhân sẵn alpha); lõi cắt theo hình
/// bo góc liên tục và thêm viền sáng, sửa tại chỗ.
///
/// # Safety
/// `pixels` đọc / ghi được `h` hàng, mỗi hàng `stride` byte.
#[no_mangle]
pub unsafe extern "C" fn g6_icon_render(pixels: *mut u8, w: u32, h: u32, stride: u32, scale: f32, dark: i32) -> i32 {
    let buf = match out_slice(pixels, w, h, stride) {
        Ok(b) => b,
        Err(e) => return e,
    };
    match api::finish_icon(w, h, scale, dark != 0, buf, stride as usize) {
        Ok(()) => 0,
        Err(Error::Size) => G6_ERR_SIZE,
        Err(Error::Buffer) => G6_ERR_BUFFER,
        Err(Error::Backdrop) => G6_ERR_BACKDROP,
    }
}

/// Dựng bóng đổ của bề mặt `w × h` vào `out` cỡ `(w + 2·lề) × (h + 2·lề)`; lề lấy từ lệnh `glass.metrics` (`shadowMargin`).
///
/// # Safety
/// Như `g6_glass_render`.
#[no_mangle]
pub unsafe extern "C" fn g6_shadow_render(
    surface: *const c_char,
    w: u32,
    h: u32,
    scale: f32,
    dark: i32,
    out: *mut u8,
    out_w: u32,
    out_h: u32,
    out_stride: u32,
) -> i32 {
    if surface.is_null() {
        return G6_ERR_ARG;
    }
    let Some(surface) = CStr::from_ptr(surface).to_str().ok().and_then(Surface::parse) else {
        return G6_ERR_SURFACE;
    };
    let dst = match out_slice(out, out_w, out_h, out_stride) {
        Ok(d) => d,
        Err(e) => return e,
    };
    let Some((bmp, _margin)) = api::render_surface_shadow(surface, w, h, scale, dark != 0) else {
        return G6_ERR_SIZE;
    };
    if bmp.w != out_w || bmp.h != out_h {
        return G6_ERR_BUFFER;
    }
    let row = out_w as usize * 4;
    for y in 0..out_h as usize {
        let d = y * out_stride as usize;
        dst[d..d + row].copy_from_slice(&bmp.data[y * row..(y + 1) * row]);
    }
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn goi_qua_mat_c() {
        unsafe {
            assert_eq!(CStr::from_ptr(g6_version()).to_str().unwrap(), g6_core::VERSION);
            assert!(g6_call(ptr::null()).is_null());
            let r = g6_call(c"{\"cmd\":\"version\"}".as_ptr());
            assert!(CStr::from_ptr(r).to_str().unwrap().contains("\"ok\":true"));
            g6_free(r);
            g6_free(ptr::null_mut());
        }
    }

    #[test]
    fn dung_kinh_qua_mat_c() {
        unsafe {
            let src = vec![128u8; 256 * 192 * 4];
            let img = G6Image { data: src.as_ptr(), w: 256, h: 192, stride: 256 * 4 };
            let (mut bw, mut bh) = (0u32, 0u32);
            assert_eq!(g6_backdrop_size(256, 192, 1.0, 0, 1, &mut bw, &mut bh), 0);
            assert_eq!((bw, bh), (64, 48));
            let mut small = vec![0u8; (bw * bh * 4) as usize];
            assert_eq!(g6_backdrop_prepare(&img, 1.0, 0, 1, small.as_mut_ptr(), bw, bh, bw * 4), 0);
            // Ảnh đã thu nhỏ sẵn 4 lần → giữ nguyên cỡ
            let (mut pw, mut ph) = (0u32, 0u32);
            assert_eq!(g6_backdrop_size(256, 192, 1.0, 0, 4, &mut pw, &mut ph), 0);
            assert_eq!((pw, ph), (256, 192));
            let bd = G6Image { data: small.as_ptr(), w: bw, h: bh, stride: bw * 4 };
            let rect = G6Affine { a: 0.25, b: 0.0, c: 0.0, d: 0.25, tx: 2.0, ty: 2.0 };
            let mut out = vec![0u8; 120 * 40 * 4];
            let rc = g6_glass_render(c"capsule".as_ptr(), 120, 40, 1.0, 0, &bd, &rect, out.as_mut_ptr(), 480);
            assert_eq!(rc, 0);
            assert_eq!(out[(20 * 120 + 60) * 4 + 3], 255);
            // Kính giả
            assert_eq!(g6_glass_render(c"bar".as_ptr(), 120, 40, 1.0, 1, ptr::null(), ptr::null(), out.as_mut_ptr(), 480), 0);
        }
    }

    #[test]
    fn tham_so_hong_tra_ma_loi() {
        unsafe {
            let mut out = vec![0u8; 16];
            let o = out.as_mut_ptr();
            assert_eq!(g6_glass_render(ptr::null(), 2, 2, 1.0, 0, ptr::null(), ptr::null(), o, 8), G6_ERR_ARG);
            assert_eq!(g6_glass_render(c"la".as_ptr(), 2, 2, 1.0, 0, ptr::null(), ptr::null(), o, 8), G6_ERR_SURFACE);
            assert_eq!(g6_glass_render(c"dock".as_ptr(), 0, 2, 1.0, 0, ptr::null(), ptr::null(), o, 8), G6_ERR_SIZE);
            assert_eq!(g6_glass_render(c"dock".as_ptr(), 2, 2, 1.0, 0, ptr::null(), ptr::null(), o, 7), G6_ERR_BUFFER);
            assert_eq!(
                g6_glass_render(c"dock".as_ptr(), 2, 2, 1.0, 0, ptr::null(), ptr::null(), ptr::null_mut(), 8),
                G6_ERR_ARG
            );
            let bad = G6Image { data: ptr::null(), w: 4, h: 4, stride: 16 };
            let rect = G6Affine { a: 1.0, b: 0.0, c: 0.0, d: 1.0, tx: 0.0, ty: 0.0 };
            assert_eq!(g6_glass_render(c"dock".as_ptr(), 2, 2, 1.0, 0, &bad, &rect, o, 8), G6_ERR_BACKDROP);
            assert_eq!(g6_shadow_render(c"dock".as_ptr(), 2, 2, 1.0, 0, o, 2, 2, 8), G6_ERR_BUFFER);
            assert_eq!(g6_backdrop_size(0, 5, 1.0, 0, 1, &mut 0, &mut 0), G6_ERR_SIZE);
            assert_eq!(g6_icon_render(ptr::null_mut(), 2, 2, 8, 1.0, 0), G6_ERR_ARG);
            assert_eq!(g6_icon_render(o, 0, 2, 8, 1.0, 0), G6_ERR_SIZE);
            assert_eq!(g6_icon_render(o, 2, 2, 7, 1.0, 0), G6_ERR_BUFFER);
            assert_eq!(g6_icon_render(o, 2, 2, 8, f32::NAN, 1), 0);
        }
    }
}

//! glass6ctl — công cụ dòng lệnh (quyền mobile) của Glass 6 cho cập nhật OTA. Xem docs/THIET-KE.md mục 10.
//!
//! ```text
//! glass6ctl version                         in số bản
//! glass6ctl update check                    hỏi bản mới nhất → một dòng JSON; ghi /var/mobile/Library/Glass6/update.json
//! glass6ctl update download                 tải gói + chữ ký của bản mới về …/Glass6/update/ → các dòng «progress <đã tải> <tổng>»
//!                                           rồi một dòng JSON có đường dẫn hai tệp (đưa cho g6update)
//! glass6ctl update clean                    dọn thư mục tải
//!   --current <bản>                         coi như đang cài bản này (thử; g6update vẫn so với bản cài thật trước khi cài)
//! ```
//!
//! Tách riêng khỏi libglass6core.dylib để SpringBoard và các app không phải gánh TLS (rustls + bộ chứng chỉ gốc ~1 MB).
//! Công cụ không có quyền gì đặc biệt: mọi thứ tải về đều do g6update kiểm chữ ký số trước khi cài.
//! Mã thoát: 0 = được · 1 = lỗi (dòng JSON cuối có "ok": false, "error": mã, "detail": lời) · 64 = sai cách dùng.
mod http;
mod update;

use serde_json::{json, Value};
use std::ffi::CStr;
use std::io::Write;
use std::os::raw::{c_char, c_int};
use std::path::PathBuf;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

const VERSION: &str = env!("CARGO_PKG_VERSION");
const USER_AGENT: &str = concat!("Glass6/", env!("CARGO_PKG_VERSION"), " (iOS 6 tweak; +https://github.com/itovn/Glass6)");
const DATA_DIR: &str = "/var/mobile/Library/Glass6";

/// Thư mục dữ liệu của Glass 6 (bản thử: đổi được bằng G6_DATA_DIR để chạy trên PC)
fn data_dir() -> PathBuf {
    #[cfg(feature = "test-source")]
    if let Ok(dir) = std::env::var("G6_DATA_DIR") {
        if !dir.is_empty() {
            return PathBuf::from(dir);
        }
    }
    PathBuf::from(DATA_DIR)
}

/// Nguồn cập nhật: (địa chỉ API, tiền tố link tải). Bản phát hành: cố định. Bản thử: đổi được bằng biến môi trường
/// G6_UPDATE_API / G6_UPDATE_PREFIX hoặc tệp `update-source.txt` trong thư mục dữ liệu (dòng 1: API, dòng 2: tiền tố).
fn source() -> (String, String) {
    #[cfg(feature = "test-source")]
    {
        let file = std::fs::read_to_string(data_dir().join("update-source.txt")).unwrap_or_default();
        let mut lines = file.lines().map(str::trim).filter(|l| !l.is_empty());
        let api = std::env::var("G6_UPDATE_API").ok().or_else(|| lines.next().map(String::from));
        let prefix = std::env::var("G6_UPDATE_PREFIX").ok().or_else(|| lines.next().map(String::from));
        if let Some(api) = api {
            return (api, prefix.unwrap_or_else(|| update::ASSET_PREFIX.to_string()));
        }
    }
    (update::API_URL.to_string(), update::ASSET_PREFIX.to_string())
}

fn now() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0)
}

/// In một dòng ra stdout (bỏ qua lỗi ghi: bên đọc đã đóng ống thì thôi)
fn emit_line(line: &str) {
    let out = std::io::stdout();
    let mut out = out.lock();
    let _ = writeln!(out, "{line}");
    let _ = out.flush();
}

fn emit(value: &Value) {
    emit_line(&value.to_string());
}

fn fail(code: &str, detail: &str, extra: Value) -> i32 {
    let mut v = json!({"ok": false, "error": code, "detail": detail});
    if let (Some(obj), Some(more)) = (v.as_object_mut(), extra.as_object()) {
        for (k, val) in more {
            obj.insert(k.clone(), val.clone());
        }
    }
    emit(&v);
    1
}

fn cmd_check(current: &str) -> i32 {
    let (api, prefix) = source();
    let client = match http::Client::new(USER_AGENT) {
        Ok(c) => c,
        Err(e) => return fail(e.code(), &e.to_string(), json!({})),
    };
    match update::fetch_release(&client, &api, &prefix) {
        Ok(release) => {
            let result = update::check_json(&release, current, now());
            // Tệp trạng thái: lượt kiểm thành công gần nhất (bảng Cài đặt và SpringBoard đọc). Không ghi được cũng không sao.
            let _ = std::fs::create_dir_all(data_dir());
            let _ = update::write_state(&data_dir().join("update.json"), &result);
            emit(&result);
            0
        }
        Err(e) => fail(e.code(), &e.to_string(), json!({"status": e.status(), "checked": now(), "current": current})),
    }
}

fn cmd_download(current: &str) -> i32 {
    let (api, prefix) = source();
    let client = match http::Client::new(USER_AGENT) {
        Ok(c) => c,
        Err(e) => return fail(e.code(), &e.to_string(), json!({})),
    };
    let release = match update::fetch_release(&client, &api, &prefix) {
        Ok(r) => r,
        Err(e) => return fail(e.code(), &e.to_string(), json!({"status": e.status()})),
    };
    if !update::newer(&release.version, current) {
        return fail("current", "đang dùng bản mới nhất", json!({"latest": release.version, "current": current}));
    }
    let dir = data_dir().join("update");
    // Tiến độ: không quá ~8 dòng mỗi giây, luôn có dòng cuối
    let mut last: Option<Instant> = None;
    let mut progress = |done: u64, total: u64| {
        let due = last.map(|t| t.elapsed() >= Duration::from_millis(120)).unwrap_or(true);
        if due || (total > 0 && done >= total) {
            last = Some(Instant::now());
            emit_line(&format!("progress {done} {total}"));
        }
    };
    match update::download(&client, &release, &dir, &mut progress) {
        Ok((deb, sig)) => {
            emit(&json!({"ok": true, "version": release.version, "deb": deb.to_string_lossy(), "sig": sig.to_string_lossy()}));
            0
        }
        Err(e) => fail(e.code(), &e.to_string(), json!({"latest": release.version})),
    }
}

fn usage() -> i32 {
    eprintln!("glass6ctl {VERSION} — cập nhật OTA của Glass 6");
    eprintln!("  glass6ctl version");
    eprintln!("  glass6ctl update check [--current <bản>]");
    eprintln!("  glass6ctl update download [--current <bản>]");
    eprintln!("  glass6ctl update clean");
    64
}

fn run(args: &[String]) -> i32 {
    // Tuỳ chọn --current <bản> đứng đâu cũng được
    let mut current = VERSION.to_string();
    let mut words: Vec<&str> = Vec::new();
    let mut i = 1;
    while i < args.len() {
        if args[i] == "--current" {
            match args.get(i + 1) {
                Some(v) if !v.is_empty() => current = v.clone(),
                _ => return usage(),
            }
            i += 2;
        } else {
            words.push(args[i].as_str());
            i += 1;
        }
    }
    match words.as_slice() {
        ["version"] => {
            emit_line(VERSION);
            0
        }
        ["update", "check"] => cmd_check(&current),
        ["update", "download"] => cmd_download(&current),
        ["update", "clean"] => {
            update::clean_dir(&data_dir().join("update"));
            emit(&json!({"ok": true}));
            0
        }
        _ => usage(),
    }
}

/// Điểm vào cho `main` của C (ctl/main.c).
///
/// # Safety
/// `argv` phải là mảng `argc` con trỏ chuỗi C hợp lệ (đúng như `main` nhận từ hệ điều hành).
#[no_mangle]
pub unsafe extern "C" fn g6ctl_main(argc: c_int, argv: *const *const c_char) -> c_int {
    let mut args = Vec::new();
    if !argv.is_null() {
        for i in 0..argc.max(0) as isize {
            let p = *argv.offset(i);
            if p.is_null() {
                break;
            }
            args.push(CStr::from_ptr(p).to_string_lossy().into_owned());
        }
    }
    run(&args)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn args(list: &[&str]) -> Vec<String> {
        list.iter().map(|s| s.to_string()).collect()
    }

    #[test]
    fn sai_cach_dung() {
        assert_eq!(run(&args(&["glass6ctl"])), 64);
        assert_eq!(run(&args(&["glass6ctl", "update"])), 64);
        assert_eq!(run(&args(&["glass6ctl", "update", "xoa-het"])), 64);
        assert_eq!(run(&args(&["glass6ctl", "update", "check", "--current"])), 64);
        assert_eq!(run(&args(&["glass6ctl", "version"])), 0);
    }

    #[test]
    fn nguon_mac_dinh_la_repo_cong_khai() {
        assert_eq!(update::API_URL, "https://api.github.com/repos/itovn/Glass6/releases/latest");
        assert_eq!(update::ASSET_PREFIX, "https://github.com/itovn/Glass6/releases/download/");
        assert!(USER_AGENT.starts_with("Glass6/"));
    }

    /// Thử với GitHub thật: TLS, chứng chỉ gốc đóng kèm, JSON của API, chuyển tiếp sang máy chủ tệp.
    /// `cargo test -p g6-ctl -- --ignored --nocapture` (đổi nguồn bằng G6_TEST_API)
    #[test]
    #[ignore = "cần mạng"]
    fn mang_that_github() {
        let api = std::env::var("G6_TEST_API").unwrap_or_else(|_| "https://api.github.com/repos/itovn/GramMini/releases/latest".into());
        let client = http::Client::new(USER_AGENT).unwrap();
        let bytes = client.get_bytes(&api, "application/vnd.github+json", 1 << 20).unwrap();
        let v: Value = serde_json::from_slice(&bytes).unwrap();
        println!("tag_name = {}", v["tag_name"]);
        assert!(v["tag_name"].is_string());
        // Tệp chữ ký (vài trăm byte) — đi qua một lần chuyển tiếp
        let sig = v["assets"].as_array().and_then(|list| {
            list.iter().find(|a| a["name"].as_str().map(|n| n.ends_with(".sig")).unwrap_or(false)).cloned()
        });
        if let Some(sig) = sig {
            let url = sig["browser_download_url"].as_str().unwrap();
            let got = client.get_bytes(url, "application/octet-stream", 4096).unwrap();
            println!("{} → {} byte", url, got.len());
            assert_eq!(got.len() as u64, sig["size"].as_u64().unwrap());
        }
    }
}

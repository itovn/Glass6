//! Cập nhật OTA của Glass 6 (docs/THIET-KE.md mục 10): hỏi bản phát hành mới nhất trên GitHub, tải gói `.deb` và chữ ký `.deb.sig`
//! về thư mục tải. Việc kiểm chữ ký và cài là của `g6update` (quyền root) — ở đây chỉ kiểm sơ bộ (kích thước, SHA-256 GitHub ghi
//! cho tệp đính kèm) để báo lỗi tải sớm.
use crate::http::{Client, HttpError};
use serde_json::{json, Value};
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};

pub const API_URL: &str = "https://api.github.com/repos/itovn/Glass6/releases/latest";
/// Tệp phát hành chỉ tải từ đúng repo này (GitHub chuyển tiếp sang máy chủ tệp của nó — lớp HTTP chỉ theo link https)
pub const ASSET_PREFIX: &str = "https://github.com/itovn/Glass6/releases/download/";
const DEB_PREFIX: &str = "vn.glass6.tweak_";
const DEB_SUFFIX: &str = "_iphoneos-arm.deb";
/// Cùng giới hạn với g6update
pub const MAX_DEB: u64 = 64 * 1024 * 1024;
pub const MAX_SIG: u64 = 1024;
const MAX_API: u64 = 1024 * 1024;
const MAX_NOTES: usize = 600;

#[derive(Debug, Clone, PartialEq)]
pub struct Asset {
    pub name: String,
    pub url: String,
    pub size: u64,
    /// SHA-256 (hex thường) GitHub ghi cho tệp đính kèm, nếu có
    pub sha256: Option<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Release {
    pub version: String,
    /// Gói cài được: có đủ `.deb` và `.deb.sig` với link đúng repo
    pub deb: Option<Asset>,
    pub sig_url: Option<String>,
    pub notes: String,
}

/// Phần số của một số bản: "v1.2.3" / "1.2.3-1+debug" → [1, 2, 3]
fn version_numbers(v: &str) -> Vec<u64> {
    let v = v.trim().trim_start_matches(['v', 'V']);
    let upstream = v.split(['-', '+', '~']).next().unwrap_or("");
    upstream
        .split('.')
        .map(|p| p.chars().take_while(char::is_ascii_digit).collect::<String>().parse::<u64>().unwrap_or(0))
        .collect()
}

/// Bản `a` mới hơn bản `b` (so từng số; thiếu số coi là 0). g6update so lại bằng dpkg trước khi cài.
pub fn newer(a: &str, b: &str) -> bool {
    let (x, y) = (version_numbers(a), version_numbers(b));
    for i in 0..x.len().max(y.len()) {
        let (p, q) = (x.get(i).copied().unwrap_or(0), y.get(i).copied().unwrap_or(0));
        if p != q {
            return p > q;
        }
    }
    false
}

/// Tên tệp / số bản chỉ gồm chữ số, chữ cái và `. _ + - ~` (đi vào đường dẫn tệp)
fn safe_name(s: &str) -> bool {
    !s.is_empty()
        && s.len() <= 96
        && !s.starts_with('.')
        && s.bytes().all(|b| b.is_ascii_alphanumeric() || matches!(b, b'.' | b'_' | b'+' | b'-' | b'~'))
}

/// Ghi chú phát hành (markdown) → chữ thường: bỏ `**`, dấu `` ` ``, dấu `#` đầu dòng; gạch đầu dòng → «• »; cắt còn 600 ký tự
pub fn clean_notes(body: &str) -> String {
    let text = body.replace('\r', "").replace("**", "").replace('`', "");
    let mut lines: Vec<String> = Vec::new();
    for line in text.lines() {
        let t = line.trim_end();
        let t = match t.strip_prefix("- ").or_else(|| t.strip_prefix("* ")) {
            Some(rest) => format!("• {}", rest.trim_start()),
            None => t.trim_start_matches('#').trim_start().to_string(),
        };
        // Không quá một dòng trống liền nhau
        if t.is_empty() && lines.last().map(|l| l.is_empty()).unwrap_or(true) {
            continue;
        }
        lines.push(t);
    }
    let joined = lines.join("\n").trim().to_string();
    if joined.chars().count() > MAX_NOTES {
        let cut: String = joined.chars().take(MAX_NOTES).collect();
        format!("{}…", cut.trim_end())
    } else {
        joined
    }
}

/// Đọc trả lời của `…/releases/latest`. `prefix`: link tải phải bắt đầu bằng chuỗi này.
pub fn parse_release(text: &str, prefix: &str) -> Result<Release, String> {
    let v: Value = serde_json::from_str(text).map_err(|e| format!("JSON sai: {e}"))?;
    let tag = v.get("tag_name").and_then(Value::as_str).ok_or("thiếu tag_name")?;
    let version = tag.trim().trim_start_matches(['v', 'V']).to_string();
    if !safe_name(&version) || !version.starts_with(|c: char| c.is_ascii_digit()) {
        return Err("số bản lạ".into());
    }
    let empty = Vec::new();
    let assets = v.get("assets").and_then(Value::as_array).unwrap_or(&empty);
    let field = |a: &Value, k: &str| a.get(k).and_then(Value::as_str).unwrap_or("").to_string();
    let mut deb = None;
    for a in assets {
        let (name, url) = (field(a, "name"), field(a, "browser_download_url"));
        if name.starts_with(DEB_PREFIX) && name.ends_with(DEB_SUFFIX) && safe_name(&name) && url.starts_with(prefix) {
            let sha256 = field(a, "digest")
                .strip_prefix("sha256:")
                .map(str::to_ascii_lowercase)
                .filter(|h| h.len() == 64 && h.bytes().all(|b| b.is_ascii_hexdigit()));
            deb = Some(Asset { name, url, size: a.get("size").and_then(Value::as_u64).unwrap_or(0), sha256 });
        }
    }
    let mut sig_url = None;
    if let Some(d) = &deb {
        let want = format!("{}.sig", d.name);
        for a in assets {
            let url = field(a, "browser_download_url");
            if field(a, "name") == want && url.starts_with(prefix) {
                sig_url = Some(url);
            }
        }
    }
    // Thiếu chữ ký thì coi như không có gói cài được (g6update không cài gói không chữ ký)
    if sig_url.is_none() {
        deb = None;
    }
    let notes = clean_notes(v.get("body").and_then(Value::as_str).unwrap_or(""));
    Ok(Release { version, deb, sig_url, notes })
}

/// Hỏi bản phát hành mới nhất
pub fn fetch_release(client: &Client, api_url: &str, prefix: &str) -> Result<Release, CheckError> {
    let bytes = client.get_bytes(api_url, "application/vnd.github+json", MAX_API).map_err(CheckError::Http)?;
    let text = String::from_utf8(bytes).map_err(|_| CheckError::Parse("không phải văn bản UTF-8".into()))?;
    parse_release(&text, prefix).map_err(CheckError::Parse)
}

#[derive(Debug)]
pub enum CheckError {
    Http(HttpError),
    Parse(String),
}

impl CheckError {
    pub fn code(&self) -> &'static str {
        match self {
            CheckError::Http(e) => e.code(),
            CheckError::Parse(_) => "parse",
        }
    }

    pub fn status(&self) -> Option<u16> {
        match self {
            CheckError::Http(HttpError::Status(c)) => Some(*c),
            _ => None,
        }
    }
}

impl std::fmt::Display for CheckError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            CheckError::Http(e) => e.fmt(f),
            CheckError::Parse(s) => write!(f, "không đọc được thông tin bản phát hành: {s}"),
        }
    }
}

/// Kết quả một lượt kiểm, dạng JSON cho bảng Cài đặt / SpringBoard (cũng là nội dung tệp trạng thái `update.json`)
pub fn check_json(release: &Release, current: &str, now: u64) -> Value {
    let is_newer = newer(&release.version, current);
    json!({
        "ok": true,
        "checked": now,
        "current": current,
        "latest": release.version,
        "newer": is_newer,
        // Có bản mới nhưng thiếu gói / chữ ký đúng chỗ → chỉ cập nhật được qua Cydia
        "installable": is_newer && release.deb.is_some(),
        "size": release.deb.as_ref().map(|d| d.size).unwrap_or(0),
        "notes": release.notes,
    })
}

/// Ghi tệp trạng thái (ghi tệp tạm rồi đổi tên — bên đọc không bao giờ thấy tệp dở)
pub fn write_state(path: &Path, value: &Value) -> std::io::Result<()> {
    let tmp = path.with_extension("json.tmp");
    let _ = fs::remove_file(&tmp);
    fs::write(&tmp, serde_json::to_vec(value).unwrap_or_default())?;
    fs::rename(&tmp, path)
}

/// Dọn thư mục tải: bỏ mọi tệp (không đi theo liên kết tượng trưng, không đụng thư mục con)
pub fn clean_dir(dir: &Path) {
    let Ok(entries) = fs::read_dir(dir) else { return };
    for entry in entries.flatten() {
        let path = entry.path();
        if let Ok(meta) = fs::symlink_metadata(&path) {
            if !meta.is_dir() {
                let _ = fs::remove_file(&path);
            }
        }
    }
}

#[derive(Debug)]
pub enum DownloadError {
    /// Bản mới nhất không kèm gói + chữ ký tải được
    NotInstallable,
    Http(HttpError),
    Io(String),
    Size { got: u64, want: u64 },
    Hash,
    Signature,
}

impl DownloadError {
    pub fn code(&self) -> &'static str {
        match self {
            DownloadError::NotInstallable => "unsigned",
            DownloadError::Http(e) => e.code(),
            DownloadError::Io(_) => "io",
            DownloadError::Size { .. } => "size",
            DownloadError::Hash => "hash",
            DownloadError::Signature => "signature",
        }
    }
}

impl std::fmt::Display for DownloadError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            DownloadError::NotInstallable => write!(f, "bản này không kèm gói có chữ ký — cập nhật bằng Cydia"),
            DownloadError::Http(e) => e.fmt(f),
            DownloadError::Io(s) => write!(f, "không ghi được tệp: {s}"),
            DownloadError::Size { got, want } => write!(f, "tệp tải về sai kích thước ({got} / {want} byte)"),
            DownloadError::Hash => write!(f, "tệp tải về bị sai (SHA-256 không khớp)"),
            DownloadError::Signature => write!(f, "không tải được chữ ký của bản cập nhật"),
        }
    }
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

/// Tải gói và chữ ký của `release` vào `dir` (dọn thư mục trước). `progress(đã tải, tổng)` gọi theo từng khúc của gói.
/// Trả đường dẫn (.deb, .deb.sig) — hai tệp g6update nhận.
pub fn download(
    client: &Client,
    release: &Release,
    dir: &Path,
    progress: &mut dyn FnMut(u64, u64),
) -> Result<(PathBuf, PathBuf), DownloadError> {
    let (deb, sig_url) = match (&release.deb, &release.sig_url) {
        (Some(d), Some(s)) => (d, s),
        _ => return Err(DownloadError::NotInstallable),
    };
    let io = |e: std::io::Error| DownloadError::Io(e.to_string());
    fs::create_dir_all(dir).map_err(io)?;
    clean_dir(dir);
    let part = dir.join("download.part");
    let deb_path = dir.join(&deb.name);
    let sig_path = dir.join(format!("{}.sig", deb.name));

    // 1. Gói: ghi thẳng ra tệp, băm SHA-256 trong lúc tải
    let mut file = fs::OpenOptions::new().write(true).create_new(true).open(&part).map_err(io)?;
    let mut hasher = ring::digest::Context::new(&ring::digest::SHA256);
    let mut done = 0u64;
    let fetched = client.get(&deb.url, "application/octet-stream", MAX_DEB, &mut |chunk, total| {
        file.write_all(chunk)?;
        hasher.update(chunk);
        done += chunk.len() as u64;
        progress(done, total.unwrap_or(deb.size));
        Ok(())
    });
    let flushed = file.flush();
    drop(file);
    let fail = |e: DownloadError| {
        let _ = fs::remove_file(&part);
        e
    };
    let got = fetched.map_err(|e| fail(DownloadError::Http(e)))?;
    flushed.map_err(|e| fail(io(e)))?;
    if got == 0 || (deb.size > 0 && got != deb.size) {
        return Err(fail(DownloadError::Size { got, want: deb.size }));
    }
    if let Some(want) = &deb.sha256 {
        if &hex(hasher.finish().as_ref()) != want {
            return Err(fail(DownloadError::Hash));
        }
    }

    // 2. Chữ ký (vài trăm byte)
    let sig = client.get_bytes(sig_url, "application/octet-stream", MAX_SIG).map_err(|_| fail(DownloadError::Signature))?;
    if sig.is_empty() {
        return Err(fail(DownloadError::Signature));
    }
    fs::write(&sig_path, &sig).map_err(|e| fail(io(e)))?;
    fs::rename(&part, &deb_path).map_err(|e| fail(io(e)))?;
    Ok((deb_path, sig_path))
}

#[cfg(test)]
mod tests {
    use super::*;

    const SAMPLE: &str = r###"{
      "tag_name": "v1.2.0",
      "name": "Glass 6 1.2.0",
      "body": "## Thay đổi\r\n\r\n- **Thẻ thông báo** kiểu iPhone\r\n- Sửa lỗi `MobilePhone` sập\r\n\r\n\r\nCảm ơn!",
      "assets": [
        {"name": "vn.glass6.tweak_1.2.0_iphoneos-arm.deb", "size": 1868220,
         "digest": "sha256:AB12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12",
         "browser_download_url": "https://github.com/itovn/Glass6/releases/download/v1.2.0/vn.glass6.tweak_1.2.0_iphoneos-arm.deb"},
        {"name": "vn.glass6.tweak_1.2.0_iphoneos-arm.deb.sig", "size": 384,
         "browser_download_url": "https://github.com/itovn/Glass6/releases/download/v1.2.0/vn.glass6.tweak_1.2.0_iphoneos-arm.deb.sig"},
        {"name": "Source code.zip", "size": 1, "browser_download_url": "https://github.com/itovn/Glass6/archive/v1.2.0.zip"}
      ]
    }"###;

    #[test]
    fn so_sanh_so_ban() {
        assert!(newer("1.0.1", "1.0.0"));
        assert!(newer("v1.10.0", "1.9.9"));
        assert!(newer("2", "1.9.9"));
        assert!(newer("1.0.0.1", "1.0.0"));
        assert!(!newer("1.0.0", "1.0.0"));
        assert!(!newer("1.0", "1.0.0"));
        assert!(!newer("0.9.9", "1.0.0"));
        // Bản thử của Theos: «0.1.0-1+debug» ngang với 0.1.0
        assert!(!newer("0.1.0", "0.1.0-1+debug"));
        assert!(newer("0.1.1", "0.1.0-1+debug"));
        assert!(!newer("rác", "1.0.0"));
    }

    #[test]
    fn doc_ban_phat_hanh() {
        let r = parse_release(SAMPLE, ASSET_PREFIX).unwrap();
        assert_eq!(r.version, "1.2.0");
        let deb = r.deb.as_ref().unwrap();
        assert_eq!(deb.name, "vn.glass6.tweak_1.2.0_iphoneos-arm.deb");
        assert_eq!(deb.size, 1868220);
        assert_eq!(deb.sha256.as_deref(), Some("ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12ab12"));
        assert!(r.sig_url.as_deref().unwrap().ends_with(".deb.sig"));
        assert_eq!(r.notes, "Thay đổi\n\n• Thẻ thông báo kiểu iPhone\n• Sửa lỗi MobilePhone sập\n\nCảm ơn!");
        let j = check_json(&r, "1.1.0", 42);
        assert_eq!((j["newer"].as_bool(), j["installable"].as_bool(), j["latest"].as_str()), (Some(true), Some(true), Some("1.2.0")));
        let j = check_json(&r, "1.2.0", 42);
        assert_eq!((j["newer"].as_bool(), j["installable"].as_bool()), (Some(false), Some(false)));
    }

    #[test]
    fn thieu_chu_ky_hoac_link_la_thi_khong_cai_duoc() {
        // Không có tệp .sig
        let no_sig = SAMPLE.replace("iphoneos-arm.deb.sig\", \"size\"", "iphoneos-arm.deb.khac\", \"size\"");
        let r = parse_release(&no_sig, ASSET_PREFIX).unwrap();
        assert!(r.deb.is_none() && r.sig_url.is_none());
        assert_eq!(check_json(&r, "1.0.0", 0)["installable"].as_bool(), Some(false));
        assert_eq!(check_json(&r, "1.0.0", 0)["newer"].as_bool(), Some(true));
        // Link tải ở repo khác
        let other = SAMPLE.replace("github.com/itovn/Glass6/releases", "github.com/kekhac/Glass6/releases");
        assert!(parse_release(&other, ASSET_PREFIX).unwrap().deb.is_none());
        // Tên tệp có ký tự đường dẫn
        let slash = SAMPLE.replace("\"vn.glass6.tweak_1.2.0_iphoneos-arm.deb\"", "\"vn.glass6.tweak_../../x_iphoneos-arm.deb\"");
        assert!(parse_release(&slash, ASSET_PREFIX).unwrap().deb.is_none());
    }

    #[test]
    fn tra_loi_la() {
        assert!(parse_release("không phải JSON", ASSET_PREFIX).is_err());
        assert!(parse_release("{}", ASSET_PREFIX).is_err());
        assert!(parse_release(r#"{"tag_name": "../../etc"}"#, ASSET_PREFIX).is_err());
        assert!(parse_release(r#"{"tag_name": "beta"}"#, ASSET_PREFIX).is_err());
        let bare = parse_release(r#"{"tag_name": "v2.0.0"}"#, ASSET_PREFIX).unwrap();
        assert_eq!((bare.version.as_str(), bare.deb.is_none(), bare.notes.as_str()), ("2.0.0", true, ""));
    }

    #[test]
    fn ghi_chu_dai_bi_cat() {
        let long = "á".repeat(2000);
        let cut = clean_notes(&long);
        assert_eq!(cut.chars().count(), MAX_NOTES + 1);
        assert!(cut.ends_with('…'));
    }

    #[test]
    fn tep_trang_thai_va_don_thu_muc() {
        let dir = std::env::temp_dir().join(format!("g6ctl-test-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(dir.join("update/sub")).unwrap();
        let state = dir.join("update.json");
        write_state(&state, &json!({"ok": true, "latest": "1.0.0"})).unwrap();
        write_state(&state, &json!({"ok": true, "latest": "1.0.1"})).unwrap();
        let back: Value = serde_json::from_slice(&fs::read(&state).unwrap()).unwrap();
        assert_eq!(back["latest"].as_str(), Some("1.0.1"));
        assert!(!dir.join("update.json.tmp").exists());
        fs::write(dir.join("update/a.deb"), b"x").unwrap();
        fs::write(dir.join("update/download.part"), b"x").unwrap();
        clean_dir(&dir.join("update"));
        assert!(!dir.join("update/a.deb").exists() && !dir.join("update/download.part").exists());
        assert!(dir.join("update/sub").is_dir(), "không đụng thư mục con");
        let _ = fs::remove_dir_all(&dir);
    }
}

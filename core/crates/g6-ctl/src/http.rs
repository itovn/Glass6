//! HTTPS GET tối thiểu cho glass6ctl: một kết nối cho mỗi yêu cầu (`Connection: close`), theo chuyển tiếp, thân trả lời theo
//! `Content-Length` / `chunked` / tới khi máy chủ đóng. TLS bằng rustls + bộ chứng chỉ gốc Mozilla đóng kèm (webpki-roots) vì
//! iOS 6 không tự vào được GitHub. Chỉ nhận `https://` (bản thử — feature `test-source` — nhận thêm `http://` để thử với máy chủ
//! trong mạng nội bộ). Không nén, không giữ kết nối, không cookie: đủ cho API của GitHub và tệp phát hành.
use std::fmt;
use std::io::{self, BufRead, BufReader, Read, Write};
use std::net::{SocketAddr, TcpStream, ToSocketAddrs};
use std::sync::Arc;
use std::time::Duration;

const CONNECT_TIMEOUT: Duration = Duration::from_secs(20);
const IO_TIMEOUT: Duration = Duration::from_secs(40);
const MAX_REDIRECTS: usize = 5;
const MAX_HEAD: usize = 64 * 1024;
const MAX_HEADERS: usize = 100;

#[derive(Debug)]
pub enum HttpError {
    Url(String),
    Dns(String),
    Connect(String),
    Tls(String),
    Io(String),
    Status(u16),
    Protocol(&'static str),
    TooLarge,
    Redirect(String),
}

impl HttpError {
    /// Mã ngắn cho bảng Cài đặt chọn câu báo lỗi
    pub fn code(&self) -> &'static str {
        match self {
            HttpError::Url(_) | HttpError::Redirect(_) => "url",
            HttpError::Dns(_) | HttpError::Connect(_) | HttpError::Io(_) => "network",
            HttpError::Tls(_) => "tls",
            HttpError::Status(_) => "http",
            HttpError::Protocol(_) | HttpError::TooLarge => "protocol",
        }
    }
}

impl fmt::Display for HttpError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            HttpError::Url(s) => write!(f, "địa chỉ không hợp lệ: {s}"),
            HttpError::Dns(s) => write!(f, "không tìm được máy chủ: {s}"),
            HttpError::Connect(s) => write!(f, "không kết nối được: {s}"),
            HttpError::Tls(s) => write!(f, "lỗi kết nối an toàn (TLS): {s}"),
            HttpError::Io(s) => write!(f, "lỗi truyền dữ liệu: {s}"),
            HttpError::Status(c) => write!(f, "máy chủ trả mã HTTP {c}"),
            HttpError::Protocol(s) => write!(f, "trả lời sai dạng: {s}"),
            HttpError::TooLarge => write!(f, "dữ liệu lớn quá mức cho phép"),
            HttpError::Redirect(s) => write!(f, "chuyển tiếp không hợp lệ: {s}"),
        }
    }
}

/// Lỗi đọc / ghi của kết nối: lỗi của rustls (chứng chỉ, bắt tay) nằm trong io::Error → tách ra thành lỗi TLS
fn map_io(e: io::Error) -> HttpError {
    if e.get_ref().map(|inner| inner.is::<rustls::Error>()).unwrap_or(false) {
        return HttpError::Tls(e.to_string());
    }
    match e.kind() {
        io::ErrorKind::WouldBlock | io::ErrorKind::TimedOut => HttpError::Io("hết thời gian chờ".into()),
        _ => HttpError::Io(e.to_string()),
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct Url {
    pub tls: bool,
    pub host: String,
    pub port: u16,
    /// Đường dẫn kèm chuỗi truy vấn, luôn bắt đầu bằng `/`
    pub path: String,
}

impl Url {
    fn host_header(&self) -> String {
        let default = if self.tls { 443 } else { 80 };
        if self.port == default {
            self.host.clone()
        } else {
            format!("{}:{}", self.host, self.port)
        }
    }

    fn origin(&self) -> String {
        format!("{}://{}", if self.tls { "https" } else { "http" }, self.host_header())
    }
}

pub fn parse_url(s: &str) -> Result<Url, HttpError> {
    let bad = || HttpError::Url(s.chars().take(120).collect());
    let (tls, rest) = if let Some(r) = s.strip_prefix("https://") {
        (true, r)
    } else if cfg!(feature = "test-source") && s.starts_with("http://") {
        (false, &s["http://".len()..])
    } else {
        return Err(bad());
    };
    let end = rest.find(['/', '?', '#']).unwrap_or(rest.len());
    let (authority, tail) = rest.split_at(end);
    let (host, port) = match authority.rsplit_once(':') {
        Some((h, p)) => (h, p.parse::<u16>().map_err(|_| bad())?),
        None => (authority, if tls { 443 } else { 80 }),
    };
    if host.is_empty() || host.len() > 253 || port == 0 || !host.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'.') {
        return Err(bad());
    }
    let tail = tail.split('#').next().unwrap_or("");
    let path = if tail.is_empty() {
        "/".to_string()
    } else if tail.starts_with('?') {
        format!("/{tail}")
    } else {
        tail.to_string()
    };
    if path.bytes().any(|b| b <= 0x20 || b == 0x7f) {
        return Err(bad());
    }
    Ok(Url { tls, host: host.to_ascii_lowercase(), port, path })
}

/// Địa chỉ đích của một lần chuyển tiếp (`Location`): tuyệt đối, hoặc đường dẫn trên cùng máy chủ
fn resolve(base: &Url, location: &str) -> Result<Url, HttpError> {
    let location = location.trim();
    let next = if location.starts_with("https://") || location.starts_with("http://") {
        parse_url(location)
    } else if location.starts_with('/') && !location.starts_with("//") {
        parse_url(&format!("{}{}", base.origin(), location))
    } else {
        Err(HttpError::Redirect(location.chars().take(120).collect()))
    }
    .map_err(|_| HttpError::Redirect(location.chars().take(120).collect()))?;
    // Không bao giờ rời HTTPS
    if base.tls && !next.tls {
        return Err(HttpError::Redirect(location.chars().take(120).collect()));
    }
    Ok(next)
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Framing {
    Length(u64),
    Chunked,
    Close,
}

#[derive(Debug)]
pub struct Head {
    pub status: u16,
    /// Tên đã đổi sang chữ thường
    pub headers: Vec<(String, String)>,
}

impl Head {
    pub fn header(&self, name: &str) -> Option<&str> {
        self.headers.iter().find(|(k, _)| k == name).map(|(_, v)| v.as_str())
    }

    pub fn framing(&self) -> Result<Framing, HttpError> {
        if let Some(te) = self.header("transfer-encoding") {
            if te.to_ascii_lowercase().contains("chunked") {
                return Ok(Framing::Chunked);
            }
        }
        match self.header("content-length") {
            Some(v) => v.trim().parse::<u64>().map(Framing::Length).map_err(|_| HttpError::Protocol("Content-Length sai")),
            None => Ok(Framing::Close),
        }
    }
}

/// Đọc một dòng (bỏ CR LF), trừ vào `budget`; dòng dài quá phần còn lại → lỗi
fn read_line<R: BufRead>(r: &mut R, budget: &mut usize) -> Result<String, HttpError> {
    let mut buf = Vec::new();
    let n = r.by_ref().take(*budget as u64 + 1).read_until(b'\n', &mut buf).map_err(map_io)?;
    if n == 0 {
        return Err(HttpError::Protocol("máy chủ đóng kết nối giữa chừng"));
    }
    if n > *budget || buf.last() != Some(&b'\n') {
        return Err(HttpError::Protocol("dòng quá dài"));
    }
    *budget -= n;
    while matches!(buf.last(), Some(b'\n') | Some(b'\r')) {
        buf.pop();
    }
    Ok(String::from_utf8_lossy(&buf).into_owned())
}

pub fn read_head<R: BufRead>(r: &mut R) -> Result<Head, HttpError> {
    let mut budget = MAX_HEAD;
    let line = read_line(r, &mut budget)?;
    let mut parts = line.split_whitespace();
    let version = parts.next().unwrap_or("");
    let status = parts.next().and_then(|c| c.parse::<u16>().ok());
    let status = match status {
        Some(c) if version.starts_with("HTTP/1.") && (100..600).contains(&c) => c,
        _ => return Err(HttpError::Protocol("dòng trạng thái sai")),
    };
    let mut headers = Vec::new();
    loop {
        let line = read_line(r, &mut budget)?;
        if line.is_empty() {
            break;
        }
        if headers.len() >= MAX_HEADERS {
            return Err(HttpError::Protocol("quá nhiều dòng đầu"));
        }
        if let Some((k, v)) = line.split_once(':') {
            headers.push((k.trim().to_ascii_lowercase(), v.trim().to_string()));
        }
    }
    Ok(Head { status, headers })
}

/// Chép đúng `left` byte của thân sang `sink`
fn copy_exact<R: Read>(
    r: &mut R,
    mut left: u64,
    total: &mut u64,
    limit: u64,
    buf: &mut [u8],
    sink: &mut dyn FnMut(&[u8]) -> io::Result<()>,
) -> Result<(), HttpError> {
    while left > 0 {
        let want = (buf.len() as u64).min(left) as usize;
        let n = match r.read(&mut buf[..want]) {
            Ok(0) => return Err(HttpError::Protocol("thân trả lời bị cắt")),
            Ok(n) => n,
            Err(e) if e.kind() == io::ErrorKind::Interrupted => continue,
            Err(e) if e.kind() == io::ErrorKind::UnexpectedEof => return Err(HttpError::Protocol("thân trả lời bị cắt")),
            Err(e) => return Err(map_io(e)),
        };
        *total += n as u64;
        if *total > limit {
            return Err(HttpError::TooLarge);
        }
        sink(&buf[..n]).map_err(|e| HttpError::Io(format!("ghi dữ liệu: {e}")))?;
        left -= n as u64;
    }
    Ok(())
}

/// Đọc thân trả lời theo cách đóng khung `framing`, đưa từng khúc cho `sink`; quá `limit` byte → lỗi. Trả số byte.
pub fn pump<R: BufRead>(r: &mut R, framing: Framing, limit: u64, sink: &mut dyn FnMut(&[u8]) -> io::Result<()>) -> Result<u64, HttpError> {
    let mut total = 0u64;
    let mut buf = vec![0u8; 16 * 1024];
    match framing {
        Framing::Length(n) => {
            if n > limit {
                return Err(HttpError::TooLarge);
            }
            copy_exact(r, n, &mut total, limit, &mut buf, sink)?;
        }
        Framing::Chunked => loop {
            let mut budget = 256;
            let line = read_line(r, &mut budget)?;
            let hex = line.split(';').next().unwrap_or("").trim();
            let size = u64::from_str_radix(hex, 16).map_err(|_| HttpError::Protocol("khúc dữ liệu sai dạng"))?;
            if size == 0 {
                // Phần đuôi (nếu có) tới dòng trống; máy chủ đóng sớm ở đây cũng coi là xong
                let mut budget = 8192;
                while let Ok(l) = read_line(r, &mut budget) {
                    if l.is_empty() {
                        break;
                    }
                }
                break;
            }
            copy_exact(r, size, &mut total, limit, &mut buf, sink)?;
            let mut budget = 2;
            if !read_line(r, &mut budget)?.is_empty() {
                return Err(HttpError::Protocol("khúc dữ liệu sai dạng"));
            }
        },
        Framing::Close => loop {
            let n = match r.read(&mut buf) {
                Ok(0) => break,
                Ok(n) => n,
                Err(e) if e.kind() == io::ErrorKind::Interrupted => continue,
                // Máy chủ đóng TCP mà không báo đóng TLS: với kiểu «đọc tới khi đóng» thì đó là hết thân
                Err(e) if e.kind() == io::ErrorKind::UnexpectedEof => break,
                Err(e) => return Err(map_io(e)),
            };
            total += n as u64;
            if total > limit {
                return Err(HttpError::TooLarge);
            }
            sink(&buf[..n]).map_err(|e| HttpError::Io(format!("ghi dữ liệu: {e}")))?;
        },
    }
    Ok(total)
}

enum Stream {
    Tls(Box<rustls::StreamOwned<rustls::ClientConnection, TcpStream>>),
    #[cfg(feature = "test-source")]
    Plain(TcpStream),
}

impl Read for Stream {
    fn read(&mut self, buf: &mut [u8]) -> io::Result<usize> {
        match self {
            Stream::Tls(s) => s.read(buf),
            #[cfg(feature = "test-source")]
            Stream::Plain(s) => s.read(buf),
        }
    }
}

impl Write for Stream {
    fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
        match self {
            Stream::Tls(s) => s.write(buf),
            #[cfg(feature = "test-source")]
            Stream::Plain(s) => s.write(buf),
        }
    }

    fn flush(&mut self) -> io::Result<()> {
        match self {
            Stream::Tls(s) => s.flush(),
            #[cfg(feature = "test-source")]
            Stream::Plain(s) => s.flush(),
        }
    }
}

/// Nơi nhận thân trả lời: (khúc dữ liệu, tổng số byte nếu máy chủ báo trước)
pub type BodySink<'a> = dyn FnMut(&[u8], Option<u64>) -> io::Result<()> + 'a;

pub struct Client {
    tls: Arc<rustls::ClientConfig>,
    user_agent: String,
}

impl Client {
    pub fn new(user_agent: &str) -> Result<Client, HttpError> {
        let mut roots = rustls::RootCertStore::empty();
        roots.extend(webpki_roots::TLS_SERVER_ROOTS.iter().cloned());
        let provider = Arc::new(rustls::crypto::ring::default_provider());
        let config = rustls::ClientConfig::builder_with_provider(provider)
            .with_safe_default_protocol_versions()
            .map_err(|e| HttpError::Tls(e.to_string()))?
            .with_root_certificates(roots)
            .with_no_client_auth();
        Ok(Client { tls: Arc::new(config), user_agent: user_agent.to_string() })
    }

    fn connect(&self, url: &Url) -> Result<Stream, HttpError> {
        let mut addrs: Vec<SocketAddr> =
            (url.host.as_str(), url.port).to_socket_addrs().map_err(|e| HttpError::Dns(e.to_string()))?.collect();
        // IPv4 trước: nhiều mạng báo có IPv6 nhưng không đi được
        addrs.sort_by_key(|a| a.is_ipv6());
        let mut last = String::from("không có địa chỉ");
        let mut sock = None;
        for addr in addrs.iter().take(6) {
            match TcpStream::connect_timeout(addr, CONNECT_TIMEOUT) {
                Ok(s) => {
                    sock = Some(s);
                    break;
                }
                Err(e) => last = e.to_string(),
            }
        }
        let sock = sock.ok_or(HttpError::Connect(last))?;
        let _ = sock.set_read_timeout(Some(IO_TIMEOUT));
        let _ = sock.set_write_timeout(Some(IO_TIMEOUT));
        let _ = sock.set_nodelay(true);
        if url.tls {
            let name = rustls::pki_types::ServerName::try_from(url.host.clone()).map_err(|_| HttpError::Url(url.host.clone()))?;
            let conn = rustls::ClientConnection::new(self.tls.clone(), name).map_err(|e| HttpError::Tls(e.to_string()))?;
            return Ok(Stream::Tls(Box::new(rustls::StreamOwned::new(conn, sock))));
        }
        #[cfg(feature = "test-source")]
        {
            Ok(Stream::Plain(sock))
        }
        #[cfg(not(feature = "test-source"))]
        {
            Err(HttpError::Url(url.host.clone()))
        }
    }

    /// GET `url`, theo chuyển tiếp. Chỉ trả lời 200 mới có thân: từng khúc đưa cho `sink` kèm tổng số byte nếu máy chủ báo
    /// trước. Mã khác → `HttpError::Status`. Trả số byte của thân.
    pub fn get(
        &self,
        url: &str,
        accept: &str,
        limit: u64,
        sink: &mut BodySink<'_>,
    ) -> Result<u64, HttpError> {
        let mut url = parse_url(url)?;
        for _ in 0..=MAX_REDIRECTS {
            let stream = self.connect(&url)?;
            let mut reader = BufReader::with_capacity(16 * 1024, stream);
            let request = format!(
                "GET {} HTTP/1.1\r\nHost: {}\r\nUser-Agent: {}\r\nAccept: {}\r\nAccept-Encoding: identity\r\nConnection: close\r\n\r\n",
                url.path,
                url.host_header(),
                self.user_agent,
                accept
            );
            reader.get_mut().write_all(request.as_bytes()).map_err(map_io)?;
            reader.get_mut().flush().map_err(map_io)?;
            let head = read_head(&mut reader)?;
            match head.status {
                200 => {
                    let framing = head.framing()?;
                    let known = match framing {
                        Framing::Length(n) => Some(n),
                        _ => None,
                    };
                    return pump(&mut reader, framing, limit, &mut |chunk| sink(chunk, known));
                }
                301 | 302 | 303 | 307 | 308 => {
                    let location = head.header("location").ok_or(HttpError::Redirect("thiếu Location".into()))?;
                    url = resolve(&url, location)?;
                }
                code => return Err(HttpError::Status(code)),
            }
        }
        Err(HttpError::Redirect("chuyển tiếp quá nhiều lần".into()))
    }

    /// GET lấy cả thân vào bộ nhớ (tối đa `limit` byte)
    pub fn get_bytes(&self, url: &str, accept: &str, limit: u64) -> Result<Vec<u8>, HttpError> {
        let mut out = Vec::new();
        self.get(url, accept, limit, &mut |chunk, _| {
            out.extend_from_slice(chunk);
            Ok(())
        })?;
        Ok(out)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;

    fn body(raw: &[u8], limit: u64) -> Result<Vec<u8>, HttpError> {
        let mut r = Cursor::new(raw.to_vec());
        let head = read_head(&mut r)?;
        let mut out = Vec::new();
        pump(&mut r, head.framing()?, limit, &mut |c| {
            out.extend_from_slice(c);
            Ok(())
        })?;
        Ok(out)
    }

    #[test]
    fn tach_dia_chi() {
        let u = parse_url("https://API.github.com/repos/itovn/Glass6/releases/latest").unwrap();
        assert_eq!(u, Url { tls: true, host: "api.github.com".into(), port: 443, path: "/repos/itovn/Glass6/releases/latest".into() });
        let u = parse_url("https://example.com:8443?x=1#y").unwrap();
        assert_eq!((u.port, u.path.as_str()), (8443, "/?x=1"));
        assert_eq!(parse_url("https://example.com").unwrap().path, "/");
        assert_eq!(u.host_header(), "example.com:8443");
    }

    #[test]
    fn dia_chi_la_bi_tu_choi() {
        for bad in ["ftp://a.b/c", "https://", "https://user@host/x", "https://ho st/x", "https://host/a b", "https://[::1]/x", "//host/x", "https://host:0/"] {
            assert!(parse_url(bad).is_err(), "{bad}");
        }
        // Bản phát hành không nhận http thường
        assert_eq!(parse_url("http://example.com/x").is_ok(), cfg!(feature = "test-source"));
    }

    #[test]
    fn chuyen_tiep() {
        let base = parse_url("https://github.com/itovn/Glass6/releases/download/v1/a.deb").unwrap();
        let next = resolve(&base, "https://release-assets.githubusercontent.com/x?sig=1&b=2").unwrap();
        assert_eq!((next.host.as_str(), next.path.as_str()), ("release-assets.githubusercontent.com", "/x?sig=1&b=2"));
        let same = resolve(&base, "/other/path").unwrap();
        assert_eq!((same.host.as_str(), same.path.as_str()), ("github.com", "/other/path"));
        assert!(resolve(&base, "http://example.com/x").is_err(), "không rời HTTPS");
        assert!(resolve(&base, "//evil.example/x").is_err());
        assert!(resolve(&base, "relative").is_err());
    }

    #[test]
    fn than_theo_content_length() {
        let got = body(b"HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 5\r\n\r\nhello-thua", 100).unwrap();
        assert_eq!(got, b"hello");
    }

    #[test]
    fn than_chia_khuc() {
        let raw = b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n4;ext=1\r\nWiki\r\n6\r\npedia \r\nE\r\nin \r\n\r\nchunks.\r\n0\r\nX-Trailer: 1\r\n\r\n";
        assert_eq!(body(raw, 100).unwrap(), b"Wikipedia in \r\n\r\nchunks.");
    }

    #[test]
    fn than_toi_khi_dong() {
        assert_eq!(body(b"HTTP/1.0 200 OK\r\n\r\nabc", 100).unwrap(), b"abc");
    }

    #[test]
    fn than_bi_cat_hoac_qua_lon() {
        assert!(matches!(body(b"HTTP/1.1 200 OK\r\nContent-Length: 10\r\n\r\nabc", 100), Err(HttpError::Protocol(_))));
        assert!(matches!(body(b"HTTP/1.1 200 OK\r\nContent-Length: 10\r\n\r\n0123456789", 5), Err(HttpError::TooLarge)));
        assert!(matches!(body(b"HTTP/1.1 200 OK\r\n\r\n0123456789", 5), Err(HttpError::TooLarge)));
        assert!(matches!(body(b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\nzz\r\n", 100), Err(HttpError::Protocol(_))));
        assert!(matches!(body(b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nab", 100), Err(HttpError::Protocol(_))));
    }

    #[test]
    fn phan_dau() {
        let mut r = Cursor::new(b"HTTP/1.1 302 Found\r\nLocation: https://a.example/b\r\nX-Empty:\r\n\r\n".to_vec());
        let head = read_head(&mut r).unwrap();
        assert_eq!(head.status, 302);
        assert_eq!(head.header("location"), Some("https://a.example/b"));
        assert_eq!(head.header("x-empty"), Some(""));
        assert!(read_head(&mut Cursor::new(b"SSH-2.0-OpenSSH\r\n\r\n".to_vec())).is_err());
        assert!(read_head(&mut Cursor::new(b"".to_vec())).is_err());
        let long = format!("HTTP/1.1 200 OK\r\nX: {}\r\n\r\n", "a".repeat(MAX_HEAD));
        assert!(read_head(&mut Cursor::new(long.into_bytes())).is_err());
    }
}

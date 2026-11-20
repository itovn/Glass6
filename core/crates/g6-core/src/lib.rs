//! Lõi Glass 6 — không phụ thuộc mạng, không phụ thuộc iOS: chạy thử được trên PC.
//!
//! - [`bitmap`], [`blur`], [`shape`], [`glass`]: dựng vật liệu kính ra điểm ảnh BGRA nhân sẵn alpha.
//! - [`icon`]: cắt ảnh biểu tượng app theo hình bo góc liên tục, thêm viền sáng.
//! - [`theme`]: số đo và màu của từng bề mặt theo chế độ sáng / tối.
//! - [`config`]: lược đồ cấu hình, giá trị mặc định, kiểm và kẹp giá trị.
//! - [`guard`]: quét xung đột, đếm sập.
//! - [`services`]: danh mục dịch vụ hệ thống được phép tắt / bật, hồ sơ dựng sẵn.
//! - [`assist`]: nút AssistiveTouch của Glass 6 — danh mục chức năng gán được và cấu hình.
//! - [`apps`]: chính sách theo từng app cho phần nạp vào app (app nào được đổi thanh / bảng / nút).
//! - [`perf`]: hiệu suất hệ thống (CPU, RAM, đĩa, mạng) — tính từ số đếm thô và dựng chuỗi hiển thị.
//! - [`api`]: cửa JSON cho vỏ ObjC (`g6_call`).
//!
//! Bản cho máy iOS dựng với `panic = abort`: một lần panic là SpringBoard sập. Mã ở đây vì thế không đánh chỉ số ngoài
//! tầm, không `unwrap` trên dữ liệu từ ngoài; kích thước vô lý thì trả lỗi.

pub mod api;
pub mod apps;
pub mod assist;
pub mod bitmap;
pub mod blur;
pub mod config;
pub mod glass;
pub mod guard;
pub mod icon;
pub mod perf;
pub mod services;
pub mod shape;
pub mod theme;

/// Số bản của lõi (lấy từ Cargo) — vỏ ObjC ghi vào nhật ký lúc nạp.
pub const VERSION: &str = env!("CARGO_PKG_VERSION");

/// Cạnh dài nhất của một ảnh lõi chịu dựng (điểm ảnh). Màn iPad @2x là 2048; quá số này là dữ liệu hỏng.
pub const MAX_SIDE: u32 = 4096;

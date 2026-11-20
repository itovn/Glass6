// Cầu nối sang lõi Rust (/usr/lib/libglass6core.dylib — core/crates/g6-ffi). Nạp bằng dlopen, tra từng hàm bằng dlsym:
// thiếu thư viện hay thiếu hàm thì G6CoreLoad trả NO và Glass 6 tự tắt, tiến trình chủ không bị ảnh hưởng.
#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

// Ảnh BGRA 8 bit nhân sẵn alpha do bên gọi giữ (cùng bố cục với G6Image của g6-ffi)
typedef struct {
    const uint8_t *data;
    uint32_t w, h, stride;
} G6Image;

// Điểm ảnh tấm kính → điểm ảnh ảnh nền: X = a·x + c·y + tx, Y = b·x + d·y + ty (như CGAffineTransform, số thực 32 bit)
typedef struct {
    float a, b, c, d, tx, ty;
} G6Affine;

// Nạp lõi (gọi nhiều lần được). NO = không dùng được lõi.
BOOL G6CoreLoad(void);
// Số bản của lõi; nil nếu chưa nạp được.
NSString *G6CoreVersion(void);
// Lệnh điều khiển JSON (xem docs/FFI.md). nil nếu lõi chưa nạp / lệnh không đổi được sang JSON.
NSDictionary *G6CoreCall(NSDictionary *cmd);

// Các hàm điểm ảnh: trả 0 khi được, số âm khi lỗi (G6_ERR_* của g6-ffi), -100 nếu lõi chưa nạp.
// `pre`: ảnh gốc đã thu nhỏ sẵn bấy nhiêu lần so với màn hình (1 = cỡ màn hình).
int G6CoreBackdropSize(uint32_t srcW, uint32_t srcH, float scale, BOOL fast, uint32_t pre, uint32_t *outW, uint32_t *outH);
int G6CoreBackdropPrepare(const G6Image *src, float scale, BOOL fast, uint32_t pre, uint8_t *out, uint32_t outW,
                          uint32_t outH, uint32_t outStride);
int G6CoreGlassRender(const char *surface, uint32_t w, uint32_t h, float scale, BOOL dark, const G6Image *backdrop,
                      const G6Affine *place, uint8_t *out, uint32_t outStride);
int G6CoreShadowRender(const char *surface, uint32_t w, uint32_t h, float scale, BOOL dark, uint8_t *out, uint32_t outW,
                       uint32_t outH, uint32_t outStride);
// Ảnh gốc của app đã vẽ kín `w × h` trong `pixels` → cắt theo hình biểu tượng + viền sáng, tại chỗ. Gọi được từ mọi luồng.
int G6CoreIconRender(uint8_t *pixels, uint32_t w, uint32_t h, uint32_t stride, float scale, BOOL dark);

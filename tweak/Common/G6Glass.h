// Dựng ảnh kính từ lõi Rust thành UIImage. Xem docs/THIET-KE.md mục 2.
//
// Mọi ảnh nền (G6Backdrop) đều theo hệ toạ độ khung hình của màn hình (dọc, gốc ở góc trên trái khi máy đứng) — cùng hệ
// với toạ độ cửa sổ của iOS 6. Tấm kính nằm trong view đang xoay (iPad nằm ngang) vẫn lấy đúng vùng nền nhờ phép biến
// đổi view → màn hình.
#import <UIKit/UIKit.h>

@interface G6Backdrop : NSObject
// Điểm ảnh BGRA đã thu nhỏ + làm mờ + tăng bão hoà
@property (nonatomic, readonly) NSData *pixels;
@property (nonatomic, readonly) uint32_t width, height;
// Một điểm ảnh nền ứng bao nhiêu điểm ảnh màn hình
@property (nonatomic, readonly) CGFloat factor;

// Chụp màn hình đang hiện (CARenderServerRenderDisplay) rồi chuẩn bị làm nền. Gọi TRƯỚC khi hiện tấm kính.
// fast = YES: thu nhỏ 1/8 (mở tấm kính trên app); NO: 1/4 (mịn hơn).
+ (instancetype)backdropWithScreen:(BOOL)fast;
// Từ điểm ảnh BGRA cỡ màn hình (vd hình nền đã vẽ vào hệ toạ độ khung hình).
+ (instancetype)backdropWithPixels:(const uint8_t *)data width:(uint32_t)w height:(uint32_t)h stride:(uint32_t)stride fast:(BOOL)fast;
// Như trên cho ảnh đã vẽ sẵn ở cỡ nhỏ hơn màn hình `prescale` lần (vd 4: ảnh 192×256 của màn 768×1024) — nhanh hơn nhiều so
// với vẽ đủ cỡ rồi để lõi thu nhỏ.
+ (instancetype)backdropWithPixels:(const uint8_t *)data width:(uint32_t)w height:(uint32_t)h stride:(uint32_t)stride fast:(BOOL)fast prescale:(uint32_t)prescale;
@end

// Chụp màn hình đang hiện thành ảnh đủ cỡ (hệ dọc, không trong suốt). `backdrop` ≠ NULL: trả luôn nền mờ dựng từ cùng lần chụp.
// nil nếu máy không chụp được.
UIImage *G6ScreenImage(G6Backdrop **backdrop, BOOL fast);
// Tấm kính phủ kín `view` (cỡ = bounds), nền lấy đúng vùng `view` đang che trên màn hình. backdrop = nil → kính giả.
// `view` phải đang nằm trong cửa sổ. nil nếu lõi lỗi.
UIImage *G6GlassImageForView(NSString *surface, UIView *view, BOOL dark, G6Backdrop *backdrop);

// Như trên cho một vùng `rect` (toạ độ của `view`) — vd chỗ một bảng SẼ nằm khi trượt xong, tính theo view cha đứng yên.
UIImage *G6GlassImageForRect(NSString *surface, UIView *view, CGRect rect, BOOL dark, G6Backdrop *backdrop);

// Dựng tấm kính cho vùng `rect` của `view` thẳng vào vùng nhớ `out` của bên gọi (BGRA nhân sẵn alpha, mỗi hàng `stride`
// byte, đủ chỗ cho rect.size × tỉ lệ màn hình) — khi tấm kính chỉ là một phần của ảnh lớn hơn. Trả 0 khi được.
int G6GlassRenderForRect(NSString *surface, UIView *view, CGRect rect, BOOL dark, G6Backdrop *backdrop, uint8_t *out, uint32_t stride);

// Tấm kính cỡ `size` điểm; `toScreen` đưa toạ độ điểm của tấm kính sang toạ độ điểm màn hình (khung hình dọc).
UIImage *G6GlassImage(NSString *surface, CGSize size, BOOL dark, G6Backdrop *backdrop, CGAffineTransform toScreen);

// Bóng đổ của tấm kính cỡ `size`: đặt vào khung của tấm kính nới ra `*margin` điểm mỗi phía. Ảnh là ảnh 9 mảnh
// (dựng ở cỡ nhỏ nhất giữ nguyên bốn góc, phần giữa kéo giãn) và được nhớ lại — lần sau cùng loại không tốn gì.
UIImage *G6ShadowImage(NSString *surface, CGSize size, BOOL dark, CGFloat *margin);

// Điểm ảnh BGRA nhân sẵn alpha (`w × h`, mỗi hàng `w × 4` byte) → UIImage. Ảnh giữ `pixels`, không chép. Gọi được từ mọi luồng.
UIImage *G6ImageFromPixels(NSData *pixels, uint32_t w, uint32_t h, CGFloat scale);
// Như trên, điểm ảnh nằm sau `offset` byte đầu của `pixels` (tệp đệm có đầu tệp).
UIImage *G6ImageFromPixelsAt(NSData *pixels, size_t offset, uint32_t w, uint32_t h, CGFloat scale);

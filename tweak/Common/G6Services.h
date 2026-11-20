// Cầu nối sang g6svc — công cụ quyền root tắt / bật dịch vụ hệ thống trong danh mục (svc/g6svc.c, docs/THIET-KE.md mục 7).
// Dùng chung cho SpringBoard (xác nhận «máy khởi động ổn») và bảng Cài đặt (màn «Dịch vụ hệ thống»).
#import <Foundation/Foundation.h>

#define G6_SVC_TOOL "/usr/libexec/glass6/g6svc"
// g6svc tạo tệp này khi có lần đổi dịch vụ chưa được xác nhận (đọc được bằng quyền mobile)
#define G6_SVC_PENDING "/var/db/glass6/pending"

// Chạy g6svc với các tham số (NSString) rồi chờ xong. Trả mã thoát, −1 nếu không chạy được. `output` khác NULL thì nhận
// đầu ra chuẩn. Chặn luồng gọi (tới vài giây khi tắt nhiều dịch vụ) — đừng gọi trên luồng chính của SpringBoard.
int G6SvcRun(NSArray *args, NSString **output);

// Trạng thái thật của máy: @{ @"disabled": @{ <mã>: @YES / @NO }, @"pending": @(số lần khởi động) — chỉ có khi đang chờ xác
// nhận, @"reverted": @YES — chỉ có khi bộ gác vừa tự hoàn tác }. nil nếu không chạy được g6svc.
NSDictionary *G6SvcStatus(void);

// Bảng Cài đặt gửi thông báo Darwin này sau mỗi lần đổi dịch vụ xong (SpringBoard xét lại những việc đi theo, vd dọn dấu nhắc
// cập nhật khi cập nhật iOS vừa bị chặn)
#define G6_SVC_NOTE "vn.glass6/svc"

// Mục «cập nhật iOS qua mạng» của danh mục (data/services.tsv) — được đối xử riêng: có nhóm riêng trong Cài đặt, hồ sơ không
// đụng tới, SpringBoard dọn dấu nhắc theo nó. Xem docs/DECISIONS.md D34.
#define G6_SVC_UPDATE_ID @"iosupdate"

typedef enum {
    G6UpdateOpen = 0,     // máy vẫn kiểm tra / tải bản iOS mới được (hoặc không biết: không đọc được trạng thái)
    G6UpdateBlocked = 1,  // Glass 6 đã tắt dịch vụ cập nhật (bật lại được)
    G6UpdateRemoved = 2,  // máy không còn tệp việc nào của dịch vụ cập nhật — kiểu chặn cũ là gỡ tệp; Glass 6 không bật lại được
} G6UpdateBlock;

// `status` = kết quả của G6SvcStatus() (nil → G6UpdateOpen).
G6UpdateBlock G6SvcUpdateBlock(NSDictionary *status);

// SpringBoard gọi một lần lúc nạp: 60 giây sau khi SpringBoard mở xong, nếu có lần đổi dịch vụ đang chờ thì gọi
// «g6svc confirm» (g6svc chỉ xác nhận khi máy đã khởi động lại ít nhất một lần kể từ lần đổi).
void G6SvcScheduleConfirm(void);

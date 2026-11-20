// Dải hiệu suất hệ thống (CPU, RAM, đĩa, mạng) trên màn hình chính — thành phần `perf` (khoá cấu hình `featPerf`).
// Xem G6Perf.m.
#import <Foundation/Foundation.h>

void G6PerfInstall(void);
// Bản thử: mô tả trạng thái hiện tại (khung, đang đo / đứng, số đo gần nhất, chi phí mỗi lần đo).
NSString *G6PerfDebugState(void);

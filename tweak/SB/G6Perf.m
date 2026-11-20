// Dải hiệu suất hệ thống trên màn hình chính: CPU, RAM, đĩa, mạng.
//
// Một viên kính dài và thấp trên màn hình chính:
//
//      CPU ▬▬▬ 23%  │  RAM ▬▬▬ 148 MB  │  Đĩa ▬▬▬ 51,0 GB  │  ↓ 12 KB/s  ↑ 3 KB/s
//
// Hai chỗ đặt (`perfPosition`):
//   - trên cùng (mặc định; anh chọn 19/11/2026): ngang hàng thanh trạng thái, ở giữa — chỗ của đồng hồ sau khi G6StatusBar
//     dời giờ sang trái. Cao bằng thanh trạng thái (20 điểm). Dải nằm trong màn hình chính, DƯỚI cửa sổ thanh trạng thái (thanh
//     này của Glass 6 trong suốt) nên chỉ có ở màn hình chính, đúng ý. Bề rộng chỗ trống giữa hai cụm mục của thanh trạng thái
//     đo lúc chạy: không đủ cho bản đầy đủ thì dùng bản gọn (bỏ ba thanh mức); vẫn không đủ, hoặc giờ không nằm bên trái,
//     thì xuống chỗ thứ hai;
//   - dưới thanh trạng thái: trong dải trống phía trên hàng biểu tượng đầu tiên, cao 28 điểm.
// iPhone (anh yêu cầu 19/11/2026: «ở khoảng giữa giờ và icon mạng đang có một khoảng trống, sắp xếp phần hiệu suất hệ thống vào
// khoảng này»): chỉ một chỗ — viên kính THU GỌN cao 18 điểm nằm giữa khoảng trống của thanh trạng thái (giờ bên trái, cụm sóng
// / Wi-Fi / pin bên phải; khoảng trống chừng 143–158 điểm, lệch trái so với tâm màn hình nên viên kính canh giữa KHOẢNG TRỐNG
// chứ không canh giữa màn hình). Hai kiểu (`perfStyle`):
//
//      CPU   RAM    ↓ 12K                hai hàng (mặc định): nhãn nhỏ trên, số dưới; cột mạng xếp nhận trên – gửi dưới
//      23%   148M   ↑ 3K
//
//      CPU 23%   RAM 148M                một hàng: cùng dòng chữ với giờ và phần trăm pin
//
//     Viên kính giãn cho vừa khít khoảng trống (cách hai cụm mục hai bên một khoảng bằng nhau; chỗ thừa chia đều vào khe giữa
//     các cột, có giới hạn — thừa nhiều quá thì canh giữa). Mỗi cột rộng cố định, chữ canh giữa cột → số đổi thì bố cục không
//     xô lệch mà vẫn cân. Thanh trạng thái có thêm biểu tượng (báo thức, định vị, «Không làm phiền»…) làm chỗ trống hẹp lại →
//     khe hẹp lại, rồi bỏ cột mạng, rồi chỉ còn CPU; vẫn không vừa thì ẩn. Số dùng bản ngắn do lõi dựng (`ram_short`,
//     `down_short`, `up_short`).
//
//   - CPU: phần thời gian các nhân bận trong khoảng giữa hai lần đo.
//   - RAM: số = còn dùng được (trang trống + trang không hoạt động — thứ iOS lấy lại ngay khi cần); thanh = phần còn lại
//     của tổng bộ nhớ.
//   - Đĩa: phân vùng dữ liệu (/private/var — nơi chứa app, ảnh, nhạc); thanh = phần đã dùng, số = còn trống.
//   - Mạng: tốc độ nhận ↓ / gửi ↑ qua Wi-Fi và mạng di động.
//
// Phân vai: vỏ ObjC chỉ đọc số đếm thô của nhân (host_statistics, statfs, getifaddrs); lõi Rust (`perf.reading`) tính phần
// trăm, tốc độ, dựng sẵn chuỗi hiển thị — phép tính thử được trên PC (core/crates/g6-core/src/perf.rs).
//
// SpringBoard iOS 6 (iPad), tra trên máy 19/11/2026:
//   SBIconContentView (-[SBIconController contentView])            ← dải kính gắn vào đây, đứng yên khi lật trang
//     SBIconScrollView (-[SBIconController scrollView], y = 20)    trang 0 là Tìm kiếm, các trang biểu tượng từ trang 1
//       SBIconListView …   -topIconInset = khoảng từ mép trên tới hàng biểu tượng đầu (máy ngang: 40)
//     UIView (dockContainerView)
//
// Chỉ đo khi có người nhìn: dải kính đang trong cửa sổ (SpringBoard gỡ hẳn màn hình chính khỏi cửa sổ lúc mở app), máy không
// khoá, màn hình không tắt. Lúc không ai nhìn thì không có đồng hồ hẹn nào chạy.
//   - Sang trang Tìm kiếm: dải mờ dần rồi ẩn (kẻo đè lên ô tìm kiếm).
//   - Mở thư mục: ẩn (iOS 6 xẻ đôi màn hình chính và trượt hai nửa đi — dải kính đứng yên đè lên trông sai).
// Dải kính không nhận chạm.
#import "G6Perf.h"

#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import <ifaddrs.h>
#import <mach/mach.h>
#import <net/if.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <sys/mount.h>
#import <sys/param.h>
#import <sys/socket.h>

#import "G6Core.h"
#import "G6Device.h"
#import "G6Font.h"
#import "G6Glass.h"
#import "G6Hook.h"
#import "G6Lang.h"
#import "G6Log.h"
#import "G6Prefs.h"
#import "G6Screen.h"
#import "G6StatusBar.h"
#import "G6Wallpaper.h"

// ---- Số đo của dải kính (điểm) ----
// Chỗ «dưới thanh trạng thái»
static const CGFloat kHeight = 28;
// Chỗ «trên cùng»: cao bằng thanh trạng thái, cách mép trên màn hình 1 điểm; cách cụm mục hai bên của thanh ít nhất kTopMargin
static const CGFloat kTopHeight = 20, kTopY = 1, kTopMargin = 12;
// Lề trái / phải bên trong viên kính
static const CGFloat kPadX = 16;
static const CGFloat kBarWidth = 34, kBarHeight = 4;
// Giữa nhãn / thanh / số của một mục
static const CGFloat kGap = 6;
// Hai bên nét ngăn giữa các mục
static const CGFloat kSepGap = 10;
// Mũi tên nhận / gửi
static const CGFloat kArrowWidth = 8, kArrowGap = 4;
// Dải trống phải cao hơn viên kính ít nhất chừng này mới đặt
static const CGFloat kMinSpare = 4;
// Viên kính nằm lệch lên phía thanh trạng thái: khoảng hở phía trên chiếm chừng này phần của chỗ thừa (hàng biểu tượng bên
// dưới «nặng» hơn dòng chữ nhỏ của thanh trạng thái — đặt chính giữa thì trông như sát biểu tượng)
static const CGFloat kTopShare = 0.25;

// Bản thu gọn của iPhone: viên kính cao kMiniHeight, cách cụm mục hai bên của thanh trạng thái ít nhất kMiniMargin
// (mục giờ còn chừng 1,5 điểm trống bên phải chữ nên lề trái lấy hẹp hơn một chút — nhìn bằng mắt thì hai bên bằng nhau)
static const CGFloat kMiniHeight = 18, kMiniMarginLeft = 7, kMiniMarginRight = 8;
// Chỗ thừa chia vào khe giữa các cột: mỗi khe nới tối đa chừng này
static const CGFloat kMiniStretch = 8;
// Mũi tên nhận / gửi của cột mạng và khe tới số; khe giữa nhãn và số ở kiểu một hàng
static const CGFloat kMiniArrow = 5, kMiniArrowGap = 2, kMiniLabelGap = 3;

// Màn hình chính vừa hiện lại: lần đo đầu cách mốc chừng này giây — đủ để CPU / mạng có số thật mà không phải chờ hết một nhịp
static const NSTimeInterval kFirstDelay = 0.7;
// Đĩa đổi chậm: đọc lại sau mỗi chừng này lần đo
static const int kDiskEvery = 15;

// ---- Đọc số đếm thô ----

typedef struct {
    double t, cpuBusy, cpuTotal, memFree, memTotal, diskFree, diskTotal, netIn, netOut;
} G6PerfSample;

static double gDiskFree, gDiskTotal;
static int gDiskAge;

static void G6PerfRead(G6PerfSample *s) {
    // mach_host_self() mỗi lần gọi thêm một lượt giữ cổng → lấy một lần
    static host_t host;
    static double pageSize, memTotal;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        host = mach_host_self();
        vm_size_t page = 4096;
        if (host_page_size(host, &page) != KERN_SUCCESS || page == 0) page = 4096;
        pageSize = page;
        memTotal = (double)[NSProcessInfo processInfo].physicalMemory;
    });
    memset(s, 0, sizeof(*s));
    s->t = G6NowMs();

    // CPU: tích tắc cộng dồn của mọi nhân từ lúc khởi động
    host_cpu_load_info_data_t cpu;
    mach_msg_type_number_t count = HOST_CPU_LOAD_INFO_COUNT;
    if (host_statistics(host, HOST_CPU_LOAD_INFO, (host_info_t)&cpu, &count) == KERN_SUCCESS) {
        s->cpuBusy = (double)cpu.cpu_ticks[CPU_STATE_USER] + cpu.cpu_ticks[CPU_STATE_SYSTEM] + cpu.cpu_ticks[CPU_STATE_NICE];
        s->cpuTotal = s->cpuBusy + cpu.cpu_ticks[CPU_STATE_IDLE];
    }

    // RAM: trang trống + trang không hoạt động = còn dùng được
    vm_statistics_data_t vm;
    count = HOST_VM_INFO_COUNT;
    if (host_statistics(host, HOST_VM_INFO, (host_info_t)&vm, &count) == KERN_SUCCESS) {
        s->memFree = ((double)vm.free_count + vm.inactive_count) * pageSize;
    }
    s->memTotal = memTotal;

    // Đĩa: phân vùng dữ liệu
    if (gDiskAge <= 0 || gDiskTotal <= 0) {
        struct statfs fs;
        if (statfs("/private/var", &fs) == 0) {
            gDiskFree = (double)fs.f_bavail * fs.f_bsize;
            gDiskTotal = (double)fs.f_blocks * fs.f_bsize;
        }
        gDiskAge = kDiskEvery;
    }
    gDiskAge--;
    s->diskFree = gDiskFree;
    s->diskTotal = gDiskTotal;

    // Mạng: byte cộng dồn của Wi-Fi (en*) và mạng di động (pdp_ip*). Số đếm của nhân là 32 bit — lõi lo chuyện quay vòng.
    struct ifaddrs *list = NULL;
    if (getifaddrs(&list) == 0) {
        for (struct ifaddrs *a = list; a; a = a->ifa_next) {
            if (!a->ifa_addr || a->ifa_addr->sa_family != AF_LINK || !a->ifa_data || !a->ifa_name) continue;
            if (strncmp(a->ifa_name, "en", 2) != 0 && strncmp(a->ifa_name, "pdp_ip", 6) != 0) continue;
            const struct if_data *d = (const struct if_data *)a->ifa_data;
            s->netIn += d->ifi_ibytes;
            s->netOut += d->ifi_obytes;
        }
        freeifaddrs(list);
    }
}

static NSDictionary *G6PerfDict(const G6PerfSample *s) {
    return @{
        @"t" : @(s->t),
        @"cpuBusy" : @(s->cpuBusy),
        @"cpuTotal" : @(s->cpuTotal),
        @"memFree" : @(s->memFree),
        @"memTotal" : @(s->memTotal),
        @"diskFree" : @(s->diskFree),
        @"diskTotal" : @(s->diskTotal),
        @"netIn" : @(s->netIn),
        @"netOut" : @(s->netOut),
    };
}

// ---- Trạng thái (chỉ dùng ở luồng chính) ----

@class G6PerfView, G6PerfContentView;

static BOOL gActive;
static G6PerfView *gView;
static UIImageView *gGlass, *gShadow;
static G6PerfContentView *gContent;
static BOOL gSyncPending;
// Kết quả gần nhất của lõi (`reading` của lệnh perf.reading) và thứ đang vẽ trên màn hình
static NSDictionary *gReading;
static NSString *gShownSignature;
static BOOL gDark;
// Đo
static NSTimer *gTimer;
static NSTimeInterval gTimerInterval;
static G6PerfSample gPrev;
static unsigned gTicks;
static double gTickMs;
// Chỗ đang đặt: trên cùng hay dưới thanh trạng thái; bản gọn (không có ba thanh mức) hay đầy đủ
static BOOL gTop, gCompact;
// Bản thu gọn của iPhone đang dùng (valid = NO: không phải bản thu gọn)
typedef struct {
    BOOL valid;
    int style;     // 0 = hai hàng (CPU, RAM, mạng), 1 = một hàng (CPU, RAM)
    int columns;   // số cột đang hiện
    CGFloat width; // bề rộng viên kính
    CGFloat x[3];  // mép trái từng cột
    CGFloat w[3];  // bề rộng từng cột (chữ canh giữa cột)
} G6PerfMini;
static G6PerfMini gMini;
// Ẩn / hiện
static BOOL gFolderOpen;
static BOOL gNoRoomLogged;
// Trạng thái của lần dựng kính gần nhất — không đổi thì không dựng lại
static CGRect gDrawnFrame;
static NSUInteger gDrawnGeneration;
static int gDrawnOrientation = -1;
static BOOL gDrawnDark, gDrawnWithBackdrop;

static void G6PerfScheduleSync(void);
static void G6PerfTick(void);

// ---- Bố cục chữ ----

typedef struct {
    CGFloat width;
    CGFloat labelX[3], barX[3], valueX[3], sepX[3];
    CGFloat downArrowX, downX, upArrowX, upX;
} G6PerfLayout;

static UIFont *G6PerfLabelFont(void) {
    static UIFont *font;
    if (!font) font = G6Font(G6FontMedium, 11);
    return font;
}

static UIFont *G6PerfValueFont(void) {
    static UIFont *font;
    if (!font) font = G6Font(G6FontSemiBold, 12);
    return font;
}

static NSArray *G6PerfLabels(void) {
    return @[@"CPU", @"RAM", G6L(@"Đĩa")];
}

static CGFloat G6PerfTextWidth(NSArray *samples, UIFont *font) {
    CGFloat w = 0;
    for (NSString *s in samples) w = MAX(w, [s sizeWithFont:font].width);
    return ceil(w);
}

// Vị trí từng phần trong viên kính. Mỗi số có một ô rộng cố định (đủ cho chuỗi dài nhất có thể gặp) → số đổi thì các mục
// khác không xô lệch. compact = bản gọn: bỏ ba thanh mức.
static const G6PerfLayout *G6PerfMetrics(BOOL compact) {
    static G6PerfLayout layouts[2];
    static BOOL ready[2];
    int which = compact ? 1 : 0;
    G6PerfLayout *m = &layouts[which];
    if (ready[which]) return m;
    UIFont *labelFont = G6PerfLabelFont(), *valueFont = G6PerfValueFont();
    NSArray *labels = G6PerfLabels();
    NSArray *widest = @[@[@"100%"], @[@"888 MB", @"8,8 GB"], @[@"88,8 GB", @"888 MB"]];
    CGFloat x = kPadX;
    for (int i = 0; i < 3; i++) {
        m->labelX[i] = x;
        x += G6PerfTextWidth(@[labels[i]], labelFont) + kGap;
        m->barX[i] = x;
        if (!compact) x += kBarWidth + kGap;
        m->valueX[i] = x;
        x += G6PerfTextWidth(widest[i], valueFont) + kSepGap;
        m->sepX[i] = x;
        x += 1 + kSepGap;
    }
    // iPad đời này không qua nổi 10 MB/s: không chừa chỗ cho «88,8 MB/s»
    CGFloat rate = G6PerfTextWidth(@[@"888 KB/s", @"8,8 MB/s"], valueFont);
    m->downArrowX = x;
    x += kArrowWidth + kArrowGap;
    m->downX = x;
    x += rate + kGap;
    m->upArrowX = x;
    x += kArrowWidth + kArrowGap;
    m->upX = x;
    x += rate;
    m->width = ceil(x + kPadX);
    ready[which] = YES;
    return m;
}

// ---- Bố cục thu gọn (iPhone) ----

// 0 nhãn + 1 số + 2 mạng của kiểu hai hàng; 3 nhãn + 4 số của kiểu một hàng
static UIFont *G6PerfMiniFont(int which) {
    static UIFont *fonts[5];
    static const CGFloat sizes[5] = {6.5, 9.5, 8, 8.5, 10.5};
    if (!fonts[which]) fonts[which] = G6Font(which == 3 ? G6FontMedium : G6FontSemiBold, sizes[which]);
    return fonts[which];
}

// Bố cục thu gọn kiểu `style` vừa với bề rộng `room`: không vừa thì bớt dần (khe hẹp lại → bỏ cột mạng → chỉ còn CPU).
// Mỗi cột rộng cố định theo chuỗi dài nhất có thể gặp → số đổi thì không xô lệch. NO = không có chỗ.
static BOOL G6PerfMiniFit(int style, CGFloat room, G6PerfMini *out) {
    static CGFloat cols[2][3];
    static BOOL measured;
    if (!measured) {
        // Cột CPU chừa chỗ cho hai chữ số («100%» hiếm gặp, lấn mỗi bên vài điểm vào khe cũng không sao)
        NSArray *cpu = @[@"88%"], *ram = @[@"888M", @"8,8G"];
        cols[0][0] = MAX(G6PerfTextWidth(@[@"CPU"], G6PerfMiniFont(0)), G6PerfTextWidth(cpu, G6PerfMiniFont(1)));
        cols[0][1] = MAX(G6PerfTextWidth(@[@"RAM"], G6PerfMiniFont(0)), G6PerfTextWidth(ram, G6PerfMiniFont(1)));
        cols[0][2] = kMiniArrow + kMiniArrowGap + G6PerfTextWidth(@[@"888K", @"8,8M", @"88M"], G6PerfMiniFont(2));
        cols[1][0] = G6PerfTextWidth(@[@"CPU"], G6PerfMiniFont(3)) + kMiniLabelGap + G6PerfTextWidth(cpu, G6PerfMiniFont(4));
        cols[1][1] = G6PerfTextWidth(@[@"RAM"], G6PerfMiniFont(3)) + kMiniLabelGap + G6PerfTextWidth(ram, G6PerfMiniFont(4));
        measured = YES;
    }
    // {số cột, khe giữa các cột, lề trong viên kính}; số cột 0 = hết phương án
    static const struct {
        int columns;
        CGFloat gap, pad;
    } tries[2][5] = {
        {{3, 10, 10}, {3, 7, 8}, {2, 10, 10}, {2, 7, 8}, {1, 0, 9}},
        {{2, 10, 10}, {2, 7, 8}, {1, 0, 9}, {0, 0, 0}, {0, 0, 0}},
    };
    style = style ? 1 : 0;
    for (int i = 0; i < 5 && tries[style][i].columns > 0; i++) {
        int n = tries[style][i].columns;
        CGFloat gap = tries[style][i].gap, pad = tries[style][i].pad, natural = 2 * pad + gap * (n - 1);
        for (int c = 0; c < n; c++) natural += cols[style][c];
        if (natural > room) continue;
        // Chỗ thừa: chia đều vào các khe, hai lề mỗi bên nhận một nửa phần của một khe
        CGFloat unit = MIN((room - natural) / n, kMiniStretch);
        gap += unit;
        pad += unit / 2;
        G6PerfMini m;
        memset(&m, 0, sizeof(m));
        m.valid = YES;
        m.style = style;
        m.columns = n;
        CGFloat x = pad;
        for (int c = 0; c < n; c++) {
            m.x[c] = round(x * 2) / 2;
            m.w[c] = cols[style][c];
            x += cols[style][c] + (c + 1 < n ? gap : 0);
        }
        m.width = floor(x + pad);
        *out = m;
        return YES;
    }
    return NO;
}

// Màu thanh theo mức: xanh → cam (từ 75%) → đỏ (từ 90%)
static UIColor *G6PerfLevelColor(CGFloat f) {
    if (f >= 0.90) return [UIColor colorWithRed:1.0 green:0.23 blue:0.19 alpha:1];
    if (f >= 0.75) return [UIColor colorWithRed:1.0 green:0.58 blue:0.0 alpha:1];
    return [UIColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:1];
}

// Bề rộng phần tô của thanh (điểm ảnh nguyên) ứng với tỉ lệ `f`
static CGFloat G6PerfBarFill(CGFloat f) {
    if (!(f > 0)) return 0;
    return MAX(kBarHeight, round(kBarWidth * MIN(f, 1)));
}

// ---- View ----

@interface G6PerfContentView : UIView
@end

@implementation G6PerfContentView

// Mũi tên thẳng đứng, tâm ngang ở `cx`, trong view cao `height`; down = chỉ xuống
static void G6PerfDrawArrow(CGContextRef ctx, CGFloat cx, CGFloat height, BOOL down) {
    CGFloat top = floor(height / 2) - 5, bottom = floor(height / 2) + 5, head = 3.5;
    CGFloat tip = down ? bottom : top, tail = down ? top : bottom, back = down ? bottom - head : top + head;
    CGContextSetLineWidth(ctx, 1.5);
    CGContextSetLineCap(ctx, kCGLineCapRound);
    CGContextSetLineJoin(ctx, kCGLineJoinRound);
    CGContextMoveToPoint(ctx, cx, tail);
    CGContextAddLineToPoint(ctx, cx, tip);
    CGContextMoveToPoint(ctx, cx - head, back);
    CGContextAddLineToPoint(ctx, cx, tip);
    CGContextAddLineToPoint(ctx, cx + head, back);
    CGContextStrokePath(ctx);
}

// Vẽ chữ sao cho tâm của chữ hoa / chữ số rơi vào `cy` (làm tròn tới nửa điểm — máy 2x)
static void G6PerfDrawCentered(NSString *s, CGFloat x, CGFloat cy, UIFont *font) {
    CGFloat y = cy - font.ascender + font.capHeight / 2;
    [s drawAtPoint:CGPointMake(x, round(y * 2) / 2) withFont:font];
}

// Mũi tên nhỏ của cột mạng: tâm (cx, cy), cao `h`
static void G6PerfDrawMiniArrow(CGContextRef ctx, CGFloat cx, CGFloat cy, BOOL down) {
    CGFloat h = 5.5, head = 1.9, top = cy - h / 2, bottom = cy + h / 2;
    CGFloat tip = down ? bottom : top, tail = down ? top : bottom, back = down ? bottom - head : top + head;
    CGContextSetLineWidth(ctx, 1);
    CGContextSetLineCap(ctx, kCGLineCapRound);
    CGContextSetLineJoin(ctx, kCGLineJoinRound);
    CGContextMoveToPoint(ctx, cx, tail);
    CGContextAddLineToPoint(ctx, cx, tip);
    CGContextMoveToPoint(ctx, cx - head, back);
    CGContextAddLineToPoint(ctx, cx, tip);
    CGContextAddLineToPoint(ctx, cx + head, back);
    CGContextStrokePath(ctx);
}

// Bản thu gọn của iPhone
- (void)g6_drawMini {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGFloat mid = self.bounds.size.height / 2;
    CGFloat white = gDark ? 1.0 : 0.08;
    UIColor *text = [UIColor colorWithWhite:white alpha:1];
    UIColor *dim = [UIColor colorWithWhite:white alpha:gDark ? 0.66 : 0.62];
    NSDictionary *strings = [gReading[@"text"] isKindOfClass:[NSDictionary class]] ? gReading[@"text"] : nil;
    NSArray *labels = @[@"CPU", @"RAM"], *keys = @[@"cpu", @"ram_short"];
    int textColumns = MIN(gMini.columns, 2);
    for (int c = 0; c < textColumns; c++) {
        NSString *value = [strings[keys[c]] isKindOfClass:[NSString class]] ? G6LDecimal(strings[keys[c]]) : @"–";
        CGFloat center = gMini.x[c] + gMini.w[c] / 2;
        if (gMini.style == 0) {
            // Hai hàng: nhãn nhỏ trên, số dưới — cả hai canh giữa cột
            UIFont *labelFont = G6PerfMiniFont(0), *valueFont = G6PerfMiniFont(1);
            [dim set];
            G6PerfDrawCentered(labels[c], round((center - [labels[c] sizeWithFont:labelFont].width / 2) * 2) / 2, mid - 4.4, labelFont);
            [text set];
            G6PerfDrawCentered(value, round((center - [value sizeWithFont:valueFont].width / 2) * 2) / 2, mid + 3.4, valueFont);
        } else {
            // Một hàng: nhãn rồi số trên cùng một dòng, cả cụm canh giữa cột
            UIFont *labelFont = G6PerfMiniFont(3), *valueFont = G6PerfMiniFont(4);
            CGFloat labelWidth = ceil([labels[c] sizeWithFont:labelFont].width);
            CGFloat x = round((center - (labelWidth + kMiniLabelGap + [value sizeWithFont:valueFont].width) / 2) * 2) / 2;
            [dim set];
            G6PerfDrawCentered(labels[c], x, mid + 0.25, labelFont);
            [text set];
            G6PerfDrawCentered(value, x + labelWidth + kMiniLabelGap, mid, valueFont);
        }
    }
    if (gMini.style == 0 && gMini.columns >= 3) {
        // Cột mạng: nhận ở hàng trên, gửi ở hàng dưới; hai mũi tên thẳng hàng, cả cụm (mũi tên + số dài hơn) canh giữa cột.
        // Mũi tên sáng lên khi đang có dữ liệu đi qua.
        UIFont *font = G6PerfMiniFont(2);
        NSString *down = [strings[@"down_short"] isKindOfClass:[NSString class]] ? G6LDecimal(strings[@"down_short"]) : @"–";
        NSString *up = [strings[@"up_short"] isKindOfClass:[NSString class]] ? G6LDecimal(strings[@"up_short"]) : @"–";
        CGFloat widest = MAX([down sizeWithFont:font].width, [up sizeWithFont:font].width);
        CGFloat x = round((gMini.x[2] + (gMini.w[2] - (kMiniArrow + kMiniArrowGap + widest)) / 2) * 2) / 2;
        NSArray *rows = @[@[@"down", down, @(mid - 4.1)], @[@"up", up, @(mid + 4.0)]];
        for (NSArray *row in rows) {
            BOOL busy = [gReading[row[0]] doubleValue] >= 512;
            CGFloat cy = [row[2] floatValue];
            [(busy ? text : dim) set];
            G6PerfDrawMiniArrow(ctx, x + kMiniArrow / 2, cy, [row[0] isEqualToString:@"down"]);
            [text set];
            G6PerfDrawCentered(row[1], x + kMiniArrow + kMiniArrowGap, cy, font);
        }
    }
}

- (void)drawRect:(CGRect)rect {
    if (gMini.valid) {
        [self g6_drawMini];
        return;
    }
    const G6PerfLayout *m = G6PerfMetrics(gCompact);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGFloat height = self.bounds.size.height;
    CGFloat white = gDark ? 1.0 : 0.08;
    UIColor *text = [UIColor colorWithWhite:white alpha:1];
    UIColor *dim = [UIColor colorWithWhite:white alpha:gDark ? 0.64 : 0.60];
    UIColor *faint = [UIColor colorWithWhite:white alpha:gDark ? 0.22 : 0.16];
    UIFont *labelFont = G6PerfLabelFont(), *valueFont = G6PerfValueFont();
    CGFloat labelY = floor((height - labelFont.lineHeight) / 2), valueY = floor((height - valueFont.lineHeight) / 2);
    NSDictionary *strings = [gReading[@"text"] isKindOfClass:[NSDictionary class]] ? gReading[@"text"] : nil;
    NSArray *labels = G6PerfLabels(), *keys = @[@"cpu", @"ram", @"disk"];
    for (int i = 0; i < 3; i++) {
        [dim set];
        [labels[i] drawAtPoint:CGPointMake(m->labelX[i], labelY) withFont:labelFont];
        if (!gCompact) {
            // Thanh: rãnh mờ + phần tô theo mức
            CGRect track = CGRectMake(m->barX[i], floor((height - kBarHeight) / 2), kBarWidth, kBarHeight);
            [faint set];
            [[UIBezierPath bezierPathWithRoundedRect:track cornerRadius:kBarHeight / 2] fill];
            CGFloat f = [gReading[keys[i]] floatValue], fill = G6PerfBarFill(f);
            if (fill > 0) {
                track.size.width = fill;
                [G6PerfLevelColor(f) set];
                [[UIBezierPath bezierPathWithRoundedRect:track cornerRadius:kBarHeight / 2] fill];
            }
        }
        [text set];
        NSString *value = [strings[keys[i]] isKindOfClass:[NSString class]] ? G6LDecimal(strings[keys[i]]) : @"–";
        [value drawAtPoint:CGPointMake(m->valueX[i], valueY) withFont:valueFont];
        // Nét ngăn
        [faint set];
        CGContextFillRect(ctx, CGRectMake(m->sepX[i], floor(height / 2) - 6, 1, 12));
    }
    // Mạng: mũi tên sáng lên khi đang có dữ liệu đi qua
    NSArray *net = @[@[@"down", @(m->downArrowX), @(m->downX)], @[@"up", @(m->upArrowX), @(m->upX)]];
    for (NSArray *item in net) {
        NSString *key = item[0];
        BOOL busy = [gReading[key] doubleValue] >= 512;
        [(busy ? text : dim) set];
        G6PerfDrawArrow(ctx, [item[1] floatValue] + kArrowWidth / 2, height, [key isEqualToString:@"down"]);
        [text set];
        NSString *value = [strings[key] isKindOfClass:[NSString class]] ? G6LDecimal(strings[key]) : @"–";
        [value drawAtPoint:CGPointMake([item[2] floatValue], valueY) withFont:valueFont];
    }
}

@end

@interface G6PerfView : UIView
// Đích của đồng hồ hẹn nhịp đo
+ (void)g6_tick:(NSTimer *)timer;
@end

@implementation G6PerfView

// Vào / rời cửa sổ (về màn hình chính sau khi đóng app, mở app…): xét lại có ai nhìn không → đo / dừng
- (void)didMoveToWindow {
    [super didMoveToWindow];
    G6PerfScheduleSync();
}

+ (void)g6_tick:(NSTimer *)timer {
    G6PerfTick();
}

@end

// ---- SpringBoard ----

static id G6PerfIconController(void) {
    Class cls = objc_getClass("SBIconController");
    SEL shared = NSSelectorFromString(@"sharedInstance");
    if (!cls || ![cls respondsToSelector:shared]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(cls, shared);
}

static UIView *G6PerfViewFrom(id obj, NSString *selName) {
    SEL sel = NSSelectorFromString(selName);
    if (!obj || ![obj respondsToSelector:sel]) return nil;
    id v = ((id (*)(id, SEL))objc_msgSend)(obj, sel);
    return [v isKindOfClass:[UIView class]] ? v : nil;
}

static UIScrollView *G6PerfScrollView(void) {
    UIView *v = G6PerfViewFrom(G6PerfIconController(), @"scrollView");
    return [v isKindOfClass:[UIScrollView class]] ? (UIScrollView *)v : nil;
}

// Khoảng từ mép trên của trang tới hàng biểu tượng đầu, theo hướng máy hiện tại
static CGFloat G6PerfTopInset(UIScrollView *scroll) {
    SEL sel = NSSelectorFromString(@"topIconInset");
    UIView *list = G6PerfViewFrom(G6PerfIconController(), @"currentRootIconList");
    if (![list respondsToSelector:sel]) {
        // Đang ở trang Tìm kiếm: lấy trang biểu tượng bất kỳ
        list = nil;
        for (UIView *sub in scroll.subviews) {
            if ([sub respondsToSelector:sel]) {
                list = sub;
                break;
            }
        }
    }
    return list ? ((float (*)(id, SEL))objc_msgSend)(list, sel) : 0;
}

// Chỗ đặt dải kính trong `host` (SBIconContentView): khung + bản gọn hay đầy đủ + trên cùng hay không. NO = không có chỗ.
static BOOL G6PerfSpot(UIView *host, CGRect *frame, BOOL *compact, BOOL *top, G6PerfMini *mini) {
    UIScrollView *scroll = G6PerfScrollView();
    if (!scroll || !host) return NO;
    CGFloat hostWidth = host.bounds.size.width, mid = hostWidth / 2;
    CGFloat left = 0, right = 0;
    memset(mini, 0, sizeof(*mini));
    if (g6_device_is_phone()) {
        // iPhone: chỉ một chỗ — viên kính thu gọn canh giữa khoảng trống của thanh trạng thái (giữa giờ và cụm sóng / pin)
        if (!G6StatusBarCenterFree(&left, &right)) return NO;
        CGFloat room = right - left - kMiniMarginLeft - kMiniMarginRight;
        if (!G6PerfMiniFit([G6Config()[@"perf_style"] intValue], room, mini)) return NO;
        *frame = CGRectMake(round(left + kMiniMarginLeft + (room - mini->width) / 2), kTopY, mini->width, kMiniHeight);
        *compact = NO;
        *top = YES;
        return YES;
    }
    // 1) Trên cùng: giữa thanh trạng thái, nếu giờ đã dời sang trái và chỗ trống giữa hai cụm mục đủ rộng
    if ([G6Config()[@"perf_position"] intValue] == 0 && G6StatusBarCenterFree(&left, &right)) {
        // Dải nằm đúng tâm màn hình → chỗ dùng được = hai lần khoảng hẹp hơn tính từ tâm
        CGFloat room = 2 * (MIN(mid - left, right - mid) - kTopMargin);
        for (int c = 0; c < 2; c++) {
            CGFloat width = G6PerfMetrics(c)->width;
            if (width > room) continue;
            *frame = CGRectMake(floor(mid - width / 2), kTopY, width, kTopHeight);
            *compact = c;
            *top = YES;
            return YES;
        }
    }
    // 2) Dưới thanh trạng thái, phía trên hàng biểu tượng đầu
    CGFloat y = CGRectGetMinY([host convertRect:scroll.frame fromView:scroll.superview]);
    CGFloat inset = G6PerfTopInset(scroll), width = G6PerfMetrics(NO)->width;
    if (inset < kHeight + kMinSpare || width > hostWidth - 16) return NO;
    *frame = CGRectMake(floor(mid - width / 2), y + floor((inset - kHeight) * kTopShare), width, kHeight);
    *compact = NO;
    *top = NO;
    return YES;
}

// Đặt dải kính vào chỗ. NO = không đủ chỗ (đã ẩn).
static BOOL G6PerfPlace(void) {
    UIView *host = gView.superview;
    if (!host) return NO;
    CGRect frame = CGRectZero;
    BOOL compact = NO, top = NO;
    G6PerfMini mini;
    if (!G6PerfSpot(host, &frame, &compact, &top, &mini)) {
        gView.hidden = YES;
        if (!gNoRoomLogged) {
            gNoRoomLogged = YES;
            G6Log(@"hiệu suất: không đủ chỗ (màn hình rộng %.0f điểm, dải cần %.0f) — ẩn", host.bounds.size.width,
                  G6PerfMetrics(NO)->width);
        }
        return NO;
    }
    gView.hidden = NO;
    if (compact != gCompact || top != gTop || memcmp(&mini, &gMini, sizeof(mini)) != 0) {
        gCompact = compact;
        gTop = top;
        gMini = mini;
        [gContent setNeedsDisplay];
    }
    if (!CGRectEqualToRect(gView.frame, frame)) {
        gView.frame = frame;
        gGlass.frame = gContent.frame = gView.bounds;
    }
    return YES;
}

// Dựng lại tấm kính + bóng nếu có gì đổi (khung, sáng / tối, hình nền, hướng máy)
static void G6PerfDrawGlass(void) {
    if (!gView.window || gView.hidden) return;
    BOOL dark = G6IsDark();
    if (dark != gDark || !gShownSignature) {
        gDark = dark;
        [gContent setNeedsDisplay];
    }
    int orientation = (int)[UIApplication sharedApplication].statusBarOrientation;
    G6Backdrop *backdrop = G6WallpaperBackdrop();
    CGRect frame = gView.frame;
    if (gGlass.image && CGRectEqualToRect(frame, gDrawnFrame) && dark == gDrawnDark && G6WallpaperGeneration() == gDrawnGeneration &&
        orientation == gDrawnOrientation && (backdrop != nil) == gDrawnWithBackdrop) {
        return;
    }
    double t0 = G6NowMs();
    UIImage *glass = G6GlassImageForView(@"capsule", gGlass, dark, backdrop);
    if (!glass) {
        G6Log(@"hiệu suất: không dựng được kính");
        return;
    }
    gGlass.image = glass;
    CGFloat margin = 0;
    gShadow.image = G6ShadowImage(@"capsule", frame.size, dark, &margin);
    gShadow.frame = CGRectInset(gView.bounds, -margin, -margin);
    gDrawnFrame = frame;
    gDrawnDark = dark;
    gDrawnGeneration = G6WallpaperGeneration();
    gDrawnOrientation = orientation;
    gDrawnWithBackdrop = backdrop != nil;
    NSString *variant = gCompact ? @", bản gọn" : @"";
    if (gMini.valid) variant = [NSString stringWithFormat:@", thu gọn %@ %d cột", gMini.style ? @"một hàng" : @"hai hàng", gMini.columns];
    G6Log(@"hiệu suất: kính %.0f×%.0f tại (%.0f, %.0f) — %@%@ (%@, %@ nền) %.1f ms", frame.size.width, frame.size.height,
          frame.origin.x, frame.origin.y, gTop ? @"trên cùng" : @"dưới thanh trạng thái", variant, dark ? @"tối" : @"sáng",
          backdrop ? @"có" : @"KHÔNG", G6NowMs() - t0);
}

// Độ hiện của dải: ẩn khi thư mục mở; mờ dần khi trượt sang trang Tìm kiếm (trang 0)
static CGFloat G6PerfTargetAlpha(void) {
    if (gFolderOpen) return 0;
    UIScrollView *scroll = G6PerfScrollView();
    CGFloat w = scroll.bounds.size.width;
    if (!scroll || w <= 0) return 1;
    return MAX(0, MIN(1, (scroll.contentOffset.x - w * 0.5) / (w * 0.4)));
}

static void G6PerfUpdateAlpha(BOOL animated, NSTimeInterval delay) {
    if (!gView) return;
    CGFloat alpha = G6PerfTargetAlpha();
    if (fabs(gView.alpha - alpha) < 0.01) return;
    if (!animated) {
        gView.alpha = alpha;
        return;
    }
    [UIView animateWithDuration:0.2
                          delay:delay
                        options:UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
                         gView.alpha = alpha;
                     }
                     completion:nil];
}

// ---- Đo ----

static NSTimeInterval G6PerfInterval(void) {
    id v = G6Config()[@"perf_interval"];
    NSTimeInterval s = [v respondsToSelector:@selector(doubleValue)] ? [v doubleValue] : 2;
    return MAX(1, MIN(10, s));
}

static void G6PerfStop(void) {
    if (!gTimer) return;
    [gTimer invalidate];
    gTimer = nil;
    gTimerInterval = 0;
#if G6_DEBUG
    G6Log(@"hiệu suất: dừng đo (không ai nhìn)");
#endif
}

// Bắt đầu đo cách nhau `interval` giây. Lấy mốc ngay bây giờ: CPU và mạng tính trên khoảng từ mốc này, không phải từ lần đo
// cuối trước khi rời màn hình chính (có khi đã cách cả giờ).
static void G6PerfStart(NSTimeInterval interval) {
    [gTimer invalidate];
    G6PerfRead(&gPrev);
    gTimer = [[NSTimer alloc] initWithFireDate:[NSDate dateWithTimeIntervalSinceNow:kFirstDelay]
                                      interval:interval
                                        target:[G6PerfView class]
                                      selector:@selector(g6_tick:)
                                      userInfo:nil
                                       repeats:YES];
    // Chế độ mặc định: lúc ngón tay đang kéo trang thì nghỉ đo, nhường cho cuộn
    [[NSRunLoop mainRunLoop] addTimer:gTimer forMode:NSDefaultRunLoopMode];
    gTimerInterval = interval;
#if G6_DEBUG
    G6Log(@"hiệu suất: đo mỗi %.0f giây", interval);
#endif
}

// Thứ sẽ hiện trên màn hình, gói thành chuỗi — không đổi thì khỏi vẽ lại
static NSString *G6PerfSignature(NSDictionary *reading) {
    NSDictionary *t = reading[@"text"];
    if (gMini.valid) {
        return [NSString stringWithFormat:@"%@|%@|%@|%@|%d%d", t[@"cpu"], t[@"ram_short"], t[@"down_short"], t[@"up_short"],
                                          [reading[@"down"] doubleValue] >= 512, [reading[@"up"] doubleValue] >= 512];
    }
    return [NSString stringWithFormat:@"%@|%@|%@|%@|%@|%.0f|%.0f|%.0f|%d%d", t[@"cpu"], t[@"ram"], t[@"disk"], t[@"down"], t[@"up"],
                                      G6PerfBarFill([reading[@"cpu"] floatValue]), G6PerfBarFill([reading[@"ram"] floatValue]),
                                      G6PerfBarFill([reading[@"disk"] floatValue]), [reading[@"down"] doubleValue] >= 512,
                                      [reading[@"up"] doubleValue] >= 512];
}

static void G6PerfTick(void) {
    @try {
        if (!gView.window || !G6ScreenAwake()) {
            G6PerfStop();
            return;
        }
        double t0 = G6NowMs();
        G6PerfSample cur;
        G6PerfRead(&cur);
        NSDictionary *r = G6CoreCall(@{@"cmd" : @"perf.reading", @"prev" : G6PerfDict(&gPrev), @"cur" : G6PerfDict(&cur)});
        gPrev = cur;
        NSDictionary *reading = r[@"reading"];
        if (![reading isKindOfClass:[NSDictionary class]] || ![reading[@"text"] isKindOfClass:[NSDictionary class]]) return;
        gReading = reading;
        NSString *signature = G6PerfSignature(reading);
        if (![signature isEqualToString:gShownSignature]) {
            gShownSignature = signature;
            [gContent setNeedsDisplay];
        }
        gTicks++;
        gTickMs += G6NowMs() - t0;
    } @catch (NSException *e) {
        G6Log(@"hiệu suất: lỗi khi đo: %@", e);
    }
}

// ---- Gắn / gỡ / đồng bộ ----

static void G6PerfRemove(void) {
    G6PerfStop();
    [gView removeFromSuperview];
    gView = nil;
    gGlass = gShadow = nil;
    gContent = nil;
    gDrawnFrame = CGRectZero;
    gShownSignature = nil;
}

// Đưa dải hiệu suất về đúng trạng thái: có / không, đúng chỗ, kính đúng nền, đang đo hay đứng. Gọi bao nhiêu lần cũng được.
static void G6PerfSync(void) {
    BOOL active = G6Feature(@"perf");
    if (active != gActive) {
        gActive = active;
        G6Log(@"hiệu suất: %@", active ? @"bật" : @"tắt");
    }
    if (!active) {
        G6PerfRemove();
        return;
    }
    id controller = G6PerfIconController();
    UIView *host = G6PerfViewFrom(controller, @"contentView");
    if (!host) return;
    if (!gView || gView.superview != host) {
        G6PerfRemove();
        gView = [[G6PerfView alloc] initWithFrame:CGRectMake(0, 0, G6PerfMetrics(NO)->width, kHeight)];
        gShadow = [[UIImageView alloc] initWithFrame:gView.bounds];
        gGlass = [[UIImageView alloc] initWithFrame:gView.bounds];
        gContent = [[G6PerfContentView alloc] initWithFrame:gView.bounds];
        gContent.opaque = NO;
        gContent.backgroundColor = [UIColor clearColor];
        gContent.contentMode = UIViewContentModeRedraw;
        // Không nhận chạm: mọi chạm đi thẳng xuống màn hình chính
        gView.userInteractionEnabled = NO;
        [gView addSubview:gShadow];
        [gView addSubview:gGlass];
        [gView addSubview:gContent];
        gNoRoomLogged = NO;
        // Thêm sau cùng: didMoveToWindow của gView sẽ hẹn một lượt đồng bộ nữa (vô hại)
        [host addSubview:gView];
    }
    SEL hasFolder = NSSelectorFromString(@"hasOpenFolder");
    gFolderOpen = [controller respondsToSelector:hasFolder] && ((BOOL (*)(id, SEL))objc_msgSend)(controller, hasFolder);
    if (G6PerfPlace()) G6PerfDrawGlass();
    G6PerfUpdateAlpha(NO, 0);

    NSTimeInterval interval = G6PerfInterval();
    BOOL watched = !gView.hidden && gView.window != nil && G6ScreenAwake();
    if (!watched) {
        G6PerfStop();
    } else if (!gTimer || fabs(interval - gTimerInterval) > 0.01) {
        G6PerfStart(interval);
    }
}

// Gom nhiều lần báo sát nhau (vào cửa sổ, mở khoá, đổi cấu hình, xoay máy…) thành một lượt ở vòng lặp kế
static void G6PerfScheduleSync(void) {
    if (gSyncPending) return;
    gSyncPending = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        gSyncPending = NO;
        @try {
            G6PerfSync();
        } @catch (NSException *e) {
            G6Log(@"hiệu suất: lỗi khi đồng bộ: %@", e);
        }
    });
}

// ---- Hàm thay thế (đều gọi lại hàm gốc trước) ----

// Lật trang: mờ dần khi sang trang Tìm kiếm. Hàm này chạy ở mọi khung hình lúc cuộn → chỉ vài phép tính, và chỉ đụng tới
// view khi độ hiện thật sự đổi (giữa các trang biểu tượng thì không đổi).
static void (*o_scrollViewDidScroll)(id, SEL, id);
static void g6_scrollViewDidScroll(id self, SEL _cmd, UIScrollView *scroll) {
    o_scrollViewDidScroll(self, _cmd, scroll);
    if (gView && !gFolderOpen && scroll == G6PerfScrollView()) G6PerfUpdateAlpha(NO, 0);
}

static void (*o_openFolder)(id, SEL, id, BOOL, BOOL);
static void g6_openFolder(id self, SEL _cmd, id folder, BOOL animated, BOOL fromSwitcher) {
    if (gView && folder) {
        gFolderOpen = YES;
        G6PerfUpdateAlpha(animated, 0);
    }
    o_openFolder(self, _cmd, folder, animated, fromSwitcher);
}

static void (*o_closeFolder)(id, SEL, BOOL, BOOL);
static void g6_closeFolder(id self, SEL _cmd, BOOL animated, BOOL toSwitcher) {
    o_closeFolder(self, _cmd, animated, toSwitcher);
    if (gView && gFolderOpen) {
        gFolderOpen = NO;
        // Hiện lại sau khi hai nửa màn hình đã khép
        G6PerfUpdateAlpha(YES, animated ? 0.3 : 0);
    }
}

// Xoay máy: dời dải kính ngay trong khối chuyển động xoay (trượt cùng các biểu tượng); kính dựng lại ở lượt đồng bộ sau
static void (*o_willAnimateRotation)(id, SEL, int, double);
static void g6_willAnimateRotation(id self, SEL _cmd, int orientation, double duration) {
    o_willAnimateRotation(self, _cmd, orientation, duration);
    @try {
        if (gView) G6PerfPlace();
    } @catch (NSException *e) {
    }
    G6PerfScheduleSync();
}

static void (*o_didRotate)(id, SEL, int);
static void g6_didRotate(id self, SEL _cmd, int from) {
    o_didRotate(self, _cmd, from);
    G6PerfScheduleSync();
}

NSString *G6PerfDebugState(void) {
    NSDictionary *t = gReading[@"text"];
    return [NSString stringWithFormat:@"hiệu suất: %@, khung %@ trên cùng=%d gọn=%d ẩn=%d hiện=%.2f cửa sổ=%d, %@ (nhịp %.0f s), thư mục "
                                      @"mở=%d, đã đo %u lần (%.2f ms / lần) — CPU %@ (%.2f), RAM %@ (%.2f), đĩa %@ (%.2f), ↓ %@ ↑ %@",
                                      gActive ? @"bật" : @"tắt", gView ? NSStringFromCGRect(gView.frame) : @"-", gTop, gCompact,
                                      gView.hidden, gView.alpha, gView.window != nil, gTimer ? @"đang đo" : @"đứng", gTimerInterval,
                                      gFolderOpen, gTicks,
                                      gTicks ? gTickMs / gTicks : 0, t[@"cpu"], [gReading[@"cpu"] floatValue], t[@"ram"],
                                      [gReading[@"ram"] floatValue], t[@"disk"], [gReading[@"disk"] floatValue], t[@"down"], t[@"up"]];
}

void G6PerfInstall(void) {
    G6WallpaperInstall();
    G6ScreenWatchInstall();
    Class controller = objc_getClass("SBIconController");
    if (!controller) {
        G6Log(@"hiệu suất: thiếu lớp SBIconController — bỏ qua");
        return;
    }
    G6Hook(controller, NSSelectorFromString(@"scrollViewDidScroll:"), (IMP)g6_scrollViewDidScroll, (IMP *)&o_scrollViewDidScroll);
    G6Hook(controller, NSSelectorFromString(@"openFolder:animated:fromSwitcher:"), (IMP)g6_openFolder, (IMP *)&o_openFolder);
    G6Hook(controller, NSSelectorFromString(@"closeFolderAnimated:toSwitcher:"), (IMP)g6_closeFolder, (IMP *)&o_closeFolder);
    G6Hook(controller, NSSelectorFromString(@"willAnimateRotationToInterfaceOrientation:duration:"), (IMP)g6_willAnimateRotation,
           (IMP *)&o_willAnimateRotation);
    G6Hook(controller, NSSelectorFromString(@"didRotateFromInterfaceOrientation:"), (IMP)g6_didRotate, (IMP *)&o_didRotate);

    // Đổi cấu hình (bật / tắt, sáng / tối, nhịp đo, chỗ đặt), nền mờ đã cũ, khoá / mở khoá / tắt / sáng màn hình, các mục của
    // thanh trạng thái vừa xếp lại (chỗ trống giữa thanh đổi) → xét lại
    for (NSString *name in @[G6ConfigDidChangeNotification, G6WallpaperDidChangeNotification, G6ScreenStateDidChangeNotification,
                             G6StatusBarDidReflowNotification]) {
        [[NSNotificationCenter defaultCenter] addObserverForName:name
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *note) {
                                                          G6PerfScheduleSync();
                                                      }];
    }
    G6PerfScheduleSync();
}

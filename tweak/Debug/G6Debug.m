// Công cụ thử của Glass 6 trong SpringBoard (bản thử). Lệnh — một dòng trong G6_DIR/cmd.txt:
//   dump                 cây view của mọi cửa sổ            → dump.txt
//   classes <tiền tố>    các lớp có tên bắt đầu bằng tiền tố → classes.txt
//   methods <lớp>        lớp cha, biến, hàm của một lớp      → methods.txt
//   inspect <lớp> [hàm…] lớp vẽ (CALayer) của mọi view thuộc lớp + view cha; gọi thử các hàm không tham số → inspect.txt
//   panel sang|toi|off   bật / tắt cửa sổ thử các tấm kính trên màn hình đang hiện (nền = ảnh chụp màn hình)
//   orient <1–4>         giả xoay máy (1 đứng, 3 / 4 nằm ngang)
//   bench                đo thời gian chụp màn hình, làm mờ, dựng kính, dựng bóng → glass6.log
//   goto <n>             lật màn hình chính tới trang biểu tượng thứ n (0 = trang đầu)
//   hud                  hiện bảng âm lượng (tăng rồi giảm lại một nấc)
//   alert <n>            hiện hộp thoại thử có n nút (1–3); 0 = đóng
//   cc 1|0               mở / đóng Control Center (không qua cử chỉ)
//   cctest state | tap <tên nút> | brightness <0–1> | volume <0–1>   bấm / kéo trong Control Center đang mở, ghi trạng thái máy
//   sbitems                                 các mục của thanh trạng thái trong tiến trình đang chạy lệnh (dùng được trong app)
//   statusbar                               thanh trạng thái của SpringBoard: loại mục, vùng, trạng thái SIM, khung từng mục
//   perf                                    trạng thái dải hiệu suất trên màn hình chính (khung, đang đo / đứng, số đo gần nhất)
//   assist state | menu 1|0 | press <mã> | do <mã> | tap | double | hold | move <mép> <y>   nút AssistiveTouch của Glass 6
//   pull <x>             giả cử chỉ kéo từ mép trên xuống, bắt đầu ở hoành độ x (toạ độ giao diện)
//   banner               hiện một băng thông báo thử
//   nc 1|0               mở / đóng Trung tâm thông báo
//   sim                  trạng thái SIM của SpringBoard + tiêu đề cảnh báo theo từng mã → glass6.log
//   lock                 khoá máy (như bấm nút nguồn)
//   wake                 sáng màn hình mà không mở khoá (để chụp màn khoá)
//   labels               thông số vẽ nhãn của biểu tượng (phông, màu, bóng chữ) → glass6.log
//   edit 1|0             vào / ra chế độ sắp xếp biểu tượng
//   folder 1|0           mở thư mục đầu tiên trên màn hình / đóng thư mục
//   switcher 1|0         mở / đóng khay đa nhiệm
//   iconprobe <mã app>   ghi nhật ký các hàm tạo ảnh biểu tượng rồi bắt app đó tạo lại ảnh → glass6.log
//   iconshot <mã app>    lưu ảnh biểu tượng ở mọi định dạng + ảnh các lớp con của SBIconView → icons/
//   ui                   mọi thứ bấm được đang hiện (dòng + trạng thái công tắc, nút, nút chọn đoạn, thanh trượt) → ui.txt
//   specs                (app Cài đặt) mã mục + lớp ô + biểu tượng của mọi dòng → specs.txt, ảnh biểu tượng → icons/
//   select <chữ>         chọn dòng của bảng có đúng chữ đó (cả dòng chưa cuộn tới)
//   toggle <chữ>         gạt công tắc của dòng có chữ đó
//   press <chữ>          bấm nút có chữ đó (nút trên thanh, nút hộp thoại…)
//   seg <n>              chọn đoạn thứ n của nút chọn đoạn đầu tiên đang hiện
//   back                 lùi một màn
//   row <n> [lớp bảng]   chọn dòng thứ n (từ 0, trong các dòng đang hiện) của bảng đầu tiên đang hiện (hoặc bảng thuộc lớp đã
//                        nêu) — cho bảng mà chữ của dòng là dữ liệu riêng: không cần biết chữ
//   vcsend <lớp controller> <hàm> [0|1]   gọi một hàm không tham số (hoặc một tham số: đối tượng = nil, cờ = 0 / 1) của view
//                        controller đầu tiên thuộc lớp đó đang có view trong cửa sổ (vd hiện / ẩn các thanh của trình xem ảnh)
//   balloons 1|0         (app Tin nhắn) tấm thử chứa bốn bong bóng chữ của ChatKit mang chữ thử — soi bong bóng mà không nhìn tin
//                        nhắn thật; tấm nằm ở (200, 100) cỡ 640×380 trong view gốc
//   gtap <lớp view> <hàm> @x,y   gọi hàm xử lý cử chỉ của view đầu tiên thuộc lớp đó với một «cú chạm giả» tại (x, y) (toạ độ
//                        như press @x,y) — cho view tự bắt cử chỉ, không phải UIControl (vd lưới ảnh: gtap PLStackView tap: @80,130)
//   popover 1|2|3|0      mở bảng nổi thử (mũi tên lên / xuống / trái); 0 = đóng
//   sheet 1|0            mở bảng chọn thử (trên iPad nằm trong bảng nổi)
//   appearance <0|1|2>   đặt chế độ sáng / tối / tự động (sửa đúng khoá `appearance` của tệp cấu hình rồi báo đổi)
//   gallery 1|2|3|4|0    cửa sổ trưng mọi thành phần UIKit chuẩn (thanh, nút có hình, thanh thẻ, nút điều khiển) để soi kiểu;
//                        2 = các ô nhập có sẵn chữ; 3 = bảng có thêm một ô tự vẽ; 4 = thay bảng bằng ba bánh xe chọn
//   focus 1|0            đưa con trỏ vào ô nhập đầu tiên đang hiện (bàn phím bật lên) / bỏ ra
//   cafilter list | <loại>[,<loại>…] [lớp view] | off   thử bộ lọc màu CAFilter trên lớp vẽ của một view («hue» = xoay màu 180°,
//                        «blur» = làm mờ bán kính 8); «cafilter bg <loại…>» = thử backgroundFilters (lọc thứ nằm sau một ô)
//   (tệp cờ /var/tmp/vn.glass6/imglog có sẵn lúc tiến trình khởi động → ghi tên + cỡ mọi hình nạp bằng imageNamed:)
//   svc <tham số…>       chạy g6svc từ SpringBoard (quyền mobile → thử bit setuid): «svc status», «svc set twitter=1» → glass6.log
//   uid                  uid / euid của SpringBoard → glass6.log
//   otacheck             tự kiểm bản mới ngay (bỏ dấu «đã hỏi trong 24 giờ» và «đã báo bản này») → hộp thoại nếu có bản mới
// Công cụ này cũng nằm trong Glass6UI (bản thử) nên chạy được trong app: dòng lệnh bắt đầu bằng «@<tên tiến trình> » thì chỉ
// tiến trình đó chạy (vd «@Preferences dump»); không có «@» thì chỉ SpringBoard chạy.
// Lệnh mới đừng trùng tiền tố với lệnh cũ (so bằng hasPrefix).
#import "G6Debug.h"

#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <sys/stat.h>

#if G6_SB
#import "G6Assist.h"
#if G6_SB
#import "G6OTACheck.h"
#endif
#import "G6CardSwitcher.h"
#import "G6ControlCenter.h"
#import "G6Perf.h"
#import "G6StatusBar.h"
#endif
#import "G6Core.h"
#import "G6StatusItems.h"
#import "G6Glass.h"
#import "G6Guard.h"
#import "G6Hook.h"
#import "G6Log.h"
#import "G6Prefs.h"
#if G6_SB
#import "G6Services.h"
#endif

#define G6_DEBUG_NOTE "vn.glass6/debug"

static UIWindow *gPanel;

// Thư mục chứa tệp lệnh và kết quả: G6_DIR; app trong hộp cát (không đọc được G6_DIR) thì dùng G6_APP_DIR
static NSString *G6DebugDir(void) {
    static NSString *dir;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dir = access(G6_DIR, R_OK | W_OK) == 0 ? @G6_DIR : @G6_APP_DIR;
    });
    return dir;
}
#define kCmdPath [G6DebugDir() stringByAppendingPathComponent:@"cmd.txt"]

static void G6WriteResult(NSString *name, NSString *text) {
    NSString *path = [G6DebugDir() stringByAppendingPathComponent:name];
    [text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    G6Log(@"[thử] đã ghi %@ (%lu ký tự)", name, (unsigned long)text.length);
}

static NSArray *G6AllWindows(void) {
    // Hàm riêng của UIKit: gồm cả cửa sổ không thuộc UIApplication.windows (thanh trạng thái, cảnh báo…)
    SEL sel = NSSelectorFromString(@"allWindowsIncludingInternalWindows:onlyVisibleWindows:");
    if ([UIWindow respondsToSelector:sel]) {
        NSMethodSignature *sig = [UIWindow methodSignatureForSelector:sel];
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        inv.target = [UIWindow class];
        inv.selector = sel;
        BOOL yes = YES, no = NO;
        [inv setArgument:&yes atIndex:2];
        [inv setArgument:&no atIndex:3];
        [inv invoke];
        __unsafe_unretained NSArray *result = nil;
        [inv getReturnValue:&result];
        if (result) return result;
    }
    return [UIApplication sharedApplication].windows;
}

static void G6Dump(void) {
    NSMutableString *out = [NSMutableString string];
    UIApplication *app = [UIApplication sharedApplication];
    [out appendFormat:@"hướng thanh trạng thái: %d; màn hình: %@ @%.0fx\n\n", (int)app.statusBarOrientation,
                      NSStringFromCGRect([UIScreen mainScreen].bounds), [UIScreen mainScreen].scale];
    SEL desc = NSSelectorFromString(@"recursiveDescription");
    for (UIWindow *w in G6AllWindows()) {
        [out appendFormat:@"===== %@ mức %.0f ẩn=%d khung=%@\n", NSStringFromClass([w class]), w.windowLevel, w.hidden,
                          NSStringFromCGRect(w.frame)];
        if ([w respondsToSelector:desc]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [out appendFormat:@"%@\n\n", [w performSelector:desc]];
#pragma clang diagnostic pop
        }
    }
    G6WriteResult(@"dump.txt", out);
}

static void G6Classes(NSString *prefix) {
    unsigned int n = 0;
    Class *list = objc_copyClassList(&n);
    NSMutableArray *names = [NSMutableArray array];
    for (unsigned int i = 0; i < n; i++) {
        NSString *name = @(class_getName(list[i]));
        if (prefix.length == 0 || [name hasPrefix:prefix]) {
            Class sup = class_getSuperclass(list[i]);
            [names addObject:[NSString stringWithFormat:@"%@ : %s", name, sup ? class_getName(sup) : "-"]];
        }
    }
    free(list);
    [names sortUsingSelector:@selector(compare:)];
    G6WriteResult(@"classes.txt", [[names componentsJoinedByString:@"\n"] stringByAppendingString:@"\n"]);
}

static void G6AppendMethods(NSMutableString *out, Class cls, NSString *sign) {
    unsigned int n = 0;
    Method *list = class_copyMethodList(cls, &n);
    NSMutableArray *lines = [NSMutableArray array];
    for (unsigned int i = 0; i < n; i++) {
        [lines addObject:[NSString stringWithFormat:@"%@ %s   %s", sign, sel_getName(method_getName(list[i])),
                                                    method_getTypeEncoding(list[i]) ?: ""]];
    }
    free(list);
    [lines sortUsingSelector:@selector(compare:)];
    [out appendFormat:@"%@\n", [lines componentsJoinedByString:@"\n"]];
}

static void G6Methods(NSString *name) {
    Class cls = NSClassFromString(name);
    if (!cls) {
        G6WriteResult(@"methods.txt", [NSString stringWithFormat:@"không có lớp %@\n", name]);
        return;
    }
    NSMutableString *out = [NSMutableString string];
    for (Class c = cls; c; c = class_getSuperclass(c)) [out appendFormat:@"%s%s", c == cls ? "" : " : ", class_getName(c)];
    [out appendString:@"\n\n-- biến\n"];
    unsigned int n = 0;
    Ivar *ivars = class_copyIvarList(cls, &n);
    for (unsigned int i = 0; i < n; i++) {
        [out appendFormat:@"%s   %s\n", ivar_getName(ivars[i]), ivar_getTypeEncoding(ivars[i]) ?: ""];
    }
    free(ivars);
    [out appendString:@"\n-- hàm của đối tượng\n"];
    G6AppendMethods(out, cls, @"-");
    [out appendString:@"\n-- hàm của lớp\n"];
    G6AppendMethods(out, object_getClass(cls), @"+");
    G6WriteResult(@"methods.txt", out);
}

static void G6AppendLayer(NSMutableString *out, CALayer *layer, NSString *indent, int depth) {
    id contents = layer.contents;
    NSString *what = @"-";
    if (contents) {
        CFTypeID tid = CFGetTypeID((__bridge CFTypeRef)contents);
        if (tid == CGImageGetTypeID()) {
            CGImageRef img = (__bridge CGImageRef)contents;
            what = [NSString stringWithFormat:@"CGImage %zux%zu", CGImageGetWidth(img), CGImageGetHeight(img)];
        } else {
            what = [(__bridge_transfer NSString *)CFCopyTypeIDDescription(tid) description];
        }
    }
    [out appendFormat:@"%@%@ khung=%@ nội dung=%@ nền=%@ ẩn=%d mờ=%.2f rect=%@ center=%@\n", indent, NSStringFromClass([layer class]),
                      NSStringFromCGRect(layer.frame), what, layer.backgroundColor ? @"có" : @"-", layer.hidden, layer.opacity,
                      NSStringFromCGRect(layer.contentsRect), NSStringFromCGRect(layer.contentsCenter)];
    if (depth <= 0) return;
    for (CALayer *sub in layer.sublayers) G6AppendLayer(out, sub, [indent stringByAppendingString:@"   "], depth - 1);
}

static void G6CollectViews(UIView *view, Class cls, NSMutableArray *found) {
    if ([view isKindOfClass:cls]) [found addObject:view];
    for (UIView *sub in view.subviews) G6CollectViews(sub, cls, found);
}

// Số trả về của một hàm không tham số trả float / int / BOOL — để đọc số đo bố cục của SpringBoard
static NSString *G6CallNumber(id obj, NSString *selName) {
    SEL sel = NSSelectorFromString(selName);
    if (![obj respondsToSelector:sel]) return @"(không có)";
    NSMethodSignature *sig = [obj methodSignatureForSelector:sel];
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    inv.target = obj;
    inv.selector = sel;
    [inv invoke];
    const char *type = sig.methodReturnType;
    if (type[0] == 'f') {
        float v = 0;
        [inv getReturnValue:&v];
        return [NSString stringWithFormat:@"%.2f", v];
    }
    if (type[0] == 'c' || type[0] == 'B') {
        char v = 0;
        [inv getReturnValue:&v];
        return [NSString stringWithFormat:@"%d", v];
    }
    if (type[0] == 'i' || type[0] == 'I') {
        int v = 0;
        [inv getReturnValue:&v];
        return [NSString stringWithFormat:@"%d", v];
    }
    return [NSString stringWithFormat:@"(kiểu %s)", type];
}

static void G6Inspect(NSString *arg) {
    NSArray *parts = [arg componentsSeparatedByString:@" "];
    Class cls = NSClassFromString(parts.count ? parts[0] : @"");
    NSMutableString *out = [NSMutableString string];
    if (!cls) {
        G6WriteResult(@"inspect.txt", [NSString stringWithFormat:@"không có lớp %@\n", arg]);
        return;
    }
    NSMutableArray *found = [NSMutableArray array];
    for (UIWindow *w in G6AllWindows()) G6CollectViews(w, cls, found);
    [out appendFormat:@"%lu view thuộc lớp %@\n\n", (unsigned long)found.count, NSStringFromClass(cls)];
    for (UIView *v in found) {
        [out appendFormat:@"%@\n", v];
        // Các tham số còn lại: tên hàm không tham số cần gọi thử
        for (NSUInteger i = 1; i < parts.count; i++) {
            [out appendFormat:@"   %@ = %@\n", parts[i], G6CallNumber(v, parts[i])];
        }
        [out appendString:@" lớp vẽ:\n"];
        G6AppendLayer(out, v.layer, @"   ", 2);
        if (v.superview) {
            [out appendFormat:@" cha: %@\n", v.superview];
            G6AppendLayer(out, v.superview.layer, @"   ", 1);
        }
        [out appendString:@"\n"];
    }
    G6WriteResult(@"inspect.txt", out);
}

// Cửa sổ thử: vài tấm kính đủ loại, đặt theo toạ độ khung hình (không xoay theo máy) trên màn hình đang hiện.
static void G6Panel(NSString *mode) {
    gPanel.hidden = YES;
    gPanel = nil;
    if ([mode isEqualToString:@"off"]) return;
    BOOL dark = [mode isEqualToString:@"toi"];
    double t0 = G6NowMs();
    // Chụp TRƯỚC khi hiện cửa sổ thử
    G6Backdrop *backdrop = [G6Backdrop backdropWithScreen:NO];
    double t1 = G6NowMs();
    if (!backdrop) {
        G6Log(@"[thử] không chụp được màn hình");
        return;
    }
    UIWindow *w = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    w.windowLevel = 1060;  // trên «Hình nổi» của Côn Bằng TV (1050), dưới cảnh báo hệ thống
    w.userInteractionEnabled = NO;
    w.backgroundColor = [UIColor clearColor];
    NSArray *specs = @[
        @[@"dock", [NSValue valueWithCGRect:CGRectMake(34, 900, 700, 100)]],
        @[@"panel", [NSValue valueWithCGRect:CGRectMake(404, 60, 320, 150)]],
        @[@"panel", [NSValue valueWithCGRect:CGRectMake(404, 226, 152, 152)]],
        @[@"panel", [NSValue valueWithCGRect:CGRectMake(572, 226, 152, 152)]],
        @[@"banner", [NSValue valueWithCGRect:CGRectMake(40, 60, 340, 72)]],
        @[@"capsule", [NSValue valueWithCGRect:CGRectMake(40, 160, 240, 52)]],
        @[@"capsule", [NSValue valueWithCGRect:CGRectMake(40, 236, 52, 52)]],
    ];
    for (NSArray *s in specs) {
        NSString *surface = s[0];
        CGRect frame = [s[1] CGRectValue];
        CGFloat margin = 0;
        UIImage *shadow = G6ShadowImage(surface, frame.size, dark, &margin);
        if (shadow) {
            UIImageView *sv = [[UIImageView alloc] initWithImage:shadow];
            sv.frame = CGRectInset(frame, -margin, -margin);
            [w addSubview:sv];
        }
        UIImageView *v = [[UIImageView alloc] initWithFrame:frame];
        [w addSubview:v];
        v.image = G6GlassImageForView(surface, v, dark, backdrop);
    }
    // Kính giả (không có nền) — kiểu thanh trong app
    UIImageView *fake = [[UIImageView alloc] initWithFrame:CGRectMake(40, 320, 340, 44)];
    [w addSubview:fake];
    fake.image = G6GlassImageForView(@"capsule", fake, dark, nil);
    double t2 = G6NowMs();
    w.hidden = NO;
    gPanel = w;
    G6Log(@"[thử] cửa sổ kính %@: chụp + làm mờ %.1f ms, 8 tấm kính + bóng %.1f ms", dark ? @"tối" : @"sáng", t1 - t0, t2 - t1);
}

static void G6Bench(void) {
    NSMutableString *out = [NSMutableString stringWithString:@"[thử] đo:"];
    double t = G6NowMs();
    G6Backdrop *fast = [G6Backdrop backdropWithScreen:YES];
    [out appendFormat:@" chụp+mờ 1/8 %.1f ms;", G6NowMs() - t];
    t = G6NowMs();
    G6Backdrop *slow = [G6Backdrop backdropWithScreen:NO];
    [out appendFormat:@" chụp+mờ 1/4 %.1f ms;", G6NowMs() - t];
    NSArray *cases = @[
        @[@"dock", [NSValue valueWithCGSize:CGSizeMake(700, 100)]],
        @[@"panel", [NSValue valueWithCGSize:CGSizeMake(320, 400)]],
        @[@"banner", [NSValue valueWithCGSize:CGSizeMake(420, 72)]],
        @[@"capsule", [NSValue valueWithCGSize:CGSizeMake(240, 52)]],
    ];
    for (NSArray *c in cases) {
        CGSize size = [c[1] CGSizeValue];
        CGAffineTransform at = CGAffineTransformMakeTranslation(20, 20);
        t = G6NowMs();
        UIImage *g = G6GlassImage(c[0], size, NO, slow ?: fast, at);
        double tg = G6NowMs() - t;
        // Bóng: lần đầu phải dựng, lần sau lấy từ bộ nhớ đệm
        t = G6NowMs();
        UIImage *s = G6ShadowImage(c[0], size, NO, NULL);
        double ts = G6NowMs() - t;
        t = G6NowMs();
        G6ShadowImage(c[0], size, NO, NULL);
        double ts2 = G6NowMs() - t;
        [out appendFormat:@" %@ %.0fx%.0f kính %.1f ms%@ bóng %.1f ms%@ (lần sau %.1f ms);", c[0], size.width, size.height, tg,
                          g ? @"" : @"(LỖI)", ts, s ? @"" : @"(LỖI)", ts2];
    }
    G6Log(@"%@", out);
}

// Giả xoay máy: 1 = đứng, 2 = đứng ngược, 3 / 4 = nằm ngang (UIDeviceOrientation). SpringBoard xoay theo nếu không khoá xoay.
static void G6Orient(NSString *arg) {
    int o = arg.intValue;
    SEL sel = NSSelectorFromString(@"setOrientation:animated:");
    UIDevice *dev = [UIDevice currentDevice];
    if (o < 1 || o > 4 || ![dev respondsToSelector:sel]) {
        G6Log(@"[thử] orient: cần 1–4 và hàm setOrientation:animated:");
        return;
    }
    ((void (*)(id, SEL, int, BOOL))objc_msgSend)(dev, sel, o, YES);
}

// ---- Dò đường tạo ảnh biểu tượng của SpringBoard ----

static id G6IconModel(void) {
    Class cls = objc_getClass("SBIconController");
    if (![cls respondsToSelector:@selector(sharedInstance)]) return nil;
    id ctl = ((id (*)(id, SEL))objc_msgSend)(cls, @selector(sharedInstance));
    SEL model = NSSelectorFromString(@"model");
    return [ctl respondsToSelector:model] ? ((id (*)(id, SEL))objc_msgSend)(ctl, model) : nil;
}

static NSString *G6ThreadName(void) {
    return [NSThread isMainThread] ? @"luồng chính" : @"luồng nền";
}

static id (*po_inst)(id, SEL, int, BOOL, float);
static id p_inst(UIImage *self, SEL _cmd, int format, BOOL pre, float scale) {
    UIImage *r = po_inst(self, _cmd, format, pre, scale);
    G6Log(@"[dò] -[UIImage _applicationIconImageForFormat:%d precomposed:%d scale:%.0f] nguồn %@ → %@ (%@)", format, pre, scale,
          NSStringFromCGSize(self.size), r ? NSStringFromCGSize(r.size) : @"nil", G6ThreadName());
    return r;
}

static id (*po_cls)(id, SEL, id, int, float);
static id p_cls(id self, SEL _cmd, id bundleID, int format, float scale) {
    UIImage *r = po_cls(self, _cmd, bundleID, format, scale);
    G6Log(@"[dò] +[UIImage _applicationIconImageForBundleIdentifier:%@ format:%d scale:%.0f] → %@ (%@)", bundleID, format, scale,
          r ? NSStringFromCGSize(r.size) : @"nil", G6ThreadName());
    return r;
}

static id (*po_load)(id, SEL, id, int, float);
static id p_load(id self, SEL _cmd, id arg, int format, float scale) {
    UIImage *r = po_load(self, _cmd, arg, format, scale);
    G6Log(@"[dò] -[SBApplicationIcon __loadIconImage:(%@) %@ format:%d scale:%.0f] → %@ (%@)", [arg class], arg, format, scale,
          r ? NSStringFromCGSize(r.size) : @"nil", G6ThreadName());
    return r;
}

static id (*po_gen)(id, SEL, int);
static id p_gen(id self, SEL _cmd, int format) {
    G6Log(@"[dò] -[%@ generateIconImage:%d] vào (%@)", [self class], format, G6ThreadName());
    UIImage *r = po_gen(self, _cmd, format);
    G6Log(@"[dò] -[%@ generateIconImage:%d] ra %@", [self class], format, r ? NSStringFromCGSize(r.size) : @"nil");
    return r;
}

// Gắn hàm ghi nhật ký vào các hàm tạo ảnh biểu tượng rồi bắt một app tạo lại ảnh — để biết SpringBoard đi đường nào.
static void G6IconProbe(NSString *bundleID) {
    static BOOL hooked;
    if (!hooked) {
        hooked = YES;
        G6Hook([UIImage class], NSSelectorFromString(@"_applicationIconImageForFormat:precomposed:scale:"), (IMP)p_inst, (IMP *)&po_inst);
        G6Hook(object_getClass([UIImage class]), NSSelectorFromString(@"_applicationIconImageForBundleIdentifier:format:scale:"),
               (IMP)p_cls, (IMP *)&po_cls);
        G6HookNamed("SBApplicationIcon", NSSelectorFromString(@"__loadIconImage:format:scale:"), (IMP)p_load, (IMP *)&po_load);
        G6HookNamed("SBApplicationIcon", NSSelectorFromString(@"generateIconImage:"), (IMP)p_gen, (IMP *)&po_gen);
    }
    id model = G6IconModel();
    SEL find = NSSelectorFromString(@"leafIconForIdentifier:");
    id icon = [model respondsToSelector:find] ? ((id (*)(id, SEL, id))objc_msgSend)(model, find, bundleID) : nil;
    SEL reload = NSSelectorFromString(@"reloadIconImagePurgingImageCache:");
    if (!icon || ![icon respondsToSelector:reload]) {
        G6Log(@"[dò] không có biểu tượng «%@»", bundleID);
        return;
    }
    ((void (*)(id, SEL, BOOL))objc_msgSend)(icon, reload, YES);
    G6Log(@"[dò] đã bảo «%@» (%@) tạo lại ảnh", bundleID, [icon class]);
}

static void G6SavePNG(UIImage *img, NSString *dir, NSString *name, NSMutableString *report) {
    if (![img isKindOfClass:[UIImage class]]) {
        [report appendFormat:@"%@: (không có)\n", name];
        return;
    }
    [report appendFormat:@"%@: %@ %@ @%.0fx\n", name, [img class], NSStringFromCGSize(img.size), img.scale];
    [UIImagePNGRepresentation(img) writeToFile:[dir stringByAppendingPathComponent:[name stringByAppendingString:@".png"]] atomically:YES];
}

// Lưu ảnh của một biểu tượng ở mọi định dạng + ảnh các lớp con của SBIconView → thư mục icons/
static void G6IconShot(NSString *identifier) {
    id model = G6IconModel();
    SEL find = NSSelectorFromString(@"leafIconForIdentifier:");
    id icon = [model respondsToSelector:find] ? ((id (*)(id, SEL, id))objc_msgSend)(model, find, identifier) : nil;
    NSString *dir = [@G6_DIR stringByAppendingPathComponent:@"icons"];
    [[NSFileManager defaultManager] removeItemAtPath:dir error:NULL];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    NSMutableString *report = [NSMutableString stringWithFormat:@"%@ → %@\n", identifier, icon];
    SEL get = NSSelectorFromString(@"getIconImage:");
    if ([icon respondsToSelector:get]) {
        for (int f = 0; f < 12; f++) {
            UIImage *img = ((id (*)(id, SEL, int))objc_msgSend)(icon, get, f);
            G6SavePNG(img, dir, [NSString stringWithFormat:@"f%d", f], report);
        }
    }
    // Mọi SBIconView đang hiện: lưu ảnh từng lớp con của biểu tượng đầu tiên thuộc mỗi lớp
    NSMutableArray *views = [NSMutableArray array];
    for (UIWindow *w in G6AllWindows()) G6CollectViews(w, objc_getClass("SBIconView"), views);
    NSMutableSet *seen = [NSMutableSet set];
    for (UIView *v in views) {
        NSString *cls = NSStringFromClass([v class]);
        id vicon = [v respondsToSelector:@selector(icon)] ? ((id (*)(id, SEL))objc_msgSend)(v, @selector(icon)) : nil;
        BOOL wanted = icon && vicon == icon;
        if (!wanted && [seen containsObject:cls]) continue;
        [seen addObject:cls];
        NSString *tag = wanted ? @"view" : cls;
        [report appendFormat:@"\n%@ %@\n", tag, v];
        NSMutableArray *subs = [NSMutableArray array];
        G6CollectViews(v, [UIImageView class], subs);
        int i = 0;
        for (UIImageView *iv in subs) {
            [report appendFormat:@"  %d %@ khung %@ trong SBIconView %@\n", i, [iv class], NSStringFromCGRect(iv.frame),
                                 NSStringFromCGRect([v convertRect:iv.bounds fromView:iv])];
            G6SavePNG(iv.image, dir, [NSString stringWithFormat:@"%@-%d", tag, i], report);
            i++;
        }
    }
    G6WriteResult(@"icons/report.txt", report);
}

// Thông số vẽ nhãn (phông, màu, bóng chữ) của biểu tượng đầu tiên thuộc mỗi lớp view / mỗi vị trí → nhật ký
static void G6Labels(void) {
    NSMutableArray *views = [NSMutableArray array];
    for (UIWindow *w in G6AllWindows()) G6CollectViews(w, objc_getClass("SBIconView"), views);
    SEL make = NSSelectorFromString(@"_labelImageParametersForIcon:location:");
    NSMutableSet *seen = [NSMutableSet set];
    for (UIView *v in views) {
        id icon = [v respondsToSelector:@selector(icon)] ? ((id (*)(id, SEL))objc_msgSend)(v, @selector(icon)) : nil;
        int loc = [v respondsToSelector:@selector(location)] ? ((int (*)(id, SEL))objc_msgSend)(v, @selector(location)) : -1;
        NSString *key = [NSString stringWithFormat:@"%@/%d", [v class], loc];
        if (!icon || [seen containsObject:key] || ![[v class] respondsToSelector:make]) continue;
        [seen addObject:key];
        id p = ((id (*)(id, SEL, id, int))objc_msgSend)([v class], make, icon, loc);
        UIFont *font = [p respondsToSelector:@selector(font)] ? ((id (*)(id, SEL))objc_msgSend)(p, @selector(font)) : nil;
        float blur = [p respondsToSelector:@selector(shadowBlur)] ? ((float (*)(id, SEL))objc_msgSend)(p, @selector(shadowBlur)) : -1;
        CGSize off = CGSizeZero, max = CGSizeZero;
        // armv7: struct lớn hơn 4 byte trả qua vùng nhớ → phải gọi objc_msgSend_stret (gọi objc_msgSend là sập — đã gặp)
        if ([p respondsToSelector:@selector(shadowOffset)]) off = ((CGSize (*)(id, SEL))objc_msgSend_stret)(p, @selector(shadowOffset));
        if ([p respondsToSelector:@selector(maxSize)]) max = ((CGSize (*)(id, SEL))objc_msgSend_stret)(p, @selector(maxSize));
        id text = [p respondsToSelector:@selector(textColor)] ? ((id (*)(id, SEL))objc_msgSend)(p, @selector(textColor)) : nil;
        id shadow = [p respondsToSelector:@selector(shadowColor)] ? ((id (*)(id, SEL))objc_msgSend)(p, @selector(shadowColor)) : nil;
        BOOL gray = [p respondsToSelector:NSSelectorFromString(@"colorspaceIsGrayscale")]
                        ? ((BOOL (*)(id, SEL))objc_msgSend)(p, NSSelectorFromString(@"colorspaceIsGrayscale")) : NO;
        G6Log(@"[thử] nhãn %@ → %@: phông %@ %.1f, chữ %@, bóng %@ nhoè %.1f lệch %@, tối đa %@, xám %d", key, [p class], font.fontName,
              font.pointSize, text, shadow, blur, NSStringFromCGSize(off), NSStringFromCGSize(max), gray);
    }
}

// Hiện bảng âm lượng: tăng một nấc rồi giảm lại một nấc (âm lượng về như cũ; lần hai là trường hợp «bảng đang hiện»)
static void G6ShowHUD(void) {
    Class cls = objc_getClass("VolumeControl");
    SEL shared = NSSelectorFromString(@"sharedVolumeControl");
    id vc = [cls respondsToSelector:shared] ? ((id (*)(id, SEL))objc_msgSend)(cls, shared) : nil;
    for (NSString *name in @[@"increaseVolume", @"cancelVolumeEvent", @"decreaseVolume", @"cancelVolumeEvent"]) {
        SEL sel = NSSelectorFromString(name);
        if ([vc respondsToSelector:sel]) ((void (*)(id, SEL))objc_msgSend)(vc, sel);
        else G6Log(@"[thử] hud: không có %@", name);
    }
}

// Mở / đóng Trung tâm thông báo. arg: 1 / 0
static void G6ShowNC(NSString *arg) {
    Class cls = objc_getClass("SBBulletinListController");
    SEL shared = NSSelectorFromString(@"sharedInstance");
    id ctl = [cls respondsToSelector:shared] ? ((id (*)(id, SEL))objc_msgSend)(cls, shared) : nil;
    SEL sel = NSSelectorFromString(arg.intValue ? @"showListViewAnimated:" : @"hideListViewAnimated:");
    if ([ctl respondsToSelector:sel]) ((void (*)(id, SEL, BOOL))objc_msgSend)(ctl, sel, NO);
    else G6Log(@"[thử] nc: không có %@", NSStringFromSelector(sel));
}

// Hiện / đóng một hộp thoại thử. arg: số nút (1–3), 0 = đóng hộp thoại đang hiện
static UIAlertView *gTestAlert;
static void G6ShowAlert(NSString *arg) {
    [gTestAlert dismissWithClickedButtonIndex:0 animated:NO];
    gTestAlert = nil;
    int buttons = arg.intValue;
    if (buttons <= 0) return;
    gTestAlert = [[UIAlertView alloc] initWithTitle:@"Hộp thoại thử"
                                            message:@"Đây là hộp thoại của công cụ thử Glass 6, có hai dòng chữ để xem cách xuống dòng."
                                           delegate:nil
                                  cancelButtonTitle:@"Huỷ"
                                  otherButtonTitles:nil];
    if (buttons >= 2) [gTestAlert addButtonWithTitle:@"Đồng ý"];
    if (buttons >= 3) [gTestAlert addButtonWithTitle:@"Để sau"];
    [gTestAlert show];
}

// Giả cử chỉ «kéo từ mép trên xuống» bắt đầu ở hoành độ x (toạ độ giao diện): gọi đúng ba hàm của SBUIController mà cử chỉ
// thật vẫn gọi — x ở một phần ba bên phải thì phải mở Control Center, chỗ khác thì mở Trung tâm thông báo.
static void G6PullFromTop(NSString *arg) {
    Class cls = objc_getClass("SBUIController");
    id ui = [cls respondsToSelector:@selector(sharedInstance)] ? ((id (*)(id, SEL))objc_msgSend)(cls, @selector(sharedInstance)) : nil;
    SEL began = NSSelectorFromString(@"_showNotificationsGestureBeganWithLocation:");
    SEL changed = NSSelectorFromString(@"_showNotificationsGestureChangedWithLocation:velocity:");
    SEL ended = NSSelectorFromString(@"_showNotificationsGestureEndedWithLocation:velocity:");
    if (![ui respondsToSelector:began] || ![ui respondsToSelector:changed] || ![ui respondsToSelector:ended]) {
        G6Log(@"[thử] pull: thiếu hàm cử chỉ của SBUIController");
        return;
    }
    CGFloat x = arg.floatValue;
    CGPoint velocity = CGPointMake(0, 600);
    ((void (*)(id, SEL, CGPoint))objc_msgSend)(ui, began, CGPointMake(x, 4));
    for (int y = 40; y <= 280; y += 60) {
        ((void (*)(id, SEL, CGPoint, CGPoint))objc_msgSend)(ui, changed, CGPointMake(x, y), velocity);
    }
    ((void (*)(id, SEL, CGPoint, CGPoint))objc_msgSend)(ui, ended, CGPointMake(x, 300), velocity);
}

// Hiện một băng thông báo thử của SpringBoard
// arg = số mili giây: sau chừng đó thì ghi cây view (dump.txt) — để xem các view của hiệu ứng lật lúc đang chạy
static void G6ShowBanner(NSString *arg) {
    Class cls = objc_getClass("SBBulletinBannerController");
    SEL shared = NSSelectorFromString(@"sharedInstance"), sel = NSSelectorFromString(@"showTestBanner");
    id ctl = [cls respondsToSelector:shared] ? ((id (*)(id, SEL))objc_msgSend)(cls, shared) : nil;
    if ([ctl respondsToSelector:sel]) ((void (*)(id, SEL))objc_msgSend)(ctl, sel);
    else G6Log(@"[thử] banner: không có showTestBanner");
    if (arg.intValue > 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(arg.intValue * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
            G6Dump();
        });
    }
}

// Trạng thái SIM của SpringBoard + tiêu đề cảnh báo ứng với từng mã trạng thái → nhật ký
static void G6SIMProbe(void) {
    Class mgrClass = objc_getClass("SBSIMLockManager"), itemClass = objc_getClass("SBSIMLockAlertItem");
    SEL shared = NSSelectorFromString(@"sharedInstance"), status = NSSelectorFromString(@"status");
    id mgr = [mgrClass respondsToSelector:shared] ? ((id (*)(id, SEL))objc_msgSend)(mgrClass, shared) : nil;
    int current = [mgr respondsToSelector:status] ? ((int (*)(id, SEL))objc_msgSend)(mgr, status) : -1;
    Ivar iv = mgr ? class_getInstanceVariable([mgr class], "_currentAlert") : NULL;
    id alert = iv ? object_getIvar(mgr, iv) : nil;
    int alertStatus = [alert respondsToSelector:status] ? ((int (*)(id, SEL))objc_msgSend)(alert, status) : -1;
    NSMutableString *out = [NSMutableString stringWithFormat:@"[thử] SIM: quản lý %@, trạng thái %d, cảnh báo đang giữ %@ (trạng thái %d);", mgr ? @"có" : @"KHÔNG",
                                                             current, alert ? NSStringFromClass([alert class]) : @"không", alertStatus];
    SEL title = NSSelectorFromString(@"alertTitleForStatus:");
    if ([itemClass respondsToSelector:title]) {
        for (int i = 0; i < 10; i++) [out appendFormat:@" %d=«%@»", i, ((id (*)(id, SEL, int))objc_msgSend)(itemClass, title, i)];
    }
    G6Log(@"%@", out);
}

// Khoá máy (như bấm nút nguồn)
static void G6Lock(void) {
    Class cls = objc_getClass("SBUIController");
    SEL sel = NSSelectorFromString(@"lockFromSource:");
    id ctl = [cls respondsToSelector:@selector(sharedInstance)] ? ((id (*)(id, SEL))objc_msgSend)(cls, @selector(sharedInstance)) : nil;
    if ([ctl respondsToSelector:sel]) ((void (*)(id, SEL, int))objc_msgSend)(ctl, sel, 0);
    else G6Log(@"[thử] lock: không có lockFromSource:");
}

// Thêm n thông báo thử vào danh sách của màn khoá (máy phải đang khoá): -[SBAwayBulletinListController showTestBulletin]
static void G6LockBulletin(NSString *arg) {
    Class cls = objc_getClass("SBAwayController");
    SEL shared = NSSelectorFromString(@"sharedAwayController"), viewSel = NSSelectorFromString(@"awayView");
    id away = [cls respondsToSelector:shared] ? ((id (*)(id, SEL))objc_msgSend)(cls, shared) : nil;
    id view = [away respondsToSelector:viewSel] ? ((id (*)(id, SEL))objc_msgSend)(away, viewSel) : nil;
    Ivar iv = view ? class_getInstanceVariable([view class], "_bulletinController") : NULL;
    id controller = iv ? object_getIvar(view, iv) : nil;
    SEL test = NSSelectorFromString(@"showTestBulletin");
    if (![controller respondsToSelector:test]) {
        G6Log(@"[thử] lockbulletin: không có danh sách thông báo của màn khoá (máy chưa khoá?)");
        return;
    }
    int n = MAX(1, MIN(8, arg.intValue));
    for (int i = 0; i < n; i++) ((void (*)(id, SEL))objc_msgSend)(controller, test);
    G6Log(@"[thử] lockbulletin: đã thêm %d thông báo thử", n);
}

// Sáng màn hình mà không mở khoá (để chụp màn khoá)
static void G6Wake(void) {
    Class cls = objc_getClass("SBAwayController");
    SEL shared = NSSelectorFromString(@"sharedAwayController"), sel = NSSelectorFromString(@"undimScreen");
    id away = [cls respondsToSelector:shared] ? ((id (*)(id, SEL))objc_msgSend)(cls, shared) : nil;
    if ([away respondsToSelector:sel]) ((void (*)(id, SEL))objc_msgSend)(away, sel);
    else G6Log(@"[thử] wake: không có undimScreen");
    // undimScreen chỉ đủ khi đèn màn hình còn bật; sau khi khoá hẳn (đèn đã tắt) phải bật lại đèn như lúc có người chạm máy
    UIApplication *app = [UIApplication sharedApplication];
    SEL reset = NSSelectorFromString(@"resetIdleTimerAndUndim:"), factor = NSSelectorFromString(@"setBacklightFactor:");
    if ([app respondsToSelector:reset]) ((void (*)(id, SEL, BOOL))objc_msgSend)(app, reset, YES);
    if ([app respondsToSelector:factor]) ((void (*)(id, SEL, float))objc_msgSend)(app, factor, 1.0f);
}

// Lật tới trang biểu tượng thứ n (0 = trang đầu) của màn hình chính
static void G6GotoPage(NSString *arg) {
    Class cls = objc_getClass("SBIconController");
    SEL sel = NSSelectorFromString(@"scrollToIconListAtIndex:animate:");
    id ctl = [cls respondsToSelector:@selector(sharedInstance)] ? ((id (*)(id, SEL))objc_msgSend)(cls, @selector(sharedInstance)) : nil;
    if (![ctl respondsToSelector:sel]) {
        G6Log(@"[thử] goto: không có scrollToIconListAtIndex:animate:");
        return;
    }
    ((void (*)(id, SEL, int, BOOL))objc_msgSend)(ctl, sel, arg.intValue, NO);
}

// Đưa màn hình chính vào các trạng thái không bấm được từ SSH: chế độ sắp xếp, mở thư mục, khay đa nhiệm. arg: 1 / 0
static void G6HomeAction(NSString *what, NSString *arg) {
    BOOL on = arg.intValue != 0;
    Class cls = objc_getClass("SBIconController");
    id ctl = [cls respondsToSelector:@selector(sharedInstance)] ? ((id (*)(id, SEL))objc_msgSend)(cls, @selector(sharedInstance)) : nil;
    if ([what isEqualToString:@"edit"]) {
        SEL sel = NSSelectorFromString(@"setIsEditing:");
        if ([ctl respondsToSelector:sel]) ((void (*)(id, SEL, BOOL))objc_msgSend)(ctl, sel, on);
    } else if ([what isEqualToString:@"folder"]) {
        SEL open = NSSelectorFromString(@"openFolder:animated:"), close = NSSelectorFromString(@"closeFolderAnimated:");
        if (!on) {
            if ([ctl respondsToSelector:close]) ((void (*)(id, SEL, BOOL))objc_msgSend)(ctl, close, NO);
            return;
        }
        // Thư mục đầu tiên đang có trên màn hình
        NSMutableArray *views = [NSMutableArray array];
        for (UIWindow *w in G6AllWindows()) G6CollectViews(w, objc_getClass("SBFolderIconView"), views);
        for (UIView *v in views) {
            if ([v class] != objc_getClass("SBFolderIconView")) continue;
            id folder = [v respondsToSelector:@selector(folder)] ? ((id (*)(id, SEL))objc_msgSend)(v, @selector(folder)) : nil;
            if (folder && [ctl respondsToSelector:open]) {
                ((void (*)(id, SEL, id, BOOL))objc_msgSend)(ctl, open, folder, NO);
                return;
            }
        }
        G6Log(@"[thử] folder: không thấy thư mục nào");
    } else {
        Class ui = objc_getClass("SBUIController");
        id uictl = [ui respondsToSelector:@selector(sharedInstance)] ? ((id (*)(id, SEL))objc_msgSend)(ui, @selector(sharedInstance)) : nil;
        SEL show = NSSelectorFromString(@"activateSwitcher"), hide = NSSelectorFromString(@"dismissSwitcherAnimated:");
        if (on && [uictl respondsToSelector:show]) ((BOOL (*)(id, SEL))objc_msgSend)(uictl, show);
        if (!on && [uictl respondsToSelector:hide]) ((void (*)(id, SEL, BOOL))objc_msgSend)(uictl, hide, NO);
    }
}

#if G6_SB
// Chạy g6svc đúng như SpringBoard / Cài đặt sẽ chạy (quyền mobile, qua G6SvcRun) rồi ghi mã thoát + đầu ra
static void G6SvcDebug(NSString *arg) {
    NSArray *args = [arg componentsSeparatedByString:@" "];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        double t0 = G6NowMs();
        NSString *out = nil;
        int rc = G6SvcRun(args, &out);
        G6Log(@"[thử] g6svc %@ → mã %d, %.0f ms\n%@", arg, rc, G6NowMs() - t0, out ?: @"");
    });
}
#endif

// ---- Tự bấm: chọn dòng, gạt công tắc, bấm nút theo chữ — để tự thử các màn mà không cần ngón tay ----
// Không giả sự kiện chạm (cấu trúc GSEvent khác nhau theo bản iOS): gọi thẳng hành động của nút / hàm chọn dòng của bảng,
// đúng thứ UIKit sẽ gọi khi người dùng bấm.

static void G6CollectVisible(UIView *view, Class cls, NSMutableArray *out) {
    if (view.hidden || view.alpha < 0.01) return;
    if ([view isKindOfClass:cls]) [out addObject:view];
    for (UIView *sub in view.subviews) G6CollectVisible(sub, cls, out);
}

static NSArray *G6VisibleViews(Class cls) {
    NSMutableArray *out = [NSMutableArray array];
    for (UIWindow *window in G6AllWindows()) G6CollectVisible(window, cls, out);
    return out;
}

// Mọi chữ hiện trong một view (nhãn, tiêu đề nút), nối bằng « | »
static NSString *G6TextsOf(UIView *view) {
    NSMutableArray *texts = [NSMutableArray array];
    NSMutableArray *labels = [NSMutableArray array];
    G6CollectVisible(view, [UILabel class], labels);
    for (UILabel *label in labels) {
        if (label.text.length) [texts addObject:label.text];
    }
    if ([view isKindOfClass:[UIButton class]]) {
        NSString *title = [(UIButton *)view titleForState:UIControlStateNormal];
        if (title.length && ![texts containsObject:title]) [texts addObject:title];
    }
    return [texts componentsJoinedByString:@" | "];
}

static BOOL G6TextMatches(NSString *texts, NSString *wanted) {
    for (NSString *part in [texts componentsSeparatedByString:@" | "]) {
        if ([part isEqualToString:wanted]) return YES;
    }
    return NO;
}

static UISwitch *G6SwitchOfCell(UITableViewCell *cell) {
    if (!cell) return nil;
    NSMutableArray *switches = [NSMutableArray array];
    G6CollectVisible(cell, [UISwitch class], switches);
    if (switches.count) return switches.firstObject;
    // Ô chưa xếp con (vừa tạo): công tắc còn là accessoryView chưa gắn vào ô
    return [cell.accessoryView isKindOfClass:[UISwitch class]] ? (UISwitch *)cell.accessoryView : nil;
}

// Ô có chữ `text`: tìm trong các ô đang hiện trước, rồi hỏi nguồn dữ liệu của từng bảng (ô chưa cuộn tới)
static UITableViewCell *G6FindCell(NSString *text, UITableView **tableOut, NSIndexPath **pathOut) {
    for (UITableView *table in G6VisibleViews([UITableView class])) {
        for (UITableViewCell *cell in table.visibleCells) {
            if (G6TextMatches(G6TextsOf(cell), text)) {
                *tableOut = table;
                *pathOut = [table indexPathForCell:cell];
                return cell;
            }
        }
    }
    for (UITableView *table in G6VisibleViews([UITableView class])) {
        NSInteger sections = [table numberOfSections];
        for (NSInteger s = 0; s < sections; s++) {
            NSInteger rows = [table numberOfRowsInSection:s];
            for (NSInteger r = 0; r < rows; r++) {
                NSIndexPath *path = [NSIndexPath indexPathForRow:r inSection:s];
                if ([table cellForRowAtIndexPath:path]) continue;  // đang hiện: đã xét ở trên
                UITableViewCell *cell = [table.dataSource tableView:table cellForRowAtIndexPath:path];
                if (cell && G6TextMatches(G6TextsOf(cell), text)) {
                    [table scrollToRowAtIndexPath:path atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
                    [table layoutIfNeeded];
                    *tableOut = table;
                    *pathOut = path;
                    // Ô thật đang hiện sau khi cuộn (ô vừa xin từ nguồn dữ liệu chỉ là bản rời để so chữ)
                    for (UITableViewCell *shown in table.visibleCells) {
                        if (G6TextMatches(G6TextsOf(shown), text)) return shown;
                    }
                    return [table cellForRowAtIndexPath:path] ?: cell;
                }
            }
        }
    }
    return nil;
}

// ui → ui.txt: mọi thứ bấm được đang hiện (dòng của bảng kèm trạng thái công tắc, nút, nút chọn đoạn, thanh trượt)
static void G6UIList(void) {
    NSMutableString *out = [NSMutableString string];
    for (UINavigationBar *bar in G6VisibleViews([UINavigationBar class])) {
        [out appendFormat:@"[thanh] %@\n", bar.topItem.title ?: @"-"];
    }
    for (UITableView *table in G6VisibleViews([UITableView class])) {
        [out appendFormat:@"[bảng %@ %@]\n", table.style == UITableViewStyleGrouped ? @"nhóm" : @"thường", NSStringFromCGRect(table.frame)];
        for (UITableViewCell *cell in table.visibleCells) {
            UISwitch *sw = G6SwitchOfCell(cell);
            [out appendFormat:@"  [dòng] %@%@\n", G6TextsOf(cell), sw ? (sw.on ? @"  (công tắc: BẬT)" : @"  (công tắc: TẮT)") : @""];
        }
    }
    for (UIControl *control in G6VisibleViews([UIControl class])) {
        if ([control isKindOfClass:[UISwitch class]]) continue;
        if ([control isKindOfClass:[UISegmentedControl class]]) {
            UISegmentedControl *seg = (UISegmentedControl *)control;
            NSMutableArray *titles = [NSMutableArray array];
            for (NSUInteger i = 0; i < seg.numberOfSegments; i++) [titles addObject:[seg titleForSegmentAtIndex:i] ?: @"(hình)"];
            [out appendFormat:@"[chọn đoạn] %@ → đang chọn %ld\n", [titles componentsJoinedByString:@" / "], (long)seg.selectedSegmentIndex];
        } else if ([control isKindOfClass:[UISlider class]]) {
            [out appendFormat:@"[thanh trượt] %.2f\n", ((UISlider *)control).value];
        } else {
            NSString *texts = G6TextsOf(control);
            if (texts.length) [out appendFormat:@"[nút %@] %@\n", NSStringFromClass(control.class), texts];
        }
    }
    G6WriteResult(@"ui.txt", out);
}

// specs → specs.txt: các dòng của app Cài đặt (PSTableCell) đang có trong mọi bảng đang hiện: mã mục, lớp ô, cỡ biểu tượng.
// Lưu luôn ảnh biểu tượng của từng mục vào thư mục icons/ (tên = mã mục) để xem.
static void G6SpecsList(void) {
    NSMutableString *out = [NSMutableString string];
    NSString *dir = [G6DebugDir() stringByAppendingPathComponent:@"icons"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    for (UITableView *table in G6VisibleViews([UITableView class])) {
        [out appendFormat:@"[bảng %@]\n", NSStringFromCGRect(table.frame)];
        NSInteger sections = [table numberOfSections];
        for (NSInteger s = 0; s < sections; s++) {
            NSInteger rows = [table numberOfRowsInSection:s];
            for (NSInteger r = 0; r < rows; r++) {
                NSIndexPath *path = [NSIndexPath indexPathForRow:r inSection:s];
                UITableViewCell *cell = [table cellForRowAtIndexPath:path] ?: [table.dataSource tableView:table cellForRowAtIndexPath:path];
                id spec = [cell respondsToSelector:@selector(specifier)] ? [cell performSelector:@selector(specifier)] : nil;
                NSString *ident = [spec respondsToSelector:@selector(identifier)] ? [spec performSelector:@selector(identifier)] : nil;
                UIImage *icon = cell.imageView.image;
                [out appendFormat:@"  %ld.%ld  %@  «%@»  %@  biểu tượng %@\n", (long)s, (long)r, ident ?: @"-", cell.textLabel.text ?: @"",
                                  NSStringFromClass(cell.class), icon ? NSStringFromCGSize(icon.size) : @"-"];
                if (icon && ident.length) {
                    NSString *name = [[ident componentsSeparatedByCharactersInSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]]
                        componentsJoinedByString:@"_"];
                    [UIImagePNGRepresentation(icon) writeToFile:[dir stringByAppendingPathComponent:[name stringByAppendingString:@".png"]]
                                                     atomically:YES];
                }
            }
        }
    }
    G6WriteResult(@"specs.txt", out);
}

// select <chữ>: chọn dòng của bảng như người dùng bấm vào
static void G6UISelect(NSString *text) {
    UITableView *table = nil;
    NSIndexPath *path = nil;
    UITableViewCell *cell = G6FindCell(text, &table, &path);
    if (!cell || !path) {
        G6Log(@"[thử] không thấy dòng «%@»", text);
        return;
    }
    id<UITableViewDelegate> delegate = table.delegate;
    if ([delegate respondsToSelector:@selector(tableView:willSelectRowAtIndexPath:)]) {
        path = [delegate tableView:table willSelectRowAtIndexPath:path];
        if (!path) {
            G6Log(@"[thử] dòng «%@» không cho chọn", text);
            return;
        }
    }
    [table selectRowAtIndexPath:path animated:NO scrollPosition:UITableViewScrollPositionNone];
    if ([delegate respondsToSelector:@selector(tableView:didSelectRowAtIndexPath:)]) [delegate tableView:table didSelectRowAtIndexPath:path];
    G6Log(@"[thử] đã chọn dòng «%@» (nhóm %ld dòng %ld)", text, (long)path.section, (long)path.row);
}

// toggle <chữ>: gạt công tắc của dòng có chữ đó. Dòng vừa được cuộn tới có thể chưa kịp dựng ô thật (công tắc chưa có):
// thử lại một lần sau một nhịp.
static void G6UIToggleTry(NSString *text, BOOL retried) {
    UITableView *table = nil;
    NSIndexPath *path = nil;
    UISwitch *sw = G6SwitchOfCell(G6FindCell(text, &table, &path));
    if (!sw && path && !retried) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            G6UIToggleTry(text, YES);
        });
        return;
    }
    if (!sw) {
        G6Log(@"[thử] không thấy công tắc ở dòng «%@»", text);
        return;
    }
    [sw setOn:!sw.on animated:YES];
    [sw sendActionsForControlEvents:UIControlEventValueChanged];
    G6Log(@"[thử] gạt «%@» → %@", text, sw.on ? @"BẬT" : @"TẮT");
}

static void G6UIToggle(NSString *text) {
    G6UIToggleTry(text, NO);
}

// press <chữ>: bấm nút (nút trên thanh, nút hộp thoại, nút thường) có chữ đó.
// press @<x>,<y>: bấm nút nằm ở toạ độ giao diện (x, y) — cho nút chỉ có hình. Toạ độ tính trong view gốc đã xoay của cửa sổ
// chính (cùng hệ với khung in ở `dump`, cộng 20 điểm thanh trạng thái nếu view gốc bắt đầu dưới thanh).
static void G6UIPress(NSString *text) {
    if ([text hasPrefix:@"@"]) {
        NSArray *xy = [[text substringFromIndex:1] componentsSeparatedByString:@","];
        UIWindow *window = [UIApplication sharedApplication].keyWindow ?: [[UIApplication sharedApplication].windows firstObject];
        UIView *root = window.subviews.firstObject;
        if (xy.count != 2 || !root) {
            G6Log(@"[thử] press @x,y: sai cú pháp hoặc không có view gốc");
            return;
        }
        CGPoint point = CGPointMake([xy[0] floatValue], [xy[1] floatValue]);
        UIControl *best = nil;
        CGFloat bestArea = CGFLOAT_MAX;
        for (UIControl *control in G6VisibleViews([UIControl class])) {
            if ([control isKindOfClass:[UISwitch class]] || !control.enabled) continue;
            CGRect r = [control convertRect:control.bounds toView:root];
            CGFloat area = r.size.width * r.size.height;
            if (CGRectContainsPoint(r, point) && area < bestArea) {
                best = control;
                bestArea = area;
            }
        }
        if (!best) {
            G6Log(@"[thử] không có nút nào ở (%.0f, %.0f)", point.x, point.y);
            return;
        }
        [best sendActionsForControlEvents:UIControlEventTouchUpInside];
        G6Log(@"[thử] đã bấm nút ở (%.0f, %.0f) (%@)", point.x, point.y, NSStringFromClass(best.class));
        return;
    }
    for (UIControl *control in G6VisibleViews([UIControl class])) {
        if ([control isKindOfClass:[UISwitch class]] || !G6TextMatches(G6TextsOf(control), text)) continue;
        [control sendActionsForControlEvents:UIControlEventTouchUpInside];
        G6Log(@"[thử] đã bấm nút «%@» (%@)", text, NSStringFromClass(control.class));
        return;
    }
    G6Log(@"[thử] không thấy nút «%@»", text);
}

// seg <n>: chọn đoạn thứ n của nút chọn đoạn đầu tiên đang hiện
static void G6UISegment(NSString *arg) {
    UISegmentedControl *seg = [G6VisibleViews([UISegmentedControl class]) firstObject];
    NSInteger index = arg.integerValue;
    if (!seg || index < 0 || index >= (NSInteger)seg.numberOfSegments) {
        G6Log(@"[thử] không có nút chọn đoạn / đoạn %ld", (long)index);
        return;
    }
    seg.selectedSegmentIndex = index;
    [seg sendActionsForControlEvents:UIControlEventValueChanged];
    G6Log(@"[thử] chọn đoạn %ld", (long)index);
}

// row <n> [lớp bảng]: chọn dòng thứ n đang hiện như người dùng bấm vào — không cần biết chữ của dòng
static void G6UIRow(NSString *arg) {
    NSArray *parts = [arg componentsSeparatedByString:@" "];
    NSInteger index = parts.count ? [parts[0] integerValue] : 0;
    Class want = parts.count > 1 ? NSClassFromString(parts[1]) : Nil;
    UITableView *table = nil;
    for (UITableView *t in G6VisibleViews([UITableView class])) {
        if (want && ![t isKindOfClass:want]) continue;
        table = t;
        break;
    }
    NSArray *paths = [table indexPathsForVisibleRows];
    if (!table || index < 0 || index >= (NSInteger)paths.count) {
        G6Log(@"[thử] row: không có bảng / dòng %ld (bảng %@ có %lu dòng đang hiện)", (long)index, table ? NSStringFromClass(table.class) : @"-",
              (unsigned long)paths.count);
        return;
    }
    NSIndexPath *path = paths[index];
    id<UITableViewDelegate> delegate = table.delegate;
    if ([delegate respondsToSelector:@selector(tableView:willSelectRowAtIndexPath:)]) {
        path = [delegate tableView:table willSelectRowAtIndexPath:path];
        if (!path) {
            G6Log(@"[thử] row: dòng %ld không cho chọn", (long)index);
            return;
        }
    }
    [table selectRowAtIndexPath:path animated:NO scrollPosition:UITableViewScrollPositionNone];
    if ([delegate respondsToSelector:@selector(tableView:didSelectRowAtIndexPath:)]) [delegate tableView:table didSelectRowAtIndexPath:path];
    G6Log(@"[thử] row: đã chọn dòng %ld / %lu của %@", (long)index, (unsigned long)paths.count, NSStringFromClass(table.class));
}

// ---- gtap: «cú chạm giả» cho view tự bắt cử chỉ ----
// Lớp cử chỉ giả tạo lúc chạy (không khai lớp tĩnh: công cụ thử nằm trong cả hai thư viện, lớp tĩnh sẽ trùng tên): trả vị trí
// đã cho, trạng thái «đã nhận ra».
static char kFakePointKey, kFakeViewKey;

static CGPoint g6fake_locationInView(id self, SEL _cmd, UIView *view) {
    UIView *target = objc_getAssociatedObject(self, &kFakeViewKey);
    CGPoint p = [objc_getAssociatedObject(self, &kFakePointKey) CGPointValue];
    return (view && target) ? [target convertPoint:p toView:view] : p;
}

static CGPoint g6fake_locationOfTouch(id self, SEL _cmd, NSUInteger index, UIView *view) {
    return g6fake_locationInView(self, _cmd, view);
}

static NSInteger g6fake_state(id self, SEL _cmd) {
    return UIGestureRecognizerStateEnded;
}

static id g6fake_view(id self, SEL _cmd) {
    return objc_getAssociatedObject(self, &kFakeViewKey);
}

static NSUInteger g6fake_numberOfTouches(id self, SEL _cmd) {
    return 1;
}

static Class G6FakeTapClass(void) {
    static Class cls;
    if (cls) return cls;
#if G6_SB
    const char *name = "G6SBDebugFakeTap";
#else
    const char *name = "G6UIDebugFakeTap";
#endif
    Class made = objc_allocateClassPair([UITapGestureRecognizer class], name, 0);
    if (!made) return cls = objc_getClass(name);
    class_addMethod(made, @selector(locationInView:), (IMP)g6fake_locationInView, "{CGPoint=ff}12@0:4@8");
    class_addMethod(made, @selector(locationOfTouch:inView:), (IMP)g6fake_locationOfTouch, "{CGPoint=ff}16@0:4I8@12");
    class_addMethod(made, @selector(state), (IMP)g6fake_state, "i8@0:4");
    class_addMethod(made, @selector(view), (IMP)g6fake_view, "@8@0:4");
    class_addMethod(made, @selector(numberOfTouches), (IMP)g6fake_numberOfTouches, "I8@0:4");
    objc_registerClassPair(made);
    return cls = made;
}

static void G6UIGestureTap(NSString *arg) {
    NSArray *parts = [arg componentsSeparatedByString:@" "];
    if (parts.count != 3 || ![parts[2] hasPrefix:@"@"]) {
        G6Log(@"[thử] gtap <lớp view> <hàm> @x,y");
        return;
    }
    Class cls = NSClassFromString(parts[0]);
    SEL sel = NSSelectorFromString(parts[1]);
    NSArray *xy = [[parts[2] substringFromIndex:1] componentsSeparatedByString:@","];
    UIView *target = cls ? [G6VisibleViews(cls) firstObject] : nil;
    UIWindow *window = [UIApplication sharedApplication].keyWindow ?: [[UIApplication sharedApplication].windows firstObject];
    UIView *root = window.subviews.firstObject;
    if (!target || ![target respondsToSelector:sel] || xy.count != 2 || !root) {
        G6Log(@"[thử] gtap: không có view đang hiện thuộc lớp %@ nhận «%@»", parts[0], parts[1]);
        return;
    }
    CGPoint point = [root convertPoint:CGPointMake([xy[0] floatValue], [xy[1] floatValue]) toView:target];
    UIGestureRecognizer *fake = [[G6FakeTapClass() alloc] initWithTarget:nil action:NULL];
    objc_setAssociatedObject(fake, &kFakeViewKey, target, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(fake, &kFakePointKey, [NSValue valueWithCGPoint:point], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    ((void (*)(id, SEL, id))objc_msgSend)(target, sel, fake);
    G6Log(@"[thử] gtap: đã gọi -[%@ %@] tại (%.0f, %.0f) của view", parts[0], parts[1], point.x, point.y);
}

// vcsend <lớp controller> <hàm>
static UIViewController *G6FindController(UIView *view, Class cls, int depth) {
    UIResponder *next = view.nextResponder;
    if ([next isKindOfClass:cls]) return (UIViewController *)next;
    if (depth <= 0) return nil;
    for (UIView *sub in view.subviews) {
        UIViewController *found = G6FindController(sub, cls, depth - 1);
        if (found) return found;
    }
    return nil;
}

// Tìm view đầu tiên thuộc lớp `cls` trong cây view (sâu tối đa `depth` tầng)
static UIView *G6FindViewOfClass(UIView *root, Class cls, int depth) {
    if ([root isKindOfClass:cls]) return root;
    if (depth <= 0) return nil;
    for (UIView *sub in root.subviews) {
        UIView *found = G6FindViewOfClass(sub, cls, depth - 1);
        if (found) return found;
    }
    return nil;
}

// send <Lớp> <hàm lớp trả đối tượng dùng chung | view> <hàm> [0|1] — gọi một hàm không tham số (hoặc một tham số cờ / đối
// tượng nil) của một đối tượng dùng chung («send SBAwayController sharedAwayController _batteryStatusChanged») hay của view
// đầu tiên thuộc lớp đó đang nằm trong cửa sổ («send SBAwayView view updateChargingView»). Chỉ để tái hiện sự kiện lúc thử.
// imgdump: ghi ảnh của mọi UIImageView trong app (kể cả view đang ẩn) thành tệp PNG img-<n>.png + danh sách imgdump.txt —
// để biết app dựng giao diện từ những hình nào khi hình không đi qua +[UIImage imageNamed:] (nạp từ tệp nib)
static void G6ImageDump(void) {
    NSMutableArray *found = [NSMutableArray array];
    for (UIWindow *w in G6AllWindows()) G6CollectViews(w, [UIImageView class], found);
    NSMutableString *out = [NSMutableString string];
    NSMutableArray *seen = [NSMutableArray array];
    int n = 0;
    for (UIImageView *view in found) {
        UIImage *image = view.image;
        if (!image) continue;
        NSUInteger index = [seen indexOfObjectIdenticalTo:image];
        if (index == NSNotFound) {
            [seen addObject:image];
            index = seen.count - 1;
            NSString *name = [NSString stringWithFormat:@"img-%lu.png", (unsigned long)index];
            [UIImagePNGRepresentation(image) writeToFile:[G6DebugDir() stringByAppendingPathComponent:name] atomically:YES];
            n++;
        }
        CGRect inWindow = [view convertRect:view.bounds toView:nil];
        [out appendFormat:@"img-%lu  ảnh %.0f×%.0f  view %@ khung cửa sổ %@ ẩn=%d mờ=%.2f cha=%@\n", (unsigned long)index, image.size.width,
                          image.size.height, NSStringFromClass([view class]), NSStringFromCGRect(inWindow), view.hidden, view.alpha,
                          NSStringFromClass([view.superview class])];
    }
    G6WriteResult(@"imgdump.txt", out);
    G6Log(@"[thử] imgdump: %d ảnh", n);
}

// tab <n>: chọn thẻ thứ n (0 = thẻ đầu) của thanh thẻ đang hiện, như người dùng chạm vào thẻ
static void G6UITab(NSString *arg) {
    UITabBar *bar = nil;
    for (UIWindow *w in G6AllWindows()) {
        bar = (UITabBar *)G6FindViewOfClass(w, [UITabBar class], 24);
        if (bar) break;
    }
    id controller = bar.delegate;
    if (![controller isKindOfClass:[UITabBarController class]]) {
        G6Log(@"[thử] tab: không thấy thanh thẻ do UITabBarController quản");
        return;
    }
    UITabBarController *tabs = controller;
    NSUInteger index = (NSUInteger)MAX(0, arg.intValue);
    if (index >= tabs.viewControllers.count) {
        G6Log(@"[thử] tab: chỉ có %lu thẻ", (unsigned long)tabs.viewControllers.count);
        return;
    }
    tabs.selectedIndex = index;
    G6Log(@"[thử] tab: đã chọn thẻ %lu / %lu", (unsigned long)index, (unsigned long)tabs.viewControllers.count);
}

static void G6Send(NSString *arg) {
    NSArray *parts = [arg componentsSeparatedByString:@" "];
    if (parts.count < 3) {
        G6Log(@"[thử] send: cần <lớp> <hàm lớp | view> <hàm> [0|1]");
        return;
    }
    Class cls = NSClassFromString(parts[0]);
    id target = nil;
    if ([parts[1] isEqualToString:@"view"]) {
        for (UIWindow *w in G6AllWindows()) {
            target = cls ? G6FindViewOfClass(w, cls, 24) : nil;
            if (target) break;
        }
    } else {
        SEL shared = NSSelectorFromString(parts[1]);
        if (cls && [cls respondsToSelector:shared] && [[cls methodSignatureForSelector:shared] methodReturnType][0] == '@') {
            target = ((id (*)(id, SEL))objc_msgSend)(cls, shared);
        }
    }
    SEL sel = NSSelectorFromString(parts[2]);
    if (!target || ![target respondsToSelector:sel]) {
        G6Log(@"[thử] send: không có đối tượng %@ nhận «%@»", parts[0], parts[2]);
        return;
    }
    NSMethodSignature *sig = [target methodSignatureForSelector:sel];
    char ret = [sig methodReturnType][0];
    if (sig.numberOfArguments == 2 && (ret == 'c' || ret == 'B')) {
        G6Log(@"[thử] send: -[%@ %@] trả %d", NSStringFromClass([target class]), parts[2], ((BOOL (*)(id, SEL))objc_msgSend)(target, sel));
        return;
    } else if (sig.numberOfArguments == 2 && ret == 'f') {
        G6Log(@"[thử] send: -[%@ %@] trả %.3f", NSStringFromClass([target class]), parts[2], ((float (*)(id, SEL))objc_msgSend)(target, sel));
        return;
    } else if (sig.numberOfArguments == 2) {
        ((void (*)(id, SEL))objc_msgSend)(target, sel);
    } else if (sig.numberOfArguments == 3 && ([sig getArgumentTypeAtIndex:2][0] == 'c' || [sig getArgumentTypeAtIndex:2][0] == 'B')) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(target, sel, parts.count > 3 && [parts[3] intValue] != 0);
    } else if (sig.numberOfArguments == 3 && [sig getArgumentTypeAtIndex:2][0] == '@') {
        // Tham số đối tượng: chuỗi ở phần thứ tư (không có = nil)
        ((void (*)(id, SEL, id))objc_msgSend)(target, sel, parts.count > 3 ? parts[3] : nil);
    } else if (sig.numberOfArguments == 4 && [sig getArgumentTypeAtIndex:2][0] == '@' &&
               ([sig getArgumentTypeAtIndex:3][0] == 'c' || [sig getArgumentTypeAtIndex:3][0] == 'B')) {
        // (chuỗi, cờ) — vd setText:needsFormat:
        ((void (*)(id, SEL, id, BOOL))objc_msgSend)(target, sel, parts.count > 3 ? parts[3] : nil, parts.count > 4 && [parts[4] intValue] != 0);
    } else {
        G6Log(@"[thử] send: «%@» nhận tham số kiểu khác — không gọi", parts[2]);
        return;
    }
    G6Log(@"[thử] send: đã gọi -[%@ %@]", NSStringFromClass([target class]), parts[2]);
}

static void G6VCSend(NSString *arg) {
    NSArray *parts = [arg componentsSeparatedByString:@" "];
    Class cls = parts.count >= 2 ? NSClassFromString(parts[0]) : Nil;
    SEL sel = parts.count >= 2 ? NSSelectorFromString(parts[1]) : NULL;
    UIViewController *found = nil;
    if (cls && [cls isSubclassOfClass:[UIViewController class]]) {
        for (UIWindow *w in G6AllWindows()) {
            found = G6FindController(w, cls, 24);
            if (found) break;
        }
    }
    if (!found || !sel || ![found respondsToSelector:sel]) {
        G6Log(@"[thử] vcsend: không có controller %@ đang hiện nhận «%@»", parts.count ? parts[0] : @"?", parts.count > 1 ? parts[1] : @"?");
        return;
    }
    NSMethodSignature *sig = [found methodSignatureForSelector:sel];
    if (sig.numberOfArguments == 2) {
        ((void (*)(id, SEL))objc_msgSend)(found, sel);
    } else if (sig.numberOfArguments == 3 && [sig getArgumentTypeAtIndex:2][0] == '@') {
        ((void (*)(id, SEL, id))objc_msgSend)(found, sel, nil);
    } else if (sig.numberOfArguments == 3 && ([sig getArgumentTypeAtIndex:2][0] == 'c' || [sig getArgumentTypeAtIndex:2][0] == 'B')) {
        // Tham số cờ: lấy từ từ thứ ba của lệnh (mặc định 0), vd «vcsend UINavigationController dismissModalViewControllerAnimated: 0»
        ((void (*)(id, SEL, BOOL))objc_msgSend)(found, sel, parts.count > 2 && [parts[2] intValue] != 0);
    } else {
        G6Log(@"[thử] vcsend: «%@» nhận tham số kiểu khác — không gọi", parts[1]);
        return;
    }
    G6Log(@"[thử] vcsend: đã gọi -[%@ %@]", NSStringFromClass([found class]), parts[1]);
}

// balloons 1|0 (app Tin nhắn): đặt một tấm thử lên trên giao diện, trong đó là bốn bong bóng chữ của ChatKit (hai phía × hai màu
// gửi đi) mang CHỮ THỬ — để soi hình dạng, mép, đuôi, màu chữ của bong bóng mà không phải nhìn tin nhắn thật của người dùng.
// Tấm thử đục, nằm trong view gốc (đã xoay) tại (200, 100) cỡ 640×380: ảnh chụp chỉ cần cắt đúng khung đó.
static UIView *gBalloonPanel;

static void G6TestBalloons(NSString *arg) {
    [gBalloonPanel removeFromSuperview];
    gBalloonPanel = nil;
    if (!arg.intValue) return;
    Class cls = objc_getClass("CKTextBalloonView");
    UIWindow *window = [UIApplication sharedApplication].keyWindow ?: [[UIApplication sharedApplication].windows firstObject];
    UIView *root = window.subviews.firstObject;
    SEL setOrientation = NSSelectorFromString(@"setOrientation:"), setColor = NSSelectorFromString(@"setOutgoingColor:");
    SEL setText = NSSelectorFromString(@"setAttributedText:");
    if (!cls || !root || ![cls instancesRespondToSelector:setOrientation] || ![cls instancesRespondToSelector:setText]) {
        G6Log(@"[thử] balloons: app này không có CKTextBalloonView");
        return;
    }
    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(200, 100, 640, 380)];
    panel.backgroundColor = G6IsDark() ? [UIColor blackColor] : [UIColor whiteColor];
    CGFloat y = 14;
    int index = 0;
    for (int orientation = 0; orientation < 2; orientation++) {
        for (int color = 0; color < 2; color++) {
            UIImageView *balloon = [[cls alloc] initWithFrame:CGRectZero];
            ((void (*)(id, SEL, int))objc_msgSend)(balloon, setOrientation, orientation);
            if ([balloon respondsToSelector:setColor]) ((void (*)(id, SEL, int))objc_msgSend)(balloon, setColor, color);
            NSString *text = index % 2 ? [NSString stringWithFormat:@"Bóng thử %d", index + 1]
                                       : [NSString stringWithFormat:@"Bóng thử %d — Glass 6 kiểm hình dạng, mép và đuôi của bong bóng; dòng này đủ dài để xuống hàng.", index + 1];
            ((void (*)(id, SEL, id))objc_msgSend)(balloon, setText, [[NSAttributedString alloc] initWithString:text]);
            CGSize size = [balloon sizeThatFits:CGSizeMake(330, 2000)];
            if (size.width < 20 || size.height < 20) size = CGSizeMake(200, 40);
            balloon.frame = CGRectMake(orientation == 0 ? 14 : 640 - 14 - size.width, y, size.width, size.height);
            [panel addSubview:balloon];
            [balloon setNeedsLayout];
            UIImage *image = balloon.image;
            G6Log(@"[thử] balloons: bóng %d hướng %d màu %d cỡ %@, ảnh %@ mép %@", index + 1, orientation, color, NSStringFromCGSize(size),
                  image ? NSStringFromCGSize(image.size) : @"-", image ? NSStringFromUIEdgeInsets(image.capInsets) : @"-");
            y += size.height + 12;
            index++;
        }
    }
    [root addSubview:panel];
    gBalloonPanel = panel;
}

// back: lùi một màn trên thanh điều hướng có nhiều màn nhất đang hiện
static void G6UIBack(void) {
    UINavigationBar *best = nil;
    for (UINavigationBar *bar in G6VisibleViews([UINavigationBar class])) {
        if (bar.items.count > 1 && bar.items.count > best.items.count) best = bar;
    }
    UIResponder *responder = best;
    while (responder && ![responder isKindOfClass:[UINavigationController class]]) responder = responder.nextResponder;
    if (!responder) {
        // Bộ điều hướng tự viết (app Ảnh trên iPad: WInteractiveNavigationController không phải UINavigationController): nó là
        // delegate của thanh và có cùng tên hàm lùi
        id delegate = best.delegate;
        SEL plain = NSSelectorFromString(@"popViewController");
        if (best && [delegate respondsToSelector:@selector(popViewControllerAnimated:)]) {
            [(UINavigationController *)delegate popViewControllerAnimated:NO];
            G6Log(@"[thử] đã lùi một màn (qua %@)", NSStringFromClass([delegate class]));
            return;
        }
        if (best && [delegate respondsToSelector:plain]) {
            ((void (*)(id, SEL))objc_msgSend)(delegate, plain);
            G6Log(@"[thử] đã lùi một màn (qua -[%@ popViewController])", NSStringFromClass([delegate class]));
            return;
        }
        G6Log(@"[thử] không có màn nào để lùi");
        return;
    }
    [(UINavigationController *)responder popViewControllerAnimated:NO];
    G6Log(@"[thử] đã lùi một màn");
}

// Nguồn dữ liệu của bảng thường trong cửa sổ trưng bày
@interface G6GalleryData : NSObject <UITableViewDataSource, UIPickerViewDataSource, UIPickerViewDelegate>
@property (nonatomic) BOOL custom;
@end

// Bánh xe mà app tự cấp view cho từng dòng (chữ sẫm do app đặt) — để soi trường hợp Glass 6 không được đổi màu chữ
@interface G6GalleryCustomPicker : NSObject <UIPickerViewDataSource, UIPickerViewDelegate>
@end

@implementation G6GalleryCustomPicker
- (NSInteger)numberOfComponentsInPickerView:(UIPickerView *)pickerView {
    return 1;
}
- (NSInteger)pickerView:(UIPickerView *)pickerView numberOfRowsInComponent:(NSInteger)component {
    return 8;
}
- (UIView *)pickerView:(UIPickerView *)pickerView viewForRow:(NSInteger)row forComponent:(NSInteger)component reusingView:(UIView *)view {
    UIView *box = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 200, 40)];
    UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(8, 10, 20, 20)];
    dot.backgroundColor = [UIColor colorWithHue:row / 8.0 saturation:0.8 brightness:0.9 alpha:1];
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(40, 0, 160, 40)];
    label.backgroundColor = [UIColor clearColor];
    label.textColor = [UIColor blackColor];
    label.font = [UIFont boldSystemFontOfSize:18];
    label.text = [NSString stringWithFormat:@"Dòng tự vẽ %ld", (long)row + 1];
    [box addSubview:dot];
    [box addSubview:label];
    return box;
}
@end

// View tự vẽ chữ (giả một ô của app tự vẽ nội dung) — Glass 6 không đổi màu được loại này
@interface G6GalleryDrawn : UIView
@end

@implementation G6GalleryDrawn
- (void)drawRect:(CGRect)rect {
    [[UIColor blackColor] set];
    [@"Ô tự vẽ chữ (app tự vẽ)" drawAtPoint:CGPointMake(10, 12) withFont:[UIFont boldSystemFontOfSize:17]];
}
@end

@implementation G6GalleryData

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.custom ? 6 : 5;
}

// Bánh xe chuẩn hai cột (gallery 4)
- (NSInteger)numberOfComponentsInPickerView:(UIPickerView *)pickerView {
    return 2;
}

- (NSInteger)pickerView:(UIPickerView *)pickerView numberOfRowsInComponent:(NSInteger)component {
    return component == 0 ? 12 : 5;
}

- (NSString *)pickerView:(UIPickerView *)pickerView titleForRow:(NSInteger)row forComponent:(NSInteger)component {
    return component == 0 ? [NSString stringWithFormat:@"Tháng %ld", (long)row + 1] : @[@"Một", @"Hai", @"Ba", @"Bốn", @"Năm"][row];
}

// Để soi thanh tiêu đề nhóm của bảng thường
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @"Tiêu đề nhóm";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSInteger row = indexPath.row;
    UITableViewCellStyle style = row == 1 ? UITableViewCellStyleSubtitle : (row == 2 ? UITableViewCellStyleValue1 : UITableViewCellStyleDefault);
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:style reuseIdentifier:nil];
    if (row == 5) {
        G6GalleryDrawn *drawn = [[G6GalleryDrawn alloc] initWithFrame:cell.contentView.bounds];
        drawn.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        drawn.backgroundColor = [UIColor whiteColor];
        [cell.contentView addSubview:drawn];
        return cell;
    }
    cell.textLabel.text = @[@"Ô thường", @"Ô có dòng phụ", @"Ô có giá trị", @"Ô có dấu chọn", @"Ô có mũi tên"][row];
    if (row == 1) cell.detailTextLabel.text = @"Dòng phụ màu xám";
    if (row == 2) cell.detailTextLabel.text = @"Giá trị";
    if (row == 3) cell.accessoryType = UITableViewCellAccessoryCheckmark;
    if (row == 4) cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

@end

// ---- gallery 1|0: cửa sổ trưng mọi thành phần UIKit chuẩn (thanh, nút trên thanh có hình, thanh thẻ, ô tìm kiếm, nút điều
// khiển) để soi kiểu dáng ở một chỗ — chạy trong app nào cũng được ----
static UIWindow *gGallery;

static void G6Gallery(NSString *arg) {
    gGallery.hidden = YES;
    gGallery = nil;
    if (arg.intValue == 0) return;
    CGRect screen = [UIScreen mainScreen].bounds;
    UIWindow *window = [[UIWindow alloc] initWithFrame:screen];
    window.windowLevel = UIWindowLevelAlert - 1;
    // Cùng chiều với giao diện đang hiện
    UIInterfaceOrientation o = [UIApplication sharedApplication].statusBarOrientation;
    CGFloat w = screen.size.width, h = screen.size.height;
    UIView *root = [[UIView alloc] initWithFrame:screen];
    if (UIInterfaceOrientationIsLandscape(o)) {
        root.bounds = CGRectMake(0, 0, h, w);
        root.center = CGPointMake(w / 2, h / 2);
        root.transform = CGAffineTransformMakeRotation(o == UIInterfaceOrientationLandscapeLeft ? -M_PI_2 : M_PI_2);
        CGFloat t = w;
        w = h;
        h = t;
    } else if (o == UIInterfaceOrientationPortraitUpsideDown) {
        root.transform = CGAffineTransformMakeRotation(M_PI);
    }
    root.backgroundColor = G6IsDark() ? [UIColor colorWithWhite:0.05 alpha:1] : [UIColor colorWithWhite:0.95 alpha:1];
    [window addSubview:root];
    CGFloat y = 20;
    // Màn hẹp (iPhone đứng): các thành phần xếp chồng thành nhiều hàng ngắn, khoảng cách hẹp hơn
    BOOL narrow = w < 500;
    CGFloat gap = narrow ? 8 : 16, gapBig = narrow ? 10 : 24;
    // gallery 4 trên màn hẹp: chỉ thanh điều hướng + hai bánh xe (không đủ chỗ cho phần còn lại)
    BOOL pickersOnly = narrow && arg.intValue == 4;

    UINavigationBar *nav = [[UINavigationBar alloc] initWithFrame:CGRectMake(0, y, w, 44)];
    UINavigationItem *back = [[UINavigationItem alloc] initWithTitle:@"Trước"];
    UINavigationItem *item = [[UINavigationItem alloc] initWithTitle:narrow ? @"Tiêu đề" : @"Tiêu đề thanh"];
    item.rightBarButtonItems = narrow ? @[
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:nil action:NULL],
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:nil action:NULL],
    ] : @[
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:nil action:NULL],
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:nil action:NULL],
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:nil action:NULL],
        [[UIBarButtonItem alloc] initWithTitle:@"Sửa" style:UIBarButtonItemStyleBordered target:nil action:NULL],
    ];
    [nav setItems:@[back, item] animated:NO];
    [root addSubview:nav];
    y += 44 + gap;

    if (!pickersOnly) {
    UIToolbar *toolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, y, w, 44)];
    UIBarButtonItem *flex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:NULL];
    toolbar.items = narrow ? @[
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemTrash target:nil action:NULL], flex,
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCompose target:nil action:NULL], flex,
        [[UIBarButtonItem alloc] initWithTitle:@"Chữ" style:UIBarButtonItemStyleBordered target:nil action:NULL], flex,
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemBookmarks target:nil action:NULL], flex,
        [[UIBarButtonItem alloc] initWithTitle:@"Xong" style:UIBarButtonItemStyleDone target:nil action:NULL],
    ] : @[
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemTrash target:nil action:NULL], flex,
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCompose target:nil action:NULL], flex,
        [[UIBarButtonItem alloc] initWithTitle:@"Chữ thường" style:UIBarButtonItemStyleBordered target:nil action:NULL], flex,
        [[UIBarButtonItem alloc] initWithTitle:@"Trơn" style:UIBarButtonItemStylePlain target:nil action:NULL], flex,
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemBookmarks target:nil action:NULL], flex,
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemPlay target:nil action:NULL], flex,
        [[UIBarButtonItem alloc] initWithTitle:@"Xong" style:UIBarButtonItemStyleDone target:nil action:NULL],
    ];
    [root addSubview:toolbar];
    y += 44 + gap;

    UISearchBar *search = [[UISearchBar alloc] initWithFrame:CGRectMake(0, y, w, 44)];
    search.placeholder = @"Tìm kiếm";
    if (arg.intValue == 2) search.text = @"Chữ đã gõ";
    [root addSubview:search];
    y += 44 + gapBig;

    UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:@[@"Một", @"Hai", @"Ba"]];
    seg.frame = CGRectMake(20, y, narrow ? w - 40 : 300, 30);
    seg.selectedSegmentIndex = 1;
    [root addSubview:seg];
    if (narrow) y += 30 + gapBig;
    UISegmentedControl *bar = [[UISegmentedControl alloc] initWithItems:narrow ? @[@"Thanh", @"Hai"] : @[@"Kiểu thanh", @"Hai"]];
    bar.segmentedControlStyle = UISegmentedControlStyleBar;
    bar.frame = narrow ? CGRectMake(10, y, 132, 30) : CGRectMake(340, y, 220, 30);
    bar.selectedSegmentIndex = 0;
    [root addSubview:bar];
    UISwitch *on = [[UISwitch alloc] initWithFrame:CGRectMake(narrow ? 152 : 580, y, 0, 0)];
    on.on = YES;
    [root addSubview:on];
    [root addSubview:[[UISwitch alloc] initWithFrame:CGRectMake(narrow ? 236 : 680, y, 0, 0)]];
    y += 30 + gapBig;

    UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(20, y, narrow ? w - 40 : 300, 24)];
    slider.value = 0.4;
    [root addSubview:slider];
    if (narrow) y += 24 + gapBig;
    UIProgressView *progress = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    progress.frame = narrow ? CGRectMake(20, y + 8, 150, 9) : CGRectMake(340, y + 8, 220, 9);
    progress.progress = 0.6;
    [root addSubview:progress];
    UIStepper *stepper = [[UIStepper alloc] initWithFrame:CGRectMake(narrow ? 200 : 580, y, 0, 0)];
    [root addSubview:stepper];
    y += 30 + gapBig;

    UIButton *button = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    button.frame = CGRectMake(20, y, narrow ? 130 : 200, 40);
    [button setTitle:@"Nút bo góc" forState:UIControlStateNormal];
    [root addSubview:button];
    UITextField *field = [[UITextField alloc] initWithFrame:narrow ? CGRectMake(160, y + 4, 140, 31) : CGRectMake(240, y + 4, 240, 31)];
    field.borderStyle = UITextBorderStyleRoundedRect;
    field.placeholder = @"Ô nhập";
    if (arg.intValue == 2) field.text = @"Chữ đã gõ";
    [root addSubview:field];
    if (narrow) y += 40 + gap;
    UIActivityIndicatorView *spin = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    spin.center = CGPointMake(narrow ? 40 : 520, y + (narrow ? 14 : 20));
    [spin startAnimating];
    [root addSubview:spin];
    UIPageControl *pages = [[UIPageControl alloc] initWithFrame:narrow ? CGRectMake(80, y, 160, 28) : CGRectMake(560, y, 160, 36)];
    pages.numberOfPages = 5;
    pages.currentPage = 1;
    [root addSubview:pages];
    y += narrow ? 28 + gap : 40 + 24;
    }

    UITabBar *tab = [[UITabBar alloc] initWithFrame:CGRectMake(0, h - 49, w, 49)];
    tab.items = @[
        [[UITabBarItem alloc] initWithTabBarSystemItem:UITabBarSystemItemFavorites tag:0],
        [[UITabBarItem alloc] initWithTabBarSystemItem:UITabBarSystemItemSearch tag:1],
        [[UITabBarItem alloc] initWithTabBarSystemItem:UITabBarSystemItemHistory tag:2],
        [[UITabBarItem alloc] initWithTabBarSystemItem:UITabBarSystemItemMore tag:3],
    ];
    tab.selectedItem = tab.items[1];
    [root addSubview:tab];

    // Bảng thường với các kiểu ô chuẩn (để soi chế độ tối của danh sách không chia nhóm); gallery 3: thêm một ô tự vẽ
    static G6GalleryData *data;
    if (!data) data = [G6GalleryData new];
    data.custom = arg.intValue == 3;
    if (arg.intValue == 4) {
        // gallery 4: thay bảng bằng ba bánh xe — chuẩn hai cột, chọn ngày giờ, và loại app tự cấp view cho từng dòng
        static G6GalleryCustomPicker *customData;
        if (!customData) customData = [G6GalleryCustomPicker new];
        UIPickerView *plain = [[UIPickerView alloc] initWithFrame:narrow ? CGRectMake(0, y, w, 216) : CGRectMake(20, y, 300, 216)];
        plain.dataSource = data;
        plain.delegate = data;
        plain.showsSelectionIndicator = YES;
        [plain selectRow:3 inComponent:0 animated:NO];
        [root addSubview:plain];
        UIDatePicker *date = [[UIDatePicker alloc] initWithFrame:narrow ? CGRectMake(0, y + 224, w, 216) : CGRectMake(340, y, 320, 216)];
        date.datePickerMode = UIDatePickerModeDateAndTime;
        [root addSubview:date];
        // Bánh xe thứ ba (app tự cấp view cho từng dòng): màn hẹp không đủ chỗ
        if (!narrow) {
            UIPickerView *custom = [[UIPickerView alloc] initWithFrame:CGRectMake(680, y, 300, 216)];
            custom.dataSource = customData;
            custom.delegate = customData;
            custom.showsSelectionIndicator = YES;
            [custom selectRow:2 inComponent:0 animated:NO];
            [root addSubview:custom];
        }
    } else {
        UITableView *table = [[UITableView alloc] initWithFrame:CGRectMake(20, y, w - 40, h - 49 - y - 16) style:UITableViewStylePlain];
        table.dataSource = data;
        table.rowHeight = 44;
        [root addSubview:table];
    }

    window.hidden = NO;
    gGallery = window;
    G6Log(@"[thử] cửa sổ trưng bày %.0f×%.0f", w, h);
}

// ---- cafilter list | <loại>[,<loại>…] [lớp view] | off: thử bộ lọc màu của CoreAnimation (CAFilter, lớp riêng) ----
// Gắn bộ lọc vào lớp vẽ của view đầu tiên thuộc lớp đã nêu (mặc định: cửa sổ trưng bày hoặc cửa sổ chính) để xem trình dựng
// hình của máy có áp bộ lọc hay không. «hue» = xoay màu 180° (colorHueRotate với inputAngle = π).
static UIView *gFilteredView, *gBackdropProbe;

static void G6CAFilter(NSString *arg) {
    Class filterClass = objc_getClass("CAFilter");
    SEL types = NSSelectorFromString(@"filterTypes"), make = NSSelectorFromString(@"filterWithType:");
    if (![filterClass respondsToSelector:types] || ![filterClass respondsToSelector:make]) {
        G6Log(@"[thử] cafilter: không có lớp CAFilter");
        return;
    }
    if ([arg isEqualToString:@"list"]) {
        G6Log(@"[thử] cafilter: %@", [((id (*)(id, SEL))objc_msgSend)(filterClass, types) componentsJoinedByString:@", "]);
        return;
    }
    gFilteredView.layer.filters = nil;
    gFilteredView = nil;
    [(UIWindow *)objc_getAssociatedObject(gBackdropProbe, "g6-probe-window") setHidden:YES];
    [gBackdropProbe removeFromSuperview];
    gBackdropProbe = nil;
    if (arg.length == 0 || [arg isEqualToString:@"off"]) return;
    NSArray *parts = [arg componentsSeparatedByString:@" "];
    UIView *target = gGallery ?: [UIApplication sharedApplication].keyWindow;
    // «bg <loại…>»: đặt một ô gần trong suốt giữa view đích và gắn bộ lọc vào backgroundFilters của nó — xem trình dựng hình có
    // lọc thứ NẰM SAU lớp đó không (nếu có: làm mờ nền sống được)
    // «bgclip»: như «bg» nhưng ô thử cắt theo khung bo góc (masksToBounds); «bgwin»: ô thử là một cửa sổ riêng nằm trên mọi thứ
    // (thử lọc cả nội dung của tiến trình khác nằm dưới)
    BOOL clip = [parts[0] isEqualToString:@"bgclip"], win = [parts[0] isEqualToString:@"bgwin"];
    BOOL behind = clip || win || [parts[0] isEqualToString:@"bg"];
    if (behind) parts = [parts subarrayWithRange:NSMakeRange(1, parts.count - 1)];
    if (parts.count == 0) return;
    if (parts.count > 1) {
        NSMutableArray *found = [NSMutableArray array];
        for (UIWindow *w in G6AllWindows()) G6CollectViews(w, NSClassFromString(parts[1]), found);
        target = found.firstObject;
    }
    if (!target) {
        G6Log(@"[thử] cafilter: không thấy view để gắn");
        return;
    }
    NSMutableArray *filters = [NSMutableArray array];
    for (NSString *name in [parts[0] componentsSeparatedByString:@","]) {
        BOOL hue = [name isEqualToString:@"hue"], blur = [name isEqualToString:@"blur"];
        id filter = ((id (*)(id, SEL, id))objc_msgSend)(filterClass, make, hue ? @"colorHueRotate" : (blur ? @"gaussianBlur" : name));
        if (!filter) {
            G6Log(@"[thử] cafilter: không tạo được «%@»", name);
            continue;
        }
        if (hue) [filter setValue:@(M_PI) forKey:@"inputAngle"];
        // «blur» = gaussianBlur bán kính 8 điểm
        if (blur) [filter setValue:@8 forKey:@"inputRadius"];
        [filters addObject:filter];
    }
    if (behind) {
        CGRect b = target.bounds;
        gBackdropProbe = [[UIView alloc] initWithFrame:CGRectMake(CGRectGetMidX(b) - 220, CGRectGetMidY(b) - 150, 440, 300)];
        gBackdropProbe.backgroundColor = [UIColor colorWithRed:1 green:1 blue:1 alpha:0.08];
        gBackdropProbe.layer.borderColor = [UIColor redColor].CGColor;
        gBackdropProbe.layer.borderWidth = 2;
        gBackdropProbe.userInteractionEnabled = NO;
        gBackdropProbe.layer.backgroundFilters = filters;
        if (clip || win) {
            gBackdropProbe.layer.cornerRadius = 40;
            gBackdropProbe.layer.masksToBounds = YES;
        }
        if (win) {
            UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(120, 260, 440, 300)];
            window.windowLevel = UIWindowLevelAlert + 5;
            window.userInteractionEnabled = NO;
            window.backgroundColor = [UIColor clearColor];
            gBackdropProbe.frame = window.bounds;
            [window addSubview:gBackdropProbe];
            window.hidden = NO;
            objc_setAssociatedObject(gBackdropProbe, "g6-probe-window", window, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            G6Log(@"[thử] cafilter: cửa sổ thử với %lu bộ lọc ở backgroundFilters", (unsigned long)filters.count);
            return;
        }
        [target addSubview:gBackdropProbe];
        G6Log(@"[thử] cafilter: ô thử (viền đỏ) với %lu bộ lọc ở backgroundFilters trên %@", (unsigned long)filters.count,
              NSStringFromClass([target class]));
        return;
    }
    target.layer.filters = filters;
    gFilteredView = target;
    G6Log(@"[thử] cafilter: gắn %lu bộ lọc vào %@", (unsigned long)filters.count, NSStringFromClass([target class]));
}

// ---- focus 1|0: đưa con trỏ vào ô nhập đầu tiên đang hiện (bàn phím bật lên) / bỏ ra ----
static void G6Focus(NSString *arg) {
    NSMutableArray *fields = [NSMutableArray array];
    for (UIWindow *w in G6AllWindows()) G6CollectViews(w, [UITextField class], fields);
    UITextField *field = nil;
    for (UITextField *f in fields) {
        // Ô tìm kiếm của thanh tìm kiếm để sau: ưu tiên ô nhập thường
        if (!field || [field isKindOfClass:NSClassFromString(@"UISearchBarTextField")]) field = f;
    }
    if (!field) {
        G6Log(@"[thử] focus: không có ô nhập nào");
        return;
    }
    if (arg.intValue) [field becomeFirstResponder];
    else [field.window endEditing:YES];
    G6Log(@"[thử] focus: %@ %@", arg.intValue ? @"vào" : @"ra khỏi", NSStringFromClass([field class]));
}

// ---- popover 1|0, sheet 1|0: mở bảng nổi / bảng chọn thử ở giữa màn hình ----
static UIPopoverController *gTestPopover;
static UIActionSheet *gTestSheet;

static UIView *G6FrontView(void) {
    UIWindow *window = [UIApplication sharedApplication].keyWindow ?: [[UIApplication sharedApplication].windows firstObject];
    return window.rootViewController.view ?: window;
}

static void G6TestPopover(NSString *arg) {
    [gTestPopover dismissPopoverAnimated:NO];
    gTestPopover = nil;
    if (arg.intValue == 0) return;
    UITableViewController *table = [[UITableViewController alloc] initWithStyle:UITableViewStyleGrouped];
    table.title = @"Bảng nổi thử";
    table.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:nil action:NULL];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:table];
    nav.contentSizeForViewInPopover = CGSizeMake(320, 260);
    gTestPopover = [[UIPopoverController alloc] initWithContentViewController:nav];
    UIView *view = G6FrontView();
    // arg: 1 = mũi tên chỉ lên, 2 = chỉ xuống, 3 = chỉ sang trái
    CGRect anchor = CGRectMake(CGRectGetMidX(view.bounds) - 20, arg.intValue == 2 ? CGRectGetMaxY(view.bounds) - 120 : 90, 40, 30);
    UIPopoverArrowDirection direction = arg.intValue == 2 ? UIPopoverArrowDirectionDown
                                                          : (arg.intValue == 3 ? UIPopoverArrowDirectionLeft : UIPopoverArrowDirectionUp);
    if (arg.intValue == 3) anchor = CGRectMake(120, CGRectGetMidY(view.bounds), 30, 30);
    [gTestPopover presentPopoverFromRect:anchor inView:view permittedArrowDirections:direction animated:NO];
    G6Log(@"[thử] bảng nổi: lớp khung %@", NSStringFromClass(gTestPopover.popoverBackgroundViewClass));
}

static void G6TestSheet(NSString *arg) {
    [gTestSheet dismissWithClickedButtonIndex:gTestSheet.cancelButtonIndex animated:NO];
    gTestSheet = nil;
    if (arg.intValue == 0) return;
    gTestSheet = [[UIActionSheet alloc] initWithTitle:@"Bảng chọn thử"
                                             delegate:nil
                                    cancelButtonTitle:@"Huỷ"
                               destructiveButtonTitle:@"Xoá"
                                    otherButtonTitles:@"Việc thứ nhất", @"Việc thứ hai", nil];
    UIView *view = G6FrontView();
    [gTestSheet showFromRect:CGRectMake(CGRectGetMidX(view.bounds) - 20, 90, 40, 30) inView:view animated:NO];
}

// appearance <0|1|2>: đặt chế độ sáng / tối / tự động như người dùng chọn trong Cài đặt — sửa đúng một khoá trong tệp cấu hình
// (giữ nguyên mọi khoá khác, dù tệp là XML hay nhị phân) rồi báo cho mọi tiến trình
static void G6SetAppearanceDebug(NSString *arg) {
    NSString *path = @"/var/mobile/Library/Preferences/" G6_PREFS_DOMAIN ".plist";
    NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithContentsOfFile:path] ?: [NSMutableDictionary dictionary];
    prefs[@"appearance"] = @(MAX(0, MIN(2, arg.intValue)));
    BOOL ok = [prefs writeToFile:path atomically:YES];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR(G6_PREFS_NOTE), NULL, NULL, YES);
    G6Log(@"[thử] appearance = %@ (%@)", prefs[@"appearance"], ok ? @"đã ghi" : @"KHÔNG ghi được");
}

static void G6RunCommand(void) {
    struct stat st;
    if (stat(kCmdPath.fileSystemRepresentation, &st) != 0 || st.st_uid != 0) {
        // Mọi tiến trình có công cụ thử đều nhận thông báo: chỉ SpringBoard ghi lời báo này, kẻo mỗi app một dòng
        if (objc_getClass("SpringBoard")) G6Log(@"[thử] bỏ qua: không có cmd.txt hoặc tệp không do root ghi");
        return;
    }
    NSString *text = [NSString stringWithContentsOfFile:kCmdPath encoding:NSUTF8StringEncoding error:NULL];
    NSString *line = [[text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]] firstObject];
    line = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    // Đích của lệnh: «@Tên lệnh…» cho đúng tiến trình đó, không có «@» là cho SpringBoard
    NSString *me = [[NSProcessInfo processInfo] processName];
    if ([line hasPrefix:@"@"]) {
        NSRange first = [line rangeOfString:@" "];
        NSString *target = first.location == NSNotFound ? [line substringFromIndex:1]
                                                        : [line substringWithRange:NSMakeRange(1, first.location - 1)];
        if (![target isEqualToString:me]) return;
        line = first.location == NSNotFound ? @"" : [[line substringFromIndex:first.location + 1]
                                                        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    } else if (![me isEqualToString:@"SpringBoard"]) {
        return;
    }
    NSRange sp = [line rangeOfString:@" "];
    NSString *cmd = sp.location == NSNotFound ? line : [line substringToIndex:sp.location];
    NSString *arg = sp.location == NSNotFound ? @"" : [[line substringFromIndex:sp.location + 1]
                                                          stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    G6Log(@"[thử] lệnh «%@»", line);
    @try {
        if ([cmd isEqualToString:@"dump"]) G6Dump();
        else if ([cmd isEqualToString:@"classes"]) G6Classes(arg);
        else if ([cmd isEqualToString:@"methods"]) G6Methods(arg);
        else if ([cmd isEqualToString:@"inspect"]) G6Inspect(arg);
        else if ([cmd isEqualToString:@"orient"]) G6Orient(arg);
        else if ([cmd isEqualToString:@"panel"]) G6Panel(arg);
        else if ([cmd isEqualToString:@"bench"]) G6Bench();
        else if ([cmd isEqualToString:@"goto"]) G6GotoPage(arg);
        else if ([cmd isEqualToString:@"lock"]) G6Lock();
        else if ([cmd isEqualToString:@"sim"]) G6SIMProbe();
        else if ([cmd isEqualToString:@"hud"]) G6ShowHUD();
#if G6_SB
        else if ([cmd isEqualToString:@"cc"]) G6ControlCenterSetVisible(arg.intValue != 0, YES);
        else if ([cmd isEqualToString:@"cctest"]) G6ControlCenterDebug(arg);
        else if ([cmd isEqualToString:@"cards"]) G6CardSwitcherDebug(arg);
        else if ([cmd isEqualToString:@"assist"]) G6AssistDebug(arg);
        else if ([cmd isEqualToString:@"perf"]) G6Log(@"[thử] %@", G6PerfDebugState());
        else if ([cmd isEqualToString:@"statusbar"]) G6Log(@"[thử] %@", G6StatusBarDebugState());
#endif
        else if ([cmd isEqualToString:@"sbitems"]) G6Log(@"[thử] thanh trạng thái (tiến trình này): %@", G6StatusItemsDescribe());
        else if ([cmd isEqualToString:@"pull"]) G6PullFromTop(arg);
        else if ([cmd isEqualToString:@"alert"]) G6ShowAlert(arg);
        else if ([cmd isEqualToString:@"nc"]) G6ShowNC(arg);
        else if ([cmd isEqualToString:@"banner"]) G6ShowBanner(arg);
        else if ([cmd isEqualToString:@"wake"]) G6Wake();
        else if ([cmd isEqualToString:@"lockbulletin"]) G6LockBulletin(arg);
        else if ([cmd isEqualToString:@"labels"]) G6Labels();
        else if ([cmd isEqualToString:@"edit"]) G6HomeAction(@"edit", arg);
        else if ([cmd isEqualToString:@"folder"]) G6HomeAction(@"folder", arg);
        else if ([cmd isEqualToString:@"switcher"]) G6HomeAction(@"switcher", arg);
        else if ([cmd isEqualToString:@"iconprobe"]) G6IconProbe(arg);
        else if ([cmd isEqualToString:@"iconshot"]) G6IconShot(arg);
        else if ([cmd isEqualToString:@"gallery"]) G6Gallery(arg);
        else if ([cmd isEqualToString:@"cafilter"]) G6CAFilter(arg);
        else if ([cmd isEqualToString:@"focus"]) G6Focus(arg);
        else if ([cmd isEqualToString:@"popover"]) G6TestPopover(arg);
        else if ([cmd isEqualToString:@"sheet"]) G6TestSheet(arg);
        else if ([cmd isEqualToString:@"appearance"]) G6SetAppearanceDebug(arg);
        else if ([cmd isEqualToString:@"ui"]) G6UIList();
        else if ([cmd isEqualToString:@"specs"]) G6SpecsList();
        else if ([cmd isEqualToString:@"select"]) G6UISelect(arg);
        else if ([cmd isEqualToString:@"toggle"]) G6UIToggle(arg);
        else if ([cmd isEqualToString:@"press"]) G6UIPress(arg);
        else if ([cmd isEqualToString:@"seg"]) G6UISegment(arg);
        else if ([cmd isEqualToString:@"back"]) G6UIBack();
        else if ([cmd isEqualToString:@"row"]) G6UIRow(arg);
        else if ([cmd isEqualToString:@"gtap"]) G6UIGestureTap(arg);
        else if ([cmd isEqualToString:@"vcsend"]) G6VCSend(arg);
        else if ([cmd isEqualToString:@"send"]) G6Send(arg);
        else if ([cmd isEqualToString:@"tab"]) G6UITab(arg);
        else if ([cmd isEqualToString:@"imgdump"]) G6ImageDump();
        else if ([cmd isEqualToString:@"tap"] || [cmd isEqualToString:@"drag"]) G6DebugTouch(cmd, arg);
        else if ([cmd isEqualToString:@"balloons"]) G6TestBalloons(arg);
#if G6_SB
        else if ([cmd isEqualToString:@"svc"]) G6SvcDebug(arg);
        else if ([cmd isEqualToString:@"otacheck"]) G6OTACheckForce();
#endif
        else if ([cmd isEqualToString:@"uid"]) G6Log(@"[thử] uid %d euid %d", getuid(), geteuid());
        else G6Log(@"[thử] lệnh lạ");
    } @catch (NSException *e) {
        G6Log(@"[thử] lệnh «%@» ném ngoại lệ: %@", line, e);
    }
    G6Log(@"[thử] xong «%@»", line);
}

static void G6DebugNotified(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object,
                            CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        G6RunCommand();
    });
}

// ---- Ghi tên các hình app nạp bằng +[UIImage imageNamed:] ----
// Bật bằng tệp cờ /var/tmp/vn.glass6/imglog (tạo TRƯỚC khi mở app, vì hình được nạp ngay lúc app dựng giao diện):
//   touch /var/tmp/vn.glass6/imglog; mở app; đọc các dòng «[hình]» trong nhật ký; rm tệp cờ.
// Mỗi tên ghi một lần, kèm cỡ ảnh (điểm). Dùng để biết app tự vẽ giao diện bằng những hình nào (Đợt 3).
static id (*orig_imageNamed)(id, SEL, NSString *);
static id repl_imageNamed(id self, SEL _cmd, NSString *name) {
    UIImage *image = orig_imageNamed(self, _cmd, name);
    @try {
        static NSMutableSet *seen;
        if (!seen) seen = [NSMutableSet set];
        if ([name isKindOfClass:[NSString class]] && ![seen containsObject:name]) {
            [seen addObject:name];
            G6Log(@"[hình] «%@» %.0f×%.0f%@", name, image.size.width, image.size.height, image ? @"" : @" (không có)");
        }
    } @catch (NSException *e) {
    }
    return image;
}

void G6DebugStart(void) {
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, G6DebugNotified, CFSTR(G6_DEBUG_NOTE),
                                    NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    G6Log(@"[thử] nghe lệnh qua " G6_DEBUG_NOTE);
    // Chỉ việc của runtime (đổi hàm): hàm này chạy trong hàm khởi tạo của thư viện, trước UIApplicationMain
    if (access("/var/tmp/vn.glass6/imglog", F_OK) == 0) {
        Method m = class_getClassMethod([UIImage class], @selector(imageNamed:));
        if (m) {
            orig_imageNamed = (id (*)(id, SEL, NSString *))method_setImplementation(m, (IMP)repl_imageNamed);
            G6Log(@"[thử] ghi tên hình được nạp (imglog)");
        }
    }
}

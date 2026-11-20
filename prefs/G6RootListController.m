// Bảng điều khiển của Glass 6 trong Cài đặt (Cài đặt › Glass 6). Công tắc / thanh trượt khai trong Resources/Root.plist;
// lớp này chỉ lo phần động: dòng trạng thái (đọc G6_DIR/status.plist do tweak ghi), đặt lại bộ gác, khởi động lại SpringBoard,
// kiểm / tải / cài bản mới (OTA).
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <dirent.h>
#import <spawn.h>
#import <unistd.h>

#import <objc/runtime.h>

#import "G6Device.h"
#import "G6Guard.h"
#import "G6Lang.h"
#import "G6Log.h"
#import "G6OTA.h"

extern char **environ;

@interface G6RootListController : PSListController
@end

// ── Hộp thoại có khối xử lý nút bấm ──────────────────────────────────────────────────────────────────────────────────────
// Đối tượng nhận nút gắn theo hộp thoại (sống tới khi hộp thoại mất): rời màn Glass 6 lúc hộp thoại còn hiện cũng không sao
// (delegate của UIAlertView không giữ đối tượng).
@interface G6AlertBlock : NSObject <UIAlertViewDelegate>
@property (nonatomic, copy) void (^handler)(BOOL confirmed);
@end

@implementation G6AlertBlock

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (self.handler) self.handler(buttonIndex != alertView.cancelButtonIndex);
}

@end

static char kAlertBlockKey;

// `cancel` và `other` đều nil = hộp thoại không nút (báo «đang làm…», tự gỡ bằng mã)
static UIAlertView *G6ShowAlert(NSString *title, NSString *message, NSString *cancel, NSString *other, void (^handler)(BOOL confirmed)) {
    G6AlertBlock *delegate = [G6AlertBlock new];
    delegate.handler = handler;
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title message:message delegate:delegate cancelButtonTitle:cancel otherButtonTitles:other, nil];
    objc_setAssociatedObject(alert, &kAlertBlockKey, delegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [alert show];
    return alert;
}

static void G6DismissAlert(UIAlertView *alert) {
    [alert dismissWithClickedButtonIndex:alert.cancelButtonIndex animated:YES];
}

// ── Cập nhật OTA (docs/THIET-KE.md mục 10) ───────────────────────────────────────────────────────────────────────────────
// Bảng Cài đặt chỉ điều phối: glass6ctl hỏi GitHub và tải gói + chữ ký; g6update (quyền root) kiểm chữ ký số rồi cài và khởi
// động lại SpringBoard. g6update chỉ nhận lời gọi từ tiến trình Cài đặt / SpringBoard nên phải chạy nó từ đây.

// Đang kiểm / tải / cài (một việc một lúc, kể cả khi người dùng rời màn rồi quay lại)
static BOOL gOTABusy;
// Ghi chú phát hành trong hộp thoại: cắt ngắn (bản đầy đủ nằm ở chú thích của nhóm «Có bản mới»)
static const NSUInteger kAlertNotesMax = 300;

static NSString *G6SizeText(long long bytes) {
    NSString *text = [NSString stringWithFormat:@"%.1f MB", bytes / 1048576.0];
    return G6LDecimal([text stringByReplacingOccurrencesOfString:@"." withString:@","]);
}

// PSSpecifier của iOS 6 chưa chắc có setButtonAction: → ghi thẳng biến `action` (cách của Root.plist: khoá «action»)
static void G6SetButtonAction(PSSpecifier *spec, SEL action) {
    Ivar ivar = class_getInstanceVariable([PSSpecifier class], "action");
    if (ivar) *(SEL *)((char *)(__bridge void *)spec + ivar_getOffset(ivar)) = action;
}

static void G6OTAStartDownload(NSString *latest, G6RootListController *controller) {
    if (gOTABusy) return;
    if (!G6OTAHelperReady()) {
        G6ShowAlert(G6L(@"Không tự cập nhật được"), G6OTAInstallErrorText(access(G6_OTA_HELPER, X_OK) == 0 ? 66 : -1), @"OK", nil, nil);
        return;
    }
    gOTABusy = YES;
    __weak G6RootListController *weakController = controller;
    G6OTATask *task = [G6OTATask new];
    UIAlertView *progress = G6ShowAlert([NSString stringWithFormat:G6L(@"Đang tải bản %@…"), latest], @"0%", G6L(@"Huỷ"), nil, ^(BOOL confirmed) {
        [task cancel];
    });
    __weak UIAlertView *weakProgress = progress;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        __block NSDictionary *result = nil;
        int code = G6OTARun(@[@"update", @"download", @"--current", @G6_VERSION], task, ^(NSString *line) {
            if (![line hasPrefix:@"progress "]) {
                NSDictionary *d = G6OTAParse(line);
                if (d) result = d;
                return;
            }
            NSArray *parts = [line componentsSeparatedByString:@" "];
            if (parts.count < 3) return;
            long long done = [parts[1] longLongValue], total = [parts[2] longLongValue];
            NSString *text = total > 0 ? [NSString stringWithFormat:@"%d%% (%@ / %@)", (int)(done * 100 / total), G6SizeText(done), G6SizeText(total)]
                                       : G6SizeText(done);
            dispatch_async(dispatch_get_main_queue(), ^{
                weakProgress.message = text;
            });
        });
        dispatch_async(dispatch_get_main_queue(), ^{
            G6Log(@"cập nhật: tải bản %@ → mã %d%@", latest, code, task.cancelled ? @" (đã huỷ)" : @"");
            if (task.cancelled) {
                gOTABusy = NO;
                // Bỏ phần tải dở
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
                    G6OTARun(@[@"update", @"clean"], nil, nil);
                });
                return;
            }
            G6DismissAlert(progress);
            if (![result[@"ok"] boolValue]) {
                gOTABusy = NO;
                G6ShowAlert(G6L(@"Cập nhật không thành công"), G6OTAErrorText(result ?: @{@"error" : @"tool"}), @"OK", nil, nil);
                return;
            }
            UIAlertView *installing = G6ShowAlert([NSString stringWithFormat:G6L(@"Đang cài bản %@…"), latest],
                                                  G6L(@"Màn hình chính sẽ tự khởi động lại sau ít giây."), nil, nil, nil);
            NSString *deb = result[@"deb"], *sig = result[@"sig"];
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                int rc = G6OTAInstallPackage(deb, sig);
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (rc != 0) {
                        gOTABusy = NO;
                        G6DismissAlert(installing);
                        G6ShowAlert(G6L(@"Cập nhật không thành công"), G6OTAInstallErrorText(rc), @"OK", nil, nil);
                        return;
                    }
                    // g6update đã kiểm xong và đang cài ở nền; SpringBoard khởi động lại thì Cài đặt cũng bị đóng theo. Nếu vì
                    // lý do gì app vẫn còn sống thì gỡ hộp thoại (nó không có nút) kẻo kẹt màn hình.
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(90 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        gOTABusy = NO;
                        G6DismissAlert(installing);
                        [weakController reloadSpecifiers];
                    });
                });
            });
        });
    });
}

// Có bản mới: hỏi người dùng rồi mới tải
static void G6OTAOffer(NSDictionary *found, G6RootListController *controller) {
    NSString *latest = [found[@"latest"] isKindOfClass:[NSString class]] ? found[@"latest"] : @"?";
    NSString *title = [NSString stringWithFormat:G6L(@"Có bản mới %@"), latest];
    if (![found[@"installable"] boolValue]) {
        G6ShowAlert(title, G6OTAErrorText(@{@"error" : @"unsigned"}), @"OK", nil, nil);
        return;
    }
    NSString *notes = [found[@"notes"] isKindOfClass:[NSString class]] ? found[@"notes"] : @"";
    if (notes.length > kAlertNotesMax) notes = [[notes substringToIndex:kAlertNotesMax] stringByAppendingString:@"…"];
    NSMutableString *message = [NSMutableString stringWithFormat:G6L(@"Đang dùng bản %@."), @G6_VERSION];
    if (notes.length) [message appendFormat:@"\n\n%@", notes];
    [message appendFormat:@"\n\n%@", G6L(@"Cài xong, màn hình chính tự khởi động lại.")];
    __weak G6RootListController *weakController = controller;
    G6ShowAlert(title, message, G6L(@"Để sau"), G6L(@"Cập nhật"), ^(BOOL confirmed) {
        if (confirmed) G6OTAStartDownload(latest, weakController);
    });
}

@implementation G6RootListController

// Nhóm «Có bản mới» đặt trên đầu bảng khi lượt kiểm gần nhất (tay, hoặc SpringBoard tự kiểm) thấy bản mới hơn bản đang chạy
- (NSArray *)g6UpdateBanner {
    NSDictionary *found = G6OTAPending(@G6_VERSION);
    if (!found) return nil;
    NSString *latest = found[@"latest"];
    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:[NSString stringWithFormat:G6L(@"Có bản mới %@"), latest]];
    NSString *notes = found[@"notes"];
    if ([notes isKindOfClass:[NSString class]] && notes.length) [group setProperty:notes forKey:@"footerText"];
    PSSpecifier *button = [PSSpecifier preferenceSpecifierNamed:[NSString stringWithFormat:G6L(@"Cập nhật lên bản %@"), latest]
                                                         target:self
                                                            set:NULL
                                                            get:NULL
                                                         detail:Nil
                                                           cell:PSButtonCell
                                                           edit:Nil];
    G6SetButtonAction(button, @selector(installFound:));
    return @[group, button];
}

- (void)installFound:(PSSpecifier *)specifier {
    NSDictionary *found = G6OTAPending(@G6_VERSION);
    if (found) G6OTAOffer(found, self);
    else [self reloadSpecifiers];
}

- (void)checkUpdate:(PSSpecifier *)specifier {
    if (gOTABusy) return;
    gOTABusy = YES;
    UIAlertView *wait = G6ShowAlert(G6L(@"Đang kiểm bản mới…"), nil, nil, nil, nil);
    NSDate *shown = [NSDate date];
    __weak G6RootListController *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSDictionary *result = G6OTACheck(@G6_VERSION);
        // Hộp «đang kiểm» hiện ít nhất một giây: gỡ ngay lúc nó còn đang bay vào thì chớp rất khó chịu
        NSTimeInterval wait_ = MAX(0, 1.0 + [shown timeIntervalSinceNow]);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(wait_ * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            gOTABusy = NO;
            G6DismissAlert(wait);
            [weakSelf reloadSpecifiers];
            if (![result[@"ok"] boolValue]) {
                G6ShowAlert(G6L(@"Không kiểm được bản mới"), G6OTAErrorText(result), @"OK", nil, nil);
            } else if (!G6OTANewer(result[@"latest"], @G6_VERSION)) {
                G6ShowAlert(G6L(@"Đang dùng bản mới nhất"), [NSString stringWithFormat:@"Glass 6 %@", @G6_VERSION], @"OK", nil, nil);
            } else {
                G6OTAOffer(result, weakSelf);
            }
        });
    });
}

// Dịch một mục khai trong Root.plist: tên, chú thích cuối nhóm, tên các lựa chọn của mục dạng danh sách
static void G6LocalizeSpecifier(PSSpecifier *spec) {
    if (spec.name.length) spec.name = G6L(spec.name);
    NSString *footer = [spec propertyForKey:@"footerText"];
    if ([footer isKindOfClass:[NSString class]] && footer.length) [spec setProperty:G6L(footer) forKey:@"footerText"];
    for (int pass = 0; pass < 2; pass++) {
        NSDictionary *titles = pass == 0 ? spec.titleDictionary : spec.shortTitleDictionary;
        if (![titles isKindOfClass:[NSDictionary class]] || titles.count == 0) continue;
        NSMutableDictionary *translated = [NSMutableDictionary dictionaryWithCapacity:titles.count];
        [titles enumerateKeysAndObjectsUsingBlock:^(id value, id title, BOOL *stop) {
            translated[value] = [title isKindOfClass:[NSString class]] ? G6L(title) : title;
        }];
        if (pass == 0) spec.titleDictionary = translated;
        else spec.shortTitleDictionary = translated;
    }
}

// Tên dễ đọc của mẫu máy đang chạy
static NSString *G6DeviceTitle(void) {
    NSString *machine = @(g6_device_machine());
    switch (g6_device_kind()) {
        case G6DevicePadMini1:
            return [NSString stringWithFormat:@"iPad mini 1 (%@)", machine];
        case G6DevicePhone5:
            return [NSString stringWithFormat:@"iPhone 5 (%@)", machine];
        default:
            return machine.length ? machine : @"?";
    }
}

- (id)deviceText:(PSSpecifier *)specifier {
    return G6DeviceTitle();
}

- (id)specifiers {
    if (!_specifiers && !g6_device_supported()) {
        // Mẫu máy chưa được làm và thử: không hiện công tắc nào, chỉ nói rõ lý do
        PSSpecifier *group = [PSSpecifier groupSpecifierWithName:G6L(@"Máy chưa được hỗ trợ")];
        NSString *why = [NSString stringWithFormat:G6L(@"Glass 6 chưa có giao diện cho máy này (%@). Bản này chỉ chạy trên iPad mini 1 và "
                                                         @"iPhone 5 dùng iOS 6; trên máy khác Glass 6 không thay đổi gì. Các mẫu máy khác "
                                                         @"sẽ được bổ sung ở bản sau."),
                                                   G6DeviceTitle()];
        [group setProperty:why forKey:@"footerText"];
        _specifiers = (id) @[group];
        return _specifiers;
    }
    if (!_specifiers) {
        // Mục có khoá `g6Device` («ipad» / «iphone») trong Root.plist chỉ hiện trên loại máy đó
        NSString *mine = g6_device_is_phone() ? @"iphone" : @"ipad";
        NSMutableArray *list = [NSMutableArray array];
        for (PSSpecifier *spec in [self loadSpecifiersFromPlistName:@"Root" target:self]) {
            NSString *only = [spec propertyForKey:@"g6Device"];
            if ([only isKindOfClass:[NSString class]] && ![only isEqualToString:mine]) continue;
            // Chú thích cuối nhóm viết riêng cho iPhone (`g6FooterPhone`) thay cho bản chung
            NSString *phoneFooter = [spec propertyForKey:@"g6FooterPhone"];
            if (g6_device_is_phone() && [phoneFooter isKindOfClass:[NSString class]]) [spec setProperty:phoneFooter forKey:@"footerText"];
            G6LocalizeSpecifier(spec);
            [list addObject:spec];
        }
        NSArray *banner = [self g6UpdateBanner];
        if (banner) [list insertObjects:banner atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, banner.count)]];
        _specifiers = (id)list;
    }
    return _specifiers;
}

// Đổi «Ngôn ngữ»: dựng lại cả bảng bằng ngôn ngữ mới
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    [super setPreferenceValue:value specifier:specifier];
    if ([[specifier propertyForKey:@"key"] isEqual:@"language"]) {
        G6LangReload();
        [self reloadSpecifiers];
    }
}

- (NSDictionary *)g6Status {
    return [NSDictionary dictionaryWithContentsOfFile:@G6_DIR "/status.plist"] ?: @{};
}

// Dòng «Glass 6»: đang chạy hay vì sao không
- (id)statusText:(PSSpecifier *)specifier {
    if (access(G6_OFF_FILE, F_OK) == 0) return G6L(@"Tắt bằng tệp «off»");
    if (access(G6_AUTO_OFF_FILE, F_OK) == 0) return G6L(@"Đã tự tắt");
    NSDictionary *st = [self g6Status];
    if ([st[@"running"] boolValue]) return G6L(@"Đang chạy");
    NSString *reason = st[@"reason"];
    if ([reason isEqualToString:@"disabled"]) return G6L(@"Đang tắt");
    if ([reason isEqualToString:@"device"]) return G6L(@"Máy chưa được hỗ trợ");
    if ([reason isEqualToString:@"core"]) return G6L(@"Lỗi nạp lõi");
    return G6L(@"Chưa chạy");
}

- (id)versionText:(PSSpecifier *)specifier {
    NSDictionary *st = [self g6Status];
    NSString *v = st[@"version"], *core = st[@"core"];
    if (!v) return @"—";
    return core ? [NSString stringWithFormat:G6L(@"%@ (lõi %@)"), v, core] : v;
}

// Số gói / tweak khác cần lưu ý (mức «conflict» và «warn» của bộ gác)
- (id)conflictText:(PSSpecifier *)specifier {
    NSArray *findings = [self g6Status][@"findings"];
    if (![findings isKindOfClass:[NSArray class]]) return @"—";
    NSUInteger conflict = 0, warn = 0;
    for (NSDictionary *f in findings) {
        if (![f isKindOfClass:[NSDictionary class]]) continue;
        NSString *level = f[@"level"];
        if ([level isEqualToString:@"conflict"]) conflict++;
        else if ([level isEqualToString:@"warn"]) warn++;
    }
    if (conflict) return [NSString stringWithFormat:G6L(@"%lu xung đột"), (unsigned long)conflict];
    if (warn) return [NSString stringWithFormat:G6L(@"%lu cần lưu ý"), (unsigned long)warn];
    return G6L(@"Không");
}

// Xoá các tệp có tên bắt đầu bằng một trong các tiền tố (kết thúc bằng NULL) trong một thư mục
static void G6RemovePrefixed(const char *dirPath, const char *const *prefixes) {
    DIR *dir = opendir(dirPath);
    if (!dir) return;
    struct dirent *e;
    while ((e = readdir(dir))) {
        for (int i = 0; prefixes[i]; i++) {
            if (strncmp(e->d_name, prefixes[i], strlen(prefixes[i])) == 0) {
                char path[512];
                snprintf(path, sizeof(path), "%s/%s", dirPath, e->d_name);
                unlink(path);
                break;
            }
        }
    }
    closedir(dir);
}

// Xoá cờ tự tắt và bộ đếm khởi động — Glass 6 chạy lại ở lần khởi động SpringBoard sau; app từng bị «bỏ qua» vì sập liên
// tiếp được thử lại ở lần mở sau
- (void)resetGuard:(PSSpecifier *)specifier {
    unlink(G6_AUTO_OFF_FILE);
    G6RemovePrefixed(G6_DIR, (const char *const[]){"boot.", NULL});
    G6RemovePrefixed(G6_APP_DIR, (const char *const[]){"app.", "skip.", NULL});
    [self reloadSpecifiers];
    [[[UIAlertView alloc] initWithTitle:G6L(@"Đã đặt lại bộ gác")
                                message:G6L(@"Khởi động lại SpringBoard để Glass 6 chạy lại.")
                               delegate:nil
                      cancelButtonTitle:@"OK"
                      otherButtonTitles:nil] show];
}

- (void)respring:(PSSpecifier *)specifier {
    // Cài đặt và SpringBoard cùng chạy quyền mobile nên gửi tín hiệu được
    pid_t pid;
    char *argv[] = {"killall", "SpringBoard", NULL};
    posix_spawn(&pid, "/usr/bin/killall", NULL, NULL, argv, environ);
}

@end

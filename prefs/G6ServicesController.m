// Cài đặt › Glass 6 › Dịch vụ hệ thống: hồ sơ (Nguyên bản / Cân bằng) và công tắc từng dịch vụ trong danh mục.
//   - Tên, ghi chú, nhóm, hồ sơ: lõi Rust (lệnh «services.catalog» — nguồn là data/services.tsv).
//   - Trạng thái thật và việc tắt / bật: công cụ quyền root g6svc (tweak/Common/G6Services.m). Không có khoá cấu hình nào:
//     hồ sơ đang dùng suy ra từ chính trạng thái của launchd.
// Công tắc BẬT = dịch vụ đang chạy như nguyên bản; gạt TẮT = tắt dịch vụ.
// Riêng «cập nhật iOS qua mạng» (D34) có nhóm riêng ngay dưới phần hồ sơ, công tắc mang nghĩa ngược cho dễ hiểu: «Chặn cập
// nhật iOS» BẬT = đang chặn. Hồ sơ không đụng tới mục này (áp «Nguyên bản» không âm thầm mở lại cập nhật). Máy đã bị gỡ sẵn
// tệp việc của dịch vụ cập nhật thì hiện một dòng «Đã chặn sẵn» thay cho công tắc.
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSSwitchTableCell.h>
#import <UIKit/UIKit.h>
#import <notify.h>

#import "G6Core.h"
#import "G6Lang.h"
#import "G6Services.h"

// Ô công tắc có thêm dòng ghi chú «tắt thì mất gì» dưới tên dịch vụ
@interface G6ServiceCell : PSSwitchTableCell
@end

@implementation G6ServiceCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier specifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier specifier:specifier];
    if (self) {
        // Màn dọc của iPad: ô chỉ rộng ~400 điểm — tên dài thì thu chữ lại một chút thay vì cắt
        self.textLabel.adjustsFontSizeToFitWidth = YES;
        self.textLabel.minimumScaleFactor = 0.75;
        self.detailTextLabel.numberOfLines = 2;
        self.detailTextLabel.font = [UIFont systemFontOfSize:12];
        self.detailTextLabel.textColor = [UIColor colorWithWhite:0.42 alpha:1];
    }
    return self;
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
    [super refreshCellContentsWithSpecifier:specifier];
    self.detailTextLabel.text = [specifier propertyForKey:@"note"];
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    // Công tắc là accessoryView nên contentView đã chừa chỗ cho nó: hai dòng chữ dùng hết bề ngang contentView (chừa lề
    // phải 6 điểm), ghi chú dài thì xuống dòng thứ hai
    CGFloat limit = self.contentView.bounds.size.width - 6;
    for (UILabel *label in @[self.textLabel, self.detailTextLabel]) {
        CGRect f = label.frame;
        f.size.width = MAX(0, limit - f.origin.x);
        label.frame = f;
    }
    // Ghi chú hai dòng cao hơn chỗ UIKit dành sẵn: xếp lại hai dòng chữ cho cân giữa ô
    CGFloat width = self.detailTextLabel.frame.size.width;
    CGSize note = [self.detailTextLabel.text sizeWithFont:self.detailTextLabel.font
                                        constrainedToSize:CGSizeMake(width, 2 * self.detailTextLabel.font.lineHeight + 1)
                                            lineBreakMode:NSLineBreakByWordWrapping];
    CGFloat titleH = self.textLabel.font.lineHeight;
    CGFloat top = floorf((self.contentView.bounds.size.height - titleH - note.height - 1) / 2);
    CGRect t = self.textLabel.frame, d = self.detailTextLabel.frame;
    t.origin.y = top;
    t.size.height = titleH;
    d.origin.y = top + titleH + 1;
    d.size.height = ceilf(note.height);
    self.textLabel.frame = t;
    self.detailTextLabel.frame = d;
}

@end

@interface G6ServicesController : PSListController
@end

@implementation G6ServicesController {
    NSArray *_catalog;       // [{id, group, labels, title, note}]
    NSDictionary *_profiles; // {stock: [mã…], balanced: [mã…]}
    NSDictionary *_status;   // G6SvcStatus()
    BOOL _busy;
    BOOL _shownReverted;
}

- (void)g6LoadCatalog {
    if (_catalog) return;
    NSDictionary *r = G6CoreCall(@{@"cmd" : @"services.catalog"});
    NSArray *list = r[@"services"];
    _catalog = [list isKindOfClass:[NSArray class]] ? list : @[];
    NSDictionary *profiles = r[@"profiles"];
    _profiles = [profiles isKindOfClass:[NSDictionary class]] ? profiles : @{};
}

- (BOOL)g6Disabled:(NSString *)sid {
    return [_status[@"disabled"][sid] boolValue];
}

// Mã các dịch vụ đang tắt
- (NSSet *)g6DisabledSet {
    NSMutableSet *set = [NSMutableSet set];
    NSDictionary *disabled = _status[@"disabled"];
    for (NSString *sid in disabled) {
        // Mục cập nhật iOS đứng ngoài các hồ sơ: không tính khi so «đang dùng hồ sơ nào»
        if ([sid isEqualToString:G6_SVC_UPDATE_ID]) continue;
        if ([disabled[sid] boolValue]) [set addObject:sid];
    }
    return set;
}

- (id)profileText:(PSSpecifier *)specifier {
    if (!_status) return @"—";
    NSSet *off = [self g6DisabledSet];
    if (off.count == 0) return G6L(@"Nguyên bản");
    NSArray *balanced = _profiles[@"balanced"];
    if ([balanced isKindOfClass:[NSArray class]] && [off isEqualToSet:[NSSet setWithArray:balanced]]) return G6L(@"Cân bằng");
    return G6L(@"Tuỳ chỉnh");
}

- (NSString *)g6ProfileFooter {
    NSMutableString *s = [NSMutableString string];
    if (_status[@"reverted"]) {
        [s appendString:G6L(@"Glass 6 đã tự trả các dịch vụ về như trước vì máy khởi động lại hai lần mà chưa lần nào chạy ổn.\n\n")];
    }
    [s appendString:G6L(@"Cân bằng: tắt các dịch vụ đã ngừng phía máy chủ và việc gom chẩn đoán gửi về Apple. Nguyên bản: bật lại "
                    @"tất cả. Thay đổi có tác dụng ngay và được giữ qua các lần khởi động lại máy.")];
    if (_status[@"pending"]) {
        [s appendString:G6L(@"\n\nThay đổi vừa rồi đang chờ xác nhận: ở lần khởi động lại máy tới, máy chạy ổn 60 giây thì thay đổi "
                        @"được giữ; máy khởi động không ổn hai lần liền thì Glass 6 tự trả các dịch vụ về như trước.")];
    }
    return s;
}

- (PSSpecifier *)g6Button:(NSString *)title action:(SEL)sel {
    PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:title target:self set:NULL get:NULL detail:Nil cell:PSButtonCell edit:Nil];
    spec->action = sel;
    return spec;
}

- (id)specifiers {
    if (_specifiers) return _specifiers;
    [self g6LoadCatalog];
    _status = G6SvcStatus();
    NSMutableArray *list = [NSMutableArray array];

    if (!_status || _catalog.count == 0) {
        PSSpecifier *group = [PSSpecifier emptyGroupSpecifier];
        [group setProperty:G6L(@"Không đọc được trạng thái dịch vụ (thiếu lõi hoặc công cụ g6svc). Cài lại Glass 6 rồi thử lại.")
                    forKey:@"footerText"];
        [list addObject:group];
        _specifiers = (id)list;
        return _specifiers;
    }

    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:G6L(@"Hồ sơ")];
    [group setProperty:[self g6ProfileFooter] forKey:@"footerText"];
    [list addObject:group];
    [list addObject:[PSSpecifier preferenceSpecifierNamed:G6L(@"Đang dùng")
                                                   target:self
                                                      set:NULL
                                                      get:@selector(profileText:)
                                                   detail:Nil
                                                     cell:PSTitleValueCell
                                                     edit:Nil]];
    [list addObject:[self g6Button:G6L(@"Áp hồ sơ Cân bằng") action:@selector(applyBalanced:)]];
    [list addObject:[self g6Button:G6L(@"Về Nguyên bản") action:@selector(applyStock:)]];
    [self g6AddUpdateGroupTo:list];

    NSArray *groups = @[
        @[@"A", G6L(@"Dịch vụ đã ngừng"), G6L(@"Máy chủ của các dịch vụ này đã đóng từ lâu — tắt không mất gì.")],
        @[@"B", G6L(@"Chẩn đoán gửi về Apple"), G6L(@"Gom số liệu và nhật ký gửi về Apple. Báo cáo sập vẫn được ghi trên máy.")],
        @[@"C", G6L(@"Tuỳ nhu cầu"), G6L(@"Không nằm trong hồ sơ «Cân bằng» — chỉ tắt thứ không dùng tới.")],
    ];
    for (NSArray *g in groups) {
        NSMutableArray *rows = [NSMutableArray array];
        for (NSDictionary *svc in _catalog) {
            if (![svc isKindOfClass:[NSDictionary class]] || ![svc[@"group"] isEqual:g[0]]) continue;
            NSString *sid = svc[@"id"];
            // Dịch vụ không có trên máy này (g6svc không báo trạng thái) thì không hiện
            if (!_status[@"disabled"][sid]) continue;
            if ([sid isEqualToString:G6_SVC_UPDATE_ID]) continue;  // đã có nhóm riêng ở trên
            PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:G6L(svc[@"title"])
                                                               target:self
                                                                  set:@selector(setServiceOn:specifier:)
                                                                  get:@selector(serviceOn:)
                                                               detail:Nil
                                                                 cell:PSSwitchCell
                                                                 edit:Nil];
            [spec setProperty:sid forKey:@"g6id"];
            [spec setProperty:(G6L(svc[@"note"]) ?: @"") forKey:@"note"];
            [spec setProperty:[G6ServiceCell class] forKey:@"cellClass"];
            [spec setProperty:@60 forKey:@"height"];
            [rows addObject:spec];
        }
        if (rows.count == 0) continue;
        PSSpecifier *header = [PSSpecifier groupSpecifierWithName:g[1]];
        [header setProperty:g[2] forKey:@"footerText"];
        [list addObject:header];
        [list addObjectsFromArray:rows];
    }
    _specifiers = (id)list;
    return _specifiers;
}

// Nhóm «Cập nhật iOS»: công tắc «Chặn cập nhật iOS» (máy còn dịch vụ cập nhật) hoặc dòng «Đã chặn sẵn» (tệp việc đã bị gỡ)
- (void)g6AddUpdateGroupTo:(NSMutableArray *)list {
    BOOL present = _status[@"disabled"][G6_SVC_UPDATE_ID] != nil;
    G6UpdateBlock block = G6SvcUpdateBlock(_status);
    if (!present && block != G6UpdateRemoved) return;
    PSSpecifier *header = [PSSpecifier groupSpecifierWithName:G6L(@"Cập nhật iOS")];
    [list addObject:header];
    if (present) {
        [header setProperty:G6L(@"Bật để máy thôi kiểm tra và tải bản iOS mới — nên bật nếu muốn giữ bản iOS đang dùng: lỡ cập nhật là "
                            @"mất jailbreak. Khi đang chặn, màn «Cập nhật phần mềm» của Cài đặt đứng ở «Kiểm tra cập nhật…» và Glass "
                            @"6 dọn luôn dấu nhắc «có bản cập nhật» trên biểu tượng Cài đặt. Các hồ sơ ở trên không đụng tới mục này.")
                     forKey:@"footerText"];
        PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:G6L(@"Chặn cập nhật iOS")
                                                           target:self
                                                              set:@selector(setUpdateBlocked:specifier:)
                                                              get:@selector(updateBlocked:)
                                                           detail:Nil
                                                             cell:PSSwitchCell
                                                             edit:Nil];
        [list addObject:spec];
    } else {
        [header setProperty:G6L(@"Máy này không còn tệp khởi chạy dịch vụ cập nhật của iOS (đã bị gỡ từ trước) nên không kiểm tra hay tải "
                            @"bản iOS mới được — bản iOS đang dùng được giữ nguyên. Glass 6 không thay đổi gì ở đây, chỉ dọn dấu nhắc "
                            @"«có bản cập nhật» còn sót trên biểu tượng Cài đặt.")
                     forKey:@"footerText"];
        [list addObject:[PSSpecifier preferenceSpecifierNamed:G6L(@"Chặn cập nhật iOS")
                                                       target:self
                                                          set:NULL
                                                          get:@selector(updateRemovedText:)
                                                       detail:Nil
                                                         cell:PSTitleValueCell
                                                         edit:Nil]];
    }
}

- (id)updateBlocked:(PSSpecifier *)specifier {
    return @([self g6Disabled:G6_SVC_UPDATE_ID]);
}

- (void)setUpdateBlocked:(NSNumber *)value specifier:(PSSpecifier *)specifier {
    [self g6Apply:@[[NSString stringWithFormat:@"%@=%d", G6_SVC_UPDATE_ID, value.boolValue ? 1 : 0]]];
}

- (id)updateRemovedText:(PSSpecifier *)specifier {
    return G6L(@"Đã chặn sẵn");
}

- (id)serviceOn:(PSSpecifier *)specifier {
    return @(![self g6Disabled:[specifier propertyForKey:@"g6id"]]);
}

- (void)setServiceOn:(NSNumber *)value specifier:(PSSpecifier *)specifier {
    NSString *sid = [specifier propertyForKey:@"g6id"];
    if (!sid) return;
    [self g6Apply:@[[NSString stringWithFormat:@"%@=%d", sid, value.boolValue ? 0 : 1]]];
}

// Đưa máy về đúng tập «đang tắt» của một hồ sơ: mọi dịch vụ trong danh mục đều được đặt lại (tắt hoặc bật)
- (void)g6ApplyProfile:(NSString *)name {
    NSArray *off = _profiles[name];
    if (![off isKindOfClass:[NSArray class]]) return;
    NSMutableArray *args = [NSMutableArray array];
    for (NSDictionary *svc in _catalog) {
        NSString *sid = svc[@"id"];
        if (!_status[@"disabled"][sid]) continue;
        if ([sid isEqualToString:G6_SVC_UPDATE_ID]) continue;  // hồ sơ không đụng tới mục cập nhật iOS
        [args addObject:[NSString stringWithFormat:@"%@=%d", sid, [off containsObject:sid] ? 1 : 0]];
    }
    [self g6Apply:args];
}

- (void)applyBalanced:(PSSpecifier *)specifier {
    [self g6ApplyProfile:@"balanced"];
}

- (void)applyStock:(PSSpecifier *)specifier {
    [self g6ApplyProfile:@"stock"];
}

// Chạy «g6svc set …» ở luồng nền (gỡ một dịch vụ khỏi launchd mất vài phần mười giây), khoá bảng trong lúc đó rồi đọc lại
// trạng thái thật của máy.
- (void)g6Apply:(NSArray *)assignments {
    if (_busy || assignments.count == 0) return;
    _busy = YES;
    UITableView *table = [self table];
    table.userInteractionEnabled = NO;
    UIActivityIndicatorView *spin = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    [spin startAnimating];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:spin];
    NSArray *args = [@[@"set"] arrayByAddingObjectsFromArray:assignments];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        int rc = G6SvcRun(args, NULL);
        // SpringBoard xét lại những việc đi theo trạng thái dịch vụ (dọn dấu nhắc cập nhật…)
        notify_post(G6_SVC_NOTE);
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_busy = NO;
            self.navigationItem.rightBarButtonItem = nil;
            table.userInteractionEnabled = YES;
            [self reloadSpecifiers];
            if (rc != 0) {
                [[[UIAlertView alloc] initWithTitle:G6L(@"Không đổi được dịch vụ")
                                            message:G6L(@"Công cụ g6svc báo lỗi. Cài lại Glass 6 rồi thử lại.")
                                           delegate:nil
                                  cancelButtonTitle:@"OK"
                                  otherButtonTitles:nil] show];
            }
        });
    });
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // Trạng thái có thể đã đổi từ ngoài (SSH, bộ gác): đọc lại mỗi lần màn này hiện
    if (_specifiers && !_busy) [self reloadSpecifiers];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    // Lời báo «đã tự hoàn tác» chỉ cần hiện một lần
    if (_status[@"reverted"] && !_shownReverted) {
        _shownReverted = YES;
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
            G6SvcRun(@[@"ack"], NULL);
        });
    }
}

@end

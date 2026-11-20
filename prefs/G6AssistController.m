// Cài đặt › Glass 6 › AssistiveTouch: bật nút nổi của Glass 6 và tuỳ biến bảng nút / thao tác trên nút.
// Danh sách chức năng lấy từ lõi (lệnh «assist.catalog» — core/crates/g6-core/src/assist.rs), nên Cài đặt và SpringBoard luôn
// khớp nhau. Giá trị lưu vào vn.glass6.plist bằng cơ chế chuẩn của PSListController (khoá `defaults` / `key`), mỗi lần đổi
// gửi thông báo «vn.glass6/prefs» cho SpringBoard đọc lại.
#import <Preferences/PSListController.h>
#import <Preferences/PSListItemsController.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>

#import "G6Core.h"
#import "G6Lang.h"

@interface G6AssistController : PSListController
@end

@implementation G6AssistController

- (PSSpecifier *)g6Spec:(NSString *)title key:(NSString *)key default:(id)value cell:(PSCellType)cell {
    PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:title
                                                       target:self
                                                          set:@selector(setPreferenceValue:specifier:)
                                                          get:@selector(readPreferenceValue:)
                                                       detail:(cell == PSLinkListCell ? [PSListItemsController class] : Nil)
                                                         cell:cell
                                                         edit:Nil];
    [spec setProperty:@"vn.glass6" forKey:@"defaults"];
    [spec setProperty:key forKey:@"key"];
    [spec setProperty:value forKey:@"default"];
    [spec setProperty:@"vn.glass6/prefs" forKey:@"PostNotification"];
    return spec;
}

// Ô chọn một trong nhiều giá trị
- (PSSpecifier *)g6List:(NSString *)title key:(NSString *)key default:(id)value values:(NSArray *)values titles:(NSArray *)titles {
    PSSpecifier *spec = [self g6Spec:title key:key default:value cell:PSLinkListCell];
    SEL sel = NSSelectorFromString(@"setValues:titles:");
    if ([spec respondsToSelector:sel]) {
        ((void (*)(id, SEL, id, id))objc_msgSend)(spec, sel, values, titles);
    } else {
        [spec setProperty:values forKey:@"validValues"];
        [spec setProperty:titles forKey:@"validTitles"];
    }
    return spec;
}

- (id)specifiers {
    if (_specifiers) return _specifiers;
    NSMutableArray *list = [NSMutableArray array];
    NSDictionary *catalog = G6CoreCall(@{@"cmd" : @"assist.catalog"});
    NSArray *actions = [catalog[@"actions"] isKindOfClass:[NSArray class]] ? catalog[@"actions"] : @[];
    NSArray *defaults = [catalog[@"defaults"] isKindOfClass:[NSArray class]] ? catalog[@"defaults"] : @[];
    NSInteger maxSlots = [catalog[@"maxSlots"] integerValue] ?: 8;
    NSNumber *defaultCount = [catalog[@"defaultCount"] isKindOfClass:[NSNumber class]] ? catalog[@"defaultCount"] : @9;

    PSSpecifier *group = [PSSpecifier emptyGroupSpecifier];
    [group setProperty:G6L(@"Nút nổi trên màn hình như AssistiveTouch của iOS, nhưng tự chọn được các nút bên trong. Bật nút này thì Glass 6 "
                       @"tắt AssistiveTouch của hệ thống để khỏi có hai nút; tắt đi thì nút của hệ thống được bật lại.")
                forKey:@"footerText"];
    [list addObject:group];
    [list addObject:[self g6Spec:G6L(@"Nút AssistiveTouch của Glass 6") key:@"featAssist" default:@NO cell:PSSwitchCell]];

    if (actions.count == 0) {
        PSSpecifier *broken = [PSSpecifier emptyGroupSpecifier];
        [broken setProperty:G6L(@"Không đọc được danh mục chức năng (thiếu lõi). Cài lại Glass 6 rồi thử lại.") forKey:@"footerText"];
        [list addObject:broken];
        _specifiers = (id)list;
        return _specifiers;
    }

    NSMutableArray *slotIds = [NSMutableArray array], *slotTitles = [NSMutableArray array];
    NSMutableArray *gestureIds = [NSMutableArray array], *gestureTitles = [NSMutableArray array];
    for (NSDictionary *a in actions) {
        if (![a isKindOfClass:[NSDictionary class]] || !a[@"id"] || !G6L(a[@"title"])) continue;
        if ([a[@"slot"] boolValue]) {
            [slotIds addObject:a[@"id"]];
            [slotTitles addObject:[a[@"id"] isEqual:@"none"] ? G6L(@"Để trống") : G6L(a[@"title"])];
        }
        if ([a[@"gesture"] boolValue]) {
            [gestureIds addObject:a[@"id"]];
            [gestureTitles addObject:G6L(a[@"title"])];
        }
    }

    group = [PSSpecifier groupSpecifierWithName:G6L(@"Bảng nút")];
    [group setProperty:G6L(@"Bảng nút là một ô vuông 3×3; ít hơn 9 nút thì các nút xếp đối xứng quanh tâm (8 nút: chừa ô giữa). "
                       @"Chạm vào nút nổi để mở bảng; không bấm gì thì bảng tự ẩn sau thời gian chờ. Ô «Để trống» không hiện. Tăng / "
                       @"giảm âm lượng và độ sáng bấm được liên tiếp, các chức năng khác bấm xong thì bảng tự đóng. Ô khoá xoay, tắt "
                       @"tiếng, sáng / tối hiện theo trạng thái thật: nhãn là việc lần bấm tới sẽ làm.")
                forKey:@"footerText"];
    [list addObject:group];
    NSMutableArray *counts = [NSMutableArray array], *countTitles = [NSMutableArray array];
    for (NSInteger i = 1; i <= maxSlots; i++) {
        [counts addObject:@(i)];
        [countTitles addObject:[NSString stringWithFormat:G6L(@"%ld nút"), (long)i]];
    }
    [list addObject:[self g6List:G6L(@"Số nút") key:@"assistCount" default:defaultCount values:counts titles:countTitles]];
    [list addObject:[self g6List:G6L(@"Tự ẩn bảng nút")
                             key:@"assistMenuTimeout"
                         default:@5
                          values:@[@0, @3, @5, @10, @15, @30]
                          titles:@[G6L(@"Không tự ẩn"), G6L(@"Sau 3 giây"), G6L(@"Sau 5 giây"), G6L(@"Sau 10 giây"), G6L(@"Sau 15 giây"), G6L(@"Sau 30 giây")]]];
    for (NSInteger i = 0; i < maxSlots; i++) {
        NSString *fallback = i < (NSInteger)defaults.count ? defaults[i] : @"none";
        [list addObject:[self g6List:[NSString stringWithFormat:G6L(@"Nút %ld"), (long)i + 1]
                                 key:[NSString stringWithFormat:@"assistSlot%ld", (long)i + 1]
                             default:fallback
                              values:slotIds
                              titles:slotTitles]];
    }

    group = [PSSpecifier groupSpecifierWithName:G6L(@"Thao tác trên nút")];
    [group setProperty:G6L(@"Kéo nút tới chỗ khác được; thả ra thì nút hít vào mép màn hình gần nhất.") forKey:@"footerText"];
    [list addObject:group];
    [list addObject:[self g6List:G6L(@"Chạm một lần") key:@"assistTap" default:@"menu" values:gestureIds titles:gestureTitles]];
    [list addObject:[self g6List:G6L(@"Chạm hai lần") key:@"assistDouble" default:@"none" values:gestureIds titles:gestureTitles]];
    [list addObject:[self g6List:G6L(@"Nhấn giữ") key:@"assistHold" default:@"none" values:gestureIds titles:gestureTitles]];

    group = [PSSpecifier groupSpecifierWithName:G6L(@"Độ rõ lúc nghỉ")];
    [group setProperty:G6L(@"Sau vài giây không đụng tới, nút mờ bớt cho đỡ vướng mắt.") forKey:@"footerText"];
    [list addObject:group];
    PSSpecifier *slider = [self g6Spec:nil key:@"assistIdleAlpha" default:@0.5 cell:PSSliderCell];
    [slider setProperty:@0.15 forKey:@"min"];
    [slider setProperty:@1.0 forKey:@"max"];
    [slider setProperty:@NO forKey:@"showValue"];
    [list addObject:slider];

    _specifiers = (id)list;
    return _specifiers;
}

@end

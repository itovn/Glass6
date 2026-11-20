// Công cụ thử: giả lập ngón tay (chạm, nhấn giữ, kéo) ngay trong tiến trình — để tự kiểm các thao tác mà SSH không làm được
// (bấm phím của bàn phím số / máy tính, vuốt thẻ của khay đa nhiệm, kéo thanh trượt…). Chỉ có trong bản thử.
//
// Cách làm (kỹ thuật quen thuộc của các bộ thử giao diện thời iOS 5 – 6): tự tạo một UITouch, điền các ivar riêng của nó
// (pha, vị trí trong cửa sổ, view trúng chạm, thời điểm…) qua runtime, gắn vào sự kiện chạm dùng chung của UIApplication
// (-_touchesEvent) cùng một «GSEvent giả» mang toạ độ, rồi đưa qua -[UIApplication sendEvent:] như sự kiện thật. Mỗi bước
// (bắt đầu → di chuyển… → kết thúc) là một lần gửi, cách nhau một nhịp của vòng lặp chính.
// Mọi ivar / hàm riêng đều được tra lúc chạy; thiếu thứ gì thì báo và không gửi gì.
//
//   tap <x> <y> [giữ ms]                     chạm tại (x, y) — toạ độ điểm của màn hình đứng; giữ ms (mặc định 60) rồi nhả
//   drag <x1> <y1> <x2> <y2> [ms] [giữ ms]   đặt ngón ở (x1, y1), [giữ một lúc], kéo tới (x2, y2) trong ms (mặc định 300), nhả
#import "G6Debug.h"

#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "G6Log.h"

#if G6_DEBUG

// Cùng bố cục bộ nhớ với phần đầu của GSEvent (đối tượng CoreFoundation): sau con trỏ lớp là 1 từ, rồi tới bản ghi sự kiện
@interface G6FakeGSEvent : NSObject {
   @public
    unsigned int flags;
    unsigned int type;
    unsigned int ignored1;
    float x1, y1, x2, y2;
    unsigned int ignored2[10];
    unsigned int ignored3[7];
    float sizeX, sizeY;
    float x3, y3;
    unsigned int ignored4[3];
}
@end

@implementation G6FakeGSEvent
@end

static BOOL G6TouchSet(id obj, const char *name, const void *value, size_t size) {
    Ivar iv = class_getInstanceVariable([obj class], name);
    if (!iv) return NO;
    memcpy((char *)(__bridge void *)obj + ivar_getOffset(iv), value, size);
    return YES;
}

// Ivar đối tượng của UITouch do chính nó giữ / thả (mã không ARC) → giữ thêm một lần trước khi gán
static BOOL G6TouchSetObject(id obj, const char *name, id value) {
    Ivar iv = class_getInstanceVariable([obj class], name);
    if (!iv) return NO;
    void *raw = value ? (void *)CFBridgingRetain(value) : NULL;
    memcpy((char *)(__bridge void *)obj + ivar_getOffset(iv), &raw, sizeof(raw));
    return YES;
}

// Cửa sổ trên cùng nhận chạm tại điểm `p` (toạ độ màn hình đứng = toạ độ cửa sổ trên iOS 6) và view trúng chạm
static UIView *G6TouchHit(CGPoint p, UIWindow **outWindow) {
    NSArray *windows = nil;
    SEL sel = NSSelectorFromString(@"allWindowsIncludingInternalWindows:onlyVisibleWindows:");
    if ([UIWindow respondsToSelector:sel]) {
        windows = ((id (*)(id, SEL, BOOL, BOOL))objc_msgSend)([UIWindow class], sel, YES, YES);
    }
    if (!windows.count) windows = [UIApplication sharedApplication].windows;
    NSArray *sorted = [windows sortedArrayUsingComparator:^NSComparisonResult(UIWindow *a, UIWindow *b) {
        if (a.windowLevel == b.windowLevel) return NSOrderedSame;
        return a.windowLevel > b.windowLevel ? NSOrderedAscending : NSOrderedDescending;
    }];
    for (UIWindow *window in sorted) {
        if (window.hidden || window.alpha < 0.01 || !window.userInteractionEnabled) continue;
        UIView *hit = [window hitTest:[window convertPoint:p fromWindow:nil] withEvent:nil];
        if (hit) {
            if (outWindow) *outWindow = window;
            return hit;
        }
    }
    return nil;
}

static UITouch *G6TouchMake(CGPoint p, UIWindow *window, UIView *view) {
    UITouch *touch = [[UITouch alloc] init];
    unsigned int taps = 1;
    int phase = UITouchPhaseBegan;
    NSTimeInterval now = [NSProcessInfo processInfo].systemUptime;
    unsigned char flags = 0x3;  // _firstTouchForView + _isTap
    BOOL ok = G6TouchSet(touch, "_tapCount", &taps, sizeof(taps)) && G6TouchSet(touch, "_locationInWindow", &p, sizeof(p)) &&
              G6TouchSet(touch, "_previousLocationInWindow", &p, sizeof(p)) && G6TouchSet(touch, "_phase", &phase, sizeof(phase)) &&
              G6TouchSet(touch, "_timestamp", &now, sizeof(now)) && G6TouchSet(touch, "_touchFlags", &flags, sizeof(flags)) &&
              G6TouchSetObject(touch, "_window", window) && G6TouchSetObject(touch, "_view", view);
    if (!ok) return nil;
    // View nhận cử chỉ: đặt qua hàm của UITouch (có trên iOS 6). KHÔNG tự điền _gestureRecognizers: lúc sự kiện nhận ngón tay
    // ở pha «bắt đầu», UIKit tự gom các bộ nhận cử chỉ dọc cây view và ghi vào cả ngón tay lẫn sự kiện — điền sẵn thì nó
    // bỏ bước đó, cử chỉ kéo (cuộn, vuốt thẻ) không bao giờ được nhận ra (đã gặp).
    SEL setGestureView = NSSelectorFromString(@"setGestureView:");
    if ([touch respondsToSelector:setGestureView]) ((void (*)(id, SEL, id))objc_msgSend)(touch, setGestureView, view);
    return touch;
}

static BOOL G6TouchSend(UITouch *touch, CGPoint p, int phase) {
    UIApplication *app = [UIApplication sharedApplication];
    SEL eventSel = NSSelectorFromString(@"_touchesEvent"), clearSel = NSSelectorFromString(@"_clearTouches");
    SEL gsSel = NSSelectorFromString(@"_setGSEvent:"), addSel = NSSelectorFromString(@"_addTouch:forDelayedDelivery:");
    if (![app respondsToSelector:eventSel]) return NO;
    UIEvent *event = ((id (*)(id, SEL))objc_msgSend)(app, eventSel);
    if (![event respondsToSelector:clearSel] || ![event respondsToSelector:gsSel] || ![event respondsToSelector:addSel]) return NO;
    CGPoint previous = CGPointZero;
    Ivar iv = class_getInstanceVariable([touch class], "_locationInWindow");
    if (iv) memcpy(&previous, (char *)(__bridge void *)touch + ivar_getOffset(iv), sizeof(previous));
    NSTimeInterval now = [NSProcessInfo processInfo].systemUptime;
    G6TouchSet(touch, "_previousLocationInWindow", &previous, sizeof(previous));
    G6TouchSet(touch, "_locationInWindow", &p, sizeof(p));
    G6TouchSet(touch, "_phase", &phase, sizeof(phase));
    G6TouchSet(touch, "_timestamp", &now, sizeof(now));
    if (phase == UITouchPhaseMoved) {
        // Đã di chuyển thì không còn là «chạm nhẹ»
        unsigned char flags = 0x1;
        G6TouchSet(touch, "_touchFlags", &flags, sizeof(flags));
    }
    G6FakeGSEvent *gs = [[G6FakeGSEvent alloc] init];
    gs->x1 = gs->x2 = gs->x3 = (float)p.x;
    gs->y1 = gs->y2 = gs->y3 = (float)p.y;
    gs->sizeX = gs->sizeY = 1.0f;
    gs->flags = phase == UITouchPhaseEnded ? 0x1010180 : 0x3010180;
    gs->type = 3001;
    // Chỉ lúc ngón tay «bắt đầu» mới xoá + nạp ngón vào sự kiện: khi đó UIKit gom các bộ nhận cử chỉ của cây view vào sự
    // kiện. Các bước «di chuyển / kết thúc» gửi lại CHÍNH sự kiện đó (ngón tay đã đổi vị trí, pha) — xoá rồi nạp lại ở các
    // bước này thì bảng bộ nhận cử chỉ của sự kiện bị xoá theo, cuộn / vuốt không bao giờ được nhận ra (đã gặp).
    if (phase == UITouchPhaseBegan) ((void (*)(id, SEL))objc_msgSend)(event, clearSel);
    ((void (*)(id, SEL, void *))objc_msgSend)(event, gsSel, (__bridge void *)gs);
    if (phase == UITouchPhaseBegan) ((void (*)(id, SEL, id, BOOL))objc_msgSend)(event, addSel, touch, NO);
    [app sendEvent:event];
    return YES;
}

static void G6TouchAfter(double ms, dispatch_block_t block) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(ms * NSEC_PER_MSEC)), dispatch_get_main_queue(), block);
}

// Các điểm của một lần kéo, gửi lần lượt mỗi 16 mili giây
static void G6TouchStep(UITouch *touch, CGPoint from, CGPoint to, int step, int steps) {
    @try {
        if (step > steps) {
            G6TouchSend(touch, to, UITouchPhaseEnded);
            G6Log(@"[thử] chạm giả: nhả ở (%.0f, %.0f)", to.x, to.y);
            return;
        }
        CGFloat t = (CGFloat)step / steps;
        G6TouchSend(touch, CGPointMake(from.x + (to.x - from.x) * t, from.y + (to.y - from.y) * t), UITouchPhaseMoved);
    } @catch (NSException *e) {
        G6Log(@"[thử] chạm giả: lỗi %@", e);
        return;
    }
    G6TouchAfter(16, ^{
        G6TouchStep(touch, from, to, step + 1, steps);
    });
}

void G6DebugTouch(NSString *command, NSString *arg) {
    NSMutableArray *n = [NSMutableArray array];
    for (NSString *part in [arg componentsSeparatedByString:@" "]) {
        if (part.length) [n addObject:@(part.doubleValue)];
    }
    BOOL drag = [command isEqualToString:@"drag"];
    if (n.count < (drag ? 4 : 2)) {
        G6Log(@"[thử] %@: thiếu toạ độ", command);
        return;
    }
    CGPoint from = CGPointMake([n[0] doubleValue], [n[1] doubleValue]);
    CGPoint to = drag ? CGPointMake([n[2] doubleValue], [n[3] doubleValue]) : from;
    double moveMs = drag && n.count > 4 ? [n[4] doubleValue] : 300;
    double holdMs = drag ? (n.count > 5 ? [n[5] doubleValue] : 30) : (n.count > 2 ? [n[2] doubleValue] : 60);
    UIWindow *window = nil;
    UIView *view = G6TouchHit(from, &window);
    if (!view || !window) {
        G6Log(@"[thử] %@: không view nào nhận chạm ở (%.0f, %.0f)", command, from.x, from.y);
        return;
    }
    UITouch *touch = G6TouchMake(from, window, view);
    if (!touch || !G6TouchSend(touch, from, UITouchPhaseBegan)) {
        G6Log(@"[thử] %@: máy này không có đủ ivar / hàm riêng để giả lập chạm", command);
        return;
    }
    G6Log(@"[thử] chạm giả: đặt ngón ở (%.0f, %.0f) trên %@ trong %@", from.x, from.y, NSStringFromClass([view class]),
          NSStringFromClass([window class]));
    int steps = drag ? MAX(2, (int)(moveMs / 16)) : 0;
    G6TouchAfter(holdMs, ^{
        if (drag) {
            G6TouchStep(touch, from, to, 1, steps);
        } else {
            @try {
                G6TouchSend(touch, to, UITouchPhaseEnded);
                G6Log(@"[thử] chạm giả: nhả ở (%.0f, %.0f)", to.x, to.y);
            } @catch (NSException *e) {
                G6Log(@"[thử] chạm giả: lỗi %@", e);
            }
        }
    });
}

#endif

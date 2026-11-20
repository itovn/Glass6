#import "G6Hook.h"

#import "G6Log.h"

BOOL G6Hook(Class cls, SEL sel, IMP repl, IMP *orig) {
    if (!cls || !sel || !repl || !orig) return NO;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) {
        G6Log(@"không có -[%s %s] trên máy này — bỏ qua", class_getName(cls), sel_getName(sel));
        return NO;
    }
    // Hàm thừa kế từ lớp cha: thêm vào chính lớp này, gốc là bản của lớp cha
    if (class_addMethod(cls, sel, repl, method_getTypeEncoding(m))) {
        *orig = method_getImplementation(m);
        return YES;
    }
    *orig = method_setImplementation(m, repl);
    return YES;
}

BOOL G6HookNamed(const char *cls, SEL sel, IMP repl, IMP *orig) {
    Class c = objc_getClass(cls);
    if (!c) {
        G6Log(@"không có lớp %s trên máy này — bỏ qua", cls);
        return NO;
    }
    return G6Hook(c, sel, repl, orig);
}

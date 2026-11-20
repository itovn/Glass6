#import "G6Font.h"

#import <CoreText/CoreText.h>

#import "G6Log.h"

static NSString *const kFontDir = @"/Library/Application Support/Glass6/Fonts";

static NSString *G6FontName(G6FontWeight weight) {
    switch (weight) {
        case G6FontMedium:
            return @"Inter-Medium";
        case G6FontSemiBold:
            return @"Inter-SemiBold";
        case G6FontBold:
            return @"Inter-Bold";
        default:
            return @"Inter-Regular";
    }
}

// Đăng ký từng kiểu đậm nhạt khi có nơi dùng tới lần đầu (mỗi tệp tốn chừng chục mili giây — app chỉ dùng hai kiểu thì
// không phải trả cho cả bốn). Trả YES nếu UIKit tìm được phông theo tên sau khi đăng ký.
static BOOL G6FontRegister(G6FontWeight weight) {
    static dispatch_once_t once[4];
    static BOOL ok[4];
    int index = weight < 0 || weight > G6FontBold ? 0 : (int)weight;
    dispatch_once(&once[index], ^{
        NSString *name = G6FontName((G6FontWeight)index);
        NSURL *url = [NSURL fileURLWithPath:[[kFontDir stringByAppendingPathComponent:name] stringByAppendingPathExtension:@"ttf"]];
        CFErrorRef error = NULL;
        BOOL registered = CTFontManagerRegisterFontsForURL((__bridge CFURLRef)url, kCTFontManagerScopeProcess, &error);
        if (error) CFRelease(error);
        // Đăng ký được chưa chắc UIKit đã tìm thấy theo tên — thử thật (đã đăng ký từ trước thì hàm trên báo lỗi nhưng phông vẫn có)
        ok[index] = [UIFont fontWithName:name size:12] != nil;
        if (!ok[index]) G6Log(@"phông: không có %@ (đăng ký %@) — dùng phông hệ thống", name, registered ? @"được" : @"hỏng");
    });
    return ok[index];
}

BOOL G6FontAvailable(void) {
    return G6FontRegister(G6FontMedium);
}

UIFont *G6Font(G6FontWeight weight, CGFloat size) {
    UIFont *font = G6FontRegister(weight) ? [UIFont fontWithName:G6FontName(weight) size:size] : nil;
    if (font) return font;
    return weight >= G6FontSemiBold ? [UIFont boldSystemFontOfSize:size] : [UIFont systemFontOfSize:size];
}

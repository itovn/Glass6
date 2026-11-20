#import "G6Lang.h"

#ifndef G6_PREFS_DOMAIN
#define G6_PREFS_DOMAIN "vn.glass6"
#endif

// Bảng dịch nằm trong gói bảng Cài đặt (một bản cho mọi thành phần)
static NSString *const kStringsPath = @"/Library/PreferenceBundles/Glass6Prefs.bundle/Strings-en.plist";
static NSString *const kPrefsPath = @"/var/mobile/Library/Preferences/" G6_PREFS_DOMAIN ".plist";

static NSString *gLanguage;
static NSDictionary *gEnglish;

NSString *G6Language(void) {
    @synchronized(kStringsPath) {
        if (!gLanguage) {
            id choice = [[NSDictionary dictionaryWithContentsOfFile:kPrefsPath] objectForKey:@"language"];
            if ([choice isEqual:@"vi"] || [choice isEqual:@"en"]) {
                gLanguage = choice;
            } else {
                NSString *first = [[NSLocale preferredLanguages] firstObject];
                gLanguage = [first hasPrefix:@"vi"] ? @"vi" : @"en";
            }
        }
        return gLanguage;
    }
}

void G6LangReload(void) {
    @synchronized(kStringsPath) {
        gLanguage = nil;
    }
}

NSString *G6L(NSString *text) {
    if (![text isKindOfClass:[NSString class]] || text.length == 0) return text;
    if ([G6Language() isEqualToString:@"vi"]) return text;
    NSDictionary *table;
    @synchronized(kStringsPath) {
        if (!gEnglish) gEnglish = [NSDictionary dictionaryWithContentsOfFile:kStringsPath] ?: @{};
        table = gEnglish;
    }
    NSString *english = table[text];
    return ([english isKindOfClass:[NSString class]] && english.length) ? english : text;
}

NSString *G6LDecimal(NSString *text) {
    if (![text isKindOfClass:[NSString class]] || [G6Language() isEqualToString:@"vi"]) return text;
    return [text stringByReplacingOccurrencesOfString:@"," withString:@"."];
}

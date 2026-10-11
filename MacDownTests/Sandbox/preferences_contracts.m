// Real CFPreferences consumer for signed sandbox fixtures. Refuse all domains
// except the dedicated synthetic test prefix, including MacDown's real suite.
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        if (argc != 4) return 2;
        NSString *domain = @(argv[2]);
        if (![domain hasPrefix:@"org.macdown.audit.preferences."]) return 2;
        CFStringRef suite = (__bridge CFStringRef)domain;
        if (!strcmp(argv[1], "write") || !strcmp(argv[1], "delete")) {
            CFPropertyListRef value = !strcmp(argv[1], "delete") ? NULL : (__bridge CFStringRef)@(argv[3]);
            CFPreferencesSetValue(CFSTR("AuditSyntheticValue"), value, suite,
                                  kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
            return CFPreferencesSynchronize(suite, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) ? 0 : 2;
        }
        if (strcmp(argv[1], "read")) return 2;
        NSString *value = CFBridgingRelease(CFPreferencesCopyValue(CFSTR("AuditSyntheticValue"),
            suite, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
        fprintf(stdout, "read=%s\n", value.description.UTF8String);
        return [value isEqual:@(argv[3])] ? 0 : 1;
    }
}

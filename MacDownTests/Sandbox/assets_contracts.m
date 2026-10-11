// Exercise the actual Core HTML consumer with isolated asset names only.
#import <Foundation/Foundation.h>
#import "../../MacDownCore/MPQuickLookRenderer.h"
#import "../../MacDownCore/MPQuickLookPreferences.h"
#import <pwd.h>
#import <unistd.h>

@interface MPAuditAssetPreferences : MPQuickLookPreferences
@property NSString *fixtureStyle;
@property NSString *fixtureTheme;
@end
@implementation MPAuditAssetPreferences
- (NSString *)styleName { return self.fixtureStyle; }
- (NSString *)highlightingThemeName { return self.fixtureTheme; }
- (BOOL)syntaxHighlightingEnabled { return YES; }
- (int)extensionFlags { return 0; }
- (int)rendererFlags { return 0; }
@end

int main(int argc, const char **argv)
{
    @autoreleasepool {
        if (argc != 4) return 2;
        NSString *token = @(argv[1]);
        if (token.length != 32 || [token rangeOfCharacterFromSet:
                [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"].invertedSet].location != NSNotFound) return 2;
        BOOL userAssets = !strcmp(argv[2], "user");
        BOOL blocked = !strcmp(argv[2], "blocked");
        BOOL sandboxed = !strcmp(argv[3], "sandbox");
        struct passwd *account = getpwuid(getuid());
        if (!account || !account->pw_dir) return 2;
        NSString *root = [@(account->pw_dir) stringByAppendingPathComponent:@"Library/Application Support/MacDown 3000"];
        NSString *styleName = [@"AuditSandboxAsset-" stringByAppendingString:token];
        NSString *themeName = [@"auditsandboxasset-" stringByAppendingString:token];
        NSArray *paths = @[[root stringByAppendingPathComponent:[NSString stringWithFormat:@"Styles/%@.css", styleName]],
            [root stringByAppendingPathComponent:[NSString stringWithFormat:@"Prism/themes/prism-%@.css", themeName]]];
        MPAuditAssetPreferences *preferences = [MPAuditAssetPreferences new];
        preferences.fixtureStyle = styleName;
        preferences.fixtureTheme = themeName;
        MPQuickLookRenderer *renderer = [MPQuickLookRenderer new];
        // The production singleton is constructed but none of its real suite
        // keys are read: these exact names replace all styling preferences.
        [renderer setValue:preferences forKey:@"preferences"];
        NSString *html = [renderer renderMarkdown:@"# Isolated asset fixture"];
        if (![html containsString:@">Isolated asset fixture</h1>"]) return 1;
        NSString *prefix = userAssets ? @"USER" : @"BUNDLE";
        for (NSString *kind in @[@"STYLE", @"THEME"]) {
            NSString *marker = [NSString stringWithFormat:@"%@_%@_%@", prefix, kind, token];
            if (blocked) {
                NSString *userMarker = [NSString stringWithFormat:@"USER_%@_%@", kind, token];
                if ([html containsString:userMarker]) return 1;
            } else if (![html containsString:marker]) { fprintf(stderr, "Missing CSS %s\n", marker.UTF8String); return 1; }
        }
        NSString *outside = [root stringByAppendingPathComponent:[NSString stringWithFormat:@"AuditSandboxOutside-%@.css", token]];
        if (sandboxed) {
            for (NSString *path in [paths arrayByAddingObject:outside]) {
                NSError *error = nil;
                if ([@"unauthorized replacement" writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:&error] || !error) return 1;
            }
            if ([NSString stringWithContentsOfFile:outside encoding:NSUTF8StringEncoding error:NULL]) return 1;
        }
        fprintf(stdout, "PASS Core %s; sandbox boundaries preserved\n",
            blocked ? "cannot embed forbidden user CSS" : [@"embeds " stringByAppendingString:prefix].UTF8String);
        return 0;
    }
}

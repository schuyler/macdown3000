// Exercise deferred geometry with a real NSTextView/layout manager/main queue.
// Preferences are process-local memory: no application or global domain writes.
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "MPExportPanelAccessoryViewController.h"

@interface MPGeometryMemoryDefaults : NSUserDefaults
@property (nonatomic, strong) NSMutableDictionary *values;
@end

@implementation MPGeometryMemoryDefaults
- (id)objectForKey:(NSString *)key { return self.values[key]; }
- (void)setObject:(id)value forKey:(NSString *)key
{
    if (value) self.values[key] = value;
    else [self.values removeObjectForKey:key];
}
- (void)setBool:(BOOL)value forKey:(NSString *)key
{
    [self setObject:@(value) forKey:key];
}
- (BOOL)boolForKey:(NSString *)key { return [[self objectForKey:key] boolValue]; }
- (void)setInteger:(NSInteger)value forKey:(NSString *)key
{
    [self setObject:@(value) forKey:key];
}
- (NSInteger)integerForKey:(NSString *)key
{
    return [[self objectForKey:key] integerValue];
}
@end

static MPGeometryMemoryDefaults *memoryDefaults;
static id MPGeometryStandardDefaults(id receiver, SEL selector)
{
    return memoryDefaults;
}


static NSArray<NSButton *> *Buttons(NSView *view) {
    NSMutableArray *result = [NSMutableArray array];
    if ([view isKindOfClass:NSButton.class]) [result addObject:view];
    for (NSView *child in view.subviews) [result addObjectsFromArray:Buttons(child)];
    return result;
}
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 3) return 2;
        memoryDefaults = [MPGeometryMemoryDefaults new];
        memoryDefaults.values = [NSMutableDictionary dictionary];
        method_setImplementation(class_getClassMethod(NSUserDefaults.class,
            @selector(standardUserDefaults)), (IMP)MPGeometryStandardDefaults);
        [NSApplication sharedApplication];
        NSBundle *app = [NSBundle bundleWithPath:@(argv[1])];
        NSString *repo = @(argv[2]);
        if (!app.resourcePath) return 2;
        NSFileManager *fm = NSFileManager.defaultManager;
        NSString *source = [repo stringByAppendingPathComponent:@"MacDown/Localization"];
        NSUInteger resources = 0, entries = 0, locales = 0, overflows = 0;
        NSArray *tables = @[@"MPDocument", @"MainMenu", @"MPEditorPreferencesViewController",
            @"MPExportPanelAccessoryViewController", @"MPGeneralPreferencesViewController",
            @"MPHtmlPreferencesViewController", @"MPMarkdownPreferencesViewController",
            @"MPTerminalPreferencesViewController"];
        for (NSString *table in tables) {
            if (![app pathForResource:table ofType:@"nib"]) {
                fprintf(stderr, "FAIL missing bundled nib %s\n", table.UTF8String); return 1;
            }
            resources++;
        }
        NSString *assets = [repo stringByAppendingPathComponent:@"MacDown/Images.xcassets"];
        NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:assets];
        NSString *relative;
        while ((relative = enumerator.nextObject)) {
            if (![relative.pathExtension isEqual:@"imageset"]) continue;
            NSString *name = relative.lastPathComponent.stringByDeletingPathExtension;
            NSImage *image = [app imageForResource:name];
            if (!image || !image.isValid || image.size.width <= 0 || image.size.height <= 0) {
                fprintf(stderr, "FAIL bundled image %s\n", name.UTF8String); return 1;
            }
            resources++;
        }
        NSString *iconName = [app objectForInfoDictionaryKey:@"CFBundleIconFile"];
        if (!iconName.length) { fprintf(stderr, "FAIL app icon metadata\n"); return 1; }
        NSString *iconPath = [app pathForResource:iconName.stringByDeletingPathExtension ofType:@"icns"];
        if (!iconPath || ![[NSImage alloc] initWithContentsOfFile:iconPath].isValid) {
            fprintf(stderr, "FAIL actual bundled icon\n"); return 1;
        }
        for (NSString *localeDir in [fm contentsOfDirectoryAtPath:source error:nil]) {
            if (![localeDir.pathExtension isEqual:@"lproj"] || [localeDir isEqual:@"Base.lproj"]) continue;
            NSBundle *localized = [NSBundle bundleWithPath:[app.resourcePath stringByAppendingPathComponent:localeDir]];
            if (!localized) { fprintf(stderr, "FAIL locale %s absent\n", localeDir.UTF8String); return 1; }
            NSString *localeSource = [source stringByAppendingPathComponent:localeDir];
            for (NSString *file in [fm contentsOfDirectoryAtPath:localeSource error:nil]) {
                if (![file.pathExtension isEqual:@"strings"]) continue;
                NSData *data = [NSData dataWithContentsOfFile:[localeSource stringByAppendingPathComponent:file]];
                if (data.length == 0) continue; // Explicitly empty translation table: Base fallback.
                NSError *error = nil;
                NSDictionary *values = [NSPropertyListSerialization propertyListWithData:data
                    options:NSPropertyListImmutable format:nil error:&error];
                if (![values isKindOfClass:NSDictionary.class]) {
                    fprintf(stderr, "FAIL source strings parse %s\n", file.UTF8String); return 1;
                }
                for (NSString *key in values) {
                    NSString *actual = [localized localizedStringForKey:key value:@"MISSING"
                        table:file.stringByDeletingPathExtension];
                    if (![actual isEqual:values[key]]) {
                        fprintf(stderr, "FAIL bundled %s/%s %s\n", localeDir.UTF8String,
                            file.UTF8String, key.UTF8String); return 1;
                    }
                    entries++;
                }
            }
            MPExportPanelAccessoryViewController *controller =
                [[MPExportPanelAccessoryViewController alloc] initWithNibName:
                    @"MPExportPanelAccessoryViewController" bundle:app];
            NSView *view = controller.view;
            NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,view.frame.size.width,view.frame.size.height)
                styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
            window.releasedWhenClosed = NO;
            window.contentView = view;
            NSArray<NSButton *> *buttons = Buttons(view);
            if (buttons.count != 2) { fprintf(stderr,"FAIL export nib button count\n"); return 1; }
            for (NSButton *button in buttons) {
                NSString *binding = [button infoForBinding:NSValueBinding][NSObservedKeyPathKey];
                NSString *key;
                NSString *fallback;
                if ([binding isEqual:@"self.stylesIncluded"]) { key = @"fod-Ff-UTI.title"; fallback = @"Include styles"; }
                else if ([binding isEqual:@"self.highlightingIncluded"]) { key = @"1f7-JB-VR1.title"; fallback = @"Include syntax highlighting"; }
                else { fprintf(stderr,"FAIL export binding\n"); return 1; }
                button.title = [localized localizedStringForKey:key value:fallback
                    table:@"MPExportPanelAccessoryViewController"];
            }
            [view layoutSubtreeIfNeeded];
            for (NSButton *button in buttons) {
                NSRect frame = button.frame;
                NSSize needed = button.cell.cellSize;
                NSSize bounded = [button.cell cellSizeForBounds:NSMakeRect(0,0,frame.size.width,10000)];
                NSButton *measurement = [[NSButton alloc] initWithFrame:frame];
                measurement.cell = [button.cell copy];
                [measurement sizeToFit];
                BOOL wraps = button.cell.lineBreakMode == NSLineBreakByWordWrapping
                    || button.cell.lineBreakMode == NSLineBreakByCharWrapping;
                NSRect parentBounds = NSInsetRect(button.superview.bounds, -0.5, -0.5);
                BOOL overlaps = NO;
                for (NSButton *other in buttons) {
                    if (other == button || other.superview != button.superview) continue;
                    NSRect intersection = NSIntersectionRect(frame, other.frame);
                    if (intersection.size.width > 0.5 && intersection.size.height > 0.5) overlaps = YES;
                }
                BOOL overflow = bounded.height > frame.size.height + 0.5
                    || (!wraps && needed.width > frame.size.width + 0.5)
                    || !NSContainsRect(parentBounds, frame) || overlaps;
                if (overflow) overflows++;
                fprintf(stdout, "%s export %s title=%s frame=%s cell=%s bounded=%s sizeToFit=%s wraps=%d overlaps=%d\n",
                    overflow ? "OVERFLOW" : "PASS", localeDir.UTF8String, button.title.UTF8String,
                    NSStringFromRect(frame).UTF8String, NSStringFromSize(needed).UTF8String,
                    NSStringFromSize(bounded).UTF8String, NSStringFromRect(measurement.frame).UTF8String, wraps, overlaps);
            }
            // Exercise the actual BOOL bindings with a click, then release the nib owner.
            for (NSButton *button in buttons) {
                NSString *binding = [button infoForBinding:NSValueBinding][NSObservedKeyPathKey];
                BOOL styles = [binding isEqual:@"self.stylesIncluded"];
                BOOL before = styles ? controller.isStylesIncluded : controller.isHighlightingIncluded;
                [button performClick:nil];
                BOOL after = styles ? controller.isStylesIncluded : controller.isHighlightingIncluded;
                if (before == after || after != (button.state == NSControlStateValueOn)) {
                    fprintf(stderr, "FAIL export bound state %s %s before=%d after=%d button=%ld\n",
                        localeDir.UTF8String, binding.UTF8String, before, after, (long)button.state);
                    return 1;
                }
            }
            window.contentView = nil;
            [window close];
            locales++;
        }
        fprintf(stdout, "SUMMARY bundled resources=%lu entries=%lu locales=%lu export-overflows=%lu\n",
            (unsigned long)resources, (unsigned long)entries, (unsigned long)locales, (unsigned long)overflows);
        return overflows ? 1 : 0;
    }
}

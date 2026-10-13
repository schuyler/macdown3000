// Exercise deferred geometry with a real NSTextView/layout manager/main queue.
// Preferences are process-local memory: no application or global domain writes.
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "MPEditorView.h"

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

static NSMutableArray<NSScrollView *> *geometryScrollContainers;

static MPEditorView *MPGeometryView(void)
{
    MPEditorView *view = [[MPEditorView alloc] initWithFrame:NSMakeRect(0, 0, 300, 200)];
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 300, 200)];
    scroll.hasVerticalScroller = YES;
    scroll.documentView = view;
    if (!geometryScrollContainers) geometryScrollContainers = [NSMutableArray array];
    [geometryScrollContainers addObject:scroll];
    view.string = @"hello\nworld";
    [view.layoutManager ensureLayoutForTextContainer:view.textContainer];
    return view;
}

int main(void)
{
    @autoreleasepool
    {
        memoryDefaults = [MPGeometryMemoryDefaults new];
        memoryDefaults.values = [NSMutableDictionary dictionary];
        Method defaultsMethod = class_getClassMethod(NSUserDefaults.class,
                                                       @selector(standardUserDefaults));
        method_setImplementation(defaultsMethod, (IMP)MPGeometryStandardDefaults);
        [NSApplication sharedApplication];

        MPEditorView *toggledView = MPGeometryView();
        toggledView.scrollsPastEnd = YES;
        toggledView.scrollsPastEnd = NO;

        MPEditorView *changedView = MPGeometryView();
        changedView.scrollsPastEnd = YES;
        changedView.string = @"updated text\nwith another line\nand a third line";
        [changedView.layoutManager ensureLayoutForTextContainer:changedView.textContainer];
        changedView.scrollsPastEnd = NO;

        MPEditorView *enabledView = MPGeometryView();
        enabledView.scrollsPastEnd = YES;
        enabledView.scrollsPastEnd = NO;
        enabledView.scrollsPastEnd = YES;

        __block NSBlockOperation *verify = nil;
        verify = [NSBlockOperation blockOperationWithBlock:^{
            for (MPEditorView *disabledView in @[toggledView, changedView])
            {
                if (!NSEqualRects(disabledView.contentRect, disabledView.frame))
                {
                    fprintf(stderr, "FAIL disabled contentRect=%s frame=%s\n",
                            NSStringFromRect(disabledView.contentRect).UTF8String,
                            NSStringFromRect(disabledView.frame).UTF8String);
                    exit(1);
                }
            }
            if (!enabledView.scrollsPastEnd ||
                NSEqualRects(enabledView.contentRect, enabledView.frame) ||
                enabledView.contentRect.size.height <= 0)
            {
                fprintf(stderr, "FAIL enabled geometry was not updated\n");
                exit(1);
            }
            NSRect expectedFrame = enabledView.frame;
            NSRect expectedContent = enabledView.contentRect;
            if (enabledView.enclosingScrollView.contentSize.height <= 0) {
                fprintf(stderr, "FAIL editor must have a positive viewport\n");
                exit(1);
            }
            for (NSUInteger i = 0; i < 30; i++) {
                [enabledView didChangeText];
                if (!NSEqualRects(expectedFrame, enabledView.frame) ||
                    !NSEqualRects(expectedContent, enabledView.contentRect)) {
                    fprintf(stderr, "FAIL enabled didChangeText grows frame on update %lu\n",
                        (unsigned long)i);
                    exit(1);
                }
                enabledView.string = @"hello\nworld";
                [enabledView.layoutManager ensureLayoutForTextContainer:enabledView.textContainer];
            }
            __block NSBlockOperation *afterStrings = nil;
            afterStrings = [NSBlockOperation blockOperationWithBlock:^{
                if (!NSEqualRects(expectedFrame, enabledView.frame) ||
                    !NSEqualRects(expectedContent, enabledView.contentRect)) {
                    fprintf(stderr, "FAIL enabled setString accumulates padding\n");
                    exit(1);
                }
                enabledView.string = [@"long line\n" stringByPaddingToLength:2000
                    withString:@"long line\n" startingAtIndex:0];
                [enabledView.layoutManager ensureLayoutForTextContainer:enabledView.textContainer];
                [enabledView didChangeText];
                if (enabledView.frame.size.height <= expectedFrame.size.height ||
                    enabledView.contentRect.size.height <= expectedContent.size.height) {
                    fprintf(stderr, "FAIL long content did not expand geometry\n");
                    exit(1);
                }
                enabledView.string = @"hello\nworld";
                [enabledView.layoutManager ensureLayoutForTextContainer:enabledView.textContainer];
                [enabledView didChangeText];
                if (!NSEqualRects(expectedFrame, enabledView.frame) ||
                    !NSEqualRects(expectedContent, enabledView.contentRect)) {
                    fprintf(stderr, "FAIL shortened content retained stale height\n");
                    exit(1);
                }
                enabledView.scrollsPastEnd = NO;
                if (!NSEqualRects(enabledView.contentRect, enabledView.frame)) {
                    fprintf(stderr, "FAIL disabled mode did not restore contentRect fallback\n");
                    exit(1);
                }
                enabledView.scrollsPastEnd = YES;
                NSBlockOperation *final = [NSBlockOperation blockOperationWithBlock:^{
                    if (!NSEqualRects(expectedFrame, enabledView.frame) ||
                        !NSEqualRects(expectedContent, enabledView.contentRect)) {
                        fprintf(stderr, "FAIL re-enable changed geometry for unchanged content\n");
                        exit(1);
                    }
                    puts("PASS attached viewport, deferred toggles, 30 repeated updates/strings, long/short content and re-enable geometry");
                    exit(0);
                }];
                for (NSOperation *operation in NSOperationQueue.mainQueue.operations)
                    if (operation != afterStrings) [final addDependency:operation];
                [NSOperationQueue.mainQueue addOperation:final];
            }];
            for (NSOperation *operation in NSOperationQueue.mainQueue.operations)
                if (operation != verify) [afterStrings addDependency:operation];
            [NSOperationQueue.mainQueue addOperation:afterStrings];
        }];
        // Drain precisely the queued production operations, then consume their
        // public result. No timer-dependent assertion or replacement layout.
        for (NSOperation *operation in NSOperationQueue.mainQueue.operations)
            [verify addDependency:operation];
        [NSOperationQueue.mainQueue addOperation:verify];
        dispatch_main();
    }
}

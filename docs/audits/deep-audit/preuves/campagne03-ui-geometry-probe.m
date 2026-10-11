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

        MPEditorView *view = MPGeometryView();
        view.scrollsPastEnd = YES;
        __block NSBlockOperation *verify = nil;
        verify = [NSBlockOperation blockOperationWithBlock:^{
            NSRect frame = view.frame;
            NSRect content = view.contentRect;
            for (NSUInteger i = 0; i < 30; i++) {
                [view didChangeText];
                if (!NSEqualRects(frame, view.frame) || !NSEqualRects(content, view.contentRect)) {
                    fprintf(stderr, "FAIL repeated enabled geometry i=%lu frame=%s expected=%s content=%s expected=%s\n",
                        (unsigned long)i, NSStringFromRect(view.frame).UTF8String,
                        NSStringFromRect(frame).UTF8String, NSStringFromRect(view.contentRect).UTF8String,
                        NSStringFromRect(content).UTF8String);
                    exit(1);
                }
                view.string = @"hello\nworld";
                [view.layoutManager ensureLayoutForTextContainer:view.textContainer];
            }
            NSBlockOperation *after = [NSBlockOperation blockOperationWithBlock:^{
                if (!NSEqualRects(frame, view.frame) || !NSEqualRects(content, view.contentRect)) {
                    fprintf(stderr, "FAIL repeated setString changed enabled geometry\n");
                    exit(1);
                }
                puts("PASS 30 enabled didChangeText and setString geometry updates remain idempotent");
                exit(0);
            }];
            for (NSOperation *operation in NSOperationQueue.mainQueue.operations)
                if (operation != verify) [after addDependency:operation];
            [NSOperationQueue.mainQueue addOperation:after];
        }];
        for (NSOperation *operation in NSOperationQueue.mainQueue.operations)
            [verify addDependency:operation];
        [NSOperationQueue.mainQueue addOperation:verify];
        dispatch_main();
    }
}

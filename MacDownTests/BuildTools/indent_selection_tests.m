#import <Cocoa/Cocoa.h>
#import "../../MacDown/Code/Extension/NSTextView+Autocomplete.h"

static BOOL check(NSString *input, NSRange range, NSString *padding,
                  NSString *expected, NSRange expectedRange)
{
    NSTextView *view = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 500, 300)];
    view.string = input;
    view.selectedRange = range;
    [view indentSelectedLinesWithPadding:padding];
    BOOL success = [view.string isEqual:expected] && NSEqualRanges(view.selectedRange, expectedRange);
    if (success) {
        [view unindentSelectedLines];
        success = [view.string isEqual:input] && NSEqualRanges(view.selectedRange, range);
    }
    fprintf(success ? stdout : stderr, "%s indent/unindent selection: %s range=%s\n",
        success ? "PASS" : "FAIL", view.string.UTF8String, NSStringFromRange(view.selectedRange).UTF8String);
    return success;
}

@interface MPMutationDelegate : NSObject <NSTextViewDelegate>
@property (strong) NSUndoManager *manager;
@property BOOL refusesChange;
@end
@implementation MPMutationDelegate
- (NSUndoManager *)undoManagerForTextView:(NSTextView *)view { return self.manager; }
- (BOOL)textView:(NSTextView *)view shouldChangeTextInRange:(NSRange)range replacementString:(NSString *)string
{ return !self.refusesChange; }
@end

static BOOL checkDeletion(NSUInteger kind, BOOL refusesChange)
{
    NSTextView *view = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 500, 300)];
    MPMutationDelegate *delegate = [MPMutationDelegate new];
    delegate.manager = [NSUndoManager new];
    delegate.manager.groupsByEvent = NO;
    delegate.refusesChange = refusesChange;
    view.delegate = delegate;
    view.allowsUndo = YES;
    NSString *original = kind == 2 ? @"- " : kind == 1 ? @"()" : @"    x";
    view.string = original;
    NSRange originalSelection = NSMakeRange(kind == 2 ? 2 : kind == 1 ? 1 : 4, 0);
    view.selectedRange = originalSelection;
    [delegate.manager removeAllActions];
    __block NSUInteger notices = 0;
    id token = [NSNotificationCenter.defaultCenter
        addObserverForName:NSTextDidChangeNotification object:view queue:nil
        usingBlock:^(NSNotification *note) { notices++; }];
    [delegate.manager beginUndoGrouping];
    BOOL handled = kind == 2 ? [view completeNextListItem:YES]
                 : kind == 1 ? [view deleteMatchingCharactersAround:1]
                             : [view unindentForSpacesBefore:4];
    [delegate.manager endUndoGrouping];
    BOOL success = handled;
    if (refusesChange) {
        success &= [view.string isEqual:original] && notices == 0
            && NSEqualRanges(view.selectedRange, originalSelection);
        if (delegate.manager.canUndo) {
            [delegate.manager undo];
            success &= [view.string isEqual:original] && notices == 0;
        }
    } else {
        success &= [view.string isEqual:kind == 2 ? @"\n" : kind == 1 ? @"" : @"x"]
            && (kind == 2 ? notices == 3 : notices == 1)
            && NSEqualRanges(view.selectedRange, NSMakeRange(kind == 2 ? 1 : 0, 0))
            && delegate.manager.canUndo;
        if (delegate.manager.canUndo) {
            [delegate.manager undo];
            success &= [view.string isEqual:original];
        }
    }
    [NSNotificationCenter.defaultCenter removeObserver:token];
    fprintf(success ? stdout : stderr, "%s %s deletion, delegate %s, notifications=%lu\n",
        success ? "PASS" : "FAIL", kind == 2 ? "empty list" : kind == 1 ? "pair" : "spaces",
        refusesChange ? "refuses" : "allows", (unsigned long)notices);
    return success;
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        BOOL success = check(@"a\n\nb", NSMakeRange(0, 4), @"    ", @"    a\n    \n    b", NSMakeRange(4, 12));
        success &= check(@"a\n\nb\n", NSMakeRange(0, 5), @"\t", @"\ta\n\t\n\tb\n", NSMakeRange(1, 7));
        success &= check(@"\n\nx", NSMakeRange(0, 3), @"    ", @"    \n    \n    x", NSMakeRange(4, 11));
        success &= check(@"ab\n\ncd", NSMakeRange(1, 4), @"    ", @"    ab\n    \n    cd", NSMakeRange(5, 12));
        success &= check(@"a\n\nb", NSMakeRange(2, 0), @"    ", @"a\n    \nb", NSMakeRange(6, 0));
        success &= check(@"", NSMakeRange(0, 0), @"    ", @"", NSMakeRange(0, 0));
        success &= checkDeletion(YES, NO);
        success &= checkDeletion(NO, NO);
        success &= checkDeletion(YES, YES);
        success &= checkDeletion(NO, YES);
        success &= checkDeletion(2, NO);
        success &= checkDeletion(2, YES);
        return success ? 0 : 1;
    }
}

//
//  MPDocumentWindowTestSupport.h
//  MacDownTests
//
//  Shared helpers for tests that need an MPDocument whose nib is loaded.
//

#import <Cocoa/Cocoa.h>
#import "MPDocument.h"

/// Creates the document's window controller if needed and loads its window
/// (never ordered front), after clearing the split-view frames that untitled
/// documents autosave under "Untitled", so each test starts from the nib's
/// both-panes layout. Returns the window, or nil if none could be loaded.
static inline NSWindow *MPLoadDocumentWindow(MPDocument *document)
{
    if (!document.fileURL)
        [[NSUserDefaults standardUserDefaults]
            removeObjectForKey:@"NSSplitView Subview Frames Untitled"];
    if (document.windowControllers.count == 0)
        [document makeWindowControllers];
    NSWindow *window = document.windowControllers.firstObject.window;
    [window.contentView layoutSubtreeIfNeeded];
    return window;
}

/// Runs the main run loop until condition returns YES or timeout passes;
/// returns the final value of condition.
static inline BOOL MPRunLoopUntil(NSTimeInterval timeout,
                                  BOOL (^condition)(void))
{
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!condition() && [deadline timeIntervalSinceNow] > 0)
    {
        [[NSRunLoop currentRunLoop]
            runMode:NSDefaultRunLoopMode
         beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    return condition();
}

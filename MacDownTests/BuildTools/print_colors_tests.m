// Exercise the same legacy WebView printing surface as MPDocument and consume
// the saved PDF. The wrapper must bound this process: printing is synchronous.
#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import <PDFKit/PDFKit.h>

@interface PrintContract : NSObject <WebFrameLoadDelegate>
@property BOOL finished;
@property BOOL success;
@property(copy) NSURL *output;
@end
@implementation PrintContract
- (void)webView:(WebView *)webView didFinishLoadForFrame:(WebFrame *)frame
{
    if (frame != webView.mainFrame) return;
    NSPrintInfo *info = [NSPrintInfo new];
    info.paperSize = NSMakeSize(612, 792);
    info.topMargin = info.bottomMargin = info.leftMargin = info.rightMargin = 36;
    info.horizontalPagination = NSFitPagination;
    info.verticalPagination = NSAutoPagination;
    info.jobDisposition = NSPrintSaveJob;
    info.dictionary[NSPrintJobSavingURL] = self.output;
    NSPrintOperation *operation = [frame.frameView printOperationWithPrintInfo:info];
    operation.showsPrintPanel = NO;
    operation.showsProgressPanel = NO;
    BOOL printed = [operation runOperation];
    PDFDocument *document = [[PDFDocument alloc] initWithURL:self.output];
    NSUInteger ink = 0;
    for (NSUInteger page = 0; page < document.pageCount; page++) {
        NSImage *thumbnail = [[document pageAtIndex:page] thumbnailOfSize:NSMakeSize(612,792) forBox:kPDFDisplayBoxMediaBox];
        NSBitmapImageRep *pixels = [NSBitmapImageRep imageRepWithData:thumbnail.TIFFRepresentation];
        for (NSInteger y = 0; y < pixels.pixelsHigh; y++) {
            for (NSInteger x = 0; x < pixels.pixelsWide; x++) {
                NSColor *color = [[pixels colorAtX:x y:y] colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];
                if (color.redComponent < 0.6 && color.greenComponent < 0.6 && color.blueComponent < 0.6) ink++;
            }
        }
    }
    // Fixture contains only one heading. A white page without dark pixels
    // demonstrates that light heading colors disappeared in the printed PDF.
    self.success = printed && document.pageCount == 1 && ink > 100;
    fprintf(self.success ? stdout : stderr, "%s printed heading consumer: %lu pages, %lu dark pixels\n",
            self.success ? "PASS" : "FAIL", (unsigned long)document.pageCount, (unsigned long)ink);
    self.finished = YES;
}
@end

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        if (argc != 5 || atoi(argv[4]) < 1 || atoi(argv[4]) > 6) return 2;
        [NSApplication sharedApplication];
        NSString *theme = [NSString stringWithContentsOfFile:@(argv[1]) encoding:NSUTF8StringEncoding error:NULL];
        NSString *printCSS = [NSString stringWithContentsOfFile:@(argv[2]) encoding:NSUTF8StringEncoding error:NULL];
        if (!theme || !printCSS) return 2;
        PrintContract *contract = [PrintContract new];
        contract.output = [NSURL fileURLWithPath:@(argv[3])];
        WebView *webView = [[WebView alloc] initWithFrame:NSMakeRect(0,0,800,600)];
        webView.frameLoadDelegate = contract;
        NSString *html = [NSString stringWithFormat:
            @"<html><head><style>%@\n%@</style></head><body><h%d>Printed heading</h%d></body></html>", theme, printCSS, atoi(argv[4]), atoi(argv[4])];
        [webView.mainFrame loadHTMLString:html baseURL:nil];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
        while (!contract.finished && deadline.timeIntervalSinceNow > 0)
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        if (!contract.finished) fprintf(stderr, "FAIL loading timeout\n");
        return contract.finished && contract.success ? 0 : 1;
    }
}

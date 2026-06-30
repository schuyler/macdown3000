#import <XCTest/XCTest.h>
#import "MPDocument.h"

@interface MPDocument (TabReuseTesting)
+ (MPDocument *)openDocumentForFileURL:(NSURL *)url;
@end

@interface MPDocumentTabReuseTests : XCTestCase
@end

@implementation MPDocumentTabReuseTests

- (void)testReturnsNilWhenNoDocumentIsOpenForURL
{
    NSURL *url = [NSURL fileURLWithPath:@"/tmp/definitely-not-open-xyz.md"];
    XCTAssertNil([MPDocument openDocumentForFileURL:url]);
}

@end

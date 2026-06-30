#import <XCTest/XCTest.h>
#import "MPFileNode.h"

@interface MPFileNodeTests : XCTestCase
@property (strong) NSURL *root;
@end

@implementation MPFileNodeTests

- (void)setUp
{
    [super setUp];
    NSString *unique = [NSProcessInfo processInfo].globallyUniqueString;
    self.root = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
                 URLByAppendingPathComponent:unique isDirectory:YES];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtURL:self.root withIntermediateDirectories:YES
                  attributes:nil error:NULL];
    // Layout:
    //   notes.md, NOTES.MARKDOWN, image.png, .hidden.md, sub/ , .git/
    [self writeFile:@"notes.md"];
    [self writeFile:@"NOTES.MARKDOWN"];
    [self writeFile:@"image.png"];
    [self writeFile:@".hidden.md"];
    [fm createDirectoryAtURL:[self.root URLByAppendingPathComponent:@"sub" isDirectory:YES]
        withIntermediateDirectories:YES attributes:nil error:NULL];
    [fm createDirectoryAtURL:[self.root URLByAppendingPathComponent:@".git" isDirectory:YES]
        withIntermediateDirectories:YES attributes:nil error:NULL];
}

- (void)tearDown
{
    [[NSFileManager defaultManager] removeItemAtURL:self.root error:NULL];
    self.root = nil;
    [super tearDown];
}

- (void)writeFile:(NSString *)name
{
    NSURL *url = [self.root URLByAppendingPathComponent:name];
    [@"# x" writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

- (void)testMarkdownDetectionIsCaseInsensitive
{
    XCTAssertTrue([MPFileNode isMarkdownFileURL:
        [NSURL fileURLWithPath:@"/a/b.md"]]);
    XCTAssertTrue([MPFileNode isMarkdownFileURL:
        [NSURL fileURLWithPath:@"/a/b.MARKDOWN"]]);
    XCTAssertFalse([MPFileNode isMarkdownFileURL:
        [NSURL fileURLWithPath:@"/a/b.png"]]);
    XCTAssertFalse([MPFileNode isMarkdownFileURL:
        [NSURL fileURLWithPath:@"/a/b"]]);
}

- (void)testChildrenFilterAndSort
{
    MPFileNode *node = [[MPFileNode alloc] initWithURL:self.root isDirectory:YES];
    NSArray<MPFileNode *> *kids = node.children;
    NSArray<NSString *> *names = [kids valueForKey:@"name"];

    // Excluded: image.png (non-md), .hidden.md (hidden), .git (hidden dir).
    // Included: sub/ (dir), notes.md, NOTES.MARKDOWN. Folders first, then by name (ci).
    XCTAssertEqualObjects(names, (@[@"sub", @"NOTES.MARKDOWN", @"notes.md"]));
    XCTAssertTrue(kids.firstObject.isDirectory);
}

- (void)testFilesHaveNoChildren
{
    NSURL *file = [self.root URLByAppendingPathComponent:@"notes.md"];
    MPFileNode *node = [[MPFileNode alloc] initWithURL:file isDirectory:NO];
    XCTAssertEqualObjects(node.children, @[]);
}

- (void)testChildrenAreCachedUntilInvalidated
{
    MPFileNode *node = [[MPFileNode alloc] initWithURL:self.root isDirectory:YES];
    NSArray *first = node.children;
    XCTAssertTrue(first == node.children, @"children should be cached (same pointer)");
    [self writeFile:@"new.md"];
    XCTAssertEqual(node.children.count, first.count, @"still cached after disk change");
    [node invalidateChildrenRecursively];
    XCTAssertEqual(node.children.count, first.count + 1, @"re-reads after invalidation");
}

@end

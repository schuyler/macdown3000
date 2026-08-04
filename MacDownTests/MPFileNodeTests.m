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

#pragma mark - Symlink cycles

- (void)linkAt:(NSString *)relativePath toURL:(NSURL *)target
{
    NSURL *link = [self.root URLByAppendingPathComponent:relativePath];
    NSError *error = nil;
    XCTAssertTrue([[NSFileManager defaultManager]
                       createSymbolicLinkAtURL:link
                            withDestinationURL:target error:&error],
                  @"could not create symlink: %@", error);
}

/// Walk the whole tree, failing rather than hanging if it never bottoms out.
- (NSUInteger)visitAllUnder:(MPFileNode *)node depth:(NSUInteger)depth
{
    XCTAssertLessThan(depth, (NSUInteger)32,
                      @"tree did not bottom out — symlink cycle guard failed");
    if (depth >= 32)
        return 0;
    NSUInteger count = 1;
    for (MPFileNode *child in node.children)
        count += [self visitAllUnder:child depth:depth + 1];
    return count;
}

- (NSArray<NSString *> *)namesOfChildrenOf:(MPFileNode *)node
{
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (MPFileNode *child in node.children)
        [names addObject:child.name];
    return names;
}

- (void)testSelfReferentialSymlinkIsNotDescended
{
    [self linkAt:@"selfloop" toURL:self.root];
    MPFileNode *node = [[MPFileNode alloc] initWithURL:self.root isDirectory:YES];
    XCTAssertFalse([[self namesOfChildrenOf:node] containsObject:@"selfloop"],
                   @"a symlink to the root itself must not become a child");
    [self visitAllUnder:node depth:0];
}

- (void)testSymlinkToAncestorIsNotDescended
{
    [self linkAt:@"sub/back" toURL:self.root];
    MPFileNode *node = [[MPFileNode alloc] initWithURL:self.root isDirectory:YES];
    MPFileNode *sub = nil;
    for (MPFileNode *child in node.children)
        if ([child.name isEqualToString:@"sub"])
            sub = child;
    XCTAssertNotNil(sub);
    XCTAssertFalse([[self namesOfChildrenOf:sub] containsObject:@"back"],
                   @"a symlink pointing at an ancestor must be dropped");
    [self visitAllUnder:node depth:0];
}

- (void)testMutuallyRecursiveSymlinksTerminate
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSURL *a = [self.root URLByAppendingPathComponent:@"a" isDirectory:YES];
    NSURL *b = [self.root URLByAppendingPathComponent:@"b" isDirectory:YES];
    [fm createDirectoryAtURL:a withIntermediateDirectories:YES
                  attributes:nil error:NULL];
    [fm createDirectoryAtURL:b withIntermediateDirectories:YES
                  attributes:nil error:NULL];
    [self linkAt:@"a/to-b" toURL:b];
    [self linkAt:@"b/to-a" toURL:a];

    MPFileNode *node = [[MPFileNode alloc] initWithURL:self.root isDirectory:YES];
    // a/to-b/to-a is a repeat of `a` on this path and must terminate there.
    XCTAssertNoThrow([self visitAllUnder:node depth:0]);
}

// The guard must only drop links that re-enter the tree, not every symlink.
- (void)testSymlinkToUnrelatedDirectoryIsKept
{
    NSString *unique = [NSProcessInfo processInfo].globallyUniqueString;
    NSURL *outside = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
                      URLByAppendingPathComponent:unique isDirectory:YES];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtURL:outside withIntermediateDirectories:YES
                  attributes:nil error:NULL];
    [@"# x" writeToURL:[outside URLByAppendingPathComponent:@"far.md"]
            atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [self linkAt:@"elsewhere" toURL:outside];

    MPFileNode *node = [[MPFileNode alloc] initWithURL:self.root isDirectory:YES];
    MPFileNode *linked = nil;
    for (MPFileNode *child in node.children)
        if ([child.name isEqualToString:@"elsewhere"])
            linked = child;
    XCTAssertNotNil(linked, @"a symlink outside the tree should still be shown");
    XCTAssertTrue([[self namesOfChildrenOf:linked] containsObject:@"far.md"]);

    [fm removeItemAtURL:outside error:NULL];
}

// Opening a symlink's own URL fails — NSDocumentController type-detects it as
// public.symlink, not Markdown — so a link must report its target instead.
- (void)testSymlinkedFileResolvesToItsTargetForOpening
{
    NSString *unique = [NSProcessInfo processInfo].globallyUniqueString;
    NSURL *outside = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
                      URLByAppendingPathComponent:unique isDirectory:YES];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtURL:outside withIntermediateDirectories:YES
                  attributes:nil error:NULL];
    NSURL *target = [outside URLByAppendingPathComponent:@"target.md"];
    [@"# x" writeToURL:target atomically:YES
              encoding:NSUTF8StringEncoding error:NULL];
    [self linkAt:@"alias.md" toURL:target];

    MPFileNode *node = [[MPFileNode alloc] initWithURL:self.root isDirectory:YES];
    MPFileNode *alias = nil;
    for (MPFileNode *child in node.children)
        if ([child.name isEqualToString:@"alias.md"])
            alias = child;

    XCTAssertNotNil(alias, @"a link to a Markdown file should be listed");
    XCTAssertEqualObjects(alias.name, @"alias.md",
                          @"the sidebar shows the link's own name");
    XCTAssertEqualObjects(alias.resolvedURL.URLByResolvingSymlinksInPath,
                          target.URLByResolvingSymlinksInPath,
                          @"but opening it must reach the target file");
    XCTAssertNotEqualObjects(alias.resolvedURL, alias.URL);

    [fm removeItemAtURL:outside error:NULL];
}

- (void)testOrdinaryFileResolvesToItself
{
    MPFileNode *node = [[MPFileNode alloc] initWithURL:self.root isDirectory:YES];
    NSUInteger checked = 0;
    for (MPFileNode *child in node.children)
    {
        if (child.isDirectory)
            continue;
        checked++;
        XCTAssertEqualObjects(child.resolvedURL, child.URL,
                              @"%@ is not a link", child.name);
    }
    XCTAssertGreaterThan(checked, 0u, @"the loop must actually assert something");
}

- (void)testBrokenSymlinkIsSkipped
{
    [self linkAt:@"dangling.md"
           toURL:[self.root URLByAppendingPathComponent:@"does-not-exist.md"]];
    MPFileNode *node = [[MPFileNode alloc] initWithURL:self.root isDirectory:YES];
    XCTAssertFalse([[self namesOfChildrenOf:node] containsObject:@"dangling.md"],
                   @"a broken symlink has nothing to open");
}

@end

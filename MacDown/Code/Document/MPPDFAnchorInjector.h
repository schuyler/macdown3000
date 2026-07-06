//
//  MPPDFAnchorInjector.h
//  MacDown 3000
//
//  Pure, headless-testable engine that injects clickable internal-anchor
//  link annotations into an already-rendered PDFDocument, using PDF-native
//  text search for geometry (never DOM coordinates).
//
//  Related to GitHub issue #504.
//

#import <Foundation/Foundation.h>
#import <PDFKit/PDFKit.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * A single internal anchor link read from the rendered document, in
 * document order: the visible link text (as it appears in the PDF, e.g.
 * inside a table of contents) and the fragment slug it targets.
 */
@interface MPPDFAnchorLink : NSObject

@property (nonatomic, copy, readonly) NSString *linkText;
@property (nonatomic, copy, readonly) NSString *targetSlug;

+ (instancetype)linkWithText:(NSString *)linkText slug:(NSString *)targetSlug;

@end


/**
 * A single heading read from the rendered document, in document order: its
 * anchor slug (the heading element's `id`) and its rendered text.
 */
@interface MPPDFAnchorHeading : NSObject

@property (nonatomic, copy, readonly) NSString *slug;
@property (nonatomic, copy, readonly) NSString *headingText;

+ (instancetype)headingWithSlug:(NSString *)slug text:(NSString *)headingText;

@end


/**
 * Injects clickable `.link` PDFAnnotations into `document` for each entry in
 * `links` whose `targetSlug` resolves to a heading in `headings`, using
 * PDF-native text search (`-[PDFDocument findString:withOptions:]`) to locate
 * both the source rect (the rendered link text) and the destination rect
 * (the rendered heading text). Mutates `document` in place. Never throws;
 * unresolvable links are silently skipped. Returns the number of annotations
 * added.
 */
@interface MPPDFAnchorInjector : NSObject

+ (NSUInteger)injectLinksIntoDocument:(PDFDocument *)document
                                 links:(NSArray<MPPDFAnchorLink *> *)links
                              headings:(NSArray<MPPDFAnchorHeading *> *)headings;

@end

NS_ASSUME_NONNULL_END

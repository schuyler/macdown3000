//
//  FileURLExt.m
//  MacDown 3000
//
//  Created by wltb on 04.01.26.
//  Copyright © 2026 Tzu-ping Chung . All rights reserved.
//

#import "FileURLInlining.h"

@implementation FileURLInlining

/** Return the collected inline content of its argument as array of NSString, or nil when nothing could be inlined
 *
 * @param iterable  enumerated objects, only NSURLs can be inlined
 * @return array of inlined content, or nil when none was found
 */
+(NSArray<NSString*>*)inlineFromIterable:(id<NSFastEnumeration>)iterable {
    NSMutableArray<NSString*> *texts = [NSMutableArray array];
    for (id item in iterable) {
        if(! [item isKindOfClass:[NSURL class]]) continue;
        FileURLInlining *file = [self withURL:item];
        if(! file) continue;
        [texts addObject: [file inlineContent]];
    }
    if(texts.count == 0) texts = nil;
    return texts;
}

+(instancetype)withURL:(NSURL *)url {
    if(! url.isFileURL) return nil;

    return [[self alloc] initWithURL:url];
}

-(NSString *)inlineContent {
    SEL selectors[2] = {@selector(imageContent), @selector(clippingContent)};
    NSString *content = nil;
    for(int i = 0; i < sizeof(selectors) / sizeof(SEL); i++) {
        content = [self performSelector:selectors[i]];
        if(content) return content;
    }
    
    return self.url.path;
}

#pragma mark private
-(instancetype)initWithURL:(NSURL *) url {
    self = [super init];
    if (self) {
        _url = url;
    }
    return self;
}

-(NSString *)imageContent
{
    NSString *mimeType = [[self class] mimeTypeForFilePath: self.url.path];
    if (!mimeType) return nil;

    // Load file data
    NSError *error;
    NSData *fileData = [NSData dataWithContentsOfFile:self.url.path
                                              options:NSDataReadingMappedIfSafe
                                                error:&error];
    if (!fileData) return nil;

    // Convert to base64 and create markdown image
    NSString *base64String = [fileData base64EncodedStringWithOptions:0];
    return [NSString stringWithFormat:@"![](data:%@;base64,%@)",
                          mimeType, base64String];

}

/** Returns the supported image MIME type for a file path, or nil if unsupported.
 *
 * Checks if the file's UTI conforms to one of the supported image types:
 * JPEG, PNG, GIF, or WebP.
 *
 * @param filePath The path to the file
 * @return The matching supported MIME type, or nil if not a supported image
 */
+ (NSString *)mimeTypeForFilePath:(NSString *)filePath
{
    NSDictionary *supportedUTIstoMIMEtype = @{
        @"public.jpeg": @"image/jpeg",
        @"public.png": @"image/png",
        @"com.compuserve.gif": @"image/gif",
        @"public.webp": @"image/webp"
    };
    
    // Get UTI from file extension
    NSString *extension = [filePath pathExtension];
    CFStringRef fileUTI = UTTypeCreatePreferredIdentifierForTag(
        kUTTagClassFilenameExtension,
        (__bridge CFStringRef)extension,
        NULL);

    if (!fileUTI) return nil;

    NSString *uti = (__bridge_transfer NSString *)fileUTI;

    // Check if the UTI conforms to any of our supported types
    for (NSString *supportedUTI in supportedUTIstoMIMEtype) {
        if (UTTypeConformsTo((__bridge CFStringRef)uti,
                             (__bridge CFStringRef)supportedUTI)) {
            return supportedUTIstoMIMEtype[supportedUTI];
        }
    }

    return nil;
}

// **********************************************************************************************************************************************

-(NSString *)clippingContent
{
    if (! [[self class] isTextClippingAtPath: self.url.path]) return nil;
    return [[self class] textContentFromClipping:self.url];
}

/** Returns whether the file at the given path is a textClipping file.
 *
 * TextClipping files are created by macOS when dragging text to Finder.
 * They have the UTI com.apple.finder.textclipping.
 *
 * @param filePath The path to the file
 * @return YES if the file is a textClipping, NO otherwise
 */
+ (BOOL)isTextClippingAtPath:(NSString *)filePath
{
    NSString *extension = [filePath pathExtension];
    CFStringRef fileUTI = UTTypeCreatePreferredIdentifierForTag(
        kUTTagClassFilenameExtension,
        (__bridge CFStringRef)extension,
        NULL);

    if (!fileUTI) return NO;

    BOOL isTextClipping = UTTypeConformsTo(fileUTI,
        CFSTR("com.apple.finder.textclipping"));
    CFRelease(fileUTI);

    return isTextClipping;
}

/** Reads the text content from a textClipping file.
 *
 * TextClipping files store their content as a binary plist. This method
 * extracts the UTF-8  text content from the file.
 *
 * @param url The file URL of the textClipping
 * @return The text content, or nil if it could not be read
 */
+ (NSString *)textContentFromClipping:(NSURL *)url
{
    NSError *error;
    NSData *fileData = [NSData dataWithContentsOfURL:url options:0 error:&error];
    if (!fileData) return nil;

    // Try to read as binary plist
    NSDictionary *plist = [NSPropertyListSerialization
        propertyListWithData:fileData
        options:NSPropertyListImmutable
        format:nil
        error:&error];

    if (![plist isKindOfClass:[NSDictionary class]]) return nil;
    NSDictionary *utiData = [plist objectForKey:@"UTI-Data"];
    if(! utiData) return nil;
    NSString *textData = [utiData objectForKey:@"public.utf8-plain-text"];
    
    return textData;
}

@end

//
//  NSDocumentController+Document.m
//  MacDown 3000
//
//  Created by Tzu-ping Chung on 25/1.
//  Copyright (c) 2015 Tzu-ping Chung . All rights reserved.
//

#import "NSDocumentController+Document.h"

@implementation NSDocumentController (Document)

- (__kindof NSDocument *)createNewEmptyDocumentForURL:(NSURL *)url
        display:(BOOL)display error:(NSError * __autoreleasing *)error
{
    if (!url.isFileURL) {
        if (error)
            *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                        code:NSFileWriteUnsupportedSchemeError
                                    userInfo:nil];
        return nil;
    }
    if (![[NSData data] writeToURL:url options:NSDataWritingWithoutOverwriting
                            error:error])
        return nil;

    NSDocument *doc = [self openUntitledDocumentAndDisplay:display
                                                     error:error];
    if (!doc)
        return doc;

    doc.draft = YES;
    doc.fileURL = url;
    return doc;
}

@end

//
//  main.m
//  macdown-cmd
//
//  Created by Esben Sorig on 30/06/2014.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import "MPCommandInput.h"
#import <AppKit/AppKit.h>
#import "MPCommandQueue.h"
#import "MPGlobals.h"
#import "MPArgumentProcessor.h"


int main(int argc, const char * argv[])
{
    @autoreleasepool
    {
        MPArgumentProcessor *argproc = [[MPArgumentProcessor alloc] init];

        if (argproc.printsHelp)
            [argproc printHelp:YES];
        else if (argproc.printsVersion)
            [argproc printVersion:YES];
        
        NSError *inputError = nil;
        NSData *dataFromPipe = MPReadCommandInput(STDIN_FILENO, &inputError);
        if (inputError) {
            fprintf(stderr, "Could not read standard input: %s\n", inputError.localizedDescription.UTF8String);
            return EXIT_FAILURE;
        }
        
        // Collect one invocation as one request. Concurrent invocations append
        // under the same filesystem lock used by the application consumer.
        NSString *pwd = [NSFileManager defaultManager].currentDirectoryPath;
        NSFileManager *fm = [NSFileManager defaultManager];
        NSMutableOrderedSet<NSURL *> *fileURLs = [NSMutableOrderedSet orderedSet];
        NSMutableOrderedSet<NSURL *> *folderURLs = [NSMutableOrderedSet orderedSet];
        for (NSString *arg in argproc.arguments)
        {
            NSURL *url = MPCommandFileURL(arg, pwd);
            BOOL isDir = NO;
            if ([fm fileExistsAtPath:url.path isDirectory:&isDir] && isDir)
                [folderURLs addObject:url];
            else
                [fileURLs addObject:url];
        }
        if (fileURLs.count || folderURLs.count || dataFromPipe) {
            NSMutableArray<NSString *> *files = [NSMutableArray array];
            NSMutableArray<NSString *> *folders = [NSMutableArray array];
            for (NSURL *url in fileURLs) [files addObject:url.path];
            for (NSURL *url in folderURLs) [folders addObject:url.path];
            NSMutableDictionary *request = [@{@"files": files, @"folders": folders} mutableCopy];
            if (dataFromPipe) request[@"pipedContent"] = dataFromPipe;
            NSError *queueError = nil;
            if (!MPCommandQueueEnqueue(MPCommandQueueDirectoryForSuite(kMPApplicationSuiteName),
                                       request, &queueError)) {
                fprintf(stderr, "Could not queue command input: %s\n", queueError.localizedDescription.UTF8String);
                return EXIT_FAILURE;
            }
        }

        // Launch MacDown.
        BOOL launched = [[NSWorkspace sharedWorkspace] launchAppWithBundleIdentifier:kMPApplicationBundleIdentifier options:NSWorkspaceLaunchDefault additionalEventParamDescriptor:nil launchIdentifier:nil];
        if (!launched) {
            fprintf(stderr, "Could not launch %s\n", kMPApplicationBundleIdentifier.UTF8String);
            return EXIT_FAILURE;
        }
    }
    return EXIT_SUCCESS;
}


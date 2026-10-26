#import <Foundation/Foundation.h>
#import "MPCommandQueue.h"

int main(int argc, char **argv) {
    @autoreleasepool {
        NSURL *directory = [NSURL fileURLWithPath:@(argv[1]) isDirectory:YES];
        NSString *mode = @(argv[2]);
        NSError *error = nil;
        if ([mode isEqual:@"enqueue"]) {
            NSUInteger count = argc > 4 ? (NSUInteger)atoi(argv[4]) : 1;
            if (argc > 5) { char go; if (read(STDIN_FILENO, &go, 1) != 1) return 2; }
            for (NSUInteger i = 0; i < count; i++) {
                NSString *path = [NSString stringWithFormat:@"/%s-%lu.md", argv[3], i];
                NSData *pipe = [NSData dataWithBytes:"input\0bytes" length:11];
                if (!MPCommandQueueEnqueue(directory, @{@"files": @[path], @"folders": @[@"/folder"], @"pipedContent": pipe}, &error)) {
                    fprintf(stderr, "%s\n", error.description.UTF8String); return 1;
                }
            }
        } else if ([mode isEqual:@"invalid"]) {
            if (MPCommandQueueEnqueue(directory, @{@"files": @[@"relative"], @"folders": @[]}, &error)) return 1;
            if (!error) return 1;
        } else if ([mode isEqual:@"large"]) {
            NSData *data = [NSMutableData dataWithLength:MPCommandQueueMaximumBytes];
            if (MPCommandQueueEnqueue(directory, @{@"files": @[], @"folders": @[], @"pipedContent": data}, &error) || !error) return 1;
        } else {
            NSUInteger times = argc > 3 ? (NSUInteger)atoi(argv[3]) : 1;
            for (NSUInteger i = 0; i < times; i++) {
                NSArray *pending = [mode isEqual:@"peek"] ? MPCommandQueueReadPending(directory, &error) : MPCommandQueueDrain(directory, &error);
                if (!pending) { fprintf(stderr, "%s\n", error.description.UTF8String); return 1; }
                for (NSDictionary *request in pending) {
                    NSData *expected = [NSData dataWithBytes:"input\0bytes" length:11];
                    if (![request[@"folders"] isEqual:@[@"/folder"]] || ![request[@"pipedContent"] isEqual:expected]) return 1;
                    NSString *path = [request[@"files"] firstObject];
                    printf("%s\n", path.UTF8String);
                }
            }
        }
    }
    return 0;
}

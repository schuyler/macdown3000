#import "../../macdown-cmd/MPCommandInput.h"
#import <dispatch/dispatch.h>
#include <assert.h>

int main(void)
{
    @autoreleasepool {
        for (NSString *name in @[@"a#b.md", @"a?b.md", @"name:part.md", @"space and %.md"]) {
            NSURL *url = MPCommandFileURL(name, @"/tmp/test input");
            assert([url.path isEqualToString:[@"/tmp/test input" stringByAppendingPathComponent:name]]);
            assert(url.isFileURL);
        }
        int descriptors[2];
        assert(pipe(descriptors) == 0);
        int writeDescriptor = descriptors[1];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
            usleep(50000); // Producer starts after the reader, exposing the old select(0) bug.
            assert(write(writeDescriptor, "delayed input", 13) == 13);
            close(writeDescriptor);
        });
        NSError *error = nil;
        NSData *data = MPReadCommandInput(descriptors[0], &error);
        close(descriptors[0]);
        assert(error == nil);
        assert([[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] isEqualToString:@"delayed input"]);
        assert(MPReadCommandInput(-1, &error) == nil);
        assert(error.code == EBADF);
        puts("CLI delayed pipe, file-name preservation and read error: passed");
    }
    return 0;
}

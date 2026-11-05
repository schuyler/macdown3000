#import <Foundation/Foundation.h>
#import <unistd.h>
#import <errno.h>
#import "MPCommandQueue.h"

// A pipe need not be readable at process startup. Wait for its producer to
// finish; interactive terminals have no redirected input to collect.
NS_INLINE NSData *MPReadCommandInput(int descriptor, NSError **error)
{
    if (isatty(descriptor)) return nil;
    NSMutableData *data = [NSMutableData data];
    uint8_t buffer[16384];
    for (;;) {
        ssize_t count = read(descriptor, buffer, sizeof(buffer));
        if (count > 0) {
            if ((NSUInteger)count > MPCommandQueueMaximumBytes - data.length) {
                if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain
                    code:EFBIG userInfo:nil];
                return nil;
            }
            [data appendBytes:buffer length:(NSUInteger)count];
        }
        else if (count == 0) return data;
        else if (errno != EINTR) {
            if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
            return nil;
        }
    }
}

NS_INLINE NSURL *MPCommandFileURL(NSString *argument, NSString *directory)
{
    NSString *path = argument.stringByExpandingTildeInPath;
    if (!path.isAbsolutePath) path = [directory stringByAppendingPathComponent:path];
    return [NSURL fileURLWithPath:path.stringByStandardizingPath];
}

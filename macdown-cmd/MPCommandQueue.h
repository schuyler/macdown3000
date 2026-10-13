// Shared CLI/application handoff. Each producer appends one request and the
// application drains a batch under the same interprocess lock. Never delete the
// lock file: its inode is the synchronization point across atomic plist writes.
#import <Foundation/Foundation.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>

static NSString *const MPCommandQueueErrorDomain = @"app.macdown.command-queue";
static const NSUInteger MPCommandQueueMaximumBytes = 32 * 1024 * 1024;

static inline BOOL MPCommandQueueFail(NSError **error, NSString *message) {
    if (error) *error = [NSError errorWithDomain:MPCommandQueueErrorDomain code:1
                                      userInfo:@{NSLocalizedDescriptionKey: message}];
    return NO;
}

static inline NSURL *MPCommandQueueDirectoryForSuite(NSString *suite) {
    NSURL *support = [[[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory
                                                            inDomains:NSUserDomainMask] firstObject];
    return [[support URLByAppendingPathComponent:suite isDirectory:YES]
                     URLByAppendingPathComponent:@"CommandQueue" isDirectory:YES];
}

static inline BOOL MPCommandQueuePathIsValid(id path) {
    return [path isKindOfClass:[NSString class]] && [path hasPrefix:@"/"]
        && [path rangeOfCharacterFromSet:[NSCharacterSet characterSetWithRange:NSMakeRange(0, 1)]].location == NSNotFound;
}

static inline BOOL MPCommandQueueRequestIsValid(id request) {
    if (![request isKindOfClass:[NSDictionary class]] || [request count] > 3)
        return NO;
    for (id key in request)
        if (![key isEqual:@"files"] && ![key isEqual:@"folders"] && ![key isEqual:@"pipedContent"])
            return NO;
    for (NSString *key in @[@"files", @"folders"]) {
        id paths = request[key];
        if (![paths isKindOfClass:[NSArray class]]) return NO;
        for (id path in paths) if (!MPCommandQueuePathIsValid(path)) return NO;
    }
    id pipe = request[@"pipedContent"];
    return !pipe || [pipe isKindOfClass:[NSData class]];
}

static inline NSArray *MPCommandQueueLoad(NSURL *file, NSError **error) {
    int descriptor = open(file.fileSystemRepresentation, O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW);
    if (descriptor < 0) {
        if (errno == ENOENT) return @[];
        MPCommandQueueFail(error, @"Cannot open pending command requests");
        return nil;
    }
    struct stat status;
    if (fstat(descriptor, &status) != 0 || !S_ISREG(status.st_mode)
        || status.st_uid != getuid() || status.st_nlink != 1 || status.st_size < 0
        || status.st_size > MPCommandQueueMaximumBytes) {
        close(descriptor);
        MPCommandQueueFail(error, @"Invalid pending command request file");
        return nil;
    }
    NSMutableData *data = [NSMutableData dataWithLength:(NSUInteger)status.st_size];
    NSUInteger offset = 0;
    while (offset < data.length) {
        ssize_t count = read(descriptor, (char *)data.mutableBytes + offset, data.length - offset);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) {
            close(descriptor);
            MPCommandQueueFail(error, @"Cannot read pending command requests");
            return nil;
        }
        offset += (NSUInteger)count;
    }
    close(descriptor);
    id requests = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable
                                                            format:NULL error:error];
    if (![requests isKindOfClass:[NSArray class]]) {
        MPCommandQueueFail(error, @"Pending command requests must be a property list array");
        return nil;
    }
    for (id request in requests) {
        if (!MPCommandQueueRequestIsValid(request)) {
            MPCommandQueueFail(error, @"Pending command request has an invalid format");
            return nil;
        }
    }
    return requests;
}

static inline BOOL MPCommandQueueSave(NSArray *requests, NSURL *file, NSError **error) {
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:requests
        format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
    if (!data) return NO;
    if (data.length > MPCommandQueueMaximumBytes)
        return MPCommandQueueFail(error, @"Pending command queue is full");
    NSString *pattern = [file.path stringByAppendingString:@".XXXXXX"];
    char *temporary = strdup(pattern.fileSystemRepresentation);
    if (!temporary) return MPCommandQueueFail(error, @"Cannot allocate command queue temporary path");
    int descriptor = mkstemp(temporary);
    BOOL written = descriptor >= 0;
    NSUInteger offset = 0;
    while (written && offset < data.length) {
        ssize_t count = write(descriptor, (const char *)data.bytes + offset, data.length - offset);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) written = NO;
        else offset += (NSUInteger)count;
    }
    if (written && fsync(descriptor) != 0) written = NO;
    if (descriptor >= 0 && close(descriptor) != 0) written = NO;
    if (written && rename(temporary, file.fileSystemRepresentation) != 0) written = NO;
    if (!written) unlink(temporary);
    free(temporary);
    return written || MPCommandQueueFail(error, @"Cannot save pending command requests");
}

// request=nil reads or drains; a nonnil request appends. All operations share
// the lock and validate the existing queue before making any change.
static inline NSArray *MPCommandQueuePerform(NSURL *directory, NSDictionary *request,
                                             BOOL drain, NSError **error) {
    if (error) *error = nil;
    if (!directory.isFileURL || (request && !MPCommandQueueRequestIsValid(request))) {
        MPCommandQueueFail(error, @"Invalid command queue directory or request");
        return nil;
    }
    NSFileManager *manager = [NSFileManager defaultManager];
    if (![manager createDirectoryAtURL:directory withIntermediateDirectories:YES
                           attributes:@{NSFilePosixPermissions: @0700} error:error]) return nil;
    struct stat directoryStatus;
    if (lstat(directory.fileSystemRepresentation, &directoryStatus) != 0
        || !S_ISDIR(directoryStatus.st_mode) || directoryStatus.st_uid != getuid()
        || (directoryStatus.st_mode & (S_IRWXG | S_IRWXO))) {
        MPCommandQueueFail(error, @"Command queue directory must be private and owned by the current user");
        return nil;
    }
    NSURL *lockFile = [directory URLByAppendingPathComponent:@".lock"];
    int lock = open(lockFile.fileSystemRepresentation, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0600);
    struct stat lockStatus;
    if (lock < 0 || fstat(lock, &lockStatus) != 0 || !S_ISREG(lockStatus.st_mode)
        || lockStatus.st_uid != getuid() || lockStatus.st_nlink != 1) {
        if (lock >= 0) close(lock);
        MPCommandQueueFail(error, @"Cannot open command queue lock");
        return nil;
    }
    int outcome;
    do { outcome = flock(lock, LOCK_EX); } while (outcome != 0 && errno == EINTR);
    if (outcome != 0) {
        close(lock);
        MPCommandQueueFail(error, @"Cannot lock pending command requests");
        return nil;
    }
    NSArray *result = nil;
    @try {
        NSURL *file = [directory URLByAppendingPathComponent:@"requests.plist"];
        NSArray *pending = MPCommandQueueLoad(file, error);
        if (pending) {
            if (request) {
                NSMutableArray *updated = [pending mutableCopy];
                [updated addObject:request];
                if (MPCommandQueueSave(updated, file, error)) result = updated;
            } else if (!drain || !pending.count || MPCommandQueueSave(@[], file, error)) {
                result = pending;
            }
        }
    } @finally {
        flock(lock, LOCK_UN);
        close(lock);
    }
    return result;
}

static inline BOOL MPCommandQueueEnqueue(NSURL *directory, NSDictionary *request, NSError **error) {
    if (!request) return MPCommandQueueFail(error, @"Missing command request");
    return MPCommandQueuePerform(directory, request, NO, error) != nil;
}
static inline NSArray *MPCommandQueueReadPending(NSURL *directory, NSError **error) {
    return MPCommandQueuePerform(directory, nil, NO, error);
}
static inline NSArray *MPCommandQueueDrain(NSURL *directory, NSError **error) {
    return MPCommandQueuePerform(directory, nil, YES, error);
}

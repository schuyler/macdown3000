#import <Foundation/Foundation.h>
#import "YAMLSerialization.h"

static void Require(BOOL condition, NSString *message) {
    if (!condition) {
        fprintf(stderr, "FAIL %s\n", message.UTF8String);
        exit(1);
    }
}
static id Parse(NSString *text, YAMLReadOptions options, NSError **error) {
    return [YAMLSerialization objectWithYAMLString:text options:options error:error];
}
static NSString *AliasGraph(NSUInteger levels) {
    NSMutableString *text = [NSMutableString stringWithString:@"n0: &n0 [x, x]\n"];
    for (NSUInteger i = 1; i <= levels; i++)
        [text appendFormat:@"n%lu: &n%lu [*n%lu, *n%lu]\n", i, i, i - 1, i - 1];
    [text appendFormat:@"title: *n%lu\n", levels];
    return text;
}
int main(void) {
    @autoreleasepool {
        NSError *error = nil;
        id object = Parse(AliasGraph(18), kYAMLReadOptionStringScalars, &error);
        Require(!object && error.code == kYAMLErrorInvalidYamlObject,
                @"Amplifying front matter must be rejected before title description allocation");
        object = Parse(@"a: &a [hello, world]\ntitle: *a\n", kYAMLReadOptionStringScalars, &error);
        Require(object && !error, @"Ordinary shared aliases must remain supported");
        Require([[[object objectForKey:@"title"] description] containsString:@"hello"],
                @"Accepted title must remain consumable by presumedFileName");
        Require([[object objectForKey:@"a"] isEqual:[object objectForKey:@"title"]], @"Alias values differ");
        object = Parse(@"&cycle [*cycle]\n", kYAMLReadOptionStringScalars, &error);
        Require(!object && error.code == kYAMLErrorInvalidYamlObject, @"Recursive aliases must remain rejected");
        NSMutableString *deep = [NSMutableString stringWithString:@"n0: &n0 x\n"];
        for (NSUInteger i = 1; i <= 260; i++)
            [deep appendFormat:@"n%lu: &n%lu [*n%lu]\n", i, i, i - 1];
        object = Parse(deep, kYAMLReadOptionStringScalars, &error);
        Require(!object && error.code == kYAMLErrorInvalidYamlObject, @"Memoized aliases must not bypass depth limit");
        NSMutableString *large = [NSMutableString stringWithString:@"scalar: &s '"];
        [large appendString:[@"x" stringByPaddingToLength:65536 withString:@"x" startingAtIndex:0]];
        [large appendString:@"'\ntitle: ["];
        for (NSUInteger i = 0; i < 300; i++) [large appendString:i ? @", *s" : @"*s"];
        [large appendString:@"]\n"];
        object = Parse(large, kYAMLReadOptionStringScalars, &error);
        Require(!object && error.code == kYAMLErrorInvalidYamlObject, @"Scalar amplification must be bounded independently of node count");
        object = Parse(@"? [a, b]\n: value\n", kYAMLReadOptionStringScalars, &error);
        Require(object && [[object objectForKey:@[@"a", @"b"]] isEqual:@"value"], @"Collection keys must keep value equality");
        object = Parse(@"items: [one, two]\n", kYAMLReadOptionStringScalars | kYAMLReadOptionMutableContainers, &error);
        [[object objectForKey:@"items"] addObject:@"three"];
        Require([[object objectForKey:@"items"] count] == 3, @"Mutable option contract changed");
        puts("PASS YAML alias expansion, scalar bytes, actual DAG depth, cycles and valid consumers");
    }
    return 0;
}

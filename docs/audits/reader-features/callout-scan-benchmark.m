#import <Foundation/Foundation.h>
#import "../../../MacDownCore/MPMarkdownPreprocessor.h"
int main(void) { @autoreleasepool {
for (NSNumber *n in @[@2000,@10000,@20000]) {
 NSMutableString *text=[@"::: {.callout-note}\nText\n:::\n" mutableCopy];
 for (int i=0;i<n.intValue;i++) [text appendString:@"A `literal` paragraph.\n"];
 NSTimeInterval start=NSDate.timeIntervalSinceReferenceDate;
 NSDictionary *prepared=MPPrepareCallouts(text);
 printf("lines=%d callouts=%lu seconds=%.6f\n",n.intValue,(unsigned long)[prepared[@"callouts"] count],NSDate.timeIntervalSinceReferenceDate-start);
}
} return 0; }

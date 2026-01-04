//
//  Untitled.h
//  MacDown 3000
//
//  Created by wltb on 04.01.26.
//  Copyright © 2026 Tzu-ping Chung . All rights reserved.
//

@interface FileURLInlining : NSObject
+(instancetype) withURL: (NSURL *) url;
-(NSString *) inlineContent;
@property (nonatomic, strong) NSURL *url;
@end

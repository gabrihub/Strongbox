//
//  AttachmentsHelper.h
//  Strongbox
//
//  Created by Strongbox on 22/12/2020.
//  Copyright © 2020 Mark McGuill. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Node.h"

NS_ASSUME_NONNULL_BEGIN

@interface MinimalPoolHelper : NSObject

+ (NSArray<DatabaseAttachment*>*)getMinimalAttachmentPool:(Node*)rootNode;
+ (NSDictionary<NSUUID*, NSData*>*)getMinimalIconPool:(Node*)rootNode;

@end

NS_ASSUME_NONNULL_END

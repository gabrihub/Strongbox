//
//  Pair.h
//  Strongbox
//
//  Created by Strongbox on 15/12/2020.
//  Copyright © 2020 Mark McGuill. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface Pair <TypeA, TypeB> : NSObject

+ (instancetype)pairOfA:(TypeA)a andB:(TypeB)b;
- (instancetype)init NS_UNAVAILABLE;

@property (readonly) TypeA a;
@property (readonly) TypeB b;

@end

NS_ASSUME_NONNULL_END

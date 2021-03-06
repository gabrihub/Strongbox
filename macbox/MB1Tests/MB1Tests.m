//
//  MB1Tests.m
//  MB1Tests
//
//  Created by Mark on 27/11/2018.
//  Copyright © 2018 Mark McGuill. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "DatabaseMetadata.h"

@interface MB1Tests : XCTestCase

@end

@implementation MB1Tests

- (void)testEmpty {
    DatabaseMetadata* metadata = [[DatabaseMetadata alloc] initWithNickName:@"Hello" storageProvider:kLocalDevice fileUrl:[NSURL URLWithString:@""] storageInfo:@""];
    
    [metadata resetConveniencePasswordWithCurrentConfiguration:@""];
    
    XCTAssertNotNil(metadata.conveniencePassword);
    XCTAssert(metadata.conveniencePassword.length == 0);
}

- (void)testNil {
    DatabaseMetadata* metadata = [[DatabaseMetadata alloc] initWithNickName:@"Hello" storageProvider:kLocalDevice fileUrl:[NSURL URLWithString:@""] storageInfo:@""];

    [metadata resetConveniencePasswordWithCurrentConfiguration:nil];
    
    XCTAssertNil(metadata.conveniencePassword);
}

- (void)testSomething {
    DatabaseMetadata* metadata = [[DatabaseMetadata alloc] initWithNickName:@"Hello" storageProvider:kLocalDevice fileUrl:[NSURL URLWithString:@""] storageInfo:@""];

    [metadata resetConveniencePasswordWithCurrentConfiguration:@"Something"];
    
    XCTAssert([metadata.conveniencePassword isEqualToString:@"Something"]);
}

@end

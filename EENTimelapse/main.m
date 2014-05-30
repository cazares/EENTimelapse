//
//  main.m
//  EENTimelapse
//
//  Created by Miguel Cazares on 5/29/14.
//  Copyright (c) 2014 EagleEye Networks. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "EENTimelapseController.h"

int main(int argc, const char * argv[])
{
  @autoreleasepool {    
    EENTimelapseController *controller = [[EENTimelapseController alloc] init];
    [controller authenticateWithUsername:@"[YOUR-USERNAME]" password:@"[YOUR-PASSWORD]"];
    [[NSRunLoop currentRunLoop] run];
  }
  return 0;
}

//
//  TimelapseController.m
//  EENTimelapse
//
//  Created by Miguel Cazares on 5/29/14.
//  Copyright (c) 2014 EagleEye Networks. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "EENTimelapseController.h"
#import <AFNetworking/AFHTTPSessionManager.h>
#import <AFNetworking/AFHTTPRequestOperationManager.h>

@interface EENTimelapseController ()

@property (nonatomic, strong) AFHTTPRequestOperationManager *manager;
@property (nonatomic, strong) NSString *sessionID;
@property (nonatomic, strong) NSString *timelapseID;
@property (nonatomic, strong) NSString *cameraID;

@end

@implementation EENTimelapseController

- (id)init {
  self = [super init];
  if (self) {
    self.manager = [AFHTTPRequestOperationManager manager];
    self.manager.requestSerializer = [AFJSONRequestSerializer serializer];
    self.manager.responseSerializer = [AFHTTPResponseSerializer serializer];
  }
  return self;
}

- (void)authenticateWithUsername:(NSString *)username
                        password:(NSString *)password {
  NSDictionary *parameters = @{ @"username": username,
                                @"password": password };
  [self.manager POST:@"https://login.eagleeyenetworks.com/g/aaa/authenticate"
parameters:parameters
  success:^(AFHTTPRequestOperation *operation, id responseObject) {
    NSError *error;
    NSDictionary *response = [NSJSONSerialization JSONObjectWithData:responseObject
                                                             options:NSJSONReadingAllowFragments
                                                               error:&error];
    [self authorizeUserWithToken:response[@"token"]];
  }
  failure:^(AFHTTPRequestOperation *operation, NSError *error) {
    NSLog(@"Error: %@", error);
  }];
}

- (void)authorizeUserWithToken:(NSString *)token {
  NSDictionary *parameters = @{ @"token": token };
  [self.manager POST:@"https://login.eagleeyenetworks.com/g/aaa/authorize"
parameters:parameters
  success:^(AFHTTPRequestOperation *operation, id responseObject) {
    NSArray *cookies = [NSHTTPCookie cookiesWithResponseHeaderFields:operation.response.allHeaderFields
                                                              forURL:operation.response.URL];
    if (cookies.count > 0) {
      NSHTTPCookie *cookie = (NSHTTPCookie *)cookies[0];
      self.sessionID = cookie.value;
    }
    [self getDeviceListAndRequestTimelapseOnSuccess];
  }
  failure:^(AFHTTPRequestOperation *operation, NSError *error) {
    NSLog(@"Error: %@", error);
  }];
}

- (void)getDeviceListAndRequestTimelapseOnSuccess {
  // specify device type of camera
  NSDictionary *parameters = @{ @"t": @"camera",
                                @"A": self.sessionID };
  [self.manager GET:@"https://login.eagleeyenetworks.com/g/device/list"
parameters:parameters
   success:^(AFHTTPRequestOperation *operation, id responseObject) {
     NSError *error;
     NSArray *response = [NSJSONSerialization JSONObjectWithData:responseObject
                                                         options:NSJSONReadingMutableContainers
                                                           error:&error];
     // see https://apidocs.eagleeyenetworks.com/apidocs/#!/device/deviceList_get_4
     // for indexing of subarrays and parsing more information
     // from the /device/list api call
     for (NSArray *subarray in response) {
       int cameraStatus = [subarray[10] intValue];
       BOOL cameraRegistered = (cameraStatus & (1 << 0)) != 0;
       BOOL cameraOnline = (cameraStatus & (1 << 1)) != 0;
       BOOL cameraOn = (cameraStatus & (1 << 2)) != 0;
       if (!cameraOn || !cameraRegistered || !cameraOnline) {
         continue;
       }
       // for the purposes of this example, we'll just request timelapse for first camera
       self.cameraID = subarray[1];
       [self putTimelapseWithStartTimeString:@"20140530163000.000"
                               endTimeString:@"20140530163500.000"];
       break;
     }
   }
   failure:^(AFHTTPRequestOperation *operation, NSError *error) {
     NSLog(@"Error: %@", error);
   }];
}

bool timelapseReadyToDownload = false;
- (void)putTimelapseWithStartTimeString:(NSString *)startTimeString
                          endTimeString:(NSString *)endTimeString {
  NSDictionary *parameters = @{ @"device_id": self.cameraID,
                                @"start_timestamp": startTimeString,
                                @"end_timestamp": endTimeString,
                                @"A": self.sessionID };
  [self.manager PUT:@"https://login.eagleeyenetworks.com/g/time_lapse"
parameters:parameters
   success:^(AFHTTPRequestOperation *operation, id responseObject) {
     NSError *error;
     NSDictionary *response = [NSJSONSerialization JSONObjectWithData:responseObject
                                                              options:NSJSONReadingAllowFragments
                                                                error:&error];
     self.timelapseID = response[@"id"];
     [NSTimer scheduledTimerWithTimeInterval:1.0
                                      target:self
                                    selector:@selector(checkTimelapseProgress)
                                    userInfo:nil
                                     repeats:YES];
   }
   failure:^(AFHTTPRequestOperation *operation, NSError *error) {
     NSLog(@"Error: %@", error);
   }];
}

- (void)checkTimelapseProgress {
  if (timelapseReadyToDownload) {
    return;
  }
  NSDictionary *parameters = @{ @"id": self.timelapseID,
                                @"device_id": self.cameraID,
                                @"A": self.sessionID };
  [self.manager GET:@"https://login.eagleeyenetworks.com/g/time_lapse"
parameters:parameters
   success:^(AFHTTPRequestOperation *operation, id responseObject) {
     NSError *error;
     NSDictionary *response = [NSJSONSerialization JSONObjectWithData:responseObject
                                                              options:NSJSONReadingAllowFragments
                                                                error:&error];
     CGFloat percentComplete = (CGFloat)[response[@"percent_complete"] floatValue];
     NSString *downloadUrl = (NSString *)response[@"url"];
     if (percentComplete >= 100.0f && downloadUrl) {
       NSLog(@"Ready for download!");
       NSLog(@"Here's your url to download the video: %@", downloadUrl);
       NSLog(@"Your session id is: %@", self.sessionID);
       timelapseReadyToDownload = true;
       downloadUrl = [NSString stringWithFormat:@"%@?A=%@", downloadUrl, self.sessionID];
       [self playVideoFromDownloadUrl:downloadUrl];
     }
     else {
       NSLog(@"percent complete: %f", percentComplete);
     }
   }
   failure:^(AFHTTPRequestOperation *operation, NSError *error) {
     NSLog(@"Error: %@", error);
   }];
}

- (void)playVideoFromDownloadUrl:(NSString *)downloadUrl {
#if TARGET_OS_IPHONE
  NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:downloadUrl]];
  AFHTTPRequestOperation *operation = [[AFHTTPRequestOperation alloc] initWithRequest:request];
  NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
  NSString *path = [[paths objectAtIndex:0] stringByAppendingPathComponent:@"een-timelapse.mp4"];
  operation.outputStream = [NSOutputStream outputStreamToFileAtPath:path append:NO];
  [operation setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject) {
    NSLog(@"Successfully downloaded file to %@", path);
    NSURL *contentUrl = [NSURL fileURLWithPath:path];
    MPMoviePlayerViewController *videoController = [[MPMoviePlayerViewController alloc] initWithContentURL:contentUrl];
    videoController.moviePlayer.movieSourceType = MPMovieSourceTypeFile;
    [videoController.moviePlayer prepareToPlay];
    [videoController.moviePlayer play];
    [self presentMoviePlayerViewControllerAnimated:videoController];
  } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
    NSLog(@"%@", error);
  }];
  [operation start];
#else
  NSString *commandString = [NSString stringWithFormat:@"open %@", downloadUrl];
  system([commandString cStringUsingEncoding:NSUTF8StringEncoding]);
#endif
}

@end

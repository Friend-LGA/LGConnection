//
//  LGConnection.m
//  LGConnection
//
//
//  The MIT License (MIT)
//
//  Copyright (c) 2015 Grigory Lutkov <Friend.LGA@gmail.com>
//  (https://github.com/Friend-LGA/LGConnection)
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

#import "LGConnection.h"
#import "LGHelper.h"
#import "XMLReader.h"
#import "UIProgressView+AFNetworking.h"
#import "UIKit+AFNetworking.h"
#import "Reachability.h"
#import "NSData+LGHelper.h"

static NSInteger const kErrorCodeNotModified = -1011;

@interface LGConnection ()

typedef enum
{
    RequestTypeStandard,
    RequestTypeMultipartData,
    RequestTypeMultipartDataArray,
    RequestTypeMultipartPathsArray,
    RequestTypeMultipartConstructor,
    RequestTypeDownload
}
RequestType;

@property (strong, nonatomic) Reachability      *reachability;
@property (strong, nonatomic) NSMutableArray    *managersArray;
@property (strong, nonatomic) NSMutableArray    *savedRequestsArray;

@property (strong, nonatomic) void (^connectionLostHandler)();
@property (strong, nonatomic) void (^connectionRestoreHandler)();

@end

@implementation LGConnection

- (instancetype)initWithRepeatAfterConnectionLost:(BOOL)repeat
                  connectionLostHandler:(void(^)())connectionLostHandler
               connectionRestoreHandler:(void(^)())connectionRestoreHandler
{
    self = [super init];
    if (self)
    {
        _managersArray = [NSMutableArray new];
        
        // -----
        
        _reachability = [Reachability reachabilityForInternetConnection];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reachabilityChanged:) name:kReachabilityChangedNotification object:_reachability];
        [_reachability startNotifier];
        
        // -----
        
        if (repeat)
            _savedRequestsArray = [NSMutableArray new];
        
        _connectionLostHandler = connectionLostHandler;
        _connectionRestoreHandler = connectionRestoreHandler;
        
        _cookiesShouldHandle = NO;
        
        _timeoutInterval = 60.0;
    }
    return self;
}

- (instancetype)initWithRepeatAfterConnectionLost:(BOOL)repeat
{
    return [self initWithRepeatAfterConnectionLost:repeat
                             connectionLostHandler:nil
                          connectionRestoreHandler:nil];
}

- (instancetype)init
{
    return [self initWithRepeatAfterConnectionLost:NO];
}

+ (instancetype)connectionWithRepeatAfterConnectionLost:(BOOL)repeat
{
    return [[self alloc] initWithRepeatAfterConnectionLost:repeat];
}

+ (instancetype)connectionWithRepeatAfterConnectionLost:(BOOL)repeat
                        connectionLostHandler:(void(^)())connectionLostHandler
                     connectionRestoreHandler:(void(^)())connectionRestoreHandler
{
    return [[self alloc] initWithRepeatAfterConnectionLost:repeat
                                     connectionLostHandler:connectionLostHandler
                                  connectionRestoreHandler:connectionRestoreHandler];
}

#pragma mark - Dealloc

- (void)dealloc
{
    NSLog(@"%s", __PRETTY_FUNCTION__);
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kReachabilityChangedNotification object:nil];
    [_reachability stopNotifier];
}

#pragma mark - Reachability Notifications

- (BOOL)isConnectionAvailable
{
    return [_reachability currentReachabilityStatus];
}

- (void)reachabilityChanged:(NSNotification *)notification
{
    if (_savedRequestsArray)
    {
        Reachability *reachability = notification.object;
        
        if ([reachability isEqual:_reachability] && reachability.currentReachabilityStatus != NotReachable)
        {
            if (_connectionRestoreHandler) _connectionRestoreHandler();
            
            if (_savedRequestsArray.count)
            {
                for ( ; ; )
                {
                    NSDictionary *savedRequest = _savedRequestsArray.firstObject;
                    
                    if ([savedRequest[@"type"] intValue] == RequestTypeStandard)
                    {
                        [self sendRequestToUrl:savedRequest[@"urlString"]
                                        method:[savedRequest[@"method"] intValue]
                                    parameters:savedRequest[@"parameters"]
                                  responseType:[savedRequest[@"responseType"] intValue]
                                  setupHandler:savedRequest[@"setupHandler"]
                             completionHandler:savedRequest[@"completionHandler"]];
                    }
                    else if ([savedRequest[@"type"] intValue] == RequestTypeMultipartData)
                    {
                        [self sendMultipartRequestToUrl:savedRequest[@"urlString"]
                                             parameters:savedRequest[@"parameters"]
                                                   name:savedRequest[@"name"]
                                                   data:savedRequest[@"data"]
                                          fileExtension:savedRequest[@"fileExtension"]
                                           responseType:[savedRequest[@"responseType"] intValue]
                                        progressHandler:savedRequest[@"progressHandler"]
                                      completionHandler:savedRequest[@"completionHandler"]];
                    }
                    else if ([savedRequest[@"type"] intValue] == RequestTypeMultipartDataArray)
                    {
                        [self sendMultipartRequestToUrl:savedRequest[@"urlString"]
                                             parameters:savedRequest[@"parameters"]
                                                   name:savedRequest[@"name"]
                                              dataArray:savedRequest[@"dataArray"]
                                          fileExtension:savedRequest[@"fileExtension"]
                                           responseType:[savedRequest[@"responseType"] intValue]
                                        progressHandler:savedRequest[@"progressHandler"]
                                      completionHandler:savedRequest[@"completionHandler"]];
                    }
                    else if ([savedRequest[@"type"] intValue] == RequestTypeMultipartPathsArray)
                    {
                        [self sendMultipartRequestToUrl:savedRequest[@"urlString"]
                                             parameters:savedRequest[@"parameters"]
                                                   name:savedRequest[@"name"]
                                         filePathsArray:savedRequest[@"filePathsArray"]
                                           responseType:[savedRequest[@"responseType"] intValue]
                                        progressHandler:savedRequest[@"progressHandler"]
                                      completionHandler:savedRequest[@"completionHandler"]];
                    }
                    else if ([savedRequest[@"type"] intValue] == RequestTypeMultipartConstructor)
                    {
                        [self sendMultipartRequestToUrl:savedRequest[@"urlString"]
                                             parameters:savedRequest[@"parameters"]
                              constructingBodyWithBlock:savedRequest[@"constructingBodyWithBlock"]
                                           responseType:[savedRequest[@"responseType"] intValue]
                                        progressHandler:savedRequest[@"progressHandler"]
                                      completionHandler:savedRequest[@"completionHandler"]];
                    }
                    else if ([savedRequest[@"type"] intValue] == RequestTypeDownload)
                    {
                        [self downloadFileFromURL:savedRequest[@"urlString"]
                                       toLocalUrl:savedRequest[@"localString"]
                               useModifiedControl:[savedRequest[@"useModifiedControl"] boolValue]
                                  progressHandler:savedRequest[@"progressHandler"]
                                completionHandler:savedRequest[@"completionHandler"]];
                    }
                    
                    [_savedRequestsArray removeObjectAtIndex:0];
                    
                    if (!_savedRequestsArray.count) break;
                }
            }
        }
    }
}

#pragma mark - AFNetworking
#pragma mark Get / Post

- (void)sendRequestToUrl:(NSURL *)url
                  method:(LGConnectionMethod)method
              parameters:(id)parameters
            responseType:(LGConnectionResponseType)responseType
            setupHandler:(void(^)(AFHTTPRequestOperationManager *manager))setupHandler
       completionHandler:(void(^)(NSError *error, id responseObject))completionHandler
{
    NSString *urlString = ([url isKindOfClass:[NSString class]] ? (NSString *)url : [NSString stringWithFormat:@"%@", url]);
    
    AFHTTPRequestOperationManager *manager = [AFHTTPRequestOperationManager manager];
    
    if (responseType == LGConnectionResponseTypeJSON)
    {
        AFJSONRequestSerializer *requestSerializer = [AFJSONRequestSerializer serializer];
        requestSerializer.HTTPShouldHandleCookies = _cookiesShouldHandle;
        requestSerializer.timeoutInterval = _timeoutInterval;
        manager.requestSerializer = requestSerializer;
    }
    else
    {
        AFHTTPRequestSerializer *requestSerializer = [AFHTTPRequestSerializer serializer];
        requestSerializer.HTTPShouldHandleCookies = _cookiesShouldHandle;
        requestSerializer.timeoutInterval = _timeoutInterval;
        manager.requestSerializer = requestSerializer;
    }
    
    if (setupHandler) setupHandler(manager);
    
    [_managersArray addObject:manager];
    
    // -----
    
    AFHTTPRequestOperation *operation;
    
    if (method == LGConnectionMethodPOST || method == LGConnectionMethodJSON)
    {
        operation = [manager POST:urlString
                       parameters:parameters
                          success:^(AFHTTPRequestOperation *operation, NSData *responseData)
                     {
                         //NSLog(@"statusCode: %i", (int)[operation.response statusCode]);
                         //NSLog(@"allHeaderFields: %@", [operation.response allHeaderFields]);
                         
                         [self parseResponseData:responseData responseType:responseType operation:operation completionHandler:completionHandler];
                         
                         [manager.operationQueue cancelAllOperations];
                         [_managersArray removeObject:manager];
                     }
                          failure:^(AFHTTPRequestOperation *operation, NSError *error)
                     {
                         if (!self.isConnectionAvailable)
                         {
                             if (_savedRequestsArray)
                             {
                                 NSMutableDictionary *savedRequest = [NSMutableDictionary new];
                                 [savedRequest setObject:[NSNumber numberWithInt:RequestTypeStandard] forKey:@"type"];
                                 [savedRequest setObject:urlString forKey:@"urlString"];
                                 [savedRequest setObject:[NSNumber numberWithInt:method] forKey:@"method"];
                                 if (parameters) [savedRequest setObject:parameters forKey:@"parameters"];
                                 [savedRequest setObject:[NSNumber numberWithInt:responseType] forKey:@"responseType"];
                                 if (setupHandler) [savedRequest setObject:setupHandler forKey:@"setupHandler"];
                                 if (completionHandler) [savedRequest setObject:completionHandler forKey:@"completionHandler"];
                                 
                                 BOOL isExist = NO;
                                 
                                 for (NSDictionary *dictionary in _savedRequestsArray)
                                     if ([dictionary isEqualToDictionary:savedRequest])
                                         isExist = YES;
                                 
                                 if (!isExist) [_savedRequestsArray addObject:savedRequest];
                             }
                             else if (completionHandler) completionHandler(error, nil);
                             
                             if (_connectionLostHandler) _connectionLostHandler();
                         }
                         else
                         {
                             if (completionHandler) completionHandler(error, nil);
                             
                             [manager.operationQueue cancelAllOperations];
                             [_managersArray removeObject:manager];
                         }
                     }];
    }
    else
    {
        operation = [manager GET:urlString
                      parameters:parameters
                         success:^(AFHTTPRequestOperation *operation, NSData *responseData)
                     {
                         [self parseResponseData:responseData responseType:responseType operation:operation completionHandler:completionHandler];
                         
                         [manager.operationQueue cancelAllOperations];
                         [_managersArray removeObject:manager];
                     }
                         failure:^(AFHTTPRequestOperation *operation, NSError *error)
                     {
                         if (!self.isConnectionAvailable)
                         {
                             if (_savedRequestsArray)
                             {
                                 NSMutableDictionary *savedRequest = [NSMutableDictionary new];
                                 [savedRequest setObject:[NSNumber numberWithInt:RequestTypeStandard] forKey:@"type"];
                                 [savedRequest setObject:urlString forKey:@"urlString"];
                                 [savedRequest setObject:[NSNumber numberWithInt:method] forKey:@"method"];
                                 if (parameters) [savedRequest setObject:parameters forKey:@"parameters"];
                                 [savedRequest setObject:[NSNumber numberWithInt:responseType] forKey:@"responseType"];
                                 if (completionHandler) [savedRequest setObject:completionHandler forKey:@"completionHandler"];
                                 
                                 BOOL isExist = NO;
                                 
                                 for (NSDictionary *dictionary in _savedRequestsArray)
                                     if ([dictionary isEqualToDictionary:savedRequest])
                                         isExist = YES;
                                 
                                 if (!isExist) [_savedRequestsArray addObject:savedRequest];
                             }
                             else if (completionHandler) completionHandler(error, nil);
                             
                             if (_connectionLostHandler) _connectionLostHandler();
                         }
                         else
                         {
                             if (completionHandler) completionHandler(error, nil);
                             
                             [manager.operationQueue cancelAllOperations];
                             [_managersArray removeObject:manager];
                         }
                     }];
    }
    
    [operation setShouldExecuteAsBackgroundTaskWithExpirationHandler:^(void)
     {
         /*
          [[[UIAlertView alloc] initWithTitle:@"Ошибка"
          message:@"Допустимое время фоновой загрузки файла было превышено."
          delegate:nil
          cancelButtonTitle:@"ОК"
          otherButtonTitles:nil] show];
          */
     }];
}

#pragma mark - Multipart

- (void)sendMultipartRequestToUrl:(NSURL *)url
                       parameters:(id)parameters
                             name:(NSString *)name
                             data:(NSData *)data
                    fileExtension:(NSString *)fileExtension
                     responseType:(LGConnectionResponseType)responseType
                  progressHandler:(void(^)(long long totalBytesExpectedToRead, long long totalBytesRead, float progress, NSUInteger downloadPercentage))progressHandler
                completionHandler:(void(^)(NSError *error, id responseObject))completionHandler
{
    NSString *urlString = ([url isKindOfClass:[NSString class]] ? (NSString *)url : [NSString stringWithFormat:@"%@", url]);
    
    AFHTTPRequestOperationManager *manager = [AFHTTPRequestOperationManager manager];
    manager.responseSerializer = [AFHTTPResponseSerializer serializer];
    manager.requestSerializer.HTTPShouldHandleCookies = _cookiesShouldHandle;
    manager.requestSerializer.timeoutInterval = _timeoutInterval;
    
    [_managersArray addObject:manager];
    
    AFHTTPRequestOperation *operation = [manager POST:urlString
                                           parameters:parameters
                            constructingBodyWithBlock:^(id<AFMultipartFormData> formData)
                                         {
                                             NSString *mimeType = [LGHelper mimeTypeForExtension:fileExtension];
                                             
                                             if (mimeType.length)
                                                 [formData appendPartWithFileData:data
                                                                             name:name
                                                                         fileName:[NSString stringWithFormat:@"file_%@.%@", [data md5Hash], fileExtension]
                                                                         mimeType:mimeType];
                                             else
                                                 [formData appendPartWithFormData:data
                                                                             name:name];
                                         }
                                              success:^(AFHTTPRequestOperation *operation, NSData *responseData)
                                         {
                                             [self parseResponseData:responseData responseType:responseType operation:operation completionHandler:completionHandler];
                                             
                                             [manager.operationQueue cancelAllOperations];
                                             [_managersArray removeObject:manager];
                                         }
                                              failure:^(AFHTTPRequestOperation *operation, NSError *error)
                                         {
                                             if (!self.isConnectionAvailable)
                                             {
                                                 if (_savedRequestsArray)
                                                 {
                                                     NSMutableDictionary *savedRequest = [NSMutableDictionary new];
                                                     [savedRequest setObject:[NSNumber numberWithInt:RequestTypeMultipartData] forKey:@"type"];
                                                     [savedRequest setObject:urlString forKey:@"urlString"];
                                                     if (parameters) [savedRequest setObject:parameters forKey:@"parameters"];
                                                     [savedRequest setObject:name forKey:@"name"];
                                                     [savedRequest setObject:data forKey:@"data"];
                                                     [savedRequest setObject:fileExtension forKey:@"fileExtension"];
                                                     [savedRequest setObject:[NSNumber numberWithInt:responseType] forKey:@"responseType"];
                                                     if (progressHandler) [savedRequest setObject:progressHandler forKey:@"progressHandler"];
                                                     if (completionHandler) [savedRequest setObject:completionHandler forKey:@"completionHandler"];
                                                     
                                                     BOOL isExist = NO;
                                                     
                                                     for (NSDictionary *dictionary in _savedRequestsArray)
                                                         if ([dictionary isEqualToDictionary:savedRequest])
                                                             isExist = YES;
                                                     
                                                     if (!isExist) [_savedRequestsArray addObject:savedRequest];
                                                 }
                                                 else if (completionHandler) completionHandler(error, nil);
                                                 
                                                 if (_connectionLostHandler) _connectionLostHandler();
                                             }
                                             else
                                             {
                                                 if (completionHandler) completionHandler(error, nil);
                                                 
                                                 [manager.operationQueue cancelAllOperations];
                                                 [_managersArray removeObject:manager];
                                             }
                                         }];
    
    [operation setShouldExecuteAsBackgroundTaskWithExpirationHandler:^(void)
     {
         /*
          [[[UIAlertView alloc] initWithTitle:@"Ошибка"
          message:@"Допустимое время фоновой загрузки файла было превышено."
          delegate:nil
          cancelButtonTitle:@"ОК"
          otherButtonTitles:nil] show];
          */
     }];
    
    if (progressHandler)
    {
        [operation setUploadProgressBlock:^(NSUInteger bytesRead, long long totalBytesRead, long long totalBytesExpectedToRead)
         {
             float progress = (float)totalBytesRead/(float)totalBytesExpectedToRead;
             
             NSUInteger downloadPercentage = (float)progress * (float)100;
             if (downloadPercentage > 100) downloadPercentage = 100;
             
             progressHandler(totalBytesExpectedToRead, totalBytesRead, progress, downloadPercentage);
             
             //NSLog(@"%lld | %lld | %lld", totalBytesExpectedToRead, totalBytesRead, (long long)bytesRead);
             //NSLog(@"progress: %.2f %%", downloadPercentage*100);
         }];
    }
}

- (void)sendMultipartRequestToUrl:(NSURL *)url
                       parameters:(id)parameters
                             name:(NSString *)name
                        dataArray:(NSArray *)dataArray
                    fileExtension:(NSString *)fileExtension
                     responseType:(LGConnectionResponseType)responseType
                  progressHandler:(void(^)(long long totalBytesExpectedToRead, long long totalBytesRead, float progress, NSUInteger downloadPercentage))progressHandler
                completionHandler:(void(^)(NSError *error, id responseObject))completionHandler
{
    NSString *urlString = ([url isKindOfClass:[NSString class]] ? (NSString *)url : [NSString stringWithFormat:@"%@", url]);
    
    AFHTTPRequestOperationManager *manager = [AFHTTPRequestOperationManager manager];
    manager.responseSerializer = [AFHTTPResponseSerializer serializer];
    manager.requestSerializer.HTTPShouldHandleCookies = _cookiesShouldHandle;
    manager.requestSerializer.timeoutInterval = _timeoutInterval;
    
    [_managersArray addObject:manager];
    
    NSString *mimeType = [LGHelper mimeTypeForExtension:fileExtension];
    
    AFHTTPRequestOperation *operation = [manager POST:urlString
                                           parameters:parameters
                            constructingBodyWithBlock:^(id<AFMultipartFormData> formData)
                                         {
                                             for (NSUInteger i=0; i<dataArray.count; i++)
                                             {
                                                 NSString *nameString = [NSString stringWithFormat:@"%@[%i]", name, (int)i];
                                                 
                                                 if (mimeType.length)
                                                     [formData appendPartWithFileData:dataArray[i]
                                                                                 name:nameString
                                                                             fileName:[NSString stringWithFormat:@"file_%i_%@.%@", (int)i, [(NSData *)dataArray[i] md5Hash], fileExtension]
                                                                             mimeType:mimeType];
                                                 else
                                                     [formData appendPartWithFormData:dataArray[i]
                                                                                 name:nameString];
                                             }
                                         }
                                              success:^(AFHTTPRequestOperation *operation, NSData *responseData)
                                         {
                                             [self parseResponseData:responseData responseType:responseType operation:operation completionHandler:completionHandler];
                                             
                                             [manager.operationQueue cancelAllOperations];
                                             [_managersArray removeObject:manager];
                                         }
                                              failure:^(AFHTTPRequestOperation *operation, NSError *error)
                                         {
                                             if (!self.isConnectionAvailable)
                                             {
                                                 if (_savedRequestsArray)
                                                 {
                                                     NSMutableDictionary *savedRequest = [NSMutableDictionary new];
                                                     [savedRequest setObject:[NSNumber numberWithInt:RequestTypeMultipartDataArray] forKey:@"type"];
                                                     [savedRequest setObject:urlString forKey:@"urlString"];
                                                     if (parameters) [savedRequest setObject:parameters forKey:@"parameters"];
                                                     [savedRequest setObject:name forKey:@"name"];
                                                     [savedRequest setObject:dataArray forKey:@"dataArray"];
                                                     [savedRequest setObject:fileExtension forKey:@"fileExtension"];
                                                     [savedRequest setObject:[NSNumber numberWithInt:responseType] forKey:@"responseType"];
                                                     if (progressHandler) [savedRequest setObject:progressHandler forKey:@"progressHandler"];
                                                     if (completionHandler) [savedRequest setObject:completionHandler forKey:@"completionHandler"];
                                                     
                                                     BOOL isExist = NO;
                                                     
                                                     for (NSDictionary *dictionary in _savedRequestsArray)
                                                         if ([dictionary isEqualToDictionary:savedRequest])
                                                             isExist = YES;
                                                     
                                                     if (!isExist) [_savedRequestsArray addObject:savedRequest];
                                                 }
                                                 else if (completionHandler) completionHandler(error, nil);
                                                 
                                                 if (_connectionLostHandler) _connectionLostHandler();
                                             }
                                             else
                                             {
                                                 if (completionHandler) completionHandler(error, nil);
                                                 
                                                 [manager.operationQueue cancelAllOperations];
                                                 [_managersArray removeObject:manager];
                                             }
                                         }];
    
    [operation setShouldExecuteAsBackgroundTaskWithExpirationHandler:^(void)
     {
         /*
          [[[UIAlertView alloc] initWithTitle:@"Ошибка"
          message:@"Допустимое время фоновой загрузки файла было превышено."
          delegate:nil
          cancelButtonTitle:@"ОК"
          otherButtonTitles:nil] show];
          */
     }];
    
    if (progressHandler)
    {
        [operation setUploadProgressBlock:^(NSUInteger bytesRead, long long totalBytesRead, long long totalBytesExpectedToRead)
         {
             float progress = (float)totalBytesRead/(float)totalBytesExpectedToRead;
             
             NSUInteger downloadPercentage = (float)progress * (float)100;
             if (downloadPercentage > 100) downloadPercentage = 100;
             
             progressHandler(totalBytesExpectedToRead, totalBytesRead, progress, downloadPercentage);
             
             //NSLog(@"%lld | %lld | %lld", totalBytesExpectedToRead, totalBytesRead, (long long)bytesRead);
             //NSLog(@"progress: %.2f %%", downloadPercentage*100);
         }];
    }
}

- (void)sendMultipartRequestToUrl:(NSURL *)url
                       parameters:(id)parameters
                             name:(NSString *)name
                    fileUrlsArray:(NSArray *)fileUrlsArray
                     responseType:(LGConnectionResponseType)responseType
                  progressHandler:(void(^)(long long totalBytesExpectedToRead, long long totalBytesRead, float progress, NSUInteger downloadPercentage))progressHandler
                completionHandler:(void(^)(NSError *error, id responseObject))completionHandler
{
    NSMutableArray *filePathsArray = [NSMutableArray new];
    
    for (NSURL *fileUrl in fileUrlsArray)
        [filePathsArray addObject:fileUrl.path];
    
    [self sendMultipartRequestToUrl:url
                         parameters:parameters
                               name:name
                     filePathsArray:filePathsArray
                       responseType:responseType
                    progressHandler:progressHandler
                  completionHandler:completionHandler];
}

- (void)sendMultipartRequestToUrl:(NSURL *)url
                       parameters:(id)parameters
                             name:(NSString *)name
                   filePathsArray:(NSArray *)filePathsArray
                     responseType:(LGConnectionResponseType)responseType
                  progressHandler:(void(^)(long long totalBytesExpectedToRead, long long totalBytesRead, float progress, NSUInteger downloadPercentage))progressHandler
                completionHandler:(void(^)(NSError *error, id responseObject))completionHandler
{
    NSString *urlString = ([url isKindOfClass:[NSString class]] ? (NSString *)url : [NSString stringWithFormat:@"%@", url]);
    
    AFHTTPRequestOperationManager *manager = [AFHTTPRequestOperationManager manager];
    manager.responseSerializer = [AFHTTPResponseSerializer serializer];
    manager.requestSerializer.HTTPShouldHandleCookies = _cookiesShouldHandle;
    manager.requestSerializer.timeoutInterval = _timeoutInterval;
    
    [_managersArray addObject:manager];
    
    AFHTTPRequestOperation *operation = [manager POST:urlString
                                           parameters:parameters
                            constructingBodyWithBlock:^(id<AFMultipartFormData> formData)
                                         {
                                             for (NSUInteger i=0; i<filePathsArray.count; i++)
                                             {
                                                 NSString *filePath = filePathsArray[i];
                                                 NSData *fileData = [NSData dataWithContentsOfFile:filePath];
                                                 NSString *nameString = [NSString stringWithFormat:@"%@[%i]", name, (int)i];
                                                 
                                                 NSString *mimeType = [LGHelper mimeTypeForPath:filePath];
                                                 
                                                 if (mimeType.length)
                                                     [formData appendPartWithFileData:fileData
                                                                                 name:nameString
                                                                             fileName:[NSString stringWithFormat:@"%@", filePath.pathComponents.lastObject]
                                                                             mimeType:[LGHelper mimeTypeForPath:filePath]];
                                                 else
                                                     [formData appendPartWithFormData:fileData
                                                                                 name:nameString];
                                             }
                                         }
                                              success:^(AFHTTPRequestOperation *operation, NSData *responseData)
                                         {
                                             [self parseResponseData:responseData responseType:responseType operation:operation completionHandler:completionHandler];
                                             
                                             [manager.operationQueue cancelAllOperations];
                                             [_managersArray removeObject:manager];
                                         }
                                              failure:^(AFHTTPRequestOperation *operation, NSError *error)
                                         {
                                             if (!self.isConnectionAvailable)
                                             {
                                                 if (_savedRequestsArray)
                                                 {
                                                     NSMutableDictionary *savedRequest = [NSMutableDictionary new];
                                                     [savedRequest setObject:[NSNumber numberWithInt:RequestTypeMultipartPathsArray] forKey:@"type"];
                                                     [savedRequest setObject:urlString forKey:@"urlString"];
                                                     if (parameters) [savedRequest setObject:parameters forKey:@"parameters"];
                                                     [savedRequest setObject:name forKey:@"name"];
                                                     [savedRequest setObject:filePathsArray forKey:@"filePathsArray"];
                                                     [savedRequest setObject:[NSNumber numberWithInt:responseType] forKey:@"responseType"];
                                                     if (progressHandler) [savedRequest setObject:progressHandler forKey:@"progressHandler"];
                                                     if (completionHandler) [savedRequest setObject:completionHandler forKey:@"completionHandler"];
                                                     
                                                     BOOL isExist = NO;
                                                     
                                                     for (NSDictionary *dictionary in _savedRequestsArray)
                                                         if ([dictionary isEqualToDictionary:savedRequest])
                                                             isExist = YES;
                                                     
                                                     if (!isExist) [_savedRequestsArray addObject:savedRequest];
                                                 }
                                                 else if (completionHandler) completionHandler(error, nil);
                                                 
                                                 if (_connectionLostHandler) _connectionLostHandler();
                                             }
                                             else
                                             {
                                                 if (completionHandler) completionHandler(error, nil);
                                                 
                                                 [manager.operationQueue cancelAllOperations];
                                                 [_managersArray removeObject:manager];
                                             }
                                         }];
    
    [operation setShouldExecuteAsBackgroundTaskWithExpirationHandler:^(void)
     {
         /*
          [[[UIAlertView alloc] initWithTitle:@"Ошибка"
          message:@"Допустимое время фоновой загрузки файла было превышено."
          delegate:nil
          cancelButtonTitle:@"ОК"
          otherButtonTitles:nil] show];
          */
     }];
    
    if (progressHandler)
    {
        [operation setUploadProgressBlock:^(NSUInteger bytesRead, long long totalBytesRead, long long totalBytesExpectedToRead)
         {
             float progress = (float)totalBytesRead/(float)totalBytesExpectedToRead;
             
             NSUInteger downloadPercentage = (float)progress * (float)100;
             if (downloadPercentage > 100) downloadPercentage = 100;
             
             progressHandler(totalBytesExpectedToRead, totalBytesRead, progress, downloadPercentage);
             
             //NSLog(@"%lld | %lld | %lld", totalBytesExpectedToRead, totalBytesRead, (long long)bytesRead);
             //NSLog(@"progress: %.2f %%", downloadPercentage*100);
         }];
    }
}

- (void)sendMultipartRequestToUrl:(NSURL *)url
                       parameters:(id)parameters
        constructingBodyWithBlock:(void(^)(id<AFMultipartFormData> formData))constructingBodyWithBlock
                     responseType:(LGConnectionResponseType)responseType
                  progressHandler:(void(^)(long long totalBytesExpectedToRead, long long totalBytesRead, float progress, NSUInteger downloadPercentage))progressHandler
                completionHandler:(void(^)(NSError *error, id responseObject))completionHandler
{
    NSString *urlString = ([url isKindOfClass:[NSString class]] ? (NSString *)url : [NSString stringWithFormat:@"%@", url]);
    
    AFHTTPRequestOperationManager *manager = [AFHTTPRequestOperationManager manager];
    manager.responseSerializer = [AFHTTPResponseSerializer serializer];
    manager.requestSerializer.HTTPShouldHandleCookies = _cookiesShouldHandle;
    manager.requestSerializer.timeoutInterval = _timeoutInterval;
    
    [_managersArray addObject:manager];
    
    AFHTTPRequestOperation *operation = [manager POST:urlString
                                           parameters:parameters
                            constructingBodyWithBlock:^(id<AFMultipartFormData> formData)
                                         {
                                             if (constructingBodyWithBlock) constructingBodyWithBlock(formData);
                                         }
                                              success:^(AFHTTPRequestOperation *operation, NSData *responseData)
                                         {
                                             [self parseResponseData:responseData responseType:responseType operation:operation completionHandler:completionHandler];
                                             
                                             [manager.operationQueue cancelAllOperations];
                                             [_managersArray removeObject:manager];
                                         }
                                              failure:^(AFHTTPRequestOperation *operation, NSError *error)
                                         {
                                             if (!self.isConnectionAvailable)
                                             {
                                                 if (_savedRequestsArray)
                                                 {
                                                     NSMutableDictionary *savedRequest = [NSMutableDictionary new];
                                                     [savedRequest setObject:[NSNumber numberWithInt:RequestTypeMultipartConstructor] forKey:@"type"];
                                                     [savedRequest setObject:urlString forKey:@"urlString"];
                                                     if (parameters) [savedRequest setObject:parameters forKey:@"parameters"];
                                                     if (constructingBodyWithBlock) [savedRequest setObject:constructingBodyWithBlock forKey:@"constructingBodyWithBlock"];
                                                     [savedRequest setObject:[NSNumber numberWithInt:responseType] forKey:@"responseType"];
                                                     if (progressHandler) [savedRequest setObject:progressHandler forKey:@"progressHandler"];
                                                     if (completionHandler) [savedRequest setObject:completionHandler forKey:@"completionHandler"];
                                                     
                                                     BOOL isExist = NO;
                                                     
                                                     for (NSDictionary *dictionary in _savedRequestsArray)
                                                         if ([dictionary isEqualToDictionary:savedRequest])
                                                             isExist = YES;
                                                     
                                                     if (!isExist) [_savedRequestsArray addObject:savedRequest];
                                                 }
                                                 else if (completionHandler) completionHandler(error, nil);
                                                 
                                                 if (_connectionLostHandler) _connectionLostHandler();
                                             }
                                             else
                                             {
                                                 if (completionHandler) completionHandler(error, nil);
                                                 
                                                 [manager.operationQueue cancelAllOperations];
                                                 [_managersArray removeObject:manager];
                                             }
                                         }];
    
    [operation setShouldExecuteAsBackgroundTaskWithExpirationHandler:^(void)
     {
         /*
          [[[UIAlertView alloc] initWithTitle:@"Ошибка"
          message:@"Допустимое время фоновой загрузки файла было превышено."
          delegate:nil
          cancelButtonTitle:@"ОК"
          otherButtonTitles:nil] show];
          */
     }];
    
    if (progressHandler)
    {
        [operation setUploadProgressBlock:^(NSUInteger bytesRead, long long totalBytesRead, long long totalBytesExpectedToRead)
         {
             float progress = (float)totalBytesRead/(float)totalBytesExpectedToRead;
             
             NSUInteger downloadPercentage = (float)progress * (float)100;
             if (downloadPercentage > 100) downloadPercentage = 100;
             
             progressHandler(totalBytesExpectedToRead, totalBytesRead, progress, downloadPercentage);
             
             //NSLog(@"%lld | %lld | %lld", totalBytesExpectedToRead, totalBytesRead, (long long)bytesRead);
             //NSLog(@"progress: %.2f %%", downloadPercentage*100);
         }];
    }
}

#pragma mark - Download

- (void)downloadFileFromURL:(NSURL *)url
                 toLocalUrl:(NSURL *)localUrl
            progressHandler:(void(^)(long long totalBytesExpectedToRead, long long totalBytesRead, float progress, NSUInteger downloadPercentage))progressHandler
          completionHandler:(void(^)(NSError *error))completionHandler
{
    [self downloadFileFromURL:url
                   toLocalUrl:localUrl
           useModifiedControl:NO
              progressHandler:progressHandler
            completionHandler:^(NSError *error, BOOL isModified)
     {
         if (completionHandler) completionHandler(error);
     }];
}

- (void)downloadFileWithModifiedControlFromURL:(NSURL *)url
                                    toLocalUrl:(NSURL *)localUrl
                               progressHandler:(void(^)(long long totalBytesExpectedToRead, long long totalBytesRead, float progress, NSUInteger downloadPercentage))progressHandler
                             completionHandler:(void(^)(NSError *error, BOOL isModified))completionHandler
{
    [self downloadFileFromURL:url
                   toLocalUrl:localUrl
           useModifiedControl:YES
              progressHandler:progressHandler
            completionHandler:completionHandler];
}

- (void)downloadFileFromURL:(NSURL *)url
                 toLocalUrl:(NSURL *)localUrl
         useModifiedControl:(BOOL)useModifiedControl
            progressHandler:(void(^)(long long totalBytesExpectedToRead, long long totalBytesRead, float progress, NSUInteger downloadPercentage))progressHandler
          completionHandler:(void(^)(NSError *error, BOOL isModified))completionHandler
{
    NSString *urlString = ([url isKindOfClass:[NSString class]] ? (NSString *)url : [NSString stringWithFormat:@"%@", url]);
    
    AFHTTPRequestOperationManager *manager = [AFHTTPRequestOperationManager manager];
    manager.responseSerializer = [AFHTTPResponseSerializer serializer];
    manager.requestSerializer.HTTPShouldHandleCookies = _cookiesShouldHandle;
    manager.requestSerializer.timeoutInterval = _timeoutInterval;
    
    if (useModifiedControl)
    {
        manager.requestSerializer.cachePolicy = NSURLRequestReloadIgnoringLocalAndRemoteCacheData;
        
        NSString *key = [LGHelper sha1HashFromString:[NSString stringWithFormat:@"%@", url]];
        NSString *lastModified = [[NSUserDefaults standardUserDefaults] stringForKey:key];
        if (lastModified.length)
            [manager.requestSerializer setValue:lastModified forHTTPHeaderField:@"If-Modified-Since"];
    }
    
    [_managersArray addObject:manager];
    
    __block BOOL responseFromCache = YES;
    
    AFHTTPRequestOperation *operation = [manager GET:urlString
                                          parameters:nil
                                             success:^(AFHTTPRequestOperation *operation, NSData *responseData)
                                         {
                                             //NSLog(@"statusCode: %i", (int)[operation.response statusCode]);
                                             //NSLog(@"allHeaderFields: %@", [operation.response allHeaderFields]);
                                             
                                             // -----
                                             
                                             if (responseData.length)
                                                 [responseData writeToURL:localUrl atomically:YES];
                                             
                                             if (completionHandler) completionHandler(nil, YES);
                                             
                                             [manager.operationQueue cancelAllOperations];
                                             [_managersArray removeObject:manager];
                                             
                                             // -----
                                             
                                             if (useModifiedControl)
                                             {
                                                 NSDictionary *headers = [operation.response allHeaderFields];
                                                 NSString *key = [LGHelper sha1HashFromString:[NSString stringWithFormat:@"%@", url]];
                                                 NSString *lastModified = headers[@"Last-Modified"];
                                                 if (lastModified.length)
                                                     [[NSUserDefaults standardUserDefaults] setObject:lastModified forKey:key];
                                             }
                                         }
                                             failure:^(AFHTTPRequestOperation *operation, NSError *error)
                                         {
                                             if (error.code == kErrorCodeNotModified) error = nil;
                                             
                                             // -----
                                             
                                             if (!self.isConnectionAvailable)
                                             {
                                                 if (_savedRequestsArray)
                                                 {
                                                     NSMutableDictionary *savedRequest = [NSMutableDictionary new];
                                                     [savedRequest setObject:[NSNumber numberWithInt:RequestTypeDownload] forKey:@"type"];
                                                     [savedRequest setObject:urlString forKey:@"urlString"];
                                                     [savedRequest setObject:localUrl forKey:@"localUrl"];
                                                     [savedRequest setObject:[NSNumber numberWithBool:useModifiedControl] forKey:@"useModifiedControl"];
                                                     if (progressHandler) [savedRequest setObject:progressHandler forKey:@"progressHandler"];
                                                     if (completionHandler) [savedRequest setObject:completionHandler forKey:@"completionHandler"];
                                                     
                                                     BOOL isExist = NO;
                                                     
                                                     for (NSDictionary *dictionary in _savedRequestsArray)
                                                         if ([dictionary isEqualToDictionary:savedRequest])
                                                             isExist = YES;
                                                     
                                                     if (!isExist) [_savedRequestsArray addObject:savedRequest];
                                                 }
                                                 else if (completionHandler) completionHandler(error, NO);
                                                 
                                                 if (_connectionLostHandler) _connectionLostHandler();
                                             }
                                             else
                                             {
                                                 if (completionHandler) completionHandler(error, NO);
                                                 
                                                 [manager.operationQueue cancelAllOperations];
                                                 [_managersArray removeObject:manager];
                                             }
                                         }];
    
    [operation setCacheResponseBlock:^NSCachedURLResponse *(NSURLConnection *connection, NSCachedURLResponse *cachedResponse)
     {
         responseFromCache = NO;
         
         return cachedResponse;
     }];
    
    [operation setShouldExecuteAsBackgroundTaskWithExpirationHandler:^(void)
     {
         /*
          [[[UIAlertView alloc] initWithTitle:@"Ошибка"
          message:@"Допустимое время фоновой загрузки файла было превышено."
          delegate:nil
          cancelButtonTitle:@"ОК"
          otherButtonTitles:nil] show];
          */
     }];
    
    if (progressHandler)
    {
        [operation setDownloadProgressBlock:^(NSUInteger bytesRead, long long totalBytesRead, long long totalBytesExpectedToRead)
         {
             float progress = (float)totalBytesRead/(float)totalBytesExpectedToRead;
             
             NSUInteger downloadPercentage = (float)progress * (float)100;
             if (downloadPercentage > 100) downloadPercentage = 100;
             
             progressHandler(totalBytesExpectedToRead, totalBytesRead, progress, downloadPercentage);
             
             //NSLog(@"%lld | %lld | %lld", totalBytesExpectedToRead, totalBytesRead, (long long)bytesRead);
             //NSLog(@"progress: %.2f %%", downloadPercentage*100);
         }];
    }
}

#pragma mark -

- (void)parseResponseData:(NSData *)responseData
               responseType:(LGConnectionResponseType)responseType
                  operation:(AFHTTPRequestOperation *)operation
          completionHandler:(void(^)(NSError *error, id responseObject))completionHandler
{
    if (!responseData || !responseData.length)
    {
        if (completionHandler) completionHandler(nil, nil);
    }
    else
    {
        id parsedResponseObject;
        NSError *error;
        
        if (responseType == LGConnectionResponseTypeDATA)
            parsedResponseObject = responseData;
        else if (responseType == LGConnectionResponseTypeXML)
            parsedResponseObject = [XMLReader dictionaryForXMLData:responseData error:&error];
        else if (responseType == LGConnectionResponseTypeJSON)
            parsedResponseObject = [NSJSONSerialization JSONObjectWithData:responseData options:NSJSONReadingMutableContainers error:&error];
        
        if (completionHandler)
        {
            if (error)
                completionHandler(error, nil);
            else if (!parsedResponseObject)
                completionHandler([NSError errorWithDomain:@"LGConnection parse error, no data" code:0 userInfo:nil], nil);
            else
                completionHandler(nil, parsedResponseObject);
        }
    }
}

- (void)cancelAllOperations
{
    if (_managersArray.count)
    {
        for (int i=0; i<_managersArray.count; i++)
        {
            AFHTTPRequestOperationManager *_manager = _managersArray[i];
            
            [_manager.operationQueue cancelAllOperations];
        }
        
        [_managersArray removeAllObjects];
    }
}

#pragma mark - NSURLConnection
#pragma mark Multipart (for example)

- (void)sendMultipartNSRequestToUrl:(NSURL *)url
                         parameters:(NSDictionary *)parameters
                               name:(NSString *)name
                              paths:(NSArray *)paths
                       responseType:(LGConnectionResponseType)responseType
                  completionHandler:(void(^)(NSError *error, id responseObject))completionHandler
{
    // configure the request
    
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];
    [request setHTTPMethod:@"POST"];
    
    // Generate boundary
    
    NSString *boundary = [NSString stringWithFormat:@"Boundary-%@", [[NSUUID UUID] UUIDString]];
    
    // set content type
    
    NSString *contentType = [NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary];
    [request setValue:contentType forHTTPHeaderField: @"Content-Type"];
    
    // create body
    
    NSMutableData *httpBody = [NSMutableData data];
    
    // add params (all params are strings)
    
    [parameters enumerateKeysAndObjectsUsingBlock:^(NSString *parameterKey, NSString *parameterValue, BOOL *stop)
     {
         [httpBody appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
         [httpBody appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"\r\n\r\n", parameterKey] dataUsingEncoding:NSUTF8StringEncoding]];
         [httpBody appendData:[[NSString stringWithFormat:@"%@\r\n", parameterValue] dataUsingEncoding:NSUTF8StringEncoding]];
     }];
    
    // add image data
    
    for (NSString *path in paths)
    {
        NSString *filename  = [path lastPathComponent];
        NSData   *data      = [NSData dataWithContentsOfFile:path];
        NSString *mimetype  = [LGHelper mimeTypeForPath:path];
        
        [httpBody appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
        [httpBody appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@[0]\"; filename=\"%@\"\r\n", name, filename] dataUsingEncoding:NSUTF8StringEncoding]];
        [httpBody appendData:[[NSString stringWithFormat:@"Content-Type: %@\r\n\r\n", mimetype] dataUsingEncoding:NSUTF8StringEncoding]];
        [httpBody appendData:data];
        [httpBody appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    }
    
    // -----
    
    [httpBody appendData:[[NSString stringWithFormat:@"--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    
    // -----
    
    request.HTTPBody = httpBody;
    
    [NSURLConnection sendAsynchronousRequest:request
                                       queue:[NSOperationQueue new]
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError)
     {
         //
     }];
}

@end

//
//  ViewController.m
//  VideoCaptureDemo
//
//  Created by huangyibiao on 16/6/9.
//  Copyright © 2016年 huangyibiao. All rights reserved.
//

#import "ViewController.h"
#import <AVFoundation/AVAsset.h>
#import <AVFoundation/AVFoundation.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import <AVFoundation/AVAssetImageGenerator.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <CoreMedia/CoreMedia.h>

@import CoreMotion;

@interface ViewController () <UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIGestureRecognizerDelegate, UIScrollViewDelegate>
#define UIColorForHexRGB(rgbValue) [UIColor colorWithRed:((float)((rgbValue & 0xFF0000) >> 16))/255.0 green:((float)((rgbValue & 0xFF00) >> 8))/255.0 blue:((float)(rgbValue & 0xFF))/255.0 alpha:1.0]


@property (weak, nonatomic) IBOutlet UIImageView *centerFrameImageView;//展示的图片
@property (weak, nonatomic) IBOutlet UILabel *videoDurationLabel;
@property (nonatomic, assign) BOOL shouldAsync;//记录是拍摄还是选择视频
@property (weak, nonatomic) IBOutlet UISlider *mSliderView;
@property (weak, nonatomic) IBOutlet UILabel *videoSizeLabel;

@property (nonatomic, strong) CMMotionManager *motionManager;//重力感应管理类

@property (weak, nonatomic) IBOutlet UIButton *motionBtn;//重力感应控制按钮

@end

#define isLandscape UIDeviceOrientationIsLandscape([[UIDevice currentDevice] orientation])

@implementation ViewController{
    NSString *videoSavePath;//沙盒文件存储路径
    
    float currentTime;//记录当前播放时间
    
    float midTime;
}

- (void) viewWillAppear:(BOOL)animated{
    [super viewWillAppear:animated];
    //监听程序前后台切换，防止重力感应在后台扔运行
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didEnterForeground:) name:UIApplicationWillEnterForegroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    //注册前后台切换通知
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillEnterForegroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidEnterBackgroundNotification object:nil];
}

- (void)didEnterForeground:(NSNotification *)noti {
    [self addCoreMotion];
}

- (void)didEnterBackground:(NSNotification *)noti {
    [self stopCoreMotion];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [_motionBtn setTitle:@"已开启重力感应" forState:UIControlStateNormal];
    [_motionBtn setTitle:@"未开启重力感应" forState:UIControlStateSelected];
    
    NSLog(@"%@",NSHomeDirectory());
    _mScrollView.contentSize = _mScrollView.bounds.size;
    _mScrollView.zoomScale = 1;
    _mScrollView.maximumZoomScale = 3;
    _mScrollView.minimumZoomScale = 1;
    _mScrollView.scrollEnabled = NO;
    
    
    self.centerFrameImageView.userInteractionEnabled = YES;//滑动获取视频帧需启动imageView的交互
    
    _mSliderView.minimumValue = 0.000000f;
    _mSliderView.maximumValue = 1.000000f;
    _mSliderView.value = 0.0f;
    [_mSliderView addTarget:self action:@selector(sliderAction:) forControlEvents:UIControlEventValueChanged];
    
    [self addSwipeGesture];//添加滑动获取视频帧的手势
    [self addCoreMotion];//添加重力感应
}

- (void) addSwipeGesture{
    //滑动手势
    UIPanGestureRecognizer *recognizer;
    recognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipeFrom:)];
    recognizer.delegate = self;
    [self.centerFrameImageView addGestureRecognizer:recognizer];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer{
    currentTime = _mSliderView.value;//手势滑动时先记录当前帧数
    return YES;
}

//手势滑动
- (void)handleSwipeFrom:(UIPanGestureRecognizer *)recognizer{
    //首先获取当前屏幕上手势滑动的左右及上下距离
    CGPoint translation = [recognizer translationInView:self.view];
    NSLog(@"%lf",translation.x);
    //获取当前屏幕宽度
    float allWidth = [UIScreen mainScreen].bounds.size.width;
    //计算出滑动距离占屏幕比例
    float multiple = translation.x/allWidth;
    //用滑动比例计算出滑动后的slider的value
    _mSliderView.value = multiple + currentTime;
    //获取滑动后的视频帧
    [self sliderAction:_mSliderView];
}

//拍摄视频
- (IBAction)onRecordVideo:(id)sender {
    // 7.0
    AVAuthorizationStatus authStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    //判断当前设备涉嫌头是否可用
    if (authStatus == AVAuthorizationStatusRestricted
        || authStatus == AVAuthorizationStatusDenied) {
        NSLog(@"摄像头已被禁用，您可在设置应用程序中进行开启");
        return;
    }
    
    if(![self cameraSupportsMedia:(NSString *)kUTTypeMovie sourceType:UIImagePickerControllerSourceTypeCamera]){
        NSLog(@"不支持录像");
        return;
    }
    //判断当前设备涉嫌头是否支持录像功能
    if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
        UIImagePickerController *picker = [[UIImagePickerController alloc] init];
        picker.delegate = self;
        picker.allowsEditing = YES;
        picker.sourceType = UIImagePickerControllerSourceTypeCamera;
        picker.videoQuality = UIImagePickerControllerQualityTypeMedium; //录像质量
        picker.videoMaximumDuration = 20.0f; // 限制视频录制最多不超过20秒
        picker.mediaTypes = @[(NSString *)kUTTypeMovie];
        [self presentViewController:picker animated:YES completion:NULL];
        self.shouldAsync = YES;
    } else {
        NSLog(@"手机不支持摄像");
    }
}

//选择视频
- (IBAction)onSelectLocalVideo:(id)sender {
  // 7.0
  AVAuthorizationStatus authStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
  if (authStatus == AVAuthorizationStatusRestricted
      || authStatus == AVAuthorizationStatusDenied) {
    NSLog(@"摄像头已被禁用，您可在设置应用程序中进行开启");
    return;
  }
  
  if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeSavedPhotosAlbum]) {
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.delegate = self;
    picker.allowsEditing = YES;
    picker.sourceType = UIImagePickerControllerSourceTypeSavedPhotosAlbum;
    picker.mediaTypes = @[(NSString *)kUTTypeMovie];
    [self presentViewController:picker animated:YES completion:NULL];
    self.shouldAsync = NO;
  } else {
    NSLog(@"手机不支持摄像");
  }
}


#pragma  mark - UIImagePickerControllerDelegate
// 录制视频完成后要执行的代理方法
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
    [picker dismissViewControllerAnimated:YES completion:^{
        // for fixing iOS 8.0 problem that frame changed when open camera to record video.
        self.tabBarController.view.frame  = [[UIScreen mainScreen] bounds];
        [self.tabBarController.view layoutIfNeeded];
    }];
    
    NSURL *videoURL = [info objectForKey:UIImagePickerControllerMediaURL];
    
    ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        // 判断相册是否兼容视频，兼容才能保存到相册
        if ([library videoAtPathIsCompatibleWithSavedPhotosAlbum:videoURL]) {
            //
            dispatch_async(dispatch_get_main_queue(), ^{
                AVURLAsset *videoAsset = [[AVURLAsset alloc] initWithURL:videoURL options:nil];
                Float64 duration = CMTimeGetSeconds(videoAsset.duration);
                self.videoDurationLabel.text = [NSString stringWithFormat:@"视频时长：%.0f秒",
                                                duration];
                if (self.shouldAsync) {
                    [library writeVideoAtPathToSavedPhotosAlbum:videoURL completionBlock:^(NSURL *assetURL, NSError *error) {
                        
                    }];
                }
                // 同步获取中间帧图片
                UIImage *image = [self frameImageFromVideoURL:videoURL timeProportion:0];
                self.centerFrameImageView.image = image;
                
                // Begin to compress and export the video to the output path
                NSInteger nowDate = [[NSDate date] timeIntervalSince1970];
                NSString *name = [NSString stringWithFormat:@"%ld.mp4", (long)nowDate];
                
                [self compressVideoWithVideoURL:videoURL savedName:name completion:^(NSString *savedPath) {
                    if (savedPath) {
                        NSLog(@"保存成功successfully. path: %@", savedPath);
                        videoSavePath = savedPath;
                        NSInteger fileSize = [[NSFileManager defaultManager] attributesOfItemAtPath:savedPath error:nil].fileSize;
                        self.videoSizeLabel.text = [NSString stringWithFormat:@"视频大小：%.2fM",
                                                    (float)fileSize/1024/1024];
                    } else {
                        NSLog(@"Compressed failed");
                    }
                }];
            });
        }
    });
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker{
  [picker dismissViewControllerAnimated:YES completion:^{
    // for fixing iOS 8.0 problem that frame changed when open camera to record video.
    self.tabBarController.view.frame  = [[UIScreen mainScreen]bounds];
    [self.tabBarController.view layoutIfNeeded];
  }];
}


- (void) sliderAction:(UISlider *)slider{
    NSLog(@"%f",slider.value);
    if(!videoSavePath){
        return;
    }
    float value;
    if(0 >= slider.value){
        value = 0;
    }else if (slider.value >= 1){
        value = 1;
    }else{
        value = slider.value;
    }
    
   [self getImageAndUpdate:value];
}

//根据时间获取帧数
- (void) getImageAndUpdate:(float)cuurentValue{
    if(videoSavePath){
        UIImage *image = [self frameImageFromVideoURL:[NSURL fileURLWithPath:videoSavePath] timeProportion:cuurentValue];
        self.centerFrameImageView.image = image;
    }
}

//添加重力感应
- (void) addCoreMotion{
    if(!_motionManager){
        _motionManager = [[CMMotionManager alloc] init];
        //重力感应回调间隔
        _motionManager.gyroUpdateInterval = 0.08f;
    }
    if (![_motionManager isGyroActive] && [_motionManager isGyroAvailable]) {
        [_motionManager startGyroUpdatesToQueue:[NSOperationQueue currentQueue]
                                    withHandler:^(CMGyroData *gyroData, NSError *error) {
                                        CGFloat rotationRate = isLandscape ? gyroData.rotationRate.x : gyroData.rotationRate.y;
                                        if(fabs(rotationRate) > 0.1f){
                                            _mSliderView.value += rotationRate/10;
                                            if(videoSavePath){
                                                [self getImageAndUpdate:_mSliderView.value];
                                            }
                                        }
                                    }];
    }
}

- (void) stopCoreMotion{
    [_motionManager stopGyroUpdates];
}
- (IBAction)motionClick:(UIButton *)sender {
    sender.selected = !sender.selected;
    if(sender.selected){
        sender.backgroundColor = [UIColor blackColor];
        [self stopCoreMotion];
    }else{
        sender.backgroundColor = UIColorForHexRGB(0xFF3B4F);
        [self addCoreMotion];
    }
    
}

#pragma mark - scrollview
- (UIView *) viewForZoomingInScrollView:(UIScrollView *)scrollView{
    return self.centerFrameImageView;
}


#pragma mark - toolMothods
//判断当前设备是否支持录像
- (BOOL) cameraSupportsMedia:(NSString *)paramMediaType sourceType:(UIImagePickerControllerSourceType)paramSourceType{
    __block BOOL result = NO;
    if ([paramMediaType length] == 0){
        NSLog(@"Media type is empty.");
        return NO;
    }
    NSArray *availableMediaTypes =[UIImagePickerController availableMediaTypesForSourceType:paramSourceType];
    [availableMediaTypes enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL*stop) {
        NSString *mediaType = (NSString *)obj;
        if ([mediaType isEqualToString:paramMediaType]){
            result = YES;
            *stop= YES;
        }
        
    }];
    return result;
}

// Get the video's center frame as video poster image
- (UIImage *)frameImageFromVideoURL:(NSURL *)videoURL timeProportion:(float)timeProportion {
    // result
    UIImage *image = nil;
    
    // AVAssetImageGenerator
    AVAsset *asset = [AVAsset assetWithURL:videoURL];
    AVAssetImageGenerator *imageGenerator = [[AVAssetImageGenerator alloc] initWithAsset:asset];
    imageGenerator.appliesPreferredTrackTransform = YES;
    
    //消除缓存，如不设置，系统将默认以秒为单位输出
    imageGenerator.requestedTimeToleranceAfter = kCMTimeZero;
    imageGenerator.requestedTimeToleranceBefore = kCMTimeZero;
    
    // calculate the midpoint time of video
    Float64 duration = CMTimeGetSeconds([asset duration]);
    // 取某个帧的时间，参数一表示哪个时间（秒），参数二表示每秒多少帧
    // 通常来说，600是一个常用的公共参数，苹果有说明:
    // 24 frames per second (fps) for film, 30 fps for NTSC (used for TV in North America and
    // Japan), and 25 fps for PAL (used for TV in Europe).
    // Using a timescale of 600, you can exactly represent any number of frames in these systems
    CMTime midpoint = CMTimeMakeWithSeconds(duration * timeProportion, 600);
    
    // get the image from
    NSError *error = nil;
    CMTime actualTime;
    // Returns a CFRetained CGImageRef for an asset at or near the specified time.
    // So we should mannully release it
    CGImageRef centerFrameImage = [imageGenerator copyCGImageAtTime:midpoint
                                                         actualTime:&actualTime
                                                              error:&error];
    if (centerFrameImage != NULL) {
        image = [[UIImage alloc] initWithCGImage:centerFrameImage];
        // Release the CFRetained image
        CGImageRelease(centerFrameImage);
    }
    return image;
}

// 异步获取帧图片，可以一次获取多帧图片
- (void)centerFrameImageWithVideoURL:(NSURL *)videoURL completion:(void (^)(UIImage *image))completion {
    // AVAssetImageGenerator
    AVAsset *asset = [AVAsset assetWithURL:videoURL];
    AVAssetImageGenerator *imageGenerator = [[AVAssetImageGenerator alloc] initWithAsset:asset];
    imageGenerator.appliesPreferredTrackTransform = YES;
    
    // calculate the midpoint time of video
    Float64 duration = CMTimeGetSeconds([asset duration]);
    // 取某个帧的时间，参数一表示哪个时间（秒），参数二表示每秒多少帧
    // 通常来说，600是一个常用的公共参数，苹果有说明:
    // 24 frames per second (fps) for film, 30 fps for NTSC (used for TV in North America and
    // Japan), and 25 fps for PAL (used for TV in Europe).
    // Using a timescale of 600, you can exactly represent any number of frames in these systems
    CMTime midpoint = CMTimeMakeWithSeconds(duration / 2.0, 600);
    
    // 异步获取多帧图片
    NSValue *midTime = [NSValue valueWithCMTime:midpoint];
    [imageGenerator generateCGImagesAsynchronouslyForTimes:@[midTime] completionHandler:^(CMTime requestedTime, CGImageRef  _Nullable image, CMTime actualTime, AVAssetImageGeneratorResult result, NSError * _Nullable error) {
        if (result == AVAssetImageGeneratorSucceeded && image != NULL) {
            UIImage *centerFrameImage = [[UIImage alloc] initWithCGImage:image];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) {
                    completion(centerFrameImage);
                }
            });
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) {
                    completion(nil);
                }
            });
        }
    }];
}

//视频转MP4
- (void)compressVideoWithVideoURL:(NSURL *)videoURL
                        savedName:(NSString *)savedName
                       completion:(void (^)(NSString *savedPath))completion {
    // Accessing video by URL
    AVURLAsset *videoAsset = [[AVURLAsset alloc] initWithURL:videoURL options:nil];
    
    // Find compatible presets by video asset.
    NSArray *presets = [AVAssetExportSession exportPresetsCompatibleWithAsset:videoAsset];
    
    // Begin to compress video
    // Now we just compress to low resolution if it supports
    // If you need to upload to the server, but server does't support to upload by streaming,
    // You can compress the resolution to lower. Or you can support more higher resolution.
    if ([presets containsObject:AVAssetExportPresetMediumQuality]) {
        AVAssetExportSession *session = [[AVAssetExportSession alloc] initWithAsset:videoAsset  presetName:AVAssetExportPresetMediumQuality];
        
        NSString *doc = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
        NSString *folder = [doc stringByAppendingPathComponent:@"HYBVideos"];
        BOOL isDir = NO;
        BOOL isExist = [[NSFileManager defaultManager] fileExistsAtPath:folder isDirectory:&isDir];
        if (!isExist || (isExist && !isDir)) {
            NSError *error = nil;
            [[NSFileManager defaultManager] createDirectoryAtPath:folder
                                      withIntermediateDirectories:YES
                                                       attributes:nil
                                                            error:&error];
            if (error == nil) {
                NSLog(@"目录创建成功");
            } else {
                NSLog(@"目录创建失败");
            }
        }
        
        NSString *outPutPath = [folder stringByAppendingPathComponent:savedName];
        session.outputURL = [NSURL fileURLWithPath:outPutPath];
        
        // Optimize for network use.
        session.shouldOptimizeForNetworkUse = true;
        
        NSArray *supportedTypeArray = session.supportedFileTypes;
        if ([supportedTypeArray containsObject:AVFileTypeMPEG4]) {
            session.outputFileType = AVFileTypeMPEG4;
        } else if (supportedTypeArray.count == 0) {
            NSLog(@"No supported file types");
            return;
        } else {
            session.outputFileType = [supportedTypeArray objectAtIndex:0];
        }
        
        // Begin to export video to the output path asynchronously.
        [session exportAsynchronouslyWithCompletionHandler:^{
            if ([session status] == AVAssetExportSessionStatusCompleted) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completion) {
                        completion([session.outputURL path]);
                    }
                });
            } else {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completion) {
                        completion(nil);
                    }
                });
            }
        }];
    }
}



@end

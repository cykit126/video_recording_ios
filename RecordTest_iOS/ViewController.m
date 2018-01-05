//
//  ViewController.m
//  RecordTest_iOS
//
//  Created by luoweibin on 05/01/2018.
//  Copyright © 2018 sexiangji. All rights reserved.
//

#import "ViewController.h"
#import <Photos/Photos.h>
#import <AVFoundation/AVFoundation.h>

@interface ViewController () <AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate> {
    dispatch_queue_t mCameraQueue;
    AVCaptureSession* mCameraSession;
    AVAssetWriter* mWriter;
    AVAssetWriterInput* mVideoInput;
    AVAssetWriterInputPixelBufferAdaptor* _videoInputAdaptor;
    AVAssetWriterInput* mAudioInput;
    AVCaptureVideoDataOutput* _videoOutput;
    AVCaptureAudioDataOutput* _audioOutput;
    BOOL _started;
    
    NSURL* _url;
}
@property (weak, nonatomic) IBOutlet UIView *viewView;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self requestPhotoLibraryPermission];
    
    [self initCamera];
    
    AVCaptureVideoPreviewLayer *previewLayer = [AVCaptureVideoPreviewLayer
                                                layerWithSession:mCameraSession];
    previewLayer.frame = self.viewView.frame;
    [self.viewView.layer addSublayer:previewLayer];
    
    [self start];
}

- (void)requestPhotoLibraryPermission {
    PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatus];
    if (status != PHAuthorizationStatusAuthorized) {
        [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
        }];
    }
}

- (void)start {
    dispatch_async(mCameraQueue, ^{
        if (![mCameraSession isRunning]) {
            [mCameraSession startRunning];
        }
    });
}

- (void)stop {
    dispatch_async(mCameraQueue, ^{
        if ([mCameraSession isRunning]) {
            [mCameraSession stopRunning];
        }
    });
}

- (void)initCamera {
    mCameraQueue = dispatch_queue_create("ai.camera_queue", DISPATCH_QUEUE_CONCURRENT);
    
    AVCaptureSession* session = [AVCaptureSession new];
    [session beginConfiguration];
    
    {
        AVCaptureDevice* videoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
        
        NSError *error = nil;
        AVCaptureInput* videoInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice
                                                                           error:&error];
        if ([session canAddInput:videoInput])
        {
            [session addInput:videoInput];
        }
    }
    
    {
        NSError *error = nil;
        AVCaptureDevice* audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
        AVCaptureInput* audioInput = [AVCaptureDeviceInput deviceInputWithDevice:audioDevice
                                                                           error:&error];
        if ([session canAddInput:audioInput])
        {
            [session addInput:audioInput];
        }
    }
    
    {
        AVCaptureVideoDataOutput* output = [AVCaptureVideoDataOutput new];
        [output setAlwaysDiscardsLateVideoFrames:YES];
        [output setVideoSettings:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:kCVPixelFormatType_32BGRA]
                                                             forKey:(id)kCVPixelBufferPixelFormatTypeKey]];
        [output setSampleBufferDelegate:self
                                  queue:mCameraQueue];
        if ([session canAddOutput:output]) {
            [session addOutput:output];
        }
        
        AVCaptureSessionPreset preset = AVCaptureSessionPreset1280x720;
        if ([session canSetSessionPreset:preset]) {
            [session setSessionPreset:preset];
        }
        
        AVCaptureConnection *videoConnection = [output connectionWithMediaType:AVMediaTypeVideo];
        if ([videoConnection isVideoMirroringSupported])
        {
            [videoConnection setVideoMirrored:NO];
        }
        
        if ([videoConnection isVideoOrientationSupported])
        {
            [videoConnection setVideoOrientation:AVCaptureVideoOrientationPortrait];
        }
        _videoOutput = output;
    }
    
    {
        AVCaptureAudioDataOutput* output = [AVCaptureAudioDataOutput new];
        [output setSampleBufferDelegate:self
                                  queue:mCameraQueue];
        if ([session canAddOutput:output])
        {
            [session addOutput:output];
        }
        _audioOutput = output;
    }
    
    [session commitConfiguration];
    
    mCameraSession = session;
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection {
    
    CMTime dts = CMSampleBufferGetDecodeTimeStamp(sampleBuffer);
    NSLog(@"dts:%lld/%d", dts.value, dts.timescale);
    
    CMTime pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    NSLog(@"dts:%lld", pts.value / (pts.timescale / 1000));
    
    CMFormatDescriptionRef desc = CMSampleBufferGetFormatDescription(sampleBuffer);
    CMMediaType type = CMFormatDescriptionGetMediaType(desc);
    
    if (!_started)
    {
        [mWriter startSessionAtSourceTime:pts];
        _started = YES;
    }
    
    if (type == kCMMediaType_Video)
    {
        if (mVideoInput.readyForMoreMediaData) {
            CVPixelBufferRef buffer = CMSampleBufferGetImageBuffer(sampleBuffer);
            if (![_videoInputAdaptor appendPixelBuffer:buffer
                                  withPresentationTime:pts])
            {
                AVAssetWriterStatus status = mWriter.status;
                NSLog(@"status:%d", (int)status);
            }
        } else {
            //        NSLog(@"Drop frame");
        }
    }
    else if (type == kCMMediaType_Audio) {
        if (mAudioInput.readyForMoreMediaData) {
            if (![mAudioInput appendSampleBuffer:sampleBuffer])
            {
                AVAssetWriterStatus status = mWriter.status;
                NSLog(@"status:%d", (int)status);
            }
        } else {
            //        NSLog(@"Drop frame");
        }
    }
}

- (IBAction)startWriting:(id)sender {
    NSFileManager* manager = [NSFileManager defaultManager];
    NSURL* tmpDir = [manager URLsForDirectory:NSDocumentDirectory
                                    inDomains:NSUserDomainMask][0];
    
    NSURL* tmpFile = [tmpDir URLByAppendingPathComponent:@"capture"];
    if (![tmpFile checkResourceIsReachableAndReturnError:nil])
    {
        NSError* error = nil;
        [manager createDirectoryAtURL:tmpFile
          withIntermediateDirectories:YES
                           attributes:nil
                                error:&error];
    }
    
    
    NSString* uuid = [[NSUUID UUID] UUIDString];
    tmpFile = [tmpFile URLByAppendingPathComponent:uuid];
    tmpFile = [tmpFile URLByAppendingPathExtension:@"mp4"];
    
    _url = tmpFile;
    
    NSError* error = nil;
    
    [[NSFileManager defaultManager] removeItemAtURL:tmpFile
                                              error:&error];
    
    mWriter = [AVAssetWriter assetWriterWithURL:tmpFile
                                       fileType:AVFileTypeMPEG4
                                          error:&error];
    mWriter.shouldOptimizeForNetworkUse = YES;
    
    {
        NSDictionary *videoSettings = [_videoOutput recommendedVideoSettingsForAssetWriterWithOutputFileType:AVFileTypeMPEG4];
        mVideoInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo
                                                         outputSettings:videoSettings];
        mVideoInput.expectsMediaDataInRealTime = YES;
        
//        NSDictionary* attrs = [NSDictionary dictionaryWithObjectsAndKeys:
//                               [NSNumber numberWithInt:kCVPixelFormatType_32BGRA], kCVPixelBufferPixelFormatTypeKey,
//                               nil];
        _videoInputAdaptor = [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:mVideoInput sourcePixelBufferAttributes:nil];
        
        [mWriter addInput:mVideoInput];
    }
    
    {
        AudioChannelLayout acl;
        bzero(&acl, sizeof(acl));
        
        NSDictionary* audioSettings = [_audioOutput recommendedAudioSettingsForAssetWriterWithOutputFileType:AVFileTypeMPEG4];
        mAudioInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio
                                                         outputSettings:audioSettings];
        mAudioInput.expectsMediaDataInRealTime = YES;
        [mWriter addInput:mAudioInput];
    }
    
    [mWriter startWriting];
    
    _started = NO;
}

- (IBAction)stopWriting:(id)sender {
    [mVideoInput markAsFinished];
    
    [mWriter finishWritingWithCompletionHandler:^{
        NSLog(@"MP4 finish.");
        
        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            // Create a change request from the asset to be modified.
            [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:_url];
        } completionHandler:^(BOOL success, NSError *error) {
            NSLog(@"Finished updating asset. %@", (success ? @"Success." : error));
        }];
        
        //            NSArray* items = @[_url];
        //
        //            UIActivityViewController* controller = [[UIActivityViewController alloc] initWithActivityItems:items
        //                                                                                     applicationActivities:nil];
        //            [self presentViewController:controller
        //                               animated:YES
        //                             completion:^{
        //                             }];
    }];
}


@end

















//
// CallViewController.m
// Copyright (c) 2015 Dmitry Lizin (sdkdimon@gmail.com)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "CallViewController.h"

#import <libjingle_peerconnection/RTCEAGLVideoView.h>
#import <libjingle_peerconnection/RTCVideoTrack.h>
#import <libjingle_peerconnection/RTCAudioTrack.h>
#import <libjingle_peerconnection/RTCMediaStream.h>


#import <ReactiveCocoa/RACSignal.h>
#import <ReactiveCocoa/RACSignal+Operations.h>
#import <ReactiveCocoa/NSObject+RACPropertySubscribing.h>
#import <ReactiveCocoa/RACEXTScope.h>
#import <ReactiveCocoa/RACTuple.h>
#import <ReactiveCocoa/UIControl+RACSignalSupport.h>

#import <AVFoundation/AVFoundation.h>
#import <CGSizeAspectRatioTool/CGSizeAspectRatioTool.h>
#import "AudioOutputManager.h"

typedef enum {
    RTCEAGLVideoViewTypeNone = 0,
    RTCEAGLVideoViewTypeLocal,
    RTCEAGLVideoViewTypeRemote

}RTCEAGLVideoViewType;

@interface CallViewController () <RTCEAGLVideoViewDelegate>

@property (weak, nonatomic) IBOutlet UIView *videoControlsContainerConstraintView;
@property (weak, nonatomic) IBOutlet UIView *videoControlsContainer;


@property (weak, nonatomic) IBOutlet RTCEAGLVideoView *remoteVideoView;
@property (weak, nonatomic) IBOutlet RTCEAGLVideoView *localVideoView;
@property (weak, nonatomic) IBOutlet UIButton *hangupButton;
@property (weak, nonatomic) IBOutlet UIButton *audioSwitchButton;
@property (weak,nonatomic,readwrite) IBOutlet UIButton *videoSwitchButton;
@property (weak,nonatomic,readwrite) IBOutlet UIButton *micSwitchButton;
@property (weak, nonatomic) IBOutlet UILabel *videoOverlayLabel;

@property(assign,nonatomic,readwrite) CGSize currentVideoSize;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *videoControlsContainerHeightConstraint;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *videoControlsContainerWidthConstraint;
@property (weak, nonatomic) IBOutlet UIView *videoContainer;

@property(strong,nonatomic,readonly) NSDictionary *videoSwitchButtonTitles;
@property(strong,nonatomic,readonly) NSDictionary *micSwitchButtonTitles;

@property(strong,nonatomic,readwrite) AudioOutputManager *soundRouter;

@end

@implementation CallViewController

-(instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if(self != nil){
        [self setup];
    }
    return self;
}

-(void)setup{
    _soundRouter = [[AudioOutputManager alloc] initWithAudioSession:[AVAudioSession sharedInstance]];
}


-(void)setupControls{
    _videoEnabled = NO;
    _micEnabled = YES;
    
    [_videoOverlayLabel setText:@"Video disabled. To enable video press \"Turn on video button\""];
    
    @weakify(self);
    _videoSwitchButtonTitles = @{@(UIControlStateSelected) : @"Turn off video",@(UIControlStateNormal) : @"Turn on video"};
    _micSwitchButtonTitles = @{@(UIControlStateSelected) : @"Turn off mic",@(UIControlStateNormal) : @"Turn on mic"};
    for(NSNumber *controlState in _videoSwitchButtonTitles){
        [_videoSwitchButton setTitle:_videoSwitchButtonTitles[controlState] forState:[controlState integerValue]];
    }
    [_videoSwitchButton setSelected:_videoEnabled];
    for(NSNumber *controlState in _micSwitchButtonTitles){
        [_micSwitchButton setTitle:_micSwitchButtonTitles[controlState] forState:[controlState integerValue]];
    }
    [_micSwitchButton setSelected:_micEnabled];
    
    RACSignal *videoSwitchButtonTapSignal =
    [[[[_videoSwitchButton rac_signalForControlEvents:UIControlEventTouchUpInside]
      doNext:^(UIButton *sender) {
           BOOL newState = ![sender isSelected];
          [sender setSelected:newState];
    }] map:^id(UIButton *sender) {
        return @([sender isSelected]);
    }] startWith:@(_videoEnabled)];
    
    
    
    [videoSwitchButtonTapSignal subscribeNext:^(NSNumber *isSelected) {
        @strongify(self);
        BOOL isVideoTrackEnabed = [isSelected boolValue];
        [[self videoOverlayLabel] setHidden:isVideoTrackEnabed];
        RTCVideoTrack *remoteVideoTrack = [[[self remoteMediaStream] videoTracks] firstObject];
        RTCVideoTrack *localVideoTrack = [[[self localMediaStream] videoTracks] firstObject];
        [localVideoTrack setEnabled:isVideoTrackEnabed];
        if(isVideoTrackEnabed){
            [remoteVideoTrack addRenderer:_remoteVideoView];
            [localVideoTrack addRenderer:_localVideoView];
        } else{
            [remoteVideoTrack removeRenderer:_remoteVideoView];
            [localVideoTrack removeRenderer:_localVideoView];
        }
    }];
    
    
    RACSignal *micSwitchButtonTapSignal =
    [[[[_micSwitchButton rac_signalForControlEvents:UIControlEventTouchUpInside]
        doNext:^(UIButton *sender) {
            BOOL newState = ![sender isSelected];
            [sender setSelected:newState];
        }] map:^id(UIButton *sender) {
            return @([sender isSelected]);
        }] startWith:@(_micEnabled)];
    
    [micSwitchButtonTapSignal subscribeNext:^(NSNumber *isSelected) {
        @strongify(self);
        RTCAudioTrack *localAudioTrack = [[[self localMediaStream] audioTracks] firstObject];
        [localAudioTrack setEnabled:[isSelected boolValue]];
    }];
    
    
    RACSignal *audioSwitchButtonTapSignal = [_audioSwitchButton rac_signalForControlEvents:UIControlEventTouchUpInside];
    [audioSwitchButtonTapSignal subscribeNext:^(UIButton *sender) {
    }];
    
    

    [_hangupButton addTarget:self
                      action:@selector(onHangup:)
            forControlEvents:UIControlEventTouchUpInside];
    
    [_videoControlsContainerConstraintView setBackgroundColor:[UIColor clearColor]];
    [_videoControlsContainer setBackgroundColor:[UIColor clearColor]];
    
    
    [_localVideoView setTag:RTCEAGLVideoViewTypeLocal];
    [_remoteVideoView setTag:RTCEAGLVideoViewTypeRemote];
    
    [_localVideoView setDelegate:self];
    [_remoteVideoView setDelegate:self];
    
    
    [[_audioSwitchButton rac_signalForControlEvents:UIControlEventTouchUpInside] subscribeNext:^(id x) {
        @strongify(self);
        [[self soundRouter] setOutputType:AudioOutputPortBuiltInSpeaker error:nil];
    }];
    
}

-(void)enableVideoTracks:(BOOL)enable{
   
}

-(void)viewDidLoad {
    [super viewDidLoad];
    [self setupControls];
}

-(void)onHangup:(UIButton *)button{
    [_delegate callViewControllerDidHangup:self];
}

-(void)dismissViewControllerAnimated:(BOOL)flag completion:(void (^)(void))completion{
    [self releaseMediaStreams];
    [super dismissViewControllerAnimated:flag completion:completion];

}

-(void)removeFromParentViewController{
    [self releaseMediaStreams];
    [super removeFromParentViewController];
}

-(void)videoView:(RTCEAGLVideoView *)videoView didChangeVideoSize:(CGSize)size{
        switch ([videoView tag]) {
            case RTCEAGLVideoViewTypeRemote:
                [self remoteVideoView:videoView didChangeVideoSize:size];
                break;
                
            case RTCEAGLVideoViewTypeLocal:
                [self localVideoView:videoView didChangeVideoSize:size];
                break;
                
            default:
                break;
        }
}

-(void)remoteVideoView:(RTCEAGLVideoView *)videoView didChangeVideoSize:(CGSize)size{
   
    if(!CGSizeAsectRatioIsEqualToAspectRatio(_currentVideoSize, size)){
        _currentVideoSize = size;
        CGSize videoViewMaxSize = [_videoControlsContainerConstraintView bounds].size;
        
        CGSize videoControlsContainerSize = CGSizeMakeWithAspectRatioScaledToMaxSize(size, videoViewMaxSize);
        
        CGFloat heightDelta = ceilf(videoControlsContainerSize.height) - videoViewMaxSize.height;
        CGFloat widthDelta = ceilf(videoControlsContainerSize.width) - videoViewMaxSize.width;
        
        [_videoControlsContainerWidthConstraint setConstant:widthDelta];
        [_videoControlsContainerHeightConstraint setConstant:heightDelta];
    }
}

-(void)localVideoView:(RTCEAGLVideoView *)videoView didChangeVideoSize:(CGSize)size{
    
}

#pragma mark Memory Clean

-(void)releaseMediaStreams{
    [_remoteVideoView setDelegate:nil];
    [_localVideoView setDelegate:nil];
    RTCVideoTrack *localVideoTrack = [[_localMediaStream videoTracks] firstObject];
    [localVideoTrack removeRenderer:_localVideoView];
    
    RTCVideoTrack *remoteVideoTrack = [[_remoteMediaStream videoTracks] firstObject];
    [remoteVideoTrack removeRenderer:_remoteVideoView];
    _localMediaStream = nil;
    _remoteMediaStream = nil;
}

@end

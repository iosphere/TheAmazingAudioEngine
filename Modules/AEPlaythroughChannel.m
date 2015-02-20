//
//  AEPlaythroughChannel.m
//  TheAmazingAudioEngine
//
//  Created by Michael Tyson on 21/04/2012.
//
//  This software is provided 'as-is', without any express or implied
//  warranty.  In no event will the authors be held liable for any damages
//  arising from the use of this software.
//
//  Permission is granted to anyone to use this software for any purpose,
//  including commercial applications, and to alter it and redistribute it
//  freely, subject to the following restrictions:
//
//  1. The origin of this software must not be misrepresented; you must not
//     claim that you wrote the original software. If you use this software
//     in a product, an acknowledgment in the product documentation would be
//     appreciated but is not required.
//
//  2. Altered source versions must be plainly marked as such, and must not be
//     misrepresented as being the original software.
//
//  3. This notice may not be removed or altered from any source distribution.
//

#import "AEPlaythroughChannel.h"
#import "TPCircularBuffer.h"
#import "TPCircularBuffer+AudioBufferList.h"
#import "AEAudioController_iOS5+Audiobus.h"
#import "AEAudioController_iOS5+AudiobusStub.h"

static const int kAudioBufferLength = 16384;
static const int kAudiobusReceiverPortConnectedToSelfChanged;

@interface AEPlaythroughChannel () {
    TPCircularBuffer_iOS5 _buffer;
    BOOL _audiobusConnectedToSelf;
}
@property (nonatomic, retain) AEAudioController_iOS5 *audioController;
@end

@implementation AEPlaythroughChannel
@synthesize audioController=_audioController, volume = _volume;

+(NSSet *)keyPathsForValuesAffectingAudioDescription {
    return [NSSet setWithObject:@"audioController.inputAudioDescription"];
}

- (id)initWithAudioController:(AEAudioController_iOS5*)audioController {
    if ( !(self = [super init]) ) return nil;
    TPCircularBufferInit_iOS5(&_buffer, kAudioBufferLength);
    self.audioController = audioController;
    _volume = 1.0;
    return self;
}

- (void)dealloc {
    TPCircularBufferCleanup_iOS5(&_buffer);
    self.audioController = nil;
    [super dealloc];
}

-(void)setAudioController:(AEAudioController_iOS5 *)audioController {
    if ( _audioController ) {
        [_audioController removeObserver:self forKeyPath:@"audiobusReceiverPort.connectedToSelf"];
    }
    
    [audioController retain];
    [_audioController release];
    _audioController = audioController;

    if ( _audioController ) {
        [_audioController addObserver:self forKeyPath:@"audiobusReceiverPort.connectedToSelf" options:0 context:(void*)&kAudiobusReceiverPortConnectedToSelfChanged];
        
        if ( _audioController.audiobusReceiverPort && [_audioController.audiobusReceiverPort respondsToSelector:@selector(connectedToSelf)] ) {
            _audiobusConnectedToSelf = _audioController.audiobusReceiverPort
                                    && [_audioController.audiobusReceiverPort respondsToSelector:@selector(connectedToSelf)]
                                    && [_audioController.audiobusReceiverPort connectedToSelf];
        }
    }
}

static void inputCallback(id                        receiver,
                          AEAudioController_iOS5        *audioController,
                          void                     *source,
                          const AudioTimeStamp     *time,
                          UInt32                    frames,
                          AudioBufferList          *audio) {
    AEPlaythroughChannel *THIS = receiver;
    if ( THIS->_audiobusConnectedToSelf ) return;
    TPCircularBufferCopyAudioBufferList_iOS5(&THIS->_buffer, audio, time, kTPCircularBufferCopyAll, NULL);
}

-(AEAudioController_iOS5AudioCallback)receiverCallback {
    return inputCallback;
}

static OSStatus renderCallback(id                        channel,
                               AEAudioController_iOS5        *audioController,
                               const AudioTimeStamp     *time,
                               UInt32                    frames,
                               AudioBufferList          *audio) {
    AEPlaythroughChannel *THIS = channel;
    
    while ( 1 ) {
        // Discard any buffers with an incompatible format, in the event of a format change
        AudioBufferList *nextBuffer = TPCircularBufferNextBufferList_iOS5(&THIS->_buffer, NULL);
        if ( !nextBuffer ) break;
        if ( nextBuffer->mNumberBuffers == audio->mNumberBuffers ) break;
        TPCircularBufferConsumeNextBufferList_iOS5(&THIS->_buffer);
    }
    
    UInt32 fillCount = TPCircularBufferPeek(&THIS->_buffer, NULL, AEAudioController_iOS5AudioDescription_iOS5(audioController));
    if ( fillCount > frames ) {
        UInt32 skip = fillCount - frames;
        TPCircularBufferDequeueBufferListFrames_iOS5(&THIS->_buffer,
                                                &skip,
                                                NULL,
                                                NULL,
                                                AEAudioController_iOS5AudioDescription(audioController));
    }
    
    TPCircularBufferDequeueBufferListFrames_iOS5(&THIS->_buffer,
                                            &frames,
                                            audio,
                                            NULL,
                                            AEAudioController_iOS5AudioDescription(audioController));

    return noErr;
}

-(AEAudioController_iOS5RenderCallback)renderCallback {
    return renderCallback;
}

-(AudioStreamBasicDescription)audioDescription {
    return _audioController.inputAudioDescription;
}

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ( context == &kAudiobusReceiverPortConnectedToSelfChanged ) {
        _audiobusConnectedToSelf = _audioController.audiobusReceiverPort
                                    && [_audioController.audiobusReceiverPort respondsToSelector:@selector(connectedToSelf)]
                                    && [_audioController.audiobusReceiverPort connectedToSelf];
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

@end



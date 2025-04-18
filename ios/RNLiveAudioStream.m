#import "RNLiveAudioStream.h"

@implementation RNLiveAudioStream

RCT_EXPORT_MODULE();

RCT_EXPORT_METHOD(init:(NSDictionary *) options) {
  RCTLogInfo(@"[RNLiveAudioStream] init");
  _recordState.mDataFormat.mSampleRate        = options[@"sampleRate"] == nil ? 44100 : [options[@"sampleRate"] doubleValue];
  _recordState.mDataFormat.mBitsPerChannel    = options[@"bitsPerSample"] == nil ? 16 : [options[@"bitsPerSample"] unsignedIntValue];
  _recordState.mDataFormat.mChannelsPerFrame  = options[@"channels"] == nil ? 1 : [options[@"channels"] unsignedIntValue];
  _recordState.mDataFormat.mBytesPerPacket    = (_recordState.mDataFormat.mBitsPerChannel / 8) * _recordState.mDataFormat.mChannelsPerFrame;
  _recordState.mDataFormat.mBytesPerFrame     = _recordState.mDataFormat.mBytesPerPacket;
  _recordState.mDataFormat.mFramesPerPacket   = 1;
  _recordState.mDataFormat.mReserved          = 0;
  _recordState.mDataFormat.mFormatID          = kAudioFormatLinearPCM;
  _recordState.mDataFormat.mFormatFlags       = _recordState.mDataFormat.mBitsPerChannel == 8 ? kLinearPCMFormatFlagIsPacked : (kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked);
  _recordState.bufferByteSize                 = options[@"bufferSize"] == nil ? 2048 : [options[@"bufferSize"] unsignedIntValue];
  _recordState.mSelf = self;
}

RCT_EXPORT_METHOD(start) {
  RCTLogInfo(@"[RNLiveAudioStream] start");
  _recordState.mIsRunning = true;

  OSStatus status = AudioQueueNewInput(&_recordState.mDataFormat, HandleInputBuffer, &_recordState, NULL, NULL, 0, &_recordState.mQueue);

  if (status != 0) {
    RCTLog(@"[RNLiveAudioStream] Record Failed. Cannot initialize AudioQueueNewInput. status: %i", (int) status);
    return;
  }

  for (int i = 0; i < kNumberBuffers; i++) {
    AudioQueueAllocateBuffer(_recordState.mQueue, _recordState.bufferByteSize, &_recordState.mBuffers[i]);
    AudioQueueEnqueueBuffer(_recordState.mQueue, _recordState.mBuffers[i], 0, NULL);
  }

  AudioQueueStart(_recordState.mQueue, NULL);
}

RCT_EXPORT_METHOD(stop:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock) reject) {
  if (_recordState.mIsRunning) {
    RCTLogInfo(@"[RNLiveAudioStream] stop");

    _recordState.mIsRunning = false;
    AudioQueueStop(_recordState.mQueue, true);

    for (int i = 0; i < kNumberBuffers; i++) {
      AudioQueueFreeBuffer(_recordState.mQueue, _recordState.mBuffers[i]);
    }

    AudioQueueDispose(_recordState.mQueue, true);
  } else {
    RCTLogInfo(@"[RNLiveAudioStream] stop called but not running");
  }

  resolve(@"stopped");
}

void HandleInputBuffer(void *inUserData,
                       AudioQueueRef inAQ,
                       AudioQueueBufferRef inBuffer,
                       const AudioTimeStamp *inStartTime,
                       UInt32 inNumPackets,
                       const AudioStreamPacketDescription *inPacketDesc) {
  AQRecordState* pRecordState = (AQRecordState *)inUserData;

  if (!pRecordState->mIsRunning) {
      return;
  }

  short *samples = (short *) inBuffer->mAudioData;
  long nsamples = inBuffer->mAudioDataByteSize;

  NSData *data = [NSData dataWithBytes:samples length:nsamples];
  NSString *str = [data base64EncodedStringWithOptions:0];

  [pRecordState->mSelf sendEventWithName:@"data" body:str];
  AudioQueueEnqueueBuffer(pRecordState->mQueue, inBuffer, 0, NULL);
}

- (NSArray<NSString *> *)supportedEvents {
  return @[@"data"];
}

- (void)dealloc {
  RCTLogInfo(@"[RNLiveAudioStream] dealloc");
  AudioQueueDispose(_recordState.mQueue, true);
}

@end

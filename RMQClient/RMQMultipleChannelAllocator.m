#import "RMQConnection.h"
#import "RMQAllocatedChannel.h"
#import "RMQFramesetValidator.h"
#import "RMQMultipleChannelAllocator.h"
#import "RMQUnallocatedChannel.h"
#import "RMQGCDSerialQueue.h"
#import "RMQProcessInfoNameGenerator.h"
#import "RMQFrame.h"
#import "RMQSuspendResumeDispatcher.h"
#import "RMQTransactionalConfirmations.h"

@interface RMQMultipleChannelAllocator ()
@property (atomic, readwrite) UInt16 channelNumber;
@property (nonatomic, readwrite) NSMutableDictionary *channels;
@property (nonatomic, readwrite) NSNumber *syncTimeout;
@property (nonatomic, readwrite) RMQProcessInfoNameGenerator *nameGenerator;
@end

@implementation RMQMultipleChannelAllocator
@synthesize sender;

- (instancetype)initWithChannelSyncTimeout:(NSNumber *)syncTimeout {
    self = [super init];
    if (self) {
        self.channels = [NSMutableDictionary new];
        self.channelNumber = 0;
        self.sender = nil;
        self.syncTimeout = syncTimeout;
        self.nameGenerator = [RMQProcessInfoNameGenerator new];
    }
    return self;
}

- (instancetype)init {
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (id<RMQChannel>)allocate {
    id<RMQChannel> ch;
    @synchronized(self) {
        ch = self.unsafeAllocate;
    }
    return ch;
}

- (void)releaseChannelNumber:(NSNumber *)channelNumber {
    @synchronized(self) {
        [self unsafeReleaseChannelNumber:channelNumber];
    }
}

- (NSArray *)allocatedUserChannels {
    NSMutableArray *userChannels = [self.channels.allValues mutableCopy];
    [userChannels removeObjectAtIndex:0];
    return [userChannels sortedArrayUsingComparator:^NSComparisonResult(id<RMQChannel> ch1, id<RMQChannel> ch2) {
        return ch1.channelNumber.integerValue > ch2.channelNumber.integerValue;
    }];
}

# pragma mark - RMQFrameHandler

- (void)handleFrameset:(RMQFrameset *)frameset {
    RMQAllocatedChannel *ch = self.channels[frameset.channelNumber];
    [ch handleFrameset:frameset];
}

# pragma mark - Private

- (id<RMQChannel>)unsafeAllocate {
    if (self.atCapacity) {
        return [RMQUnallocatedChannel new];
    } else if (self.atMaxIndex) {
        return self.previouslyReleasedChannel;
    } else {
        return self.newAllocation;
    }
}

- (void)unsafeReleaseChannelNumber:(NSNumber *)channelNumber {
    [self.channels removeObjectForKey:channelNumber];
}

- (id<RMQChannel>)newAllocation {
    RMQAllocatedChannel *ch = [self allocatedChannel:self.channelNumber];
    self.channelNumber++;
    return ch;
}

- (id<RMQChannel>)previouslyReleasedChannel {
    for (UInt16 i = 1; i < RMQChannelLimit; i++) {
        if (!self.channels[@(i)]) {
            return [self allocatedChannel:i];
        }
    }
    return [RMQUnallocatedChannel new];
}

- (RMQAllocatedChannel *)allocatedChannel:(NSUInteger)channelNumber {
    RMQGCDSerialQueue *commandQueue = [self suspendedDispatchQueue:channelNumber
                                                              type:@"commands"];
    RMQGCDSerialQueue *recoveryQueue = [self suspendedDispatchQueue:channelNumber
                                                               type:@"recovery"];
    RMQSuspendResumeDispatcher *dispatcher = [[RMQSuspendResumeDispatcher alloc] initWithSender:self.sender
                                                                                   commandQueue:commandQueue];
    RMQSuspendResumeDispatcher *recoveryDispatcher = [[RMQSuspendResumeDispatcher alloc] initWithSender:self.sender
                                                                                           commandQueue:recoveryQueue];
    RMQAllocatedChannel *ch = [[RMQAllocatedChannel alloc] init:@(channelNumber)
                                                contentBodySize:@(self.sender.frameMax.integerValue - RMQEmptyFrameSize)
                                                     dispatcher:dispatcher
                                             recoveryDispatcher:recoveryDispatcher
                                                  nameGenerator:self.nameGenerator
                                                      allocator:self
                                                  confirmations:[RMQTransactionalConfirmations new]];
    self.channels[@(channelNumber)] = ch;
    return ch;
}

- (BOOL)atCapacity {
    return self.channels.count == RMQChannelLimit;
}

- (BOOL)atMaxIndex {
    return self.channelNumber == RMQChannelLimit;
}

- (RMQGCDSerialQueue *)suspendedDispatchQueue:(UInt16)channelNumber
                                         type:(NSString *)type {
    RMQGCDSerialQueue *serialQueue = [[RMQGCDSerialQueue alloc] initWithName:[NSString stringWithFormat:@"channel %d (%@)", channelNumber, type]];
    [serialQueue suspend];
    return serialQueue;
}

@end

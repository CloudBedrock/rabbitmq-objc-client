#import <Foundation/Foundation.h>
#import "RMQChannel.h"
#import "RMQLocalSerialQueue.h"
#import "RMQNameGenerator.h"
#import "RMQDispatcher.h"
#import "RMQChannelAllocator.h"
#import "RMQConfirmations.h"

@interface RMQAllocatedChannel : RMQValue <RMQChannel>
- (nonnull instancetype)init:(nonnull NSNumber *)channelNumber
             contentBodySize:(nonnull NSNumber *)contentBodySize
                  dispatcher:(nonnull id<RMQDispatcher>)dispatcher
          recoveryDispatcher:(nonnull id<RMQDispatcher>)recoveryDispatcher
               nameGenerator:(nullable id<RMQNameGenerator>)nameGenerator
                   allocator:(nonnull id<RMQChannelAllocator>)allocator
               confirmations:(nonnull id<RMQConfirmations>)confirmations;
@end

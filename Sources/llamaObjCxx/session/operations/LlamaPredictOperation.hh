//
//  LlamaPredictOperation.h
//  llama
//
//  Created by Alex Rozanski on 13/03/2023.
//

#import <Foundation/NSOperation.h>

#import "common.hh"

@class LlamaContext;
@class _LlamaPredictionEvent;

NS_ASSUME_NONNULL_BEGIN

typedef void (^LlamaPredictOperationEventHandler)(_LlamaPredictionEvent *event);

@interface LlamaPredictOperation : NSOperation

- (instancetype)initWithContext:(LlamaContext *)context
                         prompt:(NSString *)prompt
                   eventHandler:(LlamaPredictOperationEventHandler)eventHandler
              eventHandlerQueue:(dispatch_queue_t)eventHandlerQueue;

@end

NS_ASSUME_NONNULL_END
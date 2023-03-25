//
//  LlamaSession.m
//  llamaObjCxx
//
//  Created by Alex Rozanski on 24/03/2023.
//

#import "LlamaSession.h"

#import "LlamaPredictOperation.hh"
#import "LlamaPredictionEvent.h"
#import "LlamaSetupOperation.hh"
#import "LlamaSessionConfig.h"

typedef NS_ENUM(NSUInteger, LlamaSessionState) {
  LlamaSessionStateNone = 0,
  LlamaSessionStateLoadingModel,
  LlamaSessionStateReadyToPredict,
  LlamaSessionStatePredicting,
  LlamaSessionStateFailed
};

BOOL IsModelLoaded(LlamaSessionState state)
{
  switch (state) {
    case LlamaSessionStateNone:
    case LlamaSessionStateLoadingModel:
      return false;
    case LlamaSessionStateReadyToPredict:
    case LlamaSessionStatePredicting:
      return true;
    case LlamaSessionStateFailed:
      return false;
    default:
      return false;
  }
}

#pragma mark -

@interface Prediction : NSObject

@property (nonatomic, readonly, copy, nonnull) NSString *prompt;
@property (nonatomic, nullable) void (^tokenHandler)(NSString*);
@property (nonatomic, nullable) void (^completionHandler)(void);
@property (nonatomic, nullable) void (^failureHandler)(NSError*);

- (instancetype)initWithPrompt:(NSString *)prompt
                  tokenHandler:(void(^)(NSString*))tokenHandler
             completionHandler:(void(^)(void))completionHandler
                failureHandler:(void(^)(NSError*))failureHandler;

@end

@implementation Prediction

- (instancetype)initWithPrompt:(NSString *)prompt
                  tokenHandler:(void(^)(NSString*))tokenHandler
             completionHandler:(void(^)(void))completionHandler
                failureHandler:(void(^)(NSError*))failureHandler
{
  if ((self = [super init])) {
    _prompt = [prompt copy];
    _tokenHandler = [tokenHandler copy];
    _completionHandler = [completionHandler copy];
    _failureHandler = [failureHandler copy];
  }

  return self;
}

@end

#pragma mark -

@interface _LlamaSession () <LlamaSetupOperationDelegate>
@end

@implementation _LlamaSession {
  LlamaSessionMode _mode;
  _LlamaSessionConfig *_config;
  NSOperationQueue *_operationQueue;

  NSMutableArray<Prediction *> *_queuedPredictions;

  LlamaSessionState _state;
  LlamaContext *_context;
}

@synthesize modelPath = _modelPath;
@synthesize delegate = _delegate;

- (instancetype)initWithModelPath:(NSString *)modelPath
                             mode:(LlamaSessionMode)mode
                           config:(_LlamaSessionConfig *)config
                         delegate:(id<_LlamaSessionDelegate>)delegate
{
  if ((self = [super init])) {
    _modelPath = [modelPath copy];
    _mode = mode;
    _config = config;
    _delegate = delegate;

    _operationQueue = [[NSOperationQueue alloc] init];
    _operationQueue.qualityOfService = NSQualityOfServiceUserInitiated;

    _state = LlamaSessionStateNone;
    _queuedPredictions = [[NSMutableArray alloc] init];
  }
  return self;
}

#pragma mark - Params

- (gpt_params)_makeParamsForPrompt:(NSString *)prompt
{
  gpt_params params;
  params.model = [_modelPath cStringUsingEncoding:NSUTF8StringEncoding];
  params.prompt = prompt ? [prompt cStringUsingEncoding:NSUTF8StringEncoding] : "";

  params.n_threads = (int)_config.numberOfThreads;
  params.n_predict = (int)_config.numberOfTokens;
  params.seed = (int32_t)_config.seed;

  if (_mode == LlamaSessionModeInstructional) {
    params.instruct = true;
  }

  if (_config.reversePrompt != nil) {
    params.antiprompt.push_back([_config.reversePrompt cStringUsingEncoding:NSUTF8StringEncoding]);
  }

  return params;
}

#pragma mark - Loading

- (BOOL)_needsModelLoad
{
  if (_context != nil) {
    return false;
  }

  switch (_state) {
    case LlamaSessionStateNone:
      return true;
    case LlamaSessionStateLoadingModel:
    case LlamaSessionStateReadyToPredict:
    case LlamaSessionStateFailed:
      return false;
    default:
      return false;
  }
}

- (void)loadModelIfNeeded
{
  NSAssert([NSThread isMainThread], @"Call -loadModelIfNeeded on main thread.");

  if (![self _needsModelLoad]) {
    return;
  }

  _state = LlamaSessionStateLoadingModel;
  [_delegate didStartLoadingModelInSession:self];

  gpt_params params = [self _makeParamsForPrompt:nil];
  LlamaSetupOperation *setupOperation = [[LlamaSetupOperation alloc] initWithParams:params delegate:self];
  [_operationQueue addOperation:setupOperation];
}

#pragma mark - Predicting

- (void)runPredictionWithPrompt:(NSString*)prompt
                   tokenHandler:(void(^)(NSString*))tokenHandler
              completionHandler:(void(^)(void))completionHandler
                 failureHandler:(void(^)(NSError*))failureHandler
{
  Prediction *prediction = [[Prediction alloc] initWithPrompt:prompt
                                                 tokenHandler:tokenHandler
                                            completionHandler:completionHandler
                                               failureHandler:failureHandler];

  if (!IsModelLoaded(_state)) {
    [_queuedPredictions addObject:prediction];
    [self loadModelIfNeeded];
  } else {
    [self _runPrediction:prediction];
  }
}

- (void)_runPrediction:(Prediction *)prediction
{
  if (_context == nil) {
    return;
  }

  gpt_params params = [self _makeParamsForPrompt:prediction.prompt];

  LlamaPredictOperationEventHandler operationEventHandler = ^(_LlamaPredictionEvent *event) {
    [event matchStarted:^{
      self->_state = LlamaSessionStatePredicting;
      [self->_delegate didStartPredictingInSession:self];
    } outputToken:^(NSString *_Nonnull token) {
      if (prediction.tokenHandler != NULL) {
        prediction.tokenHandler(token);
      }
    } completed:^{
      if (prediction.completionHandler != NULL) {
        prediction.completionHandler();
      }
    } failed:^(NSError * _Nonnull error) {
      if (prediction.failureHandler != NULL) {
        prediction.failureHandler(error);
      }
    }];
  };

  LlamaPredictOperation *predictOperation = [[LlamaPredictOperation alloc] initWithContext:_context
                                                                                    params:params
                                                                              eventHandler:operationEventHandler
                                                                         eventHandlerQueue:dispatch_get_main_queue()];

  [_operationQueue addOperation:predictOperation];
}

#pragma mark - LlamaSetupOperationDelegate

- (void)setupOperation:(nonnull LlamaSetupOperation *)operation didFailWithError:(nonnull NSError *)error
{
  NSAssert([NSThread isMainThread], @"Data synchronization should happen on main thread.");

  _state = LlamaSessionStateFailed;
  [_delegate session:self didMoveToErrorStateWithError:error];
}

- (void)setupOperation:(nonnull LlamaSetupOperation *)operation didSucceedWithContext:(nonnull LlamaContext *)context
{
  NSAssert([NSThread isMainThread], @"Data synchronization should happen on main thread.");

  _context = context;
  _state = LlamaSessionStateReadyToPredict;
  [_delegate didLoadModelInSession:self];

  for (Prediction *queuedPrediction in _queuedPredictions) {
    [self _runPrediction:queuedPrediction];
  }
  [_queuedPredictions removeAllObjects];
}

@end

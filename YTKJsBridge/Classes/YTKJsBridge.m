//
//  YTKJsBridge.m
//  YTKJsBridge
//
//  Created by lihaichun on 2018/12/21.
//  Copyright © 2018年 fenbi. All rights reserved.
//

#import "YTKJsBridge.h"
#import "UIWebView+JavaScriptContext.h"
#import "YTKJsCommandHandler.h"
#import "YTKJsCommand.h"
#import "YTKJsCommandManager.h"
#import "YTKJsEventHandler.h"
#import "YTKJsUtils.h"
#import "YTKWebInterface.h"
#import "YTKWebBasedUIWebView.h"
#import "YTKWebBasedWKWebView.h"
#import <WebKit/WebKit.h>

@interface YTKJsBridge () <YTKWebViewDelegate>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "Wdeprecated-declarations"
@property (nonatomic, weak) UIView *webView;
#pragma clang diagnostic pop

/** 方法处理对象 */
@property (nonatomic, strong) YTKJsCommandManager *manager;

/** 事件处理对象 */
@property (nonatomic, strong) YTKJsEventHandler *eventHandler;

@property (nonatomic, strong) id<YTKWebInterface> webInterface;

@property (nonatomic) UInt64 callId;

@property (nonatomic) BOOL isDebug;

@end

@implementation YTKJsBridge

- (void)dealloc {
    if (self.isDebug) {
        NSLog(@"%@ %@", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
    }
}

#pragma mark - Public Methods

- (instancetype)initWithWebView:(UIView *)webView {
    self = [super init];
    if (self) {
        if ([webView isKindOfClass:[UIWebView class]]) {
            UIWebView *web = (UIWebView *)webView;
            __weak typeof(self) weakSelf = self;
            web.ytk_delegate = weakSelf;

            self.webInterface = [[YTKWebBasedUIWebView alloc] initWithWebView:(UIWebView *)webView];
        } else if ([webView isKindOfClass:[WKWebView class]]) {
            YTKWebBasedWKWebView *web = [[YTKWebBasedWKWebView alloc] initWithWebView:(WKWebView *)webView];
            web.delegate = self.manager;
            web.eventDelegate = self.eventHandler;
            self.webInterface = web;
        }
        _webView = webView;
    }
    return self;
}

#pragma mark - Public Methods

/** command related */
- (void)addJsCommandHandlers:(NSArray *)handlers namespace:(nullable NSString *)namespace {
    [self.manager addJsCommandHandlers:handlers forNamespace:namespace];
}

- (void)removeJsCommandHandlerForNamespace:(nullable NSString *)namespace {
    [self.manager removeJsCommandHandlerForNamespace:namespace];
}

- (void)addSyncJsCommandName:(NSString *)commandName impBlock:(YTKSyncCallback)impBlock {
    [self.manager addSyncJsCommandName:commandName impBlock:impBlock];
}

- (void)addSyncJsCommandName:(NSString *)commandName namespace:(nullable NSString *)namespace impBlock:(YTKSyncCallback)impBlock {
    [self.manager addSyncJsCommandName:commandName namespace:namespace impBlock:impBlock];
}

- (void)addVoidSyncJsCommandName:(NSString *)commandName impBlock:(YTKVoidSyncCallback)impBlock {
    [self.manager addVoidSyncJsCommandName:commandName impBlock:impBlock];
}
- (void)addVoidSyncJsCommandName:(NSString *)commandName namespace:(nullable NSString *)namespace impBlock:(YTKVoidSyncCallback)impBlock {
    [self.manager addVoidSyncJsCommandName:commandName namespace:namespace impBlock:impBlock];
}

- (void)addAsyncJsCommandName:(NSString *)commandName impBlock:(YTKAsyncCallback)impBlock {
    [self.manager addAsyncJsCommandName:commandName impBlock:impBlock];
}

- (void)addAsyncJsCommandName:(NSString *)commandName namespace:(nullable NSString *)namespace impBlock:(YTKAsyncCallback)impBlock {
    [self.manager addAsyncJsCommandName:commandName namespace:namespace impBlock:impBlock];
}

- (void)removeJsCommandName:(NSString *)commandName namespace:(nullable NSString *)namespace {
    [self.manager removeJsCommandName:commandName namespace:namespace];
}

- (void)callJsCommandName:(NSString *)commandName
                 argument:(NSArray *)argument {
    if (![commandName isKindOfClass:[NSString class]]) {
        return;
    }
    NSDictionary *dict = @{@"methodName" : commandName, @"args" : argument ?: @[], @"callId" : @(self.callId ++)};
    [self.manager callJsWithDictionary:dict];
}

/** event related */
- (void)listenEvent:(NSString *)event callback:(YTKEventCallback)callback {
    [self.eventHandler listenEvent:event callback:callback];
}

- (void)unlistenEvent:(NSString *)event {
    [self.eventHandler unlistenEvent:event];
}

- (void)addListener:(id<YTKJsEventListener>)listener forEvent:(NSString *)event {
    [self.eventHandler addListener:listener forEvent:event];
}

- (void)removeListener:(id<YTKJsEventListener>)listener forEvent:(NSString *)event {
    [self.eventHandler removeListener:listener forEvent:event];
}

- (void)emit:(NSString *)event argument:(NSArray *)argument {
    [self.eventHandler emit:event argument:argument];
}

- (void)setDebugMode:(BOOL)debug {
    self.isDebug = debug;
    [self.manager setDebugMode:debug];
    [self.eventHandler setDebugMode:debug];
}

#pragma mark - Utils for UIWebView js

- (void)addJsCommandHandler:(id<YTKJsCommandHandler>)handler forCommandName:(NSString *)commandName toContext:(JSContext *)context {
    if (!handler || ![commandName isKindOfClass:[NSString class]] || !context) {
        return;
    }
    handler.webView = self.webView;
    __weak typeof(self) weakSelf = self;
    context[commandName] = ^id(JSValue *data) {
        if (!weakSelf) {
            return nil;
        }
        __strong typeof(self) strongSelf = weakSelf;
        JSValue *ret = nil;
        if ([handler respondsToSelector:@selector(handleJsCommand:inWebView:)]) {
            YTKJsCommand *commamd = [[YTKJsCommand alloc] initWithDictionary:[data toDictionary]];
            NSDictionary *result = [handler handleJsCommand:commamd inWebView:strongSelf.webView];
            if (result) {
                ret = [JSValue valueWithObject:result inContext:[JSContext currentContext]];
            }
        }
        return ret;
    };
}

- (void)addJsEventHandler:(id<YTKJsEventHandler>)handler forEvent:(NSString *)event toContext:(JSContext *)context {
    if (!handler || ![event isKindOfClass:[NSString class]] || !context) {
        return;
    }
    handler.webView = self.webView;
    __weak typeof(self) weakSelf = self;
    context[event] = ^(JSValue *data) {
        if (!weakSelf) {
            return;
        }
        __strong typeof(self) strongSelf = weakSelf;
        handler.webView = strongSelf.webView;
        if ([handler respondsToSelector:@selector(handleJsEvent:inWebView:)]) {
            YTKJsEvent *event = [[YTKJsEvent alloc] initWithDictionary:[data toDictionary]];
            [handler handleJsEvent:event inWebView:strongSelf.webView];
        }
    };
}

#pragma mark - YTKWebViewDelegate

- (void)webView:(UIWebView *)webView didCreateJavaScriptContext:(JSContext *)context {
    /** 向JS注入全局YTKJsBridge函数 */
    __weak typeof(self) weakSelf = self;
    [self addJsCommandHandler:weakSelf.manager forCommandName:self.class.description toContext:context];
    [self addJsCommandHandler:weakSelf.manager forCommandName:@"makeCallback" toContext:context];
    [self addJsEventHandler:weakSelf.eventHandler forEvent:@"sendEvent" toContext:context];
}

#pragma mark - Getter

- (YTKJsCommandManager *)manager {
    if (!_manager) {
        _manager = [YTKJsCommandManager new];
        _manager.webView = self.webView;
        _manager.webInterface = self.webInterface;
    }
    return _manager;
}

- (YTKJsEventHandler *)eventHandler {
    if (!_eventHandler) {
        _eventHandler = [YTKJsEventHandler new];
        _eventHandler.webView = self.webView;
        _eventHandler.webInterface = self.webInterface;
    }
    return _eventHandler;
}

@end

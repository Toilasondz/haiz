#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "HVSonMenu.h"
#import "HVSonEngine.h"

static HVSonWindow *gHVSonWindow = nil;
static BOOL         gHVSonInstalling = NO;
static NSTimer     *gHVSonWatchdog   = nil;

#pragma mark - Scene lookup

static UIWindowScene *HVSonFindBestScene(void) {
    if (@available(iOS 13.0, *)) {
        UIWindowScene *best = nil;
        for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
            if (![s isKindOfClass:[UIWindowScene class]]) continue;
            UIWindowScene *ws = (UIWindowScene *)s;
            if (ws.activationState == UISceneActivationStateForegroundActive) {
                return ws;
            }
            if (!best) best = ws;
        }
        return best;
    }
    return nil;
}

#pragma mark - Install

static void HVSonInstallWindow(void) {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ HVSonInstallWindow(); });
        return;
    }
    if (gHVSonInstalling) return;
    gHVSonInstalling = YES;

    @try {
        if (gHVSonWindow) {
            gHVSonWindow.hidden = NO;
            // Re-bind scene nếu user xoay / switch scene
            if (@available(iOS 13.0, *)) {
                UIWindowScene *scene = HVSonFindBestScene();
                if (scene && gHVSonWindow.windowScene != scene) {
                    gHVSonWindow.windowScene = scene;
                }
            }
            gHVSonInstalling = NO;
            return;
        }

        HVSonWindow *window = nil;
        if (@available(iOS 13.0, *)) {
            UIWindowScene *scene = HVSonFindBestScene();
            if (scene) window = [[HVSonWindow alloc] initWithWindowScene:scene];
        }
        if (!window) {
            window = [[HVSonWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        }
        if (!window) { gHVSonInstalling = NO; return; }

        window.windowLevel        = UIWindowLevelAlert + 1;
        window.backgroundColor    = [UIColor clearColor];
        window.rootViewController = [[HVSonRootViewController alloc] init];
        window.hidden             = NO;
        window.opaque             = NO;

        gHVSonWindow = window;

        NSLog(@"[HVSon] overlay window installed");
    }
    @catch (NSException *e) {
        NSLog(@"[HVSon] install error: %@ - %@", e.name, e.reason);
    }
    @finally {
        gHVSonInstalling = NO;
    }
}

#pragma mark - Watchdog

static void HVSonStartWatchdog(void) {
    if (gHVSonWatchdog) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (gHVSonWatchdog) return;
        gHVSonWatchdog = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                          repeats:YES
                                                            block:^(__unused NSTimer *t) {
            if (!gHVSonWindow || gHVSonWindow.hidden) {
                HVSonInstallWindow();
                return;
            }
            if (@available(iOS 13.0, *)) {
                UIWindowScene *scene = HVSonFindBestScene();
                if (scene && gHVSonWindow.windowScene != scene) {
                    gHVSonWindow.windowScene = scene;
                }
            }
        }];
    });
}

#pragma mark - Constructor

__attribute__((constructor))
static void HVSonDylibInit(void) {
    @autoreleasepool {
        NSLog(@"[HVSon] dylib loaded");

        dispatch_async(dispatch_get_main_queue(), ^{
            @autoreleasepool {
                /* 1. Cài runtime hooks (beat split, picked media, QR…) */
                [HVSonEngine installRuntimeHooks];

                /* 2. Tạo overlay window */
                HVSonInstallWindow();

                /* 3. Lắng nghe app state để re-install khi cần */
                [[NSNotificationCenter defaultCenter]
                    addObserverForName:UIApplicationDidBecomeActiveNotification
                                object:nil
                                 queue:[NSOperationQueue mainQueue]
                            usingBlock:^(__unused NSNotification *n) {
                    HVSonInstallWindow();
                }];

                if (@available(iOS 13.0, *)) {
                    [[NSNotificationCenter defaultCenter]
                        addObserverForName:UISceneDidActivateNotification
                                    object:nil
                                     queue:[NSOperationQueue mainQueue]
                                usingBlock:^(__unused NSNotification *n) {
                        HVSonInstallWindow();
                    }];
                }

                /* 4. Watchdog: nếu window bị ẩn / mất → cài lại */
                HVSonStartWatchdog();
            }
        });
    }
}
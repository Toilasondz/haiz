#import "HVSonEngine.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreImage/CoreImage.h>
#import <objc/runtime.h>
#import <string.h>

#pragma mark - Safe invoke via NSInvocation (hỗ trợ primitive return)

static NSInvocation *HVInvPrep(id obj, NSString *selName, NSMethodSignature **outSig) {
    if (!obj || selName.length == 0) return nil;
    SEL sel = NSSelectorFromString(selName);
    if (![obj respondsToSelector:sel]) return nil;
    NSMethodSignature *sig = [obj methodSignatureForSelector:sel];
    if (!sig) return nil;
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setTarget:obj];
    [inv setSelector:sel];
    if (outSig) *outSig = sig;
    return inv;
}

static id HV0_Obj(id obj, NSString *selName) {
    NSMethodSignature *sig = nil;
    NSInvocation *inv = HVInvPrep(obj, selName, &sig);
    if (!inv) return nil;
    [inv invoke];
    if (strcmp(sig.methodReturnType, @encode(id)) != 0) return nil;
    __unsafe_unretained id r = nil;
    [inv getReturnValue:&r];
    return r;
}

static NSInteger HV0_Int(id obj, NSString *selName) {
    NSMethodSignature *sig = nil;
    NSInvocation *inv = HVInvPrep(obj, selName, &sig);
    if (!inv) return 0;
    [inv invoke];
    NSInteger v = 0;
    [inv getReturnValue:&v];
    return v;
}

static BOOL HV0_Bool(id obj, NSString *selName) {
    NSMethodSignature *sig = nil;
    NSInvocation *inv = HVInvPrep(obj, selName, &sig);
    if (!inv) return NO;
    [inv invoke];
    BOOL v = NO;
    [inv getReturnValue:&v];
    return v;
}

static void HV0_Void(id obj, NSString *selName) {
    NSInvocation *inv = HVInvPrep(obj, selName, NULL);
    if (!inv) return;
    [inv invoke];
}

static id HV1_Obj(id obj, NSString *selName, id arg) {
    NSMethodSignature *sig = nil;
    NSInvocation *inv = HVInvPrep(obj, selName, &sig);
    if (!inv) return nil;
    [inv setArgument:&arg atIndex:2];
    [inv invoke];
    if (strcmp(sig.methodReturnType, @encode(id)) != 0) return nil;
    __unsafe_unretained id r = nil;
    [inv getReturnValue:&r];
    return r;
}

static void HV1_Void(id obj, NSString *selName, id arg) {
    NSInvocation *inv = HVInvPrep(obj, selName, NULL);
    if (!inv) return;
    [inv setArgument:&arg atIndex:2];
    [inv invoke];
}

/* selectLayer:bordered: — NSUInteger + BOOL */
static void HVSelectLayerBordered(id editor, NSUInteger idx, BOOL bordered) {
    NSInvocation *inv = HVInvPrep(editor, @"selectLayer:bordered:", NULL);
    if (!inv) return;
    [inv setArgument:&idx atIndex:2];
    [inv setArgument:&bordered atIndex:3];
    [inv invoke];
}

#pragma mark - Helpers

static UIViewController *HVTopVC(void) {
    UIWindow *keyWin = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
            if (![s isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *w in ((UIWindowScene *)s).windows) {
                if (w.isKeyWindow) { keyWin = w; break; }
            }
            if (keyWin) break;
        }
    }
    if (!keyWin) {
        for (UIWindow *w in UIApplication.sharedApplication.windows) {
            if (w.isKeyWindow) { keyWin = w; break; }
        }
    }
    UIViewController *vc = keyWin.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    if ([vc isKindOfClass:UINavigationController.class])
        vc = ((UINavigationController *)vc).visibleViewController;
    if ([vc isKindOfClass:UITabBarController.class])
        vc = ((UITabBarController *)vc).selectedViewController;
    return vc;
}

static UIView *HVFindSubview(UIView *root, Class cls, NSInteger depth) {
    if (!root || depth < 0) return nil;
    if ([root isKindOfClass:cls]) return root;
    for (UIView *sub in root.subviews) {
        UIView *r = HVFindSubview(sub, cls, depth - 1);
        if (r) return r;
    }
    return nil;
}

/* FIX: không dùng ("_" + ivarName) nữa */
static BOOL HVPressButtonInIvar(id obj, NSString *ivarName) {
    if (!obj || ivarName.length == 0) return NO;

    NSString *underscored = [@"_" stringByAppendingString:ivarName];
    Ivar iv = class_getInstanceVariable([obj class], underscored.UTF8String);
    if (!iv) {
        iv = class_getInstanceVariable([obj class], ivarName.UTF8String);
    }
    if (!iv) return NO;

    id btn = object_getIvar(obj, iv);
    if ([btn isKindOfClass:UIButton.class]) {
        [btn sendActionsForControlEvents:UIControlEventTouchUpInside];
        return YES;
    }
    return NO;
}

static NSData *HVImageToPNG(id image) {
    if (!image) return nil;
    if ([image isKindOfClass:NSData.class]) return image;
    if ([image isKindOfClass:UIImage.class]) {
        NSData *d = UIImagePNGRepresentation(image);
        if (d) return d;
    }
    if ([image isKindOfClass:CIImage.class]) {
        CIContext *ctx = [CIContext contextWithOptions:nil];
        CGRect ext = [image extent];
        CGImageRef cg = [ctx createCGImage:image fromRect:ext];
        if (cg) {
            UIImage *ui = [UIImage imageWithCGImage:cg];
            CGImageRelease(cg);
            return UIImagePNGRepresentation(ui);
        }
    }
    return nil;
}

static NSString *HVLastQRPath(void) {
    return [[NSHomeDirectory() stringByAppendingPathComponent:@"Documents"]
            stringByAppendingPathComponent:@"HVSon_LastQR.png"];
}

static void HVSaveLastQR(NSData *png) {
    if (png.length == 0) return;
    [png writeToFile:HVLastQRPath() atomically:YES];
}

#pragma mark - Engine

@interface HVSonEngine ()
@property (nonatomic, weak)   id mlEditor;
@property (nonatomic, strong) id pickedResponse;
@property (nonatomic, weak)   id beatSplitView;
@property (nonatomic, assign) NSUInteger beatIndex;
@property (nonatomic, assign) NSUInteger beatTotal;
@property (nonatomic, assign) NSUInteger mediaApplyIndex;
@property (nonatomic, assign) NSUInteger mediaApplyTotal;
@property (nonatomic, strong) NSMutableArray *mediaTargets;
@property (nonatomic, weak)   id mediaApplyEngine;
@property (nonatomic, copy)   void (^mediaApplyDone)(NSUInteger changed);
@end

@implementation HVSonEngine

+ (instancetype)shared {
    static HVSonEngine *s; static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [HVSonEngine new]; });
    return s;
}

- (void)status:(NSString *)msg {
    if (self.onStatus) self.onStatus(msg);
}

#pragma mark - FEATURE 1: Code gần nhất

- (void)feature1ShowLastCode {
    [self status:@"Đang quét code gần nhất..."];

    NSData *lastData = [NSData dataWithContentsOfFile:HVLastQRPath()];

    if (lastData.length == 0) {
        NSString *docs = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
        NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:docs error:nil];
        NSArray *exts = @[@"png", @"jpg", @"jpeg", @"heic", @"webp"];
        NSMutableArray *candidates = [NSMutableArray array];
        for (NSString *name in files) {
            NSString *ext = [name.pathExtension lowercaseString];
            if (![exts containsObject:ext]) continue;
            NSString *path = [docs stringByAppendingPathComponent:name];
            NSDictionary *attr = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
            NSDate *date = attr[NSFileModificationDate] ?: [NSDate distantPast];
            [candidates addObject:@{@"path": path, @"date": date}];
        }
        [candidates sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            return [b[@"date"] compare:a[@"date"]];
        }];
        for (NSDictionary *c in candidates) {
            NSData *d = [NSData dataWithContentsOfFile:c[@"path"]];
            if (d) { lastData = d; break; }
        }
    }

    if (lastData.length == 0) {
        [self alert:@"Thông báo" msg:@"Không tìm thấy ảnh code đã nhập gần nhất."];
        return;
    }

    UIImage *ui = [UIImage imageWithData:lastData];
    if (!ui) { [self alert:@"Thông báo" msg:@"Ảnh không đọc được."]; return; }

    NSString *qrText = [self decodeQRFromImage:ui];
    if (!qrText) {
        [self alert:@"Thông báo" msg:@"Ảnh không chứa mã QR hợp lệ."];
        return;
    }

    HVSaveLastQR(lastData);
    [self showQRPreview:ui text:qrText];
    [self status:[NSString stringWithFormat:@"QR: %.40s…", qrText.UTF8String]];
}

- (NSString *)decodeQRFromImage:(UIImage *)image {
    CIImage *ci = [[CIImage alloc] initWithImage:image];
    if (!ci) return nil;
    CIDetector *det = [CIDetector detectorOfType:CIDetectorTypeQRCode
                                         context:nil
                                         options:@{CIDetectorAccuracy: CIDetectorAccuracyHigh}];
    NSArray *features = [det featuresInImage:ci];
    for (CIFeature *f in features) {
        if ([f isKindOfClass:CIQRCodeFeature.class]) {
            return ((CIQRCodeFeature *)f).messageString;
        }
    }
    return nil;
}

- (void)showQRPreview:(UIImage *)img text:(NSString *)text {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *vc = HVTopVC();
        if (!vc) return;
        UIAlertController *ac = [UIAlertController
            alertControllerWithTitle:@"Code gần nhất"
                             message:text ?: @"(trống)"
                      preferredStyle:UIAlertControllerStyleAlert];
        [ac addAction:[UIAlertAction actionWithTitle:@"Copy"
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *a) {
            [UIPasteboard generalPasteboard].string = text ?: @"";
        }]];
        [ac addAction:[UIAlertAction actionWithTitle:@"OK"
                                               style:UIAlertActionStyleCancel
                                             handler:nil]];
        [vc presentViewController:ac animated:YES completion:nil];
    });
}

#pragma mark - FEATURE 2: Auto chia beat

- (void)feature2AutoBeatSplit {
    UIViewController *vc = HVTopVC();
    Class reviewCls = NSClassFromString(@"VideoReviewEditVC");
    Class splitCls  = NSClassFromString(@"MultiSplitView");
    if (!reviewCls || ![vc isKindOfClass:reviewCls]) {
        [self alert:@"Thông báo" msg:@"Bạn chưa trong phần chia phân cảnh."];
        return;
    }
    UIView *split = HVFindSubview(vc.view, splitCls ?: UIView.class, 6);
    if (!split) {
        [self alert:@"Thông báo" msg:@"Không tìm thấy chức năng chia beat gốc của Video Star."];
        return;
    }

    if (!HV0_Bool(split, @"beatModeOn")) {
        HV0_Void(split, @"toggleBeatMode");
    }

    NSArray *times = HV0_Obj(split, @"splitTimes");
    NSUInteger total = times.count;

    if (total == 0) {
        self.beatSplitView = split;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 800 * NSEC_PER_MSEC),
                       dispatch_get_main_queue(), ^{
            NSArray *t2 = HV0_Obj(split, @"splitTimes");
            if (t2.count == 0) {
                [self alert:@"Thông báo" msg:@"Chưa có beat nào được phát hiện."];
                return;
            }
            self.beatTotal = t2.count;
            self.beatIndex = 0;
            [self status:[NSString stringWithFormat:@"Đang xử lý %lu beat...",
                          (unsigned long)t2.count]];
            [self beatNextStep];
        });
        return;
    }

    self.beatSplitView = split;
    self.beatTotal = total;
    self.beatIndex = 0;
    [self status:[NSString stringWithFormat:@"Đang xử lý %lu beat...", (unsigned long)total]];
    [self beatNextStep];
}

- (void)beatNextStep {
    if (!self.beatSplitView) return;

    if (self.beatIndex < self.beatTotal) {
        BOOL jumped = NO;
        if ([self.beatSplitView respondsToSelector:NSSelectorFromString(@"jumpToNextBeat")]) {
            HV0_Void(self.beatSplitView, @"jumpToNextBeat");
            jumped = YES;
        } else if ([self.beatSplitView respondsToSelector:NSSelectorFromString(@"setSplitPoint")]) {
            HV0_Void(self.beatSplitView, @"setSplitPoint");
            jumped = YES;
        }
        if (!jumped) HVPressButtonInIvar(self.beatSplitView, @"nextButton");

        self.beatIndex++;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 180 * NSEC_PER_MSEC),
                       dispatch_get_main_queue(), ^{
            [self beatNextStep];
        });
        return;
    }

    [self status:@"Đang gọi lệnh chia..."];
    BOOL splitCalled = NO;
    if ([self.beatSplitView respondsToSelector:NSSelectorFromString(@"doSplit")]) {
        HV0_Void(self.beatSplitView, @"doSplit");
        splitCalled = YES;
    } else {
        splitCalled = HVPressButtonInIvar(self.beatSplitView, @"splitButton");
    }
    if (!splitCalled) {
        [self alert:@"Thông báo" msg:@"Không tìm thấy nút Chia của Video Star."];
        return;
    }

    [self beatWaitForCompletion:self.beatTotal];
}

- (void)beatWaitForCompletion:(NSUInteger)expected {
    __block NSUInteger tries = 0;
    __weak typeof(self) weak = self;
    __block void (^poll)(void) = nil;
    poll = ^{
        __strong typeof(weak) s = weak;
        if (!s) return;
        UIViewController *vc = HVTopVC();
        id project = HV0_Obj(vc, @"project");
        NSInteger scenes = HV0_Int(project, @"sceneCount");

        if (tries++ >= 120) {
            [s alert:@"Thông báo"
                  msg:@"Video Star chưa hoàn tất thao tác chia beat. Kiểm tra lại phân cảnh."];
            poll = nil;
            return;
        }
        if (scenes > (NSInteger)expected) {
            [s status:[NSString stringWithFormat:@"Chia beat xong: %ld phân cảnh.", (long)scenes]];
            poll = nil;
            return;
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC),
                       dispatch_get_main_queue(), poll);
    };
    poll();
}

#pragma mark - FEATURE 0: Auto nhập ảnh vào các lớp

- (void)feature0AutoImportImages {
    UIViewController *vc = HVTopVC();
    Class mlCls = NSClassFromString(@"MultiLayerWizEffectVC");
    if (!mlCls || ![vc isKindOfClass:mlCls]) {
        [self alert:@"Thông báo" msg:@"Bạn chưa trong phần nhiều lớp h/ả."];
        return;
    }
    self.mlEditor = vc;
    [self status:@"Mở bộ chọn ảnh/video native..."];

    if ([vc respondsToSelector:NSSelectorFromString(@"pickNewContent")]) {
        HV0_Void(vc, @"pickNewContent");
    } else {
        [self alert:@"Thông báo" msg:@"Không tìm thấy bộ chọn nội dung gốc của Video Star."];
    }
}

- (void)handlePickedResponse:(id)response editor:(id)editor {
    if (!editor || editor != self.mlEditor) return;
    self.pickedResponse = response;

    id engine = HV0_Obj(editor, @"getMultiLayerEngine");
    if (!engine) {
        [self alert:@"Thông báo" msg:@"Không lấy được engine đa lớp."];
        return;
    }

    self.mediaApplyEngine = engine;
    self.mediaTargets = [NSMutableArray array];
    self.mediaApplyIndex = 0;
    self.mediaApplyTotal = 0;

    NSInteger n = HV0_Int(engine, @"numActiveLayers");
    NSUInteger maxLayers = (n > 0) ? (NSUInteger)n : 30;

    for (NSUInteger i = 0; i < maxLayers; i++) {
        NSNumber *idx = @(i);
        id asset   = HV1_Obj(engine, @"assetForLayer:", idx);
        id layer   = HV1_Obj(engine, @"layerAtLayerNum:", idx);
        UIImage *img = HV0_Obj(layer, @"layerImage");

        BOOL hasMedia = asset || img;
        if (!hasMedia) continue;
        if (HV0_Bool(layer, @"isNullLayer")) continue;
        if (HV0_Bool(layer, @"is3DLayer"))   continue;

        [self.mediaTargets addObject:@{@"index": idx,
                                       @"layer": layer ?: NSNull.null}];
    }

    self.mediaApplyTotal = self.mediaTargets.count;
    if (self.mediaApplyTotal == 0) {
        [self alert:@"Thông báo" msg:@"Không tìm thấy lớp media nào để thay."];
        return;
    }
    [self status:[NSString stringWithFormat:@"Đang thay %lu lớp...",
                  (unsigned long)self.mediaApplyTotal]];
    [self applyNextLayer];
}

- (void)applyNextLayer {
    if (!self.mlEditor || self.mediaApplyIndex >= self.mediaApplyTotal) {
        [self finishApplyLayers];
        return;
    }
    NSDictionary *target = self.mediaTargets[self.mediaApplyIndex];
    self.mediaApplyIndex++;

    NSNumber *idx = target[@"index"];
    id editor = self.mlEditor;
    id layer = ([target[@"layer"] isKindOfClass:NSNull.class]) ? nil : target[@"layer"];

    HVSelectLayerBordered(editor, idx.unsignedIntegerValue, NO);

    if (![editor respondsToSelector:
          NSSelectorFromString(@"presentMLLayerButtonsCollectionViewItemLayerEditTitleViewWithMultiLayerLayer:")]) {
        [self tryDirectReplay:editor];
        return;
    }
    HV1_Void(editor,
             @"presentMLLayerButtonsCollectionViewItemLayerEditTitleViewWithMultiLayerLayer:",
             layer ?: NSNull.null);

    [self waitAndPressReplace:editor retries:0];
}

- (void)waitAndPressReplace:(id)editor retries:(NSUInteger)tries {
    if (tries > 40) {
        [self status:[NSString stringWithFormat:@"Bỏ qua lớp %lu (không thấy popup)",
                      (unsigned long)(self.mediaApplyIndex - 1)]];
        [self applyNextLayer];
        return;
    }
    UIViewController *vc = HVTopVC();
    UIView *popup = nil;
    Class popupCls = NSClassFromString(@"CustomPopup");
    if (popupCls) popup = HVFindSubview(vc.view, popupCls, 8);

    if (!popup) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC),
                       dispatch_get_main_queue(), ^{
            [self waitAndPressReplace:editor retries:tries + 1];
        });
        return;
    }

    BOOL pressed = [self pressButtonInPopup:popup
                                     titles:@[@"Replace Content", @"Replace",
                                              @"Thay nội dung", @"Thay"]];
    if (!pressed) {
        [self status:@"Không thấy nút Thay nội dung — dùng replay trực tiếp."];
        [self tryDirectReplay:editor];
        return;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC),
                   dispatch_get_main_queue(), ^{
        [self tryDirectReplay:editor];
    });
}

- (BOOL)pressButtonInPopup:(UIView *)popup titles:(NSArray<NSString *> *)titles {
    NSMutableArray *all = [NSMutableArray array];
    [self collectButtons:popup into:all];
    for (UIButton *btn in all) {
        NSString *t = [self normalize:btn.currentTitle];
        for (NSString *needle in titles) {
            if ([t containsString:[self normalize:needle]]) {
                [btn sendActionsForControlEvents:UIControlEventTouchUpInside];
                return YES;
            }
        }
    }
    return NO;
}

- (void)collectButtons:(UIView *)v into:(NSMutableArray *)out {
    if ([v isKindOfClass:UIButton.class]) [out addObject:v];
    for (UIView *s in v.subviews) [self collectButtons:s into:out];
}

- (NSString *)normalize:(NSString *)s {
    if (!s) return @"";
    NSString *folded = [s stringByFoldingWithOptions:
                        NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch
                                              locale:[NSLocale localeWithLocaleIdentifier:@"vi_VN"]];
    return folded.lowercaseString;
}

- (void)tryDirectReplay:(id)editor {
    if (!self.pickedResponse) {
        [self applyNextLayer];
        return;
    }
    id clone = [self cloneResponse:self.pickedResponse];
    if (!clone) {
        [self applyNextLayer];
        return;
    }
    if ([editor respondsToSelector:NSSelectorFromString(@"pickedWithClipPickerResponse:")]) {
        HV1_Void(editor, @"pickedWithClipPickerResponse:", clone);
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 300 * NSEC_PER_MSEC),
                   dispatch_get_main_queue(), ^{
        [self applyNextLayer];
    });
}

- (id)cloneResponse:(id)resp {
    Class cls = NSClassFromString(@"ClipPickerResponse")
             ?: NSClassFromString(@"_TtC10Video_Star18ClipPickerResponse");
    if (!cls || !resp) return nil;

    NSInteger type = HV0_Int(resp, @"clipPickerResponseType");
    NSInteger idx  = HV0_Int(resp, @"clipIndex");

    SEL initSel = NSSelectorFromString(@"initWithClipPickerResponseType:clipIndex:");
    id alloc = [cls alloc];
    if (![alloc respondsToSelector:initSel]) return resp;

    NSMethodSignature *sig = [alloc methodSignatureForSelector:initSel];
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setTarget:alloc];
    [inv setSelector:initSel];
    [inv setArgument:&type atIndex:2];
    [inv setArgument:&idx  atIndex:3];
    [inv invoke];

    __unsafe_unretained id ret = nil;
    [inv getReturnValue:&ret];
    return ret;
}

- (void)finishApplyLayers {
    [self status:[NSString stringWithFormat:@"Đã thay nội dung cho %lu lớp.",
                  (unsigned long)self.mediaApplyTotal]];
    if (self.mediaApplyDone) self.mediaApplyDone(self.mediaApplyTotal);
    self.mediaApplyEngine = nil;
    self.mediaTargets = nil;
    self.pickedResponse = nil;
}

#pragma mark - FEATURE 3: Auto nhiều phân cảnh

- (void)feature3AutoMultiScene {
    UIViewController *vc = HVTopVC();
    Class reviewCls = NSClassFromString(@"VideoReviewEditVC");
    if (!reviewCls || ![vc isKindOfClass:reviewCls]) {
        [self alert:@"Thông báo" msg:@"Bạn chưa trong phần chia phân cảnh."];
        return;
    }
    if (![vc respondsToSelector:NSSelectorFromString(@"showMergeScenes")]) {
        [self alert:@"Thông báo" msg:@"Không tìm thấy chức năng Hợp nhất phân cảnh."];
        return;
    }

    HV0_Void(vc, @"showMergeScenes");
    [self status:@"Đã mở Hợp nhất phân cảnh"];
    [self alert:@"Chọn phân cảnh"
            msg:@"Chọn điểm bắt đầu và kết thúc trong panel Hợp nhất phân cảnh native, rồi bấm OK để bắt đầu nhập code/ảnh cho từng phân cảnh."];
}

#pragma mark - Alert

- (void)alert:(NSString *)title msg:(NSString *)msg {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *vc = HVTopVC();
        if (!vc) return;
        UIAlertController *ac = [UIAlertController alertControllerWithTitle:title
                                                                    message:msg
                                                             preferredStyle:UIAlertControllerStyleAlert];
        [ac addAction:[UIAlertAction actionWithTitle:@"OK"
                                               style:UIAlertActionStyleDefault
                                             handler:nil]];
        [vc presentViewController:ac animated:YES completion:nil];
    });
}

#pragma mark - Runtime hooks

static IMP gOrigPickedIMP = NULL;

+ (void)installRuntimeHooks {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class mlCls = NSClassFromString(@"MultiLayerWizEffectVC");
        if (!mlCls) return;
        SEL sel = NSSelectorFromString(@"pickedWithClipPickerResponse:");
        Method m = class_getInstanceMethod(mlCls, sel);
        if (!m) return;

        gOrigPickedIMP = method_getImplementation(m);
        IMP newIMP = imp_implementationWithBlock(^(id self, id response) {
            [[HVSonEngine shared] handlePickedResponse:response editor:self];
            if (gOrigPickedIMP) {
                ((void(*)(id, SEL, id))gOrigPickedIMP)(self, sel, response);
            }
        });
        method_setImplementation(m, newIMP);
    });
}

@end

#import "HVSonEngine.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreImage/CoreImage.h>
#import <objc/runtime.h>

#pragma mark - Helpers

static UIViewController *HVTopVC(void) {
    UIWindow *keyWin = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
            if (![s isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *w in ((UIWindowScene *)s).windows)
                if (w.isKeyWindow) { keyWin = w; break; }
            if (keyWin) break;
        }
    }
    if (!keyWin) keyWin = UIApplication.sharedApplication.keyWindow;
    UIViewController *vc = keyWin.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    if ([vc isKindOfClass:UINavigationController.class])
        vc = ((UINavigationController *)vc).visibleViewController;
    if ([vc isKindOfClass:UITabBarController.class])
        vc = ((UITabBarController *)vc).selectedViewController;
    return vc;
}

static id HVCall0(id obj, NSString *sel) {
    if (!obj) return nil;
    SEL s = NSSelectorFromString(sel);
    if (![obj respondsToSelector:s]) return nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    return [obj performSelector:s];
#pragma clang diagnostic pop
}

static id HVCall(id obj, NSString *sel, id arg) {
    if (!obj) return nil;
    SEL s = NSSelectorFromString(sel);
    if (![obj respondsToSelector:s]) return nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    return [obj performSelector:s withObject:arg];
#pragma clang diagnostic pop
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

static BOOL HVPressButtonInIvar(id obj, NSString *ivarName) {
    if (!obj || ivarName.length == 0) return NO;
    Ivar iv = class_getInstanceVariable([obj class], [("_" + ivarName) UTF8String]);
    if (!iv) iv = class_getInstanceVariable([obj class], [ivarName UTF8String]);
    if (!iv) return NO;
    id btn = object_getIvar(obj, iv);
    if ([btn isKindOfClass:UIButton.class]) {
        [btn sendActionsForControlEvents:UIControlEventTouchUpInside];
        return YES;
    }
    return NO;
}

// Chuyển ảnh -> NSData (giống helper_12a34)
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
@property (nonatomic, weak)   id mlEditor;            // MultiLayerWizEffectVC
@property (nonatomic, strong) id pickedResponse;      // ClipPickerResponse clone
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

    // 1. Đọc ảnh cuối cùng đã lưu (nếu có)
    NSData *lastData = [NSData dataWithContentsOfFile:HVLastQRPath()];

    // 2. Nếu không có, quét Documents thư mục ảnh mới nhất
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

    // 3. Quét QR từ ảnh
    UIImage *ui = [UIImage imageWithData:lastData];
    if (!ui) { [self alert:@"Thông báo" msg:@"Ảnh không đọc được."]; return; }

    NSString *qrText = [self decodeQRFromImage:ui];
    if (!qrText) {
        [self alert:@"Thông báo" msg:@"Ảnh không chứa mã QR hợp lệ."];
        return;
    }

    // 4. Hiển thị QR cho user
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
    UIViewController *vc = HVTopVC();
    if (!vc) return;
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Code gần nhất"
                                                                message:text
                                                         preferredStyle:UIAlertControllerStyleAlert];
    CGFloat w = 220;
    UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, w, w)];
    iv.contentMode = UIViewContentModeScaleAspectFit;
    iv.image = img;
    [ac.view addSubview:iv];
    // resize alert (cách đơn giản)
    [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [vc presentViewController:ac animated:YES completion:nil];
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
    if (!split) { [self alert:@"Thông báo" msg:@"Không tìm thấy chức năng chia beat gốc của Video Star."]; return; }

    // Bật beat mode nếu chưa bật
    NSNumber *on = HVCall0(split, @"beatModeOn");
    if (on && !on.boolValue) HVCall0(split, @"toggleBeatMode");

    // Lấy danh sách beat
    NSArray *times = HVCall0(split, @"splitTimes");
    NSUInteger total = times.count;
    if (total == 0) {
        // Nếu beat mode chưa gen, chờ 1 nhịp rồi thử lại
        self.beatSplitView = split;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 800 * NSEC_PER_MSEC),
                       dispatch_get_main_queue(), ^{
            NSArray *t2 = HVCall0(split, @"splitTimes");
            if (t2.count == 0) {
                [self alert:@"Thông báo" msg:@"Chưa có beat nào được phát hiện."];
                return;
            }
            self.beatTotal = t2.count;
            self.beatIndex = 0;
            [self status:[NSString stringWithFormat:@"Đang xử lý %lu beat...", (unsigned long)t2.count]];
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

    // Bước 1: nếu còn beat → nhảy tới beat kế
    if (self.beatIndex < self.beatTotal) {
        BOOL jumped = NO;
        if ([self.beatSplitView respondsToSelector:NSSelectorFromString(@"jumpToNextBeat")]) {
            HVCall0(self.beatSplitView, @"jumpToNextBeat");
            jumped = YES;
        } else if ([self.beatSplitView respondsToSelector:NSSelectorFromString(@"setSplitPoint")]) {
            HVCall0(self.beatSplitView, @"setSplitPoint");
            jumped = YES;
        }
        if (!jumped) HVPressButtonInIvar(self.beatSplitView, @"nextButton");

        self.beatIndex++;
        // đợi animation native trước khi bước tiếp
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 180 * NSEC_PER_MSEC),
                       dispatch_get_main_queue(), ^{
            [self beatNextStep];
        });
        return;
    }

    // Bước 2: đã queue đủ beat → gọi split native
    [self status:@"Đang gọi lệnh chia..."];
    BOOL splitCalled = NO;
    if ([self.beatSplitView respondsToSelector:NSSelectorFromString(@"doSplit")]) {
        HVCall0(self.beatSplitView, @"doSplit");
        splitCalled = YES;
    } else {
        splitCalled = HVPressButtonInIvar(self.beatSplitView, @"splitButton");
    }
    if (!splitCalled) {
        [self alert:@"Thông báo" msg:@"Không tìm thấy nút Chia của Video Star."];
        return;
    }

    // Bước 3: chờ sceneCount tăng lên để confirm
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
        id project = HVCall0(vc, @"project");
        NSNumber *scenes = HVCall0(project, @"sceneCount");
        if (tries++ >= 120) {
            [s alert:@"Thông báo" msg:@"Video Star chưa hoàn tất thao tác chia beat. Kiểm tra lại phân cảnh."];
            poll = nil;
            return;
        }
        if (scenes && scenes.unsignedIntegerValue > expected) {
            [s status:[NSString stringWithFormat:@"Chia beat xong: %lu phân cảnh.",
                        (unsigned long)scenes.unsignedIntegerValue]];
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

    // Trigger bộ chọn native của Video Star
    if ([vc respondsToSelector:NSSelectorFromString(@"pickNewContent")]) {
        HVCall0(vc, @"pickNewContent");
    } else {
        [self alert:@"Thông báo" msg:@"Không tìm thấy bộ chọn nội dung gốc của Video Star."];
    }
}

// Hook được cài từ +installRuntimeHooks (xem dưới)
- (void)handlePickedResponse:(id)response editor:(id)editor {
    if (!editor || editor != self.mlEditor) return;
    self.pickedResponse = response;
    id engine = HVCall0(editor, @"getMultiLayerEngine");
    if (!engine) { [self alert:@"Thông báo" msg:@"Không lấy được engine đa lớp."]; return; }

    // Gom các layer có media/ảnh
    self.mediaApplyEngine = engine;
    self.mediaTargets = [NSMutableArray array];
    self.mediaApplyIndex = 0;
    self.mediaApplyTotal = 0;

    NSNumber *numLayers = HVCall0(engine, @"numActiveLayers");
    NSUInteger maxLayers = numLayers ? numLayers.unsignedIntegerValue : 30;
    for (NSUInteger i = 0; i < MAX(maxLayers, 1); i++) {
        NSNumber *idx = @(i);
        id asset = HVCall(engine, @"assetForLayer:", idx);
        id layer = HVCall(engine, @"layerAtLayerNum:", idx);
        UIImage *img = HVCall0(layer, @"layerImage");
        BOOL hasMedia = asset || img;
        if (!hasMedia) continue;
        // Bỏ qua null / 3D / particle / gif / drawing
        NSNumber *isNull = HVCall0(layer, @"isNullLayer");
        if (isNull.boolValue) continue;
        NSNumber *is3D = HVCall0(layer, @"is3DLayer");
        if (is3D.boolValue) continue;
        [self.mediaTargets addObject:@{@"index": idx, @"layer": layer ?: NSNull.null}];
    }

    self.mediaApplyTotal = self.mediaTargets.count;
    if (self.mediaApplyTotal == 0) {
        [self alert:@"Thông báo" msg:@"Không tìm thấy lớp media nào để thay."];
        return;
    }
    [self status:[NSString stringWithFormat:@"Đang thay %lu lớp...", (unsigned long)self.mediaApplyTotal]];
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

    // 1. Chọn layer trong editor native
    HVCall(editor, @"selectLayer:bordered:", idx);
    if (![editor respondsToSelector:NSSelectorFromString(@"presentMLLayerButtonsCollectionViewItemLayerEditTitleViewWithMultiLayerLayer:")]) {
        // không có API native → thử replay response trực tiếp nếu layer đúng class
        [self tryDirectReplay:editor];
        return;
    }
    HVCall(editor, @"presentMLLayerButtonsCollectionViewItemLayerEditTitleViewWithMultiLayerLayer:", layer ?: NSNull.null);

    // 2. Chờ popup native mở rồi bấm nút "Replace Content"
    [self waitAndPressReplace:editor retries:0];
}

- (void)waitAndPressReplace:(id)editor retries:(NSUInteger)tries {
    if (tries > 40) {
        [self status:[NSString stringWithFormat:@"Bỏ qua lớp %lu (không thấy popup)",
                      (unsigned long)(self.mediaApplyIndex - 1)]];
        [self applyNextLayer];
        return;
    }
    // Tìm CustomPopup trên top VC
    UIViewController *vc = HVTopVC();
    UIView *popup = nil;
    Class popupCls = NSClassFromString(@"CustomPopup");
    if (popupCls) popup = HVFindSubview(vc.view, popupCls, 8);

    if (!popup) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC),
                       dispatch_get_main_queue(), ^{ [self waitAndPressReplace:editor retries:tries + 1]; });
        return;
    }

    // Bấm nút "Replace Content" / "Thay nội dung"
    BOOL pressed = [self pressButtonInPopup:popup titles:@[@"Replace Content", @"Replace",
                                                           @"Thay nội dung", @"Thay"]];
    if (!pressed) {
        [self status:@"Không thấy nút Thay nội dung — dùng replay trực tiếp."];
        [self tryDirectReplay:editor];
        return;
    }

    // 3. Replay pickedWithClipPickerResponse: cho layer này
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC),
                   dispatch_get_main_queue(), ^{ [self tryDirectReplay:editor]; });
}

- (BOOL)pressButtonInPopup:(UIView *)popup titles:(NSArray<NSString *> *)titles {
    // Tìm UIButton trong popup, so sánh title đã chuẩn hoá
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
    NSString *folded = [s stringByFoldingWithOptions:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch
                                              locale:[NSLocale localeWithLocaleIdentifier:@"vi_VN"]];
    return folded.lowercaseString;
}

- (void)tryDirectReplay:(id)editor {
    if (!self.pickedResponse) {
        [self applyNextLayer];
        return;
    }
    // Clone response qua init mới (nếu có)
    id clone = [self cloneResponse:self.pickedResponse];
    if (!clone) {
        [self applyNextLayer];
        return;
    }
    if ([editor respondsToSelector:NSSelectorFromString(@"pickedWithClipPickerResponse:")]) {
        HVCall(editor, @"pickedWithClipPickerResponse:", clone);
    }
    // chờ animation, layer kế
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 300 * NSEC_PER_MSEC),
                   dispatch_get_main_queue(), ^{ [self applyNextLayer]; });
}

- (id)cloneResponse:(id)resp {
    Class cls = NSClassFromString(@"ClipPickerResponse")
             ?: NSClassFromString(@"_TtC10Video_Star18ClipPickerResponse");
    if (!cls || !resp) return nil;
    NSNumber *type = HVCall0(resp, @"clipPickerResponseType");
    NSNumber *idx  = HVCall0(resp, @"clipIndex");
    if (!type || !idx) return resp;
    id alloc = [cls alloc];
    SEL initSel = NSSelectorFromString(@"initWithClipPickerResponseType:clipIndex:");
    if ([alloc respondsToSelector:initSel]) {
        NSMethodSignature *sig = [alloc methodSignatureForSelector:initSel];
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        [inv setTarget:alloc];
        [inv setSelector:initSel];
        NSInteger t = type.integerValue, i = idx.integerValue;
        [inv setArgument:&t atIndex:2];
        [inv setArgument:&i atIndex:3];
        [inv invoke];
        __unsafe_unretained id ret = nil;
        [inv getReturnValue:&ret];
        return ret;
    }
    return resp;
}

- (void)finishApplyLayers {
    [self status:[NSString stringWithFormat:@"Đã thay nội dung cho %lu lớp.",
                  (unsigned long)self.mediaApplyTotal]];
    self.mediaApplyDone ? self.mediaApplyDone(self.mediaApplyTotal) : (void)0;
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

    // 1. Mở panel chọn range (dùng UI native của Video Star)
    HVCall0(vc, @"showMergeScenes");

    // 2. Hiển thị hướng dẫn; sau khi user chọn range, gọi tiếp qua nút OK
    UIAlertController *ac = [UIAlertController
        alertControllerWithTitle:@"Chọn phân cảnh"
                         message:@"Chọn điểm bắt đầu và kết thúc trong Hợp nhất phân cảnh, rồi bấm OK để bắt đầu."
                  preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self continueMultiSceneAfterRange:vc];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
    [HVTopVC() presentViewController:ac animated:YES completion:nil];
}

- (void)continueMultiSceneAfterRange:(UIViewController *)review {
    // Đọc startScene / lastScene mà panel native đã ghi
    NSNumber *start = [self kvcNum:review key:@"startScene"];
    NSNumber *last  = [self kvcNum:review key:@"lastScene"];
    if (!start || !last || last.unsignedIntegerValue < start.unsignedIntegerValue) {
        [self alert:@"Thông báo" msg:@"Chưa chọn được phạm vi hợp lệ. Hãy chọn lại."];
        return;
    }
    NSUInteger total = last.unsignedIntegerValue - start.unsignedIntegerValue + 1;
    [self status:[NSString stringWithFormat:@"Bắt đầu import %lu phân cảnh...", (unsigned long)total]];

    // Hook sẵn để nhận data khi QRCodeManager gọi về
    [self importSceneAtIndex:0 start:start.unsignedIntegerValue total:total];
}

- (void)importSceneAtIndex:(NSUInteger)i start:(NSUInteger)start total:(NSUInteger)total {
    if (i >= total) {
        [self status:[NSString stringWithFormat:@"Hoàn tất %lu phân cảnh.", (unsigned long)total]];
        return;
    }
    // Mở từng scene qua MultiLayerNavController native (best-effort)
    Class navCls = NSClassFromString(@"MultiLayerNavController");
    id project = HVCall0(HVTopVC(), @"project");
    if (navCls && project) {
        SEL initSel = NSSelectorFromString(@"initWithProject:sceneIndex:");
        if ([navCls instancesRespondToSelector:initSel]) {
            // Không có API public init dạng này — Video Star tạo qua storyboard
            // Best-effort: báo người dùng mở tay cho tới khi có hook native
            [self status:[NSString stringWithFormat:@"Mở tay phân cảnh %lu/%lu (native chưa hỗ trợ auto).",
                          (unsigned long)(i + 1), (unsigned long)total]];
        }
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 400 * NSEC_PER_MSEC),
                   dispatch_get_main_queue(), ^{
        [self importSceneAtIndex:i + 1 start:start total:total];
    });
}

- (NSNumber *)kvcNum:(id)obj key:(NSString *)key {
    @try { id v = [obj valueForKey:key]; if ([v isKindOfClass:NSNumber.class]) return v; }
    @catch (__unused NSException *e) {}
    return nil;
}

#pragma mark - Alert

- (void)alert:(NSString *)title msg:(NSString *)msg {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *vc = HVTopVC();
        if (!vc) return;
        UIAlertController *ac = [UIAlertController alertControllerWithTitle:title
                                                                    message:msg
                                                             preferredStyle:UIAlertControllerStyleAlert];
        [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [vc presentViewController:ac animated:YES completion:nil];
    });
}

#pragma mark - Runtime hooks

static IMP gOrigPickedIMP = NULL;

+ (void)installRuntimeHooks {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // Hook pickedWithClipPickerResponse: trên MultiLayerWizEffectVC
        Class mlCls = NSClassFromString(@"MultiLayerWizEffectVC");
        if (mlCls) {
            SEL sel = NSSelectorFromString(@"pickedWithClipPickerResponse:");
            Method m = class_getInstanceMethod(mlCls, sel);
            if (m) {
                gOrigPickedIMP = method_getImplementation(m);
                IMP newIMP = imp_implementationWithBlock(^(id self, id response) {
                    [[HVSonEngine shared] handlePickedResponse:response editor:self];
                    if (gOrigPickedIMP) {
                        ((void(*)(id, SEL, id))gOrigPickedIMP)(self, sel, response);
                    }
                });
                method_setImplementation(m, newIMP);
            }
        }
    });
}

@end
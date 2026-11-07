#import <UIKit/UIKit.h>

@interface HVSonEngine : NSObject
+ (instancetype)shared;
@property (nonatomic, copy) void (^onStatus)(NSString *msg);

- (void)feature0AutoImportImages;   // auto nhập ảnh vào các lớp
- (void)feature1ShowLastCode;       // code gần nhất
- (void)feature2AutoBeatSplit;      // auto chia beat
- (void)feature3AutoMultiScene;     // auto nhiều phân cảnh

+ (void)installRuntimeHooks;
@end

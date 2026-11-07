#import <UIKit/UIKit.h>

@interface HVSonEngine : NSObject
+ (instancetype)shared;
@property (nonatomic, copy) void (^onStatus)(NSString *msg);

// 4 chức năng chính
- (void)feature0AutoImportImages;   // auto nhập ảnh vào các lớp
- (void)feature1ShowLastCode;       // code gần nhất
- (void)feature2AutoBeatSplit;      // auto chia beat
- (void)feature3AutoMultiScene;     // auto nhiều phân cảnh

// Hooks cần cài trước (gọi từ constructor)
+ (void)installRuntimeHooks;
@end
#import <UIKit/UIKit.h>

@interface HVSonMenuView : UIView
@property (nonatomic, copy) void (^onClose)(void);
@end

@interface HVSonToggleButton : UIButton
@end

@interface HVSonRootViewController : UIViewController
@property (nonatomic, strong) HVSonToggleButton *toggleButton;
@property (nonatomic, strong) HVSonMenuView      *menuView;
@end

@interface HVSonWindow : UIWindow
@end

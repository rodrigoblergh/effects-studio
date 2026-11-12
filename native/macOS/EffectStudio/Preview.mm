#import <AppKit/AppKit.h>
#include "SearchPanel.h"
@interface ESPreviewDelegate:NSObject<NSApplicationDelegate>
@end
@implementation ESPreviewDelegate
- (void)applicationDidFinishLaunching:(NSNotification*)notification {
 [NSApp activateIgnoringOtherApps:YES];
 effectstudio_mac::OpenSearch({{"ADBE Slider Control",L"Slider Control",L"Expression Controls",{L"Controle deslizante"}},{"ADBE Gaussian Blur 2",L"Gaussian Blur",L"Blur & Sharpen",{L"Desfoque gaussiano"}}},2,1);
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender{return YES;}
@end
int main(){@autoreleasepool{[NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];ESPreviewDelegate* delegate=[ESPreviewDelegate new];NSApp.delegate=delegate;[NSApp run];effectstudio_mac::Shutdown();}return 0;}

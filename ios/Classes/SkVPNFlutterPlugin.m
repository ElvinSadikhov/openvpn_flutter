#import "SkVPNFlutterPlugin.h"
#if __has_include(<skvpn_flutter/skvpn_flutter-Swift.h>)
#import <skvpn_flutter/skvpn_flutter-Swift.h>
#else
// Support project import fallback if the generated compatibility header
// is not copied when this plugin is created as a library.
// https://forums.swift.org/t/swift-static-libraries-dont-copy-generated-objective-c-header/19816
#import "skvpn_flutter-Swift.h"
#endif

@implementation SkVPNFlutterPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftSkVPNFlutterPlugin registerWithRegistrar:registrar];
}
@end

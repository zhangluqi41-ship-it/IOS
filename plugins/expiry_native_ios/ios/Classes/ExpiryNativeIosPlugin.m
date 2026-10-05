#import "ExpiryNativeIosPlugin.h"

#import "SFPrinterBridge.h"

static NSString *const kPrefsChannelName = @"com.xiaoqi.expiry_manager/prefs";
static NSString *const kSaveChannelName = @"com.xiaoqi.expiry_manager/save";

@implementation ExpiryNativeIosPlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  NSObject<FlutterBinaryMessenger> *messenger = [registrar messenger];

  // ---------------------------------------------------------------- 轻量设置
  FlutterMethodChannel *prefs =
      [FlutterMethodChannel methodChannelWithName:kPrefsChannelName binaryMessenger:messenger];
  [prefs setMethodCallHandler:^(FlutterMethodCall *call, FlutterResult result) {
    [ExpiryNativeIosPlugin handlePrefs:call result:result];
  }];

  // ------------------------------------------------------------ 保存 / 分享
  FlutterMethodChannel *save =
      [FlutterMethodChannel methodChannelWithName:kSaveChannelName binaryMessenger:messenger];
  [save setMethodCallHandler:^(FlutterMethodCall *call, FlutterResult result) {
    [ExpiryNativeIosPlugin handleSave:call result:result];
  }];

  // --------------------------------------------------------------- 蓝牙打印
  [SFPrinterBridge registerWithMessenger:messenger];
}

+ (void)releaseChannels {
  // 通道随注册器生命周期存在，无需手动释放
}

#pragma mark - prefs（对齐安卓侧 MainActivity 的 PREFS_CHANNEL）

+ (void)handlePrefs:(FlutterMethodCall *)call result:(FlutterResult)result {
  NSDictionary *args =
      [call.arguments isKindOfClass:[NSDictionary class]] ? call.arguments : @{};
  NSString *key = args[@"key"];
  if (![key isKindOfClass:[NSString class]] || key.length == 0) {
    result(nil);
    return;
  }

  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSString *method = call.method;

  if ([method isEqualToString:@"getString"]) {
    result([defaults stringForKey:key]);
    return;
  }
  if ([method isEqualToString:@"setString"]) {
    id value = args[@"value"];
    if ([value isKindOfClass:[NSString class]]) {
      [defaults setObject:value forKey:key];
    } else {
      [defaults removeObjectForKey:key];
    }
    result(@YES);
    return;
  }
  if ([method isEqualToString:@"getStringList"]) {
    NSArray *list = [defaults arrayForKey:key];
    result([list isKindOfClass:[NSArray class]] ? list : @[]);
    return;
  }
  if ([method isEqualToString:@"setStringList"]) {
    id value = args[@"value"];
    if ([value isKindOfClass:[NSArray class]]) {
      [defaults setObject:value forKey:key];
    } else {
      [defaults removeObjectForKey:key];
    }
    result(@YES);
    return;
  }
  if ([method isEqualToString:@"remove"]) {
    [defaults removeObjectForKey:key];
    result(@YES);
    return;
  }

  result(FlutterMethodNotImplemented);
}

#pragma mark - save（对齐安卓侧 MainActivity 的 CHANNEL）

+ (void)handleSave:(FlutterMethodCall *)call result:(FlutterResult)result {
  if (![call.method isEqualToString:@"saveToDownloads"]) {
    result(FlutterMethodNotImplemented);
    return;
  }

  NSDictionary *args =
      [call.arguments isKindOfClass:[NSDictionary class]] ? call.arguments : @{};

  NSString *name = args[@"name"];
  if (![name isKindOfClass:[NSString class]] || name.length == 0) {
    name = @"label.pdf";
  }

  NSData *bytes = nil;
  id raw = args[@"bytes"];
  if ([raw isKindOfClass:[FlutterStandardTypedData class]]) {
    bytes = ((FlutterStandardTypedData *)raw).data;
  } else if ([raw isKindOfClass:[NSData class]]) {
    bytes = raw;
  }
  if (bytes.length == 0) {
    result([FlutterError errorWithCode:@"NO_BYTES"
                               message:@"bytes argument is missing"
                               details:nil]);
    return;
  }

  // iOS 没有公共「下载目录」：写进 App 自己的 Documents，
  // 配合 Info.plist 里的 UIFileSharingEnabled / LSSupportsOpeningDocumentsInPlace，
  // 文件就会出现在「文件」App → 我的 iPhone → 效期管理程序。
  NSFileManager *fileManager = [NSFileManager defaultManager];
  NSError *dirError = nil;
  NSURL *documents = [fileManager URLForDirectory:NSDocumentDirectory
                                         inDomain:NSUserDomainMask
                                appropriateForURL:nil
                                           create:YES
                                            error:&dirError];
  if (documents == nil) {
    result([FlutterError errorWithCode:@"SAVE_FAILED"
                               message:dirError.localizedDescription ?: @"无法访问文稿目录"
                               details:nil]);
    return;
  }

  NSURL *fileURL = [documents URLByAppendingPathComponent:name];
  NSError *writeError = nil;
  if (![bytes writeToURL:fileURL options:NSDataWritingAtomic error:&writeError]) {
    result([FlutterError errorWithCode:@"SAVE_FAILED"
                               message:writeError.localizedDescription ?: @"写入失败"
                               details:nil]);
    return;
  }

  result([NSString stringWithFormat:@"「文件」App → 我的 iPhone → 效期管理程序 / %@", name]);
}

@end

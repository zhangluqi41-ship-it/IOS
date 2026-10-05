#import "SFPrinterBridge.h"

#import <CoreBluetooth/CoreBluetooth.h>
#import <CoreGraphics/CoreGraphics.h>
#import <UIKit/UIKit.h>

// 只导入实际存在的头文件 —— 官方 umbrella 头 SFPrintSDKHeaders.h 引用了
// 几个包里并没有的私有头（DrawUtils.h / PrintPageModel.h 等），不要用。
#import <SFPrintSDK/SFPrintSDKUtils.h>
#import <SFPrintSDK/SFPrintSetModel.h>
#import <SFPrintSDK/SFPrintDrawobjectModel.h>

#pragma mark - 常量

static NSString *const kChannelName = @"com.xiaoqi.expiry_manager/printer";

/// 硕方 SDK 纸张类型：iOS 侧是 1 间隙纸 / 4 黑标纸 / 5 黑标卡尺
/// （安卓侧是 1 / 2 / 5，所以这里要映射一次）
static int SFMaterialTypeFromPaperType(int paperType) {
  switch (paperType) {
    case 2:
      return 4;
    case 5:
      return 5;
    default:
      return 1;
  }
}

/// 打印头分辨率：203dpi = 8 dots/mm，与安卓侧 RasterUtil.DOTS_PER_MM 一致
static const int kDotsPerMM = 8;

/// 二值化阈值，与安卓侧 RasterUtil.THRESHOLD 一致
static const int kMonoThreshold = 150;

static NSString *const kKindSupvan = @"supvan_t50pro";
static NSString *const kKindGenericTspl = @"generic_tspl";
static NSString *const kKindGenericEscpos = @"generic_escpos";

static NSString *const kSavedKey = @"saved_printers";

/// 已添加的打印机存这儿（与安卓侧的 SharedPreferences 名同名）
static NSUserDefaults *SFPrinterDefaults(void) {
  static NSUserDefaults *defaults = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    defaults = [[NSUserDefaults alloc] initWithSuiteName:@"expiry_printer"];
    if (defaults == nil) {
      defaults = [NSUserDefaults standardUserDefaults];
    }
  });
  return defaults;
}

static BOOL SFKindIsGeneric(NSString *kind) {
  return [kind isEqualToString:kKindGenericTspl] || [kind isEqualToString:kKindGenericEscpos];
}

static NSString *SFKindLabel(NSString *kind) {
  if ([kind isEqualToString:kKindGenericTspl]) return @"通用标签机";
  if ([kind isEqualToString:kKindGenericEscpos]) return @"通用热敏机";
  return @"硕方 T50 Pro";
}

static void SFOnMain(dispatch_block_t block) {
  if (block == nil) return;
  if ([NSThread isMainThread]) {
    block();
  } else {
    dispatch_async(dispatch_get_main_queue(), block);
  }
}

#pragma mark - 位图工具

/// 把 8bit 灰度缓冲按阈值压成纯黑白（0 / 255）。
static void SFThresholdGrayBuffer(uint8_t *buffer, size_t count) {
  if (buffer == NULL) return;
  for (size_t i = 0; i < count; i++) {
    buffer[i] = (buffer[i] < kMonoThreshold) ? 0 : 255;
  }
}

/// 把任意 UIImage 二值化（测试页用，抹掉抗锯齿产生的灰边）。
static UIImage *SFThresholdImage(UIImage *source) {
  CGImageRef cg = source.CGImage;
  if (cg == NULL) return source;
  size_t w = CGImageGetWidth(cg);
  size_t h = CGImageGetHeight(cg);
  if (w == 0 || h == 0) return source;

  CGColorSpaceRef gray = CGColorSpaceCreateDeviceGray();
  CGContextRef ctx = CGBitmapContextCreate(NULL, w, h, 8, w, gray, kCGImageAlphaNone);
  if (ctx == NULL) {
    CGColorSpaceRelease(gray);
    return source;
  }
  CGContextSetShouldAntialias(ctx, false);
  CGContextDrawImage(ctx, CGRectMake(0, 0, (CGFloat)w, (CGFloat)h), cg);
  SFThresholdGrayBuffer((uint8_t *)CGBitmapContextGetData(ctx), w * h);

  CGImageRef out = CGBitmapContextCreateImage(ctx);
  UIImage *result = out ? [UIImage imageWithCGImage:out] : source;
  if (out) CGImageRelease(out);
  CGContextRelease(ctx);
  CGColorSpaceRelease(gray);
  return result;
}

/// 标签 PDF 首页 → 打印头点阵尺寸的黑白 UIImage。
///
/// 与安卓侧 `RasterUtil.renderPdf + toMono` 等价：先按
/// `widthDots × heightDots` 栅格化，再按同一个阈值二值化。
static UIImage *SFRenderLabelPDF(NSData *pdf, int widthDots, int heightDots) {
  if (pdf.length == 0 || widthDots <= 0 || heightDots <= 0) return nil;

  CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)pdf);
  if (provider == NULL) return nil;
  CGPDFDocumentRef document = CGPDFDocumentCreateWithProvider(provider);
  CGDataProviderRelease(provider);
  if (document == NULL) return nil;

  CGPDFPageRef page = CGPDFDocumentGetPage(document, 1);
  if (page == NULL) {
    CGPDFDocumentRelease(document);
    return nil;
  }
  CGRect box = CGPDFPageGetBoxRect(page, kCGPDFMediaBox);
  if (box.size.width <= 0 || box.size.height <= 0) {
    CGPDFDocumentRelease(document);
    return nil;
  }

  size_t w = (size_t)widthDots;
  size_t h = (size_t)heightDots;
  CGColorSpaceRef gray = CGColorSpaceCreateDeviceGray();
  CGContextRef ctx = CGBitmapContextCreate(NULL, w, h, 8, w, gray, kCGImageAlphaNone);
  if (ctx == NULL) {
    CGColorSpaceRelease(gray);
    CGPDFDocumentRelease(document);
    return nil;
  }

  CGContextSetInterpolationQuality(ctx, kCGInterpolationHigh);
  CGContextSetGrayFillColor(ctx, 1.0, 1.0);
  CGContextFillRect(ctx, CGRectMake(0, 0, (CGFloat)w, (CGFloat)h));
  CGContextScaleCTM(ctx, (CGFloat)w / box.size.width, (CGFloat)h / box.size.height);
  CGContextTranslateCTM(ctx, -box.origin.x, -box.origin.y);
  CGContextDrawPDFPage(ctx, page);

  SFThresholdGrayBuffer((uint8_t *)CGBitmapContextGetData(ctx), w * h);

  CGImageRef image = CGBitmapContextCreateImage(ctx);
  UIImage *result = image ? [UIImage imageWithCGImage:image] : nil;
  if (image) CGImageRelease(image);
  CGContextRelease(ctx);
  CGColorSpaceRelease(gray);
  CGPDFDocumentRelease(document);
  return result;
}

/// 标尺测试页：确认走纸、边距、左右印位用。
static UIImage *SFBuildTestPage(int widthMm,
                                int heightMm,
                                NSString *kindLabel,
                                int density,
                                int gap,
                                int copies) {
  CGFloat w = (CGFloat)widthMm * kDotsPerMM;
  CGFloat h = (CGFloat)heightMm * kDotsPerMM;
  if (w <= 0 || h <= 0) return nil;

  UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
  format.scale = 1.0;
  format.opaque = YES;
  UIGraphicsImageRenderer *renderer =
      [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(w, h) format:format];

  UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *rendererContext) {
    CGContextRef c = rendererContext.CGContext;
    CGContextSetFillColorWithColor(c, UIColor.whiteColor.CGColor);
    CGContextFillRect(c, CGRectMake(0, 0, w, h));
    CGContextSetStrokeColorWithColor(c, UIColor.blackColor.CGColor);
    CGContextSetFillColorWithColor(c, UIColor.blackColor.CGColor);

    NSMutableParagraphStyle *center = [[NSMutableParagraphStyle alloc] init];
    center.alignment = NSTextAlignmentCenter;

    NSDictionary *titleAttrs = @{
      NSFontAttributeName : [UIFont boldSystemFontOfSize:17],
      NSForegroundColorAttributeName : UIColor.blackColor,
      NSParagraphStyleAttributeName : center,
    };
    NSDictionary *smallAttrs = @{
      NSFontAttributeName : [UIFont systemFontOfSize:9],
      NSForegroundColorAttributeName : UIColor.blackColor,
      NSParagraphStyleAttributeName : center,
    };

    [kindLabel drawInRect:CGRectMake(0, 6, w, 22) withAttributes:titleAttrs];
    [@"标尺测试页 · 确认走纸与边距" drawInRect:CGRectMake(0, 28, w, 13) withAttributes:smallAttrs];

    // 上下左右边框：确认左右印位 / 上下印位
    CGContextSetLineWidth(c, 1.0);
    CGContextStrokeRect(c, CGRectInset(CGRectMake(0, 0, w, h), 2, 2));

    // 标尺
    CGFloat rulerY = 52;
    for (int mm = 0; mm <= widthMm; mm++) {
      CGFloat x = mm * kDotsPerMM;
      CGFloat length = (mm % 10 == 0) ? 22 : ((mm % 5 == 0) ? 15 : 8);
      CGContextMoveToPoint(c, x, rulerY);
      CGContextAddLineToPoint(c, x, rulerY + length);
      CGContextStrokePath(c);
      if (mm % 10 == 0) {
        NSString *text = [NSString stringWithFormat:@"%d", mm];
        NSDictionary *tickAttrs = @{
          NSFontAttributeName : [UIFont systemFontOfSize:8],
          NSForegroundColorAttributeName : UIColor.blackColor,
        };
        [text drawInRect:CGRectMake(x - 10, rulerY + 24, 20, 11) withAttributes:tickAttrs];
      }
    }

    // 中间大字号尺寸
    NSDictionary *bigAttrs = @{
      NSFontAttributeName : [UIFont boldSystemFontOfSize:34],
      NSForegroundColorAttributeName : UIColor.blackColor,
      NSParagraphStyleAttributeName : center,
    };
    NSString *sizeText = [NSString stringWithFormat:@"%d x %d", widthMm, heightMm];
    [sizeText drawInRect:CGRectMake(0, h * 0.40, w, 40) withAttributes:bigAttrs];

    // 浓度色块：从浅到深，用来判断浓度是否合适
    CGFloat blockW = 22;
    CGFloat blockH = 16;
    CGFloat blockY = h - 118;
    for (int i = 0; i < 5; i++) {
      CGFloat level = 0.15 + i * 0.2; // 0.15 ~ 0.95
      CGContextSetGrayFillColor(c, level, 1.0);
      CGContextFillRect(c, CGRectMake(12 + i * (blockW + 6), blockY, blockW, blockH));
      CGContextSetGrayFillColor(c, 0.0, 1.0);
    }
    [@"浓度色块 →" drawInRect:CGRectMake(0, blockY - 14, w, 12) withAttributes:smallAttrs];

    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyy/MM/dd HH:mm:ss";
    NSString *stamp = [formatter stringFromDate:[NSDate date]];
    NSString *info = [NSString stringWithFormat:@"浓度 %d · 间隙 %dmm · 份数 %d", density, gap, copies];
    [info drawInRect:CGRectMake(0, h - 66, w, 12) withAttributes:smallAttrs];
    [stamp drawInRect:CGRectMake(0, h - 50, w, 12) withAttributes:smallAttrs];
  }];

  return SFThresholdImage(image);
}

#pragma mark - 桥

@interface SFPrinterBridge () <CBCentralManagerDelegate> {
  /// 自己建一个 CBCentralManager，只用来回答「有没有蓝牙 / 开没开 / 有没有授权」。
  /// 扫描和连接都由硕方 SDK 内部负责。
  CBCentralManager *_centralManager;
}

@property (nonatomic, strong) FlutterMethodChannel *channel;
@property (nonatomic, strong) NSMutableDictionary<NSString *, CBPeripheral *> *found;
@property (nonatomic, strong) NSMutableArray<CBPeripheral *> *foundOrder;
@property (nonatomic, strong) CBPeripheral *target;
@property (nonatomic, assign) BOOL scanning;
@property (nonatomic, strong) NSTimer *connectTimer;
@property (nonatomic, strong) NSTimer *scanStopTimer;

@end

@implementation SFPrinterBridge

+ (void)registerWithMessenger:(NSObject<FlutterBinaryMessenger> *)messenger {
  static SFPrinterBridge *bridge = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    bridge = [[SFPrinterBridge alloc] init];
    [bridge attachMessenger:messenger];
  });
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _found = [NSMutableDictionary dictionary];
    _foundOrder = [NSMutableArray array];
  }
  return self;
}

- (void)attachMessenger:(NSObject<FlutterBinaryMessenger> *)messenger {
  self.channel = [FlutterMethodChannel methodChannelWithName:kChannelName binaryMessenger:messenger];

  __weak typeof(self) weakSelf = self;
  [self.channel setMethodCallHandler:^(FlutterMethodCall *call, FlutterResult result) {
    [weakSelf handleCall:call result:result];
  }];

  [self setupSDKCallbacks];
}

- (void)setupSDKCallbacks {
  __weak typeof(self) weakSelf = self;
  SFPrintSDKUtils *sdk = [SFPrintSDKUtils shareInstance];

  sdk.findDeviceBlock = ^(CBPeripheral *peripheral) {
    [weakSelf handleFoundPeripheral:peripheral];
  };
  sdk.connectSuccessBlock = ^(CBPeripheral *peripheral) {
    [weakSelf finishConnectWithPeripheral:peripheral ok:YES];
  };
  sdk.connectFailBlock = ^{
    [weakSelf finishConnectWithPeripheral:weakSelf.target ok:NO];
  };
  sdk.disconnectBlock = ^{
    [weakSelf handleDisconnected];
  };
}

#pragma mark - 事件与工具

- (void)emit:(NSString *)type value:(id)value {
  NSDictionary *payload = @{
    @"type" : type,
    @"value" : value ?: [NSNull null],
  };
  SFOnMain(^{
    [self.channel invokeMethod:@"onEvent" arguments:payload];
  });
}

- (CBPeripheral *)peripheralForAddress:(NSString *)address {
  if (address.length == 0) return nil;
  return self.found[address];
}

- (NSString *)displayNameFor:(CBPeripheral *)peripheral {
  NSString *name = peripheral.name;
  if (name.length == 0) {
    NSString *friendly =
        [[SFPrintSDKUtils shareInstance] getDeviceNameWithperipheralName:peripheral.name];
    name = (friendly.length > 0) ? friendly : @"未知设备";
  }
  return name;
}

- (NSDictionary *)deviceInfoFor:(CBPeripheral *)peripheral {
  return @{
    @"name" : [self displayNameFor:peripheral],
    @"address" : peripheral.identifier.UUIDString ?: @"",
    @"bonded" : @(peripheral.state == CBPeripheralStateConnected),
  };
}

/// 已连接 / 已配对的排前面
- (NSArray<NSDictionary *> *)snapshot {
  NSMutableArray<NSDictionary *> *list = [NSMutableArray array];
  for (CBPeripheral *peripheral in self.foundOrder) {
    [list addObject:[self deviceInfoFor:peripheral]];
  }
  [list sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
    BOOL left = [a[@"bonded"] boolValue];
    BOOL right = [b[@"bonded"] boolValue];
    if (left == right) return NSOrderedSame;
    return left ? NSOrderedAscending : NSOrderedDescending;
  }];
  return list;
}

- (void)clearFound {
  [self.found removeAllObjects];
  [self.foundOrder removeAllObjects];
}

#pragma mark - 蓝牙开关 / 权限

- (CBCentralManager *)central {
  if (_centralManager == nil) {
    // 用主队列即可：SDK 自己的扫描与连接都在主线程派发
    _centralManager =
        [[CBCentralManager alloc] initWithDelegate:self queue:dispatch_get_main_queue()];
  }
  return _centralManager;
}

- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
  // 只用来回答 isSupported / isEnabled，不做额外处理
}

#pragma mark - 扫描

- (void)startScanInternal {
  self.scanning = YES;
  [self clearFound];
  [[SFPrintSDKUtils shareInstance] startScan];
}

- (void)stopScanInternal:(BOOL)notify {
  self.scanning = NO;
  [self.scanStopTimer invalidate];
  self.scanStopTimer = nil;
  [[SFPrintSDKUtils shareInstance] stopScan];
  if (notify) {
    [self emit:@"scanFinished" value:nil];
  }
}

- (void)handleFoundPeripheral:(CBPeripheral *)peripheral {
  if (peripheral == nil) return;
  NSString *uuid = peripheral.identifier.UUIDString;
  if (uuid.length == 0) return;

  if (self.found[uuid] == nil) {
    self.found[uuid] = peripheral;
    [self.foundOrder addObject:peripheral];
  }
  if (!self.scanning) return;

  NSDictionary *info = [self deviceInfoFor:peripheral];
  SFOnMain(^{
    [self.channel invokeMethod:@"onEvent" arguments:@{ @"type" : @"deviceFound", @"value" : info }];
  });
}

#pragma mark - 连接

- (void)finishConnectWithPeripheral:(CBPeripheral *)peripheral ok:(BOOL)ok {
  [self.connectTimer invalidate];
  self.connectTimer = nil;

  NSString *address = peripheral.identifier.UUIDString ?: @"";
  NSString *name = peripheral ? [self displayNameFor:peripheral] : SFKindLabel(kKindSupvan);
  if (!ok) {
    self.target = nil;
  }

  NSDictionary *value = @{
    @"ok" : @(ok),
    @"address" : ok ? address : @"",
    @"name" : name,
    @"kind" : kKindSupvan,
  };
  [self emit:@"connected" value:value];
}

- (void)handleDisconnected {
  NSString *address = self.target.identifier.UUIDString ?: @"";
  self.target = nil;
  [self emit:@"disconnected" value:@{ @"ok" : @NO, @"address" : address }];
}

- (void)connectPeripheral:(CBPeripheral *)peripheral {
  self.target = peripheral;
  [self.connectTimer invalidate];

  __weak typeof(self) weakSelf = self;
  self.connectTimer = [NSTimer scheduledTimerWithTimeInterval:15.0
                                                     repeats:NO
                                                       block:^(NSTimer *timer) {
                                                         [weakSelf finishConnectWithPeripheral:weakSelf.target
                                                                                            ok:NO];
                                                       }];
  [[SFPrintSDKUtils shareInstance] connectedBlueteeth:peripheral];
}

/// 目标设备还没扫到（例如从「已添加」进来）：先扫一轮再连。
- (void)scanUntilFound:(NSString *)address completion:(void (^)(CBPeripheral *))completion {
  [self startScanInternal];

  __block NSInteger ticks = 0;
  __weak typeof(self) weakSelf = self;
  NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                   repeats:YES
                                                     block:^(NSTimer *inner) {
                                                       ticks += 1;
                                                       CBPeripheral *found =
                                                           [weakSelf peripheralForAddress:address];
                                                       if (found != nil) {
                                                         [inner invalidate];
                                                         [weakSelf stopScanInternal:NO];
                                                         completion(found);
                                                         return;
                                                       }
                                                       if (ticks >= 8) {
                                                         [inner invalidate];
                                                         [weakSelf stopScanInternal:NO];
                                                         completion(nil);
                                                       }
                                                     }];
  [timer fire];
}

#pragma mark - 已添加的打印机

- (NSArray<NSDictionary *> *)savedList {
  NSString *raw = [SFPrinterDefaults() stringForKey:kSavedKey];
  if (raw.length == 0) return @[];

  NSData *data = [raw dataUsingEncoding:NSUTF8StringEncoding];
  id parsed = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
  if (![parsed isKindOfClass:[NSArray class]]) return @[];

  NSMutableArray<NSDictionary *> *list = [NSMutableArray array];
  for (id item in (NSArray *)parsed) {
    if (![item isKindOfClass:[NSDictionary class]]) continue;
    NSString *address = item[@"address"];
    if (![address isKindOfClass:[NSString class]] || address.length == 0) continue;
    NSString *name = item[@"name"];
    NSString *kind = item[@"kind"];
    [list addObject:@{
      @"name" : ([name isKindOfClass:[NSString class]] && name.length > 0) ? name : @"打印机",
      @"address" : address,
      @"kind" : ([kind isKindOfClass:[NSString class]] && kind.length > 0) ? kind : kKindSupvan,
    }];
  }
  return list;
}

- (void)writeSaved:(NSArray<NSDictionary *> *)items target:(NSString *)target {
  NSData *data = [NSJSONSerialization dataWithJSONObject:items options:0 error:NULL];
  NSString *json = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"[]";
  [SFPrinterDefaults() setObject:json ?: @"[]" forKey:kSavedKey];
  [self emit:@"savedChanged" value:target ?: @""];
}

- (void)savePrinterName:(NSString *)name address:(NSString *)address kind:(NSString *)kind {
  NSString *trimmed = [address stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if (trimmed.length == 0) return;

  NSString *safeName = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if (safeName.length == 0) safeName = SFKindLabel(kind);

  NSMutableArray<NSDictionary *> *list = [NSMutableArray array];
  [list addObject:@{ @"name" : safeName, @"address" : trimmed, @"kind" : kind ?: kKindSupvan }];
  for (NSDictionary *item in [self savedList]) {
    if (![item[@"address"] isEqual:trimmed]) [list addObject:item];
  }
  [self writeSaved:list target:trimmed];
}

#pragma mark - 打印

- (void)printImage:(UIImage *)image
           widthMm:(int)widthMm
          heightMm:(int)heightMm
            copies:(int)copies
           density:(int)density
        paperType:(int)paperType
               gap:(int)gap
             label:(NSString *)label {
  if (image == nil) {
    [self emit:@"printDone" value:@{ @"ok" : @NO, @"kind" : kKindSupvan }];
    return;
  }
  BOOL connected = [[SFPrintSDKUtils shareInstance] getDeviceStatus];
  if (!connected) {
    [self emit:@"printDone" value:@{ @"ok" : @NO, @"kind" : kKindSupvan }];
    return;
  }

  SFPrintSetModel *model = [[SFPrintSetModel alloc] init];
  model.isAuto = YES;
  model.width = widthMm;
  model.length = heightMm;
  model.materialType = SFMaterialTypeFromPaperType(paperType);
  // 浓度：1~9；给 0 或负数时让 SDK 自己判断
  model.deepness = (density >= 1 && density <= 9) ? density : -1;
  model.copy = (copies >= 1) ? copies : 1;
  model.cutdeep = 0;
  model.oneByone = 1;
  model.left = 0;
  model.top = 0;
  model.ratio = 1;

  SFPrintDrawobjectModel *draw = [[SFPrintDrawobjectModel alloc] init];
  draw.textColor = @0;
  draw.x = 0;
  draw.y = 0;
  draw.width = widthMm;
  draw.height = heightMm;
  draw.localImage = image;
  draw.format = @"Image";
  draw.verAlignmentType = 0;
  draw.autoReturn = YES;
  draw.ratio = 1;
  model.printImgModels = @[ draw ];

  __weak typeof(self) weakSelf = self;
  [[SFPrintSDKUtils shareInstance]
      doPrintWithPrintModel:model
                   complete:^(BOOL isSuccess, NSString *error, int printNum, int allLength) {
                     NSLog(@"[SFPrinterBridge] %@ print done ok=%d err=%@ %d/%d",
                           label,
                           isSuccess,
                           error,
                           printNum,
                           allLength);
                     [weakSelf emit:@"printDone"
                              value:@{ @"ok" : @(isSuccess), @"kind" : kKindSupvan }];
                   }];
}

#pragma mark - 通道分发

- (void)handleCall:(FlutterMethodCall *)call result:(FlutterResult)result {
  NSString *method = call.method;
  NSDictionary *args = [call.arguments isKindOfClass:[NSDictionary class]] ? call.arguments : @{};

  if ([method isEqualToString:@"isSupported"]) {
    result(@(self.central.state != CBManagerStateUnsupported));
    return;
  }
  if ([method isEqualToString:@"isEnabled"]) {
    result(@(self.central.state == CBManagerStatePoweredOn));
    return;
  }
  if ([method isEqualToString:@"hasPermission"]) {
    // authorization 是 CBManager 的**类属性**，必须用类去取，不能走实例
    CBManagerAuthorization auth = CBCentralManager.authorization;
    result(@(auth == CBManagerAuthorizationAllowedAlways ||
             auth == CBManagerAuthorizationNotDetermined));
    return;
  }
  if ([method isEqualToString:@"requestPermission"]) {
    // iOS 没有显式申请接口：一碰 CBCentralManager 系统就会弹授权框
    (void)self.central;
    CBManagerAuthorization auth = CBCentralManager.authorization;
    result(@(auth != CBManagerAuthorizationDenied && auth != CBManagerAuthorizationRestricted));
    return;
  }
  if ([method isEqualToString:@"openBluetoothSettings"]) {
    NSURL *url = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
    SFOnMain(^{
      if (url != nil) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
      }
    });
    result(@YES);
    return;
  }
  if ([method isEqualToString:@"listDevices"]) {
    if (self.scanning) {
      result([self snapshot]);
      return;
    }
    // 页面加载时的一次性短扫描
    [self startScanInternal];
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
                     [weakSelf stopScanInternal:NO];
                     result([weakSelf snapshot]);
                   });
    return;
  }
  if ([method isEqualToString:@"startScan"]) {
    if (self.scanning) {
      result(@YES);
      return;
    }
    [self startScanInternal];
    // 32 秒兜底收尾（Dart 侧自己也有 30 秒的定时器）
    __weak typeof(self) weakSelf = self;
    self.scanStopTimer = [NSTimer scheduledTimerWithTimeInterval:32.0
                                                        repeats:NO
                                                          block:^(NSTimer *timer) {
                                                            [weakSelf stopScanInternal:YES];
                                                          }];
    result(@YES);
    return;
  }
  if ([method isEqualToString:@"stopScan"]) {
    [self stopScanInternal:NO];
    result(@YES);
    return;
  }
  if ([method isEqualToString:@"connect"]) {
    NSString *address = args[@"address"];
    if (![address isKindOfClass:[NSString class]] || address.length == 0) {
      result(@NO);
      return;
    }
    CBPeripheral *known = [self peripheralForAddress:address];
    if (known != nil) {
      [self connectPeripheral:known];
      result(@YES);
      return;
    }
    __weak typeof(self) weakSelf = self;
    [self scanUntilFound:address
              completion:^(CBPeripheral *found) {
                if (found == nil) {
                  [weakSelf finishConnectWithPeripheral:nil ok:NO];
                  return;
                }
                [weakSelf connectPeripheral:found];
              }];
    result(@YES);
    return;
  }
  if ([method isEqualToString:@"disconnect"]) {
    CBPeripheral *target = self.target;
    if (target != nil) {
      [[SFPrintSDKUtils shareInstance] disConnectedBlueteeth:target];
    }
    self.target = nil;
    result(@YES);
    return;
  }
  if ([method isEqualToString:@"status"]) {
    // SDK 只给「已连接 / 未连接」，没有状态码
    BOOL connected = [[SFPrintSDKUtils shareInstance] getDeviceStatus];
    result(@(connected ? 0 : -1));
    return;
  }
  if ([method isEqualToString:@"printLabel"]) {
    NSData *pdf = nil;
    id raw = args[@"pdf"];
    if ([raw isKindOfClass:[FlutterStandardTypedData class]]) {
      pdf = ((FlutterStandardTypedData *)raw).data;
    } else if ([raw isKindOfClass:[NSData class]]) {
      pdf = raw;
    }
    if (pdf.length == 0) {
      result(@NO);
      return;
    }

    NSString *kind = args[@"kind"] ?: kKindSupvan;
    if (SFKindIsGeneric(kind)) {
      // iOS 不给经典蓝牙 SPP，通用机型走不了
      [self emit:@"printDone" value:@{ @"ok" : @NO, @"kind" : kind }];
      result(@NO);
      return;
    }

    int widthMm = [args[@"widthMm"] intValue];
    int heightMm = [args[@"heightMm"] intValue];
    if (widthMm <= 0) widthMm = 50;
    if (heightMm <= 0) heightMm = 30;
    int copies = [args[@"copies"] intValue];
    int density = [args[@"density"] intValue];
    int paperType = [args[@"paperType"] intValue];
    int gap = [args[@"gap"] intValue];

    UIImage *image = SFRenderLabelPDF(pdf, widthMm * kDotsPerMM, heightMm * kDotsPerMM);
    [self printImage:image
             widthMm:widthMm
            heightMm:heightMm
              copies:copies
             density:density
           paperType:paperType
                 gap:gap
               label:@"printLabel"];
    result(@YES);
    return;
  }
  if ([method isEqualToString:@"printTest"]) {
    NSString *kind = args[@"kind"] ?: kKindSupvan;
    int widthMm = [args[@"width"] intValue];
    int heightMm = [args[@"height"] intValue];
    if (widthMm <= 0) widthMm = 50;
    if (heightMm <= 0) heightMm = 30;
    int copies = [args[@"copies"] intValue];
    if (copies <= 0) copies = 1;
    int density = [args[@"density"] intValue];
    int gap = [args[@"gap"] intValue];

    UIImage *image =
        SFBuildTestPage(widthMm, heightMm, SFKindLabel(kind), density, gap, copies);
    [self printImage:image
             widthMm:widthMm
            heightMm:heightMm
              copies:copies
             density:density
           paperType:1
                 gap:gap
               label:@"printTest"];
    result(@YES);
    return;
  }
  if ([method isEqualToString:@"listSavedPrinters"]) {
    result([self savedList]);
    return;
  }
  if ([method isEqualToString:@"savePrinter"]) {
    NSString *address = args[@"address"];
    if (![address isKindOfClass:[NSString class]] || address.length == 0) {
      result(@NO);
      return;
    }
    [self savePrinterName:args[@"name"] address:address kind:args[@"kind"] ?: kKindSupvan];
    result(@YES);
    return;
  }
  if ([method isEqualToString:@"renamePrinter"]) {
    NSString *address = args[@"address"];
    NSString *name = args[@"name"];
    if (![address isKindOfClass:[NSString class]] || address.length == 0 ||
        ![name isKindOfClass:[NSString class]] || name.length == 0) {
      result(@NO);
      return;
    }
    NSMutableArray<NSDictionary *> *list = [NSMutableArray array];
    for (NSDictionary *item in [self savedList]) {
      if ([item[@"address"] isEqual:address]) {
        [list addObject:@{ @"name" : name, @"address" : address, @"kind" : item[@"kind"] }];
      } else {
        [list addObject:item];
      }
    }
    [self writeSaved:list target:address];
    result(@YES);
    return;
  }
  if ([method isEqualToString:@"removePrinter"]) {
    NSString *address = args[@"address"];
    if (![address isKindOfClass:[NSString class]] || address.length == 0) {
      result(@NO);
      return;
    }
    NSMutableArray<NSDictionary *> *list = [NSMutableArray array];
    for (NSDictionary *item in [self savedList]) {
      if (![item[@"address"] isEqual:address]) [list addObject:item];
    }
    [self writeSaved:list target:address];
    result(@YES);
    return;
  }

  result(FlutterMethodNotImplemented);
}

@end

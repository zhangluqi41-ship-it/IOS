//
//  ExpiryPrinterSDK.m
//  硕方蓝牙标签机封装实现。
//
//  逻辑移植自 Flutter 版 `plugins/expiry_native_ios/ios/Classes/SFPrinterBridge.m`
//  （那份代码已在真机 T50 Pro 上验证可正常打印），去掉了 Flutter 通道部分，
//  改成 delegate 回调给 SwiftUI。
//

#import "ExpiryPrinterSDK.h"
#import "PrinterLog.h"

// 诊断日志：既进系统日志，也落沙盒文件（真机上没有 Mac，只能事后拉文件看）。
// 用宏包一层是为了让调用点保持 NSLog 的写法，参数直接透传。
#define SFPLog(fmt, ...) SFPrinterLog([NSString stringWithFormat:(fmt), ##__VA_ARGS__])

#import <CoreBluetooth/CoreBluetooth.h>
#import <CoreGraphics/CoreGraphics.h>
#import <UIKit/UIKit.h>

// ⚠️ 只导入真实存在的头 —— 官方 umbrella 头 SFPrintSDKHeaders.h 引用了
//    包里并不存在的 DrawUtils.h / PrintPageModel.h，不能用。
#import <SFPrintSDK/SFPrintSDKUtils.h>
#import <SFPrintSDK/SFPrintSetModel.h>
#import <SFPrintSDK/SFPrintDrawobjectModel.h>

#pragma mark - 常量

/// 打印头分辨率：203dpi = 8 dots/mm（与安卓侧 RasterUtil.DOTS_PER_MM 一致）
static const int kDotsPerMM = 8;

/// 二值化阈值（与安卓侧 RasterUtil.THRESHOLD 一致）
static const int kMonoThreshold = 150;

/// 扫描自动收尾时长（秒）
static const NSTimeInterval kAutoStopScanSeconds = 30.0;

/// 连接超时（秒）
static const NSTimeInterval kConnectTimeoutSeconds = 15.0;

/// 找设备时的最长等待（秒），1 秒一次
static const NSInteger kScanUntilFoundTicks = 8;

/// 安卓侧纸张枚举（1 间隙 / 2 普通黑标 / 5 黑标卡纸）
/// → 硕方 iOS 侧纸张类型（1 间隙 / 4 黑标 / 5 黑标卡尺）
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

/// 把任意 UIImage 二值化（抹掉抗锯齿产生的灰边）。
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
/// 与安卓侧 `RasterUtil.renderPdf + toMono` 等价。
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

/// 标尺测试页：确认走纸、边距、左右印位、浓度用。
static UIImage *SFBuildTestPage(int widthMm,
                                int heightMm,
                                int density,
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

    [@"硕方 T50 Pro" drawInRect:CGRectMake(0, 6, w, 22) withAttributes:titleAttrs];
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

    // 浓度色块
    CGFloat blockW = 22;
    CGFloat blockH = 16;
    CGFloat blockY = h - 118;
    for (int i = 0; i < 5; i++) {
      CGFloat level = 0.15 + i * 0.2;
      CGContextSetGrayFillColor(c, level, 1.0);
      CGContextFillRect(c, CGRectMake(12 + i * (blockW + 6), blockY, blockW, blockH));
      CGContextSetGrayFillColor(c, 0.0, 1.0);
    }
    [@"浓度色块 →" drawInRect:CGRectMake(0, blockY - 14, w, 12) withAttributes:smallAttrs];

    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyy/MM/dd HH:mm:ss";
    NSString *stamp = [formatter stringFromDate:[NSDate date]];
    NSString *info = [NSString stringWithFormat:@"浓度 %d · 份数 %d", density, copies];
    [info drawInRect:CGRectMake(0, h - 66, w, 12) withAttributes:smallAttrs];
    [stamp drawInRect:CGRectMake(0, h - 50, w, 12) withAttributes:smallAttrs];
  }];

  return SFThresholdImage(image);
}

#pragma mark - 实现

@interface ExpiryPrinterSDK () <CBCentralManagerDelegate>

/// 只用来回答「有没有蓝牙 / 开没开 / 有没有授权」。
/// 扫描与连接都由硕方 SDK 内部负责，它自己也会建 central。
@property (nonatomic, strong, nullable) CBCentralManager *centralManager;

@property (nonatomic, strong) NSMutableDictionary<NSString *, CBPeripheral *> *found;
@property (nonatomic, strong) NSMutableArray<CBPeripheral *> *foundOrder;
@property (nonatomic, strong, nullable) CBPeripheral *target;
@property (nonatomic, assign) BOOL scanning;
@property (nonatomic, strong, nullable) NSTimer *connectTimer;
@property (nonatomic, strong, nullable) NSTimer *scanStopTimer;

/// ★★ 是否有一次连接正在飞行中。
///
/// 为什么必须有这个标记：真机实测（v1.6.7）证明**「刚发起连接就 stopScan」会把
/// 这次连接掐死** —— 当时的扫描表点设备后是 `connect(...)` 紧跟着 `dismiss()`，
/// sheet 一关就走 `onDisappear -> stopScan()`，用户那边表现就是「打印机完全无法连接」。
///
/// Swift 层已经在 `isConnecting` 时拒绝转调 stopScan，但**下面那个 30 秒自动收尾
/// 定时器是直接调本方法的**，绕过了 Swift 层的守卫：用户如果在扫描的第 28 秒才
/// 点设备，自动收尾正好落在连接过程中，就会复现同一个坑。
/// 所以这一层也要挡。
@property (nonatomic, assign) BOOL connecting;

@end

@implementation ExpiryPrinterSDK

+ (instancetype)shared {
  static ExpiryPrinterSDK *instance = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    instance = [[ExpiryPrinterSDK alloc] init];
  });
  return instance;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _found = [NSMutableDictionary dictionary];
    _foundOrder = [NSMutableArray array];
    // ⚠️ 这里**故意不碰 CBCentralManager**。
    //    一碰它系统就会立刻弹蓝牙授权框；如果在 init 里碰，App 一启动就弹，
    //    用户还没进打印机页就被问权限（不符合苹果「就近申请」的规范，
    //    实测也确实在启动那一秒就弹了）。改为等真正用到蓝牙时再建。
    [self setupSDKCallbacks];
  }
  return self;
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

#pragma mark - 蓝牙状态

- (CBCentralManager *)centralManager {
  if (_centralManager == nil) {
    _centralManager =
        [[CBCentralManager alloc] initWithDelegate:self queue:dispatch_get_main_queue()];
  }
  return _centralManager;
}

- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
  // 只用于读取状态，不做额外处理
}

- (BOOL)bluetoothSupported {
  return self.centralManager.state != CBManagerStateUnsupported;
}

- (BOOL)bluetoothPoweredOn {
  return self.centralManager.state == CBManagerStatePoweredOn;
}

- (BOOL)bluetoothDenied {
  CBManagerAuthorization auth = CBCentralManager.authorization;
  return auth == CBManagerAuthorizationDenied || auth == CBManagerAuthorizationRestricted;
}

#pragma mark - 扫描

- (void)startScan {
  if (self.scanning) {
    SFPLog(@"[Printer] startScan 被忽略：已在扫描中");
    return;
  }
  self.scanning = YES;
  [self clearFound];
  [[SFPrintSDKUtils shareInstance] startScan];
  SFPLog(@"[Printer] startScan 已发起（30 秒后自动收尾）");

  [self.scanStopTimer invalidate];
  __weak typeof(self) weakSelf = self;
  self.scanStopTimer = [NSTimer scheduledTimerWithTimeInterval:kAutoStopScanSeconds
                                                       repeats:NO
                                                         block:^(NSTimer *timer) {
                                                           [weakSelf stopScan];
                                                         }];

  NSObject<ExpiryPrinterSDKDelegate> *d = self.delegate;
  if ([d respondsToSelector:@selector(printerDidStartScan)]) {
    SFOnMain(^{ [d printerDidStartScan]; });
  }
}

- (void)stopScan {
  // ★★ 连接进行中绝不真的去停扫描 —— 见 `connecting` 属性的注释。
  //    真停下去会把刚发起的 BLE 连接掐掉（v1.6.7 的「完全无法连接」就是这么来的）。
  //    改成就地**推迟 5 秒再收尾**：连接超时是 15 秒，最多推迟三四次；
  //    连接一旦有结果（成功/失败都会调 finishConnectWithPeripheral:）就放行，
  //    不会让扫描无限期跑下去。
  if (self.connecting) {
    SFPLog(@"[Printer] stopScan 推迟执行：正在连接中");
    [self.scanStopTimer invalidate];
    __weak typeof(self) weakSelf = self;
    self.scanStopTimer =
        [NSTimer scheduledTimerWithTimeInterval:5.0
                                        repeats:NO
                                          block:^(NSTimer *timer) {
                                            [weakSelf stopScan];
                                          }];
    return;
  }

  if (!self.scanning) {
    [self.scanStopTimer invalidate];
    self.scanStopTimer = nil;
    return;
  }
  self.scanning = NO;
  [self.scanStopTimer invalidate];
  self.scanStopTimer = nil;
  [[SFPrintSDKUtils shareInstance] stopScan];
  SFPLog(@"[Printer] stopScan 已调用");

  NSObject<ExpiryPrinterSDKDelegate> *d = self.delegate;
  if ([d respondsToSelector:@selector(printerDidStopScan)]) {
    SFOnMain(^{ [d printerDidStopScan]; });
  }
}

- (void)clearFound {
  [self.found removeAllObjects];
  [self.foundOrder removeAllObjects];
}

/// 给设备算一个可以展示的名字。
///
/// ★ 注意这里**不是稳定值**：BLE 设备常常在广播里不带名字，扫描阶段
///   `peripheral.name` 是 nil，只能退到 SDK 的友好名；而**连上之后**
///   iOS 会从 GATT 读到真实的 Device Name，`peripheral.name` 就变成另一个值了。
///   所以同一台设备「扫描列表里叫 A、连上后叫 B」是正常现象 —— 展示层要
///   以用户点过的那个名字为准（见 PrinterService.markConnected）。
- (NSString *)friendlyNameFor:(CBPeripheral *)peripheral {
  NSString *name = peripheral.name;
  if (name.length > 0) return name;
  NSString *friendly =
      [[SFPrintSDKUtils shareInstance] getDeviceNameWithperipheralName:peripheral.name];
  return (friendly.length > 0) ? friendly : @"未知设备";
}

+ (NSString *)nameStageOf:(CBPeripheral *)peripheral {
  // 便于日志里一眼看出名字是从哪一级来的
  if (peripheral == nil) return @"nil";
  if (peripheral.name.length > 0) return @"advertised";
  NSString *friendly =
      [[SFPrintSDKUtils shareInstance] getDeviceNameWithperipheralName:peripheral.name];
  return (friendly.length > 0) ? @"sdkFriendly" : @"unknown";
}

- (void)handleFoundPeripheral:(CBPeripheral *)peripheral {
  if (peripheral == nil) return;
  NSString *uuid = peripheral.identifier.UUIDString;
  if (uuid.length == 0) return;

  BOOL isNew = (self.found[uuid] == nil);
  if (isNew) {
    self.found[uuid] = peripheral;
    [self.foundOrder addObject:peripheral];
    SFPLog(@"[Printer] 发现设备 rawName=%@ stage=%@ uuid=%@",
           peripheral.name, [ExpiryPrinterSDK nameStageOf:peripheral], uuid);
  }
  if (!self.scanning) return;

  NSString *name = [self friendlyNameFor:peripheral];
  NSObject<ExpiryPrinterSDKDelegate> *d = self.delegate;
  if ([d respondsToSelector:@selector(printerDidFindDeviceUUID:name:)]) {
    SFOnMain(^{ [d printerDidFindDeviceUUID:uuid name:name]; });
  }
}

#pragma mark - 连接

- (void)finishConnectWithPeripheral:(CBPeripheral *)peripheral ok:(BOOL)ok {
  [self.connectTimer invalidate];
  self.connectTimer = nil;
  self.connecting = NO;

  NSString *uuid = peripheral.identifier.UUIDString ?: @"";
  NSString *name = peripheral ? [self friendlyNameFor:peripheral] : @"硕方 T50 Pro";
  SFPLog(@"[Printer] 连接回调 ok=%d uuid=%@ friendlyName=%@ rawName=%@ stage=%@",
         (int)ok, uuid, name, peripheral.name,
         [ExpiryPrinterSDK nameStageOf:peripheral]);
  NSObject<ExpiryPrinterSDKDelegate> *d = self.delegate;

  if (ok) {
    self.target = peripheral;
    if ([d respondsToSelector:@selector(printerDidConnectUUID:name:)]) {
      SFOnMain(^{ [d printerDidConnectUUID:uuid name:name]; });
    }
  } else {
    self.target = nil;
    if ([d respondsToSelector:@selector(printerDidFailToConnect)]) {
      SFOnMain(^{ [d printerDidFailToConnect]; });
    }
  }
}

- (void)handleDisconnected {
  self.target = nil;
  NSObject<ExpiryPrinterSDKDelegate> *d = self.delegate;
  if ([d respondsToSelector:@selector(printerDidDisconnect)]) {
    SFOnMain(^{ [d printerDidDisconnect]; });
  }
}

- (void)connectPeripheral:(CBPeripheral *)peripheral {
  self.target = peripheral;
  self.connecting = YES;
  [self.connectTimer invalidate];
  SFPLog(@"[Printer] 开始连接 %@ (%@)",
        peripheral.name, peripheral.identifier.UUIDString);

  __weak typeof(self) weakSelf = self;
  self.connectTimer = [NSTimer scheduledTimerWithTimeInterval:kConnectTimeoutSeconds
                                                      repeats:NO
                                                        block:^(NSTimer *timer) {
                                                          [weakSelf finishConnectWithPeripheral:weakSelf.target
                                                                                             ok:NO];
                                                        }];
  [[SFPrintSDKUtils shareInstance] connectedBlueteeth:peripheral];
}

- (void)connectDeviceUUID:(NSString *)uuid name:(nullable NSString *)name {
  if (uuid.length == 0 && name.length == 0) return;

  SFPLog(@"[Printer] connect 请求 uuid=%@ name=%@", uuid, name);

  // ① 本轮扫描结果里直接有 —— 最常见的情况。
  CBPeripheral *known = self.found[uuid];
  if (known == nil && name.length > 0) {
    // ② UUID 失效（重装 App 后 identifier 会变）时按名字回退。
    known = [self peripheralMatchingName:name];
    if (known != nil) {
      SFPLog(@"[Printer] UUID 已失效，按名字匹配到 %@ -> %@",
            name, known.identifier.UUIDString);
    }
  }
  if (known != nil) {
    [self connectPeripheral:known];
    return;
  }

  // ③ 还没扫到：先扫一轮再连。
  SFPLog(@"[Printer] 未在本轮扫描结果中，重新扫描后再连");
  [self startScan];

  __block NSInteger ticks = 0;
  __weak typeof(self) weakSelf = self;
  NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                   repeats:YES
                                                     block:^(NSTimer *inner) {
                                                       ticks += 1;
                                                       __strong typeof(weakSelf) strongSelf = weakSelf;
                                                       if (strongSelf == nil) {
                                                         [inner invalidate];
                                                         return;
                                                       }
                                                       CBPeripheral *found = strongSelf.found[uuid];
                                                       if (found == nil && name.length > 0) {
                                                         found = [strongSelf peripheralMatchingName:name];
                                                       }
                                                       if (found != nil) {
                                                         [inner invalidate];
                                                         [strongSelf stopScan];
                                                         [strongSelf connectPeripheral:found];
                                                         return;
                                                       }
                                                       if (ticks >= kScanUntilFoundTicks) {
                                                         SFPLog(@"[Printer] 扫描 %ld 秒仍未发现目标设备",
                                                               (long)ticks);
                                                         [inner invalidate];
                                                         [strongSelf stopScan];
                                                         [strongSelf finishConnectWithPeripheral:nil ok:NO];
                                                       }
                                                     }];
  [timer fire];
}

/// 在已发现的设备里按显示名找一个（UUID 失效时的回退手段）。
- (nullable CBPeripheral *)peripheralMatchingName:(NSString *)name {
  if (name.length == 0) return nil;
  for (CBPeripheral *peripheral in self.foundOrder) {
    NSString *candidate = peripheral.name;
    if (candidate.length == 0) {
      candidate = [[SFPrintSDKUtils shareInstance] getDeviceNameWithperipheralName:peripheral.name];
    }
    if (candidate.length == 0) continue;
    if ([candidate isEqualToString:name]) return peripheral;
  }
  return nil;
}

- (void)disconnect {
  CBPeripheral *target = self.target;
  if (target != nil) {
    [[SFPrintSDKUtils shareInstance] disConnectedBlueteeth:target];
  }
  self.target = nil;
  self.connecting = NO;
  [self.connectTimer invalidate];
  self.connectTimer = nil;
}

- (BOOL)isConnected {
  return [[SFPrintSDKUtils shareInstance] getDeviceStatus];
}

- (NSString *)connectedUUID {
  return self.target.identifier.UUIDString;
}

#pragma mark - 打印

- (void)notifyPrintDone:(BOOL)success message:(nullable NSString *)message {
  NSObject<ExpiryPrinterSDKDelegate> *d = self.delegate;
  if ([d respondsToSelector:@selector(printerDidFinishPrint:message:)]) {
    SFOnMain(^{ [d printerDidFinishPrint:success message:message]; });
  }
}

- (BOOL)printImage:(UIImage *)image
           widthMm:(int)widthMm
          heightMm:(int)heightMm
            copies:(int)copies
           density:(int)density
         paperType:(int)paperType {
  if (image == nil) {
    [self notifyPrintDone:NO message:@"标签图像渲染失败"];
    return NO;
  }
  if (![[SFPrintSDKUtils shareInstance] getDeviceStatus]) {
    [self notifyPrintDone:NO message:@"打印机未连接"];
    return NO;
  }

  SFPrintSetModel *model = [[SFPrintSetModel alloc] init];
  model.isAuto = YES;
  model.width = widthMm;
  model.length = heightMm;
  model.materialType = SFMaterialTypeFromPaperType(paperType);
  // 浓度 1~9；给 0 或负数时让 SDK 自己判断
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
                     SFPLog(@"[ExpiryPrinterSDK] print done ok=%d err=%@ %d/%d",
                           isSuccess,
                           error,
                           printNum,
                           allLength);
                     [weakSelf notifyPrintDone:isSuccess message:error];
                   }];
  return YES;
}

- (BOOL)printPDF:(NSData *)pdf
         widthMm:(int)widthMm
        heightMm:(int)heightMm
          copies:(int)copies
         density:(int)density
       paperType:(int)paperType {
  if (widthMm <= 0) widthMm = 50;
  if (heightMm <= 0) heightMm = 30;

  UIImage *image = SFRenderLabelPDF(pdf, widthMm * kDotsPerMM, heightMm * kDotsPerMM);
  return [self printImage:image
                  widthMm:widthMm
                 heightMm:heightMm
                   copies:copies
                  density:density
                paperType:paperType];
}

- (BOOL)printTestPageWidthMm:(int)widthMm
                    heightMm:(int)heightMm
                      copies:(int)copies
                     density:(int)density {
  if (widthMm <= 0) widthMm = 50;
  if (heightMm <= 0) heightMm = 30;
  if (copies <= 0) copies = 1;

  UIImage *image = SFBuildTestPage(widthMm, heightMm, density, copies);
  return [self printImage:image
                  widthMm:widthMm
                 heightMm:heightMm
                   copies:copies
                  density:density
                paperType:1];
}

@end

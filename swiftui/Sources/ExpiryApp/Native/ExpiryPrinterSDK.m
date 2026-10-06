//
//  ExpiryPrinterSDK.m
//  硕方蓝牙标签机封装实现。
//
//  逻辑移植自 Flutter 版 `plugins/expiry_native_ios/ios/Classes/SFPrinterBridge.m`
//  （那份代码已在真机 T50 Pro 上验证可正常打印），去掉了 Flutter 通道部分，
//  改成 delegate 回调给 SwiftUI。
//

#import "ExpiryPrinterSDK.h"

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
    [self setupSDKCallbacks];
    // 一碰 CBCentralManager 系统就会弹蓝牙授权框
    (void)self.centralManager;
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
  if (self.scanning) return;
  self.scanning = YES;
  [self clearFound];
  [[SFPrintSDKUtils shareInstance] startScan];

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
  if (!self.scanning) {
    [self.scanStopTimer invalidate];
    self.scanStopTimer = nil;
    return;
  }
  self.scanning = NO;
  [self.scanStopTimer invalidate];
  self.scanStopTimer = nil;
  [[SFPrintSDKUtils shareInstance] stopScan];

  NSObject<ExpiryPrinterSDKDelegate> *d = self.delegate;
  if ([d respondsToSelector:@selector(printerDidStopScan)]) {
    SFOnMain(^{ [d printerDidStopScan]; });
  }
}

- (void)clearFound {
  [self.found removeAllObjects];
  [self.foundOrder removeAllObjects];
}

- (NSString *)friendlyNameFor:(CBPeripheral *)peripheral {
  NSString *name = peripheral.name;
  if (name.length > 0) return name;
  NSString *friendly =
      [[SFPrintSDKUtils shareInstance] getDeviceNameWithperipheralName:peripheral.name];
  return (friendly.length > 0) ? friendly : @"未知设备";
}

- (void)handleFoundPeripheral:(CBPeripheral *)peripheral {
  if (peripheral == nil) return;
  NSString *uuid = peripheral.identifier.UUIDString;
  if (uuid.length == 0) return;

  BOOL isNew = (self.found[uuid] == nil);
  if (isNew) {
    self.found[uuid] = peripheral;
    [self.foundOrder addObject:peripheral];
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

  NSString *uuid = peripheral.identifier.UUIDString ?: @"";
  NSString *name = peripheral ? [self friendlyNameFor:peripheral] : @"硕方 T50 Pro";
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
  [self.connectTimer invalidate];

  __weak typeof(self) weakSelf = self;
  self.connectTimer = [NSTimer scheduledTimerWithTimeInterval:kConnectTimeoutSeconds
                                                      repeats:NO
                                                        block:^(NSTimer *timer) {
                                                          [weakSelf finishConnectWithPeripheral:weakSelf.target
                                                                                             ok:NO];
                                                        }];
  [[SFPrintSDKUtils shareInstance] connectedBlueteeth:peripheral];
}

- (void)connectDeviceUUID:(NSString *)uuid {
  if (uuid.length == 0) return;

  CBPeripheral *known = self.found[uuid];
  if (known != nil) {
    [self connectPeripheral:known];
    return;
  }

  // 目标设备还没扫到（例如从「已添加」进来）：先扫一轮再连。
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
                                                       if (found != nil) {
                                                         [inner invalidate];
                                                         [strongSelf stopScan];
                                                         [strongSelf connectPeripheral:found];
                                                         return;
                                                       }
                                                       if (ticks >= kScanUntilFoundTicks) {
                                                         [inner invalidate];
                                                         [strongSelf stopScan];
                                                         [strongSelf finishConnectWithPeripheral:nil ok:NO];
                                                       }
                                                     }];
  [timer fire];
}

- (void)disconnect {
  CBPeripheral *target = self.target;
  if (target != nil) {
    [[SFPrintSDKUtils shareInstance] disConnectedBlueteeth:target];
  }
  self.target = nil;
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
                     NSLog(@"[ExpiryPrinterSDK] print done ok=%d err=%@ %d/%d",
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

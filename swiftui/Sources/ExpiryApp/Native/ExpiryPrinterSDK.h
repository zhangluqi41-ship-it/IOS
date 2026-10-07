//
//  ExpiryPrinterSDK.h
//  效期管理系统 —— 硕方（SUPVAN）蓝牙标签机原生封装
//
//  为什么是 Objective-C：
//  硕方官方 SDK `SFPrintSDK.xcframework` 是 ObjC 框架，且**没有 module.modulemap**，
//  Swift 无法 `import SFPrintSDK`。做法是：用桥接头把 ObjC 头暴露给 Swift，
//  再写这一层 ObjC 封装（逻辑直接移植自 Flutter 版 `SFPrinterBridge.m`，
//  那份代码已在真机上验证过能成功打印 T50 Pro）。
//
//  ⚠️ 链接器必须带 `-ObjC`（见 project.yml 的 OTHER_LDFLAGS），
//     否则静态库里的 ObjC 类会被剥离 —— 表现是编译通过、运行期 unrecognized selector。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol ExpiryPrinterSDKDelegate <NSObject>

@optional
/// 开始扫描（含 SDK 侧 30 秒自动收尾触发的那次）。
- (void)printerDidStartScan;
/// 扫描结束（手动停止或自动收尾）。
- (void)printerDidStopScan;
/// 扫描过程中发现一台设备。
- (void)printerDidFindDeviceUUID:(NSString *)uuid name:(NSString *)name;
/// 连接成功。
- (void)printerDidConnectUUID:(NSString *)uuid name:(NSString *)name;
/// 连接失败（含 15 秒超时）。
- (void)printerDidFailToConnect;
/// 连接断开。
- (void)printerDidDisconnect;
/// 一次打印结束。
- (void)printerDidFinishPrint:(BOOL)success message:(nullable NSString *)message;

@end

@interface ExpiryPrinterSDK : NSObject

+ (instancetype)shared;

/// 事件回调。所有回调都在主线程。
@property (nonatomic, weak, nullable) id<ExpiryPrinterSDKDelegate> delegate;

/// 设备蓝牙是否支持（未支持时整个功能不可用）。
@property (nonatomic, readonly) BOOL bluetoothSupported;
/// 蓝牙是否已开启。
@property (nonatomic, readonly) BOOL bluetoothPoweredOn;
/// 蓝牙授权是否被拒。
@property (nonatomic, readonly) BOOL bluetoothDenied;
/// 当前是否正在扫描。
@property (nonatomic, readonly) BOOL scanning;
/// 当前已连接设备的 UUID 字符串（未连接为 nil）。
@property (nonatomic, readonly, nullable) NSString *connectedUUID;

#pragma mark - 扫描 / 连接

- (void)startScan;
- (void)stopScan;
/// 连接指定设备。
///
/// - Parameters:
///   - uuid: 目标设备的 `peripheral.identifier`。
///   - name: 设备名，可空。**UUID 找不到时会按名字回退匹配**。
///
/// ★ 为什么必须支持按名字回退：iOS 的 `peripheral.identifier` 是**按 App 安装**
///   分配的 —— 重装 App（我们每周都要重签重装）之后，旧 UUID 就指向不存在的设备了。
///   「已添加」里存的就是这种旧 UUID，点它必然扫不到、永远连不上。
///   此时按名字匹配才能救回来，连上后再把新 UUID 回写覆盖。
- (void)connectDeviceUUID:(NSString *)uuid name:(nullable NSString *)name;
- (void)disconnect;

/// 硕方 SDK 只暴露「已连接 / 未连接」，没有更细的状态码。
- (BOOL)isConnected;

#pragma mark - 打印

/// 打印一张标签 PDF（首页按 203dpi 栅格化后二值化）。
- (BOOL)printPDF:(NSData *)pdf
         widthMm:(int)widthMm
        heightMm:(int)heightMm
          copies:(int)copies
         density:(int)density
       paperType:(int)paperType;

/// 打印标尺测试页（确认走纸、边距、印位、浓度）。
- (BOOL)printTestPageWidthMm:(int)widthMm
                    heightMm:(int)heightMm
                      copies:(int)copies
                     density:(int)density;

@end

NS_ASSUME_NONNULL_END

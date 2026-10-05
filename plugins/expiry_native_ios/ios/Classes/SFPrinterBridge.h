#import <Foundation/Foundation.h>
#import <Flutter/Flutter.h>

/// 蓝牙打印通道（`com.xiaoqi.expiry_manager/printer`）的 iOS 实现。
///
/// 走硕方官方 iOS SDK（`SFPrintSDKUtils`），通道名、方法名、事件格式
/// 与安卓侧 `PrinterBridge` **完全一致**，Dart 代码一行都不用改。
///
/// 与安卓的差异（iOS 平台本身限制，非实现取舍）：
/// * iOS 拿不到蓝牙 MAC 地址，设备标识用 CoreBluetooth 的
///   `peripheral.identifier.UUIDString`（本 App 内稳定）；
/// * iOS 不允许经典蓝牙 SPP，所以只支持走 BLE 的硕方机型，
///   `generic_tspl` / `generic_escpos` 会直接返回失败；
/// * SDK 只提供「已连接 / 未连接」，查不到具体状态码。
@interface SFPrinterBridge : NSObject

/// 注册通道并初始化 SDK 回调。整个 App 生命周期只调一次。
+ (void)registerWithMessenger:(NSObject<FlutterBinaryMessenger> *)messenger;

@end

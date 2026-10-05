//
//  SFPrintSDK.h
//  SFPrintSDK
//
//  Created by SFTechnology on 2023/9/12.
//

#import <Foundation/Foundation.h>
#import <CoreBluetooth/CoreBluetooth.h>
#import <SFPrintSDK/SFPrintSetModel.h>
//#import <SFPrintSDK/SFDeviceModel.h>

NS_ASSUME_NONNULL_BEGIN

@interface SFPrintSDKUtils : NSObject
+ (SFPrintSDKUtils *)shareInstance;

// 发现设备回调
@property (nonatomic, copy) void(^findDeviceBlock)(CBPeripheral *peripheral);
// 连接成功回调
@property (nonatomic, copy) void (^connectSuccessBlock)(CBPeripheral *peripheral);
// 连接失败回调
@property (nonatomic, copy) void (^connectFailBlock)(void);
// 连接断开回调
@property (nonatomic, copy) void (^disconnectBlock)(void);

// 连接蓝牙
-(void)connectedBlueteeth:(CBPeripheral *)peripheral;
// 断开蓝牙
-(void)disConnectedBlueteeth:(CBPeripheral *) peripheral;
/*
  搜索蓝牙设备
  由于蓝牙是搜索不会自动停止，需要自己手动设置搜索的时间然后自己手动停止
 */
-(void)startScan;
// 停止搜索
-(void)stopScan;
/// 获取打印机连接状态
/// 返回值 YES: 已连接， NO: 未连接
- (BOOL)getDeviceStatus;
/// 打印方法
/// - Parameters:
///   - printModel: 打印数据模型，具体参数请看模型
///   - printImages: 需要打印的内容
///   - complete: 完成回调
- (void)doPrintWithPrintModel:(SFPrintSetModel *)printModel complete:(void(^)(BOOL isSuccess, NSString *error, int printNum, int allLength))complete;
// 取消打印
-(void)cancelPrint;
-(NSString *)getDeviceNameWithperipheralName:(nullable NSString *)peripheralName;
-(UIImage *)getDeviceImageWithperipheralName:(nullable NSString *)peripheralName;
@end

NS_ASSUME_NONNULL_END

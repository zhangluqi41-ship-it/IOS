//
//  SFPrintSetModel.h
//  SFPrintSDK
//
//  Created by SFTechnology on 2023/9/13.
//

#import <Foundation/Foundation.h>
#import <SFPrintSDK/SFPrintDrawobjectModel.h>
NS_ASSUME_NONNULL_BEGIN
@interface SFPrintSetModel : NSObject
// 是否自动 必传参数
@property (nonatomic, assign) BOOL isAuto;
// 标签宽 必传参数 单位为毫米 ---- 旋转之前的宽
@property (nonatomic, assign) int width;
// 标签长 必传参数 单位为毫米 ---- 旋转之前的高
@property (nonatomic, assign) int length;
/**
纸张类型： 1 间隙纸  4 黑标纸 5 黑标卡尺
*/
@property (nonatomic, assign) int materialType;
// 浓度 1 - 9
@property (nonatomic, assign) int deepness;
// 份数
@property (nonatomic, assign) int copy;
// 半切深度
@property (nonatomic, assign) int cutdeep;
// 是否逐份打印
@property (nonatomic, assign) int oneByone;
//  左右印位
@property (nonatomic, assign) int left;
// 上下印位
@property (nonatomic, assign) int top;
/*
 耗材旋转角度 1： 0°， 2 ：90°， 3： 180° ，4：270°
 旋转 90° 和 270° 的时候宽高需要主要是否互换
 */
@property (nonatomic, assign) int ratio;

// 要打印的元素 详情请见 SFPrintDrawobjectModel 头文件
@property (nonatomic, copy) NSArray<SFPrintDrawobjectModel *> *printImgModels;
@end

NS_ASSUME_NONNULL_END

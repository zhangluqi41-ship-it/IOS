//
//  SFPrintDrawobjectModel.h
//  SFPrintSDK
//
//  Created by SFTechnology on 2023/9/13.
//


#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SFPrintDrawobjectModel : NSObject
// 反色
@property (nonatomic, strong) NSNumber *textColor;

// x坐标单位 pt
@property (nonatomic, assign) double x;

// y坐标单位 pt
@property (nonatomic, assign) double y;

// 宽度单位 pt
@property (nonatomic, assign) double width;

// 高度单位 pt
@property (nonatomic, assign) double height;

// 默认字符，如果是TEXT类型的话直接显示，如果是Image类型的话这里是 图片的 url 地址，如果要打印本地图片的话需要给 localImage赋值
@property (nonatomic, copy) NSString* content;

// 顺时针的旋转度数
@property (nonatomic, strong) NSNumber *rotate;

// 字体类型 0：正常 1：加粗 2：倾斜 3: 下划线 4：中划线
@property (nonatomic, assign) int fontStyle;

// 字体高度 0 - 1.0 倍数
@property (nonatomic, assign) double fontHeight;

// 对齐方式 0： 左对齐， 1： 垂直对齐  2： 右对齐
@property (nonatomic, assign) int verAlignmentType;

// 字间距
@property (nonatomic, assign) int charSpace;

// 行间距
@property (nonatomic, assign) int lineSpace;

// 自动换行 目前没有解决
@property (nonatomic, assign) BOOL autoReturn;


// 字体大小
@property (nonatomic, assign) int fontSize;

///自动字号
@property (nonatomic, assign) BOOL autoFont;


// 字体名称，默认黑体
@property (nonatomic, copy) NSString* fontName;

@property (nonatomic, copy) NSString* format;

// 如果要打印本地图片，直接从相册选取本地图片后放到这个属性即可
@property (nonatomic, strong) UIImage *localImage;

// 耗材旋转角度 1： 0°， 2 ：90°， 3： 180° ，4：270°
@property (nonatomic, assign) int ratio;

@end

NS_ASSUME_NONNULL_END

//
//  ExpiryApp-Bridging-Header.h
//  Swift ⇄ Objective-C 桥接头
//
//  作用有两个：
//   1. 把硕方 SDK 的头暴露给 Swift（框架没有 modulemap，不能 `import SFPrintSDK`）；
//   2. 暴露自写的 ObjC 封装 `ExpiryPrinterSDK`。
//
//  ⚠️ 顺序很关键：**必须先 import UIKit**。
//     硕方 SDK 的头文件用了 `UIImage` 却没有自己 import UIKit
//     （SFPrintDrawobjectModel.h 的 localImage 属性、SFPrintSDKUtils.h 的
//      getDeviceImageWithperipheralName），先引 SDK 头会直接报
//     「unknown type name 'UIImage'」把整个 PCH 编译打断。
//     Flutter 版的 SFPrinterBridge.m 之所以没踩到，就是因为它先 import 了 UIKit。
//
//  ⚠️ 只 import 硕方包里**真实存在**的头文件。
//     官方 umbrella 头 `SFPrintSDKHeaders.h` 引用了 DrawUtils.h / PrintSetModel.h /
//     DrawobjectModel.h / PrintPageModel.h —— 这些文件在发布的 framework 里并不存在，
//     一旦 import 就会编译失败。
//

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

#import <SFPrintSDK/SFPrintSDKUtils.h>
#import <SFPrintSDK/SFPrintSetModel.h>
#import <SFPrintSDK/SFPrintDrawobjectModel.h>

#import "ExpiryPrinterSDK.h"
#import "PrinterLog.h"

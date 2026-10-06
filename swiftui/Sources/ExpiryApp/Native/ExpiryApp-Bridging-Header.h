//
//  ExpiryApp-Bridging-Header.h
//  Swift ⇄ Objective-C 桥接头
//
//  作用有两个：
//   1. 把硕方 SDK 的头暴露给 Swift（框架没有 modulemap，不能 `import SFPrintSDK`）；
//   2. 暴露自写的 ObjC 封装 `ExpiryPrinterSDK`。
//
//  ⚠️ 只 import 硕方包里**真实存在**的头文件。
//     官方 umbrella 头 `SFPrintSDKHeaders.h` 引用了 DrawUtils.h / PrintSetModel.h /
//     DrawobjectModel.h / PrintPageModel.h —— 这些文件在发布的 framework 里并不存在，
//     一旦 import 就会编译失败。
//

#import <SFPrintSDK/SFPrintSDKUtils.h>
#import <SFPrintSDK/SFPrintSetModel.h>
#import <SFPrintSDK/SFPrintDrawobjectModel.h>

#import "ExpiryPrinterSDK.h"

//
//  PrinterLog.h
//  打印机诊断日志 —— 同时进系统日志（NSLog）和沙盒内文件。
//
//  为什么必须落文件：这台机器上没有 Mac，真机上的 `NSLog` 只能靠
//  `syslog_relay` 实时抓（`ip_tool.py log`），**没有历史回放** ——
//  用户操作完了再去抓，日志已经过去了，只能让用户"再来一遍"，很折磨。
//  落到 Documents 里就没有这个问题：随时用 house_arrest 拉回来慢慢看。
//
//  路径：<App 沙盒>/Documents/printer_log.txt（超过 256 KB 自动清空重记）
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 记一行日志。会自动加时间戳，线程安全，失败静默（日志绝不能影响主流程）。
FOUNDATION_EXPORT void SFPrinterLog(NSString *message);

/// 日志文件的绝对路径（用于界面上展示 / 排查）。
FOUNDATION_EXPORT NSString * _Nullable SFPrinterLogPath(void);

/// 清空日志。
FOUNDATION_EXPORT void SFPrinterLogClear(void);

NS_ASSUME_NONNULL_END

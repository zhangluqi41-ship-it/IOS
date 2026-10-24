//
//  PrinterLog.m
//

#import "PrinterLog.h"

/// 超过这个大小就清空重来，避免日志无限增长把沙盒塞满。
static const unsigned long long kMaxLogBytes = 256 * 1024;

static NSString *SFPrinterLogFilePath(void) {
  static NSString *path = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    NSArray<NSString *> *docs =
        NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *dir = docs.firstObject;
    if (dir.length > 0) {
      path = [dir stringByAppendingPathComponent:@"printer_log.txt"];
    }
  });
  return path;
}

NSString * _Nullable SFPrinterLogPath(void) {
  return SFPrinterLogFilePath();
}

static NSDateFormatter *SFPrinterLogFormatter(void) {
  static NSDateFormatter *formatter = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    formatter = [[NSDateFormatter alloc] init];
    // 固定 locale，避免跟随系统 12/24 小时制变化
    formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.dateFormat = @"HH:mm:ss.SSS";
  });
  return formatter;
}

static dispatch_queue_t SFPrinterLogQueue(void) {
  static dispatch_queue_t queue = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    queue = dispatch_queue_create("com.xiaoqi.expiry.printer.log", DISPATCH_QUEUE_SERIAL);
  });
  return queue;
}

void SFPrinterLog(NSString *message) {
  if (message.length == 0) return;

  // 1) 系统日志 —— 便于 `ip_tool.py log` 实时抓
  NSLog(@"[Printer] %@", message);

  // 2) 沙盒文件 —— 便于事后拉回来
  NSString *path = SFPrinterLogFilePath();
  if (path.length == 0) return;

  NSString *line = [NSString stringWithFormat:@"%@ %@\n",
                                              [SFPrinterLogFormatter() stringFromDate:[NSDate date]],
                                              message];

  dispatch_async(SFPrinterLogQueue(), ^{
    NSFileManager *fm = [NSFileManager defaultManager];
    @try {
      NSDictionary *attrs = [fm attributesOfItemAtPath:path error:NULL];
      if (attrs != nil && [attrs fileSize] > kMaxLogBytes) {
        [fm removeItemAtPath:path error:NULL];
      }
      if (![fm fileExistsAtPath:path]) {
        [fm createFileAtPath:path contents:nil attributes:nil];
      }
      NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
      if (handle == nil) return;
      [handle seekToEndOfFile];
      [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
      [handle closeFile];
    } @catch (NSException *e) {
      // 记日志失败绝不能影响打印/连接主流程
      NSLog(@"[Printer] 写日志文件失败: %@", e.reason);
    }
  });
}

void SFPrinterLogClear(void) {
  NSString *path = SFPrinterLogFilePath();
  if (path.length == 0) return;
  dispatch_async(SFPrinterLogQueue(), ^{
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
  });
}

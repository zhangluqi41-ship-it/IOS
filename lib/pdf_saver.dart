import 'package:flutter/services.dart';

/// PDF 落盘到手机系统目录。
///
/// 走安卓原生 MediaStore（`Downloads` 集合），**不需要任何存储权限**：
/// - API >= 29：写入 MediaStore.Downloads，文件出现在系统「下载」目录，
///   任何文件管理器 / 电脑数据线都能看到；
/// - API < 29：退回应用专属外部目录（同样免权限），并用 MediaScanner 通知媒体库。
///
/// 非 Android 平台（桌面 / Web）本通道未实现，调用会抛 [MissingPluginException]，
/// 由调用方降级处理。
class PdfSaver {
  const PdfSaver._();

  static const MethodChannel _channel =
      MethodChannel('com.xiaoqi.expiry_manager/save');

  /// 把 [bytes] 存为 [fileName]，返回人类可读的保存位置（失败抛异常）。
  static Future<String> saveToDownloads(Uint8List bytes, String fileName) async {
    final path = await _channel.invokeMethod<String>(
      'saveToDownloads',
      <String, dynamic>{'name': fileName, 'bytes': bytes},
    );
    return path ?? '下载/$fileName';
  }
}

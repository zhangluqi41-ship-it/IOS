import 'package:flutter/services.dart';

import 'printer.dart' show kIsIos;

/// PDF 落盘到手机系统目录。
///
/// **Android**：走原生 MediaStore（`Downloads` 集合），**不需要任何存储权限**：
/// - API >= 29：写入 MediaStore.Downloads，文件出现在系统「下载」目录，
///   任何文件管理器 / 电脑数据线都能看到；
/// - API < 29：退回应用专属外部目录（同样免权限），并用 MediaScanner 通知媒体库。
///
/// **iOS**：写入 App 的 Documents 目录。配合 `Info.plist` 里的
/// `UIFileSharingEnabled = true` + `LSSupportsOpeningDocumentsInPlace = true`，
/// 用户可以在「文件」App 的「我的 iPhone → 效期管理系统」里看到，
/// 也可以通过「分享」面板导出到别处。
///
/// 非 Android / iOS 平台本通道未实现，调用会抛 [MissingPluginException]，
/// 由调用方降级处理。
class PdfSaver {
  const PdfSaver._();

  static const MethodChannel _channel =
      MethodChannel('com.xiaoqi.expiry_manager/save');

  /// 安卓：把 [bytes] 存为 [fileName]，返回人类可读的保存位置（失败抛异常）。
  ///
  /// **iOS 也复用这个方法**：原生侧 `handleSave` 对 iOS 的实现是
  /// 写入 App 的 Documents 目录，并返回「文件 App → 我的 iPhone → 效期管理程序 / xxx.pdf」
  /// 这样的可读路径 —— 两端行为一致，无需额外方法。
  static Future<String> saveToDownloads(Uint8List bytes, String fileName) async {
    final String? path = await _channel.invokeMethod<String>(
      'saveToDownloads',
      <String, dynamic>{'name': fileName, 'bytes': bytes},
    );
    return path ?? (kIsIos ? '「文件」App / $fileName' : '下载/$fileName');
  }
}


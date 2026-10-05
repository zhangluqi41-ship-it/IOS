/// iOS 导航封装 —— `lib/nav.dart` 的 Cupertino 对位实现。
///
/// **核心修复（需求第 2 条）**：
/// 安卓侧用的 `GlassPageRoute` 是 `PageRouteBuilder` 的通用过渡，
/// **不携带 iOS 的边缘滑动返回手势**，所以「手势操作返回上一级无法使用」。
///
/// 这里改用 `CupertinoPageRoute`，它由 Flutter 引擎直接提供：
///  * 从屏幕左缘右滑返回上一级（interactive pop gesture）
///  * iOS 原生的横向推入 + 阴影过渡
///  * 上一页视差跟随（parallax）
///  * 导航栏标题的淡入淡出
///
/// 三者都是 Flutter 里最接近真 UIKit 的行为。
library;

import 'dart:typed_data';

import 'package:flutter/cupertino.dart';

import '../preview_page.dart';

/// 全局导航观察者（供底栏显隐订阅）。
///
/// 注意：必须是 `RouteObserver<PageRoute<dynamic>>`，
/// 而 `CupertinoPageRoute` 正是 `PageRoute` 的子类，可以被正常订阅。
final RouteObserver<PageRoute<dynamic>> iosRouteObserver =
    RouteObserver<PageRoute<dynamic>>();

/// 打开二级 / 三级页面 —— iOS 原生转场 + 边缘滑动返回。
Future<T?> iosPush<T>(BuildContext context, Widget page) {
  return Navigator.of(context).push<T>(
    CupertinoPageRoute<T>(
      builder: (_) => page,
      // 保留页面标题用于返回按钮文案（Cupertino 会显示上一页标题）
      // 不传 settings 时返回按钮为「返回」
    ),
  );
}

/// 打开标签预览页（三级）。
Future<void> iosOpenPreview(
  BuildContext context,
  Uint8List bytes,
  String fileName,
) {
  return iosPush<void>(
    context,
    LabelPreviewPage(pdfBytes: bytes, fileName: fileName),
  );
}

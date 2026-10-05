import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'preview_page.dart';

/// 全局路由观察者：一级页面靠它感知「二级页压上来 / 退回去」，
/// 从而让底部玻璃栏下滑消失、返回时上滑复原。
final RouteObserver<PageRoute<dynamic>> glassRouteObserver =
    RouteObserver<PageRoute<dynamic>>();

/// 二级页面推入时的过渡：轻微上浮 + 淡入。
///
/// 故意不用整页遮罩式的切换 —— 过渡期间能看见一级页面的底栏正在往下沉，
/// 视觉上就是「底栏收进屏幕、子页面浮上来」。
class GlassPageRoute<T> extends PageRouteBuilder<T> {
  GlassPageRoute({required WidgetBuilder builder, super.settings})
    : super(
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (context, animation, secondary) => builder(context),
        transitionsBuilder: (context, animation, secondary, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.05),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      );
}

/// 打开一个二级页面。
Future<T?> openLevel2<T>(BuildContext context, Widget page) {
  return Navigator.of(context).push<T>(GlassPageRoute<T>(builder: (_) => page));
}

/// 打开三级页：标签预览。
Future<void> openPreview(
  BuildContext context,
  Uint8List bytes,
  String fileName,
) async {
  await openLevel2<void>(
    context,
    LabelPreviewPage(pdfBytes: bytes, fileName: fileName),
  );
}

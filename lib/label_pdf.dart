import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import 'label_renderer.dart';

String _p2(int v) => v.toString().padLeft(2, '0');

/// 生成 PDF 文件名：`标题_yyyyMMdd_HHmm.pdf`。
/// 标题里可能含非法字符且可能很长，统一做替换与截断。
String labelFileName(String title, DateTime now) {
  var safe = title.replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_');
  final runes = safe.runes.toList();
  if (runes.length > 40) safe = String.fromCharCodes(runes.take(40));
  if (safe.isEmpty) safe = '标签';
  final ts =
      '${now.year}${_p2(now.month)}${_p2(now.day)}_'
      '${_p2(now.hour)}${_p2(now.minute)}';
  return '${safe}_$ts.pdf';
}

/// 加载内置字体并渲染标签 PDF（字体已随包分发，开源思源黑体）。
Future<Uint8List> renderLabelPdf(LabelData data) async {
  final reg = await rootBundle.load('assets/fonts/NotoSansSC-Regular.ttf');
  final bold = await rootBundle.load('assets/fonts/NotoSansSC-Bold.ttf');
  return buildLabelPdf(
    data,
    fontRegular: reg.buffer.asUint8List(reg.offsetInBytes, reg.lengthInBytes),
    fontBold: bold.buffer.asUint8List(bold.offsetInBytes, bold.lengthInBytes),
  );
}

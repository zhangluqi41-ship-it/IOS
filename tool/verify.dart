import 'dart:io';

import 'package:expiry_manager/label_renderer.dart';

/// 校验脚本：复刻 Python 定稿 `v5_通用模板` 的**完全相同输入**，
/// 产出 PDF 用于与原版 PNG 做版式比对。
///
/// 注意：定稿里的星期/时间是当时的示例数据（写死在 Python TEMPLATES 里），
/// 这里照抄，才能验证「版式」而不是「数据规则」。
Future<void> main(List<String> args) async {
  final outPath = args.isNotEmpty ? args[0] : 'verify_out.pdf';

  const data = LabelData(
    title: '杨桃菠萝浓缩汁',
    rows: [
      LabelRow('开封时间：', '2026/10/04 20:08'),
      LabelRow('原始保质期：', '2027/01/04 23:59'),
      LabelRow('最佳使用时间：', '2026/11/04 23:59'),
    ],
    weekdayCn: '四',
    weekdayEn: 'Thu',
    rightText: '20:08',
    maker: '制作人：张皓',
  );

  final reg = File('assets/fonts/NotoSansSC-Regular.ttf').readAsBytesSync();
  final bold = File('assets/fonts/NotoSansSC-Bold.ttf').readAsBytesSync();

  final bytes = await buildLabelPdf(
    data,
    fontRegular: reg,
    fontBold: bold,
  );
  File(outPath).writeAsBytesSync(bytes);

  stdout.writeln('PDF: $outPath (${bytes.length} bytes)');
  stdout.writeln('二维码: ${data.qrText}');
}

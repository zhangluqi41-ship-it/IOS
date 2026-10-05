import 'dart:io';

import 'package:expiry_manager/label_renderer.dart';
import 'package:expiry_manager/label_template.dart';

/// 标题自适应缩放验证：不同长度标题各出一张 PDF，看字号是否自动收窄。
///
/// 用法：dart run tool/title_test.dart <输出目录>
Future<void> main(List<String> args) async {
  final outDir = args.isNotEmpty ? args[0] : '.';
  final titles = <String>[
    '杨桃菠萝浓缩汁',
    '杨桃菠萝浓缩汁（大瓶）',
    '杨桃菠萝浓缩汁·无糖发酵版',
    '杨桃菠萝浓缩汁超长标题压力测试版一号',
  ];

  final reg = File('assets/fonts/NotoSansSC-Regular.ttf').readAsBytesSync();
  final bold = File('assets/fonts/NotoSansSC-Bold.ttf').readAsBytesSync();
  final now = DateTime(2026, 10, 4, 20, 8, 30);

  for (var i = 0; i < titles.length; i++) {
    final data = LabelTemplate.buildGeneric(
      title: titles[i],
      now: now,
      expireDate: DateTime(2027, 1, 4),
      bestBefore: DateTime(2026, 11, 4),
      maker: '张皓',
    );
    final bytes = await buildLabelPdf(
      data,
      fontRegular: reg,
      fontBold: bold,
    );
    File('$outDir/title_$i.pdf').writeAsBytesSync(bytes);
    stdout.writeln('[$i] ${titles[i].length} 字 -> $outDir/title_$i.pdf');
  }
}

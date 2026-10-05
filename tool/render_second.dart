// 端到端回环验证：读取真实标签解码出来的二维码文本 →
// 解析一发 → 按规则生成二发标签 PDF。
// 运行： dart run tool/render_second.dart <qr.txt> <out.pdf>
import 'dart:io';

import '../lib/label_renderer.dart';
import '../lib/label_template.dart';

Future<void> main(List<String> args) async {
  final qr = File(args[0]).readAsStringSync();
  final out = args[1];

  print('扫到的二维码文本: $qr');
  final parsed = LabelTemplate.parseKombuchaQr(qr);
  if (parsed == null) {
    stderr.writeln('解析失败：不是康普茶标签');
    exit(1);
  }
  print('解析 → 标题=${parsed.title} 品种=${parsed.variety} '
      '完成=${parsed.finished} 最佳=${parsed.bestBefore} 制作人=${parsed.maker}');

  // 模拟：二发在 一发完成日 当天扫码
  final scanAt = DateTime(2026, 10, 12, 9, 15);
  final data = LabelTemplate.buildKombuchaSecond(
    firstTitle: parsed.title,
    fruit: '草莓',
    now: scanAt,
    firstFinished: parsed.finished,
    firstBestBefore: parsed.bestBefore,
    maker: parsed.maker,
  );
  print('二发标题: ${data.title}');
  for (final r in data.rows) {
    print('  ${r.label}${r.value}');
  }

  final reg = File('assets/fonts/NotoSansSC-Regular.ttf').readAsBytesSync();
  final bold = File('assets/fonts/NotoSansSC-Bold.ttf').readAsBytesSync();
  final pdf = await buildLabelPdf(
    data,
    fontRegular: reg,
    fontBold: bold,
  );
  File(out).writeAsBytesSync(pdf);
  print('已写出 $out （${pdf.length} 字节）');
}

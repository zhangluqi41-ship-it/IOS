import 'dart:io';

import 'package:expiry_manager/label_renderer.dart';
import 'package:expiry_manager/label_template.dart';

/// 规则演示：固定「生成时刻」，看不同天数产出什么文本。
///
/// 用法：
///   dart run tool/rule_demo.dart <输出目录> [天数,逗号分隔]
/// 例：
///   dart run tool/rule_demo.dart D:/out 3,7,8,30
///
/// 规则（2026-10-05 定稿）：
///   开封时间                   = 生成时刻
///   原始保质期 / 最佳使用时间  = 所选日期；距今天 ≤7 自然日 → 当前时刻；>7 天 → 23:59
///   右竖排                     = 当前时刻 HH:MM
Future<void> main(List<String> args) async {
  final outDir = args.isNotEmpty ? args[0] : '.';
  final days = args.length > 1
      ? args[1].split(',').map(int.parse).toList()
      : <int>[3, 7, 8, 30];

  // 固定“生成时刻”，保证可复现
  final now = DateTime(2026, 10, 4, 20, 8, 30);
  final today = DateTime(now.year, now.month, now.day);

  final reg = File('assets/fonts/NotoSansSC-Regular.ttf').readAsBytesSync();
  final bold = File('assets/fonts/NotoSansSC-Bold.ttf').readAsBytesSync();

  stdout.writeln('生成时刻 now = ${LabelTemplate.fmtDateTime(now)}'
      '   阈值 = ${LabelTemplate.endOfDayThresholdDays} 天');
  stdout.writeln('原始保质期与最佳使用时间共用同一规则，故取同一日期做边界验证。');
  stdout.writeln('');

  for (final d in days) {
    final date = today.add(Duration(days: d));
    final isShort = LabelTemplate.isWithinThreshold(now, date);

    final data = LabelTemplate.buildGeneric(
      title: '所选日期+$d天',
      now: now,
      expireDate: date,
      bestBefore: date,
      maker: '张皓',
    );

    final bytes = await buildLabelPdf(
      data,
      fontRegular: reg,
      fontBold: bold,
    );
    final path = '$outDir/rule_demo_$d.pdf';
    File(path).writeAsBytesSync(bytes);

    stdout.writeln('--- 所选日期 = 今天 + $d 天 '
        '→ ${isShort ? '≤7 天：取当前时刻' : '>7 天：23:59'} ---');
    for (final r in data.rows) {
      stdout.writeln('    ${r.label}${r.value}');
    }
    stdout.writeln('    右竖排: ${data.rightText}');
    stdout.writeln('    -> $path');
    stdout.writeln('');
  }

  // 附加：两字段取不同日期，验证各自独立判定
  stdout.writeln('--- 附加：两字段取不同日期（各自独立判定）---');
  final mixed = LabelTemplate.buildGeneric(
    title: '混合场景',
    now: now,
    expireDate: today.add(const Duration(days: 3)), // ≤7 → 当前时刻
    bestBefore: today.add(const Duration(days: 30)), // >7 → 23:59
    maker: '张皓',
  );
  for (final r in mixed.rows) {
    stdout.writeln('    ${r.label}${r.value}');
  }
}

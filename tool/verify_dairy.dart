// 纯 Dart 逻辑校验：奶制品 5 个类型的效期规则 + 出 PDF 供肉眼看版式。
// 运行： dart run tool/verify_dairy.dart <outDir>
import 'dart:io';

import '../lib/label_renderer.dart';
import '../lib/label_template.dart';

int _pass = 0;
int _fail = 0;

void check(String name, Object? actual, Object? expected) {
  final ok = '$actual' == '$expected';
  if (ok) {
    _pass++;
    print('  [OK]   $name = $actual');
  } else {
    _fail++;
    print('  [FAIL] $name = $actual  (期望 $expected)');
  }
}

/// 距 [base] 的当天 + [days] 天（不带时刻，模拟界面上点快捷按钮的结果）。
DateTime at(DateTime base, int days) =>
    DateTime(base.year, base.month, base.day).add(Duration(days: days));

Future<void> main(List<String> args) async {
  final outDir = args.isEmpty ? 'build/dairy' : args[0];
  Directory(outDir).createSync(recursive: true);

  final now = DateTime(2026, 10, 5, 18, 34, 20);

  print('== 1. 各类型推荐天数 ==');
  check('牛奶', '${DairyKind.milk.expireDays}/${DairyKind.milk.bestDays}', '7/3');
  check(
    '高蛋白牛奶',
    '${DairyKind.highProteinMilk.expireDays}/${DairyKind.highProteinMilk.bestDays}',
    '7/3',
  );
  check('豆奶', '${DairyKind.soyMilk.expireDays}/${DairyKind.soyMilk.bestDays}', '7/3');
  check('燕麦奶', '${DairyKind.oatMilk.expireDays}/${DairyKind.oatMilk.bestDays}', '45/5');
  check(
    '巴旦木奶',
    '${DairyKind.almondMilk.expireDays}/${DairyKind.almondMilk.bestDays}',
    '60/7',
  );

  print('== 2. 牛奶：+7 天（阈值内，显示时刻） / +3 天 ==');
  final milk = LabelTemplate.buildDairy(
    kindLabel: DairyKind.milk.label,
    now: now,
    expireDate: at(now, 7),
    bestBefore: at(now, 3),
    maker: '张皓',
  );
  check('标题 = 类型名', milk.title, '牛奶');
  check('开封时间', milk.rows[0].value, '2026/10/05 18:34');
  check('原始保质期（7 天 = 阈值内）', milk.rows[1].value, '2026/10/12 18:34');
  check('最佳使用时间（3 天）', milk.rows[2].value, '2026/10/08 18:34');
  check('右黑条时间', milk.rightText, '18:34');
  check('左黑条 星期几', milk.weekdayCn, '一');
  print('  二维码内容 = ${milk.qrText}');

  print('== 3. 燕麦奶：+45 天（超阈值，收 23:59） / +5 天 ==');
  final oat = LabelTemplate.buildDairy(
    kindLabel: DairyKind.oatMilk.label,
    now: now,
    expireDate: at(now, 45),
    bestBefore: at(now, 5),
    maker: '张皓',
  );
  check('原始保质期（45 天）', oat.rows[1].value, '2026/11/19 23:59');
  check('最佳使用时间（5 天）', oat.rows[2].value, '2026/10/10 18:34');

  print('== 4. 巴旦木奶：+60 天（超阈值） / +7 天（恰好阈值内） ==');
  final almond = LabelTemplate.buildDairy(
    kindLabel: DairyKind.almondMilk.label,
    now: now,
    expireDate: at(now, 60),
    bestBefore: at(now, 7),
    maker: '张皓',
  );
  check('原始保质期（60 天）', almond.rows[1].value, '2026/12/04 23:59');
  check('最佳使用时间（7 天 = 阈值内）', almond.rows[2].value, '2026/10/12 18:34');

  print('== 5. 阈值边界：恰好 7 天 vs 8 天 ==');
  final d7 = LabelTemplate.buildDairy(
    kindLabel: '豆奶',
    now: now,
    expireDate: at(now, 7),
    bestBefore: at(now, 3),
    maker: '张皓',
  );
  check('7 天', d7.rows[1].value, '2026/10/12 18:34');
  final d8 = LabelTemplate.buildDairy(
    kindLabel: '豆奶',
    now: now,
    expireDate: at(now, 8),
    bestBefore: at(now, 3),
    maker: '张皓',
  );
  check('8 天', d8.rows[1].value, '2026/10/13 23:59');

  print('== 6. 出 PDF（5 个类型各一张） ==');
  final reg = File('assets/fonts/NotoSansSC-Regular.ttf').readAsBytesSync();
  final bold = File('assets/fonts/NotoSansSC-Bold.ttf').readAsBytesSync();

  final cases = <String, LabelData>{
    'milk': milk,
    'oat': oat,
    'almond': almond,
    'soy': LabelTemplate.buildDairy(
      kindLabel: DairyKind.soyMilk.label,
      now: now,
      expireDate: at(now, 7),
      bestBefore: at(now, 3),
      maker: '张皓',
    ),
    'high_protein': LabelTemplate.buildDairy(
      kindLabel: DairyKind.highProteinMilk.label,
      now: now,
      expireDate: at(now, 7),
      bestBefore: at(now, 3),
      maker: '张皓',
    ),
  };
  for (final e in cases.entries) {
    final pdf = await buildLabelPdf(
      e.value,
      fontRegular: reg,
      fontBold: bold,
    );
    final f = File('$outDir/${e.key}.pdf');
    f.writeAsBytesSync(pdf);
    print('  已写出 ${f.path} （${pdf.length} 字节）');
  }

  print('');
  print('通过 $_pass 项，失败 $_fail 项');
  if (_fail > 0) throw StateError('校验未通过');
}

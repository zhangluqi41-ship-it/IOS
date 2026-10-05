// 纯 Dart 逻辑校验：康普茶一发 / 二维码解析 / 二发时间规则。
// 运行： dart run tool/verify_kombucha.dart
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

void main() {
  final now = DateTime(2026, 10, 5, 15, 30, 20);

  print('== 1. 康普茶一发 ==');
  final first = LabelTemplate.buildKombuchaFirst(
    variety: '红茶',
    now: now,
    maker: '张皓',
  );
  check('标题', first.title, '康普茶-红茶');
  check('制备时间', first.rows[0].value, '2026/10/05 15:30');
  check('完成时间', first.rows[1].value, '2026/10/12 15:30');
  check('最佳使用时间', first.rows[2].value, '2026/11/04 15:30');
  print('  二维码内容 = ${first.qrText}');

  print('== 2. 二维码解析（一发） ==');
  final parsed = LabelTemplate.parseKombuchaQr(first.qrText);
  check('解析成功', parsed != null, true);
  if (parsed != null) {
    check('标题', parsed.title, '康普茶-红茶');
    check('茶叶品种', parsed.variety, '红茶');
    check('制备时间', parsed.prepared, DateTime(2026, 10, 5, 15, 30));
    check('完成时间', parsed.finished, DateTime(2026, 10, 12, 15, 30));
    check('最佳使用时间', parsed.bestBefore, DateTime(2026, 11, 4, 15, 30));
    check('制作人', parsed.maker, '张皓');
  }

  print('== 3. 非康普茶二维码应解析失败 ==');
  check('通用效期二维码', LabelTemplate.parseKombuchaQr('杨桃菠萝浓缩汁开封时间：2026/10/05 15:30原始保质期：2027/01/05 23:59最佳使用时间：2026/11/05 23:59制作人：张皓'), null);
  check('随机文本', LabelTemplate.parseKombuchaQr('https://example.com'), null);

  print('== 4. 康普茶二发 ==');
  final scanAt = DateTime(2026, 10, 12, 9, 15, 0);
  final second = LabelTemplate.buildKombuchaSecond(
    firstTitle: parsed!.title,
    fruit: '草莓',
    now: scanAt,
    firstFinished: parsed.finished,
    firstBestBefore: parsed.bestBefore,
    maker: parsed.maker,
  );
  check('标题', second.title, '康普茶-红茶-草莓');
  check('制备时间（扫码那一刻）', second.rows[0].value, '2026/10/12 09:15');
  check('完成时间（一发完成 +3 天）', second.rows[1].value, '2026/10/15 15:30');
  check('最佳使用时间（沿一发）', second.rows[2].value, '2026/11/04 15:30');
  print('  二维码内容 = ${second.qrText}');

  print('== 5. 边界：跨月 / 闰年 ==');
  final n2 = DateTime(2026, 12, 30, 8, 0);
  final f2 = LabelTemplate.buildKombuchaFirst(
    variety: '乌龙',
    now: n2,
    maker: '张三',
  );
  check('完成时间(+7d 跨年)', f2.rows[1].value, '2027/01/06 08:00');
  check('最佳使用时间(+30d 跨年)', f2.rows[2].value, '2027/01/29 08:00');
  check('标题自动补前缀', LabelTemplate.kombuchaTitle('康普茶-乌龙'), '康普茶-乌龙');

  print('');
  print('通过 $_pass 项，失败 $_fail 项');
  if (_fail > 0) throw StateError('校验未通过');
}

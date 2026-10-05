import 'label_renderer.dart';

/// 扫描「康普茶一发」二维码后解析出来的数据。
class KombuchaFirstLabel {
  const KombuchaFirstLabel({
    required this.title,
    required this.prepared,
    required this.finished,
    required this.bestBefore,
    required this.maker,
  });

  /// 一发标题，形如「康普茶-红茶」
  final String title;
  final DateTime prepared;
  final DateTime finished;
  final DateTime bestBefore;

  /// 制作人姓名（已去掉「制作人：」前缀；可能为空）
  final String maker;

  /// 茶叶品种，如「红茶」（取标题里第一个「-」之后的部分）
  String get variety {
    final i = title.indexOf('-');
    return i >= 0 ? title.substring(i + 1) : title;
  }
}

/// 奶制品类型 → 该类型的推荐效期（天）。
///
/// 规则来源（用户定稿 2026-10-05）：
/// - 牛奶 / 高蛋白牛奶 / 豆奶：原始保质期 **+7 天**、最佳使用时间 **+3 天**
/// - 燕麦奶                  ：原始保质期 **+45 天**、最佳使用时间 **+5 天**
/// - 巴旦木奶                ：原始保质期 **+60 天**、最佳使用时间 **+7 天**
///
/// 这两个天数**不是自动写入的默认值**，而是「快捷按钮」里主推的那一项：
/// 页面默认仍按「当天」起步，用户点一下就把对应天数加到当天上。
enum DairyKind {
  milk('牛奶', 7, 3),
  highProteinMilk('高蛋白牛奶', 7, 3),
  soyMilk('豆奶', 7, 3),
  oatMilk('燕麦奶', 45, 5),
  almondMilk('巴旦木奶', 60, 7);

  const DairyKind(this.label, this.expireDays, this.bestDays);

  /// 显示名（同时也是标签标题）
  final String label;

  /// 原始保质期的推荐天数
  final int expireDays;

  /// 最佳使用时间的推荐天数
  final int bestDays;

  /// 快捷按钮文案：距今天的天数 → `+7 天` / `+45 天`
  static String offsetLabel(int days) => '+$days 天';
}

/// 时间字段规则与模板装配。
///
/// 规则来源（项目定稿，2026-10-05 修订）：
///
/// 【通用效期】
/// - 标题        → 用户输入
/// - 开封时间    → 当前时间 now（日期 + 时刻）
/// - 原始保质期  → 用户填写日期；**距今天 ≤7 天**时刻取 now，**>7 天**取 23:59
/// - 最佳使用时间→ 用户填写日期；**与原始保质期同一规则**（≤7 天取 now，>7 天取 23:59）
///
/// 【奶制品】
/// - 标题        → 奶制品类型名（牛奶 / 高蛋白牛奶 / 燕麦奶 / 巴旦木奶 / 豆奶）
/// - 开封时间    → 当前时间 now
/// - 原始保质期  → 用户填写日期（快捷按钮按 [DairyKind] 主推 +N 天）；阈值规则同通用
/// - 最佳使用时间→ 用户填写日期（快捷按钮按 [DairyKind] 主推 +M 天）；阈值规则同通用
///
/// 【康普茶一发】
/// - 标题        → `康普茶-{茶叶品种}`（用户只填品种，如「红茶」）
/// - 制备时间    → 当前时间 now
/// - 完成时间    → now + 7 天
/// - 最佳使用时间→ now + 30 天
/// （三个时间全部自动，无需手填）
///
/// 【康普茶二发】（扫描一发二维码得到）
/// - 标题        → `{一发标题}-{水果}`，如「康普茶-红茶-草莓」
/// - 制备时间    → 扫码那一刻 now
/// - 完成时间    → 一发完成时间 + 3 天
/// - 最佳使用时间→ 与一发完全一致
///
/// 公共项：左黑条 = 打印当天 星期/中文日/英文缩写；右黑条 = 打印当时 HH:MM。
class LabelTemplate {
  const LabelTemplate._();

  /// 日期类字段的 23:59 阈值：距今天**超过**该天数用 23:59，否则用当前时刻。
  /// 同时适用于「原始保质期」与「最佳使用时间」两个字段。
  static const int endOfDayThresholdDays = 7;

  /// 康普茶一发：完成时间距制备时间的天数
  static const int kombuchaDoneDays = 7;

  /// 康普茶一发：最佳使用时间距制备时间的天数
  static const int kombuchaBestDays = 30;

  /// 康普茶二发：完成时间距一发完成时间的天数
  static const int kombuchaSecondDoneDays = 3;

  /// 康普茶标题前缀
  static const String kombuchaPrefix = '康普茶';

  static const List<String> _weekCn = ['日', '一', '二', '三', '四', '五', '六'];
  static const List<String> _weekEn = [
    'Sun',
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
  ];

  static String _p2(int v) => v.toString().padLeft(2, '0');

  /// yyyy/MM/dd
  static String fmtDate(DateTime t) =>
      '${t.year}/${_p2(t.month)}/${_p2(t.day)}';

  /// yyyy/MM/dd HH:mm（取 [t] 的日期与时刻）
  static String fmtDateTime(DateTime t) =>
      '${fmtDate(t)} ${_p2(t.hour)}:${_p2(t.minute)}';

  /// [date] 的日期 + [time] 的时刻 → yyyy/MM/dd HH:mm
  static String fmtDateAt(DateTime date, DateTime time) =>
      '${fmtDate(date)} ${_p2(time.hour)}:${_p2(time.minute)}';

  /// yyyy/MM/dd 23:59 —— 保质期类字段收尾时刻
  static String fmtDateEndOfDay(DateTime t) => '${fmtDate(t)} 23:59';

  /// HH:MM（不显示秒）
  static String fmtTime(DateTime t) => '${_p2(t.hour)}:${_p2(t.minute)}';

  /// [date] 是否落在**阈值内**（距 [now] 当天 ≤ [endOfDayThresholdDays] 个自然日）。
  /// 按**自然日差**比较，不受时刻影响。
  static bool isWithinThreshold(DateTime now, DateTime date) {
    final today = DateTime(now.year, now.month, now.day);
    final end = DateTime(date.year, date.month, date.day);
    return end.difference(today).inDays <= endOfDayThresholdDays;
  }

  /// 日期类字段取值（原始保质期 / 最佳使用时间共用）：
  /// 阈值内 → [date] 的日期 + 当前时刻；超过阈值 → [date] 的日期 + 23:59。
  static String fmtDateByThreshold(DateTime now, DateTime date) =>
      isWithinThreshold(now, date)
      ? fmtDateAt(date, now)
      : fmtDateEndOfDay(date);

  static String _weekdayCn(DateTime t) => _weekCn[t.weekday % 7];
  static String _weekdayEn(DateTime t) => _weekEn[t.weekday % 7];

  // -------------------------------------------------------------------------
  // 通用效期
  // -------------------------------------------------------------------------

  /// 通用模板：开封=now；原始保质期与最佳使用时间**共用阈值规则**
  /// （距今天 ≤7 自然日 → 当前时刻；>7 天 → 23:59）。
  static LabelData buildGeneric({
    required String title,
    required DateTime now,
    required DateTime expireDate,
    required DateTime bestBefore,
    required String maker,
  }) {
    return LabelData(
      title: title,
      rows: [
        LabelRow('开封时间：', fmtDateTime(now)),
        LabelRow('原始保质期：', fmtDateByThreshold(now, expireDate)),
        LabelRow('最佳使用时间：', fmtDateByThreshold(now, bestBefore)),
      ],
      weekdayCn: _weekdayCn(now),
      weekdayEn: _weekdayEn(now),
      rightText: fmtTime(now),
      maker: '制作人：$maker',
    );
  }

  // -------------------------------------------------------------------------
  // 奶制品
  // -------------------------------------------------------------------------

  /// 奶制品：标题 = 类型名；开封 = now；两个日期字段都由用户填/选，
  /// 阈值规则与通用模板完全一致（≤7 天取当前时刻，>7 天取 23:59）。
  static LabelData buildDairy({
    required String kindLabel,
    required DateTime now,
    required DateTime expireDate,
    required DateTime bestBefore,
    required String maker,
  }) {
    return LabelData(
      title: kindLabel,
      rows: [
        LabelRow('开封时间：', fmtDateTime(now)),
        LabelRow('原始保质期：', fmtDateByThreshold(now, expireDate)),
        LabelRow('最佳使用时间：', fmtDateByThreshold(now, bestBefore)),
      ],
      weekdayCn: _weekdayCn(now),
      weekdayEn: _weekdayEn(now),
      rightText: fmtTime(now),
      maker: '制作人：$maker',
    );
  }

  // -------------------------------------------------------------------------
  // 康普茶
  // -------------------------------------------------------------------------

  /// 把用户填的「茶叶品种」补成完整标题：填「红茶」→「康普茶-红茶」。
  /// 若用户已经自己带了「康普茶」前缀则原样保留。
  static String kombuchaTitle(String variety) {
    final v = variety.trim();
    return v.startsWith(kombuchaPrefix) ? v : '$kombuchaPrefix-$v';
  }

  /// 康普茶一发：制备 = now，完成 = now + 7 天，最佳使用 = now + 30 天。
  /// 三个时间全部自动，界面不提供日期选择。
  static LabelData buildKombuchaFirst({
    required String variety,
    required DateTime now,
    required String maker,
  }) {
    final done = now.add(const Duration(days: kombuchaDoneDays));
    final best = now.add(const Duration(days: kombuchaBestDays));
    return LabelData(
      title: kombuchaTitle(variety),
      rows: [
        LabelRow('制备时间：', fmtDateTime(now)),
        LabelRow('完成时间：', fmtDateTime(done)),
        LabelRow('最佳使用时间：', fmtDateTime(best)),
      ],
      weekdayCn: _weekdayCn(now),
      weekdayEn: _weekdayEn(now),
      rightText: fmtTime(now),
      maker: '制作人：$maker',
    );
  }

  /// 康普茶二发：制备 = 扫码那一刻，完成 = 一发完成 + 3 天，最佳使用 = 沿一发。
  static LabelData buildKombuchaSecond({
    required String firstTitle,
    required String fruit,
    required DateTime now,
    required DateTime firstFinished,
    required DateTime firstBestBefore,
    required String maker,
  }) {
    final done = firstFinished.add(
      const Duration(days: kombuchaSecondDoneDays),
    );
    return LabelData(
      title: '$firstTitle-${fruit.trim()}',
      rows: [
        LabelRow('制备时间：', fmtDateTime(now)),
        LabelRow('完成时间：', fmtDateTime(done)),
        LabelRow('最佳使用时间：', fmtDateTime(firstBestBefore)),
      ],
      weekdayCn: _weekdayCn(now),
      weekdayEn: _weekdayEn(now),
      rightText: fmtTime(now),
      maker: '制作人：$maker',
    );
  }

  // -------------------------------------------------------------------------
  // 二维码解析
  // -------------------------------------------------------------------------

  /// 二维码内容 = 页面全部文字顺序拼接（无分隔符），例如：
  /// `康普茶-红茶制备时间：2026/10/05 15:30完成时间：2026/10/12 15:30`
  /// `最佳使用时间：2026/11/04 15:30制作人：张皓`
  ///
  /// 按固定标签词切分；解析失败或不是康普茶标签时返回 null。
  static final RegExp _kombuchaQrRe = RegExp(
    r'^(?<title>.+?)制备时间：(?<prep>\d{4}/\d{2}/\d{2} \d{2}:\d{2})'
    r'完成时间：(?<done>\d{4}/\d{2}/\d{2} \d{2}:\d{2})'
    r'最佳使用时间：(?<best>\d{4}/\d{2}/\d{2} \d{2}:\d{2})'
    r'制作人：(?<maker>.*)$',
  );

  static DateTime? _parseDate(String s) {
    final m = RegExp(r'^(\d{4})/(\d{2})/(\d{2}) (\d{2}):(\d{2})$')
        .firstMatch(s);
    if (m == null) return null;
    return DateTime(
      int.parse(m[1]!),
      int.parse(m[2]!),
      int.parse(m[3]!),
      int.parse(m[4]!),
      int.parse(m[5]!),
    );
  }

  /// 解析康普茶（一发）标签的二维码文本；不是康普茶标签时返回 null。
  static KombuchaFirstLabel? parseKombuchaQr(String raw) {
    final text = raw.trim();
    final m = _kombuchaQrRe.firstMatch(text);
    if (m == null) return null;
    final title = m.namedGroup('title')!.trim();
    if (!title.startsWith(kombuchaPrefix)) return null;
    final prep = _parseDate(m.namedGroup('prep')!);
    final done = _parseDate(m.namedGroup('done')!);
    final best = _parseDate(m.namedGroup('best')!);
    if (prep == null || done == null || best == null) return null;
    return KombuchaFirstLabel(
      title: title,
      prepared: prep,
      finished: done,
      bestBefore: best,
      maker: m.namedGroup('maker')!.trim(),
    );
  }
}

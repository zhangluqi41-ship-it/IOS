import 'package:flutter/material.dart';

import 'label_pdf.dart';
import 'label_template.dart';
import 'nav.dart';
import 'prefs.dart';
import 'ui_kit.dart';

// ===========================================================================
// 二级页：通用效期
// ===========================================================================

/// 通用效期输入页。
///
/// 刻意**不给任何默认内容**：标题留空、日期默认当天、制作人沿用上一次填的。
class GenericTemplatePage extends StatefulWidget {
  const GenericTemplatePage({super.key});

  @override
  State<GenericTemplatePage> createState() => _GenericTemplatePageState();
}

class _GenericTemplatePageState extends State<GenericTemplatePage> {
  final _titleCtrl = TextEditingController();
  late final TextEditingController _makerCtrl = TextEditingController(
    text: AppPrefs.lastMaker,
  );

  /// 日期默认给「当天」——不做任何猜测性的顺延。
  DateTime _expireDate = _today();
  DateTime _bestDate = _today();
  bool _busy = false;

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  static DateTime _addDays(DateTime d, int days) =>
      DateTime(d.year, d.month, d.day).add(Duration(days: days));

  static DateTime _addMonths(DateTime d, int m) =>
      DateTime(d.year, d.month + m, d.day);

  static DateTime _addYears(DateTime d, int y) =>
      DateTime(d.year + y, d.month, d.day);

  @override
  void dispose() {
    _titleCtrl.dispose();
    _makerCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isExpire}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isExpire ? _expireDate : _bestDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: isExpire ? '选择原始保质期' : '选择最佳使用时间',
    );
    if (picked == null) return;
    setState(() {
      if (isExpire) {
        _expireDate = picked;
      } else {
        _bestDate = picked;
      }
    });
  }

  Future<void> _generate() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先填写标题')));
      return;
    }
    final maker = _makerCtrl.text.trim().isEmpty
        ? '未署名'
        : _makerCtrl.text.trim();
    setState(() => _busy = true);
    try {
      await AppPrefs.setLastMaker(_makerCtrl.text);
      final now = DateTime.now();
      final data = LabelTemplate.buildGeneric(
        title: title,
        now: now,
        expireDate: _expireDate,
        bestBefore: _bestDate,
        maker: maker,
      );
      final bytes = await renderLabelPdf(data);
      if (!mounted) return;
      openPreview(context, bytes, labelFileName(title, now));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('生成失败：$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('通用效期'),
        centerTitle: false,
        backgroundColor: theme.colorScheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          TextField(
            controller: _titleCtrl,
            autofocus: true,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: '标题',
              hintText: '例：杨桃菠萝浓缩汁',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.label_outline),
            ),
          ),
          const SizedBox(height: 16),
          const AutoTimeBanner(
            lines: [
              '· 开封时间 = 当前时刻',
              '· 原始保质期 / 最佳使用时间 = 所选日期；'
                  '距今天 7 天内取当前时刻，超过 7 天为 23:59',
              '· 右侧竖排 = 当前时刻（HH:MM）',
            ],
          ),
          const SizedBox(height: 16),
          DateField(
            label: '原始保质期',
            value: _expireDate,
            icon: Icons.event_available_outlined,
            onTap: () => _pickDate(isExpire: true),
          ),
          _QuickDates(
            onPick: (d) => setState(() => _expireDate = d),
            presets: [
              ('今天', _today()),
              ('+7 天', _addDays(_today(), 7)),
              ('+1 月', _addMonths(_today(), 1)),
              ('+3 月', _addMonths(_today(), 3)),
              ('+6 月', _addMonths(_today(), 6)),
              ('+1 年', _addYears(_today(), 1)),
            ],
          ),
          const SizedBox(height: 10),
          DateField(
            label: '最佳使用时间',
            value: _bestDate,
            icon: Icons.schedule_outlined,
            onTap: () => _pickDate(isExpire: false),
          ),
          _QuickDates(
            onPick: (d) => setState(() => _bestDate = d),
            presets: [
              ('今天', _today()),
              ('+7 天', _addDays(_today(), 7)),
              ('+15 天', _addDays(_today(), 15)),
              ('+1 月', _addMonths(_today(), 1)),
              ('+2 月', _addMonths(_today(), 2)),
              ('+3 月', _addMonths(_today(), 3)),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _makerCtrl,
            decoration: const InputDecoration(
              labelText: '制作人',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person_outline),
              helperText: '默认沿用上一次填写的名字',
            ),
          ),
          const SizedBox(height: 28),
          GenerateButton(busy: _busy, onPressed: _generate),
          const SizedBox(height: 14),
          const FootNote(text: '标签规格 50 × 30 mm · 生成后可预览 / 打印 / 分享'),
        ],
      ),
    );
  }
}

/// 日期快捷选项：只是省事的入口，不改变「默认就是当天」的规则。
class _QuickDates extends StatelessWidget {
  const _QuickDates({
    required this.onPick,
    required this.presets,
    this.recommended,
  });

  final ValueChanged<DateTime> onPick;
  final List<(String, DateTime)> presets;

  /// 需要高亮成「主推」的快捷项文案（奶制品页按类型给出）。
  final String? recommended;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final (label, date) in presets) _chip(theme, label, date),
        ],
      ),
    );
  }

  Widget _chip(ThemeData theme, String label, DateTime date) {
    final isRec = recommended != null && label == recommended;
    return ActionChip(
      avatar: isRec
          ? Icon(Icons.star_rounded, size: 15, color: theme.colorScheme.primary)
          : null,
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isRec ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      backgroundColor: isRec
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.65)
          : null,
      side: BorderSide(
        color: isRec
            ? theme.colorScheme.primary
            : theme.colorScheme.outlineVariant,
        width: isRec ? 1.2 : 1,
      ),
      onPressed: () => onPick(date),
    );
  }
}

// ===========================================================================
// 二级页：康普茶（一发）
// ===========================================================================

/// 康普茶一发输入页。
///
/// 只填「茶叶品种」和「制作人」，三个时间全部按规则自动推算。
class KombuchaTemplatePage extends StatefulWidget {
  const KombuchaTemplatePage({super.key});

  @override
  State<KombuchaTemplatePage> createState() => _KombuchaTemplatePageState();
}

class _KombuchaTemplatePageState extends State<KombuchaTemplatePage> {
  final _varietyCtrl = TextEditingController();
  late final TextEditingController _makerCtrl = TextEditingController(
    text: AppPrefs.lastMaker,
  );

  /// 页面打开时刻，仅用于「预览」三个自动时间的取值；
  /// 真正生成时以点击「生成标签」的那一刻重算。
  final DateTime _openedAt = DateTime.now();
  bool _busy = false;

  @override
  void dispose() {
    _varietyCtrl.dispose();
    _makerCtrl.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final variety = _varietyCtrl.text.trim();
    if (variety.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先填写茶叶品种')));
      return;
    }
    final maker = _makerCtrl.text.trim().isEmpty
        ? '未署名'
        : _makerCtrl.text.trim();
    setState(() => _busy = true);
    try {
      await AppPrefs.setLastMaker(_makerCtrl.text);
      final now = DateTime.now();
      final data = LabelTemplate.buildKombuchaFirst(
        variety: variety,
        now: now,
        maker: maker,
      );
      final bytes = await renderLabelPdf(data);
      if (!mounted) return;
      openPreview(context, bytes, labelFileName(data.title, now));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('生成失败：$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final variety = _varietyCtrl.text.trim();
    final preview = LabelTemplate.buildKombuchaFirst(
      variety: variety.isEmpty ? '（茶叶品种）' : variety,
      now: _openedAt,
      maker: _makerCtrl.text.trim().isEmpty ? '未署名' : _makerCtrl.text.trim(),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('康普茶 · 一发'),
        centerTitle: false,
        backgroundColor: theme.colorScheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          TextField(
            controller: _varietyCtrl,
            autofocus: true,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: '茶叶品种',
              hintText: '例：红茶',
              helperText: '生成标题会自动补前缀：红茶 → 康普茶-红茶',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.eco_outlined),
            ),
          ),
          const SizedBox(height: 16),
          AutoTimeBanner(
            lines: [
              '· 制备时间 = 当前时刻',
              '· 完成时间 = 制备时间 + ${LabelTemplate.kombuchaDoneDays} 天',
              '· 最佳使用时间 = 制备时间 + ${LabelTemplate.kombuchaBestDays} 天',
              '以上三个时间全部自动生成，无需手填',
            ],
          ),
          const SizedBox(height: 16),
          PreviewCard(
            title: '生成预览',
            note: '实际数值以点击「生成标签」的时刻为准',
            titlePreview: preview.title,
            rows: preview.rows,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _makerCtrl,
            decoration: const InputDecoration(
              labelText: '制作人',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person_outline),
              helperText: '默认沿用上一次填写的名字',
            ),
          ),
          const SizedBox(height: 28),
          GenerateButton(busy: _busy, onPressed: _generate),
          const SizedBox(height: 14),
          const FootNote(text: '二发标签：打印后扫瓶身上的二维码，输入二发使用的水果即可自动生成'),
        ],
      ),
    );
  }
}

// ===========================================================================
// 二级页：奶制品
// ===========================================================================

/// 奶制品输入页。
///
/// 选一个奶制品类型 + 填制作人；两个日期默认当天（不预填、不猜测），
/// 快捷按钮会按所选类型主推该品类的推荐天数：
/// 牛奶 / 高蛋白牛奶 / 豆奶 → +7 天、+3 天；燕麦奶 → +45 天、+5 天；
/// 巴旦木奶 → +60 天、+7 天。
class DairyTemplatePage extends StatefulWidget {
  const DairyTemplatePage({super.key});

  @override
  State<DairyTemplatePage> createState() => _DairyTemplatePageState();
}

class _DairyTemplatePageState extends State<DairyTemplatePage> {
  DairyKind? _kind;
  late final TextEditingController _makerCtrl = TextEditingController(
    text: AppPrefs.lastMaker,
  );

  /// 与通用模板一致：默认给「当天」，不做任何猜测性顺延。
  DateTime _expireDate = _today();
  DateTime _bestDate = _today();
  bool _busy = false;

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  static DateTime _addDays(DateTime d, int days) =>
      DateTime(d.year, d.month, d.day).add(Duration(days: days));

  static DateTime _addMonths(DateTime d, int m) =>
      DateTime(d.year, d.month + m, d.day);

  /// 快捷项按文案去重，避免类型推荐值与通用档位撞车（如巴旦木奶 +7 天）。
  static List<(String, DateTime)> _dedupe(List<(String, DateTime)> src) {
    final seen = <String>{};
    final out = <(String, DateTime)>[];
    for (final e in src) {
      if (seen.add(e.$1)) out.add(e);
    }
    return out;
  }

  List<(String, DateTime)> _expirePresets() {
    final t = _today();
    final k = _kind;
    return _dedupe([
      ('今天', t),
      if (k != null)
        (DairyKind.offsetLabel(k.expireDays), _addDays(t, k.expireDays)),
      ('+1 月', _addMonths(t, 1)),
      ('+3 月', _addMonths(t, 3)),
      ('+6 月', _addMonths(t, 6)),
      ('+1 年', _addMonths(t, 12)),
    ]);
  }

  List<(String, DateTime)> _bestPresets() {
    final t = _today();
    final k = _kind;
    return _dedupe([
      ('今天', t),
      if (k != null)
        (DairyKind.offsetLabel(k.bestDays), _addDays(t, k.bestDays)),
      ('+7 天', _addDays(t, 7)),
      ('+15 天', _addDays(t, 15)),
      ('+1 月', _addMonths(t, 1)),
      ('+3 月', _addMonths(t, 3)),
    ]);
  }

  @override
  void dispose() {
    _makerCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isExpire}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isExpire ? _expireDate : _bestDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: isExpire ? '选择原始保质期' : '选择最佳使用时间',
    );
    if (picked == null) return;
    setState(() {
      if (isExpire) {
        _expireDate = picked;
      } else {
        _bestDate = picked;
      }
    });
  }

  /// 一键把两个日期都按所选类型的规则填好（仍然是可改的手填结果）。
  void _applyRule() {
    final k = _kind;
    if (k == null) return;
    final t = _today();
    setState(() {
      _expireDate = _addDays(t, k.expireDays);
      _bestDate = _addDays(t, k.bestDays);
    });
  }

  Future<void> _generate() async {
    final k = _kind;
    if (k == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先选择奶制品类型')));
      return;
    }
    final maker = _makerCtrl.text.trim().isEmpty
        ? '未署名'
        : _makerCtrl.text.trim();
    setState(() => _busy = true);
    try {
      await AppPrefs.setLastMaker(_makerCtrl.text);
      final now = DateTime.now();
      final data = LabelTemplate.buildDairy(
        kindLabel: k.label,
        now: now,
        expireDate: _expireDate,
        bestBefore: _bestDate,
        maker: maker,
      );
      final bytes = await renderLabelPdf(data);
      if (!mounted) return;
      openPreview(context, bytes, labelFileName(k.label, now));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('生成失败：$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<String> get _bannerLines {
    final k = _kind;
    if (k == null) {
      return const [
        '· 先选奶制品类型，两个日期都由你填写',
        '· 牛奶 / 高蛋白牛奶 / 豆奶：原始保质期 +7 天、最佳使用时间 +3 天',
        '· 燕麦奶：+45 天 / +5 天　·　巴旦木奶：+60 天 / +7 天',
      ];
    }
    final sameDay = k.expireDays == 7;
    return [
      '· 「${k.label}」推荐：原始保质期 +${k.expireDays} 天、最佳使用时间 +${k.bestDays} 天',
      '· 开封时间 = 生成的那一刻；距今天 ≤7 天显示具体时刻',
      '· ${sameDay ? '>7 天显示 23:59' : '+${k.expireDays} 天的原始保质期会显示为当天 23:59'}',
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final k = _kind;

    return Scaffold(
      appBar: AppBar(
        title: const Text('奶制品'),
        centerTitle: false,
        backgroundColor: theme.colorScheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          DropdownButtonFormField<DairyKind>(
            initialValue: _kind,
            isExpanded: true,
            icon: const Icon(Icons.expand_more),
            hint: Text(
              '请选择',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
            decoration: const InputDecoration(
              labelText: '奶制品类型',
              prefixIcon: Icon(Icons.local_drink_outlined),
              border: OutlineInputBorder(),
              helperText: '标签标题就用类型名，例如「燕麦奶」',
            ),
            items: [
              for (final d in DairyKind.values)
                DropdownMenuItem<DairyKind>(
                  value: d,
                  child: Text(d.label, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) => setState(() => _kind = v),
          ),
          const SizedBox(height: 16),
          AutoTimeBanner(
            lines: _bannerLines,
            action: k == null
                ? null
                : TextButton.icon(
                    onPressed: _applyRule,
                    icon: const Icon(Icons.auto_fix_high_outlined, size: 16),
                    label: const Text('按规则填两个日期'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      textStyle: const TextStyle(fontSize: 12.5),
                    ),
                  ),
          ),
          const SizedBox(height: 16),
          DateField(
            label: '原始保质期',
            value: _expireDate,
            icon: Icons.event_available_outlined,
            onTap: () => _pickDate(isExpire: true),
          ),
          _QuickDates(
            onPick: (d) => setState(() => _expireDate = d),
            presets: _expirePresets(),
            recommended: k == null ? null : DairyKind.offsetLabel(k.expireDays),
          ),
          const SizedBox(height: 10),
          DateField(
            label: '最佳使用时间',
            value: _bestDate,
            icon: Icons.schedule_outlined,
            onTap: () => _pickDate(isExpire: false),
          ),
          _QuickDates(
            onPick: (d) => setState(() => _bestDate = d),
            presets: _bestPresets(),
            recommended: k == null ? null : DairyKind.offsetLabel(k.bestDays),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _makerCtrl,
            decoration: const InputDecoration(
              labelText: '制作人',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person_outline),
              helperText: '默认沿用上一次填写的名字',
            ),
          ),
          const SizedBox(height: 28),
          GenerateButton(busy: _busy, onPressed: _generate),
          const SizedBox(height: 14),
          const FootNote(text: '标签规格 50 × 30 mm · 生成后可预览 / 打印 / 分享'),
        ],
      ),
    );
  }
}

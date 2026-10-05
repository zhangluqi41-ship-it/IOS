/// iOS 模板页 —— `templates.dart` 的 Cupertino 对位实现（需求第 3、4、7 条）。
///
/// 关键改造点：
///  * `Material` Scaffold/AppBar → `CupertinoPageScaffold` + `CupertinoNavigationBar`
///  * `DropdownButtonFormField<DairyKind>`（需求第 7 条点名的「安卓感下拉」）
///    → **`IosPickerField`**（点击弹 `CupertinoPicker` 滚轮）
///  * `showDatePicker`（安卓日历）→ **`showIosDatePicker`**（`CupertinoDatePicker` 滚轮）
///  * `ActionChip` 快捷档位 → **`IosChipRow`** Cupertino 胶囊
///  * `TextField` → **`CupertinoTextField`**（带 iOS 圆角输入框样式）
///  * `SnackBar` → **`showCupertinoDialog` / Cupertino 提示**
library;

// ⚠️ `CNToast` 只在顶层 `cupertino_native_better.dart` 里导出，
//    子层 `cupertino_native.dart` 没有 export 它。
import 'package:cupertino_native_better/cupertino_native_better.dart'
    show CNToast;
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../label_pdf.dart';
import '../label_renderer.dart';
import '../label_template.dart';
import '../prefs.dart';
import 'ios_nav.dart';
import 'ios_theme.dart';
import 'ios_widgets.dart';

// ===========================================================================
// 公共：iOS 输入框
// ===========================================================================

/// iOS 风格输入行（对应 Material 的 `TextField` + `OutlineInputBorder`）。
class _IosField extends StatelessWidget {
  const _IosField({
    required this.label,
    required this.controller,
    this.hint,
    this.icon,
    this.autofocus = false,
    this.textInputAction = TextInputAction.next,
    this.onChanged,
    this.footer,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final IconData? icon;
  final bool autofocus;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onChanged;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final Brightness b = iosBrightness(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: IosSpace.ml,
        vertical: IosSpace.m,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(
              fontSize: IosText.footnote,
              color: IosColors.secondaryLabel(b),
            ),
          ),
          const SizedBox(height: IosSpace.s),
          CupertinoTextField(
            controller: controller,
            autofocus: autofocus,
            textInputAction: textInputAction,
            onChanged: onChanged,
            padding: const EdgeInsets.symmetric(
              horizontal: IosSpace.m,
              vertical: IosSpace.smd,
            ),
            placeholder: hint,
            placeholderStyle: TextStyle(
              fontSize: IosText.body,
              color: IosColors.tertiaryLabel(b),
            ),
            style: TextStyle(
              fontSize: IosText.body,
              color: IosColors.label(b),
              letterSpacing: -0.41,
            ),
            prefix: icon == null
                ? null
                : Padding(
                    padding: const EdgeInsets.only(
                      left: IosSpace.m,
                      right: IosSpace.sm,
                    ),
                    child: Icon(icon, size: 18, color: IosColors.brand),
                  ),
            decoration: BoxDecoration(
              color: IosColors.grouped(b).withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(IosRadius.m),
            ),
          ),
          if (footer != null && footer!.isNotEmpty) ...<Widget>[
            const SizedBox(height: IosSpace.s),
            Text(
              footer!,
              style: TextStyle(
                fontSize: IosText.caption1,
                color: IosColors.tertiaryLabel(b),
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// iOS 风格提示（替代 SnackBar）。
///
/// 走 `cupertino_native_better` 的原生 toast：iOS 26 上是苹果原厂玻璃浮层，
/// 不拦截交互、不打断操作流（原来的 `CupertinoAlertDialog` 要点「好」才能继续）。
/// 失败文案自动用红色错误样式。
Future<void> showIosToast(BuildContext context, String message) {
  final bool isError = message.contains('失败') || message.contains('错误');
  if (isError) {
    CNToast.error(context: context, message: message);
  } else {
    CNToast.info(context: context, message: message);
  }
  return Future<void>.value();
}

/// 日期快捷档位的数据结构。
class _QuickPreset {
  const _QuickPreset(this.label, this.value, {this.recommended = false});

  final String label;
  final DateTime value;
  final bool recommended;
}

/// 通用快捷日期行：把若干档位渲染成 `IosChipRow`。
class _QuickDates extends StatefulWidget {
  const _QuickDates({
    required this.onPick,
    required this.presets,
  });

  final ValueChanged<DateTime> onPick;
  final List<_QuickPreset> presets;

  @override
  State<_QuickDates> createState() => _QuickDatesState();
}

class _QuickDatesState extends State<_QuickDates> {
  int _selected = -1;

  @override
  Widget build(BuildContext context) {
    final int recIndex =
        widget.presets.indexWhere((p) => p.recommended);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: IosSpace.screenH),
      child: IosChipRow(
        labels: widget.presets.map((p) => p.label).toList(),
        selectedIndex: _selected,
        recommendedIndex: recIndex >= 0 ? recIndex : null,
        onSelected: (int i) {
          setState(() => _selected = i);
          iosHaptic(HapticFeedbackType.selection);
          widget.onPick(widget.presets[i].value);
        },
      ),
    );
  }
}

// 日期工具 -----------------------------------------------------------------

DateTime _today() {
  final DateTime n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

DateTime _addDays(DateTime d, int days) =>
    DateTime(d.year, d.month, d.day).add(Duration(days: days));

DateTime _addMonths(DateTime d, int m) => DateTime(d.year, d.month + m, d.day);

/// 通用效期的两个快捷档位组。
///
/// 需求（2026-10-05 第 2 轮）模板二级菜单第 2 条：
/// 「删除全部的今天，保留 +7、+15、+1 个月，再久就没有意义了」。
/// → 两个日期都精简成同一组三档，并删掉「今天」。
List<_QuickPreset> _expirePresets(DateTime t) => <_QuickPreset>[
  _QuickPreset('+7 天', _addDays(t, 7), recommended: true),
  _QuickPreset('+15 天', _addDays(t, 15)),
  _QuickPreset('+1 个月', _addMonths(t, 1)),
];

List<_QuickPreset> _bestPresets(DateTime t) => <_QuickPreset>[
  _QuickPreset('+7 天', _addDays(t, 7)),
  _QuickPreset('+15 天', _addDays(t, 15), recommended: true),
  _QuickPreset('+1 个月', _addMonths(t, 1)),
];

// ===========================================================================
// 二级页：通用效期
// ===========================================================================

class IosGenericTemplatePage extends StatefulWidget {
  const IosGenericTemplatePage({super.key});

  @override
  State<IosGenericTemplatePage> createState() => _IosGenericTemplatePageState();
}

class _IosGenericTemplatePageState extends State<IosGenericTemplatePage> {
  final TextEditingController _titleCtrl = TextEditingController();
  late final TextEditingController _makerCtrl = TextEditingController(
    text: AppPrefs.lastMaker,
  );

  DateTime _expireDate = _today();
  DateTime _bestDate = _today();
  bool _busy = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _makerCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isExpire}) async {
    final DateTime? picked = await showIosDatePicker(
      context,
      initial: isExpire ? _expireDate : _bestDate,
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isExpire) {
        _expireDate = picked;
      } else {
        _bestDate = picked;
      }
    });
  }

  Future<void> _generate() async {
    final String title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      await showIosToast(context, '请先填写标题');
      return;
    }
    final String maker =
        _makerCtrl.text.trim().isEmpty ? '未署名' : _makerCtrl.text.trim();
    setState(() => _busy = true);
    try {
      await AppPrefs.setLastMaker(_makerCtrl.text);
      final DateTime now = DateTime.now();
      final LabelData data = LabelTemplate.buildGeneric(
        title: title,
        now: now,
        expireDate: _expireDate,
        bestBefore: _bestDate,
        maker: maker,
      );
      final Uint8List bytes = await renderLabelPdf(data);
      if (!mounted) return;
      await iosOpenPreview(context, bytes, labelFileName(title, now));
    } catch (e) {
      if (!mounted) return;
      await showIosToast(context, '生成失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = iosBrightness(context);
    final DateTime t = _today();

    return CupertinoPageScaffold(
      backgroundColor: IosColors.grouped(b),
      navigationBar: CupertinoNavigationBar(
        middle: const Text('通用效期', style: IosText.navTitle),
        backgroundColor: IosColors.grouped(b).withValues(alpha: 0.92),
        border: Border(
          bottom: BorderSide(color: IosColors.separator(b), width: 0.5),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: kIosListPadding,
          children: <Widget>[
            IosListGroup(
              children: <Widget>[
                _IosField(
                  label: '标题',
                  controller: _titleCtrl,
                  hint: '例：杨桃菠萝浓缩汁',
                  icon: CupertinoIcons.tag,
                  autofocus: true,
                ),
                _IosRowDivider(b: b),
                _IosField(
                  label: '制作人',
                  controller: _makerCtrl,
                  hint: '例：四野',
                  icon: CupertinoIcons.person,
                  textInputAction: TextInputAction.done,
                  footer: '会记住上次填写的名字',
                ),
              ],
            ),
            const SizedBox(height: IosSpace.lg),
            const IosBanner(
              lines: <String>[
                '· 开封时间 = 当前时刻',
                '· 原始保质期 / 最佳使用时间 = 所选日期；距今天 7 天内取当前时刻，超过 7 天为 23:59',
                '· 右侧竖排 = 当前时刻（HH:MM）',
              ],
            ),
            const SizedBox(height: IosSpace.lg),
            // 需求（2026-10-05 第 2 轮）模板二级菜单第 1 条：
            // 「奶制品中的日期是统一一起的，但通用效期就分开了」→
            // 参照奶制品，把「原始保质期」「最佳使用时间」合并进同一个「日期」组，
            // 两行之间用分隔线隔开，风格统一。
            IosListGroup(
              header: IosSectionHeader(
                title: '日期',
                padding: const EdgeInsets.fromLTRB(
                  IosSpace.xs,
                  0,
                  IosSpace.xs,
                  IosSpace.sm,
                ),
              ),
              children: <Widget>[
                IosDateField(
                  label: '原始保质期',
                  value: _expireDate,
                  icon: CupertinoIcons.calendar,
                  onTap: () => _pickDate(isExpire: true),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    IosSpace.ml,
                    IosSpace.xs,
                    IosSpace.ml,
                    IosSpace.m,
                  ),
                  child: _QuickDates(
                    presets: _expirePresets(t),
                    onPick: (DateTime d) => setState(() => _expireDate = d),
                  ),
                ),
                _IosRowDivider(b: b),
                IosDateField(
                  label: '最佳使用时间',
                  value: _bestDate,
                  icon: CupertinoIcons.bell,
                  onTap: () => _pickDate(isExpire: false),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    IosSpace.ml,
                    IosSpace.xs,
                    IosSpace.ml,
                    IosSpace.m,
                  ),
                  child: _QuickDates(
                    presets: _bestPresets(t),
                    onPick: (DateTime d) => setState(() => _bestDate = d),
                  ),
                ),
              ],
            ),
            const SizedBox(height: IosSpace.xl),
            IosPrimaryButton(busy: _busy, onPressed: _generate),
            const SizedBox(height: IosSpace.lg),
            const IosFootNote(text: '标签规格 50 × 30 mm · 生成后可预览 / 打印 / 分享'),
            const SizedBox(height: IosSize.tabBarInset),
          ],
        ),
      ),
    );
  }
}

/// 分组内的分隔线。
class _IosRowDivider extends StatelessWidget {
  const _IosRowDivider({required this.b});

  final Brightness b;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: IosSpace.ml),
      child: Container(height: 0.5, color: IosColors.separator(b)),
    );
  }
}

// ===========================================================================
// 二级页：奶制品
// ===========================================================================

class IosDairyTemplatePage extends StatefulWidget {
  const IosDairyTemplatePage({super.key});

  @override
  State<IosDairyTemplatePage> createState() => _IosDairyTemplatePageState();
}

class _IosDairyTemplatePageState extends State<IosDairyTemplatePage> {
  late final TextEditingController _makerCtrl = TextEditingController(
    text: AppPrefs.lastMaker,
  );

  DairyKind? _kind;
  late DateTime _expireDate = _today();
  late DateTime _bestDate = _today();
  bool _busy = false;

  @override
  void dispose() {
    _makerCtrl.dispose();
    super.dispose();
  }

  /// 按类型一键填入推荐的两个日期。
  void _applyRule() {
    final DairyKind? k = _kind;
    if (k == null) return;
    final DateTime t = _today();
    setState(() {
      _expireDate = _addDays(t, k.expireDays);
      _bestDate = _addDays(t, k.bestDays);
    });
    iosHaptic(HapticFeedbackType.light);
  }

  List<_QuickPreset> _expirePresets() {
    final DateTime t = _today();
    final DairyKind? k = _kind;
    final List<_QuickPreset> raw = <_QuickPreset>[
      _QuickPreset('+1 天', _addDays(t, 1)),
      _QuickPreset('+3 天', _addDays(t, 3)),
      _QuickPreset('+7 天', _addDays(t, 7)),
      _QuickPreset('+15 天', _addDays(t, 15)),
      _QuickPreset('+30 天', _addDays(t, 30)),
      _QuickPreset('+45 天', _addDays(t, 45)),
      _QuickPreset('+60 天', _addDays(t, 60)),
      _QuickPreset('+90 天', _addDays(t, 90)),
    ];
    if (k == null) return raw;
    // 按文案去重后标记推荐项（巴旦木奶的 +60 天可能与档位撞车）
    final String rec = '+${k.expireDays} 天';
    final Set<String> seen = <String>{};
    final List<_QuickPreset> out = <_QuickPreset>[];
    for (final _QuickPreset p in raw) {
      if (!seen.add(p.label)) continue;
      out.add(
        _QuickPreset(p.label, p.value, recommended: p.label == rec),
      );
    }
    return out;
  }

  List<_QuickPreset> _bestPresets() {
    final DateTime t = _today();
    final DairyKind? k = _kind;
    final List<_QuickPreset> raw = <_QuickPreset>[
      _QuickPreset('+1 天', _addDays(t, 1)),
      _QuickPreset('+3 天', _addDays(t, 3)),
      _QuickPreset('+5 天', _addDays(t, 5)),
      _QuickPreset('+7 天', _addDays(t, 7)),
      _QuickPreset('+15 天', _addDays(t, 15)),
      _QuickPreset('+30 天', _addDays(t, 30)),
    ];
    if (k == null) return raw;
    final String rec = '+${k.bestDays} 天';
    final Set<String> seen = <String>{};
    final List<_QuickPreset> out = <_QuickPreset>[];
    for (final _QuickPreset p in raw) {
      if (!seen.add(p.label)) continue;
      out.add(
        _QuickPreset(p.label, p.value, recommended: p.label == rec),
      );
    }
    return out;
  }

  List<String> get _bannerLines {
    final DairyKind? k = _kind;
    if (k == null) {
      return const <String>[
        '· 开封时间 = 当前时刻',
        '· 原始保质期与最佳使用时间都需要手填',
        '· 选好类型后可点「按推荐填日期」一键填入',
      ];
    }
    final bool sameDay = k.expireDays == 7;
    return <String>[
      '· 开封时间 = 当前时刻',
      '· 原始保质期默认推荐 +${k.expireDays} 天',
      '· 最佳使用时间默认推荐 +${k.bestDays} 天'
          '${sameDay ? '；≤7 天会显示具体时刻' : '；>7 天显示 23:59'}',
    ];
  }

  Future<void> _pickDate({required bool isExpire}) async {
    final DateTime? picked = await showIosDatePicker(
      context,
      initial: isExpire ? _expireDate : _bestDate,
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isExpire) {
        _expireDate = picked;
      } else {
        _bestDate = picked;
      }
    });
  }

  Future<void> _generate() async {
    final DairyKind? k = _kind;
    if (k == null) {
      await showIosToast(context, '请先选择奶制品类型');
      return;
    }
    final String maker =
        _makerCtrl.text.trim().isEmpty ? '未署名' : _makerCtrl.text.trim();
    setState(() => _busy = true);
    try {
      await AppPrefs.setLastMaker(_makerCtrl.text);
      final DateTime now = DateTime.now();
      final LabelData data = LabelTemplate.buildDairy(
        kindLabel: k.label,
        now: now,
        expireDate: _expireDate,
        bestBefore: _bestDate,
        maker: maker,
      );
      final Uint8List bytes = await renderLabelPdf(data);
      if (!mounted) return;
      await iosOpenPreview(context, bytes, labelFileName(k.label, now));
    } catch (e) {
      if (!mounted) return;
      await showIosToast(context, '生成失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = iosBrightness(context);

    return CupertinoPageScaffold(
      backgroundColor: IosColors.grouped(b),
      navigationBar: CupertinoNavigationBar(
        middle: const Text('奶制品', style: IosText.navTitle),
        backgroundColor: IosColors.grouped(b).withValues(alpha: 0.92),
        border: Border(
          bottom: BorderSide(color: IosColors.separator(b), width: 0.5),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: kIosListPadding,
          children: <Widget>[
            IosListGroup(
              children: <Widget>[
                // ★ 需求第 7 条：这里原本是 Material 的 DropdownButtonFormField，
                //   换成 iOS 滚轮选择器。
                IosPickerField<DairyKind>(
                  label: '奶制品类型',
                  value: _kind,
                  items: DairyKind.values,
                  itemLabel: (DairyKind k) => k.label,
                  icon: CupertinoIcons.lab_flask,
                  placeholder: '请选择',
                  helper: '标签标题就用类型名，例如「燕麦奶」',
                  onChanged: (DairyKind k) => setState(() => _kind = k),
                ),
                if (_kind != null) ...<Widget>[
                  _IosRowDivider(b: b),
                  IosListRow(
                    title: '按推荐填日期',
                    subtitle:
                        '原始保质期 +${_kind!.expireDays} 天 · 最佳使用时间 +${_kind!.bestDays} 天',
                    leadingIcon: CupertinoIcons.wand_stars,
                    showChevron: false,
                    showDivider: false,
                    onTap: _applyRule,
                  ),
                ],
              ],
            ),
            const SizedBox(height: IosSpace.lg),
            IosBanner(lines: _bannerLines),
            const SizedBox(height: IosSpace.lg),
            IosListGroup(
              header: IosSectionHeader(
                title: '日期',
                padding: const EdgeInsets.fromLTRB(
                  IosSpace.xs,
                  0,
                  IosSpace.xs,
                  IosSpace.sm,
                ),
              ),
              children: <Widget>[
                IosDateField(
                  label: '原始保质期（开封后）',
                  value: _expireDate,
                  icon: CupertinoIcons.calendar,
                  onTap: () => _pickDate(isExpire: true),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    IosSpace.ml,
                    IosSpace.xs,
                    IosSpace.ml,
                    IosSpace.m,
                  ),
                  child: _QuickDates(
                    presets: _expirePresets(),
                    onPick: (DateTime d) => setState(() => _expireDate = d),
                  ),
                ),
                _IosRowDivider(b: b),
                IosDateField(
                  label: '最佳使用时间',
                  value: _bestDate,
                  icon: CupertinoIcons.bell,
                  onTap: () => _pickDate(isExpire: false),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    IosSpace.ml,
                    IosSpace.xs,
                    IosSpace.ml,
                    IosSpace.m,
                  ),
                  child: _QuickDates(
                    presets: _bestPresets(),
                    onPick: (DateTime d) => setState(() => _bestDate = d),
                  ),
                ),
              ],
            ),
            const SizedBox(height: IosSpace.lg),
            IosListGroup(
              children: <Widget>[
                _IosField(
                  label: '制作人',
                  controller: _makerCtrl,
                  hint: '例：四野',
                  icon: CupertinoIcons.person,
                  textInputAction: TextInputAction.done,
                  footer: '会记住上次填写的名字',
                ),
              ],
            ),
            const SizedBox(height: IosSpace.xl),
            IosPrimaryButton(busy: _busy, onPressed: _generate),
            const SizedBox(height: IosSpace.lg),
            const IosFootNote(text: '标签三行 = 开封时间 / 原始保质期 / 最佳使用时间'),
            const SizedBox(height: IosSize.tabBarInset),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// 二级页：康普茶（一发）
// ===========================================================================

/// 康普茶一发页 —— 只填茶叶品种 + 制作人，三个时间全自动推算。
class IosKombuchaTemplatePage extends StatefulWidget {
  const IosKombuchaTemplatePage({super.key});

  @override
  State<IosKombuchaTemplatePage> createState() =>
      _IosKombuchaTemplatePageState();
}

class _IosKombuchaTemplatePageState extends State<IosKombuchaTemplatePage> {
  final TextEditingController _varietyCtrl = TextEditingController();
  late final TextEditingController _makerCtrl = TextEditingController(
    text: AppPrefs.lastMaker,
  );

  /// 页面打开时刻：仅用于预览区展示，真正生成时按点击那刻重算。
  final DateTime _openedAt = DateTime.now();
  bool _busy = false;

  @override
  void dispose() {
    _varietyCtrl.dispose();
    _makerCtrl.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final String variety = _varietyCtrl.text.trim();
    if (variety.isEmpty) {
      await showIosToast(context, '请先填写茶叶品种');
      return;
    }
    final String maker =
        _makerCtrl.text.trim().isEmpty ? '未署名' : _makerCtrl.text.trim();
    setState(() => _busy = true);
    try {
      await AppPrefs.setLastMaker(_makerCtrl.text);
      final DateTime now = DateTime.now();
      final LabelData data = LabelTemplate.buildKombuchaFirst(
        variety: variety,
        now: now,
        maker: maker,
      );
      final Uint8List bytes = await renderLabelPdf(data);
      if (!mounted) return;
      await iosOpenPreview(context, bytes, labelFileName(data.title, now));
    } catch (e) {
      if (!mounted) return;
      await showIosToast(context, '生成失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = iosBrightness(context);
    final String variety = _varietyCtrl.text.trim();
    final String maker =
        _makerCtrl.text.trim().isEmpty ? '未署名' : _makerCtrl.text.trim();

    final LabelData preview = LabelTemplate.buildKombuchaFirst(
      variety: variety.isEmpty ? '（茶叶品种）' : variety,
      now: _openedAt,
      maker: maker,
    );

    return CupertinoPageScaffold(
      backgroundColor: IosColors.grouped(b),
      navigationBar: CupertinoNavigationBar(
        middle: const Text('康普茶 · 一发', style: IosText.navTitle),
        backgroundColor: IosColors.grouped(b).withValues(alpha: 0.92),
        border: Border(
          bottom: BorderSide(color: IosColors.separator(b), width: 0.5),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: kIosListPadding,
          children: <Widget>[
            IosListGroup(
              children: <Widget>[
                _IosField(
                  label: '茶叶品种',
                  controller: _varietyCtrl,
                  hint: '例：红茶',
                  icon: CupertinoIcons.leaf_arrow_circlepath,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  footer: '标题会自动拼成「康普茶-品种」',
                ),
                _IosRowDivider(b: b),
                _IosField(
                  label: '制作人',
                  controller: _makerCtrl,
                  hint: '例：四野',
                  icon: CupertinoIcons.person,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => setState(() {}),
                  footer: '会记住上次填写的名字',
                ),
              ],
            ),
            const SizedBox(height: IosSpace.lg),
            const IosBanner(
              lines: <String>[
                '· 制备时间 = 生成那一刻',
                '· 完成时间 = 制备 + 7 天',
                '· 最佳使用时间 = 制备 + 30 天',
              ],
            ),
            const SizedBox(height: IosSpace.lg),
            IosListGroup(
              header: IosSectionHeader(
                title: '自动推算结果',
                padding: const EdgeInsets.fromLTRB(
                  IosSpace.xs,
                  0,
                  IosSpace.xs,
                  IosSpace.sm,
                ),
              ),
              padding: const EdgeInsets.all(IosSpace.ml),
              children: <Widget>[
                IosKeyValueRow(label: '标题', value: preview.title),
                // 三个自动时间直接取标签行本身，保证与打印结果完全一致
                for (final LabelRow r in preview.rows)
                  IosKeyValueRow(
                    label: r.label.replaceAll('：', ''),
                    value: r.value,
                  ),
                IosKeyValueRow(label: '制作人', value: preview.maker),
              ],
            ),
            const SizedBox(height: IosSpace.xl),
            IosPrimaryButton(busy: _busy, onPressed: _generate),
            const SizedBox(height: IosSpace.lg),
            const IosFootNote(
              text: '二发请用「扫一扫」识别一发标签上的二维码',
              icon: CupertinoIcons.barcode_viewfinder,
            ),
            const SizedBox(height: IosSize.tabBarInset),
          ],
        ),
      ),
    );
  }
}

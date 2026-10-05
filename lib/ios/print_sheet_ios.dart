/// iOS 打印面板 —— `print_sheet.dart` 的 Cupertino 对位实现。
///
/// 业务逻辑（选打印机 / 连接 / 发送 / 超时）与安卓版**完全一致**，
/// 只把外壳从 `showModalBottomSheet` 换成 `showCupertinoModalPopup`，
/// 内部控件换成 Cupertino 系列（`CupertinoListTile` / `CupertinoSwitch` 等）。
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';

import '../prefs.dart';
import '../printer.dart';
import 'ios_theme.dart';
import 'ios_widgets.dart';
import 'printer_page_ios.dart' show IosPrintOptionsEditor;

/// 弹出「打印」面板：选打印机 → 设参数 → 直接出纸。
Future<bool?> showIosPrintSheet(
  BuildContext context, {
  required Uint8List pdf,
}) {
  return showCupertinoModalPopup<bool>(
    context: context,
    builder: (_) => _IosPrintSheet(pdf: pdf),
  );
}

class _IosPrintSheet extends StatefulWidget {
  const _IosPrintSheet({required this.pdf});

  final Uint8List pdf;

  @override
  State<_IosPrintSheet> createState() => _IosPrintSheetState();
}

class _IosPrintSheetState extends State<_IosPrintSheet> {
  final PrinterService _svc = PrinterService.instance;

  List<SavedPrinter> _printers = const <SavedPrinter>[];
  SavedPrinter? _selected;
  PrintOptions _options = AppPrefs.printOptions;

  bool _loading = true;
  bool _busy = false;
  String _status = '';
  bool _advancedOpen = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final List<SavedPrinter> list = await _svc.listSavedPrinters();
    if (!mounted) return;
    setState(() {
      _printers = list;
      _loading = false;
      _selected = list.isEmpty
          ? null
          : list.firstWhere(
              (SavedPrinter p) => p.address == _svc.connectedAddress,
              orElse: () => list.first,
            );
      final SavedPrinter? s = _selected;
      if (s != null) _options = _defaultsFor(s.kind);
    });
  }

  PrintOptions _defaultsFor(PrinterKind kind) {
    final PrintOptions base = AppPrefs.printOptions;
    return base.copyWith(
      density: kind == PrinterKind.tspl ? 8 : 4,
      headDots: kind.defaultHeadDots,
    );
  }

  Future<bool> _ensureConnected(SavedPrinter p) async {
    if (_svc.connectedAddress == p.address) return true;
    final Completer<bool> done = Completer<bool>();
    final StreamSubscription<PrinterEvent> sub = _svc.events.listen(
      (PrinterEvent e) {
        if (e.type == 'connected' &&
            (e.address == null || e.address == p.address)) {
          if (!done.isCompleted) done.complete(e.ok == true);
        }
      },
    );
    final bool sent = await _svc.connect(p.address, kind: p.kind);
    if (!sent) {
      await sub.cancel();
      return false;
    }
    final bool ok = await done.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => false,
    );
    await sub.cancel();
    return ok;
  }

  Future<void> _print() async {
    final SavedPrinter? p = _selected;
    if (p == null || _busy) return;
    setState(() {
      _busy = true;
      _status = '正在连接…';
    });
    try {
      final bool connected = await _ensureConnected(p);
      if (!mounted) return;
      if (!connected) {
        setState(() {
          _busy = false;
          _status = '';
        });
        await _alert('连接失败', '请确认打印机已开机并在范围内');
        return;
      }
      setState(() => _status = '正在发送…');
      final Completer<bool> done = Completer<bool>();
      final StreamSubscription<PrinterEvent> sub = _svc.events.listen(
        (PrinterEvent e) {
          if (e.type == 'printDone' && !done.isCompleted) {
            done.complete(e.ok == true);
          }
        },
      );
      await _svc.printLabel(pdf: widget.pdf, kind: p.kind, options: _options);
      await AppPrefs.setPrintOptions(_options);
      final bool ok = await done.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () => false,
      );
      await sub.cancel();
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).pop(true);
        await _alert('已发送', '标签已发送到「${p.name}」，请留意出纸。');
      } else {
        setState(() {
          _busy = false;
          _status = '';
        });
        await _alert(
          '打印失败',
          p.kind.supportsStatus
              ? '打印机没有回报完成。请检查纸仓与状态，再重试。'
              : '通用机型无法回报状态。请确认走纸正常，必要时调大「浓度」。',
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = '';
      });
      await _alert('打印失败', '$e');
    }
  }

  Future<void> _alert(String title, String body) {
    if (!mounted) return Future<void>.value();
    final Brightness b = iosBrightness(context);
    return showCupertinoDialog<void>(
      context: context,
      builder: (BuildContext ctx) => CupertinoAlertDialog(
        title: Text(title),
        content: Padding(
          padding: const EdgeInsets.only(top: IosSpace.sm),
          child: Text(
            body,
            style: TextStyle(
              fontSize: IosText.subheadline,
              color: IosColors.secondaryLabel(b),
              height: 1.45,
            ),
          ),
        ),
        actions: <Widget>[
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('好'),
          ),
        ],
      ),
    );
  }

  String _summary() {
    final PrintOptions o = _options;
    final List<String> parts = <String>['${o.copies} 份'];
    if (!_selected!.kind.isGeneric ||
        _selected!.kind == PrinterKind.tspl) {
      parts.add('间隙 ${o.gap}mm');
      parts.add('浓度 ${o.density}');
    }
    if (_selected!.kind == PrinterKind.tspl) {
      parts.add('速度 ${o.speed}');
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = iosBrightness(context);
    final double h = MediaQuery.of(context).size.height * 0.88;

    return Container(
      constraints: BoxConstraints(maxHeight: h),
      decoration: BoxDecoration(
        color: IosColors.grouped(b),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(IosRadius.xl),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // 抓手
            Container(
              margin: const EdgeInsets.only(top: IosSpace.sm),
              width: 36,
              height: 5,
              decoration: BoxDecoration(
                color: IosColors.tertiaryLabel(b),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            // 标题栏
            Padding(
              padding: const EdgeInsets.fromLTRB(
                IosSpace.lg,
                IosSpace.md,
                IosSpace.sm,
                IosSpace.sm,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text(
                          '打印标签',
                          style: TextStyle(
                            fontSize: IosText.title3,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.45,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '50 × 30 mm · 打印效果与预览一致',
                          style: TextStyle(
                            fontSize: IosText.footnote,
                            color: IosColors.secondaryLabel(b),
                          ),
                        ),
                      ],
                    ),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(34, 34),
                    onPressed: _busy
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: const Icon(
                      CupertinoIcons.xmark_circle_fill,
                      size: 26,
                      color: IosColors.gray3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: IosSpace.xs),
            // 内容区
            Flexible(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(IosSpace.xxxl),
                      child: CupertinoActivityIndicator(radius: 12),
                    )
                  : ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(
                        IosSpace.lg,
                        0,
                        IosSpace.lg,
                        IosSpace.lg,
                      ),
                      children: <Widget>[
                        if (_printers.isEmpty)
                          _noPrinterHint(b)
                        else ...<Widget>[
                          IosSectionHeader(
                            title: '选择打印机',
                            padding: const EdgeInsets.fromLTRB(
                              IosSpace.xs,
                              IosSpace.sm,
                              IosSpace.xs,
                              IosSpace.sm,
                            ),
                          ),
                          IosListGroup(
                            children: <Widget>[
                              for (int i = 0; i < _printers.length; i++)
                                _printerTile(b, _printers[i], i),
                            ],
                          ),
                          if (_selected!.kind.isGeneric) ...<Widget>[
                            const SizedBox(height: IosSpace.m),
                            IosBanner(
                              tone: IosBannerTone.warn,
                              lines: <String>[
                                '· 通用机型走经典蓝牙 SPP，需要先在系统蓝牙里配对',
                                '· 如果打出来是白纸，试试打开下面的「黑白取反」',
                              ],
                            ),
                          ],
                          const SizedBox(height: IosSpace.lg),
                          IosListGroup(
                            children: <Widget>[
                              IosListRow(
                                title: '打印参数',
                                subtitle: _summary(),
                                leadingIcon: CupertinoIcons.slider_horizontal_3,
                                showChevron: false,
                                showDivider: _advancedOpen,
                                trailing: Icon(
                                  _advancedOpen
                                      ? CupertinoIcons.chevron_up
                                      : CupertinoIcons.chevron_down,
                                  size: 15,
                                  color: IosColors.tertiaryLabel(b),
                                ),
                                onTap: () =>
                                    setState(() => _advancedOpen = !_advancedOpen),
                              ),
                              if (_advancedOpen)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    IosSpace.ml,
                                    IosSpace.m,
                                    IosSpace.ml,
                                    IosSpace.ml,
                                  ),
                                  child: IosPrintOptionsEditor(
                                    kind: _selected!.kind,
                                    options: _options,
                                    onChanged: (PrintOptions o) =>
                                        setState(() => _options = o),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: IosSpace.lg),
                          // 状态行
                          if (_status.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: IosSpace.sm,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: <Widget>[
                                  const CupertinoActivityIndicator(radius: 8),
                                  const SizedBox(width: IosSpace.sm),
                                  Text(
                                    _status,
                                    style: TextStyle(
                                      fontSize: IosText.footnote,
                                      color: IosColors.secondaryLabel(b),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: IosSpace.sm,
                              ),
                              child: Text(
                                '共 ${_options.copies} 份',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: IosText.footnote,
                                  color: IosColors.secondaryLabel(b),
                                ),
                              ),
                            ),
                          IosPrimaryButton(
                            label: '开始打印',
                            icon: CupertinoIcons.printer,
                            busy: _busy,
                            onPressed: _print,
                          ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _printerTile(Brightness b, SavedPrinter p, int i) {
    final bool connected = _svc.connectedAddress == p.address;
    final bool selected = _selected?.address == p.address;
    return Column(
      children: <Widget>[
        CupertinoButton(
          padding: EdgeInsets.zero,
          pressedOpacity: 0.6,
          onPressed: _busy
              ? null
              : () => setState(() => _selected = p),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: IosSpace.ml,
              vertical: IosSpace.m,
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  connected ? CupertinoIcons.printer_fill : CupertinoIcons.printer,
                  size: IosSize.rowIcon,
                  color: selected ? IosColors.brand : IosColors.gray,
                ),
                const SizedBox(width: IosSpace.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        p.name,
                        style: TextStyle(
                          fontSize: IosText.body,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: IosColors.label(b),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        connected
                            ? '已连接 · ${p.kind.label}'
                            : p.kind.label,
                        style: TextStyle(
                          fontSize: IosText.footnote,
                          color: IosColors.secondaryLabel(b),
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  const Icon(
                    CupertinoIcons.checkmark_circle_fill,
                    size: 22,
                    color: IosColors.brand,
                  ),
              ],
            ),
          ),
        ),
        if (i != _printers.length - 1)
          Padding(
            padding: const EdgeInsets.only(left: IosSpace.ml),
            child: Container(
              height: 0.5,
              color: IosColors.separator(b),
            ),
          ),
      ],
    );
  }

  Widget _noPrinterHint(Brightness b) {
    return IosEmptyState(
      icon: CupertinoIcons.printer,
      title: '还没有添加打印机',
      body: '先到「打印机」里添加一台，再回来打印。\n也可以用预览页右上角的「分享」把 PDF 发到别处。',
    );
  }
}

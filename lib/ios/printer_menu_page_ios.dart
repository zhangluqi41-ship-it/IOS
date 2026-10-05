/// iOS 打印机菜单页 —— `printer_menu_page.dart` 的 Cupertino 对位实现。
///
/// 版式沿用「第一格是添加 + 其余是已添加」的语义，
/// 但换成 iOS 分组/网格 + Cupertino 长按菜单（`CupertinoActionSheet`）。
library;

import 'dart:async';

import 'package:flutter/cupertino.dart';

import 'ios_nav.dart';
import 'ios_theme.dart';
import 'ios_widgets.dart';
import 'ios_shell.dart';
import 'printer_page_ios.dart';
import '../printer.dart';

/// 一级页第 2 节：打印机。
class IosPrinterMenuPage extends StatefulWidget {
  const IosPrinterMenuPage({super.key});

  @override
  State<IosPrinterMenuPage> createState() => _IosPrinterMenuPageState();
}

class _IosPrinterMenuPageState extends State<IosPrinterMenuPage> {
  final PrinterService _svc = PrinterService.instance;

  StreamSubscription<PrinterEvent>? _sub;
  List<SavedPrinter> _saved = const <SavedPrinter>[];

  @override
  void initState() {
    super.initState();
    _sub = _svc.events.listen(_onEvent);
    _load();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final List<SavedPrinter> list = await _svc.listSavedPrinters();
    if (!mounted) return;
    setState(() {
      _saved = list;
    });
  }

  void _onEvent(PrinterEvent e) {
    if (e.type == 'savedChanged') {
      _load();
    } else if (e.type == 'connected' || e.type == 'disconnected') {
      if (mounted) setState(() {});
    }
  }

  Future<void> _openAdd() async {
    await iosPush<void>(context, const IosPrinterPage());
    await _load();
  }

  Future<void> _openTarget(SavedPrinter p) async {
    await iosPush<void>(context, IosPrinterPage(target: p));
    await _load();
  }

  /// 长按卡片 → CupertinoActionSheet（重命名 / 移除）。
  Future<void> _showActions(SavedPrinter p) async {
    iosHaptic(HapticFeedbackType.medium);
    final String? action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (BuildContext ctx) => CupertinoActionSheet(
        title: Text(
          p.name,
          style: const TextStyle(
            fontSize: IosText.headline,
            fontWeight: FontWeight.w600,
          ),
        ),
        message: Text(
          '${p.kind.label} · ${p.address}',
          style: const TextStyle(fontSize: IosText.footnote),
        ),
        actions: <Widget>[
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(ctx).pop('rename'),
            child: const Text('重命名'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(ctx).pop('remove'),
            child: const Text('移除'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('取消'),
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'rename') await _rename(p);
    if (action == 'remove') await _remove(p);
  }

  Future<void> _rename(SavedPrinter p) async {
    final String? name = await showCupertinoDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(initial: p.name),
    );
    if (name == null || name.isEmpty) return;
    await _svc.renamePrinter(p.address, name);
    await _load();
  }

  Future<void> _remove(SavedPrinter p) async {
    final bool? ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => CupertinoAlertDialog(
        title: const Text('移除打印机'),
        content: Padding(
          padding: const EdgeInsets.only(top: IosSpace.sm),
          child: Text('确定把「${p.name}」从列表里移除吗？\n（不会解除系统里的蓝牙配对）'),
        ),
        actions: <Widget>[
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _svc.removePrinter(p.address);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = iosBrightness(context);

    return CupertinoPageScaffold(
      backgroundColor: IosColors.grouped(b),
      child: CustomScrollView(
        slivers: <Widget>[
          CupertinoSliverNavigationBar(
            largeTitle: const Text(
              '打印机',
              style: TextStyle(letterSpacing: 0.2),
            ),
            backgroundColor: Color(0x00000000),
            border: const Border(
              bottom: BorderSide(color: Color(0x00000000), width: 0),
            ),
            trailing: CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(34, 34),
              onPressed: _load,
              child: const Icon(CupertinoIcons.refresh, size: 22),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                IosSpace.screenH,
                IosSpace.xs,
                IosSpace.screenH,
                IosSpace.md,
              ),
              child: IosSectionHeader(
                title: '已添加',
                subtitle: _saved.isEmpty
                    ? '添加一台打印机后即可一键出纸'
                    : '共 ${_saved.length} 台 · 长按卡片可管理',
                padding: EdgeInsets.zero,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: IosSpace.screenH),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: IosSpace.m,
                crossAxisSpacing: IosSpace.m,
                childAspectRatio: 1.05,
              ),
              delegate: SliverChildBuilderDelegate(
                (BuildContext context, int i) {
                  if (i == 0) {
                    return IosGridCard(
                      title: '添加打印机',
                      subtitle: '选择型号后连接',
                      icon: CupertinoIcons.add_circled,
                      highlight: true,
                      onTap: _openAdd,
                    );
                  }
                  final SavedPrinter p = _saved[i - 1];
                  final bool connected = _svc.connectedAddress == p.address;
                  return IosGridCard(
                    title: p.name,
                    subtitle: p.kind.label,
                    icon: connected
                        ? CupertinoIcons.printer_fill
                        : CupertinoIcons.printer,
                    tint: connected ? IosColors.tplKombuchaTint : null,
                    iconFill: connected ? IosColors.tplKombuchaFill : null,
                    onTap: () => _openTarget(p),
                    onLongPress: () => _showActions(p),
                    badge: connected ? const IosConnectedBadge() : null,
                  );
                },
                childCount: _saved.length + 1,
              ),
            ),
          ),
          if (_saved.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  IosSpace.screenH,
                  IosSpace.lg,
                  IosSpace.screenH,
                  0,
                ),
                child: IosEmptyState(
                  icon: CupertinoIcons.printer,
                  title: '还没有打印机',
                  body: '点「添加打印机」选择型号，扫描并连接设备。\n'
                      '连接成功会自动出现在这里，下次打开就能直接打印。',
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: IosSpace.lg)),
          const SliverToBoxAdapter(child: _IosSupportedKinds()),
          const SliverToBoxAdapter(
            child: SizedBox(height: IosSize.tabBarInset),
          ),
        ],
      ),
    );
  }
}

/// 「已连接」角标（Cupertino 版）。
class IosConnectedBadge extends StatelessWidget {
  const IosConnectedBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: IosSpace.sm, vertical: 3),
      decoration: BoxDecoration(
        color: IosColors.green,
        borderRadius: BorderRadius.circular(IosRadius.xs),
      ),
      child: const Text(
        '已连接',
        style: TextStyle(
          fontSize: IosText.caption2,
          fontWeight: FontWeight.w600,
          color: CupertinoColors.white,
          height: 1.2,
        ),
      ),
    );
  }
}

/// 重命名弹窗（控制器自持自释）。
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});

  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_ctrl.text.trim());

  @override
  Widget build(BuildContext context) {
    return CupertinoAlertDialog(
      title: const Text('重命名打印机'),
      content: Padding(
        padding: const EdgeInsets.only(top: IosSpace.m),
        child: CupertinoTextField(
          controller: _ctrl,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          placeholder: '给这台打印机起个名字',
        ),
      ),
      actions: <Widget>[
        CupertinoDialogAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: _submit,
          child: const Text('保存'),
        ),
      ],
    );
  }
}

/// 「支持哪些打印机」说明卡。
class _IosSupportedKinds extends StatelessWidget {
  const _IosSupportedKinds();

  @override
  Widget build(BuildContext context) {
    final Brightness b = iosBrightness(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: IosSpace.screenH),
      child: IosListGroup(
        header: IosSectionHeader(
          title: '支持哪些打印机',
          padding: const EdgeInsets.fromLTRB(
            IosSpace.xs,
            0,
            IosSpace.xs,
            IosSpace.sm,
          ),
        ),
        padding: const EdgeInsets.all(IosSpace.ml),
        children: <Widget>[
          for (int i = 0; i < PrinterKind.values.length; i++)
            Padding(
              padding: EdgeInsets.only(
                bottom: i == PrinterKind.values.length - 1 ? 0 : IosSpace.m,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    margin: const EdgeInsets.only(top: 5),
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: IosColors.brand,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: IosSpace.m),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: <InlineSpan>[
                          TextSpan(
                            text: '${PrinterKind.values[i].label}　',
                            style: TextStyle(
                              fontSize: IosText.footnote,
                              fontWeight: FontWeight.w600,
                              color: IosColors.label(b),
                            ),
                          ),
                          TextSpan(
                            text: PrinterKind.values[i].hint,
                            style: TextStyle(
                              fontSize: IosText.footnote,
                              color: IosColors.secondaryLabel(b),
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

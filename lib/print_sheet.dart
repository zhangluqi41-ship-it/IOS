import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'prefs.dart';
import 'print_options.dart';
import 'printer.dart';

/// 弹出「打印」面板：选打印机 → 设参数 → 直接出纸。
Future<bool?> showPrintSheet(
  BuildContext context, {
  required Uint8List pdf,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => _PrintSheet(pdf: pdf),
  );
}

class _PrintSheet extends StatefulWidget {
  const _PrintSheet({required this.pdf});

  final Uint8List pdf;

  @override
  State<_PrintSheet> createState() => _PrintSheetState();
}

class _PrintSheetState extends State<_PrintSheet> {
  final _svc = PrinterService.instance;

  List<SavedPrinter> _printers = const [];
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
    final list = await _svc.listSavedPrinters();
    if (!mounted) return;
    setState(() {
      _printers = list;
      _loading = false;
      // 优先选当前已连接的，否则选第一台
      _selected = list.isEmpty
          ? null
          : list.firstWhere(
              (p) => p.address == _svc.connectedAddress,
              orElse: () => list.first,
            );
      if (_selected != null) {
        _options = _defaultsFor(_selected!.kind);
      }
    });
  }

  /// 换型号时把该型号的默认参数带出来。
  PrintOptions _defaultsFor(PrinterKind kind) {
    final base = AppPrefs.printOptions;
    return base.copyWith(
      density: kind == PrinterKind.tspl ? 8 : 4,
      headDots: kind.defaultHeadDots,
    );
  }

  /// 确保已连上目标打印机；已连同一台就直接返回。
  Future<bool> _ensureConnected(SavedPrinter p) async {
    if (_svc.connectedAddress == p.address) return true;
    final done = Completer<bool>();
    final sub = _svc.events.listen((e) {
      if (e.type == 'connected' && (e.address == null || e.address == p.address)) {
        if (!done.isCompleted) done.complete(e.ok == true);
      }
    });
    final sent = await _svc.connect(p.address, kind: p.kind);
    if (!sent) {
      await sub.cancel();
      return false;
    }
    final ok = await done.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => false,
    );
    await sub.cancel();
    return ok;
  }

  Future<void> _print() async {
    final p = _selected;
    if (p == null || _busy) return;
    setState(() {
      _busy = true;
      _status = '正在连接…';
    });
    try {
      final connected = await _ensureConnected(p);
      if (!mounted) return;
      if (!connected) {
        setState(() {
          _busy = false;
          _status = '';
        });
        _toast('连接失败，请确认打印机已开机并在范围内');
        return;
      }
      setState(() => _status = '正在发送…');
      final done = Completer<bool>();
      final sub = _svc.events.listen((e) {
        if (e.type == 'printDone' && !done.isCompleted) {
          done.complete(e.ok == true);
        }
      });
      final sent = await _svc.printLabel(
        pdf: widget.pdf,
        kind: p.kind,
        options: _options,
      );
      if (!sent) {
        await sub.cancel();
        if (!mounted) return;
        setState(() {
          _busy = false;
          _status = '';
        });
        _toast('打印指令下发失败');
        return;
      }
      await AppPrefs.setPrintOptions(_options);
      final ok = await done.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () => false,
      );
      await sub.cancel();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = '';
      });
      if (ok) {
        _toast('已发送到打印机');
        Navigator.of(context).pop(true);
      } else {
        // 部分通用机型不回报结果，这里提示「已下发」而不是报错
        _toast(p.kind.supportsStatus ? '打印失败，请检查打印机状态' : '已下发打印，请查看出纸');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = '';
      });
      _toast('打印失败：$e');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxH = MediaQuery.sizeOf(context).height * 0.88;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: _loading
            ? const SizedBox(
                height: 220,
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '打印标签',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '50 × 30 mm · 打印效果与上方预览一致',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      children: [
                        if (_printers.isEmpty)
                          _noPrinterHint(theme)
                        else ...[
                          Text('选择打印机', style: theme.textTheme.labelLarge),
                          const SizedBox(height: 6),
                          for (final p in _printers) _printerTile(p),
                          const SizedBox(height: 14),
                          if (_selected != null && _selected!.kind.isGeneric)
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.secondaryContainer
                                    .withValues(alpha: 0.45),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '通用机型走标准蓝牙打印指令，'
                                '第一次用建议先打一张标尺测试页确认边距。',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSecondaryContainer,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            childrenPadding: EdgeInsets.zero,
                            initiallyExpanded: _advancedOpen,
                            onExpansionChanged: (v) =>
                                setState(() => _advancedOpen = v),
                            title: Text(
                              '打印参数',
                              style: theme.textTheme.labelLarge,
                            ),
                            subtitle: Text(
                              _summary(),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                            ),
                            children: [
                              if (_selected != null)
                                PrintOptionsEditor(
                                  kind: _selected!.kind,
                                  options: _options,
                                  onChanged: (o) => setState(() => _options = o),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      if (_status.isNotEmpty) ...[
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 10),
                        Text(_status, style: theme.textTheme.bodySmall),
                      ] else
                        Text(
                          _printers.isEmpty
                              ? ''
                              : '共 ${_options.copies} 份',
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: (_selected == null || _busy) ? null : _print,
                      icon: const Icon(Icons.print),
                      label: Text(_busy ? '打印中…' : '开始打印'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  String _summary() {
    final o = _options;
    final parts = <String>['${o.copies} 份'];
    if (_selected?.kind != PrinterKind.escpos) parts.add('间隙 ${o.gap}mm');
    if (_selected?.kind != PrinterKind.escpos) parts.add('浓度 ${o.density}');
    if (_selected?.kind == PrinterKind.tspl) parts.add('速度 ${o.speed}');
    return parts.join(' · ');
  }

  Widget _noPrinterHint(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.print_disabled_outlined, color: theme.colorScheme.outline),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '还没有添加打印机。先到「打印机」页面添加一台，再回来打印。',
              style: theme.textTheme.bodySmall?.copyWith(height: 1.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _printerTile(SavedPrinter p) {
    final theme = Theme.of(context);
    final selected = _selected?.address == p.address;
    final connected = _svc.connectedAddress == p.address;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => setState(() {
          _selected = p;
          _options = _defaultsFor(p.kind);
        }),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
                : theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.35,
                  ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                connected ? Icons.print : Icons.print_outlined,
                color: connected
                    ? Colors.green.shade700
                    : theme.colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      connected ? '已连接 · ${p.kind.label}' : p.kind.label,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: connected
                            ? Colors.green.shade700
                            : theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle, color: theme.colorScheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

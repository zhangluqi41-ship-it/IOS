import 'dart:async';

import 'package:flutter/material.dart';

import 'app_shell.dart';
import 'nav.dart';
import 'printer.dart';
import 'printer_page.dart';
import 'ui_kit.dart';

/// 一级页第 2 节：打印机。
///
/// 版式和「模板」节完全一致：顶部一个分节大标题，下面一张 2 列卡片网格。
/// - 第一格固定是 **「添加打印机」**，点进去选型号 → 扫描 → 连接；
/// - 其余格子是**已添加**的打印机（连接成功会自动添加，重启 App 仍在）；
/// - 已连接的打印机，卡片右下角显示绿色 **「已连接」** 角标。
class PrinterMenuPage extends StatefulWidget {
  const PrinterMenuPage({super.key});

  @override
  State<PrinterMenuPage> createState() => _PrinterMenuPageState();
}

class _PrinterMenuPageState extends State<PrinterMenuPage> {
  final _svc = PrinterService.instance;

  StreamSubscription<PrinterEvent>? _sub;
  bool _loading = true;
  List<SavedPrinter> _saved = const [];

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
    final list = await _svc.listSavedPrinters();
    if (!mounted) return;
    setState(() {
      _saved = list;
      _loading = false;
    });
  }

  void _onEvent(PrinterEvent e) {
    // 连接态或列表一变就重画
    if (e.type == 'connected' ||
        e.type == 'disconnected' ||
        e.type == 'savedChanged') {
      if (e.type == 'savedChanged') {
        _load();
      } else if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _openAdd() async {
    await openLevel2(context, const PrinterPage());
    await _load();
  }

  Future<void> _openTarget(SavedPrinter p) async {
    await openLevel2(context, PrinterPage(target: p));
    await _load();
  }

  Future<void> _showActions(SavedPrinter p) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(p.name),
              subtitle: Text(
                p.addressIsMac
                    ? '${p.kind.label} · ${p.address}'
                    : '${p.kind.label} · iOS 设备',
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('重命名'),
              onTap: () => Navigator.of(context).pop('rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('移除'),
              onTap: () => Navigator.of(context).pop('remove'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'rename') {
      await _rename(p);
    } else if (action == 'remove') {
      await _remove(p);
    }
  }

  Future<void> _rename(SavedPrinter p) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(initial: p.name),
    );
    if (name == null || name.isEmpty) return;
    await _svc.renamePrinter(p.address, name);
    await _load();
  }

  Future<void> _remove(SavedPrinter p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移除打印机'),
        content: Text('确定把「${p.name}」从列表里移除吗？\n（不会解除系统里的蓝牙配对）'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _svc.removePrinter(p.address);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('已移除 ${p.name}')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: SectionHeader(
            title: '打印机',
            subtitle: _saved.isEmpty
                ? '添加一台打印机后即可一键出纸'
                : '已添加 ${_saved.length} 台 · 长按卡片可管理',
            trailing: IconButton(
              tooltip: '刷新',
              icon: const Icon(Icons.refresh),
              onPressed: _load,
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 1.0,
            ),
            delegate: SliverChildBuilderDelegate((context, i) {
              if (i == 0) {
                return TemplateCard(
                  title: '添加打印机',
                  subtitle: '选择型号后连接',
                  icon: Icons.add_circle_outline,
                  highlight: true,
                  onTap: _openAdd,
                );
              }
              final p = _saved[i - 1];
              return TemplateCard(
                title: p.name,
                subtitle: p.kind.label,
                icon: _svc.connectedAddress == p.address
                    ? Icons.print
                    : Icons.print_outlined,
                onTap: () => _openTarget(p),
                onLongPress: () => _showActions(p),
                badge: _svc.connectedAddress == p.address
                    ? const ConnectedBadge()
                    : null,
              );
            }, childCount: _saved.length + 1),
          ),
        ),
        if (_saved.isEmpty) ...[
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: EmptyStateCard(
                icon: Icons.print_outlined,
                title: '还没有打印机',
                body:
                    '点「添加打印机」选择型号，扫描并连接设备。\n'
                    '连接成功会自动出现在这里，下次打开就能直接打印。',
              ),
            ),
          ),
        ],
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: _SupportedKinds(theme: theme),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: kGlassBarInset)),
      ],
    );
  }
}

/// 重命名对话框（控制器由自己持有并释放）。
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
    return AlertDialog(
      title: const Text('重命名打印机'),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: const InputDecoration(
          labelText: '名称',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('保存')),
      ],
    );
  }
}

/// 已连接角标。
class ConnectedBadge extends StatelessWidget {
  const ConnectedBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.green.shade600,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Text(
        '已连接',
        style: TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          height: 1.2,
        ),
      ),
    );
  }
}

/// 支持的型号一览（说明为什么需要选型号）。
class _SupportedKinds extends StatelessWidget {
  const _SupportedKinds({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.memory_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                '支持哪些打印机',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final k in PrinterKind.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${k.label}　',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          TextSpan(text: k.hint),
                        ],
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 2),
          Text(
            '型号决定用哪套通信协议，添加时必须选对。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:ui';

import 'package:flutter/material.dart';

import 'nav.dart';
import 'printer_menu_page.dart';
import 'scan_page.dart';
import 'templates.dart';
import 'ui_kit.dart';

/// 底部玻璃栏给内容预留的高度（栏体 + 上方留白 + 安全区）。
const double kGlassBarInset = 118;

/// 一级页面外壳。
///
/// - 顶部固定「效期管理系统」，具体在哪一节由页面内的大标题区分；
/// - 底部是 Liquid Glass 风格的悬浮栏（模板 / 扫码 / 打印机）；
/// - 进入二级页面时玻璃栏下滑收起，返回时上滑复原。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => HomeShellState();
}

class HomeShellState extends State<HomeShell> with RouteAware {
  /// 0 = 模板，1 = 打印机
  int _index = 0;

  /// 玻璃栏是否可见（二级页盖上来时收起来）
  bool _barVisible = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) glassRouteObserver.subscribe(this, route);
  }

  @override
  void dispose() {
    glassRouteObserver.unsubscribe(this);
    super.dispose();
  }

  // 二级页压上来 → 底栏下滑收起；二级页退回去 → 底栏上滑复原
  @override
  void didPushNext() {
    if (mounted) setState(() => _barVisible = false);
  }

  @override
  void didPopNext() {
    if (mounted) setState(() => _barVisible = true);
  }

  void _select(int i) {
    if (i == _index) return;
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      // 在「打印机」节按返回，先回到「模板」节，而不是直接退出 App
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _index != 0) setState(() => _index = 0);
      },
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        appBar: AppBar(
          backgroundColor: theme.colorScheme.surface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          titleSpacing: 20,
          title: Row(
            children: [
              Icon(
                Icons.verified_outlined,
                size: 22,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              const Text(
                '效期管理系统',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ),
        body: Stack(
          children: [
            Positioned.fill(
              child: IndexedStack(
                index: _index,
                children: const [TemplatesTab(), PrinterMenuPage()],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: GlassBottomBar(
                index: _index,
                visible: _barVisible,
                onSelect: _select,
                onScan: () => openLevel2(context, const ScanPage()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// 第 1 节：模板
// ===========================================================================

class TemplatesTab extends StatelessWidget {
  const TemplatesTab({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return CustomScrollView(
      slivers: [
        const SliverToBoxAdapter(
          child: SectionHeader(title: '模板', subtitle: '选择一个模板开始制作标签'),
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
            delegate: SliverChildListDelegate([
              TemplateCard(
                title: '通用效期',
                subtitle: '50 × 30 mm',
                icon: Icons.qr_code_2,
                onTap: () => openLevel2(context, const GenericTemplatePage()),
              ),
              TemplateCard(
                title: '康普茶',
                subtitle: '一发 / 二发',
                icon: Icons.emoji_food_beverage_outlined,
                onTap: () => openLevel2(context, const KombuchaTemplatePage()),
              ),
              TemplateCard(
                title: '奶制品',
                subtitle: '牛奶 / 燕麦 / 豆奶…',
                icon: Icons.local_drink_outlined,
                onTap: () => openLevel2(context, const DairyTemplatePage()),
              ),
            ]),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 20)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _HowItWorks(theme: theme),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: kGlassBarInset)),
      ],
    );
  }
}

/// 模板卡片（也是打印机页卡片的同款版式）。
class TemplateCard extends StatelessWidget {
  const TemplateCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.onLongPress,
    this.badge,
    this.highlight = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// 右下角角标（例如「已连接」）
  final Widget? badge;

  /// 强调底色（例如「添加打印机」）
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = highlight
        ? theme.colorScheme.primary.withValues(alpha: 0.45)
        : theme.colorScheme.primary.withValues(alpha: 0.30);

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(20),
      child: Ink(
        decoration: BoxDecoration(
          color: highlight
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.55)
              : theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.65,
                ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 46, color: theme.colorScheme.primary),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
            if (badge != null) Positioned(right: 8, bottom: 8, child: badge!),
          ],
        ),
      ),
    );
  }
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
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
                Icons.tips_and_updates_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                '使用流程',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final (i, t) in const [
            '选模板 → 填标题 → 生成标签',
            '在预览页「一键打印」，或先保存 PDF',
            '康普茶二发：扫瓶身二维码即可续打',
          ].indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${i + 1}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      t,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.5,
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

// ===========================================================================
// 底部：Liquid Glass 悬浮栏
// ===========================================================================

/// 苹果「液态玻璃」风格的底部悬浮栏。
///
/// 半透明 + 背景模糊 + 描边高光；「模板 / 扫码 / 打印机」三项**同一水平面**，
/// 中间的扫码球是填充圆形强调，不凸出胶囊之外。
/// 进入二级页时整体向下滑出屏幕。
class GlassBottomBar extends StatelessWidget {
  const GlassBottomBar({
    super.key,
    required this.index,
    required this.visible,
    required this.onSelect,
    required this.onScan,
  });

  final int index;
  final bool visible;
  final ValueChanged<int> onSelect;
  final VoidCallback onScan;

  static const double _barH = 68;

  /// 扫码球直径。比 [_barH] 小一圈，好和三栏文字排在同一水平面上。
  static const double _orbD = 40;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, 1.8),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOutCubic,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 240),
          child: Padding(
            padding: EdgeInsets.fromLTRB(12, 10, 12, 10 + bottomInset),
            child: SizedBox(height: _barH, child: _pill(context, dark)),
          ),
        ),
      ),
    );
  }

  Widget _pill(BuildContext context, bool dark) {
    final radius = BorderRadius.circular(_barH / 2);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.38 : 0.10),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: dark
                    ? [
                        Colors.white.withValues(alpha: 0.16),
                        Colors.white.withValues(alpha: 0.05),
                      ]
                    : [
                        Colors.white.withValues(alpha: 0.86),
                        Colors.white.withValues(alpha: 0.62),
                      ],
              ),
              border: Border.all(
                color: dark
                    ? Colors.white.withValues(alpha: 0.18)
                    : Colors.white.withValues(alpha: 0.95),
                width: 1,
              ),
            ),
            // MaterialType.transparency 只为承载点击涟漪（本身不画任何像素），
            // 少了它 InkWell 的水波会被画到渐变层下面而看不见。
            child: Material(
              type: MaterialType.transparency,
              child: Row(
                children: [
                  Expanded(
                    child: _item(
                      context,
                      icon: Icons.dashboard_customize_outlined,
                      label: '模板',
                      selected: index == 0,
                      onTap: () => onSelect(0),
                    ),
                  ),
                  Expanded(child: _scanItem(context)),
                  Expanded(
                    child: _item(
                      context,
                      icon: Icons.print_outlined,
                      label: '打印机',
                      selected: index == 1,
                      onTap: () => onSelect(1),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _item(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final color = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 24, color: color),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// 中间的扫码按钮：填充圆球 + 「扫码」文字，
  /// 结构与 [_item] 一致，因此和左右两项**自然落在同一水平面**上。
  Widget _scanItem(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onScan,
      borderRadius: BorderRadius.circular(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _scanOrb(context, theme),
          const SizedBox(height: 2),
          Text(
            '扫码',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _scanOrb(BuildContext context, ThemeData theme) {
    return Container(
      width: _orbD,
      height: _orbD,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primary,
            theme.colorScheme.primary.withValues(alpha: 0.82),
          ],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.55),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.28),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: const Icon(Icons.qr_code_scanner, color: Colors.white, size: 21),
    );
  }
}

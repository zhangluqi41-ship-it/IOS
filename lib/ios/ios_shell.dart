/// iOS 一级页外壳 —— `app_shell.dart` 的 Cupertino 对位实现。
///
/// 对应需求：
///  * 第 1 条 —— 底栏使用苹果官方 **`CupertinoTabBar`**（真·原生标签栏组件），
///    而非安卓侧自绘的液态玻璃胶囊。玻璃质感交给系统的半透明底 + 模糊，
///    自己不画多余装饰。
///  * 第 3、4 条 —— 整个外壳用 Cupertino 组件独立实现，不复用 Material 外壳。
///
/// 与安卓版的结构差异说明：
///  安卓版是「一个 shell + 页内分节标题」；iOS 版按 HIG 改成
///  **`CupertinoTabScaffold` 双 Tab + 各自独立的大标题**——
///  这是 iOS 第一方 App（设置、App Store、健康）的标准骨架。
library;

import 'package:flutter/cupertino.dart';

import 'ios_nav.dart';
import 'ios_theme.dart';
import 'ios_widgets.dart';
import 'printer_menu_page_ios.dart';
import 'scan_page_ios.dart';
import 'templates_ios.dart';

/// iOS 一级页外壳。
///
/// - `CupertinoTabScaffold` + `CupertinoTabBar`（苹果官方标签栏）
/// - 两个 Tab：模板 / 打印机
/// - 中间的「扫码」是**凸起的悬浮球**（保持与安卓版的功能对位），
///   但用 Cupertino 的渐变圆球 + `CupertinoButton` 实现。
class IosHomeShell extends StatefulWidget {
  const IosHomeShell({super.key});

  @override
  State<IosHomeShell> createState() => _IosHomeShellState();
}

class _IosHomeShellState extends State<IosHomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final Brightness b = iosBrightness(context);

    return CupertinoTabScaffold(
      tabBar: CupertinoTabBar(
        backgroundColor: IosColors.card(b).withValues(alpha: 0.94),
        activeColor: IosColors.brand,
        inactiveColor: IosColors.secondaryLabel(b),
        border: Border(
          top: BorderSide(color: IosColors.separator(b), width: 0.5),
        ),
        currentIndex: _index,
        onTap: (int i) {
          iosHaptic(HapticFeedbackType.selection);
          setState(() => _index = i);
        },
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.square_grid_2x2, size: 26),
            activeIcon: Icon(CupertinoIcons.square_grid_2x2_fill, size: 26),
            label: '模板',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.printer, size: 26),
            activeIcon: Icon(CupertinoIcons.printer_fill, size: 26),
            label: '打印机',
          ),
        ],
      ),
      tabBuilder: (BuildContext context, int i) {
        return Stack(
          children: <Widget>[
            // 两个 Tab 各自保留导航栈（HIG 要求 Tab 内导航独立）
            CupertinoTabView(
              builder: (_) => i == 0
                  ? const IosTemplatesTab()
                  : const IosPrinterMenuPage(),
            ),
            // 扫码悬浮球：位于标签栏正上方居中
            Positioned(
              left: 0,
              right: 0,
              bottom: IosSize.tabBar + 6,
              child: Center(
                child: _ScanOrb(
                  onTap: () => iosPush<void>(context, const IosScanPage()),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 扫码悬浮球 —— Cupertino 风格的渐变圆球。
class _ScanOrb extends StatelessWidget {
  const _ScanOrb({required this.onTap});

  final VoidCallback onTap;

  static const double _d = 52;

  @override
  Widget build(BuildContext context) {
    final Brightness b = iosBrightness(context);
    return Semantics(
      button: true,
      label: '扫一扫',
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: IosColors.brand.withValues(alpha: 0.32),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(_d, _d),
          pressedOpacity: 0.75,
          borderRadius: BorderRadius.circular(_d / 2),
          onPressed: () {
            iosHaptic(HapticFeedbackType.medium);
            onTap();
          },
          child: Container(
            width: _d,
            height: _d,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[IosColors.brandLight, IosColors.brand],
              ),
              border: Border.all(
                color: IosColors.card(b),
                width: 3,
              ),
            ),
            child: const Icon(
              CupertinoIcons.barcode_viewfinder,
              size: 24,
              color: CupertinoColors.white,
            ),
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// 模板 Tab
// ===========================================================================

/// 模板 Tab —— iOS 分组卡片网格。
///
/// 用 `CustomScrollView` + `CupertinoSliverNavigationBar`（大标题），
/// 卡片是 iOS 风格的圆角方块（squircle 近似），带图标 + 标题 + 副标题。
class IosTemplatesTab extends StatelessWidget {
  const IosTemplatesTab({super.key});

  @override
  Widget build(BuildContext context) {
    final Brightness b = iosBrightness(context);

    return CupertinoPageScaffold(
      backgroundColor: IosColors.grouped(b),
      child: CustomScrollView(
        slivers: <Widget>[
          const CupertinoSliverNavigationBar(
            largeTitle: Text(
              '效期管理系统',
              style: TextStyle(letterSpacing: 0.2),
            ),
            border: Border(
              bottom: BorderSide(color: Color(0x00000000), width: 0),
            ),
            backgroundColor: Color(0x00000000),
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
                title: '模板',
                subtitle: '选择一个模板开始制作标签',
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
              delegate: SliverChildListDelegate(<Widget>[
                IosGridCard(
                  title: '通用效期',
                  subtitle: '50 × 30 mm',
                  icon: CupertinoIcons.time,
                  onTap: () =>
                      iosPush<void>(context, const IosGenericTemplatePage()),
                ),
                IosGridCard(
                  title: '康普茶',
                  subtitle: '一发 / 二发',
                  icon: CupertinoIcons.drop,
                  onTap: () =>
                      iosPush<void>(context, const IosKombuchaTemplatePage()),
                ),
                IosGridCard(
                  title: '奶制品',
                  subtitle: '牛奶 / 燕麦 / 豆奶…',
                  icon: CupertinoIcons.lab_flask,
                  onTap: () =>
                      iosPush<void>(context, const IosDairyTemplatePage()),
                ),
              ]),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: IosSpace.lg)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: IosSpace.screenH,
              ),
              child: const _IosHowItWorks(),
            ),
          ),
          const SliverToBoxAdapter(
            child: SizedBox(height: IosSize.tabBarInset),
          ),
        ],
      ),
    );
  }
}

/// iOS 网格卡片 —— 对应安卓的 `TemplateCard`。
///
/// HIG：白底、圆角 16、图标 44、标题 17 半粗、副标题 13 灰。
class IosGridCard extends StatefulWidget {
  const IosGridCard({
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
  final Widget? badge;

  /// 强调态（「添加打印机」用）。
  final bool highlight;

  @override
  State<IosGridCard> createState() => _IosGridCardState();
}

class _IosGridCardState extends State<IosGridCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final Brightness b = iosBrightness(context);

    final Color bg = widget.highlight
        ? IosColors.brand.withValues(alpha: b == Brightness.dark ? 0.26 : 0.10)
        : IosColors.card(b);
    final Color border = widget.highlight
        ? IosColors.brand.withValues(alpha: 0.35)
        : IosColors.separator(b);
    final Color fg = widget.highlight ? IosColors.brand : IosColors.label(b);

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        iosHaptic(HapticFeedbackType.selection);
        widget.onTap();
      },
      onLongPress: widget.onLongPress == null
          ? null
          : () {
              iosHaptic(HapticFeedbackType.medium);
              widget.onLongPress!();
            },
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: IosMotion.fast,
        curve: IosMotion.standard,
        child: AnimatedContainer(
          duration: IosMotion.fast,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(IosRadius.card),
            border: Border.all(color: border, width: 0.8),
            boxShadow: widget.highlight
                ? null
                : <BoxShadow>[
                    BoxShadow(
                      color: CupertinoColors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
          ),
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(
                      widget.icon,
                      size: 42,
                      color: widget.highlight
                          ? IosColors.brand
                          : IosColors.brand.withValues(alpha: 0.85),
                    ),
                    const SizedBox(height: IosSpace.m),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: IosSpace.smd,
                      ),
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: IosText.headline,
                          fontWeight: FontWeight.w600,
                          color: fg,
                          letterSpacing: -0.41,
                        ),
                      ),
                    ),
                    const SizedBox(height: IosSpace.xs),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: IosSpace.smd,
                      ),
                      child: Text(
                        widget.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: IosText.footnote,
                          color: IosColors.secondaryLabel(b),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.badge != null)
                Positioned(
                  right: IosSpace.sm,
                  bottom: IosSpace.sm,
                  child: widget.badge!,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 「使用流程」卡片。
class _IosHowItWorks extends StatelessWidget {
  const _IosHowItWorks();

  @override
  Widget build(BuildContext context) {
    final Brightness b = iosBrightness(context);
    const List<(String, String)> steps = <(String, String)>[
      ('选择模板', '按要标注的品类进入对应模板'),
      ('填写信息', '标题与日期，日期可用快捷档位'),
      ('生成标签', '预览确认后打印、分享或存到手机'),
    ];

    return IosListGroup(
      header: IosSectionHeader(
        title: '使用流程',
        padding: const EdgeInsets.fromLTRB(
          IosSpace.xs,
          IosSpace.sm,
          IosSpace.xs,
          IosSpace.sm,
        ),
      ),
      padding: const EdgeInsets.all(IosSpace.ml),
      children: <Widget>[
        for (int i = 0; i < steps.length; i++)
          Padding(
            padding: EdgeInsets.only(
              bottom: i == steps.length - 1 ? 0 : IosSpace.md,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: IosColors.brand.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(
                      fontSize: IosText.caption1,
                      fontWeight: FontWeight.w700,
                      color: IosColors.brand,
                    ),
                  ),
                ),
                const SizedBox(width: IosSpace.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        steps[i].$1,
                        style: TextStyle(
                          fontSize: IosText.subheadline,
                          fontWeight: FontWeight.w600,
                          color: IosColors.label(b),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        steps[i].$2,
                        style: TextStyle(
                          fontSize: IosText.footnote,
                          color: IosColors.secondaryLabel(b),
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

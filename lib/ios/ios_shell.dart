/// iOS 一级页外壳 —— `app_shell.dart` 的 Cupertino 对位实现。
///
/// 对应需求：
///  * 第 1 条 —— 底栏使用苹果官方 **`CNTabBar`**（原生 `UITabBar`，
///    iOS 26 上是系统原厂 Liquid Glass 材质）。不用自绘玻璃、不做凸起悬浮球。
///  * 第 3、4 条 —— 整个外壳用原生 + Cupertino 组件实现，不复用 Material 外壳。
///
/// 与安卓版的结构差异说明：
///  安卓版是「一个 shell + 页内分节标题」；iOS 版按 HIG 改成
///  **`CupertinoTabScaffold` 三 Tab + 各自独立的大标题**——
///  这是 iOS 第一方 App（设置、App Store、健康）的标准骨架。
library;

import 'package:cupertino_native_better/cupertino_native.dart';
import 'package:flutter/cupertino.dart';

import 'ios_nav.dart';
import 'ios_theme.dart';
import 'ios_widgets.dart';
import 'printer_menu_page_ios.dart';
import 'scan_page_ios.dart';
import 'templates_ios.dart';

/// iOS 一级页外壳。
///
/// - `CNTabBar`（**原生 `UITabBar`**，iOS 26 上是苹果原厂 Liquid Glass 材质）
/// - 三个等规格 Tab：模板 / 扫码 / 打印机
///
/// **为什么不再用扫码悬浮球**（用户 2026-10-05 需求）：
/// 悬浮球浮在内容之上、底栏中间空一格，功能入口分成两处，
/// 用户要「在菜单栏里找到它」而不是「在页面上找它」。
/// 现在三个入口都是平级的标签，底栏本身就是完整的导航。
class IosHomeShell extends StatefulWidget {
  const IosHomeShell({super.key});

  @override
  State<IosHomeShell> createState() => _IosHomeShellState();
}

class _IosHomeShellState extends State<IosHomeShell> {
  int _index = 0;

  /// 三个 Tab 各自一个 `Navigator`（HIG 要求 Tab 内导航互相独立，
  /// 切 Tab 不丢各自的页面栈）。
  late final List<GlobalKey<NavigatorState>> _navKeys =
      List<GlobalKey<NavigatorState>>.generate(
        3,
        (_) => GlobalKey<NavigatorState>(),
      );

  @override
  Widget build(BuildContext context) {
    final Brightness b = iosBrightness(context);
    // 底部安全区（home indicator 高度）：原生 UITabBar 的标准高度是
    // 内容区 49pt + 安全区，两者相加才是 platform view 的完整 frame。
    final double bottomInset = MediaQuery.of(context).padding.bottom;

    return CupertinoPageScaffold(
      backgroundColor: IosColors.grouped(b),
      child: Stack(
        children: <Widget>[
          // 三个 Tab 用 IndexedStack 常驻：切 Tab 不重建、不丢状态。
          Positioned.fill(
            child: IndexedStack(
              index: _index,
              children: <Widget>[
                for (int i = 0; i < 3; i++)
                  Navigator(
                    key: _navKeys[i],
                    // 每层导航只处理自己栈内的返回，不吞掉底层的。
                    onGenerateRoute: (RouteSettings s) =>
                        CupertinoPageRoute<void>(
                          settings: s,
                          builder: (_) => _pageFor(i),
                        ),
                  ),
              ],
            ),
          ),

          // ★ 原生 `UITabBar`（iOS 26 上是苹果原厂 Liquid Glass）。
          //   自己定位在底部，而不是塞进 `CupertinoTabScaffold`
          //   —— 后者只接受 Flutter 自绘的 `CupertinoTabBar`。
          //
          //   需求（2026-10-05 第 2 轮）第 1 条：
          //   「整体轮廓上下宽度稍微小一些，横向占满，参照 App Store 的菜单栏；
          //     图标占比太大，需要协调」。
          //   → 显式给 `height` 收窄（不传时用原生上报高度，含安全区，会偏高）；
          //     `iconSize` 从 25 降到 23，让图标与 17pt 文字更协调。
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: CNTabBar(
              currentIndex: _index,
              tint: IosColors.brand,
              height: IosSize.tabBar + bottomInset,
              iconSize: 22,
              items: const <CNTabBarItem>[
                CNTabBarItem(
                  label: '模板',
                  icon: CNSymbol('square.grid.2x2'),
                  activeIcon: CNSymbol('square.grid.2x2.fill'),
                ),
                CNTabBarItem(
                  label: '扫码',
                  icon: CNSymbol('qrcode.viewfinder'),
                ),
                CNTabBarItem(
                  label: '打印机',
                  icon: CNSymbol('printer'),
                  activeIcon: CNSymbol('printer.fill'),
                ),
              ],
              onTap: _onTabTapped,
            ),
          ),
        ],
      ),
    );
  }

  /// 点击底栏标签。
  ///
  /// 需求（2026-10-05 第 2 轮）二级菜单第 2 条：
  /// 「在二级以下菜单，点击对应按钮（比如模板、或者打印机）回到对应按钮的一级菜单」。
  ///
  /// 这是 iOS 第一方 App 的标准行为（设置、App Store 都这样）：
  /// * 点**别的**标签 → 切过去，并**保留**该标签原有的页面栈；
  /// * 点**当前**标签 → 若已在二级以下，则 pop 回该标签的根页。
  void _onTabTapped(int i) {
    iosHaptic(HapticFeedbackType.selection);
    final NavigatorState nav = _navKeys[i].currentState!;
    if (i == _index) {
      // 同一个标签：只要有下级页面就弹回去。
      nav.popUntil((Route<dynamic> r) => r.isFirst);
      return;
    }
    setState(() => _index = i);
  }

  Widget _pageFor(int i) {
    switch (i) {
      case 1:
        return const IosScanPage();
      case 2:
        return const IosPrinterMenuPage();
      case 0:
      default:
        return const IosTemplatesTab();
    }
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
                  subtitle: '自定标题与两个日期',
                  icon: CupertinoIcons.time,
                  tint: IosColors.tplGenericTint,
                  iconFill: IosColors.tplGenericFill,
                  onTap: () =>
                      iosPush<void>(context, const IosGenericTemplatePage()),
                ),
                IosGridCard(
                  title: '康普茶',
                  subtitle: '自动算一发二发日期',
                  icon: CupertinoIcons.drop,
                  tint: IosColors.tplKombuchaTint,
                  iconFill: IosColors.tplKombuchaFill,
                  onTap: () =>
                      iosPush<void>(context, const IosKombuchaTemplatePage()),
                ),
                IosGridCard(
                  title: '奶制品',
                  subtitle: '按品类套保质期',
                  icon: CupertinoIcons.lab_flask,
                  tint: IosColors.tplDairyTint,
                  iconFill: IosColors.tplDairyFill,
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
///
/// **图标改为「色块底片 + 深色图标」**（用户 2026-10-05 细节打磨需求）：
/// 原来三个模板都是同一套线框图标、同一颜色，扫一眼分不出区别；
/// 现在每个模板有自己的标识色，图标坐在同色系的淡色方块里。
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
    this.tint,
    this.iconFill,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget? badge;

  /// 强调态（「添加打印机」用）。
  final bool highlight;

  /// 图标主色。为 null 时回落到品牌色。
  final Color? tint;

  /// 图标底片色（同色系淡色）。为 null 时不画底片。
  final Color? iconFill;

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
                    if (widget.iconFill != null)
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: widget.iconFill,
                          borderRadius: BorderRadius.circular(IosRadius.m),
                        ),
                        child: Icon(
                          widget.icon,
                          size: 28,
                          color: widget.tint ?? IosColors.brand,
                        ),
                      )
                    else
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

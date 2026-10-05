/// iOS 设计基座 —— 对齐 Apple Human Interface Guidelines。
///
/// 本文件只放**纯常量**，不含任何 widget，供 `ios_widgets.dart` 与各 iOS 页面引用。
///
/// 设计原则（对应需求第 3、4 条）：
///  1. 数值一律取自 Apple HIG 的系统标准（字号 17/15/13/11、8pt 间距网格、
///     圆角 10/12/14/16、系统蓝 #007AFF、系统灰阶 #F2F2F7 / #FFFFFF / #1C1C1E）。
///  2. iOS 侧**不复用** `lib/ui_kit.dart` 的 Material 组件，两边各自演进（需求第 8 条）。
library;

import 'package:flutter/cupertino.dart';

// ---------------------------------------------------------------------------
// 颜色 —— 全部取自 iOS 系统调色板（Light / Dark 双套，跟随系统）
// ---------------------------------------------------------------------------

/// iOS 系统标准色。
abstract final class IosColors {
  // ---- 系统语义色 ----
  static const Color blue = Color(0xFF007AFF); // systemBlue
  static const Color green = Color(0xFF34C759); // systemGreen
  static const Color red = Color(0xFFFF3B30); // systemRed
  static const Color orange = Color(0xFFFF9500); // systemOrange
  static const Color gray = Color(0xFF8E8E93); // systemGray
  static const Color gray2 = Color(0xFFAEAEB2); // systemGray2
  static const Color gray3 = Color(0xFFC7C7CC); // systemGray3
  static const Color gray4 = Color(0xFFD1D1D6); // systemGray4

  // ---- 品牌色：沿用安卓端主色（#00695C），保证两端观感一致 ----
  static const Color brand = Color(0xFF00695C);
  static const Color brandLight = Color(0xFF4DB6AC);

  // ---- 分组列表背景（grouped background）----
  static const Color groupedLight = Color(0xFFF2F2F7); // light: systemGroupedBackground
  static const Color groupedDark = Color(0xFF000000); // dark
  static const Color cardLight = Color(0xFFFFFFFF); // light: secondarySystemGroupedBackground
  static const Color cardDark = Color(0xFF1C1C1E); // dark

  // ---- 分隔线 ----
  static const Color separatorLight = Color(0x1F3C3C43); // 12% 黑
  static const Color separatorDark = Color(0x5C545458); // 36% 白

  // ---- 文字 ----
  static const Color labelLight = Color(0xFF000000);
  static const Color labelDark = Color(0xFFFFFFFF);
  static const Color secondaryLabelLight = Color(0x993C3C43); // 60%
  static const Color secondaryLabelDark = Color(0x99EBEBF5);
  static const Color tertiaryLabelLight = Color(0x4D3C3C43); // 30%
  static const Color tertiaryLabelDark = Color(0x4CEBEBF5);

  /// 按亮度取分组背景色。
  static Color grouped(Brightness b) =>
      b == Brightness.dark ? groupedDark : groupedLight;

  /// 按亮度取卡片背景色。
  static Color card(Brightness b) =>
      b == Brightness.dark ? cardDark : cardLight;

  /// 按亮度取分隔线。
  static Color separator(Brightness b) =>
      b == Brightness.dark ? separatorDark : separatorLight;

  /// 按亮度取主文字色。
  static Color label(Brightness b) =>
      b == Brightness.dark ? labelDark : labelLight;

  /// 按亮度取次级文字色。
  static Color secondaryLabel(Brightness b) =>
      b == Brightness.dark ? secondaryLabelDark : secondaryLabelLight;

  /// 按亮度取三级文字色。
  static Color tertiaryLabel(Brightness b) =>
      b == Brightness.dark ? tertiaryLabelDark : tertiaryLabelLight;
}

// ---------------------------------------------------------------------------
// 字号 —— 严格取 HIG 的 Dynamic Type 默认档（Large，body 17pt）
// ---------------------------------------------------------------------------

abstract final class IosText {
  static const double largeTitle = 34; // NavigationBar large title
  static const double title1 = 28;
  static const double title2 = 22;
  static const double title3 = 20;
  static const double headline = 17; // 半粗
  static const double body = 17;
  static const double callout = 16;
  static const double subheadline = 15;
  static const double footnote = 13;
  static const double caption1 = 12;
  static const double caption2 = 11;

  /// 表格 / 列表行主文字。
  static const TextStyle rowTitle = TextStyle(
    fontSize: body,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.41,
  );

  /// 分组头（UPPERCASE 灰色小字）。
  static const TextStyle groupHeader = TextStyle(
    fontSize: footnote,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.08,
  );

  /// 导航栏标题（inline）。
  static const TextStyle navTitle = TextStyle(
    fontSize: headline,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.41,
  );

  /// 大标题。
  static const TextStyle largeTitleStyle = TextStyle(
    fontSize: largeTitle,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.37,
  );

  /// 表格行右侧的次级说明。
  static const TextStyle rowDetail = TextStyle(
    fontSize: body,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.41,
  );

  /// 卡片内的小标签。
  static const TextStyle smallLabel = TextStyle(
    fontSize: footnote,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.08,
  );
}

// ---------------------------------------------------------------------------
// 间距 —— 8pt 网格，辅以 HIG 常用的 2 / 4 / 6 细调值
// ---------------------------------------------------------------------------

abstract final class IosSpace {
  static const double xxs = 2;
  static const double xs = 4;
  static const double s = 6;
  static const double sm = 8;
  static const double smd = 10;
  static const double m = 12;
  static const double md = 14;
  static const double ml = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 44;

  /// 屏幕左右安全边距（iOS 分组列表标准）。
  static const double screenH = 16;

  /// 分组卡片之间的间距。
  static const double groupGap = 28;

  /// 分组内行高（HIG: 44pt 最小可点区域）。
  static const double rowHeight = 44;
}

// ---------------------------------------------------------------------------
// 圆角 —— 连续圆角（squircle）半径
// ---------------------------------------------------------------------------

abstract final class IosRadius {
  /// 小组件 / 标签。
  static const double xs = 6;
  static const double s = 8;

  /// 列表行内嵌控件。
  static const double m = 10;

  /// 按钮 / 输入框。
  static const double button = 12;

  /// 卡片。
  static const double card = 16;

  /// 大卡片 / 分组容器。
  static const double lg = 20;
  static const double xl = 26;

  static const BorderRadius rCard = BorderRadius.all(Radius.circular(card));
  static const BorderRadius rButton = BorderRadius.all(Radius.circular(button));
  static const BorderRadius rMed = BorderRadius.all(Radius.circular(m));
}

// ---------------------------------------------------------------------------
// 动效 —— 贴合 iOS 的曲线与时长
// ---------------------------------------------------------------------------

abstract final class IosMotion {
  /// iOS 默认缓动（接近 CAMediaTimingFunction default）。
  static const Curve standard = Curves.easeInOutCubic;

  /// 弹性回弹（用于底栏显隐、sheet 弹出）。
  static const Curve spring = Curves.easeOutBack;

  static const Duration fast = Duration(milliseconds: 180);
  static const Duration normal = Duration(milliseconds: 280);
  static const Duration slow = Duration(milliseconds: 350);
}

// ---------------------------------------------------------------------------
// 液态玻璃近似 —— iOS 26 Liquid Glass 的 Flutter 视觉仿制
// ---------------------------------------------------------------------------

/// ⚠️ 技术边界：Flutter 是自绘引擎，**无法调用 iOS 26 真正的 Liquid Glass 材质**
/// （那是 UIKit / SwiftUI 层面的系统材质）。这里用
/// `模糊(BackdropFilter) + 半透明渐变 + 高光描边` 做**视觉近似**。
///
/// 需求第 1 条要求的「全面使用 Liquid Glass」→ 用本类统一实现，
/// 各页面不得自行散写模糊参数，保证观感一致。
abstract final class IosGlass {
  /// 素材模糊半径。
  static const double blur = 30;

  /// 顶部高光强度（模拟玻璃边缘折射）。
  static const double highlightTop = 0.55;
  static const double highlightBottom = 0.18;

  /// 玻璃底色的不透明度（吃背后的内容，但不糊）。
  static const List<double> fillOpacity = <double>[0.72, 0.52];

  /// 描边（1px 高光边）。
  static const double borderWidth = 0.6;

  /// 浅色模式玻璃底色。
  static const List<Color> tintLight = <Color>[
    Color(0xFFFFFFFF),
    Color(0xFFF7F9F8),
  ];

  /// 深色模式玻璃底色。
  static const List<Color> tintDark = <Color>[
    Color(0xFF2C2C2E),
    Color(0xFF1C1C1E),
  ];

  /// 玻璃投影（低对比、大扩散，模拟悬浮）。
  static const List<BoxShadow> shadow = <BoxShadow>[
    BoxShadow(
      color: Color(0x14000000),
      blurRadius: 28,
      offset: Offset(0, 10),
    ),
    BoxShadow(
      color: Color(0x0A000000),
      blurRadius: 4,
      offset: Offset(0, 1),
    ),
  ];
}

// ---------------------------------------------------------------------------
// 尺寸 —— 底栏等固定高度
// ---------------------------------------------------------------------------

abstract final class IosSize {
  /// CupertinoTabBar 标准高度（HIG: 49pt + 安全区）。
  static const double tabBar = 49;

  /// 页面底部为悬浮底栏预留的留白。
  static const double tabBarInset = 96;

  /// 主操作按钮高度（HIG 大按钮常用 50）。
  static const double primaryButton = 50;

  /// 列表行内图标尺寸。
  static const double rowIcon = 22;
}

// ---------------------------------------------------------------------------
// 亮度取值 —— ⚠️ 必须用它，不要直接写 CupertinoTheme.of(context).brightness
// ---------------------------------------------------------------------------

/// 安全取当前亮度。
///
/// ⚠️ 坑：`CupertinoThemeData.brightness` 的类型是 **`Brightness?`**
/// （Cupertino 主题允许不覆写亮度，此时为 null 表示跟随系统）。
/// 直接 `final Brightness b = CupertinoTheme.of(context).brightness;`
/// 会报 `invalid_assignment`。所有 iOS 组件必须走本函数。
Brightness iosBrightness(BuildContext context) {
  return CupertinoTheme.of(context).brightness ??
      MediaQuery.maybeOf(context)?.platformBrightness ??
      Brightness.light;
}

/// iOS 语义图标 —— `CupertinoIcons` 里没有 `qr_code`，
/// 统一在这里映射，避免各文件各写一个导致不一致。
abstract final class IosIcons {
  /// 二维码 / 标签（对应 Material 的 Icons.qr_code_2）。
  static const IconData qrCode = CupertinoIcons.qrcode;

  /// 标签预览（右上角「保存到手机」）。
  static const IconData save = CupertinoIcons.arrow_down_to_line;

  /// 分享。
  static const IconData share = CupertinoIcons.share;

  /// 打印。
  static const IconData print = CupertinoIcons.printer;

  /// 打印不可用。
  static const IconData printDisabled = CupertinoIcons.printer_fill;

  /// 蓝牙。
  static const IconData bluetooth = CupertinoIcons.bluetooth;

  /// 扫码。
  static const IconData scanner = CupertinoIcons.barcode_viewfinder;

  /// 手电筒。
  static const IconData torch = CupertinoIcons.lightbulb;

  /// 切换摄像头。
  static const IconData flipCamera = CupertinoIcons.camera_rotate;

  /// 刷新。
  static const IconData refresh = CupertinoIcons.refresh;

  /// 添加。
  static const IconData add = CupertinoIcons.add_circled;

  /// 标签页 · 模板。
  static const IconData templates = CupertinoIcons.square_grid_2x2;

  /// 标签页 · 打印机。
  static const IconData printers = CupertinoIcons.printer_fill;
}


/// iOS 公共组件库 —— `lib/ui_kit.dart` 的 Cupertino 对位实现。
///
/// 与 `ui_kit.dart` 的组件一一对应（安卓继续用老的，iOS 走这一套，需求第 3、8 条）：
///
///  | 安卓（Material）      | iOS（Cupertino）        |
///  |----------------------|------------------------|
///  | SectionHeader        | IosSectionHeader       |
///  | AutoTimeBanner       | IosBanner              |
///  | FootNote             | IosFootNote            |
///  | GenerateButton       | IosPrimaryButton       |
///  | DateField            | IosDateField / IosPickerField |
///  | PreviewCard          | IosListGroup + IosListRow |
///  | EmptyStateCard       | IosEmptyState          |
///  | GlassButton          | IosSecondaryButton     |
///  | _QuickDates(ActionChip)| IosChipRow           |
///  | PreviewCard          | IosPreviewGroup        |
///
/// 额外提供 `LiquidGlassBar`（液态玻璃容器）与 `IosSheet`（底部 sheet 封装）。
library;

import 'package:cupertino_native_better/cupertino_native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import 'ios_theme.dart';

// ===========================================================================
// 1. 分节标题
// ===========================================================================

/// iOS 分组列表的节标题：左侧小字 +（可选）右侧说明。
///
/// 对齐 HIG：橙色/灰色 UPPERCASE 小标题 + 可选 trailing。
class IosSectionHeader extends StatelessWidget {
  const IosSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(
      IosSpace.screenH + 4,
      IosSpace.sm,
      IosSpace.screenH,
      IosSpace.sm,
    ),
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final Brightness b = iosBrightness(context);
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title.toUpperCase(),
                  style: IosText.groupHeader.copyWith(
                    color: IosColors.secondaryLabel(b),
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...<Widget>[
                  const SizedBox(height: IosSpace.xxs),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: IosText.caption1,
                      color: IosColors.tertiaryLabel(b),
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// 页面级大标题（HIG large title），用于一级页顶部。
class IosLargeTitle extends StatelessWidget {
  const IosLargeTitle({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final Brightness b = iosBrightness(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        IosSpace.screenH,
        IosSpace.sm,
        IosSpace.screenH,
        IosSpace.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: IosText.largeTitleStyle),
                if (subtitle != null && subtitle!.isNotEmpty) ...<Widget>[
                  const SizedBox(height: IosSpace.xs),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: IosText.subheadline,
                      color: IosColors.secondaryLabel(b),
                    ),
                  ),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

// ===========================================================================
// 2. 提示条（对应 AutoTimeBanner）
// ===========================================================================

/// iOS 风格的说明条：浅色底 + 图标 + 多行文案 +（可选）右侧操作。
class IosBanner extends StatelessWidget {
  const IosBanner({
    super.key,
    required this.lines,
    this.icon = CupertinoIcons.info_circle,
    this.tone = IosBannerTone.neutral,
    this.action,
    this.title,
  });

  final List<String> lines;
  final IconData icon;
  final IosBannerTone tone;
  final Widget? action;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final Brightness b = iosBrightness(context);

    final (Color bg, Color fg, Color iconColor) = switch (tone) {
      IosBannerTone.neutral => (
        IosColors.brand.withValues(alpha: b == Brightness.dark ? 0.22 : 0.09),
        IosColors.label(b),
        IosColors.brand,
      ),
      IosBannerTone.warn => (
        IosColors.orange.withValues(alpha: b == Brightness.dark ? 0.22 : 0.12),
        IosColors.label(b),
        IosColors.orange,
      ),
      IosBannerTone.danger => (
        IosColors.red.withValues(alpha: b == Brightness.dark ? 0.22 : 0.10),
        IosColors.label(b),
        IosColors.red,
      ),
      IosBannerTone.success => (
        IosColors.green.withValues(alpha: b == Brightness.dark ? 0.22 : 0.12),
        IosColors.label(b),
        IosColors.green,
      ),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(IosSpace.md),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(IosRadius.card),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 19, color: iconColor),
          const SizedBox(width: IosSpace.smd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (title != null && title!.isNotEmpty) ...<Widget>[
                  Text(
                    title!,
                    style: IosText.smallLabel.copyWith(color: fg),
                  ),
                  const SizedBox(height: IosSpace.xs),
                ],
                for (int i = 0; i < lines.length; i++)
                  Padding(
                    padding: EdgeInsets.only(top: i == 0 ? 0 : IosSpace.xs),
                    child: Text(
                      lines[i],
                      style: TextStyle(
                        fontSize: IosText.footnote,
                        color: fg.withValues(alpha: 0.86),
                        height: 1.5,
                      ),
                    ),
                  ),
                if (action != null) ...<Widget>[
                  const SizedBox(height: IosSpace.sm),
                  Align(alignment: Alignment.centerRight, child: action!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum IosBannerTone { neutral, warn, danger, success }

// ===========================================================================
// 3. 脚注
// ===========================================================================

class IosFootNote extends StatelessWidget {
  const IosFootNote({super.key, required this.text, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final Brightness b = iosBrightness(context);
    final Color c = IosColors.tertiaryLabel(b);
    if (icon == null) {
      return Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: IosText.caption1, color: c, height: 1.5),
        ),
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Icon(icon, size: 13, color: c),
        const SizedBox(width: IosSpace.xs),
        Flexible(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: IosText.caption1, color: c, height: 1.5),
          ),
        ),
      ],
    );
  }
}

// ===========================================================================
// 4. 按钮
// ===========================================================================

/// 主操作按钮（对应 GenerateButton）。
///
/// 走 `cupertino_native_better` 的原生 `UIButton`：
/// * `CNButtonStyle.prominentGlass` —— iOS 26 上是苹果原厂 Liquid Glass
///   的「突出」变体（有色玻璃底 + 白色高光），低版本自动回落 Flutter 实现。
/// * `busy` 时按钮自身不给 loading 态（原生按钮没有 spinner 契约），
///   改为不可点 + 文案切「生成中…」，视觉上等价。
///
/// ⚠️ 原生按钮是 `UiKitView`，**不能放进滚动长列表**；本按钮都放在
/// 表单页底部固定区，符合使用边界。
class IosPrimaryButton extends StatelessWidget {
  const IosPrimaryButton({
    super.key,
    required this.onPressed,
    this.label = '生成标签',
    this.icon = IosIcons.qrCode,
    this.busy = false,
    this.color,
  });

  final VoidCallback? onPressed;
  final String label;
  final IconData? icon;
  final bool busy;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: IosSize.primaryButton,
      child: CNButton(
        label: busy ? '生成中…' : label,
        icon: icon == IosIcons.qrCode ? const CNSymbol('qrcode') : null,
        tint: color ?? IosColors.brand,
        enabled: !busy && onPressed != null,
        onPressed: busy ? null : onPressed,
        config: const CNButtonConfig(
          style: CNButtonStyle.prominentGlass,
          width: double.infinity,
          minHeight: IosSize.primaryButton,
          borderRadius: IosRadius.button,
          labelFontSize: IosText.headline,
          labelFontWeight: FontWeight.w600,
          labelColor: CupertinoColors.white,
        ),
      ),
    );
  }
}

/// 次要按钮（对应 GlassButton）—— 原生玻璃底。
///
/// 走 `CNButtonStyle.glass`：iOS 26 上是苹果原厂玻璃材质，
/// 低版本回落 Flutter 自绘（仍比裸白底描边更接近系统观感）。
class IosSecondaryButton extends StatelessWidget {
  const IosSecondaryButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
    this.busy = false,
    this.expand = false,
  });

  final VoidCallback? onPressed;
  final String label;
  final IconData? icon;
  final bool busy;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final CNButtonConfig cfg = CNButtonConfig(
      style: CNButtonStyle.glass,
      width: expand ? double.infinity : null,
      shrinkWrap: !expand,
      minHeight: expand ? IosSize.primaryButton : null,
      borderRadius: IosRadius.button,
      labelFontSize: IosText.callout,
      labelFontWeight: FontWeight.w600,
      labelColor: IosColors.brand,
    );
    return CNButton(
      label: busy ? '处理中…' : label,
      enabled: !busy && onPressed != null,
      onPressed: busy ? null : onPressed,
      tint: IosColors.brand,
      config: cfg,
    );
  }
}

/// 导航栏右侧的文字按钮（HIG：19pt 无底色）。
class IosNavAction extends StatelessWidget {
  const IosNavAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.destructive = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: IosSpace.sm),
      minimumSize: const Size(0, 34),
      pressedOpacity: 0.4,
      onPressed: busy ? null : onPressed,
      child: busy
          ? const SizedBox(
              width: 17,
              height: 17,
              child: CupertinoActivityIndicator(radius: 8),
            )
          : Text(
              label,
              style: TextStyle(
                fontSize: IosText.headline,
                fontWeight: FontWeight.w400,
                color: destructive ? IosColors.red : IosColors.blue,
                letterSpacing: -0.41,
              ),
            ),
    );
  }
}

// ===========================================================================
// 5. 分组列表容器（对应 PreviewCard / Card）
// ===========================================================================

/// iOS 分组卡片：白底 + 连续圆角 + 内嵌若干 `IosListRow`。
class IosListGroup extends StatelessWidget {
  const IosListGroup({
    super.key,
    this.header,
    this.footer,
    required this.children,
    this.padding = const EdgeInsets.symmetric(vertical: IosSpace.xs),
  });

  final Widget? header;
  final Widget? footer;
  final List<Widget> children;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final Brightness b = iosBrightness(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ?header,
        ClipRRect(
          borderRadius: BorderRadius.circular(IosRadius.card),
          child: Container(
            color: IosColors.card(b),
            padding: padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
        ?footer,
      ],
    );
  }
}

/// 分组内的一行：左图标 / 标题 / 副标题 + 右侧值或箭头。
class IosListRow extends StatelessWidget {
  const IosListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.leadingIcon,
    this.leadingColor,
    this.value,
    this.valueColor,
    this.trailing,
    this.onTap,
    this.showChevron = false,
    this.showDivider = true,
    this.titleColor,
    this.dense = false,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final IconData? leadingIcon;
  final Color? leadingColor;
  final String? value;
  final Color? valueColor;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showChevron;
  final bool showDivider;
  final Color? titleColor;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final Brightness b = iosBrightness(context);

    final Widget? lead = leading ??
        (leadingIcon != null
            ? SizedBox(
                width: 28,
                child: Icon(
                  leadingIcon,
                  size: IosSize.rowIcon,
                  color: leadingColor ?? IosColors.brand,
                ),
              )
            : null);

    final Widget content = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: IosSpace.ml,
        vertical: dense ? IosSpace.smd : IosSpace.m,
      ),
      child: Row(
        children: <Widget>[
          if (lead != null) ...<Widget>[lead, const SizedBox(width: IosSpace.m)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: TextStyle(
                    fontSize: IosText.body,
                    color: titleColor ?? IosColors.label(b),
                    letterSpacing: -0.41,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: IosText.footnote,
                        color: IosColors.secondaryLabel(b),
                        height: 1.3,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (value != null)
            Padding(
              padding: const EdgeInsets.only(left: IosSpace.sm),
              child: Text(
                value!,
                style: TextStyle(
                  fontSize: IosText.body,
                  color: valueColor ?? IosColors.secondaryLabel(b),
                  letterSpacing: -0.41,
                ),
              ),
            ),
          if (trailing != null) ...<Widget>[const SizedBox(width: IosSpace.sm), trailing!],
          if (showChevron) ...<Widget>[
            const SizedBox(width: IosSpace.s),
            Icon(
              CupertinoIcons.chevron_forward,
              size: 15,
              color: IosColors.tertiaryLabel(b),
            ),
          ],
        ],
      ),
    );

    final Widget body = onTap == null
        ? content
        : CupertinoButton(
            padding: EdgeInsets.zero,
            pressedOpacity: 0.55,
            onPressed: onTap,
            child: content,
          );

    if (!showDivider) return body;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        body,
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
}

/// 无边框的键值行（对应 PreviewCard 里的 `_kv`）。
class IosKeyValueRow extends StatelessWidget {
  const IosKeyValueRow({
    super.key,
    required this.label,
    required this.value,
    this.labelWidth = 84,
    this.onTap,
  });

  final String label;
  final String value;
  final double labelWidth;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Brightness b = iosBrightness(context);
    final Widget row = Padding(
      padding: const EdgeInsets.symmetric(vertical: IosSpace.s),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: labelWidth,
            child: Text(
              label,
              style: TextStyle(
                fontSize: IosText.subheadline,
                color: IosColors.secondaryLabel(b),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: IosText.subheadline,
                fontWeight: FontWeight.w600,
                color: IosColors.label(b),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
    return onTap == null
        ? row
        : CupertinoButton(
            padding: EdgeInsets.zero,
            pressedOpacity: 0.55,
            onPressed: onTap,
            child: row,
          );
  }
}

// ===========================================================================
// 6. 空态卡片
// ===========================================================================

class IosEmptyState extends StatelessWidget {
  const IosEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final Brightness b = iosBrightness(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: IosSpace.lg,
        vertical: IosSpace.xxl,
      ),
      decoration: BoxDecoration(
        color: IosColors.card(b),
        borderRadius: BorderRadius.circular(IosRadius.lg),
      ),
      child: Column(
        children: <Widget>[
          Icon(icon, size: 40, color: IosColors.tertiaryLabel(b)),
          const SizedBox(height: IosSpace.m),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: IosText.subheadline,
              fontWeight: FontWeight.w600,
              color: IosColors.secondaryLabel(b),
            ),
          ),
          if (body != null && body!.isNotEmpty) ...<Widget>[
            const SizedBox(height: IosSpace.s),
            Text(
              body!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: IosText.footnote,
                color: IosColors.tertiaryLabel(b),
                height: 1.5,
              ),
            ),
          ],
          if (action != null) ...<Widget>[
            const SizedBox(height: IosSpace.ml),
            action!,
          ],
        ],
      ),
    );
  }
}

// ===========================================================================
// 7. 选择器（对应 DateField 以及所有「安卓味下拉」）
// ===========================================================================

/// 通用选择行：点击后在底部弹出 CupertinoPicker / 自定义 sheet。
///
/// 用于替代安卓侧的 `DropdownButtonFormField`（需求第 7 条点名的问题）。
class IosPickerField<T> extends StatelessWidget {
  const IosPickerField({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
    this.placeholder = '请选择',
    this.icon,
    this.helper,
    this.enabled = true,
    this.lockedHint,
  });

  final String label;
  final T? value;
  final List<T> items;
  final String Function(T) itemLabel;
  final ValueChanged<T> onChanged;
  final String placeholder;
  final IconData? icon;
  final String? helper;
  final bool enabled;
  final String? lockedHint;

  Future<void> _pick(BuildContext context) async {
    final int initial = value == null ? 0 : items.indexOf(value as T);
    final T? result = await showIosPickerSheet<T>(
      context,
      title: label,
      items: items,
      itemLabel: itemLabel,
      initialIndex: initial < 0 ? 0 : initial,
    );
    if (result != null) onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = iosBrightness(context);
    final bool hasValue = value != null;
    final Color fg = hasValue
        ? IosColors.label(b)
        : IosColors.tertiaryLabel(b);

    final Widget row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: IosSpace.ml,
        vertical: IosSpace.m,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(
                  icon,
                  size: IosSize.rowIcon,
                  color: enabled
                      ? IosColors.brand
                      : IosColors.tertiaryLabel(b),
                ),
                const SizedBox(width: IosSpace.m),
              ],
              Expanded(
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
                    const SizedBox(height: 3),
                    Text(
                      hasValue ? itemLabel(value as T) : placeholder,
                      style: TextStyle(
                        fontSize: IosText.body,
                        color: enabled ? fg : IosColors.tertiaryLabel(b),
                        letterSpacing: -0.41,
                      ),
                    ),
                  ],
                ),
              ),
              if (lockedHint != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: IosSpace.sm,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: IosColors.gray.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(IosRadius.xs),
                  ),
                  child: Text(
                    lockedHint!,
                    style: TextStyle(
                      fontSize: IosText.caption2,
                      color: IosColors.secondaryLabel(b),
                    ),
                  ),
                )
              else if (enabled)
                Icon(
                  CupertinoIcons.chevron_up_chevron_down,
                  size: 14,
                  color: IosColors.tertiaryLabel(b),
                ),
            ],
          ),
          if (helper != null && helper!.isNotEmpty) ...<Widget>[
            const SizedBox(height: IosSpace.s),
            Text(
              helper!,
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

    if (!enabled) return row;

    return CupertinoButton(
      padding: EdgeInsets.zero,
      pressedOpacity: 0.55,
      onPressed: () => _pick(context),
      child: row,
    );
  }
}

/// 日期选择行（对应 DateField），点击弹 `CupertinoDatePicker`。
class IosDateField extends StatelessWidget {
  const IosDateField({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
    this.icon,
    this.trailing,
  });

  final String label;
  final DateTime value;
  final VoidCallback onTap;
  final IconData? icon;
  final Widget? trailing;

  static String format(DateTime d) => '${d.year}年${d.month}月${d.day}日';

  @override
  Widget build(BuildContext context) {
    final Brightness b = iosBrightness(context);
    return CupertinoButton(
      padding: EdgeInsets.zero,
      pressedOpacity: 0.55,
      onPressed: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: IosSpace.ml,
          vertical: IosSpace.m,
        ),
        child: Row(
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: IosSize.rowIcon, color: IosColors.brand),
              const SizedBox(width: IosSpace.m),
            ],
            Expanded(
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
                  const SizedBox(height: 3),
                  Text(
                    format(value),
                    style: TextStyle(
                      fontSize: IosText.body,
                      color: IosColors.label(b),
                      letterSpacing: -0.41,
                    ),
                  ),
                ],
              ),
            ),
            trailing ??
                Icon(
                  CupertinoIcons.calendar,
                  size: 20,
                  color: IosColors.tertiaryLabel(b),
                ),
          ],
        ),
      ),
    );
  }
}

/// 底部弹出的 CupertinoPicker（带「取消 / 完成」栏），返回选中项。
Future<T?> showIosPickerSheet<T>(
  BuildContext context, {
  required String title,
  required List<T> items,
  required String Function(T) itemLabel,
  int initialIndex = 0,
}) {
  return showCupertinoModalPopup<T>(
    context: context,
    builder: (BuildContext ctx) {
      final Brightness b = iosBrightness(ctx);
      int index = initialIndex.clamp(0, items.isEmpty ? 0 : items.length - 1);
      return Container(
        height: 296,
        color: IosColors.card(b),
        child: Column(
          children: <Widget>[
            Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: IosSpace.sm),
              decoration: BoxDecoration(
                color: IosColors.card(b),
                border: Border(
                  bottom: BorderSide(color: IosColors.separator(b), width: 0.5),
                ),
              ),
              child: Row(
                children: <Widget>[
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: IosSpace.m),
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text(
                      '取消',
                      style: TextStyle(
                        fontSize: IosText.headline,
                        color: IosColors.blue,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: IosText.navTitle,
                    ),
                  ),
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: IosSpace.m),
                    onPressed: items.isEmpty
                        ? null
                        : () => Navigator.of(ctx).pop(items[index]),
                    child: const Text(
                      '完成',
                      style: TextStyle(
                        fontSize: IosText.headline,
                        fontWeight: FontWeight.w600,
                        color: IosColors.blue,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Text(
                        '暂无可选项',
                        style: TextStyle(
                          fontSize: IosText.subheadline,
                          color: IosColors.secondaryLabel(b),
                        ),
                      ),
                    )
                  : CupertinoPicker(
                      itemExtent: 44,
                      scrollController:
                          FixedExtentScrollController(initialItem: index),
                      onSelectedItemChanged: (int i) => index = i,
                      children: <Widget>[
                        for (final T it in items)
                          Center(
                            child: Text(
                              itemLabel(it),
                              style: TextStyle(
                                fontSize: IosText.title3,
                                color: IosColors.label(b),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      );
    },
  );
}

/// 弹出 iOS 日历（CupertinoDatePicker, mode: date），返回选中的日期。
Future<DateTime?> showIosDatePicker(
  BuildContext context, {
  required DateTime initial,
  DateTime? minimum,
  DateTime? maximum,
}) {
  return showCupertinoModalPopup<DateTime>(
    context: context,
    builder: (BuildContext ctx) {
      final Brightness b = iosBrightness(ctx);
      DateTime temp = initial;
      return Container(
        height: 320,
        color: IosColors.card(b),
        child: Column(
          children: <Widget>[
            Container(
              height: 44,
              decoration: BoxDecoration(
                color: IosColors.card(b),
                border: Border(
                  bottom: BorderSide(color: IosColors.separator(b), width: 0.5),
                ),
              ),
              child: Row(
                children: <Widget>[
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: IosSpace.m),
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text(
                      '取消',
                      style: TextStyle(
                        fontSize: IosText.headline,
                        color: IosColors.blue,
                      ),
                    ),
                  ),
                  const Spacer(),
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: IosSpace.m),
                    onPressed: () => Navigator.of(ctx).pop(temp),
                    child: const Text(
                      '完成',
                      style: TextStyle(
                        fontSize: IosText.headline,
                        fontWeight: FontWeight.w600,
                        color: IosColors.blue,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.date,
                initialDateTime: initial,
                minimumDate: minimum ?? DateTime(2020),
                maximumDate: maximum ?? DateTime(2100),
                onDateTimeChanged: (DateTime v) => temp = v,
              ),
            ),
          ],
        ),
      );
    },
  );
}

// ===========================================================================
// 8. 芯片行（对应 _QuickDates 的 ActionChip）
// ===========================================================================

/// iOS 风格的快捷选项行 —— 圆角胶囊，选中态填充品牌色。
class IosChipRow extends StatelessWidget {
  const IosChipRow({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
    this.recommendedIndex,
  });

  /// 每项：文案。
  final List<String> labels;

  /// 当前选中项（-1 表示无）。
  final int selectedIndex;

  final ValueChanged<int> onSelected;

  /// 带星标推荐项的索引。
  final int? recommendedIndex;

  @override
  Widget build(BuildContext context) {
    final Brightness b = iosBrightness(context);
    return Wrap(
      spacing: IosSpace.sm,
      runSpacing: IosSpace.sm,
      children: <Widget>[
        for (int i = 0; i < labels.length; i++)
          _chip(
            context,
            b,
            label: labels[i],
            selected: i == selectedIndex,
            recommended: i == recommendedIndex,
            onTap: () => onSelected(i),
          ),
      ],
    );
  }

  Widget _chip(
    BuildContext context,
    Brightness b, {
    required String label,
    required bool selected,
    required bool recommended,
    required VoidCallback onTap,
  }) {
    final Color border = selected
        ? IosColors.brand
        : (recommended
            ? IosColors.brand.withValues(alpha: 0.45)
            : IosColors.separator(b));
    return CupertinoButton(
      padding: EdgeInsets.zero,
      pressedOpacity: 0.6,
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: IosSpace.m,
          vertical: IosSpace.s,
        ),
        decoration: BoxDecoration(
          color: selected
              ? IosColors.brand
              : IosColors.card(b).withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: border,
            width: selected ? 0 : 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (recommended && !selected) ...<Widget>[
              const Icon(
                CupertinoIcons.star_fill,
                size: 11,
                color: IosColors.brand,
              ),
              const SizedBox(width: 3),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: IosText.subheadline,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? CupertinoColors.white : IosColors.label(b),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// 9. 液态玻璃容器（需求第 1 条）
// ===========================================================================

/// 液态玻璃材质层。
///
/// 走 `cupertino_native_better` 的原生 `UIVisualEffectView`：
/// **iOS 26+ 上是苹果原厂 Liquid Glass**（真实折射 + 高光 + 自适应着色），
/// 低版本由包自动回落 Flutter 实现（`BackdropFilter` 模糊近似）。
///
/// ⚠️ 原生视图不能进滚动长列表；本组件用于固定悬浮元素。
/// 若外层是弹窗 / sheet，需配合 `CNTabBarRouteObserver`（已在 `main.dart` 注册）。
class LiquidGlassSurface extends StatelessWidget {
  const LiquidGlassSurface({
    super.key,
    required this.child,
    this.borderRadius,
    this.blur = IosGlass.blur,
    this.padding,
    this.tint,
  });

  final Widget child;
  final BorderRadius? borderRadius;
  final double blur;
  final EdgeInsetsGeometry? padding;
  final List<Color>? tint;

  @override
  Widget build(BuildContext context) {
    final double r = borderRadius?.topLeft.x ?? IosRadius.xl;
    final Widget inner = padding == null
        ? child
        : Padding(padding: padding!, child: child);
    return LiquidGlassContainer(
      config: LiquidGlassConfig(
        cornerRadius: r,
        tint: tint?.isNotEmpty == true ? tint!.first : null,
      ),
      child: inner,
    );
  }
}

// ===========================================================================
// 10. 工具函数
// ===========================================================================

/// 触发 iOS 风格的轻震动反馈（选择、切换时用）。
Future<void> iosHaptic([HapticFeedbackType type = HapticFeedbackType.light]) async {
  switch (type) {
    case HapticFeedbackType.light:
      await HapticFeedback.lightImpact();
    case HapticFeedbackType.medium:
      await HapticFeedback.mediumImpact();
    case HapticFeedbackType.selection:
      await HapticFeedback.selectionClick();
  }
}

enum HapticFeedbackType { light, medium, selection }

/// iOS 风格的长按上下文菜单（CupertinoContextMenu 的薄封装）。
Widget iosContextMenu({
  required Widget child,
  required List<Widget> actions,
}) {
  return CupertinoContextMenu(
    actions: actions,
    child: child,
  );
}

/// 分组列表页面的标准内边距。
const EdgeInsets kIosListPadding = EdgeInsets.fromLTRB(
  IosSpace.screenH,
  IosSpace.sm,
  IosSpace.screenH,
  IosSpace.xxxl,
);

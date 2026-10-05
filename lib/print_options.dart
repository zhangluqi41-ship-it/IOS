import 'package:flutter/material.dart';

import 'printer.dart';

/// 打印参数编辑器 —— 硕方与通用机型共用，按型号显示各自的项。
///
/// 硕方 T50 Pro：份数 / 纸张类型 / 间隙 / 浓度
/// 通用标签机 TSPL：份数 / 间隙 / 浓度 / 速度 / 打印头点数 / 黑白取反
/// 通用热敏机 ESC/POS：份数 / 打印头点数 / 走纸行数 / 黑白取反
class PrintOptionsEditor extends StatelessWidget {
  const PrintOptionsEditor({
    super.key,
    required this.kind,
    required this.options,
    required this.onChanged,
  });

  final PrinterKind kind;
  final PrintOptions options;
  final ValueChanged<PrintOptions> onChanged;

  void _set(PrintOptions next) => onChanged(next);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showGap = kind != PrinterKind.escpos;
    final showDensity = kind != PrinterKind.escpos;
    final showSpeed = kind == PrinterKind.tspl;
    final generic = kind.isGeneric;

    final densityMax = kind == PrinterKind.tspl ? 15.0 : 9.0;
    final densityMin = kind == PrinterKind.tspl ? 0.0 : 1.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _slider(
          context,
          label: '份数',
          value: '${options.copies}',
          v: options.copies.toDouble(),
          min: 1,
          max: 5,
          divisions: 4,
          onChanged: (v) => _set(options.copyWith(copies: v.round())),
        ),
        if (showGap)
          _slider(
            context,
            label: '纸张间隙',
            value: '${options.gap} mm',
            v: options.gap.toDouble(),
            min: 0,
            max: 8,
            divisions: 8,
            onChanged: (v) => _set(options.copyWith(gap: v.round())),
            hint: '走纸定位不准时调它',
          ),
        if (showDensity)
          _slider(
            context,
            label: '浓度',
            value: '${options.density}',
            v: options.density.toDouble(),
            min: densityMin,
            max: densityMax,
            divisions: (densityMax - densityMin).round(),
            onChanged: (v) => _set(options.copyWith(density: v.round())),
          ),
        if (showSpeed)
          _slider(
            context,
            label: '打印速度',
            value: '${options.speed}',
            v: options.speed.toDouble(),
            min: 1,
            max: 6,
            divisions: 5,
            onChanged: (v) => _set(options.copyWith(speed: v.round())),
            hint: '越大越快，字迹越淡',
          ),
        if (kind == PrinterKind.supvan) ...[
          const SizedBox(height: 6),
          Text('纸张类型', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: PaperType.values.map((t) {
              return ChoiceChip(
                label: Text(t.label),
                selected: options.paperType == t,
                onSelected: (_) => _set(options.copyWith(paperType: t)),
              );
            }).toList(),
          ),
        ],
        if (generic) ...[
          const SizedBox(height: 10),
          Text('打印头点数', style: theme.textTheme.labelLarge),
          const SizedBox(height: 2),
          Text(
            '按打印机实际宽度选：50mm 机型多为 400 点，48mm 机型 384 点，'
            '80mm 票据机 576 点。打出来偏窄或右侧被切掉就是这里选错了。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [384, 400, 576].map((d) {
              return ChoiceChip(
                label: Text('$d 点'),
                selected: options.headDots == d,
                onSelected: (_) => _set(options.copyWith(headDots: d)),
              );
            }).toList(),
          ),
          if (kind == PrinterKind.escpos)
            _slider(
              context,
              label: '走纸行数',
              value: '${options.feedLines}',
              v: options.feedLines.toDouble(),
              min: 0,
              max: 8,
              divisions: 8,
              onChanged: (v) => _set(options.copyWith(feedLines: v.round())),
              hint: '打完空走几行，方便撕纸',
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: options.invert,
            onChanged: (v) => _set(options.copyWith(invert: v)),
            title: const Text('黑白取反'),
            subtitle: const Text(
              '如果打出来是「黑底白字」，说明这台机器 0 才是黑点，把它打开',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ],
    );
  }

  Widget _slider(
    BuildContext context, {
    required String label,
    required String value,
    required double v,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
    String? hint,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(width: 76, child: Text(label)),
            Expanded(
              child: Slider(
                value: v.clamp(min, max),
                min: min,
                max: max,
                divisions: divisions,
                label: value,
                onChanged: onChanged,
              ),
            ),
            SizedBox(
              width: 56,
              child: Text(value, textAlign: TextAlign.right),
            ),
          ],
        ),
        if (hint != null)
          Padding(
            padding: const EdgeInsets.only(left: 76, bottom: 4),
            child: Text(
              hint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
      ],
    );
  }
}

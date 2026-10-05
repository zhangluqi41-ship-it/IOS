/// iOS 扫码页 —— 按**需求第 6 条**重做。
///
/// 逐条落实：
///  ① 「点开后不要有扫描二维码」→ 去掉导航栏标题与整个 AppBar，
///     改为**全屏取景 + 顶部悬浮返回按钮**；
///  ② 「不要有对准康普茶」→ 删掉原来的「请对准康普茶瓶身上的二维码」提示，
///     文案改为**通用**的（识别失败时才提示，且不预设品类）；
///  ③ 「把右上角的两个按钮融合到屏幕下方两侧」→ 手电筒 / 切换摄像头
///     移到**屏幕底部左右两侧**；
///  ④ 「绿框改一下，增加一些设计感」→ 用**四角折线取景框 + 中心扫描线动画**
///     替换原来的绿色方框（不再是实心描边矩形）。
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:mobile_scanner/mobile_scanner.dart';

import '../label_pdf.dart';
import '../label_renderer.dart';
import '../label_template.dart';
import '../preview_page.dart';
import 'ios_theme.dart';
import 'ios_widgets.dart';

/// iOS 扫码页：扫「康普茶一发」标签 → 输入二发水果 → 生成二发标签。
class IosScanPage extends StatefulWidget {
  const IosScanPage({super.key});

  @override
  State<IosScanPage> createState() => _IosScanPageState();
}

class _IosScanPageState extends State<IosScanPage> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  /// 已识别到标签、正在处理中，避免重复触发。
  bool _busy = false;

  /// 已识别到标签但解析失败时的提示（不预设品类）。
  String? _hintText;
  DateTime _lastHint = DateTime.fromMillisecondsSinceEpoch(0);

  /// 扫描线动画。
  double _scanLine = 0;

  bool _torchOn = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _hint(String msg) {
    final DateTime now = DateTime.now();
    if (now.difference(_lastHint).inSeconds < 3) return;
    _lastHint = now;
    if (!mounted) return;
    iosHaptic(HapticFeedbackType.medium);
    setState(() => _hintText = msg);
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy) return;
    final String? raw =
        capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
    if (raw == null || raw.trim().isEmpty) return;

    final KombuchaFirstLabel? parsed = LabelTemplate.parseKombuchaQr(raw);
    if (parsed == null) {
      // 需求 6：不再写「请对准康普茶瓶身上的二维码」，改为通用文案
      _hint('这张二维码不是本系统生成的标签');
      return;
    }

    _busy = true;
    try {
      await _controller.stop();
    } catch (_) {
      // 忽略停止失败：下面照样弹输入框
    }
    if (!mounted) return;
    setState(() => _hintText = null);

    final String? fruit = await showCupertinoDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _FruitDialog(
        variety: parsed.variety,
        firstTitle: parsed.title,
      ),
    );
    if (!mounted) return;

    if (fruit == null || fruit.isEmpty) {
      _busy = false;
      await _resume();
      return;
    }

    try {
      final DateTime now = DateTime.now();
      final LabelData data = LabelTemplate.buildKombuchaSecond(
        firstTitle: parsed.title,
        fruit: fruit,
        now: now,
        firstFinished: parsed.finished,
        firstBestBefore: parsed.bestBefore,
        maker: parsed.maker.isEmpty ? '未署名' : parsed.maker,
      );
      final Uint8List bytes = await renderLabelPdf(data);
      if (!mounted) return;
      // 用 Cupertino 转场替换，保持与全局导航一致（原安卓版是 MaterialPageRoute）
      Navigator.of(context).pushReplacement(
        CupertinoPageRoute<void>(
          builder: (_) => LabelPreviewPage(
            pdfBytes: bytes,
            fileName: labelFileName(data.title, now),
          ),
        ),
      );
    } catch (e) {
      _busy = false;
      await _resume();
      if (!mounted) return;
      _hint('生成失败：$e');
    }
  }

  Future<void> _resume() async {
    try {
      await _controller.start();
    } catch (_) {
      // 相机可能已被释放，忽略
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      // 需求 6①：没有导航栏，全屏取景
      backgroundColor: CupertinoColors.black,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // 取景画面
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => _ScanError(error: error),
          ),

          // 暗角遮罩 + 取景框（需求 6④：四角折线 + 扫描线）
          _ScanOverlay(onScanLineChanged: (double v) {
            if (mounted) setState(() => _scanLine = v);
          }),

          // 顶部：返回按钮
          Positioned(
            top: MediaQuery.of(context).padding.top + IosSpace.sm,
            left: IosSpace.ml,
            child: _GlassCircleButton(
              icon: CupertinoIcons.xmark,
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ),

          // 解析失败提示（通用文案，不预设品类）
          if (_hintText != null)
            Positioned(
              left: IosSpace.xl,
              right: IosSpace.xl,
              top: MediaQuery.of(context).padding.top + 68,
              child: _HintPill(text: _hintText!),
            ),

          // 需求 6③：两个功能按钮移到**屏幕下方两侧**
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.of(context).padding.bottom + IosSpace.xl,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: <Widget>[
                _BottomAction(
                  icon: _torchOn
                      ? CupertinoIcons.lightbulb_fill
                      : CupertinoIcons.lightbulb,
                  label: '手电筒',
                  active: _torchOn,
                  onTap: () {
                    iosHaptic(HapticFeedbackType.light);
                    setState(() => _torchOn = !_torchOn);
                    _controller.toggleTorch();
                  },
                ),
                _BottomAction(
                  icon: CupertinoIcons.camera_rotate,
                  label: '切换镜头',
                  onTap: () {
                    iosHaptic(HapticFeedbackType.light);
                    _controller.switchCamera();
                  },
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
// 取景框（需求 6④：有设计感）
// ===========================================================================

/// 取景叠加层：暗角遮罩 + 四角折线取景框 + 往返扫描线。
///
/// 用 `AnimatedBuilder` 驱动扫描线上下往返，视觉上提示「正在识别」。
class _ScanOverlay extends StatefulWidget {
  const _ScanOverlay({required this.onScanLineChanged});

  final ValueChanged<double> onScanLineChanged;

  @override
  State<_ScanOverlay> createState() => _ScanOverlayState();
}

class _ScanOverlayState extends State<_ScanOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat(reverse: true);

  static const double _frame = 248;
  static const double _corner = 34;
  static const double _cornerW = 4;

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final double top = (c.maxHeight - _frame) / 2;
        final double left = (c.maxWidth - _frame) / 2;

        return IgnorePointer(
          child: Stack(
            children: <Widget>[
              // 暗角遮罩：中间挖空
              Positioned.fill(
                child: CustomPaint(
                  painter: _DimPainter(
                    hole: Rect.fromLTWH(left, top, _frame, _frame),
                    radius: IosRadius.xl,
                  ),
                ),
              ),
              // 四角折线
              Positioned(
                left: left,
                top: top,
                child: SizedBox(
                  width: _frame,
                  height: _frame,
                  child: CustomPaint(
                    painter: const _CornerPainter(
                      length: _corner,
                      weight: _cornerW,
                      radius: IosRadius.xl,
                    ),
                  ),
                ),
              ),
              // 往返扫描线
              AnimatedBuilder(
                animation: _anim,
                builder: (BuildContext context, Widget? _) {
                  final double y = top + 8 + (_frame - 16) * _anim.value;
                  return Positioned(
                    left: left + IosSpace.m,
                    top: y,
                    child: Container(
                      width: _frame - IosSpace.xl,
                      height: 2,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        gradient: const LinearGradient(
                          colors: <Color>[
                            Color(0x00FFFFFF),
                            IosColors.brandLight,
                            Color(0x00FFFFFF),
                          ],
                        ),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: IosColors.brandLight.withValues(alpha: 0.6),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              // 取景框下方的简短指引（通用文案，不预设品类）
              Positioned(
                left: 0,
                right: 0,
                top: top + _frame + IosSpace.xl,
                child: const Center(
                  child: Text(
                    '将二维码放入框内，即可自动识别',
                    style: TextStyle(
                      color: Color(0xCCFFFFFF),
                      fontSize: IosText.footnote,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 暗角遮罩：整屏半透明黑 + 中间圆角挖空。
class _DimPainter extends CustomPainter {
  const _DimPainter({required this.hole, required this.radius});

  final Rect hole;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final Path outer = Path()..addRect(Offset.zero & size);
    final Path inner = Path()
      ..addRRect(
        RRect.fromRectAndRadius(hole, const Radius.circular(IosRadius.xl)),
      );
    final Path dim = Path.combine(PathOperation.difference, outer, inner);
    canvas.drawPath(
      dim,
      Paint()..color = const Color(0x99000000),
    );
    // 挖空边缘的一圈极细高光，提升玻璃质感
    canvas.drawRRect(
      RRect.fromRectAndRadius(hole, Radius.circular(radius)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = const Color(0x33FFFFFF),
    );
  }

  @override
  bool shouldRepaint(_DimPainter old) =>
      old.hole != hole || old.radius != radius;
}

/// 四角折线取景框（比整圈描边更有设计感）。
class _CornerPainter extends CustomPainter {
  const _CornerPainter({
    required this.length,
    required this.weight,
    required this.radius,
  });

  final double length;
  final double weight;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()
      ..color = IosColors.brandLight
      ..strokeWidth = weight
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final double r = radius;
    final double l = length;
    const double inset = 0;

    // 左上
    final Path tl = Path()
      ..moveTo(inset, inset + r + l)
      ..lineTo(inset, inset + r)
      ..arcToPoint(
        Offset(inset + r, inset),
        radius: Radius.circular(r),
        clockwise: true,
      )
      ..lineTo(inset + r + l, inset);

    // 右上
    final Path tr = Path()
      ..moveTo(size.width - inset - r - l, inset)
      ..lineTo(size.width - inset - r, inset)
      ..arcToPoint(
        Offset(size.width - inset, inset + r),
        radius: Radius.circular(r),
        clockwise: true,
      )
      ..lineTo(size.width - inset, inset + r + l);

    // 右下
    final Path br = Path()
      ..moveTo(size.width - inset, size.height - inset - r - l)
      ..lineTo(size.width - inset, size.height - inset - r)
      ..arcToPoint(
        Offset(size.width - inset - r, size.height - inset),
        radius: Radius.circular(r),
        clockwise: true,
      )
      ..lineTo(size.width - inset - r - l, size.height - inset);

    // 左下
    final Path bl = Path()
      ..moveTo(inset + r + l, size.height - inset)
      ..lineTo(inset + r, size.height - inset)
      ..arcToPoint(
        Offset(inset, size.height - inset - r),
        radius: Radius.circular(r),
        clockwise: true,
      )
      ..lineTo(inset, size.height - inset - r - l);

    for (final Path path in <Path>[tl, tr, br, bl]) {
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(_CornerPainter old) =>
      old.length != length || old.weight != weight || old.radius != radius;
}

// ===========================================================================
// 小部件
// ===========================================================================

/// 半透明圆形图标按钮（顶部返回、底部功能键共用）。
class _GlassCircleButton extends StatelessWidget {
  const _GlassCircleButton({
    required this.icon,
    required this.onTap,
    this.active = false,
    this.label,
    this.size = 44,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  final String? label;
  final double size;

  @override
  Widget build(BuildContext context) {
    // 用 Material(transparency) 承载 iOS 风格水波；缺它点击反馈会被画在渐变下层
    return Material(
      type: MaterialType.transparency,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: Size(size, size),
        pressedOpacity: 0.7,
        borderRadius: BorderRadius.circular(size / 2),
        onPressed: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active
                ? IosColors.brand.withValues(alpha: 0.85)
                : const Color(0x4D000000),
            border: Border.all(color: const Color(0x33FFFFFF), width: 0.8),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, size: label == null ? 20 : 22, color: CupertinoColors.white),
              if (label != null) ...<Widget>[
                const SizedBox(height: 3),
                Text(
                  label!,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xE6FFFFFF),
                    height: 1,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 屏幕下方的功能键（带文字标签）。
class _BottomAction extends StatelessWidget {
  const _BottomAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return _GlassCircleButton(
      icon: icon,
      label: label,
      active: active,
      size: 60,
      onTap: onTap,
    );
  }
}

/// 顶部提示胶囊。
class _HintPill extends StatelessWidget {
  const _HintPill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: IosSpace.ml,
          vertical: IosSpace.smd,
        ),
        decoration: BoxDecoration(
          color: IosColors.orange.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              CupertinoIcons.exclamationmark_triangle_fill,
              size: 14,
              color: CupertinoColors.white,
            ),
            const SizedBox(width: IosSpace.s),
            Flexible(
              child: Text(
                text,
                style: const TextStyle(
                  color: CupertinoColors.white,
                  fontSize: IosText.footnote,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 相机不可用。
class _ScanError extends StatelessWidget {
  const _ScanError({required this.error});

  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(IosSpace.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              CupertinoIcons.camera,
              size: 52,
              color: Color(0xB3FFFFFF),
            ),
            const SizedBox(height: IosSpace.ml),
            const Text(
              '相机不可用',
              style: TextStyle(
                color: CupertinoColors.white,
                fontSize: IosText.title3,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: IosSpace.sm),
            Text(
              '${error.errorCode}\n请确认已授予相机权限。',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xB3FFFFFF),
                fontSize: IosText.footnote,
                height: 1.5,
              ),
            ),
            const SizedBox(height: IosSpace.lg),
            IosSecondaryButton(
              label: '返回',
              icon: CupertinoIcons.chevron_back,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ],
        ),
      ),
    );
  }
}

/// 输入「二发使用的水果」—— Cupertino 弹窗。
class _FruitDialog extends StatefulWidget {
  const _FruitDialog({required this.variety, required this.firstTitle});

  final String variety;
  final String firstTitle;

  @override
  State<_FruitDialog> createState() => _FruitDialogState();
}

class _FruitDialogState extends State<_FruitDialog> {
  // 控制器由弹窗自持并在自身 dispose 释放——
  // 放调用方会在关闭动画期间因 TextField 仍引用而红屏。
  final TextEditingController _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final String v = _ctrl.text.trim();
    Navigator.of(context).pop(v.isEmpty ? null : v);
  }

  @override
  Widget build(BuildContext context) {
    final Brightness b = iosBrightness(context);
    return CupertinoAlertDialog(
      title: const Text('二发使用的水果'),
      content: Padding(
        padding: const EdgeInsets.only(top: IosSpace.m),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '已识别标签：${widget.firstTitle}（${widget.variety}）',
              style: TextStyle(
                fontSize: IosText.footnote,
                color: IosColors.secondaryLabel(b),
              ),
            ),
            const SizedBox(height: IosSpace.m),
            CupertinoTextField(
              controller: _ctrl,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              placeholder: '例：草莓',
              prefix: const Padding(
                padding: EdgeInsets.only(left: IosSpace.m, right: IosSpace.sm),
                child: Icon(
                  CupertinoIcons.tag,
                  size: 18,
                  color: IosColors.brand,
                ),
              ),
            ),
          ],
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
          child: const Text('生成二发标签'),
        ),
      ],
    );
  }
}

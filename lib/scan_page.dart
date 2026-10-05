import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'label_pdf.dart';
import 'label_template.dart';
import 'preview_page.dart';

/// 扫码页：扫「康普茶一发」标签 → 输入二发水果 → 生成二发标签。
class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  /// 已经识别到康普茶标签、正在处理中，避免重复触发
  bool _busy = false;
  DateTime _lastHint = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _hint(String msg) {
    final now = DateTime.now();
    if (now.difference(_lastHint).inSeconds < 3) return;
    _lastHint = now;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy) return;
    final raw = capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
    if (raw == null || raw.trim().isEmpty) return;

    final parsed = LabelTemplate.parseKombuchaQr(raw);
    if (parsed == null) {
      _hint('未识别到康普茶标签，请对准瓶身上的二维码');
      return;
    }

    _busy = true;
    try {
      await _controller.stop();
    } catch (_) {
      // 忽略停止失败：下面照样弹输入框
    }
    if (!mounted) return;

    final fruit = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _FruitDialog(
        variety: parsed.variety,
        firstTitle: parsed.title,
      ),
    );
    if (!mounted) return;

    if (fruit == null || fruit.isEmpty) {
      // 取消 → 继续扫
      _busy = false;
      await _resume();
      return;
    }

    try {
      final now = DateTime.now();
      final data = LabelTemplate.buildKombuchaSecond(
        firstTitle: parsed.title,
        fruit: fruit,
        now: now,
        firstFinished: parsed.finished,
        firstBestBefore: parsed.bestBefore,
        maker: parsed.maker.isEmpty ? '未署名' : parsed.maker,
      );
      final bytes = await renderLabelPdf(data);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('生成失败：$e')));
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
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('扫描二维码'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: '手电筒',
            icon: const Icon(Icons.flashlight_on_outlined),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            tooltip: '切换摄像头',
            icon: const Icon(Icons.cameraswitch_outlined),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => _ScanError(error: error),
          ),
          // 取景框
          IgnorePointer(
            child: Center(
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  border: Border.all(color: theme.colorScheme.primary, width: 3),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 36,
            child: Center(child: _ScanTip(text: '请对准康普茶瓶身上的二维码')),
          ),
        ],
      ),
    );
  }
}

class _ScanTip extends StatelessWidget {
  const _ScanTip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 14),
      ),
    );
  }
}

class _ScanError extends StatelessWidget {
  const _ScanError({required this.error});

  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.no_photography_outlined,
              size: 56,
              color: Colors.white70,
            ),
            const SizedBox(height: 16),
            const Text(
              '相机不可用',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              '${error.errorCode}\n'
              '请确认已授予相机权限，或改用「手动输入」方式生成二发标签。',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('返回'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 输入「二发使用的水果」
class _FruitDialog extends StatefulWidget {
  const _FruitDialog({required this.variety, required this.firstTitle});

  final String variety;
  final String firstTitle;

  @override
  State<_FruitDialog> createState() => _FruitDialogState();
}

class _FruitDialogState extends State<_FruitDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _ctrl.text.trim();
    Navigator.of(context).pop(v.isEmpty ? null : v);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('二发使用的水果'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '已识别一发标签：${widget.firstTitle}（${widget.variety}）',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _ctrl,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              labelText: '水果',
              hintText: '例：草莓',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.local_florist_outlined),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('生成二发标签')),
      ],
    );
  }
}

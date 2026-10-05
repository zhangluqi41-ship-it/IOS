import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:printing/printing.dart';

import 'pdf_saver.dart';
import 'print_sheet.dart';

/// 三级页：标签预览。
///
/// 底部两个动作：**保存到手机** 和 **打印**（打印会复用当前这份 PDF，
/// 所以纸面效果和屏幕预览严格一致）。
class LabelPreviewPage extends StatelessWidget {
  const LabelPreviewPage({
    super.key,
    required this.pdfBytes,
    required this.fileName,
  });

  final Uint8List pdfBytes;
  final String fileName;

  /// 保存到手机系统「下载」目录（安卓原生 MediaStore，免权限）。
  Future<void> _saveToPhone(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('正在保存…'), duration: Duration(seconds: 1)),
    );
    try {
      final where = await PdfSaver.saveToDownloads(pdfBytes, fileName);
      messenger.showSnackBar(SnackBar(content: Text('已保存到 $where')));
    } on MissingPluginException {
      messenger.showSnackBar(
        const SnackBar(content: Text('当前平台不支持直接保存，请用「分享」导出')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('保存失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('标签预览'),
        backgroundColor: theme.colorScheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: PdfPreview(
        build: (format) async => pdfBytes,
        pdfFileName: fileName,
        // 预览清晰度：强制高分辨率栅格化。
        // 插件默认按屏幕宽度算 dpi（本机 50mm 标签约 700），这里给到 1200，
        // 约为显示尺寸的 1.8 倍超采样 —— 缩放到屏幕时更锐利，放大看小字也不糊。
        // 50×30mm 在 1200dpi 下是 2362×1417 px（约 13MB），单页无压力。
        dpi: 1200,
        allowSharing: true,
        allowPrinting: false, // 打印走下面的自研通道，不用系统打印服务
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _saveToPhone(context),
                icon: const Icon(Icons.save_alt),
                label: const Text('保存到手机'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => showPrintSheet(context, pdf: pdfBytes),
                icon: const Icon(Icons.print),
                label: const Text('一键打印'),
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
}

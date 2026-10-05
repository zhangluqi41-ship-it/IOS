import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:printing/printing.dart';

import 'ios/ios_theme.dart';
import 'ios/print_sheet_ios.dart';
import 'pdf_saver.dart';
import 'print_sheet.dart';
import 'printer.dart';

/// 三级页：标签预览。
///
/// 底部两个动作：**保存到手机** 和 **一键打印**（打印复用当前 PDF，
/// 所以纸面效果和屏幕预览严格一致）。
///
/// 本页**按平台分流表现层**：
///  * iOS → `CupertinoPageScaffold` + `CupertinoNavigationBar` + 两个 Cupertino 按钮，
///    打印面板走 [showIosPrintSheet]；
///  * 安卓 → 原 Material 版式，打印面板走 [showPrintSheet]。
///
/// `PdfPreview` 是 `printing` 插件的组件（两端共用），
/// 它的 `padding` / `dpi` 保持两边一致，保证预览观感相同。
class LabelPreviewPage extends StatelessWidget {
  const LabelPreviewPage({
    super.key,
    required this.pdfBytes,
    required this.fileName,
  });

  final Uint8List pdfBytes;
  final String fileName;

  /// 保存到手机。
  ///
  /// 安卓走原生 MediaStore 存到「下载」目录；
  /// iOS 原生侧写 App 文档目录（配合 Info.plist 的 `UIFileSharingEnabled`，
  /// 可在「文件」App 的「我的 iPhone → 效期管理程序」里看到）。
  /// **两端调的是同一个通道方法**，返回的都是人类可读的位置。
  Future<void> _saveToPhone(BuildContext context) async {
    if (kIsIos) {
      await _saveIos(context);
      return;
    }
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('正在保存…'),
        duration: Duration(seconds: 1),
      ),
    );
    try {
      final String where = await PdfSaver.saveToDownloads(pdfBytes, fileName);
      messenger.showSnackBar(SnackBar(content: Text('已保存到 $where')));
    } on MissingPluginException {
      messenger.showSnackBar(
        const SnackBar(content: Text('当前平台不支持直接保存，请用「分享」导出')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('保存失败：$e')));
    }
  }

  /// iOS 保存：落 App 文档目录，用 Cupertino 弹窗告知在「文件」App 里取。
  Future<void> _saveIos(BuildContext context) async {
    String message;
    String title;
    try {
      final String where = await PdfSaver.saveToDownloads(pdfBytes, fileName);
      title = '已保存';
      message = '已保存到：\n$where\n\n也可以在预览页右上角用「分享」导出。';
    } on MissingPluginException {
      title = '无法保存';
      message = '当前版本不支持直接保存，请用右上角「分享」导出。';
    } catch (e) {
      title = '保存失败';
      message = '$e';
    }
    if (!context.mounted) return;
    await showCupertinoDialog<void>(
      context: context,
      builder: (BuildContext ctx) => CupertinoAlertDialog(
        title: Text(title),
        content: Padding(
          padding: const EdgeInsets.only(top: IosSpace.sm),
          child: Text(
            message,
            style: const TextStyle(fontSize: IosText.subheadline),
          ),
        ),
        actions: <Widget>[
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('好'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return kIsIos ? _buildIos(context) : _buildAndroid(context);
  }

  // ------------------------------------------------------------------ iOS

  Widget _buildIos(BuildContext context) {
    final Brightness b = iosBrightness(context);
    // 底部安全区（home indicator 高度）。
    final double bottomInset = MediaQuery.of(context).padding.bottom;
    return CupertinoPageScaffold(
      backgroundColor: IosColors.grouped(b),
      navigationBar: CupertinoNavigationBar(
        middle: const Text('标签预览', style: IosText.navTitle),
        backgroundColor: IosColors.grouped(b).withValues(alpha: 0.92),
        border: Border(
          bottom: BorderSide(color: IosColors.separator(b), width: 0.5),
        ),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(34, 34),
          onPressed: () => _saveToPhone(context),
          child: const Icon(
            CupertinoIcons.arrow_down_to_line,
            size: 22,
            color: IosColors.blue,
          ),
        ),
      ),
      child: Column(
        children: <Widget>[
          Expanded(
            child: PdfPreview(
              build: (format) async => pdfBytes,
              pdfFileName: fileName,
              dpi: 1200,
              allowSharing: true,
              allowPrinting: false,
              canChangePageFormat: false,
              canChangeOrientation: false,
              canDebug: false,
              padding: const EdgeInsets.fromLTRB(
                IosSpace.ml,
                IosSpace.m,
                IosSpace.ml,
                IosSpace.ml,
              ),
            ),
          ),
          // 底栏两个 Cupertino 按钮。
          // 三级页仍在常驻原生底栏之上 —— 底部要预留「tab bar 内容区 + 安全区」
          // 的高度，否则按钮会被原生底栏盖住（需求：三级预览严重问题）。
          Container(
            padding: const EdgeInsets.fromLTRB(
              IosSpace.ml,
              IosSpace.smd,
              IosSpace.ml,
              IosSpace.m,
            ),
            decoration: BoxDecoration(
              color: IosColors.card(b),
              border: Border(
                top: BorderSide(color: IosColors.separator(b), width: 0.5),
              ),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: _IosBarButton(
                    icon: CupertinoIcons.arrow_down_to_line,
                    label: '保存到手机',
                    onTap: () => _saveToPhone(context),
                  ),
                ),
                const SizedBox(width: IosSpace.m),
                Expanded(
                  child: _IosBarButton(
                    icon: CupertinoIcons.printer,
                    label: '一键打印',
                    primary: true,
                    onTap: () => showIosPrintSheet(context, pdf: pdfBytes),
                  ),
                ),
              ],
            ),
          ),
          // 预留原生底栏占用的高度（内容区 + 安全区），背景与按钮栏连成一片。
          Container(
            height: IosSize.tabBar + bottomInset,
            color: IosColors.card(b),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- 安卓

  Widget _buildAndroid(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('标签预览'),
        backgroundColor: theme.colorScheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: PdfPreview(
        build: (format) async => pdfBytes,
        pdfFileName: fileName,
        dpi: 1200,
        allowSharing: true,
        allowPrinting: false,
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: <Widget>[
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

/// 预览页底部按钮（iOS）。
class _IosBarButton extends StatelessWidget {
  const _IosBarButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final Brightness b = iosBrightness(context);
    return SizedBox(
      height: IosSize.primaryButton,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        pressedOpacity: 0.75,
        color: primary ? IosColors.brand : IosColors.grouped(b),
        borderRadius: BorderRadius.circular(IosRadius.button),
        onPressed: onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              icon,
              size: 18,
              color: primary ? CupertinoColors.white : IosColors.brand,
            ),
            const SizedBox(width: IosSpace.s),
            Text(
              label,
              style: TextStyle(
                fontSize: IosText.callout,
                fontWeight: FontWeight.w600,
                color: primary ? CupertinoColors.white : IosColors.brand,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:qr/qr.dart';

/// 1 毫米对应的 PDF 点（pt）
const double kMm = 72.0 / 25.4;

/// 标签版式参数（单位 mm）。
///
/// 全部数值与 Python 版 `make_label_v4.py` 保持一致 ——
/// 要改版式只改这里，其余是纯绘制逻辑。
class LabelSpec {
  const LabelSpec._();

  static const double pageW = 50.0;
  static const double pageH = 30.0;

  static const double padV = 1.0; // 黑条上下留白
  static const double padH = 1.5; // 左黑条外侧留白
  static const double padHR = 1.5; // 右黑条外侧留白
  static const double barWL = 6.2; // 左黑条宽度（容纳 星期/日/英文）
  static const double barWR = 3.8; // 右黑条宽度（竖排时间）
  static const double gapBar = 0.45; // 黑条与内容间距

  static const double titleSz = 3.35; // 标题字号（超宽时会自动缩小）
  /// 标题右端与右黑条左缘之间必须保留的最小间距（mm）。
  /// 标题宽度超过「内容起点 ~ 右黑条左缘 − 该值」时，按比例缩小字号。
  static const double titleGapRight = 0.6;
  static const double rowSz = 2.3; // 行值字号
  static const double labSz = 2.2; // 行标签字号
  static const double rowStep = 5.65; // 每组占高
  static const double rowGap = 2.9; // 标签与值行距
  static const double makerSz = 1.4; // 制作人字号

  static const double qrSize = 12.8; // 二维码边长
  static const double qrTop = 7.5; // 二维码顶部 y
  static const double firstRow = 7.0; // 第一组标签 y
  static const double makerBottom = 5.0; // 制作人顶边距底边距离

  // 左黑条三排字号
  // 宽度硬约束: 英文缩写 "Wed" 最宽 (比 "星期" 更紧)，占条宽约 84% 即为上限区。
  static const double weekCnSz = 2.40; // "星期"
  static const double weekDaySz = 3.50; // 中文日（如 "四"）
  static const double weekEnSz = 2.25; // 英文缩写（如 "Thu" / "Wed"）

  /// 右黑条竖排字号系数（= 单元格高 × 该系数）。
  /// 字符数越少单元格越高，字号会被自动放大，故用该系数压制。
  static const double rightSzRatio = 0.55;
}

/// 一组「标签 + 值」
class LabelRow {
  final String label;
  final String value;
  const LabelRow(this.label, this.value);
}

/// 一张标签的全部可变量
class LabelData {
  final String title;
  final List<LabelRow> rows;
  final String weekdayCn;
  final String weekdayEn;
  final String rightText;
  final String maker;

  const LabelData({
    required this.title,
    required this.rows,
    required this.weekdayCn,
    required this.weekdayEn,
    required this.rightText,
    required this.maker,
  });

  /// 二维码内容 = 页面全部文字顺序拼接，无分隔符
  /// （标题 + 各组「标签+值」 + 制作人）
  String get qrText {
    final b = StringBuffer(title);
    for (final r in rows) {
      b
        ..write(r.label)
        ..write(r.value);
    }
    b.write(maker);
    return b.toString();
  }
}

// ---------------------------------------------------------------------------
// 渲染
// ---------------------------------------------------------------------------

/// 生成 50×30mm 标签 PDF（矢量绘制，可直接打印）。
///
/// 字体外部传入，便于在 Flutter（rootBundle）与纯 Dart 校验脚本（dart:io）
/// 两种环境下复用同一套渲染逻辑。
Future<Uint8List> buildLabelPdf(
  LabelData data, {
  required Uint8List fontRegular,
  required Uint8List fontBold,
}) async {
  final reg = pw.Font.ttf(ByteData.sublistView(fontRegular));
  final bold = pw.Font.ttf(ByteData.sublistView(fontBold));

  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      pageFormat: const PdfPageFormat(
        LabelSpec.pageW * kMm,
        LabelSpec.pageH * kMm,
      ),
      margin: pw.EdgeInsets.zero,
      build: (pw.Context context) => pw.CustomPaint(
        size: const PdfPoint(
          LabelSpec.pageW * kMm,
          LabelSpec.pageH * kMm,
        ),
        painter: (canvas, size) =>
            paintLabel(canvas, context, data, reg, bold),
      ),
    ),
  );
  return doc.save();
}

/// 绘制整张标签。
///
/// 坐标约定：**布局全程按「原点在左上、y 向下」计算**（与 Python 版
/// `render_png()` 一致），只在真正落笔时用 [fy] 翻成 PDF 原生的
/// 「原点左下、y 向上」坐标系。
void paintLabel(
  PdfGraphics c,
  pw.Context ctx,
  LabelData d,
  pw.Font regFont,
  pw.Font boldFont,
) {
  final reg = regFont.getFont(ctx);
  final bold = boldFont.getFont(ctx);

  const w = LabelSpec.pageW * kMm;
  const h = LabelSpec.pageH * kMm;
  double mm(double v) => v * kMm;

  /// top-down 的 y → PDF 的 y
  double fy(double yTop) => h - yTop;

  // ---- 左右黑条（连续整条，不是独立方块）----
  final lx0 = mm(LabelSpec.padH);
  final top = mm(LabelSpec.padV);
  final barH = h - top * 2;
  final lx1 = mm(LabelSpec.padH + LabelSpec.barWL);
  final rx1 = w - mm(LabelSpec.padHR);
  final rx0 = rx1 - mm(LabelSpec.barWR);

  c.setFillColor(PdfColors.black);
  c.drawRect(lx0, fy(top + barH), lx1 - lx0, barH);
  c.fillPath();
  c.drawRect(rx0, fy(top + barH), rx1 - rx0, barH);
  c.fillPath();

  // ---- 左侧黑条：三排（星期 / 中文日 / 英文缩写）----
  final lcx = (lx0 + lx1) / 2;
  final seg = barH / 3;
  c.setFillColor(PdfColors.white);
  _centered(c, bold, '星期', mm(LabelSpec.weekCnSz), lcx, top + seg * 0.5);
  _centered(c, bold, d.weekdayCn, mm(LabelSpec.weekDaySz), lcx, top + seg * 1.5);
  _centered(c, bold, d.weekdayEn, mm(LabelSpec.weekEnSz), lcx, top + seg * 2.5);

  // ---- 右侧黑条：竖排时间 HH:MM，每字符居中等分整条 ----
  final rc = d.rightText;
  final n = rc.isEmpty ? 1 : rc.length;
  final cell = barH / n;
  final fz = cell * LabelSpec.rightSzRatio;
  final rcx = (rx0 + rx1) / 2;
  for (var i = 0; i < n; i++) {
    _centered(c, bold, rc[i], fz, rcx, top + cell * i + cell / 2);
  }

  // ---- 内容区 ----
  final cx = mm(LabelSpec.padH + LabelSpec.barWL + LabelSpec.gapBar);
  final barRight = w - mm(LabelSpec.padHR + LabelSpec.barWR);

  final titleSize = mm(LabelSpec.titleSz);
  final labSize = mm(LabelSpec.labSz);
  final rowSize = mm(LabelSpec.rowSz);

  // 量出文字实际最大宽度，二维码在「文字右端 ~ 右黑条左缘」区间居中
  var maxTextW = 0.0;
  for (final r in d.rows) {
    maxTextW = math.max(maxTextW, _textWidth(reg, r.label, labSize));
    maxTextW = math.max(maxTextW, _textWidth(bold, r.value, rowSize));
  }
  final textRight = cx + maxTextW;
  final qs = mm(LabelSpec.qrSize);
  final freeW = barRight - textRight;
  final qrLeft = textRight + (freeW - qs) / 2;

  // ---- 标题：顶部与黑条顶端齐平；超宽时自动缩小，避免触碰右侧黑条 ----
  c.setFillColor(PdfColors.black);
  var fittedTitleSize = titleSize;
  final titleMaxW = barRight - cx - mm(LabelSpec.titleGapRight);
  final naturalTitleW = _textWidth(bold, d.title, titleSize);
  if (naturalTitleW > titleMaxW && naturalTitleW > 0) {
    fittedTitleSize = titleSize * titleMaxW / naturalTitleW;
  }
  c.drawString(
    bold,
    fittedTitleSize,
    d.title,
    cx,
    fy(top + bold.ascent * fittedTitleSize),
  );

  // ---- 三组「标签行 + 值行」----
  var y = mm(LabelSpec.firstRow);
  for (final r in d.rows) {
    c.drawString(reg, labSize, r.label, cx, fy(y + reg.ascent * labSize));
    final vy = y + mm(LabelSpec.rowGap);
    c.drawString(bold, rowSize, r.value, cx, fy(vy + bold.ascent * rowSize));
    y += mm(LabelSpec.rowStep);
  }

  // ---- 制作人：顶边距底 5.0mm，与二维码左缘对齐 ----
  final mSize = mm(LabelSpec.makerSz);
  c.drawString(
    bold,
    mSize,
    d.maker,
    qrLeft,
    fy(h - mm(LabelSpec.makerBottom) + bold.ascent * mSize),
  );

  // ---- 二维码（矢量块绘制，含 1 模块静默边）----
  _drawQr(c, d.qrText, qrLeft, mm(LabelSpec.qrTop), qs);
}

/// 测量文字在给定字号下的宽度（pt）
double _textWidth(PdfFont font, String text, double size) =>
    font.stringMetrics(text).width * size;

/// 在 (x, yTop) 处绘制边长为 size 的二维码（yTop 为顶边，top-down）。
void _drawQr(PdfGraphics c, String data, double x, double yTop, double size) {
  const h = LabelSpec.pageH * kMm;
  double fy(double v) => h - v;

  final qr = QrCode.fromData(
    data: data,
    errorCorrectLevel: QrErrorCorrectLevel.M,
  );
  final img = QrImage(qr);
  final modules = img.moduleCount;
  const border = 1; // 与原版一致：留 1 个模块的静默区
  final total = modules + border * 2;
  final ms = size / total;

  c.setFillColor(PdfColors.black);
  for (var r = 0; r < modules; r++) {
    for (var col = 0; col < modules; col++) {
      if (img.isDark(r, col)) {
        c.drawRect(
          x + (col + border) * ms,
          fy(yTop + (r + border + 1) * ms),
          ms,
          ms,
        );
        c.fillPath();
      }
    }
  }
}

/// 在 (cx, cy) 处居中绘制文字，cy 为文字的视觉垂直中心（top-down）。
/// 颜色由调用方通过 setFillColor 预先设定。
void _centered(
  PdfGraphics c,
  PdfFont f,
  String text,
  double size,
  double cx,
  double cy,
) {
  if (text.isEmpty) return;
  const h = LabelSpec.pageH * kMm;
  final tw = _textWidth(f, text, size);
  // 文字从基线向上 ascent、向下 descent，故视觉中心对应的基线为：
  final baseline = cy + (f.ascent + f.descent) * size / 2;
  c.drawString(f, size, text, cx - tw / 2, h - baseline);
}

//
//  LabelData.swift
//  标签数据模型 + 版式常量（精确迁移自 Flutter `label_renderer.dart`）。
//
//  50×30mm 横向标签，左右两条连续黑色竖条，无分隔线。
//  要改版式只改 LabelSpec 里的常量，其余是纯绘制逻辑。
//

import CoreGraphics

/// 一组「标签 + 值」。
struct LabelRow {
    let label: String
    let value: String
}

/// 一张标签的全部可变量。
struct LabelData {
    let title: String
    let rows: [LabelRow]
    let weekdayCn: String
    let weekdayEn: String
    let rightText: String
    let maker: String

    /// 二维码内容 = 页面全部文字顺序拼接，无分隔符
    /// （标题 + 各组「标签+值」 + 制作人）。
    var qrText: String {
        var b = title
        for r in rows {
            b += r.label
            b += r.value
        }
        b += maker
        return b
    }
}

/// 标签版式参数（单位 mm）。
///
/// ★★ 改这里之前先读这段约束，否则很容易把标签改到「放不下」：
///    可用内容宽度 = 50 − padH − barWL − gapBar − barWR − padHR
///                 = 50 − 0.7 − 6.2 − 0.45 − 3.8 − 0.7 = **38.15 mm**
///    这一条宽度要同时装下「最长的一行文字」和「二维码」：
///      最长行 = 「yyyy/MM/dd HH:mm」@ rowSz。
///      ★ Noto Sans SC 的数字是**等宽**的（0.59 em），斜杠 0.387 / 空格 0.227 /
///        冒号 0.325 → 整串恒为 **8.406 em**，@2.7mm = **22.696 mm**
///        （所以任何日期、任何模板都是一样宽，不用挑「最坏样本」）
///      二维码 = qrSize → 14.0 mm
///      文字右端 = 7.35 + 22.696 = 30.05；自由宽 = 45.5 − 30.05 = **15.45 mm**
///      → 二维码两侧各留 **0.73 mm**（`qrGap` 只要 0.3，真放不下时
///        `LabelRenderer.qrBox` 会自动把码收小兜底）
///    所以 **rowSz 再往上加就会触发二维码自动缩小**（试过 2.85mm）。
///
///    ⚠️ 上面这些数字**必须用包内的 Noto Sans SC 量**。
///      一旦字体回落成系统字体（SF Pro + PingFang），同一串会量出 25.21mm，
///      凭空多吃 2.5mm，整套余量结论全错 —— 见 `FontProvider.registerBundledFonts()`。
///
///    纵向：标题块 1.0~5.9，三行 6.5~25.7，制作人页脚 26.3~29.0，
///    正好把 30mm 用满。放大任何一项都要重排这三块。
///
/// 本地预览：`D:/AndroidDev/render_label_preview.py` 用同一套数值在本机出效果图
/// （无需 Xcode），改完先跑它看一眼再往云端构建。
enum LabelSpec {
    static let pageW: CGFloat = 50.0
    static let pageH: CGFloat = 30.0

    static let padV: CGFloat = 1.0   // 黑条上下留白
    static let padH: CGFloat = 0.7   // 左黑条外侧留白（原来 1.5，用户反馈边上留白太多 → 外移）
    static let padHR: CGFloat = 0.7  // 右黑条外侧留白（同上）
    static let barWL: CGFloat = 6.2  // 左黑条宽度（容纳 星期/日/英文）
    static let barWR: CGFloat = 3.8  // 右黑条宽度（竖排时间）
    static let gapBar: CGFloat = 0.45 // 黑条与内容间距

    static let titleSz: CGFloat = 4.2    // 标题字号（原来 3.35，超宽时自动缩小）
    static let titleGapRight: CGFloat = 0.6 // 标题与右黑条最小间距
    static let rowSz: CGFloat = 2.7    // 行值字号（原来 2.3）
    static let labSz: CGFloat = 2.5    // 行标签字号（原来 2.2）
    static let rowStep: CGFloat = 6.7  // 每组占高（字号放大后由 5.65 撑开）
    static let rowGap: CGFloat = 3.28  // 标签与值行距
    static let makerSz: CGFloat = 1.8  // 制作人字号（原来 1.4；超宽时自动缩小）

    static let qrSize: CGFloat = 14.0   // 二维码边长（原来 12.8）
    static let qrGap: CGFloat = 0.3     // 二维码与「文字右端 / 右黑条」的最小间距
    static let qrTop: CGFloat = 7.5     // 二维码顶部 y
    static let firstRow: CGFloat = 6.5  // 第一组标签 y（给放大后的标题让位）
    static let makerBottom: CGFloat = 3.7 // 制作人**字形顶**距底边的距离
                                          // ★ 语义：字形顶的 top-down y = pageH − makerBottom。
                                          //   字号放大后三行排到了 25.7mm 高，原来 5.0 会让
                                          //   制作人正好和第三行数值并排（看着像第三行的一部分），
                                          //   所以压到 3.7 单独留出一条页脚。

    // 左黑条三排字号（宽度硬约束：英文缩写 "Wed" 最宽）
    static let weekCnSz: CGFloat = 2.40  // "星期"
    static let weekDaySz: CGFloat = 3.50 // 中文日（如 "四"）
    static let weekEnSz: CGFloat = 2.25  // 英文缩写（如 "Thu"）

    /// 右黑条竖排字号系数（= 单元格高 × 该系数）。
    static let rightSzRatio: CGFloat = 0.55

    /// 1 毫米对应的点（pt）。
    static var kMm: CGFloat { 72.0 / 25.4 }
}

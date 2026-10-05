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

/// 标签版式参数（单位 mm），全部数值与 Flutter 版 `LabelSpec` 一致。
enum LabelSpec {
    static let pageW: CGFloat = 50.0
    static let pageH: CGFloat = 30.0

    static let padV: CGFloat = 1.0   // 黑条上下留白
    static let padH: CGFloat = 1.5   // 左黑条外侧留白
    static let padHR: CGFloat = 1.5  // 右黑条外侧留白
    static let barWL: CGFloat = 6.2  // 左黑条宽度（容纳 星期/日/英文）
    static let barWR: CGFloat = 3.8  // 右黑条宽度（竖排时间）
    static let gapBar: CGFloat = 0.45 // 黑条与内容间距

    static let titleSz: CGFloat = 3.35   // 标题字号（超宽时自动缩小）
    static let titleGapRight: CGFloat = 0.6 // 标题与右黑条最小间距
    static let rowSz: CGFloat = 2.3    // 行值字号
    static let labSz: CGFloat = 2.2    // 行标签字号
    static let rowStep: CGFloat = 5.65 // 每组占高
    static let rowGap: CGFloat = 2.9   // 标签与值行距
    static let makerSz: CGFloat = 1.4  // 制作人字号

    static let qrSize: CGFloat = 12.8   // 二维码边长
    static let qrTop: CGFloat = 7.5     // 二维码顶部 y
    static let firstRow: CGFloat = 7.0  // 第一组标签 y
    static let makerBottom: CGFloat = 5.0 // 制作人顶边距底边距离

    // 左黑条三排字号（宽度硬约束：英文缩写 "Wed" 最宽）
    static let weekCnSz: CGFloat = 2.40  // "星期"
    static let weekDaySz: CGFloat = 3.50 // 中文日（如 "四"）
    static let weekEnSz: CGFloat = 2.25  // 英文缩写（如 "Thu"）

    /// 右黑条竖排字号系数（= 单元格高 × 该系数）。
    static let rightSzRatio: CGFloat = 0.55

    /// 1 毫米对应的点（pt）。
    static var kMm: CGFloat { 72.0 / 25.4 }
}

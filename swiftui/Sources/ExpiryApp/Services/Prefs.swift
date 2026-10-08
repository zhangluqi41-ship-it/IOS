//
//  Prefs.swift
//  偏好存储 —— UserDefaults，对应 Flutter 的 prefs 通道。
//

import Foundation

enum Prefs {
    private static let d = UserDefaults.standard

    /// 上次填写的制作人（会记住）。
    static var lastMaker: String {
        get { d.string(forKey: "lastMaker") ?? "" }
        set { d.set(newValue, forKey: "lastMaker") }
    }

    /// 上次选的打印机型号 kind（supvan/tspl/escpos）。
    static var lastPrinterKind: String {
        get { d.string(forKey: "lastPrinterKind") ?? "supvan" }
        set { d.set(newValue, forKey: "lastPrinterKind") }
    }

    /// 已保存的打印机（JSON 数组，元素为 SavedPrinter）。
    static func savedPrintersJSON() -> String? {
        d.string(forKey: "savedPrinters")
    }

    static func setSavedPrintersJSON(_ json: String?) {
        d.set(json, forKey: "savedPrinters")
    }

    // MARK: - 连接

    /// 打开 App 后是否自动连接上次连过的那台打印机。
    /// ★ 默认开；键名与界面上的 `@AppStorage("autoConnectPrinter")` 必须一致。
    static var autoConnectPrinter: Bool {
        get { d.object(forKey: "autoConnectPrinter") as? Bool ?? true }
        set { d.set(newValue, forKey: "autoConnectPrinter") }
    }

    // MARK: - 打印参数

    /// 打印浓度 1~9；0 表示「自动」（交给打印机自己判断）。
    static var printDensity: Int {
        get {
            let v = d.object(forKey: "printDensity") as? Int
            return v ?? 0
        }
        set { d.set(newValue, forKey: "printDensity") }
    }

    /// 打印份数，最少 1。
    static var printCopies: Int {
        get {
            let v = d.object(forKey: "printCopies") as? Int
            return max(v ?? 1, 1)
        }
        set { d.set(max(newValue, 1), forKey: "printCopies") }
    }

    /// 纸张类型码值（1 间隙 / 2 普通黑标 / 5 黑标卡纸）。
    static var paperType: Int {
        get {
            let v = d.object(forKey: "paperType") as? Int
            return v ?? 1
        }
        set { d.set(newValue, forKey: "paperType") }
    }
}

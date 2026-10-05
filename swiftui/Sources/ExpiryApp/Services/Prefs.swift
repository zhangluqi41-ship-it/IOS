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
}

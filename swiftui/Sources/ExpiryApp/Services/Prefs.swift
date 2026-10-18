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

    // MARK: - 模板磁贴顺序（★ 2026-10-18 用户要求「长按可以移动位置」）

    /// 模板磁贴的显示顺序，存的是 `TemplateRoute.key` 的数组。
    /// 空数组 = 用默认顺序（通用 / 康普茶 / 奶制品 / 肉类）。
    static var templateOrder: [String] {
        get { d.stringArray(forKey: "templateOrder") ?? [] }
        set { d.set(newValue, forKey: "templateOrder") }
    }

    /// ★ 2026-10-18（用户第 1 条）：**长按菜单里「删除」掉的磁贴**（存 key）。
    /// 不记这个就没法区分「删掉的」和「新版本新增的」—— 删除的会被补回来。
    static var hiddenTemplates: [String] {
        get { d.stringArray(forKey: "hiddenTemplates") ?? [] }
        set { d.set(newValue, forKey: "hiddenTemplates") }
    }

    /// ★ 2026-10-18：**固定（锁定位置）**的磁贴 key。空串 = 没有固定任何一个。
    static var pinnedTemplate: String {
        get { d.string(forKey: "pinnedTemplate") ?? "" }
        set { d.set(newValue, forKey: "pinnedTemplate") }
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

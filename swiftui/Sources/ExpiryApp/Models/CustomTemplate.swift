import Foundation
import SwiftUI

// MARK: - 自定义模板（数据模型）
//
// ★★★ 2026-10-19 新增功能（用户：「自定义模板可以做了」）。
//
// 设计口径（已和用户确认）：
//   · 「模板」只是一棵**菜单树**，本身不带时间；
//   · **每一级**都可以设「建议天数」（可空 = 该级不给建议）；
//   · 使用时逐级选下去，标签标题 = 路径拼接（"解冻-猪肉-梅花肉"）；
//   · 时间**永远从打印当天往后算**（用户原话：「打印时的开封时间都是打印当时」）。
//
// 层级上限：**根 + 3 层子菜单**（`CustomNode.maxDepth`）。

/// 一个自定义模板 = 一棵菜单树。
struct CustomTemplate: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    /// 模板名（也是标签标题的第一段，如「解冻」）。
    var name: String
    /// SF Symbol 名（磁贴图标）。
    var icon: String = "square.grid.2x2"
    /// **图标块背景色**（存名字，避免 Codable 存 Color）。
    var tintName: String = "blue"
    /// **图标本身的颜色**。
    var iconColorName: String = "white"
    /// 第一级菜单。
    var nodes: [CustomNode] = []
    /// 创建时间（用于排序）。
    var createdAt: Date = Date()
    /// ★★★ 2026-10-19（用户）：「时间的设定**只会存在一个树级**……
    ///   冷冻-猪肉-五花，时间只会设置在冷冻上；冷冻和冷藏是同一级的东西……
    ///   所以时间的设定只会在一个树级单位上，不会重复出现」
    ///   ➜ `timeLevel` = 建议天数设在第几层（1 = 第一级，2 = 第二级…）。
    ///     `nil` = 还没定（编辑器里第一次填天数时自动锁定）。
    ///   ➜ 编辑器据此**只允许那一层填天数**，其他层禁用。
    ///     打印时：用自己的天数，没有就**向上找最近祖先**（继承）。
    var timeLevel: Int? = nil
    /// ★ 2026-10-19（用户）：「这一项（模板名称）**也可以设置一个建议时间**」
    ///   ➜ 模板本身的默认天数（第 0 层）。设了就等于 `timeLevel = 0`，
    ///     下属各层不再设时间；打印时没选到具体天数就用它兜底。
    var defaultDays: Int? = nil
    /// ★ 2026-10-19（用户）：「使用制备功能」——
    ///   开启后标签改用「制备时间 / 完成时间 / 最佳使用时间」三行（同康普茶一发）。
    var usePrep: Bool = false
    /// 「扫描二维码二次制备」——开启后可在打印页扫原标签续做（同康普茶二发）。
    var useSecondary: Bool = false
    // ★ 2026-10-19（用户）：「这里面**不需要重复选天数**了啊，上面不是有天数吗」
    //   → 二次制备的完成天数直接复用 `defaultDays`，不再单独存一份。
    /// ★ 2026-10-19（用户）：「开启扫描功能后这里应该是**选择绑定的模板**」
    ///   ➜ 二次制备必须知道"扫到的标签是哪个模板打的" —— 绑定一个**源模板**。
    ///     扫码时只有标题能被这个源模板产出，才会进入本模板的二次制备。
    var sourceTemplateID: UUID? = nil
    /// ★ 2026-10-19（用户）：「命名是否带模板名称」——
    ///   默认 **false**（建了菜单时标题只有菜单路径）。
    ///   打开后标题变成「模板名-第一层-第二层」。
    ///   ⚠️ 没有菜单时这一项不可用（空菜单的标题天然是「模板名-手输名」）。
    var includeTemplateInTitle: Bool = false
    /// ★ 2026-10-19（用户）：「**懒人一键保质期**，然后选择顺延的天数」
    ///   ➜ 开启后打印页**不看菜单天数**，两个日期一律 = 今天 + N 天。
    var lazyDays: Int? = nil
    /// ★ 绑定模板可以精确到**某个菜单路径**（如「康普茶一发 → 桃味」）。
    ///   空数组 = 绑整个模板。
    var sourceNodePath: [String] = []
    /// ★ 命名规则：按顺序取这些字段拼标题。空数组 = 用默认规则（兼容老模板）。
    var titleParts: [TitlePart] = []
    /// 连接符（"-" / "·" / " " / "_"）。
    var titleSeparator: String = "-"

    /// 所有菜单路径（用 `-` 拼好），供「绑定到某个子菜单」时选择。
    var allPaths: [[String]] {
        var result: [[String]] = []
        func walk(_ nodes: [CustomNode], prefix: [String]) {
            for node in nodes {
                let p = prefix + [node.name]
                result.append(p)
                walk(node.children, prefix: p)
            }
        }
        walk(nodes, prefix: [])
        return result
    }

    /// 叶子总数（删除确认、统计用）。
    var leafCount: Int { nodes.reduce(0) { $0 + $1.leafCount } }

    /// 可选颜色（名字 → 系统色）。
    static let colorChoices = [
        "blue", "green", "orange", "red", "purple",
        "pink", "teal", "indigo", "brown", "gray",
        "yellow", "mint", "cyan", "white", "black",
    ]

    static func color(named name: String) -> Color {
        switch name {
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "red": return .red
        case "purple": return .purple
        case "pink": return .pink
        case "teal": return .teal
        case "indigo": return .indigo
        case "brown": return .brown
        case "gray": return .gray
        case "yellow": return .yellow
        case "mint": return .mint
        case "cyan": return .cyan
        case "white": return .white
        case "black": return .black
        default: return .accentColor
        }
    }
}

/// 命名规则里可以取用的字段。
enum TitlePart: String, Codable, CaseIterable, Identifiable {
    case template = "模板名"
    case level1 = "第一层"
    case level2 = "第二层"
    case level3 = "第三层"
    case manual = "手输名称"
    case source = "原标签标题"

    var id: String { rawValue }
}

/// 菜单树的一个节点。
struct CustomNode: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    /// ★ 2026-10-19（用户）：「懒人一键保质期，**这个就是原始保质期**，不是重复功能」
    ///   → `days` = **原始保质期天数**（这一级）；`bestDays` = **最佳使用时间天数**。
    ///   两者可以不同（奶制品就是 +7 / +3 这种）。
    var days: Int?
    /// 最佳使用时间的天数（nil = 跟随 `days`，或继承上级）。
    var bestDays: Int?
    var children: [CustomNode] = []

    /// 该节点及其所有后代的数量（含自己）。
    var leafCount: Int { 1 + children.reduce(0) { $0 + $1.leafCount } }


    /// 层级上限：根（第 1 级）+ 3 层子菜单。
    static let maxDepth = 4
}

// MARK: - 存储

/// 自定义模板的本地存储（UserDefaults + JSON）。
///
/// ★ 用 `UserDefaults` 而不是写文件：数据量小（几十个模板），
///   和现有 `Prefs` 一致，不引入新的读写路径。
enum CustomTemplateStore {
    private static let key = "customTemplates.v1"
    /// 直接用标准 defaults（`Prefs` 内部的 `d` 是 private，不对外暴露）。
    private static let store = UserDefaults.standard

    private static var cache: [CustomTemplate]?

    static var all: [CustomTemplate] {
        get {
            if let cache { return cache }
            guard let data = store.data(forKey: key),
                  let list = try? JSONDecoder().decode([CustomTemplate].self, from: data) else {
                cache = []
                return []
            }
            cache = list
            return list
        }
        set {
            cache = newValue
            if let data = try? JSONEncoder().encode(newValue) {
                store.set(data, forKey: key)
            }
        }
    }

    static func template(id: UUID) -> CustomTemplate? {
        all.first { $0.id == id }
    }

    static func upsert(_ template: CustomTemplate) {
        var list = all
        if let index = list.firstIndex(where: { $0.id == template.id }) {
            list[index] = template
        } else {
            list.append(template)
        }
        all = list
    }

    static func delete(id: UUID) {
        all = all.filter { $0.id != id }
    }

    /// 首次启动时预置「重写」版模板（和内置的并存，方便对比实验）。
    ///
    /// ★ 2026-10-19（用户）：「能否用现有的新建模板功能**全部重写一遍原有功能**呢？
    ///   可以写完后在他们的后面**标出（重写）**，保留原有的先实验一下」
    static func seedPresetsIfNeeded() {
        let key = "customTemplates.seeded.v2"
        guard !store.bool(forKey: key) else { return }
        store.set(true, forKey: key)

        // ① 通用效期 = 空菜单（手输物料名）+ 原始 7 / 最佳 7 + 通用三行版式。
        var generic = CustomTemplate(name: "通用效期（重写）", icon: "clock")
        generic.tintName = "blue"
        generic.iconColorName = "white"
        generic.lazyDays = 7        // 原始保质期
        generic.defaultDays = 7     // 最佳使用时间
        generic.nodes = []          // 空菜单 = 前缀模板：打印时手输物料名

        // ② 奶制品 = 菜单五项，每项两个天数（原始 / 最佳），和内置规则一致。
        var dairy = CustomTemplate(name: "奶制品（重写）", icon: "drop")
        dairy.tintName = "cyan"
        dairy.iconColorName = "white"
        dairy.nodes = [
            CustomNode(name: "牛奶", days: 7, bestDays: 3),
            CustomNode(name: "高蛋白", days: 7, bestDays: 3),
            CustomNode(name: "豆奶", days: 7, bestDays: 3),
            CustomNode(name: "燕麦奶", days: 45, bestDays: 5),
            CustomNode(name: "巴旦木奶", days: 60, bestDays: 7),
        ]

        // ③ 肉类：冷藏 / 冷冻两大分支，各带原始 + 最佳天数。
        var meat = CustomTemplate(name: "肉类（重写）", icon: "flame")
        meat.tintName = "red"
        meat.iconColorName = "white"
        meat.nodes = [
            CustomNode(name: "冷藏", days: 3, bestDays: 3, children: [
                CustomNode(name: "牛肉"), CustomNode(name: "猪肉"), CustomNode(name: "鸡肉"),
            ]),
            CustomNode(name: "冷冻", days: 30, bestDays: 30, children: [
                CustomNode(name: "牛肉"), CustomNode(name: "猪肉"), CustomNode(name: "鸡肉"),
            ]),
        ]

        // ④ 肉类解冻：**第二个模板**，扫码续做（绑定上面的肉类模板）。
        var thaw = CustomTemplate(name: "肉类解冻（重写）", icon: "snowflake")
        thaw.tintName = "teal"
        thaw.iconColorName = "white"
        thaw.useSecondary = true
        thaw.sourceTemplateID = meat.id
        thaw.lazyDays = 3                   // 解冻完成 = 扫码 + 3 天

        // ⑤ 康普茶一发：制备版式（制备 / 完成 7 天 / 最佳 30 天）。
        var kombucha = CustomTemplate(name: "康普茶一发（重写）", icon: "cup.and.saucer")
        kombucha.tintName = "green"
        kombucha.iconColorName = "white"
        kombucha.usePrep = true
        kombucha.lazyDays = 7               // 完成 = 制备 + 7 天
        kombucha.defaultDays = 30           // 最佳 = 制备 + 30 天
        kombucha.nodes = [
            CustomNode(name: "原味"), CustomNode(name: "桃味"),
            CustomNode(name: "草莓"), CustomNode(name: "蓝莓"),
        ]

        // ⑥ 康普茶二发：**第二个模板**，扫一扫标签续做（绑定一发）。
        var kombucha2 = CustomTemplate(name: "康普茶二发（重写）", icon: "sparkles")
        kombucha2.tintName = "purple"
        kombucha2.iconColorName = "white"
        kombucha2.useSecondary = true
        kombucha2.sourceTemplateID = kombucha.id
        kombucha2.lazyDays = 3              // 二发完成 = 扫码 + 3 天

        all = all + [generic, dairy, meat, thaw, kombucha, kombucha2]
    }
}

// MARK: - 选中的路径（打印时用）

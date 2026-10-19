import Foundation

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
    /// 磁贴主色（存名字，避免 Codable 存 Color）。
    var tintName: String = "blue"
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

    /// 叶子总数（删除确认、统计用）。
    var leafCount: Int { nodes.reduce(0) { $0 + $1.leafCount } }
}

/// 菜单树的一个节点。
struct CustomNode: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    /// 建议天数；nil = 这一级不给建议时间。
    var days: Int?
    var children: [CustomNode] = []

    /// 该节点及其所有后代的数量（含自己）。
    var leafCount: Int { 1 + children.reduce(0) { $0 + $1.leafCount } }

    /// 从自己往下最多还能加多少层（0 = 已到最深层，不能再加子项）。
    func remainingDepth(from level: Int) -> Int {
        max(0, CustomNode.maxDepth - level)
    }

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
}

// MARK: - 选中的路径（打印时用）

/// 用户在自定义模板里选出来的那一项。
struct CustomTemplateSelection: Equatable {
    let template: CustomTemplate
    /// 从模板名开始的完整路径（"解冻", "猪肉", "梅花肉"）。
    let path: [String]
    /// 该级建议天数（nil = 没设，需要用户自己填时间）。
    let days: Int?

    /// 标签标题 = 路径用 `-` 拼起来。
    var title: String { path.joined(separator: "-") }
}

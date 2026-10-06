//
//  PdfSaver.swift
//  PDF 保存 —— 写入 App 文档目录，配合 Info.plist 的 UIFileSharingEnabled，
//  用户可在「文件」App 的「我的 iPhone → 效期管理系统」里看到。
//  对应 Flutter 的 PdfSaver.saveToDownloads（两端同一通道）。
//
//  ★ 安全：文件名来自用户输入的标题。即使上游已经过滤过一次，
//    这里也必须再做一次「只取最后一段 + 去掉 .. + 落地后校验前缀」，
//    否则标题里塞 `../../` 就能把文件写到沙箱外（目录穿越）。
//

import Foundation

enum PdfSaverError: LocalizedError {
    case unsafeFileName

    var errorDescription: String? {
        switch self {
        case .unsafeFileName: return "文件名不合法，已拒绝写入。"
        }
    }
}

enum PdfSaver {
    /// 保存 PDF 数据，返回人类可读的路径。
    static func save(_ data: Data, fileName: String) throws -> String {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent(sanitize(fileName))

        // 双保险：解析后仍必须落在文档目录内
        let root = docs.standardizedFileURL.path
        guard url.standardizedFileURL.path.hasPrefix(root + "/") else {
            throw PdfSaverError.unsafeFileName
        }

        // 原子写入 + 锁屏后不可读（用户数据一律加保护等级）
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url.path
    }

    /// 只保留最后一级文件名，清掉路径分隔符、控制字符与开头的点。
    static func sanitize(_ raw: String) -> String {
        var name = raw

        if let last = name.lastIndex(where: { $0 == "/" || $0 == "\\" }) {
            name = String(name[name.index(after: last)...])
        }

        name = name.unicodeScalars
            .filter { scalar in
                !CharacterSet.controlCharacters.contains(scalar)
                    && scalar != ":" && scalar != "*" && scalar != "?"
                    && scalar != "\"" && scalar != "<" && scalar != ">" && scalar != "|"
            }
            .reduce(into: "") { $0.unicodeScalars.append($1) }

        while name.hasPrefix(".") { name.removeFirst() }
        while name.hasSuffix(".") { name.removeLast() }

        if name.isEmpty { name = "标签" }
        if name.count > 60 { name = String(name.prefix(60)) }
        if !name.lowercased().hasSuffix(".pdf") { name += ".pdf" }
        return name
    }
}

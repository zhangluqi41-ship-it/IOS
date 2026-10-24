import Foundation

/// 简易诊断日志（只用于排查线上问题，正式版可保留 —— 开销极小）。
///
/// 写入 `Documents/drag_debug.txt`，可用 `_pull_abs.py` 从手机拉下来看。
/// 只保留最近 200 行，避免无限增长。
enum DebugLog {
    private static let queue = DispatchQueue(label: "debuglog")

    /// ★★★ 2026-10-24（用户：「**耗电发热有些严重**」）——
    ///   这个日志每拖一次就给 `Documents/drag_debug.txt` **整读+整写**一遍
    ///   （200 行 × 每次全量写盘），属于纯诊断开销，正式版必须关掉。
    ///   ➜ Release 构建里 `drag(_:)` 直接返回，不做任何 I/O；
    ///     需要排查时用 Debug 配置装包即可（`#if DEBUG`）。
    static func drag(_ message: String) {
        #if DEBUG
        append(to: "drag_debug.txt", message)
        #endif
    }

    private static func append(to fileName: String, _ message: String) {
        queue.async {
            guard let dir = FileManager.default.urls(for: .documentDirectory,
                                                     in: .userDomainMask).first else { return }
            let url = dir.appendingPathComponent(fileName)
            let stamp = ISO8601DateFormatter().string(from: Date())
            let line = "[\(stamp)] \(message)\n"

            var text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            text += line

            // 只留最后 200 行
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            if lines.count > 200 {
                text = lines.suffix(200).joined(separator: "\n")
            }
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - 清理历史诊断文件

extension DebugLog {
    /// 删掉旧版本在 `Documents/` 里留下的诊断文件。
    ///
    /// 这些文件只在排查时有用（`activity_debug.txt` 曾长到 1.2 MB），
    /// 现在 Release 已经不再写它们，但**用户设备上还留着旧文件**，占空间也碍眼。
    /// ⚠️ 只删日志类，**`records_backup_*.json` 是数据备份，一律不动**。
    static func cleanupLegacyDiagnostics() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        guard let docs else { return }
        let names = [
            "activity_debug.txt",
            "drag_debug.txt",
            "printer_log.txt",
            "_probe",
        ]
        for name in names {
            let url = docs.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }
}

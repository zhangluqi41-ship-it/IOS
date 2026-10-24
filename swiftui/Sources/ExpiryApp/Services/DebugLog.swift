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

//
//  PdfSaver.swift
//  PDF 保存 —— 写入 App 文档目录，配合 Info.plist 的 UIFileSharingEnabled，
//  用户可在「文件」App 的「我的 iPhone → 效期管理系统」里看到。
//  对应 Flutter 的 PdfSaver.saveToDownloads（两端同一通道）。
//

import Foundation

enum PdfSaver {
    /// 保存 PDF 数据，返回人类可读的路径。
    static func save(_ data: Data, fileName: String) throws -> String {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        return url.path
    }
}

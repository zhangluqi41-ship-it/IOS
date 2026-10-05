//
//  QRCodeTests.swift
//  二维码生成单元测试。
//

import XCTest
@testable import ExpiryManager

final class QRCodeTests: XCTestCase {

    func testQRImageGenerated() {
        let img = QRCodeGenerator.qrImage(for: "康普茶-红茶制备时间：测试")
        XCTAssertNotNil(img)
    }

    func testQRImageIsSquare() {
        guard let img = QRCodeGenerator.qrImage(for: "test-1234567890") else {
            XCTFail("二维码生成失败")
            return
        }
        XCTAssertEqual(img.width, img.height, "二维码应为正方形")
        XCTAssertGreaterThan(img.width, 10, "二维码应有足够的模块数")
    }
}

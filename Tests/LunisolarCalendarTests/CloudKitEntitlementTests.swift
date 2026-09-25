import XCTest
@testable import LunisolarCalendarApp

// MARK: - CloudKit entitlement 预检回归（真机 EXC_BREAKPOINT 崩溃修复）

/// 背景：个人团队（免费账号）不支持 iCloud capability，entitlements 中不含 CloudKit 容器。
/// `CKContainer.default()` 在此状态下直接 EXC_BREAKPOINT（非 throw），必须靠
/// `RealCloudKitProvider.hasCloudKitEntitlements()` 提前判定并降级。
///
/// 首版实现用 `String(contentsOf:encoding:.ascii)` 整文件解码 mobileprovision——
/// 文件头尾是二进制签名，解码必然失败 → 误判为"可用" → 真机首开同步仍崩溃。
/// 以下用例锁定修复后的行为：按字节切片解析 + 任何不确定一律返回 false（禁用）。
final class CloudKitEntitlementTests: XCTestCase {

    /// 二进制头 + XML plist + 二进制尾，模拟真实 provisioning profile 结构
    private func wrap(_ plistBody: String, head: [UInt8] = [0x00, 0x31, 0xFF, 0xFE, 0x42],
                      tail: [UInt8] = [0x99, 0x88, 0x77]) -> Data {
        var data = Data(head)
        data.append(contentsOf: Data(plistBody.utf8))
        data.append(contentsOf: Data(tail))
        return data
    }

    private let plistWithCloudKit = """
    <?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>\
    <key>com.apple.developer.icloud-container-identifiers</key>\
    <array><string>iCloud.com.example.app</string></array>\
    </dict></plist>
    """

    private let plistWithoutCloudKit = """
    <?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>\
    <key>com.apple.security.application-groups</key>\
    <array><string>group.com.example.app</string></array>\
    </dict></plist>
    """

    // MARK: - 核心回归：二进制包裹不得让解析失效

    /// 含 iCloud 容器声明 + 二进制头尾 → 判定可用（对应付费账号 / 分发构建）
    func testProvisionWithCloudKitDeclaredIsAvailable() {
        XCTAssertTrue(RealCloudKitProvider.provisionDeclaresCloudKit(wrap(plistWithCloudKit)))
    }

    /// 仅 App Groups（本项目个人团队现状）+ 二进制头尾 → 判定不可用，绝不创建容器
    func testProvisionWithoutCloudKitIsUnavailable() {
        XCTAssertFalse(RealCloudKitProvider.provisionDeclaresCloudKit(wrap(plistWithoutCloudKit)))
    }

    /// 头尾含非 ASCII 字节（0xFF/0xFE）是旧实现失败的根因：整文件 ASCII 解码会返回 nil
    func testNonASCIIWrapperBytesDoNotBreakParsing() {
        let data = wrap(plistWithCloudKit, head: [0xFF, 0xFE, 0x00, 0xC3, 0xA9])
        XCTAssertTrue(RealCloudKitProvider.provisionDeclaresCloudKit(data),
                      "二进制头不得导致误判为不可用")
    }

    // MARK: - 异常输入一律保守禁用（宁可降级，不可冒险创建容器）

    func testGarbageDataWithoutPlistIsUnavailable() {
        let garbage = Data((0..<64).map { UInt8($0 * 7 % 256) })
        XCTAssertFalse(RealCloudKitProvider.provisionDeclaresCloudKit(garbage))
    }

    func testTruncatedPlistWithoutClosingTagIsUnavailable() {
        let truncated = Data("<?xml version=\"1.0\"?><plist><dict>".utf8)
        XCTAssertFalse(RealCloudKitProvider.provisionDeclaresCloudKit(truncated))
    }

    func testEmptyDataIsUnavailable() {
        XCTAssertFalse(RealCloudKitProvider.provisionDeclaresCloudKit(Data()))
    }

    // MARK: - 回归：不得因「分发包形态」放行（发布包崩溃的那条路径）

    /// 测试宿主（无 embedded.mobileprovision）必须判为不可用。
    /// 旧实现只要 `appStoreReceiptURL` 存在就放行——而本工程发布包恰好是
    /// 「无 profile + 有收据」，正好落进该分支，于是 `CKContainer.default()`
    /// 在用户第一次点「启用 iCloud 同步」时触发 EXC_BREAKPOINT。
    func testEnvironmentWithoutVerifiableSourceIsUnavailable() {
        XCTAssertFalse(RealCloudKitProvider.hasCloudKitEntitlements(),
                       "无法核验 iCloud 容器声明时必须禁用，不得以收据或环境差异放行")
    }

    /// 只声明 `icloud-container-environment`（dev/production 选择）不足以授权容器创建
    func testProvisionDeclaringEnvironmentKeyOnlyIsUnavailable() {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>\
        <key>com.apple.developer.icloud-container-environment</key>\
        <string>Production</string>\
        </dict></plist>
        """
        XCTAssertFalse(RealCloudKitProvider.provisionDeclaresCloudKit(wrap(plist)),
                       "只有 environment 键不授权任何容器，必须判为不可用")
    }
}

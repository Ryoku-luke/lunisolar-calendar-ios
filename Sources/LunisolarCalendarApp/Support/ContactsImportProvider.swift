#if canImport(Contacts)
import Contacts
import Foundation

// MARK: - 联系人导入（CNContact 生日/纪念日 → CalendarEvent）

/// 从系统联系人里抽取"生日 / 纪念日"转成 App 事件：
/// - 申请 `.contacts` 权限
/// - 默认按 `.birthday` + `.dates` 取所有联系人的生日和纪念日
/// - 公历生日 → yearly，农历生日 → lunarAnnually（CNContact 不区分阴阳历，
///   默认按公历 yearly；用户在 UI 上可一次性转成农历）
public struct ContactsImportProvider: SystemImportProviding, @unchecked Sendable {
    public let source: SystemImportSource = .contacts

    private let store: CNContactStore
    private let fetchBirthday: Bool
    private let fetchAnniversaries: Bool
    /// 默认 false：CNContact 生日是公历，按 .yearly 重复；true 时改 .lunarAnnually
    private let asLunarAnnually: Bool

    public init(
        store: CNContactStore = CNContactStore(),
        fetchBirthday: Bool = true,
        fetchAnniversaries: Bool = true,
        asLunarAnnually: Bool = false
    ) {
        self.store = store
        self.fetchBirthday = fetchBirthday
        self.fetchAnniversaries = fetchAnniversaries
        self.asLunarAnnually = asLunarAnnually
    }

    public func requestAuthorization() async throws -> Bool {
        // A1-2 修复：iOS 18+ / macOS 15+ 使用 `requestAccess(for:)` async throws 版本
        // （替代 iOS 18 起 deprecated 的 completion-handler 版），旧版 SDK 回退到
        // withCheckedThrowingContinuation 包 completion handler。
        let entityType = CNEntityType.contacts
        let status = CNContactStore.authorizationStatus(for: entityType)
        switch status {
        case .authorized, .limited:
            return true
        case .notDetermined:
            if #available(iOS 18.0, macOS 15.0, watchOS 11.0, *) {
                return try await store.requestAccess(for: entityType)
            } else {
                return try await withCheckedThrowingContinuation { continuation in
                    store.requestAccess(for: entityType) { granted, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(returning: granted)
                        }
                    }
                }
            }
        case .restricted, .denied:
            return false
        @unknown default:
            return false
        }
    }

    public func fetchEvents() async throws -> [SystemImportEvent] {
        let ok = try await requestAuthorization()
        guard ok else { throw SystemImportError.unauthorized(source: source) }

        var keys: [CNKeyDescriptor] = []
        if fetchBirthday { keys.append(CNContactBirthdayKey as CNKeyDescriptor) }
        if fetchAnniversaries { keys.append(CNContactDatesKey as CNKeyDescriptor) }
        keys.append(CNContactGivenNameKey as CNKeyDescriptor)
        keys.append(CNContactFamilyNameKey as CNKeyDescriptor)
        keys.append(CNContactIdentifierKey as CNKeyDescriptor)
        guard !keys.isEmpty else { return [] }

        let request = CNContactFetchRequest(keysToFetch: keys)
        var results: [SystemImportEvent] = []

        // Swift 6 / iOS 18：enumerateContacts 返回 Void（不再是 Bool），
        // 且内部失败会通过 throws 传递。用 try? 静默忽略（权限已在上方 requestAuthorization 处理）。
        try? self.store.enumerateContacts(with: request) { contact, _ in
            let name = [contact.givenName, contact.familyName]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            let displayName = name.isEmpty ? "联系人" : name

            if self.fetchBirthday, let bd = contact.birthday {
                // Swift 6 / iOS 18：NSDateComponents → DateComponents 隐式桥接已移除，
                // 必须显式 as DateComponents。新 SDK 已将 CNContact.birthday 返回类型
                // 改为 DateComponents?，旧 SDK 仍返回 NSDateComponents?，as 同时兼容两者。
                let dc = bd as DateComponents
                if let ev = self.birthdayToEvent(contactID: contact.identifier,
                                                 name: displayName,
                                                 dateComponents: dc) {
                    results.append(ev)
                }
            }
            if self.fetchAnniversaries {
                for d in contact.dates {
                    // Swift 6：CNContact.Date.value 在旧 SDK 返回 NSDateComponents，
                    // 新 SDK 改为 DateComponents；显式 as 双向兼容。
                    let dc = d.value as DateComponents
                    if let ev = self.anniversaryToEvent(contactID: contact.identifier,
                                                        label: d.label,
                                                        name: displayName,
                                                        dateComponents: dc) {
                        results.append(ev)
                    }
                }
            }
        }

        return results
    }

    // MARK: - 生日 / 纪念日 → SystemImportEvent

    private func birthdayToEvent(
        contactID: String,
        name: String,
        dateComponents: DateComponents
    ) -> SystemImportEvent? {
        // CNContact.birthday 返回 DateComponents，month/day/year 都是可选 Int?
        guard let month = dateComponents.month, month > 0,
              let day = dateComponents.day, day > 0 else { return nil }
        let cal = Calendar(identifier: .gregorian)
        // BUG-P1-1 修复：禁止用「year ?? 0 > 0 ? year! : 1900」强制解包。
        // year 是 DateComponents 上的懒取计算属性（可能跨线程/进程从 Contacts DB 取），
        // 先读可选再解包与"再次解包"之间不保真，极端情况下会 crash。
        let year = dateComponents.year.map { $0 > 0 ? $0 : nil } ?? 1900
        guard let s = cal.date(from: DateComponents(year: year,
                                                    month: month,
                                                    day: day,
                                                    hour: 9)) else { return nil }
        return SystemImportEvent(
            sourceID: "contact-birthday:\(contactID)",
            title: "\(name) 生日",
            startDate: s,
            isAllDay: false,
            notes: "从联系人导入",
            repeatRule: asLunarAnnually ? .lunarAnnually : .yearly,
            eventType: .reminder,
            priority: .high
        )
    }

    private func anniversaryToEvent(
        contactID: String,
        label: String?,
        name: String,
        dateComponents: DateComponents
    ) -> SystemImportEvent? {
        // A1-2: CNContact.dates[i].value 原签名是 NSDateComponents（与 birthday 的
        // DateComponents 不一致），Swift 会在 iOS 18 SDK 警告 "use of DateComponents
        // instead of NSDateComponents"，外加 .month / .year 对可选 Int? 的空值比较
        // 警告。统一先 bridge 成 DateComponents 再处理。
        let dc = dateComponents
        guard let month = dc.month, month > 0,
              let day = dc.day, day > 0 else { return nil }
        let cal = Calendar(identifier: .gregorian)
        let year = (dc.year ?? 0) > 0 ? dc.year : 1900
        guard let s = cal.date(from: DateComponents(year: year,
                                                    month: month,
                                                    day: day,
                                                    hour: 10)) else { return nil }
        let labelName = (label ?? "纪念日").isEmpty ? "纪念日" : (label ?? "纪念日")
        return SystemImportEvent(
            sourceID: "contact-\(labelName):\(contactID)",
            title: "\(name) \(labelName)",
            startDate: s,
            isAllDay: false,
            notes: "从联系人导入",
            repeatRule: asLunarAnnually ? .lunarAnnually : .yearly,
            eventType: .reminder,
            priority: .normal
        )
    }
}
#endif

#if canImport(Contacts)
import Contacts
import Foundation

public struct ContactsImportProvider: SystemImportProviding {
    public let source: SystemImportSource = .contacts

    private let store: CNContactStore
    private let fetchBirthday: Bool
    private let fetchAnniversaries: Bool
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
        let entityType = CNEntityType.contacts
        let status = CNContactStore.authorizationStatus(for: entityType)
        switch status {
        case .authorized, .limited:
            return true
        case .notDetermined:
            return try await withCheckedThrowingContinuation { continuation in
                store.requestAccess(for: entityType) { granted, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
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

        let didEnumerate = self.store.enumerateContacts(with: request) { contact, _ in
            let name = [contact.givenName, contact.familyName]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            let displayName = name.isEmpty ? "联系人" : name

            if self.fetchBirthday, let bd = contact.birthday {
                if let ev = self.birthdayToEvent(contactID: contact.identifier,
                                                 name: displayName,
                                                 dateComponents: bd) {
                    results.append(ev)
                }
            }
            if self.fetchAnniversaries {
                for d in contact.dates {
                    if let ev = self.anniversaryToEvent(contactID: contact.identifier,
                                                        label: d.label,
                                                        name: displayName,
                                                        dateComponents: d.value) {
                        results.append(ev)
                    }
                }
            }
        }
        if !didEnumerate {
            // enumerate 返回 false 通常意味着权限/通讯录受限
        }

        return results
    }

    private func birthdayToEvent(
        contactID: String,
        name: String,
        dateComponents: DateComponents
    ) -> SystemImportEvent? {
        guard dateComponents.month > 0, dateComponents.day > 0 else { return nil }
        let cal = Calendar(identifier: .gregorian)
        let year = dateComponents.year > 0 ? dateComponents.year : 1900
        guard let s = cal.date(from: DateComponents(year: year,
                                                    month: dateComponents.month,
                                                    day: dateComponents.day,
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
        dateComponents: NSDateComponents
    ) -> SystemImportEvent? {
        guard dateComponents.month > 0, dateComponents.day > 0 else { return nil }
        let cal = Calendar(identifier: .gregorian)
        let year = dateComponents.year > 0 ? dateComponents.year : 1900
        guard let s = cal.date(from: DateComponents(year: year,
                                                    month: dateComponents.month,
                                                    day: dateComponents.day,
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

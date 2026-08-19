#if canImport(SwiftUI)
import SwiftUI
import Observation

// MARK: - App 入口

@main
struct LunisolarCalendarApp: App {

    @State private var store = EventStore.shared

    var body: some Scene {
        WindowGroup {
            CalendarMonthView()
                .environment(store)
                .preferredColorScheme(.none)
                .tint(Color.systemBlue)
        }
    }
}

// MARK: - SwiftPM 宿主入口 (兼容调用)

@available(iOS 17.0, *)
public struct CalendarAppRootView: View {
    @State private var store = EventStore.shared

    public init() {}

    public var body: some View {
        CalendarMonthView()
            .environment(store)
    }
}


#endif

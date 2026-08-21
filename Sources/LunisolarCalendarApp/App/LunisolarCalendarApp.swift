#if canImport(SwiftUI)
import SwiftUI
import Observation

// MARK: - App 入口

@main
struct LunisolarCalendarApp: App {

    @State private var store = EventStore.shared

    var body: some Scene {
        WindowGroup {
            AdaptiveRootView()
                .environment(store)
                .preferredColorScheme(.none)
                .tint(Color.systemBlue)
        }
    }
}

// MARK: - 自适应根视图：iPhone NavigationStack / iPad NavigationSplitView

/// iPad (regular sizeClass) 用双栏 SplitView：左月历 + 右详情
/// iPhone (compact) 保留单栏 NavigationStack
struct AdaptiveRootView: View {
    @Environment(\.horizontalSizeClass) private var hSizeClass

    var body: some View {
        if hSizeClass == .regular {
            // iPad：双栏布局
            iPadRootView()
        } else {
            // iPhone：单栏布局
            CalendarMonthView()
        }
    }
}

// MARK: - iPad 双栏根视图

struct iPadRootView: View {
    @State private var selectedDate: Date = Date()
    @Environment(EventStore.self) private var store

    var body: some View {
        NavigationSplitView {
            // 左栏：月历
            CalendarMonthView(selectedDate: $selectedDate)
        } detail: {
            // 右栏：当日详情
            DayDetailView(date: selectedDate)
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

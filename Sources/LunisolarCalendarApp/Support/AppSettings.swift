import Foundation

// MARK: - 偏好键与默认值统一入口
//
// 背景：`@AppStorage` 的"默认值"只作用于 UI 读取，**不会写入 UserDefaults**。
// 因此对同一键做 raw `UserDefaults` 读取时，必须显式带上同样的默认值，
// 否则会出现"设置页显示已开启、业务逻辑判定为关闭"的分裂——
// 灵动岛时间胶囊曾因这个分裂完全不上岛（TimeCapsuleCoordinator 读 false，UI 显示 true）。
//
// 规则：新增"@AppStorage 默认值为 true 的键"时，raw 读取一律走本类型，
// 并在 registerDefaults() 中登记，避免同类问题复发。

public enum AppSettings {

    // MARK: 键

    /// 时间胶囊（Live Activities）总开关；@AppStorage 默认 true
    public static let liveActivityEnabledKey = "Lunisolar.liveActivity.enabled"

    // MARK: raw 读取（带与 @AppStorage 一致的默认值）

    /// 时间胶囊总开关。@AppStorage 侧默认 true，此处必须一致。
    public static var liveActivityEnabled: Bool {
        (UserDefaults.standard.object(forKey: liveActivityEnabledKey) as? Bool) ?? true
    }

    /// App 启动时注册默认值域（NSRegistrationDomain）：
    /// 注册后连 `bool(forKey:)` 也能得到正确默认值，后续新增读取点无需各自处理。
    public static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            liveActivityEnabledKey: true
        ])
    }
}

# 清和日历 · Entitlement 与权限清单

本文档列出上架 App Store 所需的全部 Capability / Entitlement / 隐私权限配置。

---

## 一、Xcode Capability 配置

在 Xcode → 主 App Target → Signing & Capabilities 中添加以下能力：

| Capability | 用途 | 必需 | 配置项 |
|---|---|---|---|
| **App Groups** | 主 App 与 Widget Extension 共享数据快照 | ✅ | `group.com.lunisolar.calendar` |
| **iCloud** | CloudKit 私有数据库同步 | ✅ | 勾选 CloudKit，Container ID：`iCloud.com.lunisolar.calendar` |
| **Push Notifications** | 未来支持远端推送通知（当前本地通知不需要） | ⚪ 可选 | — |
| **Background Modes** | 后台刷新（可选，用于农历提醒续排） | ⚪ 可选 | Background fetch |

> ⚠️ **重要**：Widget Extension Target 也必须勾选 **App Groups**，且与主 App 使用**完全相同**的 Group ID，否则 Widget 无法读取主 App 写入的快照。

---

## 二、Entitlements 文件

### 主 App (`LunisolarHostApp/LunisolarCalendar.entitlements`)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- App Group：主 App ↔ Widget 共享 -->
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.lunisolar.calendar</string>
    </array>
</dict>
</plist>
```

### Widget Extension (`LunisolarWidget/LunisolarWidget.entitlements`)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- 必须与主 App 完全一致 -->
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.lunisolar.calendar</string>
    </array>
</dict>
</plist>
```

---

## 三、Info.plist 隐私权限

在 `Sources/LunisolarCalendarApp/Info.plist` 中配置以下权限说明文案（**上架必须**，否则审核被拒）：

| Key | 用途 | 当前文案 |
|---|---|---|
| `NSContactsUsageDescription` | 导入联系人生日 | "用于导入联系人生日，并按农历每年重复提醒。" |
| `NSCalendarsFullAccessUsageDescription` | 从系统日历导入日程（iOS 17+） | "用于从系统日历导入日程安排，方便迁移历史事件。" |
| `NSCalendarsUsageDescription` | 从系统日历导入日程（iOS 16 及以下） | "用于从系统日历导入日程安排，方便迁移历史事件。" |

> 通知权限（`UNUserNotificationCenter`）**不需要**在 Info.plist 中声明，运行时调用 `requestAuthorization` 即可。

---

## 四、CloudKit Container 配置

### 1. 创建 Container

1. 登录 [Apple Developer](https://developer.apple.com/account/) → Certificates, Identifiers & Profiles
2. Identifiers → 找到 App 的 Bundle ID → 勾选 iCloud → 配置 CloudKit Container
3. 创建 Container ID：`iCloud.com.lunisolar.calendar`

### 2. Xcode 配置

1. 主 App Target → Signing & Capabilities → 添加 iCloud
2. 勾选 CloudKit → 选择 Container：`iCloud.com.lunisolar.calendar`
3. 确保 Widget Extension Target **不**需要 iCloud capability（Widget 只读 App Group 快照）

### 3. 代码接入

`RealCloudKitProvider` 默认使用 `CKContainer.default()`，如需指定容器：

```swift
let provider = RealCloudKitProvider(
    containerIdentifier: "iCloud.com.lunisolar.calendar"
)
```

### 4. 首次运行

首次在真机运行时，CloudKit 会自动创建 Schema（Development 环境）。生产环境需在 CloudKit Dashboard 手动 Deploy Schema。

---

## 五、隐私清单（Privacy Manifest）

iOS 17+ 要求 App 声明隐私数据访问。创建 `Sources/LunisolarCalendarApp/PrivacyInfo.xcprivacy`：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSPrivacyAccessedAPITypes</key>
    <array>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <string>C617.1</string>
            </array>
        </dict>
    </array>
    <key>NSPrivacyTrackingDomains</key>
    <array/>
    <key>NSPrivacyCollectedDataTypes</key>
    <array/>
</dict>
</plist>
```

> 本 App 不收集用户数据、不进行跟踪、不接入第三方分析 SDK。CloudKit 同步的日历事件属于用户主动管理的个人数据，不用于追踪。

---

## 六、验证清单

- [ ] 主 App Target 与 Widget Extension Target 的 App Group ID 完全一致
- [ ] CloudKit Container ID 与 Developer Portal 注册的一致
- [ ] 真机首次运行后，CloudKit Dashboard 出现 Records 列表
- [ ] 真机创建事件 → 另一设备同步后可见
- [ ] Widget 在主 App 后台 6h 内仍显示正确数据
- [ ] 隐私清单已包含 File timestamp 声明

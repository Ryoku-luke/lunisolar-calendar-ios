# 使用 Xcode 编译 · 测试 · 发布

> 本文档说明如何使用 Xcode 对**清和日历**（LunisolarCalendar）进行本地编译、单元测试、真机调试与上架发布。
>
> 本项目是 **Swift Package Manager（SPM）纯工程**，仓库里没有 `.xcodeproj`。Xcode 打开 `Package.swift` 就会自动生成 `LunisolarCalendar.xcodeproj`，但要跑 iOS App / Widget / 真机调试，仍然需要**手动创建一个宿主 iOS App target**（见 §2）。

---

## 目录

1. [环境要求](#1-环境要求)
2. [首次打开 · 接入 iOS App Target](#2-首次打开--接入-ios-app-target)
3. [编译 & 运行](#3-编译--运行)
4. [单元测试](#4-单元测试)
5. [Widget 小组件 Extension](#5-widget-小组件-extension)
6. [本地通知 / Contacts / Calendars 权限](#6-本地通知--contacts--calendars-权限)
7. [iCloud · CloudKit](#7-icloud--cloudkit)
8. [黄历离散数据库生成器](#8-黄历离散数据库生成器)
9. [iPad 适配](#9-ipad-适配)
10. [发布到 App Store](#10-发布到-app-store)

---

## 1. 环境要求

| 项 | 要求 |
| --- | --- |
| Mac | Apple Silicon（M1+）或 Intel 均可 |
| Xcode | **16.0+**（Swift 6） |
| iOS SDK | 最低支持 **iOS 17**；推荐 iOS 26 |
| macOS SDK | 最低支持 **macOS 14**（Widget / CloudKit 用） |
| Swift | 6.0（strict concurrency 模式） |
| CocoaPods | 不需要，本项目**无第三方依赖** |
| Apple 开发者账号 | 真机调试免费；CloudKit / 上架 App Store 需要付费开发者计划 |

### 命令行快速自检

```bash
xcode-select -p            # 应该指向 /Applications/Xcode.app/Contents/Developer
xcodebuild -version        # 16.x
swift --version            # 6.0
swift build                # 全 target 构建（命令行）
swift test                 # 跑单元测试（命令行）
```

### 项目 Target 结构

```
Package.swift
├── LunarCore              # Models/LunarDate.swift + Models/Huangli.swift
│   └── 纯 Swift，无 UIKit/SwiftUI 依赖；gen_huangli_db 只依赖它
├── LunisolarCalendarApp   # App UI + Stores + Views + Widgets + 同步/导入
│   └── 依赖 LunarCore
├── gen_huangli_db         # CLI，离散黄历数据库生成工具
└── LunisolarCalendarTests # 单元测试
```

---

## 2. 首次打开 · 接入 iOS App Target

SPM 纯工程 `swift run LunisolarCalendarApp` 无法启动 App（没有可执行的 iOS 入口）。需要：

### 方式 A · 创建一个空的 iOS App Target（推荐）

1. Xcode → **File → Open**，选择仓库根目录的 `Package.swift`。
   Xcode 会自动生成 `LunisolarCalendar.xcodeproj`（在 DerivedData，不用手动保存）。
2. **File → New → Target…** → 选 **iOS → App**。
   - Product Name：`LunisolarCalendar`（或别的，只要**与 SPM product 名字不同**就行）
   - Interface：SwiftUI
   - Language：Swift
   - **⚠️ 不要勾 "Use SwiftUI App" 以外的东西**，Core Data / Testing / Localization 都关掉
3. 新 target 创建完后，进入 **Project → Target → General → Frameworks, Libraries, and Embedded Content**。
   点 `+`，选择 `Package Products` 分组下的 **`LunisolarCalendarApp`**，设为 **`Embed & Sign`**。
4. 删除模板生成的 `ContentView.swift` 和 `LunisolarCalendarApp.swift`（Xcode 默认建的那个）。
5. 新建一个**只有三行**的入口文件 `AppDelegate+Main.swift`（放在你新建 target 的文件夹里，**不要**放进 Sources/LunisolarCalendarApp）：

   ```swift
   import SwiftUI
   import LunisolarCalendarApp

   @main
   struct HostApp: App {
       var body: some Scene {
           WindowGroup {
               AdaptiveRootView()
                   .environment(EventStore.shared)
           }
       }
   }
   ```

6. 把新 target 的 **Bundle Identifier** 设为你自己的（例如 `com.yourname.lunisolar-calendar`），并在 **Signing & Capabilities** 勾上你的 Team。
7. 如果要跑 Widget，按 §5 创建 Widget Extension target。

### 方式 B · 用 `swift run` + 命令行

不推荐，只能验证业务逻辑，无法启动 UI：

```bash
swift build
.build/debug/gen_huangli_db Resources/huangli_db.json
```

---

## 3. 编译 & 运行

### Xcode 界面

- 左上角选择 Scheme：新宿主 App target（不是 SPM 生成的 `LunisolarCalendarApp` library）。
- 设备：Simulator → 选 **iPhone 16 (iOS 26)** 或 iPad；真机需要连数据线 + 开发者证书。
- **⌘R** Run；**⌘B** 只编译；**⌘.** 停止。

### 命令行（CI 用）

```bash
# 模拟器 Debug 构建
xcodebuild -scheme LunisolarCalendar \
    -destination 'platform=iOS Simulator,name=iPhone 16' \
    -configuration Debug build

# 真机 Release 构建（需要签名）
xcodebuild -scheme LunisolarCalendar \
    -destination 'generic/platform=iOS' \
    -configuration Release build CODE_SIGNING_ALLOWED=YES
```

### 常见编译错误速查

| 错误 | 原因 | 修复 |
| --- | --- | --- |
| `'HuangliDay' initializer is inaccessible due to 'internal' protection level` | 拆分 LunarCore target 后，跨模块调用 internal init | 确保 Huangli.swift / LunarDate.swift 里有显式 `public init`（本仓库已修好） |
| `cannot find 'HuangliGenerator' / 'ChineseCalendar' in scope` | 测试文件没拿到 LunarCore 类型 | HuangliDBProvider.swift 里的 `@_exported import LunarCore` 必须保留 |
| `Bundle.module` unavailable | iOS App Target 不是 SPM module | 本项目已改成 `Bundle.main` + Bundle+Resources.swift |
| `Color.tertiary` removed in iOS 18 | 旧 SwiftUI API | 用 `Color(uiColor: .tertiaryLabel)` 或 `Theme.tertiary` |
| `UIScreen.main` deprecated | iOS 26 | 用 GeometryReader 或 UIWindowScene 读屏幕尺寸 |
| CloudKit entitlement 缺失 | 没加 iCloud capability | 见 §7 |
| 链接错误 `duplicate symbols for architecture x86_64` | 同时链接了 LunarCore 和 LunisolarCalendarApp | LunisolarCalendarApp 依赖 LunarCore，不要把 LunarCore 重复加入宿主 target |

---

## 4. 单元测试

### 全部测试（推荐先跑命令行）

```bash
swift test
# 期望输出：Test run with 0 tests in 0 suites passed after 0.001 seconds.
# + LunisolarCalendarTests: 59 tests, 0 failures
```

### Xcode 跑

- Scheme 选宿主 App target。
- **⌘U** 或 Product → Test。
- Test Navigator (⌘6) 可以单独跑某一个 Case。

### 测试清单（59 tests）

| 测试类 | 数量 | 覆盖 |
| --- | ---: | --- |
| LunarDateTests | 4 | 公历↔农历双向真值表（1900-2100）、润月 |
| HuangliTests | 3 | 天干地支、神位、chongSha/naYin 兼容别名 |
| HuangliDBProviderTests | 6 | 离散库命中 / fallback / DB 与算法一致性 |
| CalendarEventTests | 11 | RepeatRule、RepeatRule.displayText、iconName、UID 稳定性、ICS 解析 |
| EventStoreTests | 7 | CRUD、dirty/migration、statsCache、autoPush |
| DataPortabilityTests | 3 | JSON 导入导出、UUID 合并 |
| ICloudSyncTests | 6 | SyncBidirectional、MockCloudKitProvider 全链路 |
| WidgetSnapshotTests | 4 | EventStore auto-write snapshot、stale 忽略 |
| SystemImportTests | 9 | Contacts Event Bridge、UUID 稳定、DTO 映射 |

### 新增测试文件的位置

```
Tests/LunisolarCalendarTests/YourNewTests.swift
```

头文件加 `import XCTest`，以及 `import LunisolarCalendarApp`（`@_exported import LunarCore` 会自动 re-export，所以 LunarDate / HuangliDay / ChineseCalendar / HuangliGenerator 都可见）。

---

## 5. Widget 小组件 Extension

### 目标

本项目已实现 **3 种 Widget**，统一在 `LunisolarWidgetBundle()`：

| 样式 | 入口 | 说明 |
| --- | --- | --- |
| 今日黄历概览 | `HuangliTodayWidgetEntry` | 宜忌 + 冲煞 + 农历日期 |
| 农历日期卡片 | `LunarDateWidgetEntry` | 农历月日 + 节日 + 生肖 |
| 今日待办进度 | `EventProgressWidgetEntry` | 完成比例 + 近期待办条数 |

### Xcode 接入步骤

1. **File → New → Target…** → **Widget Extension**。
   - Product Name：`LunisolarWidget`
   - **⚠️ 不勾 "Include Configuration App Intent"**
   - Language：Swift
2. 进入 `LunisolarWidget` target，**General → Frameworks, Libraries, and Embedded Content** → `+` → `Package Products` → **`LunisolarCalendarApp`**，设为 `Embed & Sign`。
3. 模板生成的 Widget 文件删掉，替换为一行：

   ```swift
   import WidgetKit
   import SwiftUI
   import LunisolarCalendarApp

   @main
   struct LunisolarWidgetBundle: WidgetBundle {
       var body: some Widget {
           HuangliTodayWidget()
           LunarDateWidget()
           EventProgressWidget()
       }
   }
   ```

4. **重要**：让 App Group 生效。
   - 宿主 App target 和 `LunisolarWidget` target 都要在 **Signing & Capabilities** 加 **App Groups**，勾选 `group.com.yourname.lunisolar`。
   - 然后在宿主 App 的 `AppDelegate`（或你自己的入口）里：

     ```swift
     EventStore.shared.widgetAppGroupID = "group.com.yourname.lunisolar"
     ```

   Widget 侧通过 `WidgetSnapshotStore` 读同一份快照 JSON。

5. 宿主 App 的 `Info.plist` 必须有 `NSExtension` 记录指向 Widget bundle（Xcode 加 Extension target 时会自动处理）。

### Widget 调试

- Run Scheme 选宿主 App target（Widget 不单独 Run）。
- 真机 Debug 时 Widget 会被 Xcode 自动安装；
  或者桌面长按空白 → `+` → 搜 `Lunisolar` 添加。
- 刷新数据：Widget 内部使用 `WidgetCenter.shared.reloadAllTimelines()`，由 `EventStore` 在事件变更时触发。

### WidgetKit 限制速查

| 限制 | 说明 | 本项目对策 |
| --- | --- | --- |
| 不支持 UIKit | 只能 SwiftUI | 全部 WidgetView 是纯 SwiftUI |
| 每 15 分钟最多刷新一次 | 系统节流 | 用 `EventStore` 写 snapshot JSON；Widget 下次刷新时读 |
| 不能访问网络（iOS 17+ 有 NSAppTransport） | — | 本项目不联网，纯本地数据 |

---

## 6. 本地通知 / Contacts / Calendars 权限

Info.plist 已预置以下 usage description，真机首次使用会弹窗询问：

| Key | 场景 |
| --- | --- |
| `NSContactsUsageDescription` | 系统导入联系人生日 → 农历/公历纪念日 |
| `NSCalendarsUsageDescription` / `NSCalendarsFullAccessUsageDescription` | 导入/导出 ICS（EventKit） |
| `UNUserNotificationCenter` | 设置提醒时触发本地通知（需代码申请） |

### 本地通知申请代码（已内置）

```swift
NotificationManager.shared.requestAuthorization()  // 在 Settings 页首次使用时触发
```

系统会弹出 `NotificationSettingsViewController`，用户允许后才能排程 `UNCalendarNotificationTrigger`。

### Contacts 导入（已内置）

```swift
ContactsImportProvider().fetchBirthdays()  // 返回 [SystemContactBirthdayDTO]
```

内部自动申请 `CNContactStore authorizationStatus`。拒绝后返回空数组，不崩溃。

---

## 7. iCloud · CloudKit

### 前提

1. **Signing & Capabilities**：宿主 App target + Widget target 都要加 **iCloud** capability，并勾选 **CloudKit**（选或新建一个 iCloud Container，例如 `iCloud.com.yourname.lunisolar`）。
2. macOS entitlements 另建 `LunisolarCalendar-macOS.entitlements`（如有）。iOS entitlement Xcode 会自动生成。
3. `ICloudSyncProvider.swift` / `MockCloudKitProvider.swift` / `RealCloudKitProvider.swift` 在 SPM 工程里**不直接链接** CloudKit，这样 Linux / CI 能通过；真机构建时宿主 App target 必须显式 `import CloudKit`。

### Mock vs Real 切换

- 默认走 **MockCloudKitProvider**（纯内存，离线测试 / `swift test`）。
- 真机 iCloud 同步通过 `SyncBootstrapper` 自动切换 `RealCloudKitProvider`：

  ```swift
  #if canImport(CloudKit)
  EventSyncCoordinator.shared.bootstrapIfNeeded()
  #endif
  ```

### CloudKit 调试技巧

- CloudKit Dashboard：https://icloud.developer.apple.com/dashboard/
- 真机 Console.app 过滤 `Lunisolar` 看日志（本项目所有同步操作都走 `AppLogger.sync`）。
- 删除所有本地 iCloud 缓存：Settings → 你的 Apple ID → iCloud → Manage Storage → 找到你的 App → "Delete All"。

### 已知限制

- `CKModifyRecordsOperation.perRecordCompletionBlock` 在 macOS 12 被 deprecated，但 Apple 没提供替代 API（per-record Result 只在 Fetch/Query 上有）。本项目用 `configurePerRecordTracking` helper 封装，Xcode 会有 deprecation warning，但运行正常。
- Linux / `swift test` 环境没有 CloudKit；`ICloudSyncTests` 全部跑 Mock，测试全绿。

---

## 8. 黄历离散数据库生成器

位置：`Tools/gen_huangli_db/main.swift`

它**不依赖** SwiftUI / LunisolarCalendarApp，只依赖 `LunarCore`。所以 CLI target 可以独立构建运行，不会触发 `@main` 符号冲突。

### 命令行生成（2024-01-01 ~ 2028-12-31）

```bash
swift run gen_huangli_db Sources/LunisolarCalendarApp/Resources/huangli_db.json
```

### 输出格式

```json
{
  "v": 1,
  "range": ["2024-01-01", "2028-12-31"],
  "count": 1826,
  "days": {
    "2026-09-01": {
      "y": ["祭祀", "祈福"],
      "j": ["出行", "开市"],
      "c": "鼠",
      "s": "南",
      "w": "海中金",
      "g": "喜神:东北 财神:西南"
    }
  }
}
```

### 扩展年份

把 `start` / `end` 的 DateComponents 改成你想要的范围，再跑一遍。农历数据表覆盖 1900-2100 年，中间任意连续区间都可以。

### 重要注意

生成器**强制走纯算法**（`HuangliGenerator.algorithmGenerate(for:lunar:)`），不查已有的离散库。这样避免循环写入同样的数据。离散库内容被写入 `Resources/huangli_db.json` 后，`HuangliDBProvider` 会优先查库，缺失才 fallback 到算法。

---

## 9. iPad 适配

`CalendarMonthView` 的手势代码做了 `#if canImport(UIKit)` 隔离，避免 macOS / Linux 编译时缺失 `GestureState`。iPad 上：

- NavigationSplitView（`AdaptiveRootView` 自动生效）：左侧月视图 + 右侧 DayDetailView。
- 横竖屏都支持（`Info.plist` 已声明 `UIInterfaceOrientationLandscapeLeft/Right`）。
- Widget 在 iPad 上默认用 `systemMedium` / `systemLarge`，自动适配。

### iPad 真机调优

在 iPad Simulator 跑起来后，**Product → Destination → iPad Pro 13" (M4)** 观察布局。NavigationSplitView 在横屏默认显示两栏，竖屏折叠为一栏，符合 HIG。

---

## 10. 发布到 App Store

### 10.1 准备工作

1. **Apple Developer 账号**（$99/年）。
2. 在 https://developer.apple.com/account/ 注册 App ID：
   - 选 "App ID" → Identifier → App IDs → **+**
   - Bundle ID 填你自己的（**必须**与 Xcode Signing 里的一致）
   - Capabilities：勾选 **iCloud** + CloudKit + **Push Notifications** + **Background Modes (remote-notification)**
3. 如需 Widget App Group，在 **Identifiers → App Groups** 创建一个，然后回 App ID 关联。
4. iCloud Container（在 iCloud 后台）要和 App ID 绑定。

### 10.2 Info.plist 版本号

- `CFBundleShortVersionString`：语义化版本（例如 `1.2.0`），**App Store 展示用**。
- `CFBundleVersion`：build 号，**每次上传必须 +1**（整数）。

### 10.3 Archive 流程

```bash
# 命令行
xcodebuild \
  -scheme LunisolarCalendar \
  -archivePath LunisolarCalendar.xcarchive \
  -destination 'generic/platform=iOS' \
  -configuration Release archive
```

或 Xcode 界面：

> Product → Archive（或 ⌘Y）→ 等待构建完成 → Organizer 弹出 → Distribute App

### 10.4 Distribute 选项

| 场景 | 选 | 说明 |
| --- | --- | --- |
| 内测 | App Store Connect → **TestFlight** | 先上 beta 测一遍 |
| 灰度 | Ad Hoc | 小范围内部测试（需要设备 UDID） |
| 正式上架 | **App Store Connect** | 自动处理签名、上传到 App Store |

### 10.5 App Store Connect 填写

1. https://appstoreconnect.apple.com/ → **My Apps** → `+ New App`
2. Bundle ID、版本号、build 号必须与 Archive 一致。
3. **App Information**：
   - Primary Category：Lifestyle
   - Subcategory：Productivity
   - Copyright：`© 2026 清和日历`
4. **App Privacy**：说明 Contacts / Calendars / Notifications / iCloud 数据用途。
5. **App Review Information**：准备测试账号（含 Contacts 演示数据），以及 iCloud 演示步骤。
6. 等待审核（通常 24-72 小时）。

### 10.6 上架后版本更新

```bash
# 改版本号
PlistBuddy -c "Set :CFBundleShortVersionString 1.2.1" Sources/LunisolarCalendarApp/Info.plist
PlistBuddy -c "Set :CFBundleVersion 12" Sources/LunisolarCalendarApp/Info.plist

# 重新 Archive + 上传
```

---

## 快速参考

| 目标 | 命令 |
| --- | --- |
| 命令行构建 | `swift build` |
| 命令行测试（59 cases） | `swift test` |
| 生成黄历离散库 | `swift run gen_huangli_db Sources/LunisolarCalendarApp/Resources/huangli_db.json` |
| Xcode 打开 | `open Package.swift` |
| iOS Archive | `xcodebuild -scheme LunisolarCalendar -archivePath L.xcarchive -destination 'generic/platform=iOS' -configuration Release archive` |

---

## 常见问题 FAQ

**Q: Xcode 打开 Package.swift 后没有 iOS App target？**
A: SPM 不生成可执行 App target。按 §2 方式 A 创建一个空 SwiftUI App target，加 Package Product 依赖即可。

**Q: 真机 Run 报 "The app identifier cannot be registered"？**
A: Bundle ID 冲突或没有 Team。Signing & Capabilities → Team 选你的付费开发者账号，Bundle Identifier 改一个唯一的（比如 `com.<你的名字>.lunisolar`）。

**Q: Widget Run 了但桌面没有？**
A: 真机长按桌面 → `+` → 搜 "Lunisolar" → 添加。Widget Extension 在 Xcode 里无法单 Run，是宿主 App 装带过去的。

**Q: CloudKit 同步不工作？**
A: 1) 确认 App ID 绑定了 CloudKit；2) 确认 App Group 和 iCloud Container ID 一致；3) 真机设置里 iCloud Drive 已开启；4) 首次登录 Apple ID 后重启 App。

**Q: `swift test` 在 GitHub Actions 上能过吗？**
A: 能。本仓库是 SwiftPM 纯工程，CI 用 `swift test` 即可。CloudKit 走 Mock provider，Linux 环境也能过。

**Q: Info.plist 为什么不在 Package.swift resources 里？**
A: SwiftPM library target 把 Info.plist 当作需要 copy 的资源会告警，且 Xcode App target 会自己生成。所以我们 exclude 它，由宿主 App target 的 Build Settings 引用同一份 plist。

---

*最后更新：2026-09-01 · 对应 commit `449544e`*

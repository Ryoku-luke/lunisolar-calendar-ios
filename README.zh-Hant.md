**语言 / Language：** [简体](README.md) | 繁體 | [English](README.en.md) | [日本語](README.ja.md)

# 清和日曆 · iOS 中國農曆日曆

> 「清和」出自《漢書·郊祀志》「天氣清和，稼穡咸秀」——晴朗溫和、歲月美好。

一款 iOS / iPadOS 日曆應用程式：內建西曆↔農曆轉換、黃曆宜忌、行程/記事/提醒、天氣、倒數日動態島、本機通知、iCloud 同步。介面遵循 iOS 26/27 設計規範（Liquid Glass 液態玻璃 + 節日自適應主題色 + 按壓回饋），支援 iPhone / iPad 自適應版面，相容 iOS 27 / iPadOS 27。

## 功能

| 模組 | 說明 |
|---|---|
| 日曆月檢視 | 7 列標準網格、卡片式左右滑動翻月、「今天」快速跳轉、月份標題點擊選月、日期格長按選單 |
| 年檢視 | 全年 12 個月迷你網格總覽，標示今日 / 事件 / 節氣 / 節日，點擊月份直達 |
| 中國農曆 | 1900–2100 西曆↔農曆轉換、閏月、干支紀年、十二生肖；農曆↔西曆雙向查詢 |
| 黃曆 | 宜/忌、沖煞、五行納音、財神/喜神方位；離散資料庫（2024–2028）+ 演算法兜底 |
| 節氣 / 節日 | 格內文字標示節氣（無需選取即可見）、傳統節日主題色、國務院放假安排（休/班徽章） |
| 天氣 | Open-Meteo 免 Key + 自動定位 + 城市反地理編碼；日期卡片內隨選取日顯示當天天氣 |
| 事件管理 | 行程 / 提醒 / 記事三類，優先級標示，本機通知，重複規則（含**農曆每年**） |
| 倒數日 / 紀念日 | 週年計算（閏月 / 2·29 回退）、**動態島 + 鎖定畫面即時活動**（系統級倒數，零耗電） |
| 資料匯入 | 系統行事曆（EventKit）+ 聯絡人（Contacts）+ .ics/.csv/.json 還原，確定性 UUID 防重複 |
| iCloud 同步 | 真實 CloudKit（私有 DB + Custom Zone + 墓碑 + 增量拉取）+ Mock 測試容器 |
| Widget 小工具 | 今日黃曆概覽 / 農曆日期卡片 / 今日待辦進度，App Group 共享快照，資料變更即時刷新 |
| 多語言 | 簡體中文 / 繁體中文 / 日文 / 英文（含 Widget、動態島全量本地化） |
| 主題 | 深淺色自適應、每週起始日設定、節日自動換圖示（春節限定版） |
| AI 日曆助手 | 本機自然語言解析（「明天下午3點提醒我開會」）→ 預覽 → 一鍵建立行程，不上傳資料 |
| 底部導覽 | iPhone TabBar（日曆 / 黃曆 / AI 助手 / 我的）；iPad 三欄 Sidebar（日曆 / 年檢視 / 倒數日 / 設定） |

## 系統需求

- iOS / iPadOS 17.0+（iOS 26+ 自動啟用 Liquid Glass；iOS 27 / iPadOS 27 已驗證相容）
- Swift 6.0 / Xcode 16.0+（建議 Xcode 27；2027 Q1 起 App Store 送審要求 Xcode 27 建置）

## 執行方式

### Xcode 直接執行（建議）

1. 開啟專案根目錄的 `LunisolarCalendar.xcodeproj`
2. 選擇 **LunisolarCalendar** target → Signing & Capabilities → 選擇你的 Team
3. 主 App 與 Widget 擴充確認勾選同一 App Group（<同一 App Group>）
4. ⌘R 執行（模擬器無需簽名；真機需先在開發者後台設定 Bundle ID 與 Profile）

> 完整簽名 / Capability 指引見 [`docs/XCODE_BUILD_GUIDE.md`](docs/XCODE_BUILD_GUIDE.md) 與 [`docs/ENTITLEMENTS.md`](docs/ENTITLEMENTS.md)。

### 作為 Swift Package 接入

```swift
dependencies: [
    .package(url: "https://github.com/Ryoku-luke/lunisolar-calendar-ios.git", branch: "main")
],
targets: [
    .target(name: "YourApp", dependencies: [
        .product(name: "LunisolarCalendarApp", package: "lunisolar-calendar-ios")
    ])
]
```

```swift
import SwiftUI
import LunisolarCalendarApp

@main
struct YourApp: App {
    var body: some Scene {
        WindowGroup {
            AdaptiveRootView()
                .environment(EventStore.shared)
        }
    }
}
```

### App 圖示

- 圖示來源：`Assets/Assets.xcassets/AppIcon.appiconset/`（四季日曆主圖示）與 `AppIconSpringFestival.appiconset/`（春節限定版）
- 重新產生全部尺寸 PNG：`python3 Tools/gen-icons-flat-blue.py`（需 Pillow）
- 春節窗口自動切換由 `AlternateIconManager.shared.applyTodayIfNeeded()` 處理

### Widget 接入

1. Widget 擴充 target 的 `@main` 使用 `LunisolarWidgetsBundle()`
2. 主 App 與 Widget 擴充勾選同一 App Group（<同一 App Group>）
3. 主 App 啟動時設定 `EventStore.shared.widgetAppGroupID = appGroupID`（HostApp.swift 已接線）
4. 動態島（Live Activity）：主 App 與 Widget 擴充的 Info.plist 均需 `NSSupportsLiveActivities = true`

### iCloud / CloudKit

1. Xcode → 主 App Target → Signing & Capabilities → 加入 iCloud → 勾選 CloudKit
2. 設定頁開啟「iCloud 同步」開關

> 個人免費開發者帳號不支援 iCloud capability（已從 entitlements 移除相關 key，App 內自動降級為「不可用」提示，不影響其他功能）；Linux / SwiftPM 環境使用 MockCloudKitProvider。

## 專案結構

```
LunisolarCalendar.xcodeproj/     # Xcode 宿主專案（僅編譯入口 + 資源，業務程式碼走 SwiftPM）
LunisolarHostApp/                # 主 App 宿主入口（HostApp.swift + entitlements）
LunisolarWidget/                 # Widget 擴充宿主（WidgetMain.swift + Info.plist + entitlements）
Assets/Assets.xcassets/          # App 圖示（主圖示 + 春節限定）
Sources/LunisolarCalendarApp/
├── App/                         # @main 入口 + AdaptiveRootView + 外觀偏好
├── Models/                      # LunarDate（農曆演算法）/ Huangli（黃曆）/ CalendarEvent / CountdownEvent
├── Stores/EventStore.swift      # @Observable + JSON 持久化 + dirty 追蹤 + Widget 快照
├── Support/                     # 設計 Token、天氣、節日/節氣、黃曆庫、通知、匯入橋接、評分引導等
├── Sync/                        # CloudKit 同步（協定 / Mock / 真實 / 協調器）
├── Widgets/                     # 3 種小工具 + 倒數日動態島（Live Activity）
├── Views/                       # 月檢視 / 年檢視 / 日詳情 / 編輯 / 倒數日 / 設定 / 天氣卡
└── Resources/                   # lunar_calendar.json、huangli_db.json、4 套 lproj 本地化
Tools/                           # 黃曆庫產生工具 + 圖示產生腳本
Tests/LunisolarCalendarTests/    # 99 個單元測試
UITests/                         # UI 冒煙測試（3 條）
docs/                            # 上架 / 簽名 / 建置指引
```

## 建置與測試

```bash
swift build        # 編譯所有 Target
swift test         # 執行 99 個單元測試
```

> Linux 環境僅驗證模型層（農曆/黃曆/事件 CRUD/匯入匯出/同步 Mock），SwiftUI 檢視編譯需 iOS/macOS SDK；本倉庫**未設定 CI**（無 `.github/workflows`，推送不會觸發建置）。本機自檢：`swift build` / `swift test`（macOS 宿主，2026-09-24 起可用）與 `swift build --triple arm64-apple-ios17.0-simulator --sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)"`（iOS 檢視層與宿主編譯），詳見 `docs/XCODE_BUILD_GUIDE.md` §4。

## 測試覆蓋（99 條）

| 套件 | 數量 | 覆蓋內容 |
|---|---|---|
| CalendarEventTests | 16 | 事件模型、農曆重複規則、ICS 往返、優先級、節日主色 |
| EventStoreTests | 16 | CRUD、搜尋、合併策略、副本防護、toggleCompleted 通知重排 |
| ICloudSyncTests | 11 | 推送/拉取/衝突/增量/離線上線/墓碑傳播 |
| SystemImportTests | 9 | DTO 對應、確定性 UUID、聚合、端到端無副本 |
| DataPortabilityTests | 8 | JSON/ICS 往返、偽 UUID 穩定性、合併統計 |
| HuangliDBProviderTests | 6 | 離散庫命中、邊界 fallback、DB↔演算法一致性 |
| LunarDateTests | 5 | 農曆真值點、閏月、邊界 nil 安全、反向轉換 |
| NotificationLunarAnniversaryTests | 5 | 農曆週年提醒邊界、閏月回退/匹配 |
| HolidayProviderTests | 7 | 2025/2026 官方放假安排錨點、調休補班 |
| CountdownEventTests | 7 | 紀念日週年（今年/跨年/2·29 回退）、倒數日文案 |
| WidgetSnapshotTests | 4 | 快照讀寫、過期偵測、自動寫入 |
| AccessibilityIDTests | 3 | 無障礙標識目錄一致性 |
| HuangliTests | 2 | 宜忌穩定性、沖煞驗證 |

## 設定說明

### 黃曆資料策略（產品決策）

1. **目前口徑**：2024-01-01 ~ 2028-12-31 使用人工核驗的離散庫（`huangli_db.json`）；此範圍外（含 2029 起）走演算法兜底，保證不空窗。
2. **一致性風險**：演算法與離散庫在個別日子的宜忌措辭可能有差異；設定頁已展示資料覆蓋說明。
3. **擴展庫**：如需 2029+ 與庫一致，執行 `swift run gen_huangli_db` 擴展 JSON 並按 `HuangliDBProviderTests` 方式抽驗後合入。

### 多語言接線（已內建）

- 4 套 `lproj`（zh-Hans / zh-Hant / ja / en）已註冊進主 App 與 Widget 兩個 target 的 Resources phase
- 新增語言：複製任一 `lproj` 並翻譯鍵值即可，無需改程式碼

### UI 測試

- 新建 **UI Testing Bundle** target（命名 `LunisolarCalendarUITests`），Target Application 選 LunisolarCalendar
- 將 `UITests/LunisolarCalendarUITests.swift` 加入該 target，Cmd+U 執行 3 條冒煙測試

## 發布清單（Release Checklist）

- [ ] `CFBundleShortVersionString` / `CFBundleVersion` 已遞增（目前 `MARKETING_VERSION = 1.0.1`）
- [ ] Xcode → Product → Archive 成功（無 codesign 錯誤）
- [ ] 主 App + Widget 擴充均勾選同一 App Group（<同一 App Group>）
- [ ] iCloud Capability 已啟用，CloudKit Container ID 已設定（付費帳號）
- [ ] 隱私權限文案（定位 / 通訊錄 / 行事曆）已審核
- [ ] App Icon 1024×1024 無透明通道（App Store 要求）
- [ ] 春節限定備用圖示宣告完整
- [ ] 真機測試：通知 → 提醒鎖定畫面彈窗；iCloud 多裝置一致性；Widget 快照刷新；動態島上下島
- [ ] 隱私清單（Privacy Manifest）已宣告
- [ ] App Store Connect：截圖、描述、關鍵字、隱私標籤已填寫

詳見 [`docs/APP_STORE.md`](docs/APP_STORE.md)、[`docs/ENTITLEMENTS.md`](docs/ENTITLEMENTS.md) 與 [`docs/XCODE_BUILD_GUIDE.md`](docs/XCODE_BUILD_GUIDE.md)。

## 已修復的關鍵問題

累計修復 56+ 個 BUG，涵蓋資料安全、並發競態、CloudKit API 相容、日曆一致性、Swift 6 並發隔離、UI 觸碰區等，關鍵方向：

- **資料安全**：損壞資料不再覆蓋使用者資料；dirty 標記持久化防重啟遺失；越界日期不再顯示「假農曆」
- **並發安全**：推送佇列序列化、同步防重入、`@MainActor` 隔離協調器、Swift 6 region-based 檢查合規
- **日曆一致性**：全模組統一 `.gregorian`，避免非西曆系統環境錯亂；農曆週年/閏月邊界正確
- **平台適配**：iOS 26/27 Liquid Glass 原生化、Live Activity 新 API、CloudKit 棄用 API 遷移
- **UI/效能**：全部互動元素 ≥ 44pt 觸碰區、月曆渲染 O(1) 快取、靜態 `Calendar.gregorian` 高頻路徑最佳化

## License

MIT

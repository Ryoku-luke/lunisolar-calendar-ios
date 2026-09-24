**言語 / Language：** [简体](README.md) | [繁體](README.zh-Hant.md) | [English](README.en.md) | 日本語

# 清和カレンダー · iOS 旧暦カレンダー

> 「清和」は『漢書』郊祀志の「天氣清和、稼穡咸秀」（天気は清らかに和やかで、作物はみごとに実る）に由来し、晴れやかで穏やかな、佳き日々を表します。

iOS / iPadOS 向けカレンダーアプリです。西暦⇔旧暦変換、暦注（宜・忌）、予定/メモ/リマインダー、天気、カウントダウンの Dynamic Island、ローカル通知、iCloud 同期を内蔵。UI は iOS 26/27 のデザイン言語（Liquid Glass + 祝日連動アクセントカラー + 押下フィードバック）に準拠し、iPhone / iPad のアダプティブレイアウトに対応、iOS 27 / iPadOS 27 での動作を検証済みです。

## 機能

| モジュール | 説明 |
|---|---|
| 月表示 | 7 列グリッド、カード式スワイプで月送り、「今日」ボタン、月タイトルタップで月選択、日付セル長押しメニュー |
| 年表示 | 12 か月分のミニグリッドを一覧表示。今日 / イベント / 二十四節気 / 祝日をマークし、月タップでジャンプ |
| 旧暦 | 1900–2100 の西暦⇔旧暦変換、閏月、十干十二支、十二支；旧暦⇔西暦の双方向検索 |
| 暦注（黄暦） | 宜・忌、沖煞（相克）、五行納音、財神/喜神の方角；離散 DB（2024–2028）+ アルゴリズム補完 |
| 二十四節気 / 祝日 | セル内に節気名を直接表示（選択不要）、伝統祝日のアクセントカラー、国務院の祝日スケジュール（休/班バッジ） |
| 天気 | Open-Meteo（キー不要）+ 自動位置情報 + 逆ジオコーディング。選択日の天気を日付カード内に表示 |
| イベント管理 | 予定 / リマインダー / メモの 3 タイプ、優先度タグ、ローカル通知、繰り返し（**旧暦・毎年** 対応） |
| カウントダウン / 記念日 | 周年計算（閏月 / 2月29日フォールバック）、**Dynamic Island + ロック画面の Live Activity**（システム駆動のタイマー、バッテリー消費ゼロ） |
| データ取り込み | システムカレンダー（EventKit）+ 連絡先（Contacts）+ .ics/.csv/.json 復元、決定論的 UUID で重複防止 |
| iCloud 同期 | 実 CloudKit（プライベート DB + Custom Zone + トゥームストーン + 差分取得）+ Mock テストコンテナ |
| Widget | 今日の暦注 / 旧暦日付カード / 今日のタスク進捗。App Group でスナップショット共有、データ変更で即時更新 |
| 多言語 | 簡体字中国語 / 繁体字中国語 / 日本語 / 英語（Widget・Dynamic Island も全量ローカライズ） |
| テーマ | ライト/ダーク自動適応、週の開始日設定、祝日に応じたアイコン自動切替（春節限定版） |
| AI アシスタント | オンデバイス自然言語解析（「明日午後3時に電話のリマインド」）→ プレビュー → ワンタップ登録、クラウド送信なし |
| ナビゲーション | iPhone タブバー（カレンダー / 暦 / マイ）、iPad 3ペイン Sidebar（カレンダー / 年表示 / カウントダウン / 設定） |

## システム要件

- iOS / iPadOS 17.0+（iOS 26+ で Liquid Glass 自動有効化、iOS 27 / iPadOS 27 対応検証済み）
- Swift 6.0 / Xcode 16.0+（Xcode 27 推奨。2027 Q1 以降 App Store 提出には Xcode 27 ビルドが必要）

## 実行方法

### Xcode で直接実行（推奨）

1. リポジトリ直下の `LunisolarCalendar.xcodeproj` を開く
2. **LunisolarCalendar** ターゲット → Signing & Capabilities → Team を選択
3. メインアプリと Widget 拡張で同じ App Group（<同一 App Group>）を選択していることを確認
4. ⌘R で実行（シミュレータは署名不要。実機は Developer Portal で Bundle ID とプロファイルを先に設定）

> 署名・Capability の詳細は [`docs/XCODE_BUILD_GUIDE.md`](docs/XCODE_BUILD_GUIDE.md) と [`docs/ENTITLEMENTS.md`](docs/ENTITLEMENTS.md) を参照。

### Swift Package として組み込む

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

### App アイコン

- アイコンソース：`Assets/Assets.xcassets/AppIcon.appiconset/`（四季カレンダー版）+ `AppIconSpringFestival.appiconset/`（春節限定版）
- 全サイズ PNG の再生成：`python3 Tools/gen-icons-flat-blue.py`（Pillow が必要）
- 春節期間の自動切替は `AlternateIconManager.shared.applyTodayIfNeeded()` が処理

### Widget の組み込み

1. Widget 拡張ターゲットの `@main` に `LunisolarWidgetsBundle()` を使用
2. メインアプリと Widget 拡張で同じ App Group（<同一 App Group>）を選択
3. メインアプリ起動時に `EventStore.shared.widgetAppGroupID = appGroupID` を設定（HostApp.swift で配線済み）
4. Dynamic Island（Live Activity）：メインアプリと Widget 拡張の両方の Info.plist に `NSSupportsLiveActivities = true` が必要

### iCloud / CloudKit

1. Xcode → メインアプリターゲット → Signing & Capabilities → iCloud 追加 → CloudKit にチェック
2. 設定画面で「iCloud 同期」をオン

> 個人無料の開発者アカウントは iCloud capability をサポートしていません（entitlements から関連キーを削除済み。アプリ内では「利用不可」表示に自動フォールバックし、他の機能には影響なし）。Linux / SwiftPM 環境では MockCloudKitProvider を使用します。

## プロジェクト構成

```
LunisolarCalendar.xcodeproj/     # Xcode ホストプロジェクト（エントリポイント + リソースのみ。業務コードは SwiftPM）
LunisolarHostApp/                # メインアプリのホストエントリ（HostApp.swift + entitlements）
LunisolarWidget/                 # Widget 拡張のホスト（WidgetMain.swift + Info.plist + entitlements）
Assets/Assets.xcassets/          # App アイコン（通常版 + 春節限定）
Sources/LunisolarCalendarApp/
├── App/                         # @main エントリ + AdaptiveRootView + 外観設定
├── Models/                      # LunarDate（旧暦アルゴリズム）/ Huangli（暦注）/ CalendarEvent / CountdownEvent
├── Stores/EventStore.swift      # @Observable + JSON 永続化 + dirty 追跡 + Widget スナップショット
├── Support/                     # デザイントークン、天気、祝日/節気、暦注 DB、通知、インポートブリッジ、評価案内など
├── Sync/                        # CloudKit 同期（プロトコル / Mock / 実装 / コーディネータ）
├── Widgets/                     # 3 種のウィジェット + カウントダウン Live Activity
├── Views/                       # 月表示 / 年表示 / 日詳細 / 編集 / カウントダウン / 設定 / 天気カード
└── Resources/                   # lunar_calendar.json、huangli_db.json、4 言語の lproj
Tools/                           # 暦注 DB 生成ツール + アイコン生成スクリプト
Tests/LunisolarCalendarTests/    # 99 件のユニットテスト
UITests/                         # UI スモークテスト（3 件）
docs/                            # App Store / 署名 / ビルドガイド
```

## ビルドとテスト

```bash
swift build        # 全ターゲットをビルド
swift test         # 99 件のユニットテストを実行
```

> Linux ではモデル層のみ検証します（旧暦/暦注/イベント CRUD/インポート・エクスポート/同期 Mock）。SwiftUI ビューのコンパイルには iOS/macOS SDK が必要です。本リポジトリは **CI 未設定**（`.github/workflows` なし。push してもビルドは走りません）。ローカル検証は `swift build` / `swift test`（macOS ホスト、2026-09-24 以降利用可）と `swift build --triple arm64-apple-ios17.0-simulator --sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)"`（iOS ビュー層＋ホスト）— 詳細は `docs/XCODE_BUILD_GUIDE.md` §4。

## テストカバレッジ（99 件）

| スイート | 件数 | 対象 |
|---|---|---|
| CalendarEventTests | 16 | イベントモデル、旧暦繰り返し、ICS 往復、優先度、祝日カラー |
| EventStoreTests | 16 | CRUD、検索、マージ戦略、重複防止、toggleCompleted の通知再スケジュール |
| ICloudSyncTests | 11 | push/pull/競合/差分/オフライン復帰/トゥームストーン伝播 |
| SystemImportTests | 9 | DTO マッピング、決定論的 UUID、集約、重複なしの E2E |
| DataPortabilityTests | 8 | JSON/ICS 往復、擬似 UUID 安定性、マージ統計 |
| HuangliDBProviderTests | 6 | DB ヒット、境界フォールバック、DB↔アルゴリズム整合性 |
| LunarDateTests | 5 | 旧暦の真値、閏月、境界 nil 安全、逆変換 |
| NotificationLunarAnniversaryTests | 5 | 旧暦周年の境界、閏月フォールバック/一致 |
| HolidayProviderTests | 7 | 2025/2026 公式祝日アンカー、振替出勤 |
| CountdownEventTests | 7 | 記念日周年（今年/年またぎ/2月29日フォールバック）、カウントダウン文案 |
| WidgetSnapshotTests | 4 | スナップショット読み書き、期限切れ検出、自動書き込み |
| AccessibilityIDTests | 3 | アクセシビリティ識別子の一貫性 |
| HuangliTests | 2 | 宜・忌の安定性、沖煞の検証 |

## 設定メモ

### 暦注データ戦略（プロダクト決定）

1. **現行方針**：2024-01-01 〜 2028-12-31 は人手で検証済みの離散 DB（`huangli_db.json`）を使用。この範囲外（2029 以降を含む）はアルゴリズム補完に切り替わり、空になることはありません。
2. **整合性リスク**：アルゴリズムと離散 DB では日によって宜・忌の表現が異なる可能性があります。設定画面にデータ適用範囲の説明を表示済みです。
3. **DB 拡張**：2029 以降も DB と一致させたい場合は `swift run gen_huangli_db` で JSON を拡張し、`HuangliDBProviderTests` 方式で検証してからマージしてください。

### ローカライズ（組み込み済み）

- 4 言語の `lproj`（zh-Hans / zh-Hant / ja / en）はメインアプリと Widget の両ターゲットの Resources phase に登録済み
- 言語追加：任意の `lproj` をコピーしてキーと値を翻訳するだけ。コード変更は不要

### UI テスト

- **UI Testing Bundle** ターゲット（名前：`LunisolarCalendarUITests`）を作成し、Target Application を LunisolarCalendar に設定
- `UITests/LunisolarCalendarUITests.swift` をターゲットに追加し、Cmd+U でスモークテスト 3 件を実行

## リリースチェックリスト

- [ ] `CFBundleShortVersionString` / `CFBundleVersion` を更新済み（現在 `MARKETING_VERSION = 1.0.1`）
- [ ] Xcode → Product → Archive 成功（codesign エラーなし）
- [ ] メインアプリ + Widget 拡張で同じ App Group（<同一 App Group>）を選択
- [ ] iCloud capability 有効化、CloudKit Container ID 設定済み（有料アカウント）
- [ ] プライバシー権限文言（位置情報 / 連絡先 / カレンダー）を確認
- [ ] App Icon 1024×1024 に透明チャンネルなし（App Store 要件）
- [ ] 春節限定代替アイコンの宣言が完全
- [ ] 実機テスト：通知 → リマインダーのロック画面表示；iCloud マルチデバイス整合性；Widget スナップショット更新；Dynamic Island のオン/オフ
- [ ] Privacy Manifest を宣言済み
- [ ] App Store Connect：スクリーンショット、説明、キーワード、プライバシーラベルを記入済み

詳細は [`docs/APP_STORE.md`](docs/APP_STORE.md)、[`docs/ENTITLEMENTS.md`](docs/ENTITLEMENTS.md)、[`docs/XCODE_BUILD_GUIDE.md`](docs/XCODE_BUILD_GUIDE.md) を参照。

## 修正済みの主要課題

累計 56+ 件のバグを修正。データ安全性、並行処理の競合、CloudKit API 互換、カレンダー整合性、Swift 6 並行性分離、UI タッチ領域などをカバーしています。

- **データ安全性**：破損データがユーザーデータを上書きしないよう保護。dirty マーカーを永続化して再起動時の消失を防止。範囲外日付で「偽の旧暦」を表示しない
- **並行処理**：プッシュキューの直列化、再入防止、`@MainActor` 分離コーディネータ、Swift 6 region-based checker 準拠
- **カレンダー整合性**：全モジュールで `.gregorian` を統一し、非西暦環境での表示ズレを防止。旧暦周年・閏月の境界を正確に処理
- **プラットフォーム対応**：iOS 26/27 の Liquid Glass ネイティブ化、Live Activity 新 API、CloudKit 非推奨 API の移行
- **UI/パフォーマンス**：全操作要素のタッチ領域 44pt 以上、月グリッド描画の O(1) キャッシュ、高頻度パスでの静的 `Calendar.gregorian`

## ライセンス

MIT

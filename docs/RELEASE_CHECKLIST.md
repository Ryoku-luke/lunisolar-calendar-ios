# 发布前自检清单（Release）

> 目的：把散在 `APP_STORE.md` / `ENTITLEMENTS.md` / `XCODE_BUILD_GUIDE.md` 里的知识
> 收成一份**可逐项打勾**的清单，并标出哪些项**已经自动化**（✅）与哪些**必须人工**（⬜）。
> 细节不在这里重复，每一项都指向原文档。

## 0. 自动化门（本地可跑，✅ = 本清单编写时实测通过）

| # | 命令 | 期望 | 说明 |
|---|---|---|---|
| 0.1 | `swift build -c release --disable-sandbox` | Build complete，0 error / 0 真实 warning | 首次在本项目上验证 Release 配置（2026-10-18）✅ |
| 0.2 | `swift test -c release --disable-sandbox` | `Executed 463 tests, with 0 failures` | Release 优化下的全量单测 ✅ |
| 0.3 | `swift test --disable-sandbox`（默认 Debug） | 同上 | 日常门 ✅ |
| 0.4 | `Tools/run_tests.sh`（沙箱下加 `SWIFT_EXTRA_ARGS=--disable-sandbox`） | 五通道全绿 | 含 iOS SDK 构建与 UI 通道 |
| 0.5 | `xcode_build action=build configuration=Release destination=generic/platform=iOS scheme=LunisolarCalendar` | **BUILD SUCCEEDED**，0 error / 0 warning | 会走 CodeSign + 小组件 `ValidateEmbeddedBinary` + `-validate-for-store` ✅ |
| 0.6 | `swift test --disable-sandbox --filter DataExpiryTests` | 通过（无"即将到期"告警） | **发布门**：内置数据到期是**静默降级**，用户只会发现功能不对 |

> ⚠️ 0.6 的含义：放假安排可信到 **2027-01-01**，告警从 **2026-12-02** 起。
> 若在该日期之后发版而数据未更新，用户看到的放假/调休会**整体消失且无报错**。
> 流程见 `DATA_UPDATE_RUNBOOK.md`。

## 1. 版本与构建号 ⬜

- 位置：Xcode target 的 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`（当前 **1.0.1 / 1**）。
- 规则：**每次上传 App Store Connect 都必须递增 `CURRENT_PROJECT_VERSION`**（同一构建号不能复用）。
- 详见 `APP_STORE.md` §一.1。

## 2. 图标与截图 ⬜

- 图标：`APP_STORE.md` §一.2（生成脚本见 `Tools/gen-icons-flat-blue.py`）。
- 截图：`APP_STORE.md` §一.3；**多语言截图可用 `Tools/shots.sh --tour --lang <en|ja|zh-Hant>`** 批量出图。
  （该巡游由 `TEST_RUNNER_SHOTS=1` 开启，普通 UI 用例不会跑它。）

## 3. Archive → 验证 → 上传 ⬜

- 步骤见 `APP_STORE.md` §二（Archive / 验证 / 上传到 App Store Connect）。
- **本清单 0.5 已在本地验证过同样的 Release 构建链**，但它不等同于 Archive（签名类型不同）。

## 4. App Store Connect 配置 ⬜

- App 信息、**隐私标签（Privacy Labels）**、关键词、描述：`APP_STORE.md` §三。
- 隐私标签必须与 `ENTITLEMENTS.md` §五（隐私清单）**口径一致**。

## 5. 权限 / Entitlements / Privacy Manifest ⬜→✅

- Capability 与两个 entitlements 文件：`ENTITLEMENTS.md` §一、§二。
- Info.plist 隐私权限文案：§三；CloudKit Container：§四；Privacy Manifest：§五。
- **验证清单**：`ENTITLEMENTS.md` §六（逐项人工核对）。
- 本次 Release 构建已确认小组件嵌入能被系统校验通过（`ValidateEmbeddedBinary`）✅。

## 6. 真机走查 ⬜

- 基础清单：`APP_STORE.md` §六、`DEVICE_TEST_CHECKLIST.md`。
- 本会话补充的三条**易漏项**（都是真实踩过的坑）：
  1. **键盘遮挡**：AI 助手创建日程后焦点回到输入框、键盘弹起会盖住底部 Tab；
  2. **大字号**：把系统文字调到最大，确认日历格与今日安排仍可读可点；
  3. **灵动岛/小组件**：倒数日上岛后再下岛、以及小组件在多尺寸下的内容。

## 7. 审核与发布 ⬜

- 审核要点、可能被拒的点、版本发布与**热修流程**：`APP_STORE.md` §四、§五。

---

**使用方法**：每次发版复制这一份，按 0 → 7 顺序执行；任何一项不通过就**不要上传**。
需要长期维护的只有：0.6 的数据到期日期、1 的版本号现状、以及真机走查里新增的坑。

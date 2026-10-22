# 折叠屏适配方案（2026-10-22 评估稿，未实施）

## 0. 设备事实（2026-10-22 依 Apple 官网核实，**已修订**）

> ⚠️ 本方案第一版曾断言"Apple 未发布折叠屏 iPhone、Duo 是微软设备" —— **这是事实错误**，
> 已于同日用官网页面（https://www.apple.com.cn/iphone-duo/ ，HTTP 200）核实推翻。
> 教训与本会话反复得到的一致：**未核实的外部事实不能当结论**。

**iPhone Duo 已确认规格（官网）**

| 项 | 值 | 对适配的含义 |
|---|---|---|
| **外屏** | 5.4 英寸超视网膜 XDR | 宽度约 **320–340 pt**，**比现款 iPhone 更窄** ✗ |
| **内屏** | 7.6 英寸可折叠超视网膜 XDR（纳米纹理、屏下 FaceTime 摄像头）| 宽度约 **740–820 pt** → 分栏 |
| 内外屏比例 | 保持一致 | 同一套布局可两屏复用 |
| 系统 | iOS 27 | 可能有新 API，但**方案不依赖未知 API** |
| 发售 | 2026-10-23 | 适配应**先于**发售就绪 |
| 相机 | 4800 万双摄 + "Duo 双屏预览" | 与本 App 无关 |

### 0.1 对方案的修订（基于真实规格）

1. **多一档"narrow"**：原方案只有 compact(<500)/medium/expanded → 现在 **compact 内部还要细分**：
   **narrow（≤350 pt，外屏）** 与 **compact（350–500 pt，现款 iPhone）**。
   理由：7 列网格 × 44 pt = **308 pt**，在 320 pt 外屏上**只剩 12 pt 余量**；
   年视图那种 7 列小格会掉到 **<44 pt**（HIG 违约）。
2. **内屏无灵动岛** ✗：Live Activity（倒数日"上岛"）在内屏的呈现需**实测**，
   文案与交互可能要区分"有岛/无岛"。
3. **测试优先级上调** ✗→✓：现有 UI 套件按 `userInterfaceIdiom == .phone` 走 iPhone 分支，
   在 5.4" 外屏（≈320 pt）下很可能**直接红**；"注入 tier 的测试"（原 P4）
   因此**从可选升为 P0 之后的第一步**。
4. **内屏分栏可复用 iPad 路径** ✓：7.6" ≈ iPad mini 宽度，`NavigationSplitView`（已有 6 处）可直接复用。

## 1. 现状盘点（实测数据）

**已经做对的（无需重做）**
- **没有 `UIScreen.main`**（0 处）—— 躲过了折叠屏最经典的错误（用屏幕尺寸代替容器尺寸）；
- 形态判定**集中**在 `Support/LayoutIdiom.swift`（6 处引用），有改造支点；
- 已有 `NavigationSplitView`（6 处）、`horizontalSizeClass`（15 处）、`GeometryReader`（11 处）；
- 命中区有 44 pt 契约（`AppTheme.Touch`），格子最小高度有兜底。

**必须改的（按风险排序）**

| # | 问题 | 证据 | 为何是折叠屏的硬伤 |
|---|---|---|---|
| 1 | **`isIPadSplit` 布尔贯穿 17 处** | `CalendarMonthColumn` / `MonthGridMetrics` 等 | 布尔只能表达两种形态；折叠屏有**三档以上**宽度 |
| 2 | **弹性行高仅对 iPad 生效** | `MonthGridMetrics.elasticCellHeight(... isIPadSplit:)` | 折叠态**横屏**（compact 高度）时行高不收缩 → 内容溢出 |
| 3 | **`QingheUIComponents:150` 直接判 idiom** | 未走 `LayoutIdiom` | 折叠机 idiom 可能为 `.phone`，但布局应为宽屏 |
| 4 | **UI 测试用 `userInterfaceIdiom` 分支 20 处** | `LunisolarCalendarUITests` | 折叠机走错分支 → 宽屏布局**完全没有测试覆盖** |
| 5 | **未声明多窗口** | `UIApplicationSupportsMultipleScenes` 缺失 | 双屏/Stage Manager 场景不可用 |
| 6 | 缺 `verticalSizeClass` / `ViewThatFits` / `AnyLayout` | 各 0 处 | 宽而矮（横屏折叠）时缺布局手段 |

## 2. 目标判据（唯一形态来源）

引入**布局分级**，取代布尔与 idiom：

```swift
enum LayoutTier { case compact, medium, expanded }   // 阈值：<500 / 500–740 / ≥740 pt

@MainActor enum LayoutIdiom {
    static func tier(width: CGFloat, hSize: UserInterfaceSizeClass?) -> LayoutTier
}
```

规则：
- **宽度**是主判据（`GeometryReader` 的容器宽度，**不是**屏幕宽度）；
- `horizontalSizeClass` 用作**兜底与语义**（例如是否允许分栏）；
- `userInterfaceIdiom` **只保留**在"必须区分设备能力"的极少数处（当前 1 处泄漏应收口，
  若确需保留，需写明理由）；
- **禁止**在视图 `init`/`@State` 初值里锁定 tier（折叠会产生**运行时变化**）。

## 3. 分阶段方案

### P0 地基（0.5 天，必做）
1. 新增 `LayoutTier` + `LayoutIdiom.tier(...)`；把 `isIPadSplit` 的 17 处**按语义**替换：
   - 只关心"是否分栏"的 → `tier != .compact`
   - 关心"宽度够不够"的 → 直接比较容器宽度
2. `QingheUIComponents:150` 收口到 `LayoutIdiom`；
3. 全仓禁止 `UIDevice.current.userInterfaceIdiom`（加一条**静态门测试**，与 `hardcoded-font-gate` 同风格）。

### P1 布局分级（1–2 天，收益最大）
| 界面 | compact（<500） | medium（500–740） | expanded（≥740） |
|---|---|---|---|
| 日历网格 | 7 列，最小 44 pt | 7 列 + **弹性行高** | 7 列 + 弹性行高 + 更大留白 |
| 今日安排 | 单列滚动 | 单列（更宽） | 单列 + 最大宽度约束（避免超长行） |
| 日详情 | 单列 | 单列/两栏（`ViewThatFits`） | 两栏（信息 + 宜忌） |
| AI 助手 | 单栏 | 单栏 | **输入/结果两栏** |
| 倒数日 | 列表 | 列表 | 列表 + 详情（`NavigationSplitView`） |
| 设置 | 单列 | 单列 + 最大宽度 | 单列 + 最大宽度 + 居中 |
| 导航容器 | `TabView` | `NavigationSplitView`（两栏） | `NavigationSplitView`（两栏/三栏） |

关键动作：**把 `elasticCellHeight` 的 iPad 门控去掉**，改为"只要高度紧张就用"（`verticalSizeClass == .compact`
或 `tier != .compact` 且 7 行放不下）。

### P2 运行时 trait 变化（0.5 天）
- 审计所有"appear 时锁死布局"的写法（`@State` 用几何初始化、`isIPadSplit` 参与 `init`）；
- 用 `@Environment(\.horizontalSizeClass)` + `onChange(of:)` 或在 `body` 里**即时计算**；
- 横屏折叠（宽而矮）用 `ViewThatFits` 或 `verticalSizeClass` 降低行高；
- **测试**：模拟"展开→合起"（模拟器上可用 iPad Stage Manager 缩放窗口 + 旋转近似）。

### P3 多窗口 / 双屏（1 天）
- `Info.plist` 增加 `UIApplicationSupportsMultipleScenes`；
- **状态隔离**：当前 `EventStore.shared` 等是单例 → 多窗口共享同一实例。
  单窗口没问题，但多场景下需明确：共享（当前行为，简单）还是每场景独立（需改造；
  单例下**不要**在窗口间复制 UI 状态，避免不一致）。

### P4 测试与验收（1 天）
- **UI 测试去 idiom 化**：20 处 `userInterfaceIdiom` 改为**启动参数注入 tier**
  （如 `-uitest-layout-tier=expanded`），并对三档各跑一遍核心路径；
- 截图：`Tools/shots.sh` 增加 **宽度驱动的三档**（而非机型驱动）；
- 静态门：禁止 `UIScreen.main`（已是 0 ✓，加门防回归）、禁止裸 `userInterfaceIdiom`；
- 验收清单：三档 × 明暗 × 最大字号（`testFlow20` 已覆盖一档，扩展为三档）。

## 4. 为什么这个方案最省

- **项目已在 iPad 上验证过宽屏布局**（`NavigationSplitView` 6 处、侧栏、弹性行高）——
  折叠屏的"展开态"本质就是**iPad 布局的窄版**，所以 P1 主要是**复用而非新写**；
- **改动集中在判定层**（P0）+ **少量布局分支**（P1），不触碰数据层与业务逻辑；
- **测试可先于实现就绪**（注入 tier），使"折叠"成为**可自动化**的维度，而不是等真机。

## 5. 明确不做（避免投机）

- 不针对未发布设备写代码（无 SDK、无规格）；
- 不使用私有 API；不猜测铰链/折痕的 safe area 行为；
- 不为"双屏"做特殊分屏 UI（系统会把它表现为普通多窗口）；
- 不引入 `UIScreen.main`（当前 0 处，保持）。

## 6. 风险与未知

| 风险 | 说明 | 缓解 |
|---|---|---|
| 设备规格未知 | 铰链是否暴露 safe area、折叠时的尺寸类别如何变化 | 只依赖**容器宽度**与**尺寸类别**，两者在任何实现下都成立 |
| 单例状态与多窗口 | `EventStore.shared` 等跨窗口共享 | 先明确产品口径；必要时再改造为每场景实例 |
| 三档引入的布局分支 | 组合爆炸（3 档 × 2 方向 × 字号） | 用**注入 tier 的 UI 测试**覆盖核心路径，其余靠 `ViewThatFits` 自愈 |

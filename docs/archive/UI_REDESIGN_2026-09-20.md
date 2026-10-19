# 清和日历 UI 2.0 实装记录

本轮根据用户提供的 iPhone / iPad / Settings 参考图，对现有 SwiftUI UI 做实际代码调整。

## iPhone

- 底部 Tab 从 3 项扩展为 4 项：日历 / 黄历 / AI 助手 / 我的。
- AI 入口从大横幅改成轻量胶囊，降低对月历主视觉的干扰。
- 月历卡片采用更克制的浅色分组背景、24pt 圆角和轻边框。
- 日期格在 iPhone 使用更紧凑的 3pt 行间距，保留农历、节气、节日和事件点。
- 今日详情卡进一步收紧内边距和圆角，减少滚动长度。
- 主操作继续使用系统导航栏 + 新建日程，避免重复 FAB。

## 设置

- 设置页增加品牌 Hero Card：应用标识、事件数量、农历支持范围、AI 助手入口。
- 设置分组标题增加副说明：外观、提醒与时间胶囊、数据与同步、iCloud。
- 将“提醒通知”更名为“提醒与时间胶囊”，让 Live Activity 成为用户可理解的产品功能。
- 保留现有导入、iCloud、冲突策略、危险操作和文档入口，避免 UI 重构破坏业务功能。

## iPad

- 保留 NavigationSplitView 三栏信息架构。
- 中栏继续承载月历/年视图/倒数日/设置。
- 右栏保持当日详情。
- 月历卡片在 regular size class 使用更宽松的 6pt 网格间距和更大的可读性。
- iPad 不模拟 Dynamic Island；Live Activity 继续由系统在支持的位置展示。

## 验证

`swift build --disable-sandbox` 已通过。

当前 Package 仍存在既有的 56 个 unhandled file/resource 警告，这是项目 SPM target 资源/源码边界问题，不影响本轮 Swift 源码编译；建议下一轮单独清理 Package.swift 与 Xcode target membership。

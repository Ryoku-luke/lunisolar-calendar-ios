#if canImport(SwiftUI)
import SwiftUI

// MARK: - 文档 Sheet（隐私政策 / 用户协议 / 帮助说明 / 意见反馈）

enum DocKind: String, CaseIterable, Identifiable {
    case help, feedback, privacy, agreement
    var id: String { rawValue }

    var title: String {
        switch self {
        case .help: return "帮助与说明"
        case .feedback: return "意见反馈"
        case .privacy: return "隐私政策"
        case .agreement: return "用户协议"
        }
    }

    /// 文档正文（本地静态文本，随版本更新）
    var body: LocalizedStringKey {
        switch self {
        case .help:
            return """
            ## 快速上手

            **月历操作**
            - 左右滑动切换月份
            - 点击日期查看当日详情（宜忌/节气/生肖）
            - 点底部「今天」按钮快速回到本月

            **日程管理**
            - 点「＋ 新建日程」添加事件
            - 支持重复规则、提醒、优先级
            - 长按日程可删除

            **倒数日**
            - 在侧边栏或菜单进入「倒数日」
            - 自动计算距目标日期天数
            - 添加后自动上岛（灵动岛）

            **天气**
            - 首次使用请求定位权限
            - 未授权时显示默认城市天气
            - 每小时自动刷新
            """
        case .feedback:
            return """
            感谢使用清和日历。

            如有问题、建议或功能需求，欢迎通过以下方式反馈：

            - **邮件**：support@qinghe.calendar
            - 反馈时请附带：设备型号、iOS 版本、问题描述

            我们会在 1-3 个工作日内回复。
            """
        case .privacy:
            return """
            清和日历重视用户隐私。

            **数据存储**
            - 所有日程、倒数日数据仅保存在你的设备本地
            - 开启 iCloud 同步后，数据通过 Apple iCloud 私有云同步，我们无法读取
            - 天气功能使用免费 Open-Meteo API，仅发送位置坐标用于天气查询

            **权限使用**
            - 定位：用于显示当地天气
            - 通知：用于日程/节气提醒
            - 日历/联系人：仅用于导入已有日程和生日，不会上传

            **数据删除**
            - 在「设置 → 删除所有数据」可一键清除全部本地数据

            本政策最后更新：2026 年 9 月
            """
        case .agreement:
            return """
            欢迎使用清和日历。

            **服务说明**
            - 本软件按"现状"提供，农历/节气数据基于公开天文算法计算
            - 黄历宜忌内容仅供参考，不构成任何决策建议

            **免责声明**
            - 因使用本软件产生的任何直接或间接损失，开发者不承担责任
            - 农历/节气计算如遇极端日期（1900 前/2100 后）不支持

            **使用规范**
            - 不得用于任何非法用途
            - 不得逆向工程或试图提取核心算法

            继续使用即视为同意本协议。
            """
        }
    }
}

struct DocSheetView: View {
    let kind: DocKind
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(kind.body)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle(kind.title)
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    DocSheetView(kind: .privacy)
}
#endif

import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(StoreKit)
import StoreKit
#endif

// MARK: - App Store 评分引导
//
// 目标：在用户完成"有意义操作"（保存日程 / 标记待办完成）累计达到阈值后，
// 通过系统原生评分弹窗（SKStoreReviewController）邀请评分——
// 这是提升 App Store 评分数量的标准手段，评分数与评分均值共同影响商店排名。
//
// 防打扰策略：
// 1. 阈值：累计 5 次有意义操作才首次请求（避免新用户一进来就弹窗）；
// 2. 冷却：两次请求之间至少间隔 90 天（Apple 也限制每年最多约 3 次自动弹窗）；
// 3. 请求后计数清零，进入下一轮累计。
@MainActor
enum RatingPromptCoordinator {
    private static let countKey = "rating.meaningfulActions"
    private static let lastPromptKey = "rating.lastPromptAt"
    private static let threshold = 5
    private static let cooldown: TimeInterval = 90 * 24 * 3600

    /// 用户在完成一个"有意义操作"后调用（保存日程 / 勾选完成待办）。
    /// 幂等：并发/重复调用只累计计数，达到阈值且冷却结束才真正弹窗。
    static func registerMeaningfulAction() {
        let count = UserDefaults.standard.integer(forKey: countKey) + 1
        UserDefaults.standard.set(count, forKey: countKey)
        guard count >= threshold else { return }
        let last = UserDefaults.standard.double(forKey: lastPromptKey)
        guard Date().timeIntervalSince1970 - last > cooldown else { return }
        requestReview()
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastPromptKey)
        UserDefaults.standard.set(0, forKey: countKey)
    }

    private static func requestReview() {
        #if canImport(StoreKit) && canImport(UIKit)
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
                ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }
        SKStoreReviewController.requestReview(in: scene)
        #endif
    }
}

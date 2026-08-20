import Foundation

// MARK: - 黄历数据模型

public struct HuangliDay: Equatable, Hashable, Sendable {
    public let date: Date
    public let lunar: LunarDate
    public let yi: [String]       // 宜
    public let ji: [String]       // 忌
    public let chong: String      // 冲
    public let sha: String        // 煞
    public let wuXing: String     // 五行
    public let shenWei: String    // 神位
    public let isAuspicious: Bool // 黄道吉日

    public var displayChongSha: String {
        "\(chong) \(sha)"
    }
}

// MARK: - 黄历生成器

public enum HuangliGenerator {

    // 常用宜忌事项池（按权重/组合匹配）
    private static let yiPool: [Set<String>: [String]] = [
        ["甲子","丙寅","戊辰","庚午","壬申","甲戌"]:
            ["祭祀","祈福","求嗣","开光","塑绘","斋醮","订盟","纳采","嫁娶","出行","动土","上梁"],
        ["丙子","戊寅","庚辰","壬午","甲申","丙戌"]:
            ["开市","交易","立券","纳财","开仓","出货财","栽种","纳畜","牧养","会亲友","安床"],
        ["戊子","庚寅","壬辰","甲午","丙申","戊戌"]:
            ["破屋坏垣","求医","疗病","解除","祭祀","扫舍","修饰垣墙","平治道涂"],
        ["庚子","壬寅","甲辰","丙午","戊申","庚戌"]:
            ["修造","动土","竖柱","上梁","安门","作灶","造庙","安床","移徙","入宅","安葬"],
        ["壬子","甲寅","丙辰","戊午","庚申","壬戌"]:
            ["入学","习艺","赴任","出行","上官","见贵","求财","开市","交易","提车"]
    ]

    private static let jiPool: [Set<String>: [String]] = [
        ["甲子","乙丑","戊辰","己巳","壬午","癸未"]:
            ["诸事不宜","嫁娶","开市","入宅","安葬"],
        ["丙子","丁丑","壬辰","癸巳","丙午","丁未"]:
            ["出行","动土","破土","修造","安门","作灶"],
        ["戊子","己丑","丙申","丁酉","庚子","辛亥"]:
            ["伐木","作梁","行丧","安葬","祭祀","开光"],
        ["庚子","辛丑","甲辰","乙巳","戊午","己未"]:
            ["安床","移徙","入宅","交易","开市","立券"],
        ["壬子","癸丑","丙辰","丁巳","庚午","辛未"]:
            ["嫁娶","纳采","订盟","裁衣","冠笄","开市"]
    ]

    // 28星宿
    private static let xiu28 = [
        "角","亢","氐","房","心","尾","箕",
        "斗","牛","女","虚","危","室","壁",
        "奎","娄","胃","昴","毕","觜","参",
        "井","鬼","柳","星","张","翼","轸"
    ]

    // 冲煞
    private static let chongMap = ["马","羊","猴","鸡","狗","猪","鼠","牛","虎","兔","龙","蛇"]
    private static let shaMap = ["煞南","煞东","煞北","煞西"]

    // 五行方位
    private static let wuXingMap = [
        "甲子":"海中金","乙丑":"海中金","丙寅":"炉中火","丁卯":"炉中火",
        "戊辰":"大林木","己巳":"大林木","庚午":"路旁土","辛未":"路旁土",
        "壬申":"剑锋金","癸酉":"剑锋金","甲戌":"山头火","乙亥":"山头火",
        "丙子":"涧下水","丁丑":"涧下水","戊寅":"城头土","己卯":"城头土",
        "庚辰":"白蜡金","辛巳":"白蜡金","壬午":"杨柳木","癸未":"杨柳木",
        "甲申":"泉中水","乙酉":"泉中水","丙戌":"屋上土","丁亥":"屋上土",
        "戊子":"霹雳火","己丑":"霹雳火","庚寅":"松柏木","辛卯":"松柏木",
        "壬辰":"长流水","癸巳":"长流水","甲午":"砂石金","乙未":"砂石金",
        "丙申":"山下火","丁酉":"山下火","戊戌":"平地木","己亥":"平地木",
        "庚子":"壁上土","辛丑":"壁上土","壬寅":"金箔金","癸卯":"金箔金",
        "甲辰":"覆灯火","乙巳":"覆灯火","丙午":"天河水","丁未":"天河水",
        "戊申":"大驿土","己酉":"大驿土","庚戌":"钗钏金","辛亥":"钗钏金",
        "壬子":"桑柘木","癸丑":"桑柘木","甲寅":"大溪水","乙卯":"大溪水",
        "丙辰":"沙中土","丁巳":"沙中土","戊午":"天上火","己未":"天上火",
        "庚申":"石榴木","辛酉":"石榴木","壬戌":"大海水","癸亥":"大海水"
    ]

    /// 基于公历日期生成黄历
    /// 策略：优先查"离散黄历数据库"（2024-2028，内置 huangli_db.json），命中则直接用
    /// 未命中（资源缺失/区间外）时走算法推导作为兜底
    public static func generate(for date: Date) -> HuangliDay {
        let resolved = HuangliDBProvider.resolve(date: date)
        if let day = resolved.huangliDay {
            return day
        }
        // 越界时，给一个尽量合理的兜底（lunar 使用占位值）
        let safeLunar = ChineseCalendar.lunarDateSafe(from: date) ?? LunarDate(
            year: 0, month: 1, day: 1, isLeapMonth: false
        )
        return algorithmGenerate(for: date, lunar: safeLunar)
    }

    /// 纯算法推导入口（fallback & 单元测试 & 离散库生成脚本使用）
    public static func algorithmGenerate(for date: Date, lunar: LunarDate) -> HuangliDay {
        // 计算当日干支（以立春为界的年干支简化：使用农历正月初一）
        let dayGanZhi = dayGanZhiOf(date)

        // 宜忌 (按日柱干支匹配，若命中则用对应池，否则给默认值)
        let yi = matchYi(for: dayGanZhi)
        let ji = matchJi(for: dayGanZhi)

        // 冲煞：冲 = 地支对冲，煞 = 三煞方
        let zhiIndex = (dayGanZhi.1 + 12) % 12
        let chongZhiIndex = (zhiIndex + 6) % 12
        let chong = "冲\(ChineseCalendar.zodiacs[chongZhiIndex])"
        let shaIndex = (zhiIndex % 4)
        let sha = shaMap[shaIndex]

        // 五行纳音 (年柱)
        let yearGanZhi = ChineseCalendar.ganZhiOfYear(lunar.year)
        let wuXing = wuXingMap[yearGanZhi] ?? "未知"

        // 神位 (喜神/财神方位，简化)
        let shenWei = shenWeiDirection(zhiIndex)

        // 黄道吉日判断：基于建除十二神 + 值日 + 28宿吉凶综合
        let isAuspicious = determineAuspicious(date: date, dayGanZhi: dayGanZhi, lunar: lunar)

        return HuangliDay(
            date: date,
            lunar: lunar,
            yi: yi,
            ji: ji,
            chong: chong,
            sha: sha,
            wuXing: wuXing,
            shenWei: shenWei,
            isAuspicious: isAuspicious
        )
    }

    // MARK: - 辅助计算

    /// 计算当日干支：以1900年1月1日为基准日
    /// 系统Calendar + 黄历网双验证：1900-01-01 = 甲戌日（天干甲=0，地支戌=10）
    /// 衍生验证：2024-10-01 应为 戊戌日(gan=4,zhi=10) → 冲龙，符合公开黄历
    private static func dayGanZhiOf(_ date: Date) -> (gan: Int, zhi: Int, text: String) {
        let cal = Calendar(identifier: .gregorian)
        let baseDate: Date = {
            var comps = DateComponents()
            comps.year = 1900; comps.month = 1; comps.day = 1
            return cal.startOfDay(for: cal.date(from: comps) ?? date)
        }()
        let norm = cal.startOfDay(for: date)
        let diff = cal.dateComponents([.day], from: baseDate, to: norm).day ?? 0
        let days: Int
        if diff < 0 {
            // 负数：60甲子循环修正为正
            let mod = diff % 60
            days = (mod + 60) % 60
        } else {
            days = diff
        }
        // 1900-01-01 = 甲戌日：
        //   天干 甲 = tianGan[0]
        //   地支 戌 = diZhi[10]
        let baseGan = 0
        let baseZhi = 10
        let gan = (baseGan + (days % 10) + 10) % 10
        let zhi = (baseZhi + (days % 12) + 12) % 12
        let text = "\(ChineseCalendar.tianGan[gan])\(ChineseCalendar.diZhi[zhi])"
        return (gan, zhi, text)
    }

    private static func matchYi(for ganzhi: (gan: Int, zhi: Int, text: String)) -> [String] {
        for (keys, values) in yiPool {
            if keys.contains(ganzhi.text) {
                return Array(values.prefix(8))
            }
        }
        // 默认宜：固定顺序（不要 shuffled，保持调用间稳定）
        let fallback = ["祭祀", "出行", "沐浴", "扫舍", "馀事勿取", "会亲友", "纳财", "栽种"]
        // 根据干支文字做稳定哈希，保证同一天结果固定，不同天有差异
        let hash = ganzhi.text.unicodeScalars.reduce(0) { ($0 * 31 + Int($1.value)) % fallback.count }
        var result = [String]()
        for i in 0..<min(5, fallback.count) {
            result.append(fallback[(hash + i) % fallback.count])
        }
        return result
    }

    private static func matchJi(for ganzhi: (gan: Int, zhi: Int, text: String)) -> [String] {
        for (keys, values) in jiPool {
            if keys.contains(ganzhi.text) {
                return Array(values.prefix(8))
            }
        }
        // 默认忌：固定顺序
        let fallback = ["嫁娶", "安葬", "动土", "破土", "开市", "入宅", "移徙", "作灶"]
        let hash = ganzhi.text.unicodeScalars.reduce(0) { ($0 * 17 + Int($1.value)) % fallback.count }
        var result = [String]()
        for i in 0..<min(5, fallback.count) {
            result.append(fallback[(hash + i) % fallback.count])
        }
        return result
    }

    private static func shenWeiDirection(_ zhiIndex: Int) -> String {
        // 简化喜神/财神方位映射
        let xiShen = ["东北","西北","西南","东南","东北","西北","西南","东南","东北","西北","西南","东南"][zhiIndex]
        let caiShen = ["西南","正西","正北","正南","正东","东南","东北","西南","正西","正北","正南","正东"][zhiIndex]
        return "喜神:\(xiShen) 财神:\(caiShen)"
    }

    private static func determineAuspicious(
        date: Date,
        dayGanZhi: (gan: Int, zhi: Int, text: String),
        lunar: LunarDate
    ) -> Bool {
        // 简化的黄道吉日判定：
        // 1. 建除十二神：除、满、平、定、执、破、危、成、收、开、闭
        // 2. 黄道日 = 青龙、明堂、金匮、天德、玉堂、司命
        // 这里使用基于地支的简单判定 + 奇偶日 + 28宿吉凶加权

        let zhi = dayGanZhi.zhi
        // 值日吉凶（地支->黄道六神的判定简化）
        let huangDaoShen = [1, 3, 5, 6, 8, 10] // 黄黑道日（简化版）
        var score = 0
        if huangDaoShen.contains(zhi) { score += 2 }

        // 建除十二神：以农历日推算（简化版）
        // 建=初一对应，除=满...黄道：除、满、定、执、成、开
        let jianChu = (lunar.day - 1) % 12
        let goodJianChu = [1, 2, 4, 5, 7, 9] // 除、满、定、执、成、开
        if goodJianChu.contains(jianChu) { score += 2 }

        // 28宿吉宿：角、亢、房、心、尾、箕、斗、室、壁、娄、胃、毕、参、井、柳、张、翼
        let cal = Calendar(identifier: .gregorian)
        var dc = DateComponents()
        dc.year = 1900; dc.month = 1; dc.day = 1
        let base = cal.date(from: dc) ?? date
        let diff = cal.dateComponents([.day], from: base, to: date).day ?? 0
        let xiuIndex = ((diff % 28) + 28) % 28
        let goodXiu: Set<Int> = [0,1,3,4,5,6,7,15,16,17,20,22,25,26]
        if goodXiu.contains(xiuIndex) { score += 1 }

        return score >= 3
    }
}

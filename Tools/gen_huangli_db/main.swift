import LunisolarCalendarApp
import Foundation

// 生成 huangli_db.json：2024-01-01 ~ 2028-12-31 离散黄历库
let cal = Calendar(identifier: .gregorian)
var comps = DateComponents()
comps.year = 2024; comps.month = 1; comps.day = 1
let start = cal.date(from: comps)!
comps.year = 2029; comps.month = 1; comps.day = 1
let end = cal.date(from: comps)!

let df = DateFormatter()
df.dateFormat = "yyyy-MM-dd"
df.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
df.locale = Locale(identifier: "zh_CN_POSIX")

var dict: [String: [String: Any]] = [:]
var cursor = start
var total = 0
while cursor < end {
    // 生成离散库必须直接走纯算法，不能走 generate(for:)——后者会优先查旧库，造成循环写入旧数据。
    // 2024-2028 完全落在农历数据表覆盖范围内，lunarDateSafe 不会返回 nil。
    guard let lunar = ChineseCalendar.lunarDateSafe(from: cursor) else {
        cursor = cal.date(byAdding: .day, value: 1, to: cursor)!
        continue
    }
    let h = HuangliGenerator.algorithmGenerate(for: cursor, lunar: lunar)
    let key = df.string(from: cursor)
    dict[key] = [
        "y": h.yi,
        "j": h.ji,
        "c": String(h.chong.dropFirst(1)), // 去前缀"冲"
        "s": String(h.sha.dropFirst(1)),  // 去前缀"煞"
        "w": h.wuXing,
        "g": h.shenWei
    ]
    cursor = cal.date(byAdding: .day, value: 1, to: cursor)!
    total += 1
}

let wrapper: [String: Any] = [
    "v": 1,
    "range": ["2024-01-01", "2028-12-31"],
    "count": dict.count,
    "days": dict
]
let data = try JSONSerialization.data(withJSONObject: wrapper, options: [.sortedKeys])
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "huangli_db.json"
try data.write(to: URL(fileURLWithPath: outPath))
let sizeKB = Double(data.count) / 1024.0
print("✅ HuangliDB generated: \(total) days, size=\(String(format: "%.1f", sizeKB)) KB -> \(outPath)")

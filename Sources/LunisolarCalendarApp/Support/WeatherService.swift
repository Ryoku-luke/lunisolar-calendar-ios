import Foundation
#if canImport(CoreLocation)
import CoreLocation
#endif

// MARK: - 天气快照

/// 单日天气（7 天条：前 3 天 + 今天 + 后 3 天）
struct DailyWeather: Codable, Equatable, Sendable {
    var date: Date          // 当天 00:00（本地时区）
    var weatherCode: Int    // WMO 天气码
    var maxTemp: Double     // 当日最高
    var minTemp: Double     // 当日最低
}

/// 天气快照（Open-Meteo，免费免 Key）
struct WeatherSnapshot: Codable, Equatable, Sendable {
    var temperature: Double      // 当前温度
    var maxTemperature: Double   // 今日最高
    var minTemperature: Double   // 今日最低
    var weatherCode: Int         // WMO 天气码
    var locationName: String     // 城市名（反地理编码）
    var fetchedAt: Date
    /// 前 3 天 + 今天 + 后 3 天的逐日天气（旧缓存无此字段时为 nil，UI 回退单日）
    var days: [DailyWeather]?
}

/// WMO 天气代码 → 中文描述 / SF Symbol
enum WMOWeather {
    static func describe(_ code: Int) -> (text: String, symbol: String) {
        switch code {
        case 0, 1:     return ("晴", "sun.max.fill")
        case 2:        return ("少云", "cloud.sun.fill")
        case 3:        return ("多云", "cloud.fill")
        case 45, 48:   return ("雾", "cloud.fog.fill")
        case 51, 53, 55, 56, 57: return ("毛毛雨", "cloud.drizzle.fill")
        case 61, 63, 65, 80, 81, 82: return ("雨", "cloud.rain.fill")
        case 66, 67:   return ("冻雨", "cloud.sleet.fill")
        case 71, 73, 75, 77, 85, 86: return ("雪", "cloud.snow.fill")
        case 95, 96, 99: return ("雷暴", "cloud.bolt.rain.fill")
        default:       return ("未知", "cloud.fill")
        }
    }
}

// MARK: - 定位结果

#if canImport(CoreLocation)
enum LocationOutcome {
    case location(CLLocation)
    case denied     // 用户未授权定位
    case failed     // 定位服务失败（无信号等）
}
#else
/// 无 CoreLocation 平台（Linux / SwiftPM 单测）：定位恒失败
enum LocationOutcome {
    case denied
    case failed
}
#endif

// MARK: - 定位服务

/// 定位服务（WhenInUse，单次定位；未授权/失败返回对应结果，天气模块据此显示提示）。
/// 超时实现：**主线程 100ms 间隔轮询**授权状态与定位结果（无 CheckedContinuation 竞速、
/// 无 withTaskGroup sending 闭包），规避 Swift 6 区域隔离检查器无法识别的模式，且永不挂起。
#if canImport(CoreLocation)
@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {
    static let shared = LocationService()
    private let manager = CLLocationManager()
    private var pendingResult: LocationOutcome?
    private static let pollStepMS = 100
    private static let pollCount = 60   // 60 × 100ms = 6s 超时
    /// 最近一次成功定位缓存（60s 内复用）：切日期 / 视图重建不再重复请求 GPS，省电且零延迟
    private var cachedLocation: CLLocation?
    private var cachedAt: Date?
    private static let cacheTTL: TimeInterval = 60

    private override init() {
        super.init()
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.delegate = self
    }

    /// 请求单次定位；未授权返回 .denied，超时/失败返回 .failed（最坏 6s，绝不挂起）
    func currentLocation() async -> LocationOutcome {
        // 0) 60s 内直接复用最近定位结果（性能：避免每次天气视图重建都请求 GPS）
        if let loc = cachedLocation, let at = cachedAt,
           Date().timeIntervalSince(at) < Self.cacheTTL {
            return .location(loc)
        }
        // 1) 授权
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            break
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
            for _ in 0..<Self.pollCount {
                if manager.authorizationStatus != .notDetermined { break }
                try? await Task.sleep(for: .milliseconds(Self.pollStepMS))
            }
            let status = manager.authorizationStatus
            if status != .authorizedWhenInUse && status != .authorizedAlways {
                return .denied
            }
        case .denied, .restricted:
            return .denied
        @unknown default:
            return .denied
        }
        // 2) 单次定位 + 轮询结果；成功后更新缓存
        pendingResult = nil
        manager.requestLocation()
        for _ in 0..<Self.pollCount {
            if let result = pendingResult {
                if case .location(let loc) = result {
                    cachedLocation = loc
                    cachedAt = Date()
                }
                return result
            }
            try? await Task.sleep(for: .milliseconds(Self.pollStepMS))
        }
        return .failed
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // 授权状态由轮询直接读取，无需在此处理
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let result: LocationOutcome = locations.last.map { .location($0) } ?? .failed
        Task { @MainActor in self.pendingResult = result }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.pendingResult = .failed }
    }
}
#endif // canImport(CoreLocation)

// MARK: - 天气获取

enum WeatherResult {
    case success(WeatherSnapshot)
    case denied     // 定位未授权
    case failed     // 网络 / 解析 / 定位失败
}

/// Open-Meteo 天气获取（免费、免 Key）+ 1 小时缓存；
/// 定位 / 反地理编码 / 网络全链路带超时兜底，任何环节失败返回 .failed，绝不挂起
#if canImport(CoreLocation)
@MainActor
enum WeatherProvider {
    private static let cacheKey = "weather.cache.v2"
    private static let cacheTTL: TimeInterval = 3600
    /// 网络请求 8s 超时，避免无响应时界面永久卡在加载态
    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 8
        cfg.timeoutIntervalForResource = 12
        return URLSession(configuration: cfg)
    }()

    private struct Response: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let apparent_temperature: Double
            let weather_code: Int
        }
        struct Daily: Decodable {
            let time: [String]
            let weather_code: [Int]
            let temperature_2m_max: [Double]
            let temperature_2m_min: [Double]
        }
        let current: Current
        let daily: Daily
    }

    /// 当前位置天气；未授权 → .denied；超时/网络/解析失败 → .failed
    /// 并发去重：天气图标 + 天气文字两个视图同时请求时只发一次定位/一次网络（共享 in-flight task）
    private static var inflightTask: Task<WeatherResult, Never>?

    static func currentWeather() async -> WeatherResult {
        if let t = inflightTask {
            return await t.value
        }
        let t = Task { await fetchWeather() }
        inflightTask = t
        let result = await t.value
        if inflightTask == t { inflightTask = nil }
        return result
    }

    private static func fetchWeather() async -> WeatherResult {
        // 定位内部自带 6s 轮询超时（LocationService + 60s 定位缓存），此处直接 await，绝不挂起
        let outcome = await LocationService.shared.currentLocation()
        let coordinate: CLLocationCoordinate2D
        switch outcome {
        case .location(let loc):
            coordinate = loc.coordinate
        case .denied:
            // 用户明确拒绝定位：仍返回 .denied，UI 提示去系统设置开启
            return .denied
        case .failed:
            // 定位超时/无信号：用北京坐标兜底，天气仍可显示（不伪造城市名）
            coordinate = CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074)
        }
        let coordKey = String(format: "%.4f,%.4f", coordinate.latitude, coordinate.longitude)
        if let cached = cachedSnapshot(coordKey: coordKey) { return .success(cached) }

        // 真实定位成功才反地理编码城市名；兜底坐标直接显示"北京"
        let isRealLocation: Bool
        switch outcome {
        case .location: isRealLocation = true
        default: isRealLocation = false
        }
        let name: String
        if isRealLocation {
            name = await reverseGeocode(CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) ?? "当前位置"
        } else {
            name = "北京"
        }
        do {
            var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
            comps.queryItems = [
                URLQueryItem(name: "latitude", value: String(format: "%.4f", coordinate.latitude)),
                URLQueryItem(name: "longitude", value: String(format: "%.4f", coordinate.longitude)),
                URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,weather_code"),
                URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min"),
                URLQueryItem(name: "timezone", value: "auto"),
                URLQueryItem(name: "past_days", value: "3"),
                URLQueryItem(name: "forecast_days", value: "14")
            ]
            let (data, response) = try await session.data(from: comps.url!)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return .failed }
            let payload = try JSONDecoder().decode(Response.self, from: data)
            let snapshot = WeatherSnapshot(
                temperature: payload.current.temperature_2m,
                maxTemperature: payload.daily.temperature_2m_max.first ?? payload.current.temperature_2m,
                minTemperature: payload.daily.temperature_2m_min.first ?? payload.current.temperature_2m,
                weatherCode: payload.current.weather_code,
                locationName: name,
                fetchedAt: Date(),
                days: Self.buildDays(from: payload.daily)
            )
            store(snapshot, coordKey: coordKey)
            return .success(snapshot)
        } catch {
            return .failed
        }
    }

    /// 组装逐日天气（前 3 天 + 未来 7 天，共 10 条；UI 按选中日取 ±3 天窗口）
    private static func buildDays(from daily: Response.Daily) -> [DailyWeather] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        let n = min(daily.time.count, daily.weather_code.count,
                    daily.temperature_2m_max.count, daily.temperature_2m_min.count)
        guard n > 0 else { return [] }
        var result: [DailyWeather] = []
        result.reserveCapacity(n)
        for i in 0..<n {
            guard let date = formatter.date(from: daily.time[i]) else { continue }
            result.append(DailyWeather(
                date: date,
                weatherCode: daily.weather_code[i],
                maxTemp: daily.temperature_2m_max[i],
                minTemp: daily.temperature_2m_min[i]
            ))
        }
        return result
    }

    /// 反地理编码：Apple 地理编码服务自带超时，失败返回 nil 降级"当前位置"
    private static func reverseGeocode(_ location: CLLocation) async -> String? {
        let geocoder = CLGeocoder()
        guard let placemark = try? await geocoder.reverseGeocodeLocation(location).first else { return nil }
        return placemark.locality ?? placemark.administrativeArea ?? placemark.name
    }

    private static func cachedSnapshot(coordKey: String) -> WeatherSnapshot? {
        let def = UserDefaults.standard
        guard let saved = def.data(forKey: cacheKey),
              let box = try? JSONDecoder().decode(WeatherCacheBox.self, from: saved),
              box.coordKey == coordKey,
              Date().timeIntervalSince(box.snapshot.fetchedAt) < cacheTTL else { return nil }
        return box.snapshot
    }

    private static func store(_ snapshot: WeatherSnapshot, coordKey: String) {
        guard let data = try? JSONEncoder().encode(WeatherCacheBox(coordKey: coordKey, snapshot: snapshot)) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
        // 同步写 App Group，供 Widget Large 读取（跨进程共享）
        if let shared = UserDefaults(suiteName: "group.com.lumingfeng.lunisolarcalendar") {
            shared.set(data, forKey: cacheKey)
        }
    }

    private struct WeatherCacheBox: Codable {
        let coordKey: String
        let snapshot: WeatherSnapshot
    }
}
#else
/// 无 CoreLocation 平台（Linux / SwiftPM 单测）：天气功能不可用，返回 .failed
@MainActor
enum WeatherProvider {
    static func currentWeather() async -> WeatherResult { .failed }
}
#endif // canImport(CoreLocation)

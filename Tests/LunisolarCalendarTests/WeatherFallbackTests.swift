import XCTest
import CoreLocation
@testable import LunisolarCalendarApp

/// 天气兜底策略：**拿不到定位就不许造天气**。
///
/// 对应一处真 bug（2026-09-27 修复）：
/// `fetchWeather` 在「定位超时/无信号」时用北京坐标继续取天气，并把城市名显示成「北京」，
/// 而紧邻的注释写着「不伪造城市名」。对不在北京的用户，天气卡会明确告诉他当地是北京。
///
/// 这里锁住的不是「文案写对」，而是**策略本身**：没有定位 → 不许有坐标。
/// 只要有人再加回任何写死的兜底坐标，下面第二条断言就会红。
final class WeatherFallbackTests: XCTestCase {

    func testNoCoordinateWithoutRealLocation() {
        XCTAssertNil(WeatherProvider.coordinate(from: .denied),
                     "用户拒绝定位时不该给出任何坐标")
        XCTAssertNil(WeatherProvider.coordinate(from: .failed),
                     "定位失败时不该给出坐标（历史 bug：这里返回了北京坐标）")
    }

    /// 反面断言：策略给出的坐标只能来自传入的那次定位，不能是任何写死的值。
    /// 把「北京」这个历史兜底值显式钉在这里，改了别处也会被这条拦住。
    func testCoordinateIsNeverAHardcodedFallback() {
        let beijingLatitude = 39.9042
        for outcome in [LocationOutcome.denied, LocationOutcome.failed] {
            let c = WeatherProvider.coordinate(from: outcome)
            XCTAssertNil(c)
            XCTAssertNotEqual(c?.latitude, beijingLatitude,
                              "「没有定位」的分支不得给出北京坐标")
        }
    }

    func testRealLocationYieldsItsOwnCoordinate() {
        let shanghai = CLLocation(latitude: 31.2304, longitude: 121.4737)
        let c = WeatherProvider.coordinate(from: .location(shanghai))
        XCTAssertEqual(c?.latitude ?? 0, 31.2304, accuracy: 0.0001)
        XCTAssertEqual(c?.longitude ?? 0, 121.4737, accuracy: 0.0001)
    }
}

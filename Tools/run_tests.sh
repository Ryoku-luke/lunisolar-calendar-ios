#!/usr/bin/env bash
#
# 一键验证：把本项目的五条通道串成一条命令。
#
# 为什么需要它：这个项目的验证一直是本机几条固定通道 —— swift test（macOS 宿主）/
# iOS SDK 构建 / UI 测试 target 类型检查 / iPhone UI 测试 / iPad UI 测试。
# 此前每条都靠人手拼 xcodebuild 命令，
# 换个接手的人（或换台机器）就得重新推一遍参数：模拟器机型名、OS 版本、
# -only-testing 的 target 路径、以及「不要并行跑两个 xcodebuild」这条踩过坑的纪律。
#
# 用法：
#   Tools/run_tests.sh                          # 默认 iPhone 17 Pro + iPad Pro 11-inch (M5)
#   Tools/run_tests.sh "iPhone 16 Pro"          # 指定 iPhone 机型
#   IPAD_SIM="iPad Air 13-inch (M4)" Tools/run_tests.sh
#   OS_VER=27.0 Tools/run_tests.sh              # 指定模拟器 OS 版本（默认 26.5）
#   SKIP_UI=1 Tools/run_tests.sh                # 跳过两条 UI 测试（类型检查仍跑；改文档时够用）
#
# 行为约定：
# - **串行**执行。并行跑两个 xcodebuild 会互相干扰（本项目实测：模拟器克隆导致
#   随机一条用例失败，极易误判成业务 bug）。
# - 每条通道的完整输出写进 /tmp/run_tests.<通道>.log，失败时打印该文件路径；
#   终端只显示判定行，不刷屏。
# - 任一通道失败 → 退出码非零（可直接接 CI 或 git hook）。
# - 机型不存在时该通道判失败，并列出可用机型。
# - **两条 UI 通道先 `simctl shutdown all` 再跑**，且只在「模拟器基础设施抖动」
#   （Busy / failed preflight checks / runner 起不来）时清理并重试一次；
#   真实断言失败绝不重试（见 FLAKY_INFRA_PATTERN 处的注释）。

set -uo pipefail   # 刻意不用 -e：要跑完全部通道再汇总
cd "$(dirname "$0")/.." || exit 1

IPHONE_SIM="${1:-${IPHONE_SIM:-iPhone 17 Pro}}"
IPAD_SIM="${IPAD_SIM:-iPad Pro 11-inch (M5)}"
OS_VER="${OS_VER:-26.5}"

PASS=0
FAIL=0
FAILED_NAMES=()

# 模拟器偶发的**基础设施**抖动（与代码无关）——命中时清理并重试一次。
#
# 实测（2026-10-02 19:05）：iPad 通道在 iPhone 通道刚跑完后
# `Failed to install or launch the test runner ... SBMainWorkspace ... Busy
# ("Application failed preflight checks")`，一条用例都没跑就判定失败；
# 而同一通道上一轮 5 条全绿。这类失败重试即可通过。
#
# ⚠️ 只在这个白名单上重试：真实断言失败绝不重试，否则等于把红糊成绿。
FLAKY_INFRA_PATTERN='Failed to install or launch the test runner|failed preflight checks|SBMainWorkspace.*Busy|Unable to boot device|Timed out while loading'

# channel <显示名> <判定用的正则> <命令...>
channel() {
  local name="$1" pattern="$2"
  shift 2
  local log="/tmp/run_tests.${name// /_}.log"
  local attempt=1 status=0 attemptLabel=""

  while :; do
    attemptLabel=""
    [[ $attempt -gt 1 ]] && attemptLabel="（第 $attempt 次尝试）"
    echo
    echo "──── $name$attemptLabel ────"
    "$@" >"$log" 2>&1
    status=$?

    if [[ $status -eq 0 ]] && grep -qE "$pattern" "$log"; then
      echo "✅ $name"
      grep -E "$pattern" "$log" | tail -2
      PASS=$((PASS + 1))
      return 0
    fi

    # 只在「基础设施抖动」上重试一次；其余失败立即判定，不掩盖真实失败
    if [[ $attempt -lt 2 ]] && grep -qE "$FLAKY_INFRA_PATTERN" "$log"; then
      echo "⚠️  $name 命中模拟器基础设施抖动，清理后重试一次："
      grep -oE "$FLAKY_INFRA_PATTERN" "$log" | head -1 | sed 's/^/   | /'
      xcrun simctl shutdown all >/dev/null 2>&1 || true
      sleep 5
      attempt=$((attempt + 1))
      continue
    fi

    echo "❌ ${name}（退出码 ${status}）"
    echo "   完整日志：$log"
    echo "   末尾 20 行："
    tail -20 "$log" | sed 's/^/   | /'
    FAILED_NAMES+=("$name")
    FAIL=$((FAIL + 1))
    return 1
  done
}

# UI 通道专用：开跑前先关掉所有模拟器。
# 为什么：上一个 UI 通道用过的设备常常还开着，CoreSimulator 再起第二台设备时
# 容易报 Busy / failed preflight checks（见上面的白名单）。
ui_channel() {
  xcrun simctl shutdown all >/dev/null 2>&1 || true
  channel "$@"
}

echo "项目五通道验证 —— iPhone: $IPHONE_SIM / iPad: $IPAD_SIM / iOS $OS_VER"
[[ "${SKIP_UI:-0}" == "1" ]] && echo "（SKIP_UI=1：跳过两条 UI 测试通道）"

channel "swift test（macOS 宿主）" \
  "Executed [0-9]+ tests, with 0 failures" \
  swift test

channel "iOS SDK 构建" \
  "Build complete" \
  swift build --triple arm64-apple-ios17.0-simulator \
    --sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)"

# 放在两条 UI 测试通道之前：UI 测试 target 不在 SwiftPM 包里，`swift test` 看不见它，
# 副本漏同步这类问题只有这里能在几秒内拦住（2026-10-02 实测：本地 360 用例全绿，
# 而 UI 测试 target 编译失败）。SKIP_UI=1 时也跑——它只是编译检查，不碰模拟器。
channel "UI 测试 target 类型检查" \
  "UITESTS_TYPECHECK_OK" \
  Tools/typecheck_uitests.sh

if [[ "${SKIP_UI:-0}" != "1" ]]; then
  ui_channel "iPhone UI 测试（${IPHONE_SIM}）" \
    '\*\* TEST SUCCEEDED \*\*' \
    xcodebuild test -project LunisolarCalendar.xcodeproj -scheme LunisolarCalendar \
      -destination "platform=iOS Simulator,name=$IPHONE_SIM,OS=$OS_VER" \
      -only-testing:LunisolarCalendarUITests

  ui_channel "iPad UI 测试（${IPAD_SIM}）" \
    '\*\* TEST SUCCEEDED \*\*' \
    xcodebuild test -project LunisolarCalendar.xcodeproj -scheme LunisolarCalendar \
      -destination "platform=iOS Simulator,name=$IPAD_SIM,OS=$OS_VER" \
      -only-testing:LunisolarCalendarUITests
fi

echo
echo "──────── 汇总 ────────"
echo "通过 $PASS 条，失败 $FAIL 条"
if [[ $FAIL -gt 0 ]]; then
  printf '  ❌ %s\n' "${FAILED_NAMES[@]}"
  echo
  echo "若失败原因是「机型不存在」，可用机型："
  xcrun simctl list devices available | grep -E "iPhone|iPad" | head -10
  exit 1
fi
echo "✅ 全部通过"

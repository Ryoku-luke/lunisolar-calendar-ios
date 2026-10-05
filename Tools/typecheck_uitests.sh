#!/usr/bin/env bash
#
# 秒级编译检查：LunisolarCalendarUITests target。
#
# 为什么单独有这一条：UI 测试 target **不在 SwiftPM 包里**，`swift test` 完全看不见它。
# 2026-10-02 实测事故：`AccessibilityID` 加了一个标识但 `LunisolarCalendarUITests.swift`
# 里的字面量副本（`private enum ID`）没同步 → 本地 360 个用例 × 4 时区全绿，
# 而 UI 测试 target 编译失败（`type 'ID' has no member '...'`）。
# 那一次要等整条 xcodebuild 跑到编译阶段才炸。这条通道几秒钟就能给出同样的结论。
#
# 用法：
#   Tools/typecheck_uitests.sh        # 成功打印 UITESTS_TYPECHECK_OK 并返回 0
#
# 为什么不直接 `xcodebuild build-for-testing`：那要解析 SwiftPM 依赖图 + 写 DerivedData，
# 在受限环境（CI 容器 / Agent 沙箱）里常常连 `~/Library/Caches/org.swift.swiftpm` 都写不了。
# `swiftc -typecheck` 只做「能不能编译」，不需要 DerivedData、不碰模拟器。

set -euo pipefail
cd "$(dirname "$0")/.." || exit 1

SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
TMP_OUT="$(mktemp)"; trap 'rm -f "$TMP_OUT"' EXIT
PLATFORM_DIR="$(xcode-select -p)/Platforms/iPhoneSimulator.platform"
CACHE=".build/uitest-typecheck"
mkdir -p "$CACHE"

# `-Isystem .../Developer/usr/lib` 是关键：Swift 版 XCTest 断言（XCTAssertTrue 等）
# 来自那里的 XCTest.swiftmodule。XCTest.framework 的头文件里只有 C 宏，
# Swift 会报 "function like macros not supported"，看起来像环境坏了，其实是少这一条路径。
xcrun --sdk iphonesimulator swiftc -typecheck \
  LunisolarCalendarUITests/*.swift \
  -target arm64-apple-ios17.0-simulator \
  -sdk "$SDK" \
  -module-cache-path "$CACHE/modulecache" \
  -clang-scanner-module-cache-path "$CACHE/clangcache" \
  -sdk-module-cache-path "$CACHE/sdkcache" \
  -Isystem "$PLATFORM_DIR/Developer/usr/lib" \
  -F "$PLATFORM_DIR/Developer/Library/Frameworks" \
  -F "$SDK/Developer/Library/Frameworks" 2>&1 | tee "$TMP_OUT"

# 与 Tools/run_tests.sh 同一条规矩：**编译警告即失败**。
# （此前的实现只打印 OK，即使 swiftc 报了警告也照样"通过"——本轮就漏掉了两条
#   XCTSkip 相关警告，直到人工看输出才发现。）
if grep -q "warning: " "$TMP_OUT"; then
  echo "UITESTS_TYPECHECK_FAILED: 存在编译警告（项目规矩：警告即失败）"
  grep "warning: " "$TMP_OUT" | head -10
  exit 1
fi

echo "UITESTS_TYPECHECK_OK"

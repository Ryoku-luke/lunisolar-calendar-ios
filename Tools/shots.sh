#!/usr/bin/env bash
#
# 视觉取证（截图巡游）：一条命令产出可复用的界面截图。
#
# 为什么需要它：本项目长期缺一个「改完界面怎么核验」的常规手段 —— 每轮视觉改动都要
# 现搭一套 simctl + xcodebuild + 附件导出，代价大且不可复用（此前两轮验收就是这么做的）。
# 这个脚本把两条互补的路径固化下来：
#
#   1. **深链巡游**（默认，纯 shell，不跑测试）
#      只用 `xcrun simctl`（launch / openurl / io screenshot）驱动 App 已支持的
#      `qinghe://` 深链切页。适用「无需点击就能到达」的页面，最快。
#   2. **XCUITest 巡游**（--tour）
#      跑一次 `LunisolarCalendarUITests/testScreenshotTour`，用例把每站挂成 XCTAttachment，
#      再从 `.xcresult` 用 `xcresulttool export attachments` 导出，并按 `manifest.json`
#      把随机文件名还原成可读名。适用「必须点击才能到达」的页面
#      （Tab / 月历菜单二级页 / iPad 侧栏各节）。
#      该用例默认跳过，只有本脚本传 `TEST_RUNNER_SHOTS=1` 时才运行。
#      ⚠️ `-only-testing` 必须写成 **target/class/method** 三段（本项目里前两段同名）；
#         只写到 `target/method` 时 xcodebuild **不报错**、但「Executed 0 tests」——
#         表现为测试通过而一张截图都没有，最难查的一种失败。
#
# 用法：
#   Tools/shots.sh [device] [outdir]                 # 深链巡游（默认机型 iPhone 17 Pro）
#   Tools/shots.sh --tour [device] [outdir]          # XCUITest 巡游 + 导出附件
#   Tools/shots.sh --appearance dark [device]        # 深色外观（light / dark，默认不动设备）
#   Tools/shots.sh --lang en [device]                # 英文界面（en / zh，默认 zh）
#   Tools/shots.sh --tour --appearance dark "iPad Pro 11-inch (M5)" /tmp/shots-ipad
#
# 选项与两个位置参数可任意顺序混排；位置参数依次是**机型名**与**输出目录**。
#
# 行为约定（都是踩过的坑）：
# - 机型用**名字**解析 udid，绝不写死 udid（换机器 / 换模拟器名都能用）。
# - 自动 `simctl boot` + `bootstatus -b` 等它真的起来再装。
# - 装之前先 `simctl privacy … grant location`：不 grant 的话首次启动会弹系统定位权限框，
#   它属于 SpringBoard、不在 App 元素树里，会把整个界面挡死（实测有效，别删）。
# - ⚠️ iOS 26 的 `simctl openurl` 会先弹「在"清和日历"中打开?」确认框，而 LaunchServices 的
#   scheme 审批表**只在开机时读一次** —— 所以脚本会「关机 → 写
#   com.apple.launchservices.schemeapproval.plist → 重新开机」把确认框消掉（首次运行会多花
#   约 20 秒重启；之后每次运行都直接跳过）。不这么做的话，深链巡游截到的全是那个确认框。
# - 同一处还会清掉模拟器全局 prefs 里遗留的 `pending-deeplink`：那是 App 自己的深链投递键，
#   被外部写过一次后**每次冷启动**都会把 App 劫持到那个页面（两种巡游都会因此截错页/失败）。
# - 构建用独立 derivedDataPath（默认 /tmp/shots-derived），不污染日常 DerivedData。
# - 只使用 `Tools/`、`LunisolarCalendarUITests/`，不改 App 源码。
# - `set -uo pipefail` **刻意不加 -e**：要跑完全部步骤再汇总；任一必需步骤失败 → 非零退出。
# - ⚠️ macOS 自带 bash 是 **3.2**：中文紧跟在 `$变量` 后面时，变量名会被多读进一个字节并
#   报 `unbound variable`。**所有 `$变量` 紧邻中文/全角字符处一律写成 `${变量}`**。
# - 依赖 `python3` 解析 manifest.json（只有 --tour 需要；Xcode 命令行工具自带）。
#
# 可调环境变量：
#   SHOTS_DERIVED=/tmp/shots-derived   构建产物目录（复用可加速）
#   SHOTS_LAUNCH_SETTLE=6              冷启动后的等待秒数
#   SHOTS_STEP_SLEEP=1.5               每次深链切页后的等待秒数

set -uo pipefail   # 刻意不用 -e：要跑完全部步骤再汇总

cd "$(dirname "$0")/.." || exit 1

BUNDLE_ID="com.lumingfeng.lunisolarcalendar"
PROJECT="LunisolarCalendar.xcodeproj"
SCHEME="LunisolarCalendar"
TOUR_TEST="LunisolarCalendarUITests/LunisolarCalendarUITests/testScreenshotTour"

DEFAULT_DEVICE="iPhone 17 Pro"
DEFAULT_OUTDIR="/tmp/shots"
DERIVED="${SHOTS_DERIVED:-/tmp/shots-derived}"
LAUNCH_SETTLE="${SHOTS_LAUNCH_SETTLE:-6}"
STEP_SLEEP="${SHOTS_STEP_SLEEP:-1.5}"
RESULT_BUNDLE="/tmp/shots-tour.xcresult"
EXPORT_DIR="/tmp/shots-attachments"

TOUR=0
APPEARANCE=""
LANG_CODE="zh"

PASS=0
FAIL=0
SHOTS=0

usage() {
  # 直接抽本文件顶部的注释块（第 2 行到第一个非注释行）——不写死行号，
  # 否则以后往头部加一行注释，--help 就会悄悄截断
  awk 'NR==2 { inblock = 1 }
       inblock { if ($0 !~ /^#/) exit; sub(/^# ?/, ""); print }' "$0"
}

fatal() {
  echo
  echo "❌ ${1}"
  exit 2
}

# ───────────────────────── 参数解析 ─────────────────────────

POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tour)
      TOUR=1; shift ;;
    --appearance)
      APPEARANCE="${2:-}"; shift
      [[ $# -gt 0 ]] && shift ;;
    --appearance=*)
      APPEARANCE="${1#*=}"; shift ;;
    --lang)
      LANG_CODE="${2:-}"; shift
      [[ $# -gt 0 ]] && shift ;;
    --lang=*)
      LANG_CODE="${1#*=}"; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      POSITIONAL+=("$1"); shift ;;
  esac
done

DEVICE="${DEFAULT_DEVICE}"
OUTDIR="${DEFAULT_OUTDIR}"
if [[ "${#POSITIONAL[@]}" -gt 0 ]]; then DEVICE="${POSITIONAL[0]}"; fi
if [[ "${#POSITIONAL[@]}" -gt 1 ]]; then OUTDIR="${POSITIONAL[1]}"; fi

case "${APPEARANCE}" in
  ""|light|dark) ;;
  *) fatal "「--appearance」只认 light / dark（收到「${APPEARANCE}」）" ;;
esac
case "${LANG_CODE}" in
  zh|zh-Hans) LANGUAGE="(zh-Hans)"; LOCALE="zh_Hans_CN" ;;
  en)         LANGUAGE="(en)";      LOCALE="en_US" ;;
  *) fatal "「--lang」只认 zh / en（收到「${LANG_CODE}」）" ;;
esac

# ───────────────────────── 步骤 1：解析机型 ─────────────────────────

UDID="$(xcrun simctl list devices available \
          | grep -F "${DEVICE} (" \
          | head -1 \
          | sed -E 's/.*\(([0-9A-Fa-f-]{36})\).*/\1/')"

if [[ -z "${UDID}" ]]; then
  echo "❌ 找不到模拟器「${DEVICE}」。可用的机型："
  xcrun simctl list devices available | grep -E "iPhone|iPad" | sed 's/^/   /'
  exit 2
fi

echo "机型：${DEVICE}（udid ${UDID}）"
echo "输出目录：${OUTDIR}"
echo "模式：$( [[ "${TOUR}" == "1" ]] && echo "XCUITest 巡游（--tour）" || echo "深链巡游" )"
[[ -n "${APPEARANCE}" ]] && echo "外观：${APPEARANCE}"
echo "语言：${LANG_CODE}"

# ───────────────────────── 步骤 2：启动模拟器 + 抑制系统弹窗 ─────────────────────────

# 两样东西会把截图毁掉，而且**都必须关机改、靠开机生效**：
#
# ① scheme 审批表（只有深链巡游需要）—— iOS 26 起 `simctl openurl` 会先弹 SpringBoard 的
#    「在"清和日历"中打开?」确认框，盖住整个界面，深链巡游会截到一整套确认框。
#    根因（Expo 的同名 issue，本机实测一致）：LaunchServices 只在**开机时**读一次
#    <设备>/data/Library/Preferences/com.apple.launchservices.schemeapproval.plist；
#    表写晚了（当前这次开机之后才写）就照样弹框。
#
# ② 全局 prefs 里遗留的 `pending-deeplink` —— 那是 App 自己的深链投递键。它被外部
#    （例如 `simctl spawn … defaults write`）写过一次后，**每次冷启动**都会被它劫持到
#    那个页面：表现为「01-日历」截出来是 AI 助手页、UI 巡游找不到月历工具栏。
SIM_PREFS="${HOME}/Library/Developer/CoreSimulator/Devices/${UDID}/data/Library/Preferences"
SCHEME_KEY="com.apple.CoreSimulator.CoreSimulatorBridge-->qinghe"
SCHEME_PLIST="${SIM_PREFS}/com.apple.launchservices.schemeapproval.plist"
GLOBAL_PREFS="${SIM_PREFS}/${BUNDLE_ID}.plist"

step_sim_state() {
  local reason=""
  local scheme_ok=1

  if [[ "${TOUR}" != "1" ]]; then
    if [[ "$(/usr/libexec/PlistBuddy -c "Print :${SCHEME_KEY}" "${SCHEME_PLIST}" 2>/dev/null || true)" != "${BUNDLE_ID}" ]]; then
      scheme_ok=0
      reason="scheme 审批表"
    fi
  fi

  local stale_link=0
  if [[ -f "${GLOBAL_PREFS}" ]] \
     && plutil -extract pending-deeplink raw "${GLOBAL_PREFS}" >/dev/null 2>&1; then
    stale_link=1
    [[ -n "${reason}" ]] && reason="${reason}、"
    reason="${reason}遗留 pending-deeplink"
  fi

  if [[ "${scheme_ok}" == "1" && "${stale_link}" == "0" ]]; then
    echo "✅ 模拟器状态就绪（审批表齐、无残留深链）"
    PASS=$((PASS + 1))
    return
  fi

  xcrun simctl shutdown "${UDID}" >/dev/null 2>&1 || true   # 改完由 step_boot 重新开机
  if [[ "${scheme_ok}" == "0" ]]; then
    if ! /usr/libexec/PlistBuddy -c "Add :${SCHEME_KEY} string ${BUNDLE_ID}" "${SCHEME_PLIST}" >/dev/null 2>&1; then
      /usr/libexec/PlistBuddy -c "Set :${SCHEME_KEY} ${BUNDLE_ID}" "${SCHEME_PLIST}" >/dev/null 2>&1
    fi
  fi
  [[ "${stale_link}" == "1" ]] && plutil -remove pending-deeplink "${GLOBAL_PREFS}" >/dev/null 2>&1

  # 改没改成要当场验：这两样没生效都不会报错，只会让后面所有截图变成
  # 「一整套确认框」或「每次冷启动都被劫持到同一个页面」—— 那种失败最难查
  local fixed=1
  if [[ "${TOUR}" != "1" ]] \
     && [[ "$(/usr/libexec/PlistBuddy -c "Print :${SCHEME_KEY}" "${SCHEME_PLIST}" 2>/dev/null || true)" != "${BUNDLE_ID}" ]]; then
    fixed=0
  fi
  if [[ -f "${GLOBAL_PREFS}" ]] \
     && plutil -extract pending-deeplink raw "${GLOBAL_PREFS}" >/dev/null 2>&1; then
    fixed=0
  fi
  if [[ "${fixed}" == "1" ]]; then
    echo "✅ 已修正模拟器状态（${reason}）—— 重启一次让它生效"
    PASS=$((PASS + 1))
  else
    echo "❌ 模拟器状态没能修正（${reason}）—— 截图会出现确认框 / 被残留深链劫持"
    FAIL=$((FAIL + 1))
  fi
}

step_boot() {
  xcrun simctl boot "${UDID}" >/dev/null 2>&1 || true   # 已启动会报错，忽略
  if ! xcrun simctl bootstatus "${UDID}" -b >/tmp/shots-bootstatus.log 2>&1; then
    echo "❌ 模拟器启动失败，日志 /tmp/shots-bootstatus.log"
    FAIL=$((FAIL + 1))
    return
  fi
  echo "✅ 模拟器已就绪"
  PASS=$((PASS + 1))
}

# 定位权限：不 grant 的话首次启动会弹系统权限框挡住界面（App 首屏要天气定位）
step_privacy() {
  if xcrun simctl privacy "${UDID}" grant location "${BUNDLE_ID}" >/tmp/shots-privacy.log 2>&1; then
    echo "✅ 已预授权定位（location）"
    PASS=$((PASS + 1))
  else
    echo "⚠️  预授权定位失败（App 未安装时属正常，安装后还会再授一次）"
  fi
}

step_appearance() {
  [[ -z "${APPEARANCE}" ]] && return 0
  if xcrun simctl ui "${UDID}" appearance "${APPEARANCE}" >/dev/null 2>&1; then
    echo "✅ 外观已切到 ${APPEARANCE}"
  else
    echo "❌ 外观切换失败（${APPEARANCE}）"
    FAIL=$((FAIL + 1))
  fi
}

# ───────────────────────── 步骤 3：构建 + 安装 ─────────────────────────

step_build_install() {
  local log="/tmp/shots-build.log"
  echo "构建中（derivedDataPath ${DERIVED}）…"
  if ! xcodebuild build -project "${PROJECT}" -scheme "${SCHEME}" \
       -destination "id=${UDID}" -derivedDataPath "${DERIVED}" >"${log}" 2>&1; then
    echo "❌ 构建失败，日志 ${log}"
    tail -20 "${log}" | sed 's/^/   | /'
    FAIL=$((FAIL + 1))
    return
  fi

  local app="${DERIVED}/Build/Products/Debug-iphonesimulator/LunisolarCalendar.app"
  if [[ ! -d "${app}" ]]; then
    app="$(find "${DERIVED}/Build/Products" -maxdepth 2 -name "LunisolarCalendar.app" -type d 2>/dev/null | head -1)"
  fi
  if [[ ! -d "${app}" ]]; then
    echo "❌ 构建产物里找不到 LunisolarCalendar.app"
    FAIL=$((FAIL + 1))
    return
  fi

  if ! xcrun simctl install "${UDID}" "${app}" >/tmp/shots-install.log 2>&1; then
    echo "❌ 安装失败，日志 /tmp/shots-install.log"
    FAIL=$((FAIL + 1))
    return
  fi
  echo "✅ 构建并安装完成"
  PASS=$((PASS + 1))
}

# ───────────────────────── 截图 ─────────────────────────

shot() {   # $1 = 文件名（不含输出目录）
  local path="${OUTDIR}/${1}"
  if xcrun simctl io "${UDID}" screenshot "${path}" >/dev/null 2>&1 && [[ -s "${path}" ]]; then
    echo "  📸 ${1}"
    SHOTS=$((SHOTS + 1))
  else
    echo "  ❌ 截图失败：${1}"
    FAIL=$((FAIL + 1))
  fi
}

# ───────────────────────── 模式 A：深链巡游 ─────────────────────────

deep_link_tour() {
  echo
  echo "──── 深链巡游 ────"

  xcrun simctl terminate "${UDID}" "${BUNDLE_ID}" >/dev/null 2>&1 || true

  # 冷启动要多等一会：1.5 秒时截图常常还停在启动图（空屏），不是界面
  if ! xcrun simctl launch "${UDID}" "${BUNDLE_ID}" \
       -AppleLanguages "${LANGUAGE}" -AppleLocale "${LOCALE}" >/tmp/shots-launch.log 2>&1; then
    echo "❌ 启动失败，日志 /tmp/shots-launch.log"
    FAIL=$((FAIL + 1))
    return
  fi
  sleep "${LAUNCH_SETTLE}"

  # 01 用 `qinghe://calendar` 而不是「冷启动后直接截」：App 的起始 Tab 会被上一轮的
  # 遗留状态影响（实测：手工塞过一次 pending-deeplink 后，冷启动会落在 AI 助手页），
  # 而深链是确定的 —— 截出来的「01-日历」必须是日历。
  step_url "qinghe://calendar"                "01-日历.png"
  step_url "qinghe://calendar/date/2026-09-25" "02-选中中秋.png"
  step_url "qinghe://ai"                      "03-AI助手.png"
  step_url "qinghe://calendar"                "04-回到日历.png"
}

step_url() {   # $1 = 深链（空则跳过、只截图） $2 = 文件名
  if [[ -n "${1}" ]]; then
    if ! xcrun simctl openurl "${UDID}" "${1}" >/tmp/shots-openurl.log 2>&1; then
      echo "  ❌ openurl 失败：${1}（日志 /tmp/shots-openurl.log）"
      FAIL=$((FAIL + 1))
      return
    fi
    sleep "${STEP_SLEEP}"
  fi
  shot "${2}"
}

# ───────────────────────── 模式 B：XCUITest 巡游 + 导出附件 ─────────────────────────

tour_mode() {
  echo
  echo "──── XCUITest 巡游 ────"

  local log="/tmp/shots-tour.log"
  rm -rf "${RESULT_BUNDLE}"
  if ! TEST_RUNNER_SHOTS=1 xcodebuild test -project "${PROJECT}" -scheme "${SCHEME}" \
       -destination "id=${UDID}" -derivedDataPath "${DERIVED}" \
       -resultBundlePath "${RESULT_BUNDLE}" \
       -only-testing:"${TOUR_TEST}" >"${log}" 2>&1; then
    echo "❌ 巡游用例失败，日志 ${log}"
    tail -20 "${log}" | sed 's/^/   | /'
    FAIL=$((FAIL + 1))
    return
  fi
  # 「没跳过」是这条路径的前提：若 SHOTS 没被转发，用例会被 skip、附件为空
  if ! grep -q "Test Case.*testScreenshotTour.*passed" "${log}"; then
    echo "❌ 巡游用例没有 passed（可能被跳过；检查 TEST_RUNNER_SHOTS 转发），日志 ${log}"
    grep -E "Test Case|Skipped|skipped" "${log}" | tail -5 | sed 's/^/   | /'
    FAIL=$((FAIL + 1))
    return
  fi
  echo "✅ 巡游用例 passed"
  PASS=$((PASS + 1))

  export_attachments
}

export_attachments() {
  rm -rf "${EXPORT_DIR}"
  mkdir -p "${EXPORT_DIR}"
  if ! xcrun xcresulttool export attachments \
       --path "${RESULT_BUNDLE}" --output-path "${EXPORT_DIR}" >/tmp/shots-export.log 2>&1; then
    echo "❌ 导出附件失败，日志 /tmp/shots-export.log"
    FAIL=$((FAIL + 1))
    return
  fi

  if [[ ! -f "${EXPORT_DIR}/manifest.json" ]]; then
    echo "❌ 导出目录里没有 manifest.json（${EXPORT_DIR}）"
    FAIL=$((FAIL + 1))
    return
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    echo "❌ 需要 python3 解析 manifest.json（macOS 装 Xcode 命令行工具即有）"
    echo "   附件已导出到 ${EXPORT_DIR}，可手工按 manifest.json 改名"
    FAIL=$((FAIL + 1))
    return
  fi

  echo "按 manifest.json 还原可读文件名："
  python3 - "${EXPORT_DIR}" "${OUTDIR}" <<'PY'
import json, os, re, shutil, sys

export_dir, out_dir = sys.argv[1], sys.argv[2]
with open(os.path.join(export_dir, "manifest.json"), encoding="utf-8") as fh:
    manifest = json.load(fh)

# 递归收集所有带 exportedFileName 的节点：manifest 的层级结构随 Xcode 版本变过，
# 按「有没有这个键」判定比按固定层级取更耐改。
found = []

def collect(node):
    if isinstance(node, dict):
        if "exportedFileName" in node:
            found.append(node)
            return
        for value in node.values():
            collect(value)
    elif isinstance(node, list):
        for value in node:
            collect(value)

collect(manifest)

used, copied = set(), 0
for item in found:
    src = os.path.join(export_dir, item["exportedFileName"])
    if not os.path.exists(src):
        print("  ⚠️  缺少导出文件：%s" % item["exportedFileName"])
        continue
    ext = os.path.splitext(item["exportedFileName"])[1] or ".png"
    raw = (item.get("suggestedHumanReadableName") or "").strip()
    # xcresulttool 会在人类可读名后面补「_<序号>_<附件 UUID>」做唯一化，
    # 那是 xcresult 的内部标识、不是我们要的文件名，去掉它才是 attachment.name 原文
    # （例：07-AI助手_0_125CEC2D-…-AC6A3B.png → 07-AI助手.png）。
    raw_stem, raw_ext = os.path.splitext(raw)
    raw = re.sub(r"_\d+_[0-9A-Fa-f]{8}-[0-9A-Fa-f-]{27}$", "", raw_stem) + raw_ext
    name = raw if raw and os.path.splitext(raw)[1] else (raw + ext if raw else item["exportedFileName"])
    name = name.replace("/", "-")
    stem, suffix = os.path.splitext(name)
    candidate, index = name, 2
    while candidate in used:
        candidate = "%s-%d%s" % (stem, index, suffix)
        index += 1
    used.add(candidate)
    shutil.copyfile(src, os.path.join(out_dir, candidate))
    copied += 1
    print("  %s → %s" % (item["exportedFileName"], candidate))

print("Copied %d" % copied)
PY
  local exported
  exported="$(find "${OUTDIR}" -maxdepth 1 -type f ! -name ".*" | wc -l | tr -d ' ')"
  if [[ "${exported}" -eq 0 ]]; then
    echo "❌ 导出后输出目录里没有任何附件（原始附件在 ${EXPORT_DIR}）"
    FAIL=$((FAIL + 1))
    return
  fi
  SHOTS="${exported}"
  echo "✅ 附件已导出并重命名（原始附件留档：${EXPORT_DIR}，结果包：${RESULT_BUNDLE}）"
  PASS=$((PASS + 1))
}

# ───────────────────────── 主流程 ─────────────────────────

mkdir -p "${OUTDIR}"

step_sim_state         # 缺审批表 / 有残留深链时先关机改掉，随后 step_boot 重启生效
step_boot
step_privacy            # 装之前先试一次（App 已存在时有效）
step_appearance
step_build_install
step_privacy            # 装完再授一次，确保这次启动不弹权限框
[[ "${TOUR}" == "1" ]] && step_appearance

if [[ "${TOUR}" == "1" ]]; then
  tour_mode
else
  deep_link_tour
fi

echo
echo "──────── 汇总 ────────"
echo "截图 ${SHOTS} 张 → ${OUTDIR}"
ls -la "${OUTDIR}" 2>/dev/null | sed 's/^/   /'
if [[ "${FAIL}" -gt 0 ]]; then
  echo "❌ 有 ${FAIL} 项失败（详见上方日志路径）"
  exit 1
fi
echo "✅ 全部完成"

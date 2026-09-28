#!/usr/bin/env bash
#
# 在 CI 里跑一条验证通道：完整输出落盘，失败时把编译诊断转成 Actions 注解。
#
# 为什么需要它：GitHub 现在要求登录才能查看 Actions 日志（未登录只看到
# "Sign in to view logs"，API 也返回 403），而 workflow 生成的 ::error:: 注解
# 是**公开可读**的。把 error 行转成注解，CI 失败的原因不必登录 GitHub 就能定位——
# 本项目第一次 CI 失败（2026-09-27，macos-15 默认 Xcode 16.4）正是卡在这一点上：
# 只知道「swift build 退出码 1」，拿不到任何编译诊断。
#
# 用法：
#   Tools/ci_run_channel.sh macos swift build
#   Tools/ci_run_channel.sh ios-sdk swift build --triple ... --sdk ...
#
# 行为：
# - 命令的完整输出写进 $RUNNER_TEMP/ci.<通道名>.log（本地跑则落 /tmp）；
# - 失败时终端只打印 error 行摘要（不刷屏），并逐条发 ::error:: 注解；
# - 通过了就只打一行，退出码透传。

set -uo pipefail

name="${1:?用法: ci_run_channel.sh <通道名> <命令...>}"
shift
[ $# -gt 0 ] || { echo "缺少要执行的命令" >&2; exit 2; }

log="${RUNNER_TEMP:-/tmp}/ci.${name}.log"
max_annotations=8

if "$@" >"$log" 2>&1; then
  echo "✅ ${name} 通过"
  exit 0
fi

echo "❌ ${name} 失败，完整日志：${log}（需要登录 GitHub 才能看 job 日志，注解无需登录）"

# 注解里的 % \r \n 必须转义，否则 GitHub 会把整条注解截断或错位。
escape() {
  local s="$1"
  s="${s//'%'/'%25'}"
  s="${s//$'\r'/'%0D'}"
  s="${s//$'\n'/'%0A'}"
  printf '%s' "$s"
}

emit() { printf '::error::%s\n' "$(escape "$1")"; }

count=0
while IFS= read -r line; do
  echo "   $line"
  emit "$line"
  count=$((count + 1))
  [ "$count" -ge "$max_annotations" ] && break
done < <(grep -aE "error:|fatal error:" "$log")

# 没有 "error:" 行也要有注解，否则失败会变成「无声」——退化成最后几行原文。
if [ "$count" -eq 0 ]; then
  emit "${name} 失败（退出码非零），日志里没有 error: 行；末尾 3 行如下"
  while IFS= read -r line; do
    emit "$line"
  done < <(tail -3 "$log" | grep -av '^$')
fi

exit 1

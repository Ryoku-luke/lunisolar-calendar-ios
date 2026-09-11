#!/usr/bin/env bash
# ================================================================
#  gen-app-icons.sh
#  —— 生成 iOS 应用图标所有档位 PNG 到 Xcode Asset Catalog ——
#
#  用法 (macOS)：
#     bash Tools/gen-app-icons.sh
#
#  依赖：macOS 自带的 sips (Scriptable Image Processing System)
#  若已安装 ImageMagick，会同时用它把 alpha 通道去掉，避免
#  App Store Connect 上传时报 ITMS-90717：
#    "Invalid App Store Icon — The App Store Icon can't be transparent"
#
#  输入（仓库约定路径，可通过环境变量覆盖）：
#     ${PRIMARY_SRC:-Assets/Brand/app-icon-primary.jpg}
#     ${SPRING_SRC:-Assets/Brand/app-icon-spring-festival.jpg}
#
#  输出（直接写入对应的 .appiconset 目录）：
#     Assets/XCAssets/AppIcon.appiconset/Icon-*.png
#     Assets/XCAssets/AppIconSpringFestival.appiconset/Icon-*.png
# ================================================================

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PRIMARY_SRC="${PRIMARY_SRC:-$ROOT_DIR/Assets/Brand/app-icon-primary.jpg}"
SPRING_SRC="${SPRING_SRC:-$ROOT_DIR/Assets/Brand/app-icon-spring-festival.jpg}"

OUT_PRIMARY="$ROOT_DIR/Assets/XCAssets/AppIcon.appiconset"
OUT_SPRING="$ROOT_DIR/Assets/XCAssets/AppIconSpringFestival.appiconset"

# iOS AppIcon 全部档位 (逻辑尺寸 @1x, scale 由后缀承载)
# 格式：文件名 | 像素边长
# 一个 entry 一条记录，sips 直接缩到像素边长（sips -z H W 等比缩放）
declare -a SIZES=(
  "Icon-20.png       20"
  "Icon-20@2x.png    40"
  "Icon-20@3x.png    60"
  "Icon-29.png       29"
  "Icon-29@2x.png    58"
  "Icon-29@3x.png    87"
  "Icon-40.png       40"
  "Icon-40@2x.png    80"
  "Icon-40@3x.png   120"
  "Icon-60@2x.png   120"
  "Icon-60@3x.png   180"
  "Icon-76.png       76"
  "Icon-76@2x.png   152"
  "Icon-83.5@2x.png 167"
  "Icon-1024.png   1024"
)

log()  { printf '\033[1;36m[gen-app-icons]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m           %s\n' "$*" >&2; }

if [[ "$(uname -s)" != "Darwin" ]]; then
  warn "sips 仅在 macOS 上可用，当前是 $(uname -s)。"
  warn "你可以在 macOS 上运行此脚本，或用 ImageMagick / pillow 手动缩放到以下像素："
  for row in "${SIZES[@]}"; do echo "   $row"; done
  exit 1
fi

if [[ ! -f "$PRIMARY_SRC" ]]; then
  echo "主图标源图不存在：$PRIMARY_SRC" >&2; exit 1
fi
if [[ ! -f "$SPRING_SRC" ]]; then
  echo "春节限定源图不存在：$SPRING_SRC" >&2; exit 1
fi

mkdir -p "$OUT_PRIMARY" "$OUT_SPRING"

# 为后续 .pbxproj / pbxproj 资源同步打印期望的 PBXBuildFile / Resources 参考
# （详情见 README 的「Xcode 集成」章节；此处不修改项目文件）

generate_one() {
  local src="$1"
  local out_dir="$2"
  local name="$3"
  log "→ 生成 $name 到 $out_dir"
  for row in "${SIZES[@]}"; do
    local filename pixels
    filename="$(echo "$row" | awk '{print $1}')"
    pixels="$(echo "$row"   | awk '{print $2}')"
    local dst="$out_dir/$filename"
    sips -Z "$pixels" \
         --setProperty format png \
         "$src" \
         --out "$dst" > /dev/null
    # 去掉 alpha 通道，避免 App Store Connect 的 1024 图标被拒
    if command -v magick > /dev/null 2>&1; then
      magick "$dst" -background white -flatten "$dst"
    elif command -v convert > /dev/null 2>&1; then
      convert "$dst" -background white -flatten "$dst"
    else
      # 用 macOS 内置 sips 的 matchAll / hasAlpha 策略保守处理：
      # sips -b 已移除 alpha 合成开关，因此 1024 档位若出现透明，
      # 仍建议上传前用 Preview.app 导出时取消勾选 Alpha。
      :
    fi
  done
}

generate_one "$PRIMARY_SRC" "$OUT_PRIMARY" "主图标 AppIcon"
generate_one "$SPRING_SRC"  "$OUT_SPRING"  "春节限定 AppIconSpringFestival"

# ---- 校验 ----
log "校验 AppIcon.appiconset 档位覆盖率…"
missing=0
for row in "${SIZES[@]}"; do
  f="$(echo "$row" | awk '{print $1}')"
  for dir in "$OUT_PRIMARY" "$OUT_SPRING"; do
    if [[ ! -f "$dir/$f" ]]; then
      warn "缺失：$dir/$f"; missing=$((missing+1))
    fi
  done
done
if (( missing > 0 )); then
  echo "共缺失 $missing 个文件，生成失败。" >&2; exit 1
fi

log "完成 ✔"
echo
echo "   主图标目录   : $OUT_PRIMARY"
echo "   春节限定目录 : $OUT_SPRING"
echo
echo "下一步：将 Assets/XCAssets 目录整体拖入 Xcode 工程，"
echo "        勾选 Copy items if needed + Create groups，"
echo "        在工程 TARGETS → General → App Icons and Launch Screen"
echo "        把 App Icon Source 选为 AppIcon，"
echo "        春节限定版通过 Info.plist 的 CFBundleIcons 声明（见 Assets/XCAssets/Info.plist-EXAMPLE.xml）。"

#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
source_dir="$repo_root/design/app-icon/option-2-lens"
output_dir="$repo_root/App/Resources/Assets.xcassets/AppIcon.appiconset"
chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
srgb_profile="/System/Library/ColorSync/Profiles/sRGB Profile.icc"

if [ ! -x "$chrome" ]; then
  echo "Google Chrome is required at $chrome" >&2
  exit 1
fi

tmp_dir=$(mktemp -d /tmp/picsee-app-icon.XXXXXX)
cleanup() {
  rm -f "$tmp_dir/icon-default.png" "$tmp_dir/icon-small.png"
  rmdir "$tmp_dir" 2>/dev/null || true
}
trap cleanup EXIT HUP INT TERM

render_source() {
  source_svg=$1
  output_png=$2
  "$chrome" \
    --headless=new \
    --disable-gpu \
    --hide-scrollbars \
    --default-background-color=00000000 \
    --force-device-scale-factor=1 \
    --run-all-compositor-stages-before-draw \
    --virtual-time-budget=1000 \
    --window-size=1024,1024 \
    --screenshot="$output_png" \
    "file://$source_dir/raster.html?src=$source_svg" >/dev/null 2>&1
}

resize() {
  source_png=$1
  pixels=$2
  filename=$3
  sips --resampleHeightWidth "$pixels" "$pixels" \
    --matchTo "$srgb_profile" \
    "$source_png" \
    --out "$output_dir/$filename" >/dev/null
}

mkdir -p "$output_dir"
render_source icon-small.svg "$tmp_dir/icon-small.png"
render_source icon-default.svg "$tmp_dir/icon-default.png"
resize "$tmp_dir/icon-small.png" 16 app-icon-16.png
resize "$tmp_dir/icon-small.png" 32 app-icon-16@2x.png
resize "$tmp_dir/icon-small.png" 32 app-icon-32.png
resize "$tmp_dir/icon-default.png" 64 app-icon-32@2x.png
resize "$tmp_dir/icon-default.png" 128 app-icon-128.png
resize "$tmp_dir/icon-default.png" 256 app-icon-128@2x.png
resize "$tmp_dir/icon-default.png" 256 app-icon-256.png
resize "$tmp_dir/icon-default.png" 512 app-icon-256@2x.png
resize "$tmp_dir/icon-default.png" 512 app-icon-512.png
resize "$tmp_dir/icon-default.png" 1024 app-icon-512@2x.png

echo "Rasterized AppIcon.appiconset from Lens SVG sources."

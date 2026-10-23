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
  rm -f \
    "$tmp_dir/icon-default.png" \
    "$tmp_dir/icon-small-16.png" \
    "$tmp_dir/icon-small-32.png"
  rmdir "$tmp_dir" 2>/dev/null || true
}
trap cleanup EXIT HUP INT TERM

render_source() {
  source_svg=$1
  output_png=$2
  pixels=$3
  "$chrome" \
    --headless=new \
    --disable-gpu \
    --hide-scrollbars \
    --default-background-color=00000000 \
    --force-device-scale-factor=1 \
    --run-all-compositor-stages-before-draw \
    --virtual-time-budget=1000 \
    --window-size="$pixels,$pixels" \
    --screenshot="$output_png" \
    "file://$source_dir/raster.html?src=$source_svg" >/dev/null 2>&1
}

tag_srgb() {
  source_png=$1
  filename=$2
  sips --embedProfile "$srgb_profile" \
    "$source_png" \
    --out "$output_dir/$filename" >/dev/null
}

resize_large() {
  source_png=$1
  pixels=$2
  filename=$3
  sips --resampleHeightWidth "$pixels" "$pixels" \
    --matchTo "$srgb_profile" \
    "$source_png" \
    --out "$output_dir/$filename" >/dev/null
}

mkdir -p "$output_dir"
render_source icon-small.svg "$tmp_dir/icon-small-16.png" 16
render_source icon-small.svg "$tmp_dir/icon-small-32.png" 32
render_source icon-default.svg "$tmp_dir/icon-default.png" 1024
tag_srgb "$tmp_dir/icon-small-16.png" app-icon-16.png
tag_srgb "$tmp_dir/icon-small-32.png" app-icon-16@2x.png
tag_srgb "$tmp_dir/icon-small-32.png" app-icon-32.png
resize_large "$tmp_dir/icon-default.png" 64 app-icon-32@2x.png
resize_large "$tmp_dir/icon-default.png" 128 app-icon-128.png
resize_large "$tmp_dir/icon-default.png" 256 app-icon-128@2x.png
resize_large "$tmp_dir/icon-default.png" 256 app-icon-256.png
resize_large "$tmp_dir/icon-default.png" 512 app-icon-256@2x.png
resize_large "$tmp_dir/icon-default.png" 512 app-icon-512.png
resize_large "$tmp_dir/icon-default.png" 1024 app-icon-512@2x.png

echo "Rasterized AppIcon.appiconset from Lens SVG sources."

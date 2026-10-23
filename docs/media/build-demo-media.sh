#!/bin/sh
set -eu

# Build short, clearly labelled UI-flow previews from the redacted device screenshots.
# These are animation mockups of navigation and states; they are not videos of a live
# transaction, water flow, payment, or washing-machine start.

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
SHOTS=${SCREENSHOTS_DIR:-"$ROOT/docs/screenshots"}
OUT=$ROOT/docs/media
mkdir -p "$OUT"

swift "$ROOT/docs/media/make-caption.swift" "$OUT/footer.png" 540 54 14 \
  '界面流程演示 · 实际交易与设备状态以现场为准'
swift "$ROOT/docs/media/make-caption.swift" "$OUT/water-title.png" 540 72 25 \
  '校日常 · 热水流程'
swift "$ROOT/docs/media/make-caption.swift" "$OUT/laundry-title.png" 540 72 25 \
  '校日常 · 洗衣流程'
swift "$ROOT/docs/media/make-caption.swift" "$OUT/setup-title.png" 540 72 25 \
  '校日常 · 首次配置'

render() {
  name=$1
  title_image=$2
  first=$3
  second=$4
  third=$5

  ffmpeg -hide_banner -loglevel error -y \
    -loop 1 -t 3 -i "$first" \
    -loop 1 -t 3 -i "$second" \
    -loop 1 -t 3 -i "$third" \
    -loop 1 -t 8 -i "$title_image" \
    -loop 1 -t 8 -i "$OUT/footer.png" \
    -filter_complex "\
      [0:v]scale=540:1174,setsar=1,format=rgba[v0];\
      [1:v]scale=540:1174,setsar=1,format=rgba[v1];\
      [2:v]scale=540:1174,setsar=1,format=rgba[v2];\
      [v0][v1]xfade=transition=fade:duration=0.45:offset=2.55[x1];\
      [x1][v2]xfade=transition=fade:duration=0.45:offset=5.10[x2];\
      [x2][3:v]overlay=0:0[x3];\
      [x3][4:v]overlay=0:H-h,\
      fps=12,split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=bayer" \
    -t 8 -loop 0 "$OUT/$name.gif"

  ffmpeg -hide_banner -loglevel error -y \
    -loop 1 -t 3 -i "$first" \
    -loop 1 -t 3 -i "$second" \
    -loop 1 -t 3 -i "$third" \
    -loop 1 -t 8 -i "$title_image" \
    -loop 1 -t 8 -i "$OUT/footer.png" \
    -filter_complex "\
      [0:v]scale=540:1174,setsar=1,format=yuv420p[v0];\
      [1:v]scale=540:1174,setsar=1,format=yuv420p[v1];\
      [2:v]scale=540:1174,setsar=1,format=yuv420p[v2];\
      [v0][v1]xfade=transition=fade:duration=0.45:offset=2.55[x1];\
      [x1][v2]xfade=transition=fade:duration=0.45:offset=5.10[x2];\
      [x2][3:v]overlay=0:0[x3];\
      [x3][4:v]overlay=0:H-h[v]" \
    -map '[v]' -t 8 -r 24 -c:v libx264 -pix_fmt yuv420p -movflags +faststart \
    "$OUT/$name.mp4"
}

"$ROOT/docs/media/render-demo-media.sh"

printf 'Generated demo media in %s\n' "$OUT"

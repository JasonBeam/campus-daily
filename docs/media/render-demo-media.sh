#!/bin/sh
set -eu

# Render existing redacted screenshots and generated title/footer images.
# Callers may provide FFMPEG=/absolute/path/to/ffmpeg.

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
SHOTS=${SCREENSHOTS_DIR:-"$ROOT/docs/screenshots"}
OUT=$ROOT/docs/media
FFMPEG=${FFMPEG:-ffmpeg}

render() {
  name=$1
  title_image=$2
  first=$3
  second=$4
  third=$5

  "$FFMPEG" -hide_banner -loglevel error -y \
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

  "$FFMPEG" -hide_banner -loglevel error -y \
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

render water-flow-demo "$OUT/water-title.png" \
  "$SHOTS/home.png" "$SHOTS/water.png" "$SHOTS/water.png"

render laundry-flow-demo "$OUT/laundry-title.png" \
  "$SHOTS/home.png" "$SHOTS/laundry.png" "$SHOTS/review.png"

render setup-flow-demo "$OUT/setup-title.png" \
  "$SHOTS/home.png" "$SHOTS/settings.png" "$SHOTS/settings.png"

#!/bin/sh
set -eu

# Build short, clearly labelled UI-flow previews from the redacted device screenshots.
# These are animation mockups of navigation and states; they are not videos of a live
# transaction, water flow, payment, or washing-machine start.

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../../.." && pwd)
OUT=$ROOT/docs/media/0.7.0/demo
mkdir -p "$OUT"

swift "$ROOT/docs/media/0.7.0/demo/make-caption.swift" "$OUT/footer.png" 540 54 14 \
  '界面流程演示 · 实际交易与设备状态以现场为准'
swift "$ROOT/docs/media/0.7.0/demo/make-caption.swift" "$OUT/water-title.png" 540 72 25 \
  '校日常 · 热水流程'
swift "$ROOT/docs/media/0.7.0/demo/make-caption.swift" "$OUT/laundry-title.png" 540 72 25 \
  '校日常 · 洗衣流程'
swift "$ROOT/docs/media/0.7.0/demo/make-caption.swift" "$OUT/setup-title.png" 540 72 25 \
  '校日常 · 首次配置'

"$ROOT/docs/media/0.7.0/demo/render-demo-media.sh"

printf 'Generated demo media in %s\n' "$OUT"

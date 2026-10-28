#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -z "${JAVA_HOME:-}" && "$(uname -s)" == "Darwin" ]]; then
  JAVA_HOME="$(/usr/libexec/java_home -v 21)"
  export JAVA_HOME
fi
cd "$project_root/platforms/android"
./gradlew :app:assembleDebug :app:testDebugUnitTest :app:lintDebug --console=plain "-PcampusSharedAssetsDir=$project_root/Shared" "$@"
apk="$PWD/app/build/outputs/apk/debug/app-debug.apk"
ls -lh "$apk"
shasum -a 256 "$apk"

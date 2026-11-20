#!/usr/bin/env bash
# Dựng gói Glass 6 (.deb) trên máy Ubuntu có Theos + Rust nightly: lõi Rust (crate g6-ffi → libg6_ffi.a, g6-ctl → libg6_ctl.a),
# rồi make package.
#   bash tools/build.sh                    bản thử (có tweak/Debug/; glass6ctl cho đổi nguồn cập nhật để thử OTA)
#   bash tools/build.sh FINALPACKAGE=1     bản phát hành
# Thư mục dựng của lõi nằm cạnh repo (<thư mục chứa repo>/target-ios) nên chép mã mới lên vẫn dựng lại nhanh.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${CARGO_TARGET_DIR:-$(cd "$ROOT/.." && pwd)/target-ios}"
# Bản thử: glass6ctl nhận nguồn cập nhật thử (feature test-source). Bản phát hành: nguồn cố định, chỉ HTTPS.
FEATURES=(--features g6-ctl/test-source)
for arg in "$@"; do
    [[ "$arg" == FINALPACKAGE=1 ]] && FEATURES=()
done
cd "$ROOT/core"
CARGO_TARGET_DIR="$OUT" bash "$ROOT/tools/rust/cargo-ios6.sh" build --release -p g6-ffi -p g6-ctl ${FEATURES[@]+"${FEATURES[@]}"}
ls -la "$OUT/armv7-apple-ios6/release/libg6_ffi.a" "$OUT/armv7-apple-ios6/release/libg6_ctl.a"
cd "$ROOT"
export THEOS="${THEOS:-$HOME/theos}"
rm -f packages/*.deb
make package CORE_LIB_DIR="$OUT/armv7-apple-ios6/release" "$@"
ls -la packages/*.deb

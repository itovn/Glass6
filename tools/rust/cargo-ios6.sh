#!/usr/bin/env bash
# cargo cho iOS 6 (armv7, target tự định nghĩa armv7-apple-ios6.json — Cortex-A8 + NEON) trên máy Ubuntu có Theos + Rust nightly
# (rust-src). Chép từ Côn Bằng TV Legacy / GramMini (tools/rust/cargo-ios6.sh). glass6ctl dùng rustls (OTA qua HTTPS) → ring vá
# cho ARM 32-bit của Apple (vendor-ring.sh), để ngoài thư mục mã (<thư mục chứa repo>/vendor) nên chép mã mới lên không phải vá lại.
#   bash tools/rust/cargo-ios6.sh build --release -p g6-ffi -p g6-ctl        (chạy trong core/)
# Tự thêm: -Z build-std (thư viện chuẩn dựng lại cho target), --target, bản ring đã vá.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
THEOS="${THEOS:-$HOME/theos}"
TC="$THEOS/toolchain/linux/iphone/bin"
SDKROOT="$THEOS/sdks/iPhoneOS9.3.sdk"
export SDKROOT
# Giữ đúng cấu hình đã chạy thật ở hai dự án kia (5.0); tệp đối tượng dựng cho 5.0 chạy trên iOS 6 bình thường
export IPHONEOS_DEPLOYMENT_TARGET=5.0
. "$HOME/.cargo/env"
RING_VER=0.17.14
RING_BASE="${RING_BASE:-$(cd "$ROOT/.." && pwd)/vendor}"
RING="$RING_BASE/ring-$RING_VER"
if [[ ! -d "$RING" ]]; then
    # Lần đầu: cần mã ring trong ~/.cargo/registry (cargo fetch tải về), rồi vá
    ls -d "$HOME"/.cargo/registry/src/*/ring-"$RING_VER" >/dev/null 2>&1 || (cd "$ROOT/core" && cargo +nightly fetch >/dev/null)
    RING_DST="$RING_BASE" bash "$ROOT/tools/rust/vendor-ring.sh" "$RING_VER" >/dev/null
fi
# Mã C trong các crate (ring) dựng bằng clang của Theos
export CC_armv7_apple_ios6="$TC/clang"
export CFLAGS_armv7_apple_ios6="-target armv7-apple-ios5.0 -isysroot $SDKROOT -mcpu=cortex-a8"
export AR_armv7_apple_ios6="$TC/llvm-ar"
cmd="$1"
shift
exec cargo +nightly "$cmd" \
    -Z build-std=std,panic_abort \
    -Z json-target-spec \
    --target "$ROOT/tools/rust/armv7-apple-ios6.json" \
    --config "patch.crates-io.ring.path=\"$RING\"" \
    "$@"

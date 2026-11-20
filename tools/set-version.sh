#!/usr/bin/env bash
# Đặt số bản ở mọi chỗ ghi số bản (dạng a.b.c):
#   bash tools/set-version.sh 1.0.0
#   control                        số bản của gói — nguồn chính (tweak và bảng Cài đặt đọc từ đây lúc dựng: G6_VERSION)
#   core/Cargo.toml, Cargo.lock    số bản của lõi; glass6ctl dùng nó làm «bản đang cài» khi hỏi bản mới
#   prefs/Resources/Info.plist     CFBundleShortVersionString của bảng Cài đặt
# tools/build-release.sh từ chối dựng nếu ba chỗ lệch nhau.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
V="${1:?cách dùng: set-version.sh <bản, vd 1.0.0>}"
[[ "$V" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "số bản phải có dạng a.b.c (vd 1.0.0)" >&2; exit 1; }
cd "$ROOT"
sed -i "s/^Version: .*/Version: $V/" control
# Dòng «version = …» đầu tiên của core/Cargo.toml là [workspace.package]
sed -i "0,/^version = \".*\"/s//version = \"$V\"/" core/Cargo.toml
sed -i "/^name = \"g6-\(core\|ffi\|ctl\)\"\$/{n;s/^version = \".*\"/version = \"$V\"/}" core/Cargo.lock
sed -i "/CFBundleShortVersionString/{n;s/<string>.*<\/string>/<string>$V<\/string>/}" prefs/Resources/Info.plist
grep -n "^Version:" control
grep -n -m1 "^version = " core/Cargo.toml
grep -n -A1 "^name = \"g6-" core/Cargo.lock | grep version
grep -n -A1 CFBundleShortVersionString prefs/Resources/Info.plist | grep string

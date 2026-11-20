#!/usr/bin/env bash
# Dựng bản phát hành của Glass 6 (không có công cụ thử tweak/Debug/, glass6ctl chỉ nhận nguồn cập nhật thật) trên máy Ubuntu có
# Theos + Rust nightly:
#   bash tools/build-release.sh
# → packages/vn.glass6.tweak_<bản>_iphoneos-arm.deb (số bản lấy từ control; đổi số bản bằng tools/set-version.sh)
#   packages/symlist-<bản>.txt — ký hiệu mọi tệp chạy cần ở hệ thống; tra trên máy iOS 6 trước khi phát hành:
#       cat packages/symlist-<bản>.txt | ssh root@<máy> cbsymcheck
# Sau đó (trên máy phát hành, nơi giữ khoá): tools/sign-release.sh, tools/update-cydia-repo.sh + tools/sign-cydia-repo.sh.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
VERSION="$(sed -n 's/^Version: *//p' control)"
CARGO_VERSION="$(grep -m1 '^version = ' core/Cargo.toml | sed 's/.*"\(.*\)".*/\1/')"
PLIST_VERSION="$(grep -A1 CFBundleShortVersionString prefs/Resources/Info.plist | sed -n 's/.*<string>\(.*\)<\/string>.*/\1/p')"
if [[ "$VERSION" != "$CARGO_VERSION" || "$VERSION" != "$PLIST_VERSION" ]]; then
    echo "Số bản lệch nhau: control $VERSION, core/Cargo.toml $CARGO_VERSION, Info.plist $PLIST_VERSION — chạy tools/set-version.sh" >&2
    exit 1
fi
# Chứng chỉ OTA và khoá của nguồn Cydia phải có trong mã (bản thiếu chúng không tự cập nhật được)
[[ -s helper/ota_cert.h && -s layout/etc/apt/trusted.gpg.d/vn.glass6.gpg ]] || { echo "thiếu helper/ota_cert.h hoặc khoá của nguồn Cydia" >&2; exit 1; }
make clean >/dev/null 2>&1 || true
rm -rf .theos/_
bash tools/build.sh FINALPACKAGE=1
S=.theos/_
# Bản phát hành không được còn mã thử
for f in "$S/Library/MobileSubstrate/DynamicLibraries/Glass6SB.dylib" "$S/Library/MobileSubstrate/DynamicLibraries/Glass6UI.dylib"; do
    if strings "$f" | grep -q "vn.glass6/debug"; then
        echo "LỖI: $f còn công cụ thử (Debug/)" >&2
        exit 1
    fi
done
if strings "$S/usr/bin/glass6ctl" | grep -q "update-source.txt"; then
    echo "LỖI: glass6ctl còn nhận nguồn cập nhật thử (feature test-source)" >&2
    exit 1
fi
DEB="packages/vn.glass6.tweak_${VERSION}_iphoneos-arm.deb"
[[ -f "$DEB" ]] || { echo "không thấy $DEB" >&2; ls packages >&2; exit 1; }
LIST="packages/symlist-$VERSION.txt"
: > "$LIST"
for f in "$S/Library/MobileSubstrate/DynamicLibraries/Glass6SB.dylib" "$S/Library/MobileSubstrate/DynamicLibraries/Glass6UI.dylib" \
         "$S/usr/lib/libglass6core.dylib" "$S/Library/PreferenceBundles/Glass6Prefs.bundle/Glass6Prefs" \
         "$S/usr/libexec/glass6/g6svc" "$S/usr/libexec/glass6/g6update" "$S/usr/bin/glass6ctl"; do
    python3 tools/symlist.py "$f" >> "$LIST"
done
sort -u -o "$LIST" "$LIST"
ls -la "$DEB"
sha256sum "$DEB"
echo "Ký hiệu cần tra trên máy iOS 6: $LIST ($(wc -l < "$LIST") dòng) — cat $LIST | ssh root@<máy> cbsymcheck"

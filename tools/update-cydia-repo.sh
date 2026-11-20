#!/usr/bin/env bash
# Tạo / cập nhật nguồn Cydia (APT phẳng) trong thư mục cydia/ của trang giới thiệu (nhánh gh-pages của itovn/Glass6):
#   bash tools/update-cydia-repo.sh <thư mục trang>/cydia <tệp .deb mới>…
# Chép .deb vào cydia/debs (giữ 3 bản mới nhất), tạo Packages(.gz/.bz2) bằng dpkg-scanpackages (thêm Depiction / Homepage nếu
# gói chưa có) và Release (MD5 + SHA256).
# Nguồn trong Cydia: https://itovn.github.io/Glass6/cydia/  (dòng APT: deb https://itovn.github.io/Glass6/cydia/ ./)
# Cần dpkg-dev (dpkg-scanpackages), gzip, bzip2 — chạy trên máy Linux dựng. Xong thì ký trên máy phát hành (khoá GPG không nằm
# trên máy dựng): bash tools/sign-cydia-repo.sh <thư mục cydia> → Release.gpg + InRelease.
set -euo pipefail
REPO="${1:?thư mục cydia/}"
shift
SITE="https://itovn.github.io/Glass6"
mkdir -p "$REPO/debs"
for d in "$@"; do
    cp "$d" "$REPO/debs/"
done
cd "$REPO"
# Giữ 3 bản mới nhất (theo số bản trong tên tệp)
ls debs/*.deb | sort -V | head -n -3 | xargs -r rm -f
dpkg-scanpackages -m debs /dev/null 2>/dev/null |
    awk -v dep="Depiction: $SITE/cydia/depiction.html" -v home="Homepage: $SITE/" '
        /^Depiction: / { hasdep = 1 } /^Homepage: / { hashome = 1 }
        /^$/ { if (!hasdep) print dep; if (!hashome) print home; hasdep = hashome = 0; print; next }
        { print }' > Packages.utf8
# Cydia 1.1.30 trên iOS 6 đọc Description qua apt với bảng mã US-ASCII → chữ có dấu thành «?». Bỏ dấu cả tệp cho chắc (tệp
# control của gói vốn đã viết không dấu; tên gói, link vốn là ASCII).
iconv -f UTF-8 -t ASCII//TRANSLIT Packages.utf8 > Packages
rm -f Packages.utf8
gzip -9nc Packages > Packages.gz
bzip2 -9c Packages > Packages.bz2
{
    cat <<'EOF'
Origin: Glass 6
Label: Glass 6
Suite: stable
Version: 1.0
Codename: ios6
Architectures: iphoneos-arm
Components: main
Description: Glass 6 - Liquid Glass (iOS 26) cho iOS 6 da jailbreak - https://itovn.github.io/Glass6/
EOF
    echo "MD5Sum:"
    for f in Packages Packages.gz Packages.bz2; do echo " $(md5sum "$f" | cut -d' ' -f1) $(stat -c %s "$f") $f"; done
    echo "SHA256:"
    for f in Packages Packages.gz Packages.bz2; do echo " $(sha256sum "$f" | cut -d' ' -f1) $(stat -c %s "$f") $f"; done
} > Release
echo "Nguồn Cydia: $(grep -c '^Package:' Packages) gói"
grep -E '^(Package|Version|Filename|Size|Depiction):' Packages

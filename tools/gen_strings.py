#!/usr/bin/env python3
# gen_strings.py — bảng dịch Việt → Anh của Glass 6.
#
# Mọi chuỗi hiển thị trong mã viết bằng tiếng Việt; bản tiếng Anh nằm ở data/strings-en.txt. Công cụ này:
#   1. gom mọi chuỗi cần dịch từ nguồn:
#        prefs/Resources/Root.plist      nhãn, chú thích cuối nhóm, tên lựa chọn
#        prefs/*.m, tweak/**/*.m         các lời gọi G6L(@"…") (kể cả nhiều chuỗi liền nhau)
#        data/services.tsv               tên + ghi chú dịch vụ
#        core/…/assist.rs                tên chức năng của nút AssistiveTouch
#   2. đọc data/strings-en.txt (mỗi mục: «# <chuỗi tiếng Việt>» rồi «<mã> = <bản tiếng Anh>»; mã = 8 ký tự đầu SHA-1 của chuỗi
#      tiếng Việt — chuỗi tiếng Việt đổi thì mã đổi, bản dịch cũ bị coi là thiếu: đúng ý, phải dịch lại);
#   3. ghi prefs/Resources/Strings-en.plist (từ điển Việt → Anh mà tweak/Common/G6Lang.m nạp);
#   4. ghi lại data/strings-en.txt theo đúng thứ tự nguồn, thêm mục trống cho chuỗi chưa dịch, bỏ mục không còn dùng;
#   5. in các chuỗi chưa dịch và thoát mã 1 nếu còn thiếu.
# Chạy ở máy phát triển mỗi khi thêm / sửa chuỗi:  python tools/gen_strings.py   (thêm --list để in danh sách đánh số)
import hashlib, io, os, plistlib, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data", "strings-en.txt")
OUT = os.path.join(ROOT, "prefs", "Resources", "Strings-en.plist")

def read(path):
    return io.open(os.path.join(ROOT, path), encoding="utf-8").read()

LIT = r'@"((?:[^"\\\n]|\\.)*)"'
CALL = re.compile(r'G6L\(\s*((?:' + LIT + r'\s*)+)\)')
ESC = {"n": "\n", "t": "\t", '"': '"', "\\": "\\"}

def unescape(s):
    return re.sub(r"\\(.)", lambda m: ESC.get(m.group(1), m.group(1)), s)

def collect():
    keys = []
    def add(s):
        if isinstance(s, str) and s and s not in keys:
            keys.append(s)
    with open(os.path.join(ROOT, "prefs", "Resources", "Root.plist"), "rb") as f:
        root = plistlib.load(f)
    for item in root["items"]:
        add(item.get("label")); add(item.get("footerText")); add(item.get("g6FooterPhone"))
        for k in ("validTitles", "titles", "shortTitles"):
            for t in item.get(k) or []:
                add(t)
    sources = []
    for base in ("prefs", "tweak"):
        for dirpath, _, names in os.walk(os.path.join(ROOT, base)):
            for n in sorted(names):
                if n.endswith(".m"):
                    sources.append(os.path.join(dirpath, n))
    for path in sorted(sources):
        text = io.open(path, encoding="utf-8").read()
        for m in CALL.finditer(text):
            add("".join(unescape(p) for p in re.findall(LIT, m.group(1))))
    for line in read("data/services.tsv").splitlines():
        if line.startswith("#") or not line.strip():
            continue
        cols = line.split("\t")
        if len(cols) >= 5:
            add(cols[3].strip()); add(cols[4].strip())
    for m in re.finditer(r'action\(\s*(?:[A-Z]+|"[a-z]+")\s*,\s*"([^"]*)"\s*,\s*"([^"]*)"', read("core/crates/g6-core/src/assist.rs")):
        add(m.group(1)); add(m.group(2))
    return keys

def ident(s):
    return hashlib.sha1(s.encode("utf-8")).hexdigest()[:8]

def needs_translation(s):
    # giờ («16:00»), số: không cần dịch
    return not re.fullmatch(r"[0-9:., ]+", s)

def enc(s):
    return s.replace("\\", "\\\\").replace("\n", "\\n")

def dec(s):
    return re.sub(r"\\(.)", lambda m: "\n" if m.group(1) == "n" else m.group(1), s)

def load():
    table = {}
    if os.path.exists(DATA):
        for line in io.open(DATA, encoding="utf-8").read().splitlines():
            m = re.match(r"^([0-9a-f]{8}) = ?(.*)$", line)
            if m:
                table[m.group(1)] = dec(m.group(2))
    return table

HEADER = """# Bảng dịch Việt → Anh của Glass 6 — nguồn của prefs/Resources/Strings-en.plist (python tools/gen_strings.py).
# Mỗi mục hai dòng: «# <chuỗi tiếng Việt>» (chỉ để đọc, công cụ tự ghi lại) rồi «<mã> = <bản tiếng Anh>».
# Xuống dòng trong chuỗi viết là \\n. Mục để trống = chưa dịch (hiển thị nguyên tiếng Việt).
"""

def main():
    keys = [k for k in collect() if needs_translation(k)]
    if "--list" in sys.argv:
        for i, k in enumerate(keys):
            print("%3d %s %s" % (i, ident(k), enc(k)))
        return 0
    table = load()
    used, missing, english = set(), [], {}
    lines = [HEADER]
    for k in keys:
        i = ident(k); used.add(i)
        en = table.get(i, "")
        if en:
            english[k] = en
        else:
            missing.append(k)
        lines.append("# " + enc(k)); lines.append("%s = %s" % (i, enc(en))); lines.append("")
    io.open(DATA, "w", encoding="utf-8", newline="\n").write("\n".join(lines))
    with open(OUT, "wb") as f:
        plistlib.dump(english, f, sort_keys=True)
    dropped = [i for i in table if i not in used]
    print("%d chuỗi, %d đã dịch, %d thiếu, %d mục cũ bị bỏ" % (len(keys), len(english), len(missing), len(dropped)))
    for k in missing:
        print("  THIẾU: " + enc(k)[:110])
    return 1 if missing else 0

if __name__ == "__main__":
    sys.exit(main())

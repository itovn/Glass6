#!/usr/bin/env python3
"""Sinh svc/catalog.h (danh sách trắng cứng của g6svc) từ data/services.tsv.

    python3 tools/gen_catalog.py data/services.tsv > svc/catalog.h

Kiểm lại đúng các điều kiện mà phép thử của lõi (core/crates/g6-core/src/services.rs) kiểm: sai là dừng dựng — nhãn sẽ
được ghép thành đường dẫn tệp và đưa cho launchctl chạy quyền root.
"""
import re
import sys

ID = re.compile(r"^[a-z0-9]+$")
LABEL = re.compile(r"^com\.apple\.[A-Za-z0-9._-]+$")


def main(path):
    services = []
    seen_ids, seen_files, seen_labels = set(), set(), set()
    with open(path, encoding="utf-8") as f:
        for number, line in enumerate(f, 1):
            line = line.rstrip("\r\n")
            if not line.strip() or line.startswith("#"):
                continue
            cols = line.split("\t")
            if len(cols) < 5:
                sys.exit("%s:%d: thiếu cột" % (path, number))
            sid, group = cols[0].strip(), cols[1].strip()
            # Mỗi việc launchd: «tệp» hoặc «tệp:nhãn» (nhãn khác tên tệp)
            jobs = []
            for job in (j.strip() for j in cols[2].split(",")):
                if job:
                    name, _, label = job.partition(":")
                    jobs.append((name, label or name))
            if not ID.match(sid) or sid in seen_ids:
                sys.exit("%s:%d: mã «%s» sai dạng hoặc trùng" % (path, number, sid))
            if group not in ("A", "B", "C"):
                sys.exit("%s:%d: nhóm «%s» lạ" % (path, number, group))
            if not jobs:
                sys.exit("%s:%d: không có việc launchd" % (path, number))
            for name, label in jobs:
                for text, seen in ((name, seen_files), (label, seen_labels)):
                    if not LABEL.match(text) or ".." in text or text in seen:
                        sys.exit("%s:%d: «%s» sai dạng hoặc trùng" % (path, number, text))
                    seen.add(text)
            seen_ids.add(sid)
            services.append((sid, jobs))
    if not services:
        sys.exit("%s: danh mục rỗng" % path)

    out = ["// SINH TỰ ĐỘNG từ data/services.tsv bằng tools/gen_catalog.py — đừng sửa tay.", ""]
    out.append("// Một việc launchd: tệp /System/Library/LaunchDaemons/<file>.plist, nhãn (khoá Label trong tệp) là <label>")
    out.append("struct g6_job {")
    out.append("    const char *file;")
    out.append("    const char *label;")
    out.append("};")
    out.append("")
    out.append("struct g6_service {")
    out.append("    const char *id;")
    out.append("    const struct g6_job *jobs;  // kết thúc bằng phần tử có file = NULL")
    out.append("};")
    out.append("")
    for sid, jobs in services:
        items = ", ".join('{"%s", "%s"}' % job for job in jobs)
        out.append("static const struct g6_job kJobs_%s[] = {%s, {0, 0}};" % (sid, items))
    out.append("")
    out.append("static const struct g6_service kServices[] = {")
    for sid, _ in services:
        out.append('    {"%s", kJobs_%s},' % (sid, sid))
    out.append("};")
    out.append("")
    out.append("#define G6_SERVICE_COUNT %d" % len(services))
    # Ghi thẳng UTF-8: đầu ra chuẩn của Python trên Windows không phải lúc nào cũng là UTF-8
    sys.stdout.buffer.write(("\n".join(out) + "\n").encode("utf-8"))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("dùng: gen_catalog.py <services.tsv>")
    main(sys.argv[1])

#!/usr/bin/env python3
"""Sinh helper/ota_cert.h từ chứng chỉ ký bản cập nhật OTA (chỉ khoá CÔNG KHAI).

    python3 tools/gen_ota_cert.py keys/ota-sign.crt > helper/ota_cert.h

Chạy trên máy phát hành mỗi khi đổi khoá ký (keys/ nằm ngoài git). g6update chỉ cài gói có chữ ký khớp chứng chỉ này;
tools/sign-release.sh đối chiếu vân tay SHA-256 ghi ở đầu tệp trước khi ký.
"""
import base64
import hashlib
import re
import sys


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    pem = open(sys.argv[1], encoding="ascii").read()
    m = re.search(r"-----BEGIN CERTIFICATE-----(.+?)-----END CERTIFICATE-----", pem, re.S)
    if not m:
        print("không thấy chứng chỉ PEM", file=sys.stderr)
        return 1
    der = base64.b64decode("".join(m.group(1).split()))
    digest = hashlib.sha256(der).hexdigest().upper()
    fingerprint = ":".join(digest[i:i + 2] for i in range(0, len(digest), 2))
    out = [
        "// Chứng chỉ (khoá công khai RSA-3072) ký bản cập nhật OTA của Glass 6 — chỉ khoá CÔNG KHAI; khoá riêng nằm ở máy phát",
        "// hành (keys/ota-sign.key, không lên git). g6update chỉ cài .deb có chữ ký khớp khoá này (tools/sign-release.sh ký lúc",
        "// phát hành). Tệp này do tools/gen_ota_cert.py sinh — đổi khoá thì máy đang chạy bản cũ phải cập nhật qua Cydia một lần.",
        "// CN=Glass 6 OTA signing (g6update chỉ lấy khoá công khai, không xét hạn của chứng chỉ).",
        "// SHA-256: " + fingerprint,
        "static const unsigned char kOtaCert[] = {",
    ]
    for i in range(0, len(der), 16):
        out.append("    " + " ".join("0x%02x," % b for b in der[i:i + 16]))
    out.append("};")
    # Ghi byte UTF-8 với xuống dòng LF (trên Windows stdout kiểu văn bản sẽ đổi thành CRLF và bảng mã của máy)
    sys.stdout.buffer.write(("\n".join(out) + "\n").encode("utf-8"))
    return 0


if __name__ == "__main__":
    sys.exit(main())

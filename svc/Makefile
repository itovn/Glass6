# g6svc — công cụ quyền root tắt / bật dịch vụ hệ thống trong danh mục (data/services.tsv). Cài ở /usr/libexec/glass6
# (phân vùng hệ thống — phân vùng dữ liệu /private/var của iOS thường gắn «nosuid»); postinst đặt chủ root + bit setuid.
# catalog.h (danh sách trắng cứng) sinh từ data/services.tsv trước khi dịch — không lên git.
include ../g6.mk
include $(THEOS)/makefiles/common.mk

TOOL_NAME = g6svc
g6svc_FILES = g6svc.c
g6svc_INSTALL_PATH = /usr/libexec/glass6
g6svc_CFLAGS = -Wall -Wextra -Werror
g6svc_CODESIGN_FLAGS = -S -Hsha1

include $(THEOS_MAKE_PATH)/tool.mk

before-all:: catalog.h

catalog.h: ../data/services.tsv ../tools/gen_catalog.py
	python3 ../tools/gen_catalog.py ../data/services.tsv > $@.tmp
	mv $@.tmp $@

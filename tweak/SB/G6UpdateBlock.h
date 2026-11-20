// Chặn cập nhật iOS qua mạng — phần của SpringBoard: khi cập nhật đang bị chặn thì dọn dấu nhắc «có bản cập nhật» còn sót
// (huy hiệu trên biểu tượng Cài đặt, số «1» ở dòng «Cài đặt chung»). Việc chặn do g6svc làm (mục «iosupdate» của danh mục dịch
// vụ, docs/DECISIONS.md D34). Xem G6UpdateBlock.m.
void G6UpdateBlockInstall(void);

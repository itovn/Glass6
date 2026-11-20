// In âm lịch + thần trực nhật của vài ngày (để đối chiếu với trang lịch âm)
fn main() {
    for (d, m, y) in [(17, 2, 2026), (15, 6, 2026), (1, 9, 2025), (3, 4, 2026), (8, 12, 2026)] {
        let x = g6_core::lunar::day_detail(d, m, y).unwrap();
        println!("{d}/{m}/{y}: âm {}/{}{} {} | ngày {} tháng {} năm {} | {} ({}) | {} | {:?}", x.ld, x.lm, if x.leap { "N" } else { "" }, x.ly,
                 x.can_chi_day, x.can_chi_month, x.can_chi_year, x.than, if x.good { "hoàng đạo" } else { "hắc đạo" }, x.tiet_khi, x.hours);
    }
}

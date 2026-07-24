/// Pure paging math for the welcome tour's Back/Next controls.
///
/// Button actions can fire twice between SwiftUI renders (⏎ auto-repeat on
/// the default action, a double-click racing the view update), and the bounds
/// the rendered controls enforce — Next absent on the last page, Back absent
/// on the first — lag one render behind. So every step clamps instead of
/// trusting which buttons existed (DROIDECTIVE-MAC-2H: an unclamped double
/// Next reached `pages[6]` and trapped in `Array._checkSubscript`).
enum TourPaging {
    static func next(from index: Int, count: Int) -> Int {
        min(index + 1, count - 1)
    }

    static func back(from index: Int) -> Int {
        max(index - 1, 0)
    }
}

/// Session resume for the Terminal: the working directories to remember when
/// the terminal tears down *implicitly* — app quit, the Terminal feature tab
/// closed, a background-mode window close — so the next open resumes one
/// shell per directory. Tabs the user closed explicitly (⌘W / × / `exit`)
/// never reach the snapshot: they're gone from the rail by the time it's
/// taken, so closing a tab means done with it.
///
/// Pure policy (the App layer reads each shell's live cwd from the kernel at
/// teardown time — no polling) so the snapshot contract is unit-tested here.
public enum TerminalResume {
    /// Upper bound on remembered tabs, so a pathological rail doesn't balloon
    /// the layout store or the next launch.
    public static let maxRemembered = 12

    /// The snapshot to persist — and the normalization applied when reading
    /// it back: the tabs' directories in display order, blank entries
    /// dropped, capped at `maxRemembered` (keeping the first, the way the
    /// rail reads).
    public static func snapshot(_ directories: [String]) -> [String] {
        Array(directories.lazy.filter { !$0.isEmpty }.prefix(maxRemembered))
    }
}

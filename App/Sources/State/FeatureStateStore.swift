import ADBKit
import Foundation

/// Per-window, per-feature state that outlives the view showing it.
///
/// SwiftUI destroys a feature's view whenever its tab moves — to the other
/// split pane, or (now) to another window — taking every `@State` with it. For
/// most features that is correct: a form's text field or a hub's disclosure
/// state should start clean. For the ones that accumulate something the user
/// would be annoyed to lose — a log buffer, a fetched crash list, a loaded APK
/// — it is a restart wearing a move's clothes.
///
/// So those features keep their state in a model object held here instead,
/// keyed by the window, the feature, and the model's type. The view resolves it each time
/// it renders and gets the same one back; a tab moving between windows re-keys
/// the entry rather than dropping it.
///
/// **Deliberately not `@Observable`.** Views resolve their model from `body`,
/// and resolving creates one on first use — a write. If this type were
/// observed, that write would invalidate the view that just read it, and the
/// re-render would write again: the endless update loop, not a wasted pass.
/// The *models* are observable; the container holding them must not be. (Same
/// reason `LogRowFrames` and `MainThreadLoad` are plain reference boxes.)
@MainActor
final class FeatureStateStore {
    /// window → feature → model type → model. Keyed by type as well as
    /// feature because one tab can keep two unrelated things: the mirror keeps
    /// its live session *and*, when a capture is open, the screenshot editor's
    /// markup. They move and are discarded together, which is what makes the
    /// feature the middle key rather than the last one.
    private var models: [WorkspaceID: [String: [ObjectIdentifier: AnyObject]]] = [:]

    /// This window's model for `feature`, created on first use.
    ///
    /// `make` runs at most once per (window, feature, type).
    func model<T: AnyObject>(
        _ type: T.Type, feature: String, in workspace: WorkspaceID, make: () -> T
    ) -> T {
        if let existing = models[workspace]?[feature]?[ObjectIdentifier(type)] as? T { return existing }
        let created = make()
        models[workspace, default: [:]][feature, default: [:]][ObjectIdentifier(type)] = created
        return created
    }

    /// This window's model for `feature`, or nil when it has never built one.
    /// Unlike `model(_:feature:in:make:)` this creates nothing, so callers
    /// outside the view — a tab closing, say — can ask about state without
    /// bringing it into existence.
    func existing<T: AnyObject>(_ type: T.Type, feature: String, in workspace: WorkspaceID) -> T? {
        models[workspace]?[feature]?[ObjectIdentifier(type)] as? T
    }

    /// Take everything `feature` keeps out, for a tab moving to another window.
    /// Empty when the feature never built anything (it was never opened, or it
    /// keeps nothing worth moving).
    func take(feature: String, in workspace: WorkspaceID) -> [ObjectIdentifier: AnyObject] {
        let taken = models[workspace]?[feature] ?? [:]
        models[workspace]?[feature] = nil
        return taken
    }

    /// Put models taken from another window under this one.
    func put(_ taken: [ObjectIdentifier: AnyObject], feature: String, in workspace: WorkspaceID) {
        guard !taken.isEmpty else { return }
        models[workspace, default: [:]][feature] = taken
    }

    /// Forget what `feature` kept — its tab closed, so its buffer should not
    /// outlive it and reappear when the feature is opened again.
    func discard(feature: String, in workspace: WorkspaceID) {
        models[workspace]?[feature] = nil
        if models[workspace]?.isEmpty == true { models[workspace] = nil }
    }

    /// Forget everything a window held — it closed for good.
    func discardAll(in workspace: WorkspaceID) {
        models[workspace] = nil
    }

    /// Feature ids currently holding a model in `workspace`. Test/diagnostic
    /// visibility only.
    func features(in workspace: WorkspaceID) -> Set<String> {
        Set(models[workspace]?.keys ?? [:].keys)
    }
}

import ADBKit
import Foundation

/// Half-written input, kept per window by `FeatureStateStore` rather than as
/// view `@State`.
///
/// These three screens are the app's typing surfaces, and what is in their
/// fields exists nowhere else until the user presses Send or Save. A tab moving
/// to another window rebuilt the view and cleared them — a paragraph of text
/// destined for a device, a deep link half typed, a shell command being
/// composed. Nothing here is expensive to produce again *except* by hand, which
/// is the kind that annoys most.
@MainActor
@Observable
final class SendTextModel {
    /// The message waiting to be sent.
    var text = ""
    /// The "new snippet" popover: whether it is open and what is in it.
    var creatingSnippet = false
    var newSnippetName = ""
    var newSnippetText = ""
    /// How the library below is being looked at.
    var snippetSearch = ""
    var showAllSnippets = false
}

/// A deep link being added or edited. The editor is a sheet, so this carries
/// which link is being edited as well as the fields — a move that dropped the
/// sheet but kept the text would be worse than dropping both.
@MainActor
@Observable
final class DeepLinkDraftModel {
    var showEditor = false
    var editingLink: DeepLink?
    var draftLabel = ""
    var draftURL = ""
}

/// A custom command being added or edited, fields and all.
@MainActor
@Observable
final class CustomCommandDraftModel {
    var showEditor = false
    var showPresets = false
    var editing: CustomCommand?
    var draftName = ""
    var draftCommand = ""
    var draftNeedsBundle = false
    var draftRunsInTerminal = false
    var draftTerminal: CustomCommandTerminal = .droidective
}

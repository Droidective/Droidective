//! The window menu.
//!
//! A webview has no menu of its own, so this is the only place these commands
//! can live — and every one of them is a shortcut somebody already has in their
//! fingers from the Mac app. The structure mirrors `App/Sources/ADTApp.swift`'s
//! `.commands { }` block: which submenu an item sits under, its wording, and
//! its accelerator all come from there rather than from what reads well here.
//!
//! Declared as a table rather than built inline, for the same reason
//! `ADBKit`'s `FeatureRegistry` is one: the invariants worth having — no duplicate id, no
//! accelerator bound twice, every id handled on the other side of the IPC — are
//! then tests over data instead of things to remember.

use tauri::menu::{Menu, MenuEvent, MenuItemBuilder, MenuItemKind, PredefinedMenuItem, Submenu};
use tauri::{AppHandle, Emitter, Manager, Runtime, Wry};

/// The event the webview listens on. One event carrying the command id, not an
/// event per command: the webview has one dispatch table either way, and a
/// listener per item would be forty listeners to keep in step with this file.
pub const MENU_EVENT: &str = "menu://command";

/// One command. `accelerator` is Tauri's own syntax ("CmdOrCtrl+Shift+N").
struct Item {
    id: &'static str,
    label: &'static str,
    accelerator: Option<&'static str>,
}

/// A separator, written as an item with no id so the table stays one list.
const SEPARATOR: Item = Item {
    id: "",
    label: "",
    accelerator: None,
};

struct Section {
    title: &'static str,
    items: &'static [Item],
}

/// `CmdOrCtrl` throughout, which is ⌘ on macOS and Ctrl elsewhere — the same
/// rule `lib/platform.ts`' `hasModifier` applies in the webview, so a menu
/// accelerator and the key handler behind it never disagree.
///
/// Where a mapping had to change, the reason is on the item. There are three,
/// and each is forced by the platform rather than chosen:
///
/// - **The terminal's commands all gained Shift.** The Mac uses ⌘N, ⌘D, ⇧⌘D and
///   ⇧⌘W; ⌘ is a modifier no shell has ever seen, while a bare Ctrl+letter
///   belongs to the program *inside* the terminal — Ctrl+N is the next history
///   line, Ctrl+D is end-of-input, Ctrl+W deletes a word. Taking any of them
///   would break the shell in a way that reads as the terminal being broken.
/// - **⇧⌘D became Ctrl+Shift+E**, because Ctrl+Shift+D is now the other split
///   axis. E is what GNOME Terminal splits with, so one mainstream Linux
///   terminal already agrees.
/// - **The Go menu moved from ⌘1–9 to Alt+1–9.** On the Mac ⌘1–9 opens sidebar
///   rows and ⌃1–9 switches tabs — two modifiers, two meanings. Windows and
///   Linux have only Ctrl, so the two collide, and tabs keep Ctrl+digit because
///   that is what every browser and terminal on those platforms does.
const SECTIONS: &[Section] = &[
    Section {
        title: "File",
        items: &[
            Item {
                id: "window.new",
                label: "New Window",
                accelerator: Some("CmdOrCtrl+Shift+Alt+N"),
            },
            Item {
                id: "window.new-for-device",
                label: "New Window for Device",
                accelerator: None,
            },
            SEPARATOR,
            Item {
                id: "terminal.new",
                label: "New Terminal",
                accelerator: Some("CmdOrCtrl+Shift+N"),
            },
            Item {
                id: "terminal.split-beside",
                label: "Split Terminal Vertically",
                accelerator: Some("CmdOrCtrl+Shift+D"),
            },
            Item {
                id: "terminal.split-below",
                label: "Split Terminal Horizontally",
                accelerator: Some("CmdOrCtrl+Shift+E"),
            },
            Item {
                id: "terminal.close",
                label: "Close Terminal",
                accelerator: Some("CmdOrCtrl+Shift+W"),
            },
            Item {
                id: "terminal.rename",
                label: "Rename Terminal…",
                accelerator: Some("CmdOrCtrl+Shift+R"),
            },
            SEPARATOR,
            Item {
                id: "terminal.next",
                label: "Next Terminal",
                accelerator: Some("CmdOrCtrl+Shift+]"),
            },
            Item {
                id: "terminal.previous",
                label: "Previous Terminal",
                accelerator: Some("CmdOrCtrl+Shift+["),
            },
        ],
    },
    Section {
        title: "Edit",
        items: &[
            Item {
                id: "app.find-feature",
                label: "Find Feature",
                accelerator: None,
            },
            Item {
                id: "app.catalog",
                label: "Manage Features",
                accelerator: Some("CmdOrCtrl+."),
            },
            SEPARATOR,
            Item {
                id: "app.settings",
                label: "Settings…",
                accelerator: Some("CmdOrCtrl+,"),
            },
        ],
    },
    Section {
        title: "View",
        items: &[
            Item {
                id: "view.toggle-sidebar",
                label: "Toggle Sidebar",
                accelerator: Some("CmdOrCtrl+B"),
            },
            SEPARATOR,
            Item {
                id: "view.zoom-in",
                label: "Increase Font Size",
                accelerator: Some("CmdOrCtrl+="),
            },
            Item {
                id: "view.zoom-out",
                label: "Decrease Font Size",
                accelerator: Some("CmdOrCtrl+-"),
            },
            Item {
                id: "view.zoom-reset",
                label: "Actual Size",
                accelerator: Some("CmdOrCtrl+Shift+0"),
            },
        ],
    },
    Section {
        title: "Tab",
        items: &[
            // The Mac's "New Tab" opens the search palette and the chosen
            // feature lands in a new tab — the palette *is* how a tab is
            // opened, which is why the wording and the ⌘T stay.
            Item {
                id: "tab.new",
                label: "New Tab",
                accelerator: Some("CmdOrCtrl+T"),
            },
            Item {
                id: "tab.close",
                label: "Close Tab",
                accelerator: Some("CmdOrCtrl+W"),
            },
            SEPARATOR,
            Item {
                id: "tab.next",
                label: "Next Tab",
                accelerator: Some("Ctrl+Tab"),
            },
            Item {
                id: "tab.previous",
                label: "Previous Tab",
                accelerator: Some("Ctrl+Shift+Tab"),
            },
        ],
    },
    Section {
        title: "Help",
        items: &[
            Item {
                id: "help.report-issue",
                label: "Report an Issue…",
                accelerator: None,
            },
            Item {
                id: "help.request-feature",
                label: "Request a Feature…",
                accelerator: None,
            },
            SEPARATOR,
            Item {
                id: "help.repository",
                label: "Droidective on GitHub",
                accelerator: None,
            },
            Item {
                id: "help.releases",
                label: "Release Notes",
                accelerator: None,
            },
            SEPARATOR,
            Item {
                id: "app.about",
                label: "About Droidective",
                accelerator: None,
            },
        ],
    },
];

/// The items that need a terminal in front of you.
///
/// The Mac greys these out with `.disabled(!terminalCommandsEnabled)`, and a
/// menu that offers "Split Terminal" with no terminal open is a menu that lies.
/// `terminal.new` is deliberately not here: with nothing open it opens the
/// Terminal tab, which is what the Mac's New Terminal does too.
const TERMINAL_DEPENDENT: &[&str] = &[
    "terminal.split-beside",
    "terminal.split-below",
    "terminal.close",
    "terminal.rename",
    "terminal.next",
    "terminal.previous",
];

/// Greys the terminal commands in or out.
///
/// Walks the submenus rather than holding item handles in state: `Menu::get`
/// only looks at the top level, and a handle cache would be a second place the
/// ids live — which is the drift the table exists to prevent.
pub fn set_terminal_commands_enabled(app: &AppHandle<Wry>, enabled: bool) {
    let Some(menu) = app.menu() else { return };
    let Ok(sections) = menu.items() else { return };
    for section in sections {
        let MenuItemKind::Submenu(submenu) = section else {
            continue;
        };
        let Ok(items) = submenu.items() else { continue };
        for item in items {
            let MenuItemKind::MenuItem(entry) = item else {
                continue;
            };
            if TERMINAL_DEPENDENT.contains(&entry.id().0.as_str()) {
                let _ = entry.set_enabled(enabled);
            }
        }
    }
}

/// The Go menu's rows, built rather than tabled: ten items that differ only by
/// a digit are a loop, and writing them out would be ten chances to mistype one.
///
/// `Alt`, not `CmdOrCtrl` — see the note on `SECTIONS`. The label deliberately
/// says "Sidebar Item N" rather than naming the feature: the sidebar's order is
/// the user's, lives in the webview, and a label baked in at startup would be
/// wrong the first time they reordered it.
const GO_ROWS: usize = 10;

fn go_accelerator(rank: usize) -> String {
    format!("Alt+{}", (rank + 1) % GO_ROWS)
}

fn go_id(rank: usize) -> String {
    format!("go.row-{rank}")
}

/// Builds the menu. Every id reaches the webview through `MENU_EVENT`; nothing
/// is handled here, because everything these commands act on is webview state.
pub fn build<R: Runtime>(app: &AppHandle<R>) -> tauri::Result<Menu<R>> {
    let menu = Menu::new(app)?;
    for section in SECTIONS {
        let submenu = Submenu::new(app, section.title, true)?;
        for item in section.items {
            if item.id.is_empty() {
                submenu.append(&PredefinedMenuItem::separator(app)?)?;
                continue;
            }
            let mut builder = MenuItemBuilder::with_id(item.id, item.label)
                // Disabled from the start for the terminal's commands: nothing
                // is open at launch, and an item that becomes correct only
                // after the first registration would be wrong until then.
                .enabled(!TERMINAL_DEPENDENT.contains(&item.id));
            if let Some(accelerator) = item.accelerator {
                builder = builder.accelerator(accelerator);
            }
            submenu.append(&builder.build(app)?)?;
        }
        menu.append(&submenu)?;
    }

    let go = Submenu::new(app, "Go", true)?;
    for rank in 0..GO_ROWS {
        go.append(
            &MenuItemBuilder::with_id(go_id(rank), format!("Sidebar Item {}", rank + 1))
                .accelerator(go_accelerator(rank))
                .build(app)?,
        )?;
    }
    menu.append(&go)?;
    Ok(menu)
}

/// Forwards a click to the webview.
///
/// Emitted to the window rather than app-wide so this still reads correctly
/// when there is more than one — a menu click belongs to the window whose menu
/// it was.
#[expect(
    clippy::needless_pass_by_value,
    reason = "tauri's on_menu_event hands the event in by value"
)]
pub fn forward(app: &AppHandle<Wry>, event: MenuEvent) {
    let id = event.id().0.as_str();
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.emit(MENU_EVENT, id);
    }
}

#[cfg(test)]
mod tests {
    use std::collections::HashSet;

    use super::{go_accelerator, go_id, GO_ROWS, SECTIONS};

    /// Every id and accelerator in the menu, Go rows included.
    fn entries() -> Vec<(String, Option<String>)> {
        let mut all: Vec<(String, Option<String>)> = SECTIONS
            .iter()
            .flat_map(|section| section.items)
            .filter(|item| !item.id.is_empty())
            .map(|item| (item.id.to_string(), item.accelerator.map(str::to_string)))
            .collect();
        for rank in 0..GO_ROWS {
            all.push((go_id(rank), Some(go_accelerator(rank))));
        }
        all
    }

    #[test]
    fn every_terminal_dependent_id_is_a_real_menu_item() {
        // A typo here would silently never grey anything out, and the menu
        // would keep offering a command with no terminal to run it on.
        let ids: HashSet<String> = entries().into_iter().map(|(id, _)| id).collect();
        for id in super::TERMINAL_DEPENDENT {
            assert!(ids.contains(*id), "{id} is not a menu item");
        }
    }

    #[test]
    fn new_terminal_is_never_greyed_out() {
        // With nothing open it opens the Terminal tab, so disabling it would
        // leave no way in from the menu at all.
        assert!(!super::TERMINAL_DEPENDENT.contains(&"terminal.new"));
    }

    #[test]
    fn no_command_id_is_used_twice() {
        // A duplicate id means one of the two items is unreachable — the event
        // carries the id, so the webview cannot tell them apart.
        let mut seen = HashSet::new();
        for (id, _) in entries() {
            assert!(seen.insert(id.clone()), "{id} appears twice");
        }
    }

    #[test]
    fn no_accelerator_is_bound_twice() {
        // The failure this catches is silent: the platform gives the keystroke
        // to one of the two items and the other simply never fires.
        let mut seen = HashSet::new();
        for (id, accelerator) in entries() {
            if let Some(accelerator) = accelerator {
                assert!(
                    seen.insert(accelerator.clone()),
                    "{accelerator} is bound by {id} and by something else"
                );
            }
        }
    }

    #[test]
    fn every_accelerator_has_a_modifier_and_a_key() {
        // Tauri parses these when the menu is built, and one bad string fails
        // the whole menu — taking every other item with it. Asserting the shape
        // here means a typo is a test failure rather than an app that launches
        // with no menu at all.
        //
        // A modifier is mandatory: a bare key as an accelerator would fire
        // while someone was typing in a text field.
        for (id, accelerator) in entries() {
            let Some(accelerator) = accelerator else {
                continue;
            };
            let parts: Vec<&str> = accelerator.split('+').collect();
            assert!(parts.len() >= 2, "{id}: {accelerator} has no modifier");
            let Some((key, modifiers)) = parts.split_last() else {
                unreachable!("split always yields at least one part")
            };
            assert!(!key.is_empty(), "{id}: {accelerator} has no key");
            for modifier in modifiers {
                assert!(
                    matches!(*modifier, "CmdOrCtrl" | "Ctrl" | "Shift" | "Alt"),
                    "{id}: {modifier} is not a modifier this app uses"
                );
            }
        }
    }

    #[test]
    fn the_terminals_commands_all_take_shift() {
        // Not style: a bare Ctrl+letter belongs to the program inside the
        // terminal, so an accelerator without Shift would swallow Ctrl+D,
        // Ctrl+W or Ctrl+N from the shell.
        for (id, accelerator) in entries() {
            if !id.starts_with("terminal.") {
                continue;
            }
            let accelerator = accelerator.unwrap_or_default();
            assert!(
                accelerator.contains("Shift"),
                "{id} is bound to {accelerator}, which the shell would never see"
            );
        }
    }

    #[test]
    fn the_go_rows_run_one_to_nine_then_zero() {
        // The Mac's numbering: ⌘1…⌘9 then ⌘0 for the tenth. Reading 0 as "the
        // tenth" is the part a loop gets wrong.
        assert_eq!(go_accelerator(0), "Alt+1");
        assert_eq!(go_accelerator(8), "Alt+9");
        assert_eq!(go_accelerator(9), "Alt+0");
        assert_eq!(go_id(9), "go.row-9");
    }

    #[test]
    fn tabs_keep_ctrl_digit_and_the_go_menu_does_not_take_it() {
        // The collision the Alt move exists to avoid. Ctrl+1…9 is Show Tab in
        // the webview's own key handler; nothing in the menu may claim it.
        for (id, accelerator) in entries() {
            let accelerator = accelerator.unwrap_or_default();
            for digit in 0..=9 {
                assert_ne!(
                    accelerator,
                    format!("CmdOrCtrl+{digit}"),
                    "{id} claims a digit the tab shortcuts own"
                );
            }
        }
    }
}

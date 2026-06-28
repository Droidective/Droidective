import { EditorView, basicSetup } from "codemirror";
import { EditorState } from "@codemirror/state";
import { java } from "@codemirror/lang-java";
import { xml } from "@codemirror/lang-xml";
import { oneDark } from "@codemirror/theme-one-dark";
import { openSearchPanel } from "@codemirror/search";

let view = null;

function languageExtension(name) {
  if (name === "java") return java();
  if (name === "xml") return xml();
  return [];
}

// Swift (CodeEditorView) calls these via evaluateJavaScript. `line` (1-based,
// 0 = none) jumps to and highlights a search hit.
window.cmLoad = function (text, language, line) {
  const extensions = [
    basicSetup, // line numbers, fold gutter, search keymap (⌘F), bracket match…
    EditorView.editable.of(false),
    EditorState.readOnly.of(true),
    oneDark, // dark theme + syntax colours
    languageExtension(language),
  ];
  if (view) view.destroy();
  view = new EditorView({ doc: text ?? "", extensions, parent: document.body });
  const target = typeof line === "number" ? line : 0;
  if (target > 0 && target <= view.state.doc.lines) {
    const found = view.state.doc.line(target);
    view.dispatch({
      selection: { anchor: found.from, head: found.to }, // selects = highlights the line
      effects: EditorView.scrollIntoView(found.from, { y: "center" }),
    });
    view.focus();
  } else {
    view.scrollDOM.scrollTop = 0;
  }
};

// Open CodeMirror's find panel (also bound to ⌘F by basicSetup).
window.cmFind = function () {
  if (view) openSearchPanel(view);
};

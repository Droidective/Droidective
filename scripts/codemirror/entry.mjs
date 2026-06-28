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

// Swift (CodeEditorView) calls these via evaluateJavaScript.
window.cmLoad = function (text, language) {
  const extensions = [
    basicSetup, // line numbers, fold gutter, search keymap (⌘F), bracket match…
    EditorView.editable.of(false),
    EditorState.readOnly.of(true),
    oneDark, // dark theme + syntax colours
    languageExtension(language),
  ];
  if (view) view.destroy();
  view = new EditorView({ doc: text ?? "", extensions, parent: document.body });
  view.scrollDOM.scrollTop = 0;
};

// Open CodeMirror's find panel (also bound to ⌘F by basicSetup).
window.cmFind = function () {
  if (view) openSearchPanel(view);
};

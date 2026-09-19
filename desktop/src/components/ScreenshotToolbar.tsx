import {
  ArrowUpRight,
  ChevronLeft,
  Circle,
  Crop,
  EyeOff,
  Highlighter,
  MousePointer2,
  PenLine,
  Redo2,
  RotateCcw,
  RotateCw,
  Slash,
  Square,
  Trash2,
  Type,
  Undo2,
} from "lucide-react"
import type { ReactNode } from "react"
import { IconButton } from "@/components/Hub"
import {
  Divider,
  RedactControls,
  Swatches,
  ToolbarSelect,
  Toggle,
} from "@/components/ScreenshotToolbarParts"
import { showsRedactControls, trashAction, type DrawSettings } from "@/lib/screenshot-editor"
import {
  MARKUP_TOOLS,
  TOOL_LABELS,
  WIDTHS,
  type Annotation,
  type MarkupTool,
} from "@/lib/screenshot-markup"

/** One lucide glyph per markup tool, reading as the Mac's SF Symbol does. */
const TOOL_ICONS: Record<MarkupTool, ReactNode> = {
  pen: <PenLine size={14} />,
  highlighter: <Highlighter size={14} />,
  arrow: <ArrowUpRight size={14} />,
  line: <Slash size={14} />,
  rectangle: <Square size={14} />,
  ellipse: <Circle size={14} />,
  text: <Type size={14} />,
  redact: <EyeOff size={14} />,
}

export interface ToolbarProps {
  settings: DrawSettings
  onSettings: (settings: DrawSettings) => void
  selecting: boolean
  onSelecting: (on: boolean) => void
  selected: Annotation | null
  cropping: boolean
  onCropping: (on: boolean) => void
  annotations: readonly Annotation[]
  canUndo: boolean
  canRedo: boolean
  onUndo: () => void
  onRedo: () => void
  onRotate: (clockwise: boolean) => void
  onTrash: () => void
  onBack: () => void
  /** Edit the picked annotation in place — what the redact slider does. */
  onReplaceSelected: (annotation: Annotation, recordUndo: boolean) => void
}

/** The editor's top row — `ScreenshotEditorView`'s toolbar, control for control. */
export function ScreenshotToolbar(props: ToolbarProps) {
  const trash = trashAction(props.selecting, props.selected?.id ?? null, props.annotations)
  const redact = showsRedactControls(props.settings, props.selecting, props.selected)
  return (
    <div className="flex flex-wrap items-center gap-2 border-b border-border-subtle px-3 py-2">
      <IconButton icon={<ChevronLeft size={14} />} label="Back" onClick={props.onBack} />
      <Divider />
      <ToolRow {...props} />
      <Divider />
      <Swatches settings={props.settings} onSettings={props.onSettings} />
      <Divider />
      <ToolbarSelect
        label="Stroke width"
        value={String(props.settings.width)}
        onChange={(value) => {
          props.onSettings({ ...props.settings, width: Number(value) })
        }}
        options={WIDTHS.map((w) => ({ value: String(w.value), label: w.label }))}
      />
      {redact ? <RedactControls {...props} /> : null}

      <div className="flex-1" />

      <IconButton
        icon={<RotateCcw size={14} />}
        label="Rotate left 90°"
        onClick={() => {
          props.onRotate(false)
        }}
      />
      <IconButton
        icon={<RotateCw size={14} />}
        label="Rotate right 90°"
        onClick={() => {
          props.onRotate(true)
        }}
      />
      <Toggle
        on={props.cropping}
        icon={<Crop size={14} />}
        label="Crop the image"
        onClick={() => {
          props.onCropping(!props.cropping)
        }}
      />
      <IconButton
        icon={<Undo2 size={14} />}
        label="Undo (Ctrl+Z)"
        disabled={!props.canUndo}
        onClick={props.onUndo}
      />
      <IconButton
        icon={<Redo2 size={14} />}
        label="Redo (Ctrl+Shift+Z)"
        disabled={!props.canRedo}
        onClick={props.onRedo}
      />
      <IconButton
        icon={<Trash2 size={14} />}
        label={trash.label}
        disabled={!trash.enabled}
        onClick={props.onTrash}
      />
    </div>
  )
}

function ToolRow({ settings, onSettings, selecting, onSelecting, cropping }: ToolbarProps) {
  return (
    <div className="flex items-center gap-0.5">
      <Toggle
        on={selecting}
        icon={<MousePointer2 size={14} />}
        label="Select, move & resize"
        onClick={() => {
          onSelecting(true)
        }}
      />
      {MARKUP_TOOLS.map((tool) => (
        <Toggle
          key={tool}
          on={settings.tool === tool && !cropping && !selecting}
          icon={TOOL_ICONS[tool]}
          label={TOOL_LABELS[tool]}
          onClick={() => {
            onSelecting(false)
            onSettings({ ...settings, tool })
          }}
        />
      ))}
    </div>
  )
}

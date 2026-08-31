import { useState } from "react"

import { ApiConfirmations } from "@/components/api/ApiConfirmations"
import {
  ApiSidebarRegion,
  useMeasuredWidth,
  type SidebarSection,
} from "@/components/api/ApiPaneParts"
import { ApiSheetHost, type ApiSheetKind, type PendingDelete } from "@/components/api/ApiSheetHost"
import { ApiWorkbench } from "@/components/api/ApiWorkbench"
import { useApiClient } from "@/hooks/useApiClient"
import { useApiFiles } from "@/hooks/useApiFiles"
import { useApiPaneActions } from "@/hooks/useApiPaneActions"
import { useApiSeam } from "@/hooks/useApiSeam"
import { COMPACT_PANE, NARROW_PANE, fractionFrom } from "@/lib/api/layout"

/**
 * API Testing — the Mac's `ApiClientView`.
 *
 * Device-free: nothing here touches adb, which is why the screen works with
 * nothing connected. The two seams (the sidebar edge and the editor/response
 * split) are `lib/api/layout.ts`, so the drag and the layout cannot disagree
 * about their bounds.
 */
export function ApiClientPane() {
  const client = useApiClient()
  const files = useApiFiles(client.update)
  const [sheet, setSheet] = useState<ApiSheetKind | null>(null)
  const [pendingDelete, setPendingDelete] = useState<PendingDelete | null>(null)
  const [pendingNew, setPendingNew] = useState(false)
  const [section, setSection] = useState<SidebarSection>("collections")
  const [showSidebar, setShowSidebar] = useState(true)

  const { width, ref } = useMeasuredWidth()
  const narrow = width > 0 && width < NARROW_PANE
  const compact = width > 0 && width < COMPACT_PANE

  const actions = useApiPaneActions({ client, files, setSheet, setPendingDelete, setPendingNew })

  // Both seams persist, and they clamp differently for the reason
  // `ApiPaneLayout` names: the sidebar is a width (it should not grow with the
  // window) and the split is a fraction (it should).
  const sidebarSeam = useApiSeam("apiSidebarWidth", 260)
  const splitSeam = useApiSeam("apiSplitFraction", 0.5)

  return (
    <div ref={ref} className="flex h-full min-h-0 w-full">
      <ApiSidebarRegion
        data={client.data}
        section={section}
        onSection={setSection}
        actions={actions.sidebar}
        shown={showSidebar}
        narrow={narrow}
        width={width}
        storedWidth={sidebarSeam.value}
        onBeginDrag={sidebarSeam.begin}
      />

      <ApiWorkbench
        client={client}
        files={files}
        actions={actions}
        compact={compact}
        narrow={narrow}
        width={width}
        sidebarShown={showSidebar}
        onToggleSidebar={() => {
          setShowSidebar((was) => !was)
        }}
        fraction={splitSeam.value}
        onBeginSplitDrag={(position) => {
          splitSeam.begin(position, (start, moved) => fractionFrom(start, moved, width))
        }}
      />

      <ApiSheetHost
        sheet={sheet}
        client={client}
        onDismiss={() => {
          setSheet(null)
        }}
      />

      <ApiConfirmations
        pendingDelete={pendingDelete}
        onResolveDelete={() => {
          setPendingDelete(null)
        }}
        pendingNew={pendingNew}
        currentName={client.current.name}
        onSaveFirst={() => {
          setPendingNew(false)
          setSheet({ kind: "saveRequest" })
        }}
        onDiscard={() => {
          setPendingNew(false)
          client.startNewRequest()
        }}
        onKeepEditing={() => {
          setPendingNew(false)
        }}
      />
    </div>
  )
}

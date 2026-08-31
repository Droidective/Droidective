import { useState } from "react"

import { ApiSplit, ApiStrips } from "@/components/api/ApiPaneParts"
import { ApiRequestBar } from "@/components/api/ApiRequestBar"
import { ApiRequestEditor, type RequestTab } from "@/components/api/ApiRequestEditor"
import { ApiResponsePane } from "@/components/api/ApiResponsePane"
import type { ApiClient } from "@/hooks/useApiClient"
import type { ApiFiles } from "@/hooks/useApiFiles"
import type { useApiPaneActions } from "@/hooks/useApiPaneActions"

/**
 * Everything to the right of the sidebar: the request bar, the two strips, and
 * the editor/response split.
 *
 * Split from `ApiClientPane` so that file stays an arrangement of four regions
 * rather than the whole screen.
 */
export function ApiWorkbench({
  client,
  files,
  actions,
  compact,
  narrow,
  width,
  sidebarShown,
  onToggleSidebar,
  fraction,
  onBeginSplitDrag,
}: {
  client: ApiClient
  files: ApiFiles
  actions: ReturnType<typeof useApiPaneActions>
  compact: boolean
  narrow: boolean
  width: number
  sidebarShown: boolean
  onToggleSidebar: () => void
  fraction: number
  onBeginSplitDrag: (position: number) => void
}) {
  // The editor's tab is nobody else's business, so it lives here rather than
  // in the pane above.
  const [tab, setTab] = useState<RequestTab>("params")

  return (
    <div className="flex min-w-0 flex-1 flex-col">
      <ApiRequestBar
        data={client.data}
        method={client.current.method}
        url={client.current.url}
        sending={client.sending}
        canSend={client.canSend}
        sidebarShown={sidebarShown}
        unresolved={client.unresolved}
        compact={compact}
        onMethod={(method) => {
          client.setCurrent((previous) => ({ ...previous, method }))
        }}
        onUrl={actions.setUrl}
        actions={{ ...actions.bar, onToggleSidebar }}
      />
      <div className="h-px bg-border-subtle" />

      <ApiStrips
        persistFailure={client.persistFailure}
        onRetry={client.retryPersist}
        warnings={client.warnings}
      />

      <ApiSplit
        narrow={narrow}
        width={width}
        fraction={fraction}
        onBeginDrag={onBeginSplitDrag}
        editor={
          <ApiRequestEditor
            request={client.current}
            onChange={client.setCurrent}
            inherited={client.inherited}
            scope={client.scope}
            assertionResults={client.response?.assertions ?? []}
            tab={tab}
            onTab={setTab}
            onPickFile={actions.pickFile}
          />
        }
        response={
          <ApiResponsePane
            response={client.response}
            errorText={client.errorText}
            sending={client.sending}
            canSend={client.canSend}
            onRetry={client.send}
            onSaveBody={files.saveResponseBody}
          />
        }
      />
    </div>
  )
}

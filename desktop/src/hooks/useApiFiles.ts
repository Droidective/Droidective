import { useCallback } from "react"

import { useNotifications } from "@/hooks/useNotifications"
import type { ApiClientData, ApiCollection, ApiEnvironment } from "@/lib/api/model"
import { mergeImport } from "@/lib/api/workspace"
import {
  apiExport,
  apiImport,
  asDaemonError,
  exportText,
  pickFile,
  type ApiSendResponse,
} from "@/lib/daemon"

export interface ApiFiles {
  importFile: () => void
  exportCollection: (collection: ApiCollection, includeSecrets: boolean) => void
  exportEnvironment: (environment: ApiEnvironment) => void
  exportWorkspace: (data: ApiClientData) => void
  saveResponseBody: (response: ApiSendResponse) => void
  /** For a binary body or a multipart part: a host path, or null if cancelled. */
  choose: () => Promise<string | null>
}

/**
 * The API pane's file work.
 *
 * Two rules, both the app's own rather than this screen's. A *read* goes
 * through the picker in the Rust process, because a webview drop hands over a
 * `File` with no path. A *write* goes to `~/Downloads/Droidective` through
 * `exportText` — the Mac asks with a save panel, and a dialog here would be a
 * second place deciding where files land, which is how a Show in folder button
 * ends up pointing at the wrong one.
 */
export function useApiFiles(
  update: (change: (data: ApiClientData) => ApiClientData) => void,
): ApiFiles {
  const { show } = useNotifications()

  const write = useCallback(
    (name: string, contents: string) => {
      exportText(name, contents).then(
        (path) => {
          show({ message: `Saved ${name}`, ok: true, revealPath: path })
        },
        (thrown: unknown) => {
          show({ message: asDaemonError(thrown).message, ok: false })
        },
      )
    },
    [show],
  )

  const importFile = useCallback(() => {
    void (async () => {
      try {
        const path = await pickFile("JSON", ["json"])
        if (path === null) return
        const answer = await apiImport(path)
        if (answer.collections.length === 0 && answer.environments.length === 0) {
          show({ message: answer.summary, ok: false })
          return
        }
        update((previous) => mergeImport(previous, answer))
        const notes =
          answer.warnings.length === 0 ? "" : ` · ${answer.warnings.join(" · ")}`
        show({ message: `${answer.summary}${notes}`, ok: true })
      } catch (thrown) {
        show({ message: asDaemonError(thrown).message, ok: false })
      }
    })()
  }, [show, update])

  const exportPayload = useCallback(
    (
      payload: Parameters<typeof apiExport>[0],
      includeSecrets: boolean,
    ) => {
      apiExport(payload, includeSecrets).then(
        (answer) => {
          write(answer.suggestedName, answer.json)
        },
        (thrown: unknown) => {
          show({ message: asDaemonError(thrown).message, ok: false })
        },
      )
    },
    [show, write],
  )

  return {
    importFile,
    exportCollection: useCallback(
      (collection: ApiCollection, includeSecrets: boolean) => {
        exportPayload({ kind: "collection", collection }, includeSecrets)
      },
      [exportPayload],
    ),
    exportEnvironment: useCallback(
      (environment: ApiEnvironment) => {
        exportPayload({ kind: "environment", environment }, false)
      },
      [exportPayload],
    ),
    exportWorkspace: useCallback(
      (data: ApiClientData) => {
        exportPayload({ kind: "workspace", workspace: data }, false)
      },
      [exportPayload],
    ),
    saveResponseBody: useCallback(
      (response: ApiSendResponse) => {
        const name = `response${extensionFor(response)}`
        if (response.bodyText !== null) {
          write(name, response.bodyText)
          return
        }
        if (response.bodyBase64 === null) {
          show({ message: "That body is too large to save from here.", ok: false })
          return
        }
        // Base64 through `exportText` would write the *text* of the encoding.
        // Decoding here keeps one file-writing path rather than adding a
        // second Rust command for one button.
        write(name, atob(response.bodyBase64))
      },
      [show, write],
    ),
    // Any file: a binary body or a multipart part can be anything, and a
    // filter would be this screen inventing a restriction the Mac does not
    // have (`NSOpenPanel` there sets no content types).
    choose: useCallback(() => pickFile("Any file", []), []),
  }
}

/** `ApiResponsePane.fileExtension`, the same table. */
function extensionFor(response: ApiSendResponse): string {
  switch (response.format) {
    case "json":
      return ".json"
    case "xml":
      return ".xml"
    case "html":
      return ".html"
    case "text":
      return ".txt"
    case "binary":
      return ".bin"
    case "image":
      return imageExtension(response.mediaType)
  }
}

function imageExtension(mediaType: string): string {
  switch (mediaType) {
    case "image/png":
      return ".png"
    case "image/jpeg":
      return ".jpg"
    case "image/gif":
      return ".gif"
    case "image/webp":
      return ".webp"
    case "image/svg+xml":
      return ".svg"
    default:
      return ".img"
  }
}

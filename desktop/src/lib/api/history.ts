/**
 * The API pane's history list.
 *
 * Split from `workspace.ts` because it is the one part with a rule of its own:
 * what may be written down. A sent request is kept so it can be re-opened, and
 * its credentials are not, so a token never reaches disk in a file someone
 * might share.
 */

import { HISTORY_LIMIT, newId, requestWithoutSecrets } from "@/lib/api/defaults"
import type { ApiClientData, ApiHistoryEntry, SavedRequest } from "@/lib/api/model"

/** Newest first, capped — `ApiClientData.addToHistory`. */
export function addToHistory(data: ApiClientData, entry: ApiHistoryEntry): ApiClientData {
  return { ...data, history: [entry, ...data.history].slice(0, HISTORY_LIMIT) }
}

export function clearHistory(data: ApiClientData): ApiClientData {
  return { ...data, history: [] }
}

/**
 * A history entry for one send.
 *
 * The request is stored without its secrets, so a token never reaches disk in
 * a file someone might share — `ApiHistoryEntry.init` does the same scrubbing
 * on the Mac, and it is the reason the sidebar's rows carry a tooltip saying
 * credentials have to be re-entered.
 */
export function historyEntry(
  request: SavedRequest,
  outcome: {
    url: string
    statusCode?: number | null
    errorText?: string | null
    elapsedMs?: number | null
    responseSize?: number | null
  },
): ApiHistoryEntry {
  return {
    id: newId(),
    method: request.method,
    url: outcome.url,
    statusCode: outcome.statusCode ?? null,
    errorText: outcome.errorText ?? null,
    elapsedMs: outcome.elapsedMs ?? null,
    responseSize: outcome.responseSize ?? null,
    timestamp: Date.now() / 1000,
    request: requestWithoutSecrets(request),
  }
}

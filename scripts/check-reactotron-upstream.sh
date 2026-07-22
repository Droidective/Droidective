#!/bin/bash
# Did Reactotron change the MCP contract since we last synced?
#
# Diffs the contract-defining upstream files against the commit pinned in
# scripts/reactotron-upstream.lock and checks the reactotron-mcp npm version.
# Read-only: prints what changed (or "in sync") and never touches this repo.
# Run before releases, or whenever Reactotron ships something MCP-related.
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
lock="$repo_root/scripts/reactotron-upstream.lock"
# shellcheck source=/dev/null
source "$lock"

# The files that define the contract ReactotronMCP mirrors, and where each
# one lands on our side (see CLAUDE.md ▸ "Reactotron MCP — syncing with upstream").
contract_paths=(
  "lib/reactotron-mcp/src/tools.ts"          # → ADBKit/Sources/ReactotronMCP/McpToolRegistry.swift + McpToolHandlers.swift
  "lib/reactotron-mcp/src/resources.ts"      # → McpResources.swift
  "lib/reactotron-mcp/src/redaction.ts"      # → McpRedaction.swift
  "lib/reactotron-mcp/src/serialization.ts"  # → McpSerialization.swift + McpConstants.swift
  "lib/reactotron-mcp/src/mcp-server.ts"     # → McpHTTPListener.swift + McpCommandStore.swift
  "lib/reactotron-core-contract/src/command.ts"       # → ADBKit ReactotronProtocol.swift
  "lib/reactotron-core-contract/src/mcpRedaction.ts"  # → McpRedaction.swift config types
  "lib/reactotron-core-server/src/reactotron-core-server.ts"  # → ADBKit ReactotronServer.swift
)

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

echo "Fetching infinitered/reactotron (blobless clone)…"
git clone --quiet --filter=blob:none --no-checkout \
  https://github.com/infinitered/reactotron "$workdir/reactotron"
cd "$workdir/reactotron"
default_branch=$(git symbolic-ref --short refs/remotes/origin/HEAD | sed 's|origin/||')
latest=$(git rev-parse "origin/$default_branch")

status=0

echo
echo "Pinned:  $REACTOTRON_COMMIT ($REACTOTRON_COMMIT_DATE)"
echo "Latest:  $latest ($default_branch)"

if [ "$latest" = "$REACTOTRON_COMMIT" ]; then
  echo "✓ Upstream repo unchanged since the pin."
else
  changed=$(git diff --name-only "$REACTOTRON_COMMIT" "$latest" -- "${contract_paths[@]}")
  if [ -z "$changed" ]; then
    echo "✓ Upstream moved, but no contract-defining file changed."
  else
    status=1
    echo "✗ Contract files changed since the pin:"
    git diff --stat "$REACTOTRON_COMMIT" "$latest" -- "${contract_paths[@]}" | sed 's/^/    /'
    echo
    echo "  Review the diff and port what changed (the comments in this script"
    echo "  say which Swift file mirrors each upstream file):"
    echo "    cd $workdir/reactotron && git diff $REACTOTRON_COMMIT $latest -- <file>"
    echo "  Then bump scripts/reactotron-upstream.lock and re-run swift test"
    echo "  (McpGoldenContractTests pins the served contract)."
  fi
fi

echo
npm_latest=$(npm view reactotron-mcp version 2>/dev/null || echo "unknown")
if [ "$npm_latest" = "$REACTOTRON_MCP_NPM_VERSION" ]; then
  echo "✓ npm reactotron-mcp still $npm_latest."
else
  status=1
  echo "✗ npm reactotron-mcp is $npm_latest (pinned $REACTOTRON_MCP_NPM_VERSION)."
  echo "  Note: the npm package is the standalone stdio proxy — different"
  echo "  surface from the embedded server we mirror, but new tools there are"
  echo "  candidates to adopt. npm pack reactotron-mcp to inspect."
fi

exit $status

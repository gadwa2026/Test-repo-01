#!/usr/bin/env bash
set -euo pipefail

# repo-protect-dryrun.sh
# Dry-run: prints branch protection & release payloads without applying them.
#
# Usage:
#   # Optionally provide a token to query Actions runs (recommended)
#   export GITHUB_TOKEN="ghp_xxx"
#   ./repo-protect-dryrun.sh
#
# Optional env overrides:
#   OWNER (default: gadwa2026)
#   REPO (default: Test-repo-01)
#   BRANCH (default: main)
#   REQUIRED_APPROVALS (default: 1)
#   ENFORCE_ADMINS (default: true)
#   REQUIRE_LINEAR_HISTORY (default: false)
#   REQUIRE_CONVERSATION_RESOLUTION (default: false)
#   CREATE_RELEASE (default: true)
#   RELEASE_TAG (default: v0.1.0)
#   RELEASE_DRAFT (default: true)
#   RELEASE_BODY (default: "Initial release")
#   TIMEOUT_SECONDS (default: 900)
#   POLL_INTERVAL (default: 15)
#   CONTEXTS (optional, comma-separated contexts to skip waiting)
#
# To bypass waiting for CI, set CONTEXTS:
#   export CONTEXTS="ci (3.10),ci (3.11)"

OWNER="${OWNER:-gadwa2026}"
REPO="${REPO:-Test-repo-01}"
BRANCH="${BRANCH:-main}"
REQUIRED_APPROVALS="${REQUIRED_APPROVALS:-1}"
ENFORCE_ADMINS="${ENFORCE_ADMINS:-true}"
REQUIRE_LINEAR_HISTORY="${REQUIRE_LINEAR_HISTORY:-false}"
REQUIRE_CONVERSATION_RESOLUTION="${REQUIRE_CONVERSATION_RESOLUTION:-false}"
CREATE_RELEASE="${CREATE_RELEASE:-true}"
RELEASE_TAG="${RELEASE_TAG:-v0.1.0}"
RELEASE_DRAFT="${RELEASE_DRAFT:-true}"
RELEASE_BODY="${RELEASE_BODY:-Initial release}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-900}"
POLL_INTERVAL="${POLL_INTERVAL:-15}"

API_BASE="https://api.github.com"
AUTH_HEADER=""
if [ -n "${GITHUB_TOKEN:-}" ]; then
  AUTH_HEADER="Authorization: token ${GITHUB_TOKEN}"
fi

jq_or_die() { command -v jq >/dev/null 2>&1 || { echo "jq is required. Install jq and retry."; exit 2; }; }

api_get() {
  local url="$1"
  if [ -n "$AUTH_HEADER" ]; then
    curl -sSL -H "$AUTH_HEADER" -H "Accept: application/vnd.github+json" "$url"
  else
    curl -sSL -H "Accept: application/vnd.github+json" "$url"
  fi
}

wait_for_successful_run() {
  jq_or_die
  echo "Dry-run: waiting up to ${TIMEOUT_SECONDS}s for a successful Actions run on ${BRANCH}..."
  local elapsed=0
  while [ $elapsed -lt $TIMEOUT_SECONDS ]; do
    runs_json=$(api_get "${API_BASE}/repos/${OWNER}/${REPO}/actions/runs?branch=${BRANCH}&per_page=5")
    run_id=$(echo "$runs_json" | jq -r '.workflow_runs[] | select(.conclusion=="success") | .id' | head -n1 || true)
    if [ -n "$run_id" ]; then
      echo "Found successful run id: $run_id"
      echo "$run_id"
      return 0
    fi
    sleep $POLL_INTERVAL
    elapsed=$((elapsed + POLL_INTERVAL))
  done
  echo "Timed out waiting for a successful Actions run on ${BRANCH} after ${TIMEOUT_SECONDS}s" >&2
  return 1
}

get_job_names_from_run() {
  jq_or_die
  local run_id="$1"
  jobs_json=$(api_get "${API_BASE}/repos/${OWNER}/${REPO}/actions/runs/${run_id}/jobs")
  echo "$jobs_json" | jq -r '.jobs[].name' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | awk '!seen[$0]++{print $0}'
}

# Main
jq_or_die

if [ -n "${CONTEXTS:-}" ]; then
  echo "Using user-provided CONTEXTS."
  IFS=',' read -r -a contexts_array <<< "$CONTEXTS"
else
  run_id=$(wait_for_successful_run) || {
    echo "No successful run found. To bypass, set CONTEXTS env var (comma-separated)." >&2
    exit 1
  }
  mapfile -t contexts_array < <(get_job_names_from_run "$run_id")
fi

if [ ${#contexts_array[@]} -eq 0 ]; then
  echo "No status-check contexts discovered. Exiting." >&2
  exit 1
fi

echo
echo "Discovered status-check contexts:"
for c in "${contexts_array[@]}"; do echo " - $c"; done
echo

# Build contexts JSON array
contexts_json=$(printf '%s
' "${contexts_array[@]}" | jq -R . | jq -s .)

# Build branch protection payload (printed)
protection_payload=$(jq -n \
  --argjson contexts "$contexts_json" \
  --argjson require_approvals "${REQUIRED_APPROVALS}" \
  --argjson enforce_admins "${ENFORCE_ADMINS}" \
  --argjson require_linear_history "${REQUIRE_LINEAR_HISTORY}" \
  --argjson require_conv_res "${REQUIRE_CONVERSATION_RESOLUTION}" \
  '{
    required_status_checks: { strict: true, contexts: $contexts },
    enforce_admins: $enforce_admins,
    required_pull_request_reviews: {
      dismiss_stale_reviews: true,
      require_code_owner_reviews: true,
      required_approving_review_count: $require_approvals
    },
    restrictions: null,
    required_linear_history: $require_linear_history,
    required_conversation_resolution: $require_conv_res
  }'
)

echo "DRY RUN — Branch protection payload (JSON):"
echo "$protection_payload" | jq .
echo

if [ "${CREATE_RELEASE}" = "true" ] || [ "${CREATE_RELEASE}" = "True" ]; then
  release_payload=$(jq -n \
    --arg tag "${RELEASE_TAG}" \
    --arg body "${RELEASE_BODY}" \
    --argjson draft "${RELEASE_DRAFT}" \
    '{tag_name:$tag, target_commitish:"main", name:$tag, body:$body, draft:$draft, prerelease:false}')
  echo "DRY RUN — Release payload (JSON):"
  echo "$release_payload" | jq .
  echo
fi

echo "Dry-run complete. No changes were applied."
echo
echo "Notes:"
echo "- If you want to actually apply these payloads, run the script that PATCHes /repos/:owner/:repo/branches/:branch/protection and POSTs /repos/:owner/:repo/releases with these JSON bodies."
echo "- To bypass waiting for a successful workflow run, set CONTEXTS=\"context1,context2\" before running."

echo "Security note: Do not paste your PAT into chat. If you set GITHUB_TOKEN locally, it is used only to query runs in this dry-run script."

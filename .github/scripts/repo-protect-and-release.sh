#!/usr/bin/env bash
set -euo pipefail

# repo-protect-and-release.sh
# This script applies branch protection and optionally creates a release.
# Usage:
#   export GITHUB_TOKEN="ghp_xxx"   # PAT with repo scope
#   ./repo-protect-and-release.sh
#
# Environment variable overrides (optional):
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

: "${GITHUB_TOKEN:?Please export GITHUB_TOKEN with a PAT having repo scope.}"

API_BASE="https://api.github.com"
AUTH_HEADER="Authorization: token ${GITHUB_TOKEN}"
ACCEPT_HEADER="Accept: application/vnd.github+json"

jq_or_die() { command -v jq >/dev/null 2>&1 || { echo "jq is required. Install jq and retry."; exit 2; }; }

api_get() { curl -sSL -H "${AUTH_HEADER}" -H "${ACCEPT_HEADER}" "$1"; }
api_put() { curl -sSL -X PUT -H "${AUTH_HEADER}" -H "${ACCEPT_HEADER}" -d "$2" "$1"; }
api_post() { curl -sSL -X POST -H "${AUTH_HEADER}" -H "${ACCEPT_HEADER}" -d "$2" "$1"; }

wait_for_successful_run() {
  jq_or_die
  echo "Waiting up to ${TIMEOUT_SECONDS}s for a successful Actions run on ${BRANCH}..."
  local elapsed=0
  while [ $elapsed -lt $TIMEOUT_SECONDS ]; do
    runs_json=$(api_get "${API_BASE}/repos/${OWNER}/${REPO}/actions/runs?branch=${BRANCH}&per_page=5")
    run_id=$(echo "$runs_json" | jq -r '.workflow_runs[] | select(.conclusion=="success") | .id' | head -n1 || true)
    if [ -n "$run_id" ]; then
      echo "Found successful run: $run_id"
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

main() {
  jq_or_die

  if [ -n "${CONTEXTS:-}" ]; then
    echo "Using user-specified contexts from CONTEXTS env var."
    IFS=',' read -r -a contexts_array <<< "$CONTEXTS"
  else
    run_id=$(wait_for_successful_run) || {
      echo "No successful run found. You can set CONTEXTS to bypass this check." >&2
      exit 1
    }
    mapfile -t contexts_array < <(get_job_names_from_run "$run_id")
  fi

  if [ ${#contexts_array[@]} -eq 0 ]; then
    echo "No status-check contexts found. Exiting." >&2
    exit 1
  fi

  echo "Using these status-check contexts:"
  for c in "${contexts_array[@]}"; do
    echo " - $c"
  done

  contexts_json=$(printf '%s\n' "${contexts_array[@]}" | jq -R . | jq -s .)

  protection_payload=$(jq -n \
    --argjson contexts "$contexts_json" \
    --argjson require_approvals ${REQUIRED_APPROVALS} \
    --argjson enforce_admins ${ENFORCE_ADMINS} \
    --argjson require_linear_history ${REQUIRE_LINEAR_HISTORY} \
    --argjson require_conv_res ${REQUIRE_CONVERSATION_RESOLUTION} \
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

  echo "Applying branch protection to ${BRANCH}..."
  protection_url="${API_BASE}/repos/${OWNER}/${REPO}/branches/${BRANCH}/protection"
  resp=$(api_put "$protection_url" "$protection_payload")
  echo "Branch protection response:"
  echo "$resp" | jq -r '. | if .message then "Error: \(.message)" else "Protection applied successfully" end'

  if [ "${CREATE_RELEASE}" = "true" ] || [ "${CREATE_RELEASE}" = "True" ]; then
    release_payload=$(jq -n --arg tag "${RELEASE_TAG}" --arg body "${RELEASE_BODY}" --argjson draft "${RELEASE_DRAFT}" '{tag_name:$tag, target_commitish:"main", name:$tag, body:$body, draft:$draft, prerelease:false}')
    echo "Creating release ${RELEASE_TAG} (draft=${RELEASE_DRAFT})..."
    rel=$(api_post "${API_BASE}/repos/${OWNER}/${REPO}/releases" "$release_payload")
    echo "$rel" | jq -r '.html_url // .message'
  fi

  echo "Done."
}

main "$@"

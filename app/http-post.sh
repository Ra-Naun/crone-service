#!/usr/bin/env sh
# Simple HTTP runner for Cronicle Command plugin.
# Reads endpoint and auth from environment variables and performs an HTTP request.
# Expected env vars (set per Event in Cronicle UI):
#   ENDPOINT_PATH   - relative path (e.g. /api/cron/billing/renew-due) OR full URL
#   BASE_URL        - base URL (e.g. https://your-app.io). Ignored if ENDPOINT_PATH is absolute
#   APP_URL         - optional fallback base URL if BASE_URL not provided
#   CRON_SECRET     - value for header: x-cron-key
#   METHOD          - HTTP method (default: POST)
#   CONTENT_TYPE    - Content-Type header (default: application/json)
#   BODY            - JSON string body (default: {})
#   QUERY           - query string without '?', e.g. hours=48 (optional)
#   TIMEOUT         - request timeout seconds (default: 60)
#
# Exit codes:
#   0  on HTTP 2xx
#   1  on non-2xx or request error

set -eu

ENDPOINT_PATH="${ENDPOINT_PATH:-}"
BASE_URL_JOB="${BASE_URL:-}"
APP_URL_ENV="${APP_URL:-}"
CRON_SECRET_ENV="${CRON_SECRET:-}"
METHOD="${METHOD:-POST}"
CONTENT_TYPE="${CONTENT_TYPE:-application/json}"
BODY="${BODY:-{}}"
QUERY="${QUERY:-}"
TIMEOUT="${TIMEOUT:-60}"

if [ -z "$ENDPOINT_PATH" ]; then
  echo "[http-post] ENDPOINT_PATH is required" >&2
  exit 1
fi

# Build URL
case "$ENDPOINT_PATH" in
  http://*|https://*)
    URL="$ENDPOINT_PATH"
    ;;
  *)
    BASE="${BASE_URL_JOB:-${APP_URL_ENV:-}}"
    if [ -z "$BASE" ]; then
      echo "[http-post] BASE_URL/APP_URL not set and ENDPOINT_PATH is relative" >&2
      exit 1
    fi
    # Trim trailing slash
    BASE=$(printf "%s" "$BASE" | sed 's:/*$::')
    EP="$ENDPOINT_PATH"
    case "$EP" in
      /*) ;;
      *) EP="/$EP" ;;
    esac
    URL="$BASE$EP"
    ;;
esac

if [ -n "$QUERY" ]; then
  case "$URL" in
    *\?*) URL="$URL&$QUERY" ;;
    *) URL="$URL?$QUERY" ;;
  esac
fi

HDRS="-H Content-Type: ${CONTENT_TYPE}"
if [ -n "$CRON_SECRET_ENV" ]; then
  HDRS="$HDRS -H x-cron-key: ${CRON_SECRET_ENV}"
fi

echo "[http-post] ${METHOD} $URL"

TMP_OUT="/tmp/http_post_out.$$"
HTTP_CODE=0
if [ "$METHOD" = "GET" ] || [ "$METHOD" = "HEAD" ]; then
  HTTP_CODE=$(sh -c "curl -sS -m $TIMEOUT -o $TMP_OUT -w '%{http_code}' -X $METHOD $HDRS '$URL'") || true
else
  HTTP_CODE=$(sh -c "curl -sS -m $TIMEOUT -o $TMP_OUT -w '%{http_code}' -X $METHOD $HDRS --data '$BODY' '$URL'") || true
fi

echo "[http-post] HTTP $HTTP_CODE"
cat "$TMP_OUT" 2>/dev/null || true
rm -f "$TMP_OUT" || true

case "$HTTP_CODE" in
  2*) exit 0 ;;
  *) exit 1 ;;
esac


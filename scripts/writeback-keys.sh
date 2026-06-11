#!/usr/bin/env bash
# writeback-keys.sh — 새로 생성한 citationKey를 Zotero Cloud에 기록
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

if [[ -f "$REPO_DIR/.envrc" ]]; then
    set -a; source "$REPO_DIR/.envrc"; set +a
fi

SYNC_DIR="$REPO_DIR/.sync"
KEYS_FILE="$SYNC_DIR/new-keys.json"
ZOTERO_API="https://api.zotero.org"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; NC='\033[0m'
log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1" >&2; }

if [[ ! -f "$KEYS_FILE" ]]; then
    log_info "No new keys to sync back."
    exit 0
fi

count=$(jq 'length' "$KEYS_FILE")
if [[ "$count" -eq 0 ]]; then
    log_info "No new keys to sync back."
    exit 0
fi

log_info "Writing back $count citation keys to Zotero..."

success=0
failed=0

jq -r 'to_entries[] | "\(.key)\t\(.value)"' "$KEYS_FILE" | while IFS=$'\t' read -r zotero_key citekey; do
    # Get current version. Deleted items return plain text ("Item does not
    # exist"), not JSON — guard jq so a stale key can't crash the whole run.
    response=$(curl -s \
        -H "Zotero-API-Key: ${ZOTERO_API_KEY}" \
        "${ZOTERO_API}/users/${ZOTERO_USER_ID}/items/${zotero_key}")
    version=$(printf '%s' "$response" | jq -r '.version // empty' 2>/dev/null || true)

    if [[ -z "$version" ]]; then
        log_warn "  Skip $zotero_key (deleted or no version)"
        continue
    fi

    # PATCH citationKey
    http_code=$(curl -s -o /dev/null -w "%{http_code}" -X PATCH \
        -H "Zotero-API-Key: ${ZOTERO_API_KEY}" \
        -H "Content-Type: application/json" \
        -H "If-Unmodified-Since-Version: $version" \
        -d "{\"citationKey\": \"$citekey\"}" \
        "${ZOTERO_API}/users/${ZOTERO_USER_ID}/items/${zotero_key}")

    if [[ "$http_code" == "204" ]]; then
        log_success "  $zotero_key → $citekey"
    else
        log_warn "  $zotero_key failed (HTTP $http_code)"
    fi

    # Rate limit
    sleep 0.3
done

log_success "Writeback complete"
mv "$KEYS_FILE" "$KEYS_FILE.done"

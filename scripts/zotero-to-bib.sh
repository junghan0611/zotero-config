#!/usr/bin/env bash
#
# zotero-to-bib.sh - Zotero Cloud API -> BibTeX headless 동기화
#
# Usage:
#   ./zotero-to-bib.sh full    - 전체 동기화 (since=0)
#   ./zotero-to-bib.sh sync    - 증분 동기화 (since=last-version)
#   ./zotero-to-bib.sh status  - 동기화 상태 확인
#
# Requirements: curl, jq, python3
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
SYNC_DIR="$REPO_DIR/.sync"

# Output paths (프로젝트 내부, ~/org/resources 에서 symlink)
OUTPUT_DIR="$REPO_DIR/output"
BOOK_BIB="$OUTPUT_DIR/Book.bib"

# State files
ITEMS_FILE="$SYNC_DIR/items.json"
LAST_VERSION_FILE="$SYNC_DIR/last-version"

# API
ZOTERO_API="https://api.zotero.org"
PAGE_LIMIT=100

# Load .envrc from repo root
if [[ -f "$REPO_DIR/.envrc" ]]; then
    set -a
    source "$REPO_DIR/.envrc"
    set +a
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1" >&2; }

check_dependencies() {
    local missing=()
    for cmd in curl jq python3; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required commands: ${missing[*]}"
        exit 1
    fi
}

check_credentials() {
    if [[ -z "${ZOTERO_API_KEY:-}" ]]; then
        log_error "ZOTERO_API_KEY not set. Check .envrc"
        exit 1
    fi
    if [[ -z "${ZOTERO_USER_ID:-}" ]]; then
        log_error "ZOTERO_USER_ID not set. Check .envrc"
        exit 1
    fi
}

# Fetch items from Zotero API with pagination
# Args: $1 = since version (0 for full)
fetch_items() {
    local since="${1:-0}"
    local start=0
    local total=""
    local all_items="[]"
    local page=1

    log_info "Fetching items from Zotero API (since=$since)..."

    while true; do
        local url="${ZOTERO_API}/users/${ZOTERO_USER_ID}/items/top?format=json&limit=${PAGE_LIMIT}&start=${start}"
        if [[ "$since" != "0" ]]; then
            url="${url}&since=${since}"
        fi

        local tmp_headers
        tmp_headers=$(mktemp)

        local response
        response=$(curl -s -D "$tmp_headers" \
            -H "Zotero-API-Key: ${ZOTERO_API_KEY}" \
            "$url")

        # Extract headers
        local version
        version=$(grep -i "^Last-Modified-Version:" "$tmp_headers" | tr -d '\r' | awk '{print $2}')

        if [[ -z "$total" ]]; then
            total=$(grep -i "^Total-Results:" "$tmp_headers" | tr -d '\r' | awk '{print $2}')
            total="${total:-0}"
            log_info "Total items: $total"
        fi

        rm -f "$tmp_headers"

        # Count items in this page
        local count
        count=$(echo "$response" | jq 'length')

        if [[ "$count" -eq 0 ]]; then
            break
        fi

        log_info "Page $page: fetched $count items (start=$start)"

        # Merge into all_items
        all_items=$(echo "$all_items" "$response" | jq -s '.[0] + .[1]')

        # Save version
        if [[ -n "$version" ]]; then
            echo "$version" > "$LAST_VERSION_FILE"
        fi

        # Check if we got fewer than limit (last page)
        if [[ "$count" -lt "$PAGE_LIMIT" ]]; then
            break
        fi

        start=$((start + PAGE_LIMIT))
        page=$((page + 1))

        # Rate limit courtesy
        sleep 0.5
    done

    local fetched
    fetched=$(echo "$all_items" | jq 'length')
    log_success "Fetched $fetched items total"

    # Merge with existing items (incremental sync)
    if [[ "$since" != "0" && -f "$ITEMS_FILE" && "$fetched" -gt 0 ]]; then
        local existing
        existing=$(jq 'length' "$ITEMS_FILE")
        log_info "Merging $fetched new/updated items into $existing existing items..."
        # Merge: new items override existing by key
        jq -s '
          (.[0] | map({(.key): .}) | add // {}) *
          (.[1] | map({(.key): .}) | add // {})
          | to_entries | map(.value)
        ' "$ITEMS_FILE" <(echo "$all_items") > "${ITEMS_FILE}.tmp"
        mv "${ITEMS_FILE}.tmp" "$ITEMS_FILE"
        local merged
        merged=$(jq 'length' "$ITEMS_FILE")
        log_success "Merged: $merged items total"
    else
        echo "$all_items" | jq '.' > "$ITEMS_FILE"
    fi
}

do_full() {
    log_info "=== Full Sync ==="
    mkdir -p "$SYNC_DIR"
    fetch_items 0
    generate_bibtex
    writeback_keys
}

do_sync() {
    log_info "=== Incremental Sync ==="
    mkdir -p "$SYNC_DIR"

    local since=0
    if [[ -f "$LAST_VERSION_FILE" ]]; then
        since=$(cat "$LAST_VERSION_FILE")
        log_info "Last version: $since"
    else
        log_warn "No last-version found, falling back to full sync"
    fi

    fetch_items "$since"
    generate_bibtex
    writeback_keys
}

do_status() {
    log_info "=== Sync Status ==="

    if [[ -f "$LAST_VERSION_FILE" ]]; then
        log_info "Last synced version: $(cat "$LAST_VERSION_FILE")"
    else
        log_warn "Never synced (no last-version file)"
    fi

    if [[ -f "$ITEMS_FILE" ]]; then
        local count
        count=$(jq 'length' "$ITEMS_FILE")
        local size
        size=$(du -h "$ITEMS_FILE" | cut -f1)
        log_info "Cached items: $count ($size)"
    else
        log_warn "No cached items"
    fi

    for bib in "$OUTPUT_DIR"/*.bib; do
        if [[ -f "$bib" ]]; then
            local bib_count
            bib_count=$(grep -c "^@" "$bib" || true)
            log_info "$(basename "$bib"): $bib_count entries"
        fi
    done
}

generate_bibtex() {
    if [[ ! -f "$ITEMS_FILE" ]]; then
        log_error "No items file found at $ITEMS_FILE"
        exit 1
    fi

    local count
    count=$(jq 'length' "$ITEMS_FILE")
    log_info "Generating BibTeX from $count items..."

    local args=(
        --items "$ITEMS_FILE"
        --book-bib "$BOOK_BIB"
        --output-dir "$OUTPUT_DIR"
        --sync-dir "$SYNC_DIR"
    )

    if [[ -n "${DATA4LIBRARY_API_KEY:-}" ]]; then
        args+=(--data4lib-key "$DATA4LIBRARY_API_KEY")
    fi

    python3 "$SCRIPT_DIR/gen-bibtex.py" "${args[@]}"

    log_success "BibTeX generation complete"
    log_info "Book.bib: $BOOK_BIB"
    log_info "Output:   $OUTPUT_DIR/*.bib"
}

writeback_keys() {
    if [[ -f "$SYNC_DIR/new-keys.json" ]]; then
        local count
        count=$(jq 'length' "$SYNC_DIR/new-keys.json")
        if [[ "$count" -gt 0 ]]; then
            log_info "Writing back $count new citation keys to Zotero..."
            "$SCRIPT_DIR/writeback-keys.sh"
        fi
    fi
}

show_usage() {
    cat <<EOF
Usage: $(basename "$0") <command>

Commands:
  full     Full sync (fetch all items, regenerate BibTeX)
  sync     Incremental sync (fetch changes since last version)
  status   Show sync status

Examples:
  $(basename "$0") full
  $(basename "$0") sync
  $(basename "$0") status

EOF
}

# Main
check_dependencies
check_credentials

case "${1:-}" in
    full)    do_full ;;
    sync)    do_sync ;;
    status)  do_status ;;
    -h|--help|"")
        show_usage
        ;;
    *)
        log_error "Unknown command: $1"
        show_usage
        exit 1
        ;;
esac

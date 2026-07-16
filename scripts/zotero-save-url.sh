#!/usr/bin/env bash
#
# zotero-save-url.sh - Save URLs to Zotero without GUI using Translation Server
#
# Description:
#   Fetches metadata from a URL via Zotero Translation Server,
#   then uploads the item to your Zotero library via the Web API.
#
# Requirements:
#   - Zotero Translation Server running (Docker or standalone)
#   - Zotero API key with read/write permissions
#   - curl, jq
#
# Environment Variables:
#   ZOTERO_API_KEY            - Your Zotero API key (required)
#   ZOTERO_USER_ID            - Your Zotero user ID (required)
#   ZOTERO_TRANSLATION_SERVER - Translation Server URL (default: http://localhost:1969)
#
# Usage:
#   ./zotero-save-url.sh [--sync] [--json] <URL> [COLLECTION_KEY]
#
# Examples:
#   ./zotero-save-url.sh "https://arxiv.org/abs/2103.00020"
#   ./zotero-save-url.sh --sync "https://en.wikipedia.org/wiki/Vannevar_Bush"
#   ./zotero-save-url.sh --sync --json "https://www.nature.com/articles/s41586-021-03819-2" "ABC123XY"
#

set -euo pipefail

# Get script directory and load .envrc if exists
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# Load .envrc from repo root (supports both KEY=value and export KEY=value formats)
if [[ -f "$REPO_DIR/.envrc" ]]; then
    set -a  # auto-export all variables
    source "$REPO_DIR/.envrc"
    set +a
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
TRANSLATION_SERVER="${ZOTERO_TRANSLATION_SERVER:-http://localhost:1969}"
API_KEY="${ZOTERO_API_KEY:-}"
USER_ID="${ZOTERO_USER_ID:-}"
ZOTERO_API="https://api.zotero.org"
RUN_BIB_SYNC=0
OUTPUT_JSON=0

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

check_dependencies() {
    local missing=()

    if ! command -v curl &> /dev/null; then
        missing+=("curl")
    fi

    if ! command -v jq &> /dev/null; then
        missing+=("jq")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required commands: ${missing[*]}"
        log_info "Install with: nix-shell -p ${missing[*]}"
        exit 1
    fi
}

check_translation_server() {
    log_info "Checking Translation Server at $TRANSLATION_SERVER..."

    if ! curl -s --connect-timeout 5 "$TRANSLATION_SERVER" > /dev/null 2>&1; then
        log_error "Translation Server not responding at $TRANSLATION_SERVER"
        log_info ""
        log_info "To start the Translation Server:"
        log_info "  Docker:   docker run -d -p 1969:1969 zotero/translation-server"
        log_info "  NixOS:    See scripts/translation-server.nix"
        exit 1
    fi

    log_success "Translation Server is running"
}

check_credentials() {
    if [[ -z "$API_KEY" ]]; then
        log_error "ZOTERO_API_KEY not set"
        log_info ""
        log_info "Get your API key at: https://www.zotero.org/settings/keys"
        log_info "Then set: export ZOTERO_API_KEY='your_key_here'"
        exit 1
    fi

    if [[ -z "$USER_ID" ]]; then
        log_error "ZOTERO_USER_ID not set"
        log_info ""
        log_info "Find your User ID at: https://www.zotero.org/settings/keys"
        log_info "Then set: export ZOTERO_USER_ID='your_id_here'"
        exit 1
    fi
}

fetch_metadata() {
    local url="$1"
    log_info "Fetching metadata for: $url"

    local response
    response=$(curl -s -w "\n%{http_code}" -X POST \
        -H "Content-Type: text/plain" \
        -d "$url" \
        "$TRANSLATION_SERVER/web")

    local http_code
    http_code=$(echo "$response" | tail -n1)
    local body
    body=$(echo "$response" | sed '$d')

    if [[ "$http_code" != "200" ]]; then
        # Try JSON format for some endpoints
        response=$(curl -s -w "\n%{http_code}" -X POST \
            -H "Content-Type: application/json" \
            -d "{\"url\":\"$url\",\"sessionid\":\"\"}" \
            "$TRANSLATION_SERVER/web")

        http_code=$(echo "$response" | tail -n1)
        body=$(echo "$response" | sed '$d')

        if [[ "$http_code" != "200" ]]; then
            log_error "Failed to fetch metadata (HTTP $http_code)"
            log_info "Response: $body"

            # Fallback: create a basic webpage item
            log_warn "Creating fallback webpage item..."
            body=$(create_fallback_item "$url")
        fi
    fi

    echo "$body"
}

create_fallback_item() {
    local url="$1"
    local title
    title=$(echo "$url" | sed 's|https\?://||; s|/.*||')

    cat <<EOF
[{
    "itemType": "webpage",
    "title": "$title",
    "url": "$url",
    "accessDate": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}]
EOF
}

add_to_collection() {
    local metadata="$1"
    local collection_key="$2"

    if [[ -n "$collection_key" ]]; then
        log_info "Adding to collection: $collection_key"
        # Add collections array to each item
        metadata=$(echo "$metadata" | jq --arg col "$collection_key" \
            'if type == "array" then map(. + {"collections": [$col]}) else . + {"collections": [$col]} end')
    fi

    echo "$metadata"
}

upload_to_zotero() {
    local metadata="$1"

    log_info "Uploading to Zotero library..."

    # Ensure metadata is an array
    if ! echo "$metadata" | jq -e 'if type == "array" then true else false end' > /dev/null 2>&1; then
        metadata="[$metadata]"
    fi

    # Use temp file to avoid shell escaping issues with special characters
    local tmpfile
    tmpfile=$(mktemp)
    echo "$metadata" > "$tmpfile"

    local response
    response=$(curl -s -w "\n%{http_code}" -X POST \
        -H "Zotero-API-Key: $API_KEY" \
        -H "Content-Type: application/json" \
        --data-binary @"$tmpfile" \
        "$ZOTERO_API/users/$USER_ID/items")

    rm -f "$tmpfile"

    local http_code
    http_code=$(echo "$response" | tail -n1)
    local body
    body=$(echo "$response" | sed '$d')

    if [[ "$http_code" == "200" ]]; then
        local success_count
        success_count=$(echo "$body" | jq '.successful | length')
        local failed_count
        failed_count=$(echo "$body" | jq '.failed | length')

        if [[ "$success_count" -gt 0 ]]; then
            log_success "Successfully saved $success_count item(s) to Zotero!"
            if [[ "$OUTPUT_JSON" -eq 0 ]]; then
                echo "$body" | jq -r '.successful | to_entries[] | "  Key: \(.value.key) - \(.value.data.title // \"Untitled\")"' >&2
            fi
        fi

        if [[ "$failed_count" -gt 0 ]]; then
            log_warn "Failed to save $failed_count item(s)"
            echo "$body" | jq '.failed' >&2
        fi

        if [[ "$success_count" -eq 0 ]]; then
            log_error "Upload completed but no items were saved"
            exit 1
        fi

        echo "$body"
        return 0
    fi

    log_error "Failed to upload to Zotero (HTTP $http_code)"
    echo "$body" | jq . >&2 2>/dev/null || echo "$body" >&2
    exit 1
}

extract_saved_items() {
    local upload_body="$1"
    echo "$upload_body" | jq -c '[.successful | to_entries[] | {
        zoteroKey: .value.key,
        title: (.value.data.title // "Untitled")
    }]'
}

run_bib_sync() {
    log_info "Running bib sync to generate BibTeX (read-only, no Cloud writeback)..."
    if [[ "$OUTPUT_JSON" -eq 1 ]]; then
        "$REPO_DIR/run.sh" bib sync >&2
    else
        "$REPO_DIR/run.sh" bib sync
    fi
}

fetch_item_from_zotero() {
    local zotero_key="$1"
    curl -s \
        -H "Zotero-API-Key: $API_KEY" \
        "$ZOTERO_API/users/$USER_ID/items/$zotero_key"
}

# Resolve the citation key from the generator's output. bib sync is read-only
# and never pins the key onto Zotero Cloud, so .data.citationKey stays empty for
# fresh saves — the deterministic key lives in .sync/new-keys.json (regenerated
# every sync). Fall back to .done for keys pinned by a prior explicit writeback.
lookup_citation_key_from_generated() {
    local zotero_key="$1"
    local pending_file="$REPO_DIR/.sync/new-keys.json"
    local done_file="$REPO_DIR/.sync/new-keys.json.done"
    local key=""
    if [[ -f "$pending_file" ]]; then
        key=$(jq -r --arg key "$zotero_key" '.[$key] // empty' "$pending_file")
    fi
    if [[ -z "$key" && -f "$done_file" ]]; then
        key=$(jq -r --arg key "$zotero_key" '.[$key] // empty' "$done_file")
    fi
    echo "$key"
}

resolve_saved_items() {
    local saved_items_json="$1"
    local resolved='[]'

    while IFS=$'\t' read -r zotero_key _title; do
        [[ -z "$zotero_key" ]] && continue

        local item_json
        item_json=$(fetch_item_from_zotero "$zotero_key")

        local citation_key
        citation_key=$(echo "$item_json" | jq -r '.data.citationKey // empty')
        if [[ -z "$citation_key" ]]; then
            citation_key=$(lookup_citation_key_from_generated "$zotero_key")
        fi

        local title
        title=$(echo "$item_json" | jq -r '.data.title // empty')
        local item_url
        item_url=$(echo "$item_json" | jq -r '.data.url // empty')
        local item_type
        item_type=$(echo "$item_json" | jq -r '.data.itemType // empty')

        resolved=$(echo "$resolved" | jq -c \
            --arg zoteroKey "$zotero_key" \
            --arg citationKey "$citation_key" \
            --arg title "$title" \
            --arg url "$item_url" \
            --arg itemType "$item_type" \
            '. + [{
                zoteroKey: $zoteroKey,
                citationKey: $citationKey,
                title: $title,
                url: $url,
                itemType: $itemType
            }]')
    done < <(echo "$saved_items_json" | jq -r '.[] | [.zoteroKey, .title] | @tsv')

    echo "$resolved"
}

print_final_json() {
    local url="$1"
    local collection_key="$2"
    local saved_items_json="$3"
    local resolved_items_json="$4"

    jq -n \
        --arg url "$url" \
        --arg collectionKey "$collection_key" \
        --argjson saved "$saved_items_json" \
        --argjson resolved "$resolved_items_json" \
        --argjson synced "$([[ "$RUN_BIB_SYNC" -eq 1 ]] && echo true || echo false)" \
        '{
            url: $url,
            collectionKey: (if $collectionKey == "" then null else $collectionKey end),
            synced: $synced,
            saved: $saved,
            resolved: $resolved
        }'
}

print_final_human() {
    local resolved_items_json="$1"

    if [[ "$RUN_BIB_SYNC" -eq 1 ]]; then
        log_success "Citation keys after bib sync:"
        echo "$resolved_items_json" | jq -r '.[] |
            if (.citationKey // "") != "" then
                "  \(.zoteroKey) → \(.citationKey) - \(.title)"
            else
                "  \(.zoteroKey) → [citationKey missing] - \(.title)"
            end' >&2
    fi

    echo "" >&2
    log_success "Done!"
}

show_usage() {
    cat <<EOF
Usage: $(basename "$0") [--sync] [--json] <URL> [COLLECTION_KEY]

Save a URL to Zotero without using the GUI.

Arguments:
  URL             The URL to save (required)
  COLLECTION_KEY  Optional Zotero collection key to add the item to

Flags:
  --sync          Run './run.sh bib sync' after saving and resolve citationKey
  --json          Emit machine-readable JSON to stdout

Environment Variables:
  ZOTERO_API_KEY            Your Zotero API key (required)
  ZOTERO_USER_ID            Your Zotero user ID (required)
  ZOTERO_TRANSLATION_SERVER Translation Server URL (default: http://localhost:1969)

Examples:
  $(basename "$0") "https://arxiv.org/abs/2103.00020"
  $(basename "$0") --sync "https://en.wikipedia.org/wiki/Vannevar_Bush"
  $(basename "$0") --sync --json "https://www.nature.com/articles/s41586-021-03819-2" "ABC123XY"

Setup:
  1. Get API key: https://www.zotero.org/settings/keys
  2. Start Translation Server: docker run -d -p 1969:1969 zotero/translation-server
  3. Set environment variables in ~/.bashrc or ~/.zshrc

EOF
}

parse_args() {
    URL_ARG=""
    COLLECTION_KEY_ARG=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --sync|--bib-sync)
                RUN_BIB_SYNC=1
                shift
                ;;
            --json)
                OUTPUT_JSON=1
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            --)
                shift
                break
                ;;
            -*)
                log_error "Unknown flag: $1"
                show_usage >&2
                exit 1
                ;;
            *)
                if [[ -z "$URL_ARG" ]]; then
                    URL_ARG="$1"
                elif [[ -z "$COLLECTION_KEY_ARG" ]]; then
                    COLLECTION_KEY_ARG="$1"
                else
                    log_error "Too many positional arguments"
                    show_usage >&2
                    exit 1
                fi
                shift
                ;;
        esac
    done

    if [[ $# -gt 0 ]]; then
        while [[ $# -gt 0 ]]; do
            if [[ -z "$URL_ARG" ]]; then
                URL_ARG="$1"
            elif [[ -z "$COLLECTION_KEY_ARG" ]]; then
                COLLECTION_KEY_ARG="$1"
            else
                log_error "Too many positional arguments"
                show_usage >&2
                exit 1
            fi
            shift
        done
    fi

    if [[ -z "$URL_ARG" ]]; then
        show_usage
        exit 1
    fi
}

main() {
    parse_args "$@"

    local url="$URL_ARG"
    local collection_key="$COLLECTION_KEY_ARG"

    echo "" >&2
    echo "=== Zotero URL Saver ===" >&2
    echo "" >&2

    check_dependencies
    check_credentials
    check_translation_server

    local metadata
    metadata=$(fetch_metadata "$url")

    if [[ -n "$collection_key" ]]; then
        metadata=$(add_to_collection "$metadata" "$collection_key")
    fi

    local upload_body
    upload_body=$(upload_to_zotero "$metadata")

    local saved_items_json
    saved_items_json=$(extract_saved_items "$upload_body")

    local resolved_items_json='[]'
    if [[ "$RUN_BIB_SYNC" -eq 1 ]]; then
        run_bib_sync
        resolved_items_json=$(resolve_saved_items "$saved_items_json")
    fi

    if [[ "$OUTPUT_JSON" -eq 1 ]]; then
        print_final_json "$url" "$collection_key" "$saved_items_json" "$resolved_items_json"
    else
        print_final_human "$resolved_items_json"
    fi
}

main "$@"

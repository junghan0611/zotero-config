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
#   ZOTERO_API_KEY           - Your Zotero API key (required)
#   ZOTERO_USER_ID           - Your Zotero user ID (required)
#   ZOTERO_TRANSLATION_SERVER - Translation Server URL (default: http://localhost:1969)
#
# Usage:
#   ./zotero-save-url.sh <URL> [COLLECTION_KEY]
#
# Examples:
#   ./zotero-save-url.sh "https://arxiv.org/abs/2103.00020"
#   ./zotero-save-url.sh "https://www.nature.com/articles/s41586-021-03819-2" "ABC123XY"
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

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
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
    # Use stderr for log messages since stdout is captured as return value
    echo -e "${BLUE}[INFO]${NC} Fetching metadata for: $url" >&2

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
            echo -e "${RED}[ERROR]${NC} Failed to fetch metadata (HTTP $http_code)" >&2
            echo -e "${BLUE}[INFO]${NC} Response: $body" >&2

            # Fallback: create a basic webpage item
            echo -e "${YELLOW}[WARN]${NC} Creating fallback webpage item..." >&2
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

            # Show item keys
            echo "$body" | jq -r '.successful | to_entries[] | "  Key: \(.value.key) - \(.value.data.title // "Untitled")"'
        fi

        if [[ "$failed_count" -gt 0 ]]; then
            log_warn "Failed to save $failed_count item(s)"
            echo "$body" | jq '.failed'
        fi
    else
        log_error "Failed to upload to Zotero (HTTP $http_code)"
        echo "$body" | jq . 2>/dev/null || echo "$body"
        exit 1
    fi
}

show_usage() {
    cat <<EOF
Usage: $(basename "$0") <URL> [COLLECTION_KEY]

Save a URL to Zotero without using the GUI.

Arguments:
  URL             The URL to save (required)
  COLLECTION_KEY  Optional Zotero collection key to add the item to

Environment Variables:
  ZOTERO_API_KEY            Your Zotero API key (required)
  ZOTERO_USER_ID            Your Zotero user ID (required)
  ZOTERO_TRANSLATION_SERVER Translation Server URL (default: http://localhost:1969)

Examples:
  $(basename "$0") "https://arxiv.org/abs/2103.00020"
  $(basename "$0") "https://www.nature.com/articles/s41586-021-03819-2" "ABC123XY"

Setup:
  1. Get API key: https://www.zotero.org/settings/keys
  2. Start Translation Server: docker run -d -p 1969:1969 zotero/translation-server
  3. Set environment variables in ~/.bashrc or ~/.zshrc

EOF
}

main() {
    if [[ $# -lt 1 ]] || [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
        show_usage
        exit 0
    fi

    local url="$1"
    local collection_key="${2:-}"

    echo ""
    echo "=== Zotero URL Saver ==="
    echo ""

    check_dependencies
    check_credentials
    check_translation_server

    local metadata
    metadata=$(fetch_metadata "$url")

    if [[ -n "$collection_key" ]]; then
        metadata=$(add_to_collection "$metadata" "$collection_key")
    fi

    upload_to_zotero "$metadata"

    echo ""
    log_success "Done!"
}

main "$@"

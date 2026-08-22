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

# 실사용 서지 출력면 — Syncthing이 기기 간에 나르는 유일한 공유 산출물.
# 렌더가 이 실파일에 직접 내려앉으므로 서지 등록/동기화에 Git이 개입하지 않는다.
BIB_DIR="${ZOTERO_BIB_DIR:-$HOME/sync/org/resources/bib}"
BOOK_BIB="$BIB_DIR/Book.bib"

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

# ---------------------------------------------------------------------------
# Single-writer lock for the device-local `.sync` mutation boundary
# ---------------------------------------------------------------------------
#
# `.sync/` is per-device state, but several local writers can reach for it at
# once: an org steward's `pin --sync`, a `save --sync`, a manual `bib full`, an
# OpenClaw bot. Two concurrent fetches corrupt each other — measured: a second
# `bib full` wiped the first one's active fetch staging directory, so the first
# silently lost every page from 26 on.
#
# So every writer (full / sync / writeback) takes an exclusive, NON-BLOCKING
# flock first and is rejected honestly if someone else holds it. `status` is
# read-only and takes no lock.
#
# The lock lives on a file descriptor, so the kernel releases it when the
# process dies — a SIGKILL leaves no stale lock behind.
SYNC_LOCK_FILE="$SYNC_DIR/.lock"
SYNC_LOCK_FD=""
SYNC_LOCK_CMD=""

stamp_sync_lock() {
    : > "$SYNC_LOCK_FILE"
    printf 'pid=%s cmd=%s host=%s started=%s\n' \
        "$$" "${SYNC_LOCK_CMD:-?}" "$(hostname 2>/dev/null || echo ?)" \
        "$(date -Iseconds 2>/dev/null || echo ?)" >&"$SYNC_LOCK_FD"
    log_info "Acquired .sync writer lock (pid $$)"
}

acquire_sync_lock() {
    mkdir -p "$SYNC_DIR"
    exec {SYNC_LOCK_FD}>>"$SYNC_LOCK_FILE"

    if flock -n "$SYNC_LOCK_FD"; then
        stamp_sync_lock
        return 0
    fi

    local holder pid
    holder=$(head -1 "$SYNC_LOCK_FILE" 2>/dev/null || true)
    pid=$(sed -n 's/^pid=\([0-9]*\).*/\1/p' <<<"$holder")

    # 보유 프로세스가 이미 죽었다면, 아직 fd 를 물고 있는 것은 곧 끝날 자식뿐이다
    # (bash 의 {fd} 리다이렉션은 close-on-exec 이 아니라 자식이 상속한다 — 실측).
    # 남의 락을 강제로 깨지 않고, 커널이 놓을 때까지만 짧게 기다린다.
    if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then
        log_warn "락 보유 프로세스 pid $pid 는 이미 없다 — 커널이 해제할 때까지 최대 10초 대기"
        if flock -w 10 "$SYNC_LOCK_FD"; then
            stamp_sync_lock
            return 0
        fi
    fi

    log_error "다른 프로세스가 .sync 를 쓰는 중이다 — 이 실행을 거부한다."
    log_error "  lock:   $SYNC_LOCK_FILE"
    log_error "  holder: ${holder:-unknown}"
    log_error "  동시 실행은 서로의 fetch staging 을 지우고 캐시/커서를 엉키게 한다."
    log_error "  그쪽이 끝난 뒤 다시 실행하라 (락은 보유 프로세스가 끝나면 자동 해제된다)."
    exec {SYNC_LOCK_FD}>&-
    return 1
}

# ---------------------------------------------------------------------------
# Cache / cursor commit order
# ---------------------------------------------------------------------------
#
# `.sync/last-version` is a CURSOR: the next incremental sync asks Zotero only
# for items modified after it. So the cursor may never run ahead of the cache —
# if it does, every page fetched after the crash is skipped forever and the
# skipped items silently vanish from the bibliography.
#
# Measured incident: `bib full` was killed at page 44/63. The old loop wrote the
# cursor once PER PAGE, before any merge, so `items.json` stayed at the old
# 6223 items while `last-version` had already jumped to 35790. A retry would
# have asked for "changes since 35790" and never re-fetched pages 44-63.
#
# The rule this file now enforces:
#
#   fetch every page  →  commit the cache (temp + atomic rename)
#                     →  prune deletions
#                     →  ONLY THEN commit the cursor
#
# A signal, a timeout, or a network failure anywhere before the last step leaves
# the old (cache, cursor) pair intact. The one asymmetry left is harmless and
# deliberate: a crash between cache commit and cursor commit leaves the cache
# NEWER than the cursor, so the next sync re-fetches a superset and the merge
# (an upsert keyed by item key) absorbs it.

# Results of the last fetch_items call (set by it, read by the caller).
FETCH_FILE=""      # temp file holding the fetched JSON array
FETCH_COUNT=0      # number of items fetched
FETCH_VERSION=""   # newest Last-Modified-Version header seen (empty = do not commit)

# Fetch items from Zotero API with pagination.
# Writes NOTHING to $ITEMS_FILE or $LAST_VERSION_FILE — it only fills FETCH_*.
# Args: $1 = since version (0 for full)
fetch_items() {
    local since="${1:-0}"
    local start=0
    local total=""
    local page=1

    FETCH_FILE=""
    FETCH_COUNT=0
    FETCH_VERSION=""

    # 이전 SIGKILL 이 남긴 잔여물 청소. **충분히 오래된 것만** 지운다.
    #
    # 실측 사고: 여기가 원래 `rm -rf "$SYNC_DIR"/.fetch.*` 였다. 두 번째 sync 가
    # 시작하면서 먼저 돌던 sync 의 **활성** staging 디렉터리를 지워버렸고, 그쪽은
    # 페이지 26 부터 쓰기에 실패해 fetch 총계가 0 이 됐다. 나이 조건 + 아래 단일
    # 쓰기 락, 두 겹으로 다시는 남의 진행 중 디렉터리를 건드리지 않게 한다.
    find "$SYNC_DIR" -maxdepth 1 \
        \( -name '.fetch.*' -o -name '.fetched.*' \) -mmin +60 \
        -exec rm -rf {} + 2>/dev/null || true

    log_info "Fetching items from Zotero API (since=$since)..."

    # Pages land as separate files and are combined once at the end. Growing a
    # single shell variable with jq per page is quadratic and was a large part
    # of why the full sync ran long enough to be killed.
    local pages_dir
    pages_dir=$(mktemp -d "$SYNC_DIR/.fetch.XXXXXX")

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

        # Remember the reported version in memory only. It is committed to disk
        # by commit_version(), after the cache is safely in place.
        if [[ -n "$version" ]]; then
            FETCH_VERSION="$version"
        fi

        # Count items in this page
        local count
        count=$(printf '%s' "$response" | jq 'length' 2>/dev/null) || {
            log_error "Malformed response on page $page — aborting fetch (cache and cursor untouched)"
            rm -rf "$pages_dir"
            return 1
        }

        if [[ "$count" -eq 0 ]]; then
            break
        fi

        log_info "Page $page: fetched $count items (start=$start)"
        printf '%s' "$response" > "$pages_dir/page-$(printf '%05d' "$page").json"

        # Check if we got fewer than limit (last page)
        if [[ "$count" -lt "$PAGE_LIMIT" ]]; then
            break
        fi

        start=$((start + PAGE_LIMIT))
        page=$((page + 1))

        # Rate limit courtesy
        sleep 0.5
    done

    local combined
    combined=$(mktemp "$SYNC_DIR/.fetched.XXXXXX")
    if compgen -G "$pages_dir/page-*.json" >/dev/null; then
        jq -s 'add // []' "$pages_dir"/page-*.json > "$combined"
    else
        printf '[]' > "$combined"
    fi
    rm -rf "$pages_dir"

    FETCH_FILE="$combined"
    FETCH_COUNT=$(jq 'length' "$FETCH_FILE")
    log_success "Fetched $FETCH_COUNT items total"
}

# Replace the cache with the fetched set (full sync). Temp + atomic rename.
replace_cache() {
    jq '.' "$FETCH_FILE" > "${ITEMS_FILE}.tmp"
    mv -f "${ITEMS_FILE}.tmp" "$ITEMS_FILE"
    log_success "Cache replaced: $(jq 'length' "$ITEMS_FILE") items"
}

# Upsert the fetched set into the cache (incremental). Temp + atomic rename.
merge_cache() {
    local existing
    existing=$(jq 'length' "$ITEMS_FILE")
    log_info "Merging $FETCH_COUNT new/updated items into $existing existing items..."
    jq -s '
      (.[0] | map({(.key): .}) | add // {}) *
      (.[1] | map({(.key): .}) | add // {})
      | to_entries | map(.value)
    ' "$ITEMS_FILE" "$FETCH_FILE" > "${ITEMS_FILE}.tmp"
    mv -f "${ITEMS_FILE}.tmp" "$ITEMS_FILE"
    log_success "Merged: $(jq 'length' "$ITEMS_FILE") items total"
}

# Commit the cursor. Call this LAST — never before the cache is in place.
commit_version() {
    local version="$1"
    if [[ -z "$version" ]]; then
        log_warn "No Last-Modified-Version reported — leaving cursor at $(cat "$LAST_VERSION_FILE" 2>/dev/null || echo none)"
        return 0
    fi
    printf '%s\n' "$version" > "${LAST_VERSION_FILE}.tmp"
    mv -f "${LAST_VERSION_FILE}.tmp" "$LAST_VERSION_FILE"
    log_success "Cursor committed: last-version=$version"
}

cleanup_fetch() {
    [[ -n "$FETCH_FILE" && -f "$FETCH_FILE" ]] && rm -f "$FETCH_FILE"
    FETCH_FILE=""
    return 0
}

# Remove items deleted on Zotero Cloud from the local cache.
# Incremental sync (/items/top with since) never reports deletions, so stale
# items accumulate and later crash writeback (deleted items 404 as plain text).
# Full sync rebuilds from /items/top, which already excludes deleted items.
#
# Returns NONZERO on any failure. That matters: deletions are only ever visible
# to a request that carries the OLD `since`, so if this request fails and the
# caller advances the cursor anyway, those deletions are skipped forever. The
# caller must refuse to commit the cursor when this returns nonzero.
# Args: $1 = since version (fetch deletions newer than this)
prune_deleted() {
    local since="${1:-0}"
    [[ -f "$ITEMS_FILE" ]] || return 0

    log_info "Checking for items deleted on Zotero since version $since..."

    # -f → an HTTP error page becomes a nonzero exit instead of a body to parse.
    local deleted status=0
    deleted=$(curl -sf \
        -H "Zotero-API-Key: ${ZOTERO_API_KEY}" \
        "${ZOTERO_API}/users/${ZOTERO_USER_ID}/deleted?since=${since}") || status=$?
    if [[ "$status" -ne 0 ]]; then
        log_error "Deleted-items request failed (curl exit $status) — cursor must NOT advance"
        return 1
    fi

    # Validate JSON before trusting it (network/error pages return non-JSON).
    local del_array
    del_array=$(printf '%s' "$deleted" | jq -c '.items // []' 2>/dev/null) || {
        log_error "Could not parse deleted items list — cursor must NOT advance"
        return 1
    }

    local del_count
    del_count=$(printf '%s' "$del_array" | jq 'length')
    if [[ "$del_count" -eq 0 ]]; then
        log_info "No deleted items since version $since"
        return 0
    fi

    jq --argjson del "$del_array" '
        ($del | map({(.): true}) | add // {}) as $set
        | map(select($set[.key] | not))
    ' "$ITEMS_FILE" > "${ITEMS_FILE}.tmp" && mv "${ITEMS_FILE}.tmp" "$ITEMS_FILE"

    local remaining
    remaining=$(jq 'length' "$ITEMS_FILE")
    log_success "Pruned up to $del_count deleted key(s) — $remaining items remain"
}

do_full() {
    log_info "=== Full Sync ==="
    mkdir -p "$SYNC_DIR"

    fetch_items 0 || return 1
    if [[ "$FETCH_COUNT" -eq 0 ]]; then
        log_error "Full sync returned 0 items — refusing to replace the cache"
        cleanup_fetch
        return 1
    fi
    replace_cache          # 1. cache first
    cleanup_fetch
    commit_version "$FETCH_VERSION"   # 2. cursor only after the cache is safe

    generate_bibtex
    # NOTE: read-only. sync/full never mutate Zotero Cloud. Citation keys land
    # in $BIB_DIR/*.bib (the source of truth for citar) and in .sync/new-keys.json.
    # To PIN keys back onto Zotero Cloud items, run an explicit `writeback`.
}

do_sync() {
    log_info "=== Incremental Sync ==="
    mkdir -p "$SYNC_DIR"

    local since=0
    if [[ ! -f "$ITEMS_FILE" ]]; then
        log_warn "items.json missing — cannot merge incremental data, doing a full sync"
    elif [[ -f "$LAST_VERSION_FILE" ]]; then
        since=$(cat "$LAST_VERSION_FILE")
        log_info "Last version: $since"
    else
        log_warn "No last-version found, falling back to full sync"
    fi

    fetch_items "$since" || return 1

    if [[ "$since" == "0" ]]; then
        if [[ "$FETCH_COUNT" -eq 0 ]]; then
            log_error "Full sync returned 0 items — refusing to replace the cache"
            cleanup_fetch
            return 1
        fi
        replace_cache
    elif [[ "$FETCH_COUNT" -eq 0 ]]; then
        # 변경 없음 — 캐시는 그대로 둔다. 커서는 아래에서 옮겨도 안전하다:
        # 이 응답이 "since 이후 수정된 항목 없음"을 보증하고, 삭제는 바로 다음
        # prune_deleted 가 같은 since 로 처리한 뒤에야 커밋되기 때문이다.
        log_info "No changes since version $since"
    else
        merge_cache
    fi
    cleanup_fetch

    # 삭제 반영도 커서 커밋 전에 끝낸다 (/items/top 은 삭제를 보고하지 않는다).
    # 실패하면 커서를 절대 옮기지 않는다 — 옮기면 그 삭제들을 영영 못 본다.
    if ! prune_deleted "$since"; then
        log_error "Deletion sync failed — leaving the cursor at its previous value."
        log_error "  캐시가 커서보다 새로운 상태로 남는다 (안전한 방향: 다음 sync 가 superset 을 다시 받는다)."
        generate_bibtex
        return 1
    fi

    commit_version "$FETCH_VERSION"   # 마지막 — 캐시가 확정된 뒤에만
    generate_bibtex
    # read-only — see do_full note. Use `writeback` to pin keys to Zotero Cloud.
}

# Explicit, opt-in writeback of generated citation keys to Zotero Cloud.
# Kept OUT of sync/full so a routine pull can never mutate the treasure vault.
do_writeback() {
    log_info "=== Writeback (explicit) ==="
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

    for bib in "$BIB_DIR"/*.bib; do
        if [[ -f "$bib" ]]; then
            local bib_count
            bib_count=$(grep -c "^@" "$bib" || true)
            log_info "$(basename "$bib"): $bib_count entries"
        fi
    done
}

# staging 설치 규율은 gh-starred 렌더러와 공유한다 (scripts/lib-install.sh).
# shellcheck source=lib-install.sh
source "$SCRIPT_DIR/lib-install.sh"

generate_bibtex() (
    if [[ ! -f "$ITEMS_FILE" ]]; then
        log_error "No items file found at $ITEMS_FILE"
        exit 1
    fi

    local count
    count=$(jq 'length' "$ITEMS_FILE")

    # 안전장치: 아이템이 비정상적으로 적으면 중단
    if [[ "$count" -lt 100 ]]; then
        log_error "items.json has only $count items (expected 1000+). Aborting to prevent data loss."
        log_error "Run './run.sh bib full' to recover."
        exit 1
    fi

    log_info "Generating BibTeX from $count items..."

    # Generate and sanitize in staging so the comparison happens against the
    # final published form.
    #
    # The staging dir lives INSIDE $BIB_DIR so the install below is a
    # same-filesystem rename rather than a cross-device copy. Hidden name +
    # non-.bib suffix so a concurrent `bibcli`/citar glob never sees a
    # half-written file. The dir is removed on exit — no staging residue.
    mkdir -p "$BIB_DIR"
    local staging_dir
    staging_dir=$(mktemp -d "$BIB_DIR/.bibstage.XXXXXX")
    trap 'rm -rf "$staging_dir"' EXIT

    # gen-bibtex is network-free: keeps existing citationKey, else local fallback.
    # KDC assist is NOT on this path — bibcli lookup / human Zotero edit only.
    local args=(
        --items "$ITEMS_FILE"
        --book-bib "$staging_dir/Book.bib"
        --output-dir "$staging_dir"
        --sync-dir "$SYNC_DIR"
    )

    python3 "$SCRIPT_DIR/gen-bibtex.py" "${args[@]}"
    "$SCRIPT_DIR/sanitize-public-bib.sh" "$staging_dir"/*.bib

    local staged target
    for staged in "$staging_dir"/*.bib; do
        target="$BIB_DIR/$(basename "$staged")"
        # 렌더에 시각이 들어가지 않으므로 비교는 순수 바이트 동일성이다.
        # 같으면 실파일을 건드리지 않는다 → Syncthing에 no-op 전파가 없다.
        if [[ -f "$target" ]] && cmp -s "$target" "$staged"; then
            log_info "Unchanged: $target"
        else
            install_staged "$staged" "$target"
            log_success "Updated: $target"
        fi
    done

    log_success "BibTeX generation complete"
    log_info "Book.bib: $BOOK_BIB"
    log_info "Output:   $BIB_DIR/*.bib"
)

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
  full       Full sync (fetch all items, regenerate BibTeX) — read-only
  sync       Incremental sync (fetch changes since last version) — read-only
  writeback  Pin generated citation keys back onto Zotero Cloud (explicit, mutates)
  status     Show sync status

Examples:
  $(basename "$0") full
  $(basename "$0") sync
  $(basename "$0") writeback
  $(basename "$0") status

EOF
}

# Main
check_dependencies
check_credentials

case "${1:-}" in
    full)      SYNC_LOCK_CMD=full;      acquire_sync_lock || exit 1; do_full ;;
    sync)      SYNC_LOCK_CMD=sync;      acquire_sync_lock || exit 1; do_sync ;;
    writeback) SYNC_LOCK_CMD=writeback; acquire_sync_lock || exit 1; do_writeback ;;
    status)    do_status ;;   # read-only — no lock
    -h|--help|"")
        show_usage
        ;;
    *)
        log_error "Unknown command: $1"
        show_usage
        exit 1
        ;;
esac

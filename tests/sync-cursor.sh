#!/usr/bin/env bash
#
# sync-cursor.sh — `.sync/last-version` 커서 안전성 회귀 테스트
#
# 계약:
#   커서(last-version)는 캐시(items.json)보다 **앞서 갈 수 없다**. 앞서 가면
#   다음 증분 sync 가 그 사이 페이지를 영원히 건너뛰고 항목이 조용히 사라진다.
#
#   fetch 전 페이지 → 캐시 커밋(temp+rename) → 삭제 반영 → **그 다음에야** 커서 커밋
#
# 실측 사고: `bib full` 이 페이지 44/63 에서 kill 됐는데 옛 루프가 **페이지마다**
# 커서를 먼저 써서, items.json 은 6223(옛것) 그대로인데 last-version 만 35790 으로
# 튀었다. 재시도하면 44~63 페이지를 다시 받지 않는다.
#
# 네트워크 없음 — mock curl 이 fixture 라이브러리를 서빙한다.
# 실사용 bib 디렉터리와 실제 .sync/ 를 건드리지 않는다 (전부 mktemp).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
SRC="$REPO_DIR/scripts/zotero-to-bib.sh"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

pass=0; fail=0
ok()  { echo "  ok   — $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL — $1" >&2; fail=$((fail + 1)); }

# ---------------------------------------------------------------------------
echo "== 1. 정적: 커서 쓰기 지점이 하나뿐이고 fetch 루프 밖이다 =="

writes=$(grep -n '> *"\${\?LAST_VERSION_FILE' "$SRC" | wc -l)
[[ "$writes" -eq 1 ]] \
    && ok "last-version 쓰기 지점 1곳" \
    || bad "last-version 쓰기 지점이 $writes 곳 (기대 1)"

# fetch_items 본문에 커서 파일이 등장하면 안 된다
fetch_body=$(awk '/^fetch_items\(\) \{/,/^\}/' "$SRC")
if grep -q 'LAST_VERSION_FILE' <<<"$fetch_body"; then
    bad "fetch_items 본문이 LAST_VERSION_FILE 을 건드린다"
else
    ok "fetch_items 본문에 커서 참조 없음"
fi
# 주석 제외 — 본문에 실제 호출이 있으면 안 된다
if grep -vE '^[[:space:]]*#' <<<"$fetch_body" | grep -q 'commit_version'; then
    bad "fetch_items 가 commit_version 을 호출한다"
else
    ok "fetch_items 가 커서를 커밋하지 않는다"
fi

# do_full / do_sync 에서 커서 커밋이 캐시 커밋보다 뒤에 온다
for fn in do_full do_sync; do
    body=$(awk "/^$fn\\(\\) \\{/,/^\\}/" "$SRC")
    cache_line=$(grep -n -E 'replace_cache|merge_cache' <<<"$body" | tail -1 | cut -d: -f1)
    cursor_line=$(grep -n 'commit_version' <<<"$body" | head -1 | cut -d: -f1)
    if [[ -n "$cache_line" && -n "$cursor_line" && "$cursor_line" -gt "$cache_line" ]]; then
        ok "$fn: 캐시 커밋(line $cache_line) → 커서 커밋(line $cursor_line) 순서"
    else
        bad "$fn: 커밋 순서를 확인할 수 없다 (cache=$cache_line cursor=$cursor_line)"
    fi
done

# 캐시 쓰기는 전부 temp + rename
if grep -q '> "\${ITEMS_FILE}.tmp"' "$SRC" && ! grep -qE '^\s*[^#]*> *"\$ITEMS_FILE"\s*$' "$SRC"; then
    ok "items.json 은 항상 temp + rename 으로만 쓰인다"
else
    bad "items.json 을 직접 덮어쓰는 자리가 남아 있다"
fi

# ---------------------------------------------------------------------------
echo
echo "== 2. 동적: mock cloud 로 실제 분기 실행 =="

MOCK="$WORK/cloud"; mkdir -p "$MOCK"
python3 - "$MOCK/items.json" <<'PY'
import json, sys
items = [{
    "key": f"KEY{i:05d}",
    "data": {"key": f"KEY{i:05d}", "itemType": "webpage",
             "title": f"Item {i:05d}", "url": f"https://example.com/{i}",
             "dateAdded": "2020-01-01T00:00:00Z", "dateModified": "2020-01-02T00:00:00Z"},
} for i in range(250)]
json.dump(items, open(sys.argv[1], "w", encoding="utf-8"), ensure_ascii=False)
PY

export ZOTERO_API_KEY=test ZOTERO_USER_ID=1 MOCK_DIR="$MOCK"
export PATH="$SCRIPT_DIR/mock:$PATH"

# sync 하네스: 격리된 SYNC_DIR/BIB_DIR 에서 지정한 함수를 돌린다
run_sync() {   # $1 = do_full|do_sync, 나머지 = timeout 초 (선택)
    local fn="$1" limit="${2:-}"
    local script="$WORK/harness.sh"
    cat > "$script" <<HARNESS
set -uo pipefail
source "$SRC" >/dev/null 2>&1 || true
SYNC_DIR="$SBOX"; ITEMS_FILE="\$SYNC_DIR/items.json"; LAST_VERSION_FILE="\$SYNC_DIR/last-version"
BIB_DIR="$BIBBOX"
$fn
HARNESS
    if [[ -n "$limit" ]]; then
        timeout -s KILL "$limit" bash "$script" >/dev/null 2>&1
    else
        bash "$script" >/dev/null 2>&1
    fi
}

new_sandbox() {
    SBOX="$WORK/sync-$1"; BIBBOX="$WORK/bib-$1"
    mkdir -p "$SBOX" "$BIBBOX"
}

seed_old() {   # 옛 캐시 + 옛 커서 (일관된 쌍)
    jq '.[0:5]' "$MOCK/items.json" > "$SBOX/items.json"
    printf '1000\n' > "$SBOX/last-version"
    OLD_ITEMS=$(md5sum < "$SBOX/items.json")
    OLD_VER=$(cat "$SBOX/last-version")
}

echo
echo "-- 2a. 중간에 SIGKILL: 캐시도 커서도 움직이지 않는다 --"
new_sandbox kill; seed_old
MOCK_VERSION=35790 MOCK_DELAY_PAGE=100 MOCK_DELAY_SECS=10 run_sync do_full 2
[[ "$(md5sum < "$SBOX/items.json")" == "$OLD_ITEMS" ]] \
    && ok "items.json 그대로" || bad "items.json 이 바뀌었다"
[[ "$(cat "$SBOX/last-version")" == "$OLD_VER" ]] \
    && ok "last-version 그대로 ($OLD_VER)" \
    || bad "커서가 $(cat "$SBOX/last-version") 로 튀었다 — 페이지 건너뜀 위험"
# SIGKILL 은 trap 을 못 돌리므로 임시물이 남는다. 다음 실행은 그것을 **즉시 지우면
# 안 된다** — 동시에 도는 다른 sync 의 활성 staging 일 수 있기 때문이다 (실측 사고).
# 갓 생긴 잔여물은 남기고, 충분히 오래된 것만 치운다.
fresh_residue=$(find "$SBOX" -maxdepth 1 -name '.fetch.*' | head -1)
MOCK_VERSION=35792 run_sync do_full
if [[ -n "$fresh_residue" ]]; then
    [[ -d "$fresh_residue" ]] \
        && ok "갓 생긴 잔여물을 다음 실행이 지우지 않는다 (동시 실행 보호)" \
        || bad "다음 실행이 최근 staging 을 지웠다 — 동시 실행이면 사고가 된다"
fi
[[ "$(cat "$SBOX/last-version")" == "35792" ]] \
    && ok "중단 후 재시도가 정상 복구된다 (커서 35792)" \
    || bad "재시도 후 커서가 $(cat "$SBOX/last-version")"

# 오래된 잔여물은 청소된다
stale="$SBOX/.fetch.staleXX"; mkdir -p "$stale"
touch -d '3 hours ago' "$stale"
MOCK_VERSION=35793 run_sync do_full
[[ ! -d "$stale" ]] \
    && ok "60분 넘은 잔여물은 청소된다" \
    || bad "오래된 잔여물이 남았다"

echo
echo "-- 2b. 정상 full: 캐시 갱신 후에 커서가 움직인다 --"
new_sandbox full; seed_old
MOCK_VERSION=35792 run_sync do_full
[[ "$(jq 'length' "$SBOX/items.json")" == "250" ]] \
    && ok "캐시 250건으로 교체" || bad "캐시가 $(jq 'length' "$SBOX/items.json") 건"
[[ "$(cat "$SBOX/last-version")" == "35792" ]] \
    && ok "커서 35792 로 커밋" || bad "커서가 $(cat "$SBOX/last-version")"

echo
echo "-- 2c. 빈 증분: 캐시 손대지 않고 안전하다 --"
new_sandbox empty; seed_old
MOCK_EMPTY=1 MOCK_VERSION=36000 run_sync do_sync
[[ "$(md5sum < "$SBOX/items.json")" == "$OLD_ITEMS" ]] \
    && ok "변경 없음 → 캐시 그대로" || bad "빈 증분인데 캐시가 바뀌었다"
[[ "$(cat "$SBOX/last-version")" == "36000" ]] \
    && ok "커서만 전진 (36000)" || bad "커서가 $(cat "$SBOX/last-version")"

echo
echo "-- 2d. 깨진 응답: 캐시도 커서도 움직이지 않는다 --"
new_sandbox garbage; seed_old
MOCK_GARBAGE=1 MOCK_VERSION=99999 run_sync do_full
[[ "$(md5sum < "$SBOX/items.json")" == "$OLD_ITEMS" ]] \
    && ok "items.json 그대로" || bad "깨진 응답인데 캐시가 바뀌었다"
[[ "$(cat "$SBOX/last-version")" == "$OLD_VER" ]] \
    && ok "last-version 그대로 ($OLD_VER)" \
    || bad "깨진 응답인데 커서가 $(cat "$SBOX/last-version") 로 움직였다"

echo
echo "-- 2e. 증분 병합: 캐시가 먼저, 커서가 나중 --"
new_sandbox incr; seed_old
MOCK_VERSION=36100 run_sync do_sync
[[ "$(jq 'length' "$SBOX/items.json")" == "250" ]] \
    && ok "5건 캐시에 250건 upsert" || bad "캐시가 $(jq 'length' "$SBOX/items.json") 건"
[[ "$(cat "$SBOX/last-version")" == "36100" ]] \
    && ok "커서 36100 으로 커밋" || bad "커서가 $(cat "$SBOX/last-version")"

echo
echo "-- 2f. 삭제 조회 실패: 커서가 절대 전진하지 않는다 --"
# 삭제는 **옛 since** 를 실은 요청에만 보인다. 이 요청이 실패했는데 커서를 옮기면
# 그 삭제들은 영영 반영되지 않는다.
for mode in MOCK_DELETED_GARBAGE MOCK_DELETED_FAIL; do
    new_sandbox "del-$mode"; seed_old
    export "$mode=1" MOCK_VERSION=37000
    run_sync do_sync
    unset "$mode" MOCK_VERSION
    if [[ "$(cat "$SBOX/last-version")" == "$OLD_VER" ]]; then
        ok "$mode: 커서 그대로 ($OLD_VER)"
    else
        bad "$mode: 커서가 $(cat "$SBOX/last-version") 로 전진했다 — 삭제 영구 누락"
    fi
    # 캐시는 이미 갱신되어도 된다 (커서보다 새로운 방향은 안전하다)
    [[ "$(jq 'length' "$SBOX/items.json")" == "250" ]] \
        && ok "$mode: 캐시는 갱신됨 (커서보다 새로움 = 안전한 방향)" \
        || bad "$mode: 캐시가 $(jq 'length' "$SBOX/items.json") 건"
done

echo
echo "-- 2g. 삭제 정상 반영 후에야 커서가 움직인다 --"
new_sandbox del-ok; seed_old
MOCK_DELETED_KEYS="KEY00000,KEY00001" MOCK_VERSION=37100 run_sync do_sync
[[ "$(jq 'length' "$SBOX/items.json")" == "248" ]] \
    && ok "삭제 2건 반영 (250 → 248)" || bad "캐시가 $(jq 'length' "$SBOX/items.json") 건"
[[ "$(cat "$SBOX/last-version")" == "37100" ]] \
    && ok "그 뒤에 커서 커밋 (37100)" || bad "커서가 $(cat "$SBOX/last-version")"

echo
echo "passed: $pass, failed: $fail"
[[ "$fail" -eq 0 ]]

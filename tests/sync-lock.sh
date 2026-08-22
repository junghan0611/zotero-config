#!/usr/bin/env bash
#
# sync-lock.sh — `.sync` 단일 쓰기 락 회귀 테스트
#
# 실측 사고: 두 개의 `bib full` 이 동시에 돌았다. 두 번째가 시작하면서
# `rm -rf $SYNC_DIR/.fetch.*` 로 **먼저 돌던 쪽의 활성 staging 디렉터리**를
# 지웠고, 그쪽은 페이지 26 부터 쓰기에 실패해 fetch 총계가 0 이 됐다.
#
# 계약:
#   · full / sync / writeback 은 배타적 non-blocking 락을 먼저 잡는다.
#   · 못 잡으면 정직하게 거부하고 **아무것도 건드리지 않는다**
#     (남의 fetch 디렉터리, 캐시, 커서 전부).
#   · status 는 읽기 전용이라 락을 잡지 않는다.
#   · 락은 fd 에 걸리므로 프로세스가 죽으면 커널이 자동 해제한다.
#
# 네트워크 없음 — mock curl 이 서빙한다. 실제 .sync/ 와 bib 디렉터리 미접촉.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
SRC="$REPO_DIR/scripts/zotero-to-bib.sh"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

pass=0; fail=0
ok()  { echo "  ok   — $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL — $1" >&2; fail=$((fail + 1)); }

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

SBOX="$WORK/sync"; BIBBOX="$WORK/bib"
mkdir -p "$SBOX" "$BIBBOX"
jq '.[0:5]' "$MOCK/items.json" > "$SBOX/items.json"
printf '1000\n' > "$SBOX/last-version"
OLD_ITEMS=$(md5sum < "$SBOX/items.json")
OLD_VER=$(cat "$SBOX/last-version")

# 실제 진입점과 같은 경로로 돈다: 락 획득 → do_full
make_harness() {
    cat > "$1" <<HARNESS
set -uo pipefail
source "$SRC" >/dev/null 2>&1 || true
SYNC_DIR="$SBOX"; ITEMS_FILE="\$SYNC_DIR/items.json"
LAST_VERSION_FILE="\$SYNC_DIR/last-version"; SYNC_LOCK_FILE="\$SYNC_DIR/.lock"
BIB_DIR="$BIBBOX"
SYNC_LOCK_CMD=full
acquire_sync_lock || exit 9
do_full
HARNESS
}
make_harness "$WORK/h.sh"

echo "== 1. 먼저 잡은 쪽이 도는 동안 두 번째는 거부된다 =="

# A: 페이지 2 에서 지연 → fetch staging 이 살아 있는 창을 만든다
MOCK_VERSION=42000 MOCK_DELAY_PAGE=100 MOCK_DELAY_SECS=12 \
    bash "$WORK/h.sh" > "$WORK/a.log" 2>&1 &
A_PID=$!

# A 의 staging 디렉터리가 생길 때까지 기다린다
for _ in $(seq 1 100); do
    FETCHDIR=$(find "$SBOX" -maxdepth 1 -name '.fetch.*' | head -1)
    [[ -n "$FETCHDIR" ]] && break
    sleep 0.2
done
if [[ -z "${FETCHDIR:-}" ]]; then
    bad "A 의 fetch staging 이 생기지 않았다 — 테스트 전제 실패"
    kill "$A_PID" 2>/dev/null
    echo "passed: $pass, failed: $((fail + 1))"; exit 1
fi
ok "A 가 락을 쥐고 fetch 중 (staging: $(basename "$FETCHDIR"))"
A_PAGES=$(find "$FETCHDIR" -name 'page-*.json' | wc -l)

# B: 같은 SYNC_DIR 에 두 번째 full
MOCK_VERSION=43000 bash "$WORK/h.sh" > "$WORK/b.log" 2>&1
B_EXIT=$?

[[ "$B_EXIT" -eq 9 ]] \
    && ok "B 가 락 거부로 종료 (exit 9)" \
    || bad "B 가 exit $B_EXIT — 거부되지 않았다"
grep -q "다른 프로세스가 .sync 를 쓰는 중이다" "$WORK/b.log" \
    && ok "거부 사유를 정직하게 보고" || bad "거부 메시지가 없다"
grep -qE "holder: pid=[0-9]+" "$WORK/b.log" \
    && ok "락 보유자 pid 를 알려준다" || bad "holder 정보가 없다"

echo
echo "== 2. 거부된 쪽은 아무것도 건드리지 않는다 =="
[[ -d "$FETCHDIR" ]] \
    && ok "A 의 활성 staging 디렉터리가 살아 있다" \
    || bad "B 가 A 의 staging 을 지웠다 — 사고 재현"
NOW_PAGES=$(find "$FETCHDIR" -name 'page-*.json' 2>/dev/null | wc -l)
[[ "$NOW_PAGES" -ge "$A_PAGES" ]] \
    && ok "A 가 받아둔 페이지가 보존됨 ($A_PAGES → $NOW_PAGES)" \
    || bad "A 의 페이지가 사라졌다 ($A_PAGES → $NOW_PAGES)"
[[ "$(md5sum < "$SBOX/items.json")" == "$OLD_ITEMS" ]] \
    && ok "캐시 불변" || bad "거부된 B 가 캐시를 바꿨다"
[[ "$(cat "$SBOX/last-version")" == "$OLD_VER" ]] \
    && ok "커서 불변 ($OLD_VER)" || bad "거부된 B 가 커서를 옮겼다"

echo
echo "== 3. A 는 방해받지 않고 정상 완료한다 =="
wait "$A_PID"; A_EXIT=$?
[[ "$A_EXIT" -eq 0 ]] && ok "A exit 0" || bad "A 가 exit $A_EXIT (로그: $(tail -2 "$WORK/a.log"))"
[[ "$(jq 'length' "$SBOX/items.json")" == "250" ]] \
    && ok "A 가 캐시를 250건으로 교체" || bad "캐시가 $(jq 'length' "$SBOX/items.json") 건"
[[ "$(cat "$SBOX/last-version")" == "42000" ]] \
    && ok "A 가 커서를 42000 으로 커밋" || bad "커서가 $(cat "$SBOX/last-version")"

echo
echo "== 4. 락은 프로세스가 죽으면 자동 해제된다 =="
MOCK_VERSION=44000 MOCK_DELAY_PAGE=100 MOCK_DELAY_SECS=3 \
    bash "$WORK/h.sh" > "$WORK/c.log" 2>&1 &
C_PID=$!
for _ in $(seq 1 100); do
    grep -q "Acquired .sync writer lock" "$WORK/c.log" 2>/dev/null && break
    sleep 0.2
done
kill -9 "$C_PID" 2>/dev/null; wait "$C_PID" 2>/dev/null
MOCK_VERSION=45000 bash "$WORK/h.sh" > "$WORK/d.log" 2>&1
D_EXIT=$?
[[ "$D_EXIT" -eq 0 ]] \
    && ok "SIGKILL 뒤 다음 실행이 락을 정상 획득 (stale lock 없음)" \
    || bad "죽은 프로세스의 락이 남았다 (exit $D_EXIT)"

echo
echo "== 5. status 는 락 없이 읽는다 =="
grep -qE '^\s*status\)\s+do_status' "$SRC" \
    && ok "status 는 acquire_sync_lock 을 부르지 않는다" \
    || bad "status 가 락을 잡는다"
for cmd in full sync writeback; do
    grep -qE "^\s*$cmd\)\s+SYNC_LOCK_CMD=$cmd;\s+acquire_sync_lock" "$SRC" \
        && ok "$cmd 는 락을 먼저 잡는다" || bad "$cmd 가 락 없이 돈다"
done

echo
echo "== 6. 활성 staging 을 나이 무시하고 지우는 코드가 없다 =="
# 주석은 사고 설명을 담고 있으므로 제외하고 실제 코드만 본다
if grep -vE '^[[:space:]]*#' "$SRC" | grep -qE 'rm -rf .*\$SYNC_DIR"?/\.fetch'; then
    bad "블랭킷 rm -rf .fetch.* 가 코드에 남아 있다"
else
    ok "블랭킷 삭제 없음 (나이 조건 find 만 사용)"
fi
grep -q "mmin +60" "$SRC" && ok "잔여물 청소는 60분 이상 된 것만" || bad "나이 조건이 없다"

echo
echo "passed: $pass, failed: $fail"
[[ "$fail" -eq 0 ]]

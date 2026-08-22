#!/usr/bin/env bash
#
# render-determinism-live-cache.sh — 실제 기기 캐시로 결정론 계약 재확인
#
# fixture 테스트(render-determinism.sh)가 계약의 SSOT다. 이 스크립트는 같은
# 계약을 이 기기의 실제 `.sync/items.json` (수천 건) 위에서 한 번 더 확인한다.
#
# 네트워크 없음. Zotero Cloud 접근 없음. 실사용 bib 디렉터리를 읽지도 쓰지도
# 않는다 — 렌더는 전부 mktemp 디렉터리 안에서만 일어난다.
# `.sync/` 가 없으면 (다른 기기 / CI) skip.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
GEN="$REPO_DIR/scripts/gen-bibtex.py"
ITEMS="$REPO_DIR/.sync/items.json"

if [[ ! -f "$ITEMS" ]]; then
    echo "[SKIP] $ITEMS 없음 — 이 기기에 로컬 캐시가 없다."
    exit 0
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

count=$(python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1],encoding="utf-8"))))' "$ITEMS")
echo "로컬 캐시 항목: $count"

render() {
    local items="$1" name="$2"
    mkdir -p "$WORK/out-$name" "$WORK/sync-$name"
    python3 "$GEN" \
        --items "$items" \
        --book-bib "$WORK/out-$name/Book.bib" \
        --output-dir "$WORK/out-$name" \
        --sync-dir "$WORK/sync-$name" >/dev/null
}

python3 - "$ITEMS" "$WORK/a.json" "$WORK/b.json" <<'PY'
import json, random, sys
src, a, b = sys.argv[1], sys.argv[2], sys.argv[3]
items = json.load(open(src, encoding="utf-8"))
json.dump(items, open(a, "w", encoding="utf-8"), ensure_ascii=False)
shuffled = items[:]
random.Random(20260822).shuffle(shuffled)
json.dump(shuffled, open(b, "w", encoding="utf-8"), ensure_ascii=False)
PY

render "$WORK/a.json" a
render "$WORK/b.json" b

fail=0
for f in "$WORK/out-a"/*.bib; do
    n="$(basename "$f")"
    if cmp -s "$f" "$WORK/out-b/$n"; then
        echo "  ok   — $n ($(grep -c '^@' "$f") entries) byte-identical"
    else
        echo "  FAIL — $n 이 입력 순서에 따라 달라진다" >&2
        fail=1
    fi
done

if diff -q "$WORK/sync-a/new-keys.json" "$WORK/sync-b/new-keys.json" >/dev/null 2>&1; then
    echo "  ok   — new-keys.json 동일"
fi

[[ "$fail" -eq 0 ]]

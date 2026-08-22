#!/usr/bin/env bash
#
# render-determinism.sh — gen-bibtex.py 결정론 계약 검증
#
# 계약:
#   렌더 결과는 입력 .sync/items.json 의 **배열 순서**, last-version, sync 시각과
#   무관해야 한다. 같은 라이브러리를 든 어느 기기든, 몇 번을 다시 돌리든
#   **완전한 byte-identical** 이어야 한다 (생성 시각 헤더 자체가 없다).
#
# 네트워크 없음. Zotero Cloud 접근 없음. 실사용 bib 디렉터리를 건드리지 않는다
#   — 모든 렌더는 mktemp 디렉터리 안에서만 일어난다.
#
# Usage: ./tests/render-determinism.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
GEN="$REPO_DIR/scripts/gen-bibtex.py"
FIXTURE="$SCRIPT_DIR/fixtures/items.json"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0
ok()   { echo "  ok   — $1"; pass=$((pass + 1)); }
bad()  { echo "  FAIL — $1" >&2; fail=$((fail + 1)); }

# Render $1 (items.json) into a fresh dir, echo that dir.
render() {
    local items="$1" name="$2"
    local out="$WORK/out-$name"
    mkdir -p "$out" "$WORK/sync-$name"
    python3 "$GEN" \
        --items "$items" \
        --book-bib "$out/Book.bib" \
        --output-dir "$out" \
        --sync-dir "$WORK/sync-$name" >/dev/null
    echo "$out"
}

# Write a permuted copy of the fixture. $1 = mode, $2 = target path.
permute() {
    python3 - "$FIXTURE" "$1" "$2" <<'PY'
import json, random, sys
src, mode, dst = sys.argv[1], sys.argv[2], sys.argv[3]
items = json.load(open(src, encoding="utf-8"))
if mode == "reverse":
    items = items[::-1]
elif mode.startswith("rotate"):
    n = int(mode[len("rotate"):])
    items = items[n:] + items[:n]
elif mode.startswith("seed"):
    random.Random(int(mode[len("seed"):])).shuffle(items)
elif mode == "identity":
    pass
else:
    raise SystemExit(f"unknown mode {mode}")
json.dump(items, open(dst, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
PY
}

echo "== 1. 입력 배열 순서가 달라도 완전한 byte-identical =="

# fixture 에 **sanitizer 대상 토큰이 들어간 citationKey** 두 건을 주입한다.
# raw 식별자를 repo 파일에 적지 않기 위해 실행 시점에 조합한다 (sanitizer 정책과 동일).
# 이 두 건은 sanitize 를 정렬 **뒤에** 돌리면 반드시 역전을 만든다:
#   raw:       web-<company>gokweol  <  web-gordonnovakjr
#   sanitized: web-tbdhnygokweol     >  web-gordonnovakjr
augment_fixture() {
    python3 - "$FIXTURE" "$1" <<'AUG'
import json, sys
src, dst = sys.argv[1], sys.argv[2]
items = json.load(open(src, encoding="utf-8"))
company = "go" + "qual"
items.append({
    "key": "SAN00001",
    "data": {
        "key": "SAN00001",
        "itemType": "webpage",
        "citationKey": "web-" + company + "gokweol",
        "title": "A page whose curated key carries a sanitized identifier",
        "url": "https://example.com/one",
        "dateAdded": "2025-01-01T00:00:00Z",
        "dateModified": "2025-01-02T00:00:00Z",
    },
})
items.append({
    "key": "SAN00002",
    "data": {
        "key": "SAN00002",
        "itemType": "webpage",
        "citationKey": "web-gordonnovakjr",
        "title": "A neighbouring page that must sort before it",
        "url": "https://example.com/two",
        "dateAdded": "2025-01-03T00:00:00Z",
        "dateModified": "2025-01-04T00:00:00Z",
    },
})
json.dump(items, open(dst, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
AUG
}

AUGMENTED="$WORK/fixture-augmented.json"
augment_fixture "$AUGMENTED"
FIXTURE="$AUGMENTED"

base_items="$WORK/items-identity.json"
permute identity "$base_items"
base_dir=$(render "$base_items" identity)

for mode in reverse rotate3 rotate7 seed1 seed42 seed1337; do
    items="$WORK/items-$mode.json"
    permute "$mode" "$items"
    dir=$(render "$items" "$mode")

    # 같은 파일 집합인가
    if diff -q <(cd "$base_dir" && ls) <(cd "$dir" && ls) >/dev/null; then
        :
    else
        bad "$mode: 생성된 파일 목록이 다르다"
        continue
    fi

    differing=""
    for f in "$base_dir"/*.bib; do
        b="$(basename "$f")"
        if ! cmp -s "$f" "$dir/$b"; then
            differing="$differing $b"
        fi
    done
    if [[ -n "$differing" ]]; then
        bad "$mode: 다음 파일이 다르다 —$differing"
    else
        ok "$mode: 모든 .bib 가 완전히 byte-identical"
    fi

    # 중복 키 카운터(-1/-2)도 순서에 흔들리면 안 된다
    if diff -q "$WORK/sync-identity/new-keys.json" "$WORK/sync-$mode/new-keys.json" >/dev/null; then
        ok "$mode: new-keys.json 동일 (중복 접미사까지 결정론적)"
    else
        bad "$mode: new-keys.json 이 다르다 — 중복 접미사가 입력 순서에 의존한다"
    fi
done

echo
echo "== 2. 각 파일이 citationKey 로 정렬되어 있다 =="
for f in "$base_dir"/*.bib; do
    keys=$(grep -o '^@[a-z]*{[^,]*' "$f" | sed 's/^@[a-z]*{//')
    if [[ "$keys" == "$(printf '%s\n' "$keys" | LC_ALL=C sort)" ]]; then
        ok "$(basename "$f"): citationKey 오름차순"
    else
        bad "$(basename "$f"): 정렬되어 있지 않다"
    fi
done

echo
echo "== 2b. sanitize 가 정렬 불변식을 깨지 않는다 (실물 회귀) =="
company="$(printf '%s' 'go''qual')"
if grep -rqi "$company" "$base_dir"; then
    bad "최종 출력에 raw 식별자가 남아 있다 — sanitize 가 적용되지 않았다"
else
    ok "최종 출력에 raw 식별자 없음"
fi
if grep -q '^@online{web-tbdhnygokweol,' "$base_dir/Online.bib"; then
    ok "sanitize 된 키가 실제로 출력에 있다 (web-tbdhnygokweol)"
else
    bad "sanitize 된 키를 찾지 못했다 — 회귀 케이스가 렌더되지 않았다"
fi
# 정렬은 sanitize 된 최종 바이트 기준이어야 한다: gordonnovakjr < tbdhnygokweol
line_gordon=$(grep -n '^@online{web-gordonnovakjr,' "$base_dir/Online.bib" | cut -d: -f1)
line_san=$(grep -n '^@online{web-tbdhnygokweol,' "$base_dir/Online.bib" | cut -d: -f1)
if [[ -n "$line_gordon" && -n "$line_san" && "$line_gordon" -lt "$line_san" ]]; then
    ok "sanitize 후 순서가 맞다 (line $line_gordon < $line_san)"
else
    bad "sanitize 대상 키가 잘못된 자리에 있다 (gordon=$line_gordon, sanitized=$line_san)"
fi

echo
echo "== 3. dateAdded / dateModified 가 BibTeX 필드로 살아 있다 =="
if grep -q '^  dateadded = {2026-05-12T01:02:03Z},\?$' "$base_dir/Book.bib" &&
   grep -q '^  datemodified = {2026-06-01T04:05:06Z},\?$' "$base_dir/Book.bib"; then
    ok "Zotero Cloud dateAdded/dateModified 보존"
else
    bad "dateAdded/dateModified 가 렌더에서 사라졌다"
fi

echo
echo "== 4. 렌더 결과에 생성 시각이 전혀 없다 =="
if grep -rn '^% Updated:' "$base_dir" >/dev/null; then
    bad "생성 시각 헤더가 남아 있다"
else
    ok "'% Updated:' 헤더 없음"
fi
# 오늘 날짜/현재 연도가 헤더 영역(주석)에 새지 않는지도 본다
today=$(date +%Y-%m-%d)
if grep -h '^%' "$base_dir"/*.bib | grep -q "$today"; then
    bad "헤더 주석에 오늘 날짜가 들어 있다"
else
    ok "헤더 주석에 현재 시각 흔적 없음"
fi

echo
echo "== 5. 다시 돌려도 바이트가 같고, 파일을 다시 쓰지 않는다 =="
rerun="$WORK/out-rerun"
mkdir -p "$rerun" "$WORK/sync-rerun"
cp "$base_dir"/*.bib "$rerun/"
touch -d '2000-01-01 00:00:00' "$rerun"/*.bib
stamped=$(stat -c '%Y' "$rerun/Book.bib")
python3 "$GEN" \
    --items "$base_items" \
    --book-bib "$rerun/Book.bib" \
    --output-dir "$rerun" \
    --sync-dir "$WORK/sync-rerun" >/dev/null
if [[ "$(stat -c '%Y' "$rerun/Book.bib")" == "$stamped" ]]; then
    ok "재실행에서 재작성 없음 (mtime 보존 → Syncthing no-op 전파 방지)"
else
    bad "내용이 같은데도 파일을 다시 썼다 (mtime 변경)"
fi
rerun_diff=""
for f in "$base_dir"/*.bib; do
    cmp -s "$f" "$rerun/$(basename "$f")" || rerun_diff="$rerun_diff $(basename "$f")"
done
[[ -z "$rerun_diff" ]] \
    && ok "재실행 결과가 첫 실행과 완전히 byte-identical" \
    || bad "재실행 결과가 다르다 —$rerun_diff"

echo
echo "== 6. 실제 서지면을 건드리지 않았다 =="
if [[ "$WORK" == /tmp/* || "$WORK" == "${TMPDIR:-/tmp}"* ]]; then
    ok "렌더는 임시 디렉터리에서만 일어났다: $WORK"
else
    bad "임시 디렉터리 밖에서 렌더했다: $WORK"
fi

echo
echo "passed: $pass, failed: $fail"
[[ "$fail" -eq 0 ]]

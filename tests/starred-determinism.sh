#!/usr/bin/env bash
#
# starred-determinism.sh — github-starred.bib 결정론 + 정렬 불변식
#
# 계약:
#   · 같은 GitHub 응답이면 같은 바이트 (페이지 순서 무관, 생성 시각 헤더 없음).
#   · 비식별화가 **정렬 전에** 키에 적용된다. 정렬 뒤에 치환하면 키가 바뀌면서
#     최종 출력에 역전이 남는다 — Zotero 렌더러에서 겪은 것과 같은 구조적 결함.
#   · 규칙은 scripts/sanitize_bib.py 한 곳에서만 온다 (하드코딩 복제 금지).
#
# 네트워크 없음: GitHub API 를 부르지 않고 합성 응답을 jq 프로그램에 직접 먹인다.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

pass=0; fail=0
ok()  { echo "  ok   — $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL — $1" >&2; fail=$((fail + 1)); }

KEY_SANITIZE=$(python3 "$REPO_DIR/scripts/sanitize_bib.py" --jq-filter)
JQ_PROG=$(cat "$REPO_DIR/scripts/gh-starred.jq")
JQ_PROG=${JQ_PROG//@@KEYSAN@@/$KEY_SANITIZE}

# 합성 응답. raw 식별자는 실행 시점에 조합한다 (repo 파일에 적지 않는다).
# 이 두 건은 sanitize 를 정렬 뒤에 돌리면 반드시 역전을 만든다:
#   raw:       x<company>gokweol  <  xgordonnovakjr
#   sanitized: xtbdhnygokweol     >  xgordonnovakjr
make_response() {   # $1 = 출력 경로, $2 = 순서 (fwd|rev)
    python3 - "$1" "$2" <<'PY'
import json, sys
dst, order = sys.argv[1], sys.argv[2]
company = "go" + "qual"
def repo(owner, name, stars):
    return {
        "starred_at": f"2024-0{stars}-01T00:00:00Z",
        "repo": {
            "full_name": f"{owner}/{name}", "owner": {"login": owner},
            "topics": ["t"], "description": "d", "license": {"name": "MIT"},
            "updated_at": "2024-01-01", "created_at": "2023-01-01",
            "html_url": f"https://github.com/{owner}/{name}",
            "stargazers_count": stars, "language": "Go",
            "pushed_at": "2024-02-02T00:00:00Z",
        },
    }
items = [
    repo("x", company + "gokweol", 1),
    repo("x", "gordonnovakjr", 2),
    repo("a", "alpha", 3),
    repo("z", "omega", 4),
]
if order == "rev":
    items = items[::-1]
# gh --paginate 는 배열 스트림을 낸다 → 두 페이지로 쪼갠다
json.dump(items[:2], open(dst, "w", encoding="utf-8"))
with open(dst, "a", encoding="utf-8") as f:
    f.write("\n")
    json.dump(items[2:], f)
PY
}

render() { jq -s -r "$JQ_PROG" < "$1" > "$2"; }

echo "== 1. 응답 순서가 달라도 byte-identical =="
make_response "$WORK/fwd.json" fwd
make_response "$WORK/rev.json" rev
render "$WORK/fwd.json" "$WORK/fwd.bib"
render "$WORK/rev.json" "$WORK/rev.bib"
cmp -s "$WORK/fwd.bib" "$WORK/rev.bib" \
    && ok "정방향/역방향 응답이 같은 바이트" \
    || bad "응답 순서에 따라 출력이 다르다"

echo
echo "== 2. sanitize 후 기준으로 정렬되어 있다 =="
keys=$(grep -o '^@software{[^,]*' "$WORK/fwd.bib" | sed 's/^@software{//')
echo "$keys" | sed 's/^/       /'
if [[ "$keys" == "$(printf '%s\n' "$keys" | LC_ALL=C sort)" ]]; then
    ok "최종 키가 오름차순"
else
    bad "정렬되어 있지 않다"
fi
g=$(grep -n '^@software{xgordonnovakjr,' "$WORK/fwd.bib" | cut -d: -f1)
t=$(grep -n '^@software{xtbdhnygokweol,' "$WORK/fwd.bib" | cut -d: -f1)
if [[ -n "$g" && -n "$t" && "$g" -lt "$t" ]]; then
    ok "sanitize 대상 키가 제자리 (gordon $g < sanitized $t)"
else
    bad "sanitize 대상 키 위치가 틀렸다 (gordon=$g sanitized=$t)"
fi

echo
echo "== 3. raw 식별자가 렌더 결과에 이미 없다 (키·본문 모두) =="
company="$(printf '%s' 'go''qual')"
grep -qi "$company" "$WORK/fwd.bib" \
    && bad "raw 식별자가 남아 있다 — 본문 필드가 처리되지 않았다" \
    || ok "raw 식별자 없음"

echo
echo "== 4. sanitize 래퍼는 안전망일 뿐 — 아무것도 바꾸지 않는다 =="
cp "$WORK/fwd.bib" "$WORK/after.bib"
"$REPO_DIR/scripts/sanitize-public-bib.sh" "$WORK/after.bib" >/dev/null 2>&1
cmp -s "$WORK/fwd.bib" "$WORK/after.bib" \
    && ok "래퍼가 no-op (렌더 결과가 이미 최종형)" \
    || bad "래퍼가 최종 출력을 바꿨다 — 정렬이 깨질 수 있다"
after_keys=$(grep -o '^@software{[^,]*' "$WORK/after.bib" | sed 's/^@software{//')
[[ "$after_keys" == "$keys" ]] \
    && ok "래퍼 통과 후에도 키 순서 동일" \
    || bad "래퍼가 키 순서를 바꿨다"

echo
echo "== 5. 규칙이 복제되지 않았다 / 생성 시각 헤더 없음 =="
grep -q 'sanitize_bib.py" --jq-filter' "$REPO_DIR/scripts/gh-starred-to-bib.sh" \
    && ok "starred 경로가 규칙 SSOT 를 가져다 쓴다" \
    || bad "starred 경로가 규칙을 따로 들고 있다"
if grep -vE '^[[:space:]]*#' "$REPO_DIR/scripts/gh-starred-to-bib.sh" \
        | grep -qE 'tbdhny|urwqri'; then
    bad "starred 스크립트에 치환 규칙이 하드코딩돼 있다"
else
    ok "하드코딩된 치환 규칙 없음"
fi
grep -qE '^% Updated:|date -Iseconds|TIMESTAMP' "$REPO_DIR/scripts/gh-starred-to-bib.sh" \
    && bad "생성 시각이 남아 있다" || ok "생성 시각 헤더 없음"

echo
echo "== 6. 스크립트 전체: staging + 원자 설치 + 무변경 시 재작성 없음 =="
# GH_STARRED_INPUT 오프라인 시드로 실제 스크립트를 끝까지 돌린다 (GitHub 호출 없음).
OUTDIR="$WORK/bib"; mkdir -p "$OUTDIR"
TARGET="$OUTDIR/github-starred.bib"

GH_STARRED_INPUT="$WORK/fwd.json" ZOTERO_BIB_DIR="$OUTDIR" \
    "$REPO_DIR/scripts/gh-starred-to-bib.sh" >/dev/null 2>&1
[[ -f "$TARGET" ]] && ok "1회차: 파일 생성" || bad "1회차에 파일이 안 생겼다"
first_sum=$(md5sum < "$TARGET")

# 특이 mode 를 심어 승계되는지 본다
chmod 640 "$TARGET"
touch -d '2000-01-01 00:00:00' "$TARGET"
stamped=$(stat -c '%Y' "$TARGET")

GH_STARRED_INPUT="$WORK/fwd.json" ZOTERO_BIB_DIR="$OUTDIR" \
    "$REPO_DIR/scripts/gh-starred-to-bib.sh" > "$WORK/run2.log" 2>&1
[[ "$(md5sum < "$TARGET")" == "$first_sum" ]] \
    && ok "2회차: 같은 응답 → 같은 바이트" || bad "2회차 바이트가 다르다"
[[ "$(stat -c '%Y' "$TARGET")" == "$stamped" ]] \
    && ok "2회차: 재작성 없음 (mtime 보존 → Syncthing no-op 전파 없음)" \
    || bad "바이트가 같은데 다시 썼다 (mtime 변경)"
grep -q "Unchanged:" "$WORK/run2.log" \
    && ok "무변경을 정직하게 보고" || bad "무변경 보고가 없다"

# 응답이 바뀌면 교체되고, 그때 기존 mode 를 승계한다
GH_STARRED_INPUT="$WORK/rev.json" ZOTERO_BIB_DIR="$OUTDIR" \
    "$REPO_DIR/scripts/gh-starred-to-bib.sh" >/dev/null 2>&1
[[ "$(md5sum < "$TARGET")" == "$first_sum" ]] \
    && ok "응답 순서만 다르면 여전히 같은 바이트 (교체 없음)" \
    || bad "순서만 다른 응답인데 바이트가 달라졌다"

python3 - "$WORK/changed.json" <<'PY'
import json, sys
items = [{
    "starred_at": "2024-09-09T00:00:00Z",
    "repo": {"full_name": "n/newrepo", "owner": {"login": "n"}, "topics": [],
             "description": "d", "license": None, "updated_at": "2024-01-01",
             "created_at": "2023-01-01", "html_url": "https://github.com/n/newrepo",
             "stargazers_count": 9, "language": "Go", "pushed_at": "2024-02-02T00:00:00Z"},
}]
json.dump(items, open(sys.argv[1], "w", encoding="utf-8"))
PY
GH_STARRED_INPUT="$WORK/changed.json" ZOTERO_BIB_DIR="$OUTDIR" \
    "$REPO_DIR/scripts/gh-starred-to-bib.sh" >/dev/null 2>&1
[[ "$(md5sum < "$TARGET")" != "$first_sum" ]] \
    && ok "응답이 실제로 바뀌면 교체된다" || bad "바뀐 응답이 반영되지 않았다"
[[ "$(stat -c '%a' "$TARGET")" == "640" ]] \
    && ok "교체 시 기존 mode 승계 (640)" \
    || bad "mode 가 $(stat -c '%a' "$TARGET") 로 바뀌었다"

residue=$(find "$OUTDIR" -maxdepth 1 -name '.github-starred.*' -o -maxdepth 1 -name '.gh-entries.*' | wc -l)
[[ "$residue" -eq 0 ]] && ok "staging 잔여물 없음" || bad "staging 잔여물 $residue 개"
visible=$(find "$OUTDIR" -maxdepth 1 -name '*.bib' | wc -l)
[[ "$visible" -eq 1 ]] && ok "디렉터리에 .bib 는 최종본 하나뿐" || bad ".bib 가 $visible 개"

echo
echo "passed: $pass, failed: $fail"
[[ "$fail" -eq 0 ]]

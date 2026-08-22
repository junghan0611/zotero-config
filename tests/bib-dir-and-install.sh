#!/usr/bin/env bash
#
# bib-dir-and-install.sh — 출력면 경로 계약 + staged install 검증
#
# 계약:
#   · 기본 출력면은 `$HOME/sync/org/resources/bib`, `ZOTERO_BIB_DIR` 로 override.
#     모든 진입점(run.sh / zotero-to-bib.sh / sanitize / starred / pin / bibcli)이
#     같은 값을 봐야 한다.
#   · install 은 staging → 같은 파일시스템 rename. staging 잔여물이 남지 않는다.
#
# 네트워크 없음. 실사용 bib 디렉터리를 건드리지 않는다.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

pass=0; fail=0
ok()  { echo "  ok   — $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL — $1" >&2; fail=$((fail + 1)); }

DEFAULT_DIR="$HOME/sync/org/resources/bib"

echo "== 1. 모든 진입점이 같은 기본 출력면을 본다 =="
help_dir=$(cd "$REPO_DIR" && ./run.sh --help | sed -n 's/^Bib dir (실사용 출력면): //p')
[[ "$help_dir" == "$DEFAULT_DIR" ]] \
    && ok "run.sh 런타임 기본값 = $DEFAULT_DIR" \
    || bad "run.sh 기본값이 $help_dir (기대: $DEFAULT_DIR)"

for f in run.sh scripts/zotero-to-bib.sh scripts/sanitize-public-bib.sh scripts/gh-starred-to-bib.sh; do
    if grep -q 'ZOTERO_BIB_DIR:-\$HOME/sync/org/resources/bib' "$REPO_DIR/$f"; then
        ok "$f 기본값 일치"
    else
        bad "$f 가 다른 기본값을 본다"
    fi
done

if grep -q 'expanduser("~/sync/org/resources/bib")' "$REPO_DIR/scripts/pin-item.py"; then
    ok "scripts/pin-item.py 기본값 일치"
else
    bad "scripts/pin-item.py 가 다른 기본값을 본다"
fi

if grep -q '"sync", "org", "resources", "bib"' "$REPO_DIR/bibcli/main.go"; then
    ok "bibcli/main.go 기본값 일치"
else
    bad "bibcli/main.go 가 다른 기본값을 본다"
fi

# 옛 경로(~/org/resources)가 코드에 남아 있으면 안 된다 — 새 경로는 ~/sync/... 다
if grep -rnE '(~|\$HOME)/org/resources' \
        "$REPO_DIR/run.sh" "$REPO_DIR/scripts" "$REPO_DIR/bibcli"/*.go >/dev/null 2>&1; then
    bad "옛 ~/org/resources 경로가 코드에 남아 있다"
else
    ok "옛 경로 잔재 없음"
fi

echo
echo "== 2. ZOTERO_BIB_DIR override 가 먹는다 =="
override="$WORK/custom-bib"
mkdir -p "$override"
got=$(cd "$REPO_DIR" && ZOTERO_BIB_DIR="$override" ./run.sh --help | sed -n 's/^Bib dir (실사용 출력면): //p')
[[ "$got" == "$override" ]] \
    && ok "run.sh override 반영" \
    || bad "run.sh override 무시 ($got)"

got=$(cd "$REPO_DIR" && ZOTERO_BIB_DIR="$override" python3 scripts/pin-item.py --help 2>&1 | tr -d '\n')
case "$got" in
    *"$override"*) ok "pin-item.py override 반영" ;;
    *) bad "pin-item.py override 무시" ;;
esac

echo
echo "== 2b. 낡은 BIBCLI_DIR 이 새 경로를 이기지 못한다 =="
# 실측 사고: 셸 프로필에 남은 BIBCLI_DIR=~/sync/emacs/zotero-config/output 때문에
# --dir 없는 bibcli 가 폐기된 8,361건을 조용히 읽었다. 이제 BIBCLI_DIR 은 무시한다.
if command -v go >/dev/null 2>&1; then
    probe="$WORK/bibcli-probe"
    if (cd "$REPO_DIR/bibcli" && go build -o "$probe" . ) 2>/dev/null; then
        stale="$WORK/stale-legacy"; mkdir -p "$stale"
        printf '@book{legacyOnly,\n  title = {Legacy},\n}\n' > "$stale/Legacy.bib"
        fresh="$WORK/fresh-bib"; mkdir -p "$fresh"
        printf '@book{freshOnly,\n  title = {Fresh},\n}\n' > "$fresh/Fresh.bib"

        out=$(BIBCLI_DIR="$stale" ZOTERO_BIB_DIR="$fresh" "$probe" list --max 5 2>&1 || true)
        case "$out" in
            *legacyOnly*) bad "낡은 BIBCLI_DIR 이 여전히 이긴다" ;;
            *freshOnly*)  ok "BIBCLI_DIR 무시, ZOTERO_BIB_DIR 이 이긴다" ;;
            *)            bad "예상치 못한 출력: $out" ;;
        esac

        out=$(BIBCLI_DIR="$stale" "$probe" list --dir "$fresh" --max 5 2>&1 || true)
        case "$out" in
            *freshOnly*) ok "--dir 가 최우선" ;;
            *)           bad "--dir 가 무시됐다" ;;
        esac

        grep -q 'BIBCLI_DIR is retired and ignored' "$REPO_DIR/bibcli/main.go" \
            && ok "help 텍스트가 BIBCLI_DIR 폐기를 명시" \
            || bad "help 가 BIBCLI_DIR 을 여전히 광고한다"
    else
        echo "  [SKIP] bibcli 빌드 실패"
    fi
else
    echo "  [SKIP] go 없음"
fi

echo
echo "== 3. staged install: rename + 잔여물 없음 =="
# shellcheck disable=SC1090
if source "$REPO_DIR/scripts/zotero-to-bib.sh" >/dev/null 2>&1; then :; fi
if ! declare -F install_staged >/dev/null; then
    echo "  [SKIP] install_staged 를 가져올 수 없다 (자격증명 없음?)"
else
    DIR="$WORK/bib"; mkdir -p "$DIR"
    TARGET="$DIR/Book.bib"
    printf 'old\n' > "$TARGET"; chmod 600 "$TARGET"
    before_inode=$(stat -c '%i' "$TARGET")
    STAGED="$DIR/.stage.bib"; printf 'new\n' > "$STAGED"
    install_staged "$STAGED" "$TARGET"
    [[ "$(cat "$TARGET")" == "new" ]] && ok "내용 교체됨" || bad "내용이 교체되지 않았다"
    [[ "$(stat -c '%i' "$TARGET")" != "$before_inode" ]] \
        && ok "rename 경로 사용 (inode 교체 = 원자적 스왑)" \
        || bad "rename 이 아니다"
    [[ "$(stat -c '%a' "$TARGET")" == "600" ]] \
        && ok "기존 파일 mode 승계 (600)" \
        || bad "mode 가 $(stat -c '%a' "$TARGET") 로 바뀌었다"
    [[ ! -e "$STAGED" ]] && ok "staging 파일 잔여 없음" || bad "staging 파일이 남았다"
fi

echo
echo "== 4. 전체 렌더 경로: staging 디렉터리 잔여 없음 + 2회차 무변경 =="
ITEMS="$REPO_DIR/.sync/items.json"
if [[ ! -f "$ITEMS" ]] || ! declare -F generate_bibtex >/dev/null; then
    echo "  [SKIP] 로컬 캐시 또는 generate_bibtex 없음"
else
    TDIR="$WORK/render"; mkdir -p "$TDIR"
    ( ZOTERO_BIB_DIR="$TDIR" BIB_DIR="$TDIR" generate_bibtex ) >/dev/null 2>&1
    residue=$(find "$TDIR" -maxdepth 1 -name '.bibstage*' -o -maxdepth 1 -name '.stage*' | wc -l)
    [[ "$residue" -eq 0 ]] && ok "staging 디렉터리 잔여 없음" || bad "staging 잔여물 $residue 개"
    sums_a=$(cd "$TDIR" && md5sum ./*.bib | sort)
    touch -d '2000-01-01 00:00:00' "$TDIR"/*.bib
    stamped=$(stat -c '%Y' "$TDIR/Book.bib")
    ( ZOTERO_BIB_DIR="$TDIR" BIB_DIR="$TDIR" generate_bibtex ) >/dev/null 2>&1
    sums_b=$(cd "$TDIR" && md5sum ./*.bib | sort)
    [[ "$sums_a" == "$sums_b" ]] && ok "2회차 렌더가 완전히 byte-identical" || bad "2회차 결과가 다르다"
    [[ "$(stat -c '%Y' "$TDIR/Book.bib")" == "$stamped" ]] \
        && ok "2회차에서 파일을 다시 쓰지 않았다 (mtime 보존)" \
        || bad "내용이 같은데도 다시 썼다"
fi

echo
echo "passed: $pass, failed: $fail"
[[ "$fail" -eq 0 ]]

#!/usr/bin/env bash
# gh-starred-to-bib.sh — GitHub starred repos를 BibTeX 형식으로 변환
#
# Usage: ./run.sh starred
# Default output: $ZOTERO_BIB_DIR/github-starred.bib (default ~/sync/org/resources/bib)
#
# 결정론: 같은 GitHub 응답이면 같은 바이트. 엔트리를 키로 정렬하고 생성 시각을
# 헤더에 넣지 않는다 (시간 사실은 starred_at/pushed_at 같은 내용 필드로만 남는다).
#
# 의존성: gh (GitHub CLI), jq
#
# Citar 템플릿 호환 필드:
#   ${dateadded:10}       <- dateadded   (starred_at: star한 시점)
#   ${datemodified:10}    <- datemodified (pushed_at: 마지막 코드 푸시)
#   ${date year issued:4} <- date        (updated_at: 리포 업데이트)
#   ${keywords:*}         <- keywords    (topics)
#   ${url:19}             <- url         (html_url)
#   ${abstract}           <- abstract    (description)
#   ${author editor:19}   <- author      (owner.login)
#   ${title:49}           <- title       (full_name: owner/repo)
#
# GitHub API 참고:
#   Accept: application/vnd.github.star+json 헤더로 starred_at 필드 포함
#   응답 구조: {repo: {...}, starred_at: "..."}

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BIB_DIR="${ZOTERO_BIB_DIR:-$HOME/sync/org/resources/bib}"
OUTPUT="${1:-$BIB_DIR/github-starred.bib}"
OUT_DIR="$(dirname "$OUTPUT")"
mkdir -p "$OUT_DIR"

# shellcheck source=lib-install.sh
source "$SCRIPT_DIR/lib-install.sh"

# staging 은 목적지와 같은 디렉터리 안의 숨김 파일이다 (Zotero 렌더러와 같은 규율):
# 같은 파일시스템 rename + 바이트가 달라졌을 때만 교체.
STAGING=$(mktemp "$OUT_DIR/.github-starred.XXXXXX")
ENTRIES=$(mktemp "$OUT_DIR/.gh-entries.XXXXXX")
trap 'rm -f "$STAGING" "$ENTRIES"' EXIT

# GH_STARRED_INPUT 은 테스트용 오프라인 시드다 (GitHub 응답 JSON 파일).
# 설정되면 네트워크를 전혀 쓰지 않는다.
TARGET_GH_USER="${GH_STARRED_ACCOUNT:-junghan0611}"
if [[ -n "${GH_STARRED_INPUT:-}" ]]; then
  echo "Reading starred fixture from $GH_STARRED_INPUT (offline)..." >&2
  GH_USER="$TARGET_GH_USER"
else
  echo "Fetching starred repos from GitHub..." >&2
  # 이 repo는 개인 starred 기준을 기본값으로 사용한다.
  # 필요하면 GH_STARRED_ACCOUNT로 override 가능.
  GH_USER=$(gh api user --jq '.login')
  if [[ "$GH_USER" != "$TARGET_GH_USER" ]]; then
    echo "[INFO] Active gh account '$GH_USER' → switching to '$TARGET_GH_USER'" >&2
    gh auth switch --user "$TARGET_GH_USER" >/dev/null
    GH_USER=$(gh api user --jq '.login')
  fi

  if [[ "$GH_USER" != "$TARGET_GH_USER" ]]; then
    echo "[ERROR] Expected gh account '$TARGET_GH_USER' but active account is '$GH_USER'" >&2
    exit 1
  fi
fi

# 임시 파일에 entries 먼저 저장 (개수 계산용)
# Accept 헤더로 starred_at 필드 포함
# 비식별화 규칙은 scripts/sanitize_bib.py 한 곳에서만 온다. 그 규칙을 jq 필터로
# 받아 프로그램에 심어, 키를 **정렬 전에** 비식별화한다. 규칙을 여기에 하드코딩하면
# 렌더러와 갈라져 같은 정렬 역전이 다시 생긴다.
KEY_SANITIZE=$(python3 "$SCRIPT_DIR/sanitize_bib.py" --jq-filter)
JQ_PROG=$(cat "$SCRIPT_DIR/gh-starred.jq")
JQ_PROG=${JQ_PROG//@@KEYSAN@@/$KEY_SANITIZE}   # 필터에 | 가 있어 sed 구분자를 못 쓴다

if [[ -n "${GH_STARRED_INPUT:-}" ]]; then
    jq -s -r "$JQ_PROG" < "$GH_STARRED_INPUT" > "$ENTRIES"
else
    gh api --paginate user/starred -H "Accept: application/vnd.github.star+json" \
        | jq -s -r "$JQ_PROG" > "$ENTRIES"
fi

COUNT=$(grep -c '^@software{' "$ENTRIES")

# BibTeX 파일 헤더 — 생성 시각 없음 (같은 응답 → 같은 바이트)
cat > "$STAGING" << EOF
% -*- bibtex -*-
% GitHub Starred Repositories
%
% Account:  $GH_USER
% Entries:  $COUNT
%
% Regenerate: ./run.sh starred

EOF
cat "$ENTRIES" >> "$STAGING"
rm -f "$ENTRIES"

# 안전망: 렌더가 이미 같은 규칙을 적용했으므로 보통 no-op 이다.
python3 "$SCRIPT_DIR/sanitize_bib.py" "$STAGING" >/dev/null 2>&1 || true

if [[ -f "$OUTPUT" ]] && cmp -s "$OUTPUT" "$STAGING"; then
    rm -f "$STAGING"
    echo "Unchanged: $OUTPUT ($COUNT entries)" >&2
else
    install_staged "$STAGING" "$OUTPUT"
    echo "Done! $COUNT entries written to $OUTPUT" >&2
fi

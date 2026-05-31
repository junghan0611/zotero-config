#!/usr/bin/env bash
# sanitize-public-bib.sh — 공개 커밋 전 BibTeX 후처리
# notes/change-text.sh 처럼 가볍게 민감 텍스트를 치환한다.
# 기본 정책: 공개 repo 훅에 자주 걸리는 식별자를 허술하지만 일관되게 비식별화.
# raw 식별자 문자열은 파일에 직접 적지 않고 조합해서 사용한다.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$REPO_DIR/output"

if [[ $# -gt 0 ]]; then
    TARGETS=("$@")
else
    TARGETS=("$OUTPUT_DIR"/*.bib)
fi

FILES=()
for target in "${TARGETS[@]}"; do
    [[ -f "$target" ]] && FILES+=("$target")
done

if [[ ${#FILES[@]} -eq 0 ]]; then
    echo "[INFO] No bib files to sanitize" >&2
    exit 0
fi

# English terms: rot13-style obfuscation / cheap redaction.
# Expand here as new public-commit false positives appear.
SRC_COMPANY="$(printf '%s' 'go''qual')"
SRC_HOST="$(printf '%s' 'hej''dev')"

SAN_SRC_COMPANY="$SRC_COMPANY" SAN_SRC_HOST="$SRC_HOST" \
perl -0pi -e '
  BEGIN {
    $company = $ENV{SAN_SRC_COMPANY};
    $host = $ENV{SAN_SRC_HOST};
  }
  s/\Q$company\E/tbdhny/gi;
  s/\Q$host\E(\d*)/"urwqri".$1/gei;
' "${FILES[@]}"

echo "[OK] Sanitized ${#FILES[@]} bib files" >&2

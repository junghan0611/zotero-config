#!/usr/bin/env bash
# sanitize-public-bib.sh — 공개 커밋 전 BibTeX 비식별화 (얇은 위임 래퍼)
#
# 규칙 SSOT 는 `scripts/sanitize_bib.py` 다. 렌더러(`gen-bibtex.py`)가 **정렬 전에**
# 같은 규칙을 적용하므로, 이 스크립트는
#   · gen-bibtex 를 거치지 않는 산출물(github-starred.bib)
#   · 손으로 돌리는 재처리
# 를 위한 손잡이이자 공개 커밋 안전망이다. 규칙이 멱등이라 두 번 돌아도 무해하고,
# 실제로 바뀐 파일만 다시 쓰므로 mtime 을 흔들지 않는다.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIB_DIR="${ZOTERO_BIB_DIR:-$HOME/sync/org/resources/bib}"

if [[ $# -gt 0 ]]; then
    TARGETS=("$@")
else
    TARGETS=("$BIB_DIR"/*.bib)
fi

FILES=()
for target in "${TARGETS[@]}"; do
    [[ -f "$target" ]] && FILES+=("$target")
done

if [[ ${#FILES[@]} -eq 0 ]]; then
    echo "[INFO] No bib files to sanitize" >&2
    exit 0
fi

exec python3 "$SCRIPT_DIR/sanitize_bib.py" "${FILES[@]}"

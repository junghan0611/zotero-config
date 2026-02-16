#!/usr/bin/env bash
# run.sh — zotero-config 프로젝트 메인 진입점
#
# Usage:
#   ./run.sh server start|stop|status   — Translation Server 관리
#   ./run.sh bib full|sync|status       — BibTeX 동기화
#   ./run.sh save <url>                 — URL 저장
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "${1:-}" in
    server)
        shift
        exec "$SCRIPT_DIR/scripts/run.sh" "$@"
        ;;
    bib)
        shift
        exec "$SCRIPT_DIR/scripts/zotero-to-bib.sh" "$@"
        ;;
    save)
        shift
        exec "$SCRIPT_DIR/scripts/zotero-save-url.sh" "$@"
        ;;
    -h|--help|"")
        cat <<EOF
Usage: $(basename "$0") <command> [args]

Commands:
  server start|stop|status   Translation Server 관리
  bib full|sync|status       BibTeX 동기화 (Zotero Cloud → .bib)
  save <url> [collection]    URL을 Zotero에 저장

Examples:
  $(basename "$0") server start
  $(basename "$0") bib full
  $(basename "$0") bib sync
  $(basename "$0") save "https://arxiv.org/abs/2103.00020"
EOF
        ;;
    *)
        echo "Error: Unknown command '$1'" >&2
        exec "$0" --help
        ;;
esac

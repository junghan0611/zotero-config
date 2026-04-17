#!/usr/bin/env bash
# run.sh — zotero-config 프로젝트 메인 진입점
#
# Usage:
#   ./run.sh server start|stop|status   — Translation Server 관리
#   ./run.sh bib full|sync|status       — BibTeX 동기화
#   ./run.sh save [--sync] [--json] <url> [collection]
#                                     — URL 저장 (선택: bib sync + citation key 복구)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/output"
SYNC_DIR="$SCRIPT_DIR/.sync"
RESOURCES_DIR="$HOME/org/resources"

# Load .envrc and ~/.env.local
if [[ -f "$SCRIPT_DIR/.envrc" ]]; then
    set -a; source "$SCRIPT_DIR/.envrc"; set +a
fi
if [[ -f "$HOME/.env.local" ]]; then
    set -a; source "$HOME/.env.local"; set +a
fi

# output/*.bib → ~/org/resources/ 복사 (Syncthing 호환, symlink 사용 안 함)
copy_to_resources() {
    if [[ ! -d "$RESOURCES_DIR" ]]; then
        echo "[WARN] $RESOURCES_DIR 없음, 복사 건너뜀" >&2
        return
    fi
    local count=0
    for bib in "$OUTPUT_DIR"/*.bib; do
        cp "$bib" "$RESOURCES_DIR/$(basename "$bib")"
        count=$((count + 1))
    done
    echo "[OK] $count bib files → $RESOURCES_DIR"
}

case "${1:-}" in
    update)
        echo "=== Zotero sync ==="
        "$SCRIPT_DIR/scripts/zotero-to-bib.sh" sync
        echo ""
        echo "=== GitHub starred ==="
        "$SCRIPT_DIR/scripts/gh-starred-to-bib.sh"
        echo ""
        echo "=== Copy to resources ==="
        copy_to_resources
        ;;
    server)
        shift
        exec "$SCRIPT_DIR/scripts/run.sh" "$@"
        ;;
    bib)
        shift
        "$SCRIPT_DIR/scripts/zotero-to-bib.sh" "$@"
        # full/sync 후 resources로 복사 (status는 제외)
        if [[ "${1:-}" == "full" || "${1:-}" == "sync" ]]; then
            copy_to_resources
        fi
        ;;
    save)
        shift
        exec "$SCRIPT_DIR/scripts/zotero-save-url.sh" "$@"
        ;;
    starred)
        shift
        "$SCRIPT_DIR/scripts/gh-starred-to-bib.sh" "$@"
        copy_to_resources
        ;;
    enrich)
        shift
        ENRICH_ARGS=(
            --items "$SYNC_DIR/items.json"
            --sync-dir "$SYNC_DIR"
        )
        if [[ -n "${DATA4LIBRARY_API_KEY:-}" ]]; then
            ENRICH_ARGS+=(--data4lib-key "$DATA4LIBRARY_API_KEY")
        fi
        if [[ -n "${ZOTERO_API_KEY:-}" ]]; then
            ENRICH_ARGS+=(--zotero-key "$ZOTERO_API_KEY")
        fi
        if [[ -n "${ZOTERO_USER_ID:-}" ]]; then
            ENRICH_ARGS+=(--zotero-user-id "$ZOTERO_USER_ID")
        fi
        if [[ -n "${GOOGLE_BOOKS_API_KEY:-}" ]]; then
            ENRICH_ARGS+=(--gbooks-key "$GOOGLE_BOOKS_API_KEY")
        fi
        ENRICH_ARGS+=("$@")
        python3 "$SCRIPT_DIR/scripts/enrich-books.py" "${ENRICH_ARGS[@]}"
        ;;
    build)
        echo "Building bibcli..."
        INSTALL_DIR="${2:-$HOME/.local/bin}"
        mkdir -p "$INSTALL_DIR"
        BIBCLI_VERSION="$(git -C "$SCRIPT_DIR" describe --tags --always --dirty 2>/dev/null || echo dev)"
        (cd "$SCRIPT_DIR/bibcli" && CGO_ENABLED=0 go build -trimpath -ldflags "-s -w -X main.version=$BIBCLI_VERSION" -o "$INSTALL_DIR/bibcli" .)
        echo "Installed: $INSTALL_DIR/bibcli"
        echo "Set BIBCLI_DIR=$SCRIPT_DIR/output in your shell profile"
        echo "Skill docs: https://github.com/junghan0611/pi-skills/tree/main/bibcli"
        ;;
    -h|--help|"")
        cat <<EOF
Usage: $(basename "$0") <command> [args]

Commands:
  update                     Zotero 증분 + GitHub starred 한번에 갱신
  bib full|sync|status       BibTeX 동기화 (Zotero Cloud → .bib)
  enrich [--dry-run] [--max N]  book- 접두사 책 메타정보 보강 (data4library)
  starred                    GitHub starred → output/github-starred.bib
  save [--sync] [--json] <url> [collection]
                             URL을 Zotero에 저장
                             --sync: bib sync + citation key 복구
                             --json: 기계가 읽기 쉬운 JSON 출력
  server start|stop|status   Translation Server 관리
  build [dir]                bibcli 빌드 + 설치 (default: ~/.local/bin)

Examples:
  $(basename "$0") update
  $(basename "$0") bib full
  $(basename "$0") enrich --dry-run        # 미리보기
  $(basename "$0") enrich --max 3          # 3건만 실행
  $(basename "$0") save "https://arxiv.org/abs/2103.00020"
  $(basename "$0") save --sync --json "https://en.wikipedia.org/wiki/Vannevar_Bush"
EOF
        ;;
    *)
        echo "Error: Unknown command '$1'" >&2
        exec "$0" --help
        ;;
esac

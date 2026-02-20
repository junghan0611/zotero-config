#!/usr/bin/env bash
# run.sh — zotero-config 프로젝트 메인 진입점
#
# Usage:
#   ./run.sh server start|stop|status   — Translation Server 관리
#   ./run.sh bib full|sync|status       — BibTeX 동기화
#   ./run.sh save <url>                 — URL 저장
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/output"
RESOURCES_DIR="$HOME/org/resources"

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
    build)
        echo "Building bibcli..."
        INSTALL_DIR="${2:-$HOME/.local/bin}"
        mkdir -p "$INSTALL_DIR"
        BIBCLI_VERSION="$(git -C "$SCRIPT_DIR" describe --tags --always --dirty 2>/dev/null || echo dev)"
        (cd "$SCRIPT_DIR/bibcli" && go build -ldflags "-s -w -X main.version=$BIBCLI_VERSION" -o "$INSTALL_DIR/bibcli" .)
        echo "Installed: $INSTALL_DIR/bibcli"
        # Install skill to pi-skills
        SKILL_DIR="$HOME/repos/gh/pi-skills/bibcli"
        if [[ -d "$HOME/repos/gh/pi-skills" ]]; then
            mkdir -p "$SKILL_DIR"
            cp "$SCRIPT_DIR/bibcli/SKILL.md" "$SKILL_DIR/SKILL.md"
            echo "Skill installed: $SKILL_DIR/SKILL.md"
        fi
        echo "Set BIBCLI_DIR=$SCRIPT_DIR/output in your shell profile"
        ;;
    -h|--help|"")
        cat <<EOF
Usage: $(basename "$0") <command> [args]

Commands:
  update                     Zotero 증분 + GitHub starred 한번에 갱신
  bib full|sync|status       BibTeX 동기화 (Zotero Cloud → .bib)
  starred                    GitHub starred → output/github-starred.bib
  save <url> [collection]    URL을 Zotero에 저장
  server start|stop|status   Translation Server 관리
  build [dir]                bibcli 빌드 + 설치 (default: ~/.local/bin)

Examples:
  $(basename "$0") update
  $(basename "$0") bib full
  $(basename "$0") save "https://arxiv.org/abs/2103.00020"
EOF
        ;;
    *)
        echo "Error: Unknown command '$1'" >&2
        exec "$0" --help
        ;;
esac

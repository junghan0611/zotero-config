#!/usr/bin/env bash
# run.sh — zotero-config 프로젝트 메인 진입점
#
# Usage:
#   ./run.sh server start|stop|status   — Translation Server 관리
#   ./run.sh bib full|sync|status       — BibTeX 동기화
#   ./run.sh save [--sync] [--json] <url> [collection]
#                                     — URL 저장 (선택: bib sync + citation key 복구)
#
# 출력면: $ZOTERO_BIB_DIR (default ~/sync/org/resources/bib) — Syncthing 공유 실파일.
# 어느 기기에서 실행해도 대칭이다. Git 명령은 등장하지 않는다.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYNC_DIR="$SCRIPT_DIR/.sync"

# 실사용 서지 출력면 = Syncthing이 기기 간에 나르는 유일한 공유 산출물.
# 렌더가 여기에 직접 내려앉으므로 URL 등록/동기화에 Git이 개입하지 않는다.
BIB_DIR="${ZOTERO_BIB_DIR:-$HOME/sync/org/resources/bib}"

# Load .envrc and ~/.env.local
if [[ -f "$SCRIPT_DIR/.envrc" ]]; then
    set -a; source "$SCRIPT_DIR/.envrc"; set +a
fi
if [[ -f "$HOME/.env.local" ]]; then
    set -a; source "$HOME/.env.local"; set +a
fi

# *.bib 비식별화 후처리.
# `bib sync`/`bib full`은 이미 staging 안에서 sanitize 후 비교·교체하므로
# 이 커맨드는 명시적 재처리(예: starred 산출물)용 손잡이다.
sanitize_public_bibs() {
    local sanitizer="$SCRIPT_DIR/scripts/sanitize-public-bib.sh"
    if [[ ! -x "$sanitizer" ]]; then
        echo "[WARN] $sanitizer 실행 불가, 후처리 건너뜀" >&2
        return
    fi
    if [[ $# -gt 0 ]]; then
        "$sanitizer" "$@"
    else
        "$sanitizer" "$BIB_DIR"/*.bib
    fi
}

case "${1:-}" in
    update)
        echo "=== Zotero sync ==="
        "$SCRIPT_DIR/scripts/zotero-to-bib.sh" sync
        echo ""
        echo "=== GitHub starred ==="
        "$SCRIPT_DIR/scripts/gh-starred-to-bib.sh"
        sanitize_public_bibs "$BIB_DIR/github-starred.bib"
        ;;
    server)
        shift
        exec "$SCRIPT_DIR/scripts/run.sh" "$@"
        ;;
    bib)
        # 렌더는 $BIB_DIR(기본 ~/sync/org/resources/bib)에 직접 내려앉는다.
        # sanitize / 바이트 비교 / staged rename 은 전부 zotero-to-bib.sh 안에서
        # 끝난다. 복사 단계 없음 = Git 없음.
        shift
        "$SCRIPT_DIR/scripts/zotero-to-bib.sh" "$@"
        ;;
    save)
        shift
        exec "$SCRIPT_DIR/scripts/zotero-save-url.sh" "$@"
        ;;
    pin)
        # Agent-judged style + citationKey → Zotero PATCH (whitelist).
        # Never touches dateAdded. Use after save; prefer --sync so org can cite now.
        shift
        exec python3 "$SCRIPT_DIR/scripts/pin-item.py" --repo-dir "$SCRIPT_DIR" "$@"
        ;;
    starred)
        shift
        "$SCRIPT_DIR/scripts/gh-starred-to-bib.sh" "$@"
        sanitize_public_bibs "${1:-$BIB_DIR/github-starred.bib}"
        ;;
    sanitize)
        shift
        sanitize_public_bibs "$@"
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
        echo "Bib dir: $BIB_DIR (bibcli default; override with ZOTERO_BIB_DIR or --dir)"
        echo "Skill docs: https://github.com/junghan0611/pi-skills/tree/main/bibcli"
        ;;
    -h|--help|"")
        cat <<EOF
Usage: $(basename "$0") <command> [args]

Commands:
  update                     Zotero 증분 + GitHub starred 한번에 갱신
  bib full|sync|status       BibTeX 동기화 (Zotero Cloud → \$BIB_DIR/*.bib)
  enrich [--dry-run] [--max N]  book- 접두사 책 메타정보 보강 (data4library)
  starred                    GitHub starred → \$BIB_DIR/github-starred.bib
  sanitize [files...]        *.bib 비식별화 후처리 (default: \$BIB_DIR/*.bib)
  save [--sync] [--json] <url> [collection]
                             URL을 Zotero에 저장
                             --sync: bib sync + citation key 복구
                             --json: 기계가 읽기 쉬운 JSON 출력
  pin [--sync] --json '{...}|-'
                             스타일 필드 + citationKey를 Cloud에 PATCH
                             (에이전트 판단 후; dateAdded 불변; 키 중복 검사)
                             --sync: PATCH 후 bib sync → org SSOT 즉시 반영
  server start|stop|status   Translation Server 관리
  build [dir]                bibcli 빌드 + 설치 (default: ~/.local/bin)

Bib dir (실사용 출력면): $BIB_DIR
  ZOTERO_BIB_DIR 로 override 가능. 어느 기기에서 실행해도 대칭이며 Git은 개입하지 않는다.

Examples:
  $(basename "$0") update
  $(basename "$0") bib full
  $(basename "$0") enrich --dry-run        # 미리보기
  $(basename "$0") enrich --max 3          # 3건만 실행
  $(basename "$0") sanitize                # \$BIB_DIR/*.bib 후처리
  $(basename "$0") save "https://arxiv.org/abs/2103.00020"
  $(basename "$0") save --sync --json "https://en.wikipedia.org/wiki/Vannevar_Bush"
  $(basename "$0") pin --sync --json '{"zoteroKey":"ABCD","citationKey":"001.3-김74ㅁ","title":"…"}'
EOF
        ;;
    *)
        echo "Error: Unknown command '$1'" >&2
        exec "$0" --help
        ;;
esac

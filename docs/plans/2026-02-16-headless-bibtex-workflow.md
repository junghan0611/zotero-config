# Headless BibTeX Workflow Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Zotero Cloud API에서 아이템을 가져와 citar 호환 BibTeX 파일을 생성하는 headless 워크플로우 구축

**Architecture:** `run.sh`가 프로젝트 메인 진입점. Zotero Web API(JSON)로 아이템을 페이징 fetch하고, citationKey 유무에 따라 기존 키 사용 또는 BBT 규칙/KDC-저자기호로 새 키를 생성한 뒤, citar 호환 BibTeX로 변환하여 Book.bib / Slipbox.bib에 기록한다. 새로 생성한 citationKey는 Zotero API로 역동기화한다. 상태파일(`.sync/`)로 증분 동기화를 지원한다.

**Tech Stack:** bash, jq, curl, python3 (citation key의 한국어 초성 처리)

---

## Task 1: 프로젝트 루트 run.sh 생성

**Files:**
- Create: `run.sh`
- Existing reference: `scripts/run.sh` (Translation Server 관리 — 건드리지 않음)

**Step 1: run.sh 작성**

루트 `run.sh`는 서브커맨드 라우터. 기존 `scripts/run.sh`를 `server` 서브커맨드로 위임하고, `bib` 서브커맨드로 BibTeX 동기화를 처리한다.

```bash
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
```

**Step 2: 실행 권한 부여 및 테스트**

Run: `chmod +x run.sh && ./run.sh --help`
Expected: Usage 메시지 출력

Run: `./run.sh server status`
Expected: Translation Server 상태 (기존 scripts/run.sh로 위임)

**Step 3: Commit**

```bash
git add run.sh
git commit -m "feat: 프로젝트 루트 run.sh 메인 진입점 생성"
```

---

## Task 2: Zotero API fetcher 구현 (zotero-to-bib.sh 골격)

**Files:**
- Create: `scripts/zotero-to-bib.sh`

**Step 1: 스크립트 골격 작성**

페이징(limit=100)으로 Zotero API에서 전체 아이템을 JSON으로 가져와 `.sync/items.json`에 저장. `full` 모드와 `sync`(since 기반) 모드 구분.

```bash
#!/usr/bin/env bash
# zotero-to-bib.sh — Zotero Cloud → BibTeX 동기화
#
# Usage:
#   zotero-to-bib.sh full     전체 동기화
#   zotero-to-bib.sh sync     증분 동기화
#   zotero-to-bib.sh status   상태 확인
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
SYNC_DIR="$REPO_DIR/.sync"
ENVRC="$REPO_DIR/.envrc"

# .envrc 로드
if [[ -f "$ENVRC" ]]; then
    set -a; source "$ENVRC"; set +a
fi

# 설정
ZOTERO_API="https://api.zotero.org"
API_KEY="${ZOTERO_API_KEY:-}"
USER_ID="${ZOTERO_USER_ID:-}"
DATA4LIB_KEY="${DATA4LIBRARY_API_KEY:-}"
BOOK_BIB="$HOME/org/resources/Book.bib"
SLIPBOX_BIB="$HOME/org/resources/Slipbox.bib"
VERSION_FILE="$SYNC_DIR/last-version"
LOG_FILE="$SYNC_DIR/sync.log"
ITEMS_FILE="$SYNC_DIR/items.json"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; NC='\033[0m'
log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1" >&2; }

mkdir -p "$SYNC_DIR"

check_deps() {
    for cmd in curl jq python3; do
        command -v "$cmd" &>/dev/null || { log_error "Missing: $cmd"; exit 1; }
    done
    [[ -n "$API_KEY" ]] || { log_error "ZOTERO_API_KEY not set"; exit 1; }
    [[ -n "$USER_ID" ]] || { log_error "ZOTERO_USER_ID not set"; exit 1; }
}

# Zotero API에서 아이템 가져오기 (페이징)
fetch_items() {
    local since="${1:-0}"
    local start=0
    local limit=100
    local total=""
    local all_items="$SYNC_DIR/fetched.json"

    echo "[]" > "$all_items"

    while true; do
        local url="$ZOTERO_API/users/$USER_ID/items?format=json&limit=$limit&start=$start&itemType=-attachment+-note"
        if [[ "$since" != "0" ]]; then
            url="$url&since=$since"
        fi

        log_info "Fetching items (start=$start)..."

        local response_headers
        response_headers=$(mktemp)
        local body
        body=$(curl -s -D "$response_headers" \
            -H "Zotero-API-Key: $API_KEY" \
            "$url")

        # Last-Modified-Version 추출
        local version
        version=$(grep -i "Last-Modified-Version:" "$response_headers" | tr -d '\r' | awk '{print $2}')
        local total_results
        total_results=$(grep -i "Total-Results:" "$response_headers" | tr -d '\r' | awk '{print $2}')
        rm -f "$response_headers"

        if [[ -n "$version" ]]; then
            echo "$version" > "$VERSION_FILE"
        fi

        # 아이템 병합
        local count
        count=$(echo "$body" | jq 'length')
        jq -s '.[0] + .[1]' "$all_items" <(echo "$body") > "$all_items.tmp"
        mv "$all_items.tmp" "$all_items"

        log_info "  fetched $count items (total so far: $(jq 'length' "$all_items")${total_results:+/$total_results})"

        if [[ "$count" -lt "$limit" ]]; then
            break
        fi
        start=$((start + limit))
    done

    mv "$all_items" "$ITEMS_FILE"
    local final_count
    final_count=$(jq 'length' "$ITEMS_FILE")
    log_success "Total: $final_count items fetched"
}

# BibTeX 생성 (핵심 로직은 Task 3~5에서 구현)
generate_bibtex() {
    log_info "Generating BibTeX..."
    python3 "$SCRIPT_DIR/gen-bibtex.py" \
        --items "$ITEMS_FILE" \
        --book-bib "$BOOK_BIB" \
        --slipbox-bib "$SLIPBOX_BIB" \
        --data4lib-key "$DATA4LIB_KEY" \
        --sync-dir "$SYNC_DIR"
}

do_full() {
    log_info "=== Full sync ==="
    check_deps
    fetch_items 0
    generate_bibtex
    log_success "Full sync complete"
}

do_sync() {
    log_info "=== Incremental sync ==="
    check_deps
    local since=0
    if [[ -f "$VERSION_FILE" ]]; then
        since=$(cat "$VERSION_FILE")
    fi
    if [[ "$since" == "0" ]]; then
        log_warn "No previous version found. Running full sync."
    fi
    fetch_items "$since"
    generate_bibtex
    log_success "Sync complete"
}

do_status() {
    if [[ -f "$VERSION_FILE" ]]; then
        log_info "Last sync version: $(cat "$VERSION_FILE")"
    else
        log_warn "Never synced"
    fi
    if [[ -f "$ITEMS_FILE" ]]; then
        log_info "Cached items: $(jq 'length' "$ITEMS_FILE")"
    fi
    if [[ -f "$BOOK_BIB" ]]; then
        log_info "Book.bib entries: $(grep -c '^@' "$BOOK_BIB" 2>/dev/null || echo 0)"
    fi
    if [[ -f "$SLIPBOX_BIB" ]]; then
        log_info "Slipbox.bib entries: $(grep -c '^@' "$SLIPBOX_BIB" 2>/dev/null || echo 0)"
    fi
}

case "${1:-}" in
    full)   do_full ;;
    sync)   do_sync ;;
    status) do_status ;;
    -h|--help|"")
        cat <<'EOF'
Usage: zotero-to-bib.sh <command>

Commands:
  full     전체 동기화 (모든 아이템 가져오기)
  sync     증분 동기화 (마지막 이후 변경분만)
  status   현재 동기화 상태 확인
EOF
        ;;
    *)  log_error "Unknown: $1"; exit 1 ;;
esac
```

**Step 2: 실행 권한 + fetch 테스트 (아이템 5개만)**

Run: `chmod +x scripts/zotero-to-bib.sh`

테스트를 위해 임시로 limit을 5로 바꿔서 실행:
```bash
# 수동 테스트 (fetch만, bibtex 생성은 아직)
source .envrc
mkdir -p .sync
curl -s "https://api.zotero.org/users/$ZOTERO_USER_ID/items?format=json&limit=5&itemType=-attachment+-note" \
  -H "Zotero-API-Key: $ZOTERO_API_KEY" | jq 'length'
```
Expected: `5`

**Step 3: Commit**

```bash
git add scripts/zotero-to-bib.sh
git commit -m "feat: zotero-to-bib.sh API fetcher 골격 구현"
```

---

## Task 3: Python BibTeX 생성기 — 핵심 엔진 (gen-bibtex.py)

**Files:**
- Create: `scripts/gen-bibtex.py`

이것이 가장 큰 태스크. Zotero JSON → citar 호환 BibTeX 변환 + citation key 생성을 담당한다.

**Step 1: gen-bibtex.py 기본 구조 작성**

```python
#!/usr/bin/env python3
"""
gen-bibtex.py — Zotero JSON → citar 호환 BibTeX 변환기

Zotero Web API의 JSON 아이템을 읽어:
1. citationKey가 있으면 그대로 사용
2. 없으면 BBT 규칙 또는 KDC-저자기호로 생성
3. citar 호환 BibTeX 형식으로 Book.bib / Slipbox.bib에 기록
"""
import argparse
import json
import re
import sys
import unicodedata
from pathlib import Path

# === Zotero itemType → BibTeX entryType 매핑 ===
ITEM_TYPE_MAP = {
    "book": "book",
    "bookSection": "incollection",
    "journalArticle": "article",
    "magazineArticle": "article",
    "newspaperArticle": "article",
    "conferencePaper": "inproceedings",
    "thesis": "thesis",
    "report": "report",
    "webpage": "online",
    "blogPost": "online",
    "forumPost": "online",
    "encyclopediaArticle": "inreference",
    "dictionaryEntry": "inreference",
    "film": "video",
    "videoRecording": "video",
    "computerProgram": "software",
    "document": "misc",
    "letter": "misc",
    "manuscript": "unpublished",
    "interview": "misc",
    "presentation": "misc",
    "artwork": "misc",
    "podcast": "audio",
    "radioBroadcast": "audio",
    "tvBroadcast": "video",
    "map": "misc",
    "statute": "legislation",
    "case": "jurisdiction",
    "patent": "patent",
    "hearing": "misc",
    "bill": "legislation",
    "email": "misc",
    "instantMessage": "misc",
}

# === BBT citekeyFormat 규칙 (config에서 추출) ===
# type → prefix 매핑
CITEKEY_PREFIX = {
    "book": "book-",
    "blogPost": "blog-",
    "encyclopediaArticle": "wiki-",
    "film": "film-",
    "document": "doc-",
    "webpage": "web-",
    "newspaperArticle": "news-",
    "interview": "person-",
    "dictionaryEntry": "dict-",
    "artwork": "art-",
}

# year를 포함하지 않는 타입
NO_YEAR_TYPES = {"encyclopediaArticle", "webpage", "newspaperArticle",
                 "interview", "dictionaryEntry"}


def get_shorttitle(title: str, max_words: int = 3) -> str:
    """BBT shorttitle: 처음 3개 유의미 단어"""
    if not title:
        return ""
    # 특수문자 제거, 단어 분리
    words = re.findall(r'[a-zA-Z0-9\u3131-\u318E\uAC00-\uD7A3]+', title)
    skip = {"a", "an", "the", "of", "and", "in", "on", "for", "to", "with",
            "from", "by", "at", "is", "or", "as", "its", "de", "la", "le",
            "das", "der", "die", "el", "los", "les", "un", "une"}
    meaningful = [w for w in words if w.lower() not in skip]
    return "".join(meaningful[:max_words])


def get_shortyear(date: str) -> str:
    """BBT shortyear: 연도 마지막 2자리"""
    m = re.search(r'(\d{4})', date or "")
    return m.group(1)[-2:] if m else ""


def get_year(date: str) -> str:
    """연도 4자리 추출"""
    m = re.search(r'(\d{4})', date or "")
    return m.group(1) if m else ""


def sanitize_citekey(key: str) -> str:
    """citation key에서 불안전 문자 제거"""
    unsafe = set('"#%\'(),={}~')
    return "".join(c for c in key if c not in unsafe)


def generate_citekey_bbt(item_type: str, title: str, date: str) -> str:
    """BBT citekeyFormat 규칙으로 citation key 생성"""
    prefix = CITEKEY_PREFIX.get(item_type, "")
    shorttitle = get_shorttitle(title).lower()
    if item_type in NO_YEAR_TYPES:
        key = f"{prefix}{shorttitle}"
    else:
        shortyear = get_shortyear(date)
        key = f"{prefix}{shorttitle}{shortyear}"
    return sanitize_citekey(key) if key else "unknown"


# === 한글 초성 추출 ===
CHOSUNG = [
    'ㄱ', 'ㄲ', 'ㄴ', 'ㄷ', 'ㄸ', 'ㄹ', 'ㅁ', 'ㅂ', 'ㅃ', 'ㅅ',
    'ㅆ', 'ㅇ', 'ㅈ', 'ㅉ', 'ㅊ', 'ㅋ', 'ㅌ', 'ㅍ', 'ㅎ'
]


def get_chosung(char: str) -> str:
    """한글 문자의 초성 반환. 한글이 아니면 빈 문자열."""
    code = ord(char)
    if 0xAC00 <= code <= 0xD7A3:
        return CHOSUNG[(code - 0xAC00) // 588]
    return ""


# === 한국도서관 4자리 저자기호 (간소화) ===
# 실제 커터 번호표를 간소화한 매핑
# 저자성 + 2자리 번호 + 제목초성
def generate_author_notation(author_name: str, title: str) -> str:
    """한국도서관 4자리 저자기호 생성 (간소화)

    format: 성(1글자) + 커터번호(2자리) + 제목초성(1글자)
    예: 김정선, "내 문장이..." → 김74ㄴ

    간소화: 커터번호는 이름 두번째 글자의 유니코드 기반 산출
    (정밀 커터표 대신 근사치 사용)
    """
    if not author_name:
        return ""

    # 성 추출 (첫 글자)
    name = author_name.strip()
    surname = name[0] if name else ""

    # 이름 부분에서 커터번호 산출
    # 한글 이름: 두번째 글자 기반
    rest = name[1:].strip() if len(name) > 1 else ""
    if rest:
        code = ord(rest[0])
        if 0xAC00 <= code <= 0xD7A3:
            # 한글 범위 (가=44032 ~ 힣=55203) → 10~99
            cutter = 10 + int((code - 0xAC00) / (0xD7A3 - 0xAC00 + 1) * 90)
        elif 0x41 <= code <= 0x7A:
            # ASCII 알파벳 → 10~99
            cutter = 10 + int((code - 0x41) / 58 * 90)
        else:
            cutter = 50  # fallback
    else:
        cutter = 50

    # 제목 초성
    title_chosung = ""
    for ch in title:
        cs = get_chosung(ch)
        if cs:
            title_chosung = cs
            break
    if not title_chosung and title:
        title_chosung = title[0].lower()

    return f"{surname}{cutter}{title_chosung}"


# === BibTeX 필드 포맷팅 ===
def format_creators(creators: list, creator_type: str = "author") -> str:
    """Zotero creators → BibTeX author/editor/translator 필드"""
    names = []
    for c in creators:
        if c.get("creatorType") != creator_type:
            continue
        if "name" in c:
            # 단일 이름 필드 (한국 저자)
            names.append(f"{{{c['name']}}}")
        else:
            last = c.get("lastName", "")
            first = c.get("firstName", "")
            names.append(f"{last}, {first}" if last else first)
    return " and ".join(names)


def format_tags(tags: list) -> str:
    """Zotero tags → BibTeX keywords"""
    return ",".join(t.get("tag", "") for t in tags if t.get("tag"))


def escape_bibtex(text: str) -> str:
    """BibTeX 특수문자 이스케이프"""
    if not text:
        return ""
    # 중괄호만 이스케이프 (나머지는 {value}로 감싸므로 안전)
    return text.replace("{", r"\{").replace("}", r"\}")


def item_to_bibtex(item: dict, citekey: str) -> str:
    """Zotero JSON item → BibTeX entry 문자열"""
    data = item.get("data", item)
    item_type = data.get("itemType", "")
    entry_type = ITEM_TYPE_MAP.get(item_type, "misc")

    fields = []

    def add(name, value):
        if value:
            fields.append(f"  {name} = {{{escape_bibtex(str(value))}}}")

    # 필수 필드
    add("title", data.get("title", ""))

    # 저자/편집자/번역자
    creators = data.get("creators", [])
    author = format_creators(creators, "author")
    editor = format_creators(creators, "editor")
    translator = format_creators(creators, "translator")
    if author: add("author", author)
    if editor: add("editor", editor)
    if translator: add("translator", translator)

    # 날짜
    date = data.get("date", "")
    if date:
        add("date", date)

    # shorttitle
    short = data.get("shortTitle", "")
    if short:
        add("shorttitle", short)

    # 출판 정보
    add("publisher", data.get("publisher", ""))
    add("location", data.get("place", ""))
    add("edition", data.get("edition", ""))
    add("series", data.get("series", ""))
    add("volume", data.get("volume", ""))
    add("pagetotal", data.get("numPages", ""))

    # 식별자
    add("isbn", data.get("ISBN", ""))
    add("doi", data.get("DOI", ""))
    add("issn", data.get("ISSN", ""))
    add("url", data.get("url", ""))

    # 접근일
    access = data.get("accessDate", "")
    if access:
        add("urldate", access[:10])  # YYYY-MM-DD만

    # 언어
    lang = data.get("language", "")
    if lang:
        add("langid", lang)

    # 초록
    abstract = data.get("abstractNote", "")
    if abstract:
        add("abstract", abstract)

    # 키워드
    tags = format_tags(data.get("tags", []))
    if tags:
        add("keywords", tags)

    # extra → annotation
    extra = data.get("extra", "")
    if extra:
        add("annotation", extra)

    # === citar 호환 커스텀 필드 (BBT postscript 대체) ===
    add("callnumber", data.get("callNumber", ""))
    add("datemodified", data.get("dateModified", ""))
    add("dateadded", data.get("dateAdded", ""))

    # origdate
    add("origdate", data.get("originalDate", ""))

    entry = f"@{entry_type}{{{citekey},\n"
    entry += ",\n".join(fields)
    entry += "\n}\n"
    return entry


# === DATA4LIBRARY API ===
def lookup_kdc(isbn: str, api_key: str) -> str:
    """DATA4LIBRARY API로 ISBN → KDC 분류번호 조회"""
    if not isbn or not api_key:
        return ""
    import urllib.request
    import urllib.parse

    # ISBN 정규화 (하이픈 제거, 첫 번째 ISBN만)
    isbn = isbn.replace("-", "").split()[0]
    if len(isbn) < 10:
        return ""

    url = f"https://data4library.kr/api/srchDtlList?authKey={api_key}&isbn13={isbn}&format=json"
    try:
        with urllib.request.urlopen(url, timeout=10) as resp:
            result = json.loads(resp.read())
            details = result.get("response", {}).get("detail", [])
            if details:
                return details[0].get("book", {}).get("class_no", "")
    except Exception:
        pass
    return ""


# === 메인 처리 ===
def process_items(items_path: str, book_bib: str, slipbox_bib: str,
                  data4lib_key: str, sync_dir: str):
    """전체 아이템 처리: JSON → BibTeX 파일 생성"""
    with open(items_path) as f:
        items = json.load(f)

    book_entries = []
    slipbox_entries = []
    new_keys = {}  # key → citationKey (역동기화용)
    seen_keys = set()
    kdc_cache = {}  # ISBN → KDC

    print(f"Processing {len(items)} items...", file=sys.stderr)

    for item in items:
        data = item.get("data", item)
        item_type = data.get("itemType", "")
        zotero_key = data.get("key", "")

        # attachment, note 건너뛰기
        if item_type in ("attachment", "note"):
            continue

        # citation key 결정
        citekey = data.get("citationKey", "")

        if not citekey:
            # 새 키 생성
            title = data.get("title", "")
            date = data.get("date", "")
            isbn = data.get("ISBN", "")

            if item_type == "book" and isbn:
                # KDC 조회 시도
                isbn_clean = isbn.replace("-", "").split()[0]
                if isbn_clean not in kdc_cache:
                    kdc = lookup_kdc(isbn_clean, data4lib_key)
                    kdc_cache[isbn_clean] = kdc
                else:
                    kdc = kdc_cache[isbn_clean]

                if kdc:
                    # KDC-저자기호 형식
                    author_name = ""
                    for c in data.get("creators", []):
                        if c.get("creatorType") == "author":
                            author_name = c.get("name", "") or c.get("lastName", "")
                            break
                    notation = generate_author_notation(author_name, title)
                    citekey = f"{kdc}-{notation}" if notation else f"{kdc}"
                else:
                    citekey = generate_citekey_bbt(item_type, title, date)
            else:
                citekey = generate_citekey_bbt(item_type, title, date)

            # 역동기화 대상 기록
            if citekey and zotero_key:
                new_keys[zotero_key] = citekey

        if not citekey:
            citekey = f"unknown-{zotero_key}"

        # 중복 방지
        original = citekey
        counter = 1
        while citekey in seen_keys:
            citekey = f"{original}-{counter}"
            counter += 1
        seen_keys.add(citekey)

        # BibTeX 생성
        entry = item_to_bibtex(item, citekey)

        # 파일 분류
        if item_type == "book":
            book_entries.append(entry)
        else:
            slipbox_entries.append(entry)

    # BibTeX 파일 작성
    timestamp = __import__("datetime").datetime.now().isoformat()

    def write_bib(path, entries, label):
        header = f"% -*- bibtex -*-\n% {label}\n%\n"
        header += f"% Entries:  {len(entries)}\n"
        header += f"% Updated:  {timestamp}\n"
        header += f"% Source:   Zotero Cloud API (headless)\n%\n\n"
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        with open(path, "w") as f:
            f.write(header)
            f.write("\n".join(entries))
        print(f"  {label}: {len(entries)} entries → {path}", file=sys.stderr)

    write_bib(book_bib, book_entries, "Zotero Books")
    write_bib(slipbox_bib, slipbox_entries, "Zotero Slipbox")

    # 역동기화할 키 저장
    if new_keys:
        keys_file = Path(sync_dir) / "new-keys.json"
        with open(keys_file, "w") as f:
            json.dump(new_keys, f, ensure_ascii=False, indent=2)
        print(f"  New keys to sync back: {len(new_keys)} → {keys_file}",
              file=sys.stderr)

    print(f"Done! Books={len(book_entries)}, Slipbox={len(slipbox_entries)}",
          file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(description="Zotero JSON → BibTeX")
    parser.add_argument("--items", required=True, help="items.json path")
    parser.add_argument("--book-bib", required=True, help="Book.bib output path")
    parser.add_argument("--slipbox-bib", required=True, help="Slipbox.bib output path")
    parser.add_argument("--data4lib-key", default="", help="DATA4LIBRARY API key")
    parser.add_argument("--sync-dir", required=True, help=".sync directory")
    args = parser.parse_args()

    process_items(args.items, args.book_bib, args.slipbox_bib,
                  args.data4lib_key, args.sync_dir)


if __name__ == "__main__":
    main()
```

**Step 2: 단위 검증 — 소량 데이터로 테스트**

```bash
# 5개 아이템만 가져와서 테스트
source .envrc
curl -s "https://api.zotero.org/users/$ZOTERO_USER_ID/items?format=json&limit=5&itemType=-attachment+-note" \
  -H "Zotero-API-Key: $ZOTERO_API_KEY" > .sync/test-items.json

python3 scripts/gen-bibtex.py \
  --items .sync/test-items.json \
  --book-bib .sync/test-Book.bib \
  --slipbox-bib .sync/test-Slipbox.bib \
  --data4lib-key "$DATA4LIBRARY_API_KEY" \
  --sync-dir .sync
```

Expected: `.sync/test-Book.bib`과 `.sync/test-Slipbox.bib` 생성, 엔트리 확인

```bash
cat .sync/test-Book.bib
cat .sync/test-Slipbox.bib
```

**Step 3: 기존 Book.bib와 형식 비교**

```bash
# 기존 엔트리와 새 엔트리의 필드 비교
head -20 ~/org/resources/Book.bib
echo "---"
head -20 .sync/test-Book.bib
```

필드 순서, 이름, 형식이 일치하는지 확인. 차이가 있으면 수정.

**Step 4: Commit**

```bash
git add scripts/gen-bibtex.py
git commit -m "feat: gen-bibtex.py Zotero JSON → BibTeX 변환기 구현"
```

---

## Task 4: 통합 테스트 — full sync 실행

**Files:**
- Modify: `scripts/zotero-to-bib.sh` (필요시 조정)
- Modify: `scripts/gen-bibtex.py` (필요시 조정)

**Step 1: 백업 후 full sync 실행**

```bash
# 기존 bib 파일 백업
cp ~/org/resources/Book.bib ~/org/resources/Book.bib.bak
cp ~/org/resources/Slipbox.bib ~/org/resources/Slipbox.bib.bak

# full sync 실행
./run.sh bib full
```

Expected:
- `.sync/items.json` 생성 (~6500 아이템)
- `Book.bib` 생성 (book 타입)
- `Slipbox.bib` 생성 (나머지)
- `.sync/last-version` 기록
- `.sync/new-keys.json` (새 키가 있으면)

**Step 2: 결과 검증**

```bash
# 엔트리 수 비교
echo "Old Book.bib: $(grep -c '^@' ~/org/resources/Book.bib.bak)"
echo "New Book.bib: $(grep -c '^@' ~/org/resources/Book.bib)"
echo "Old Slipbox.bib: $(grep -c '^@' ~/org/resources/Slipbox.bib.bak)"
echo "New Slipbox.bib: $(grep -c '^@' ~/org/resources/Slipbox.bib)"

# 기존 키가 보존되는지 확인
grep "HowTakeSmart17" ~/org/resources/Book.bib
grep "005-포14ㅋ" ~/org/resources/Book.bib
grep "web-perplexity" ~/org/resources/Slipbox.bib
```

**Step 3: citar에서 로드 확인**

Emacs에서:
```
M-x citar-refresh
SPC n b b  (citar-insert-citation)
```
검색이 동작하고 기존 키로 찾을 수 있으면 성공.

**Step 4: 문제 수정 후 Commit**

```bash
git add scripts/gen-bibtex.py scripts/zotero-to-bib.sh .sync/.gitignore
git commit -m "fix: full sync 통합 테스트 통과"
```

---

## Task 5: citationKey 역동기화 (Zotero API PATCH)

**Files:**
- Create: `scripts/writeback-keys.sh`
- Modify: `scripts/zotero-to-bib.sh` (writeback 호출 추가)

**Step 1: writeback 스크립트 작성**

```bash
#!/usr/bin/env bash
# writeback-keys.sh — 새로 생성한 citationKey를 Zotero Cloud에 기록
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

if [[ -f "$REPO_DIR/.envrc" ]]; then
    set -a; source "$REPO_DIR/.envrc"; set +a
fi

SYNC_DIR="$REPO_DIR/.sync"
KEYS_FILE="$SYNC_DIR/new-keys.json"
ZOTERO_API="https://api.zotero.org"

if [[ ! -f "$KEYS_FILE" ]]; then
    echo "No new keys to sync back."
    exit 0
fi

count=$(jq 'length' "$KEYS_FILE")
echo "Writing back $count citation keys to Zotero..."

# 각 아이템에 citationKey PATCH
jq -r 'to_entries[] | "\(.key)\t\(.value)"' "$KEYS_FILE" | while IFS=$'\t' read -r zotero_key citekey; do
    echo "  $zotero_key → $citekey"

    # 현재 아이템 version 가져오기
    version=$(curl -s \
        -H "Zotero-API-Key: $ZOTERO_API_KEY" \
        "$ZOTERO_API/users/$ZOTERO_USER_ID/items/$zotero_key" | jq '.version')

    # citationKey 업데이트 (PATCH)
    curl -s -X PATCH \
        -H "Zotero-API-Key: $ZOTERO_API_KEY" \
        -H "Content-Type: application/json" \
        -H "If-Unmodified-Since-Version: $version" \
        -d "{\"citationKey\": \"$citekey\"}" \
        "$ZOTERO_API/users/$ZOTERO_USER_ID/items/$zotero_key" > /dev/null

    # rate limiting 방지
    sleep 0.2
done

echo "Done! Removing processed keys file."
mv "$KEYS_FILE" "$KEYS_FILE.done"
```

**Step 2: zotero-to-bib.sh에 writeback 호출 추가**

`generate_bibtex()` 함수 뒤에:
```bash
# 새 citationKey 역동기화
writeback_keys() {
    if [[ -f "$SYNC_DIR/new-keys.json" ]]; then
        local count
        count=$(jq 'length' "$SYNC_DIR/new-keys.json")
        if [[ "$count" -gt 0 ]]; then
            log_info "Writing back $count new citation keys to Zotero..."
            "$SCRIPT_DIR/writeback-keys.sh"
        fi
    fi
}
```

`do_full()`과 `do_sync()`의 `generate_bibtex` 뒤에 `writeback_keys` 호출 추가.

**Step 3: 테스트**

```bash
# new-keys.json이 있으면 실행
cat .sync/new-keys.json  # 내용 확인
./scripts/writeback-keys.sh

# Zotero에서 확인
source .envrc
curl -s "https://api.zotero.org/users/$ZOTERO_USER_ID/items/<KEY>?format=json" \
  -H "Zotero-API-Key: $ZOTERO_API_KEY" | jq '.data.citationKey'
```

**Step 4: Commit**

```bash
git add scripts/writeback-keys.sh scripts/zotero-to-bib.sh
git commit -m "feat: citationKey 역동기화 (Zotero API PATCH)"
```

---

## Task 6: .gitignore + .sync 정리 + 최종 커밋

**Files:**
- Modify: `.gitignore`

**Step 1: .gitignore 업데이트**

```
# 기존 내용에 추가
.sync/
```

**Step 2: 최종 테스트 사이클**

```bash
# 1. 서버 상태
./run.sh server status

# 2. full sync
./run.sh bib full

# 3. 상태 확인
./run.sh bib status

# 4. sync (증분 — 변경 없으면 0개)
./run.sh bib sync

# 5. bib 파일 확인
grep -c '^@' ~/org/resources/Book.bib
grep -c '^@' ~/org/resources/Slipbox.bib
```

**Step 3: 최종 Commit + Push**

```bash
git add .gitignore run.sh scripts/
git commit -m "feat: headless BibTeX 워크플로우 완성 — Zotero Cloud → .bib"
git push
```

---

## Task 7: br 이슈 완료 + 설계 노트 업데이트

**Step 1: br 이슈 업데이트**

```bash
br close zotero-config-fd7
br update zotero-config-bdr --notes "BibTeX 동기화 포함 완료"
br sync --flush-only
git add .beads/
git commit -m "sync beads: fd7 완료"
git push
```

**Step 2: org 설계 노트 TODO 체크**

`20250409T144103--§zotero-config-...org` 파일의 TODO 항목들을 `[X]`로 체크.

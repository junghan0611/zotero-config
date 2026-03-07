#!/usr/bin/env python3
"""
enrich-books.py — book- 접두사 책의 메타정보를 data4library로 보강

1. items.json에서 book- 접두사 citationKey인 book 아이템 찾기
2. yes24 title 파싱 → 깨끗한 제목/저자/출판사 추출
3. data4library 제목 검색 → ISBN 확보
4. ISBN으로 KDC, 연도, 초록 등 조회
5. Zotero Cloud에 PATCH (title, ISBN, date, publisher, creators, abstract, callNumber, collections)

Usage:
    python3 enrich-books.py --items .sync/items.json --sync-dir .sync \
        --data4lib-key KEY --zotero-key KEY --zotero-user-id ID \
        [--dry-run] [--max N]
"""

import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

# ---------------------------------------------------------------------------
# KDC → Zotero Collection mapping
# ---------------------------------------------------------------------------

KDC_COLLECTION_MAP = {
    "0": "S7W5Z692",   # 000-정보
    "1": "LS25E24L",   # 100-철학
    "2": "J2ES338U",   # 200-영성
    "3": "VF5GEFUJ",   # 300-사회
    "4": "NQRCWT8U",   # 400-자연
    "5": "6NNNFHJD",   # 500-기술
    "6": "B3N2AXFF",   # 600-예술
    "7": "PGQXIXD6",   # 700-언어
    "8": "ZRD2LLTI",   # 800-문학
    "9": "FEEZYYIH",   # 900-역사
}

BOOK_COLLECTION = "MC24XQEC"  # Book 최상위

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------

RED = "\033[0;31m"
GREEN = "\033[0;32m"
YELLOW = "\033[1;33m"
BLUE = "\033[0;34m"
NC = "\033[0m"

def log_info(msg):    print(f"{BLUE}[INFO]{NC} {msg}")
def log_ok(msg):      print(f"{GREEN}[OK]{NC} {msg}")
def log_warn(msg):    print(f"{YELLOW}[WARN]{NC} {msg}", file=sys.stderr)
def log_error(msg):   print(f"{RED}[ERROR]{NC} {msg}", file=sys.stderr)


# ---------------------------------------------------------------------------
# Title parsing
# ---------------------------------------------------------------------------

def parse_yes24_title(title):
    """Parse yes24 title pattern into (clean_title, author, publisher).

    Patterns:
        "나라는 착각 | 그레고리 번스 | 흐름출판 - 예스24"
        "Do it! LLM을 활용한 AI 에이전트 개발 입문 - 예스24"
        "[전자책]롤랑 바르트의 인문학 기호학 톺아보기 - 예스24"
    """
    if not title:
        return title, "", ""

    # Remove [전자책] prefix
    title = re.sub(r"^\[전자책\]", "", title)

    # Remove " - 예스24" and variants at end
    title = re.sub(r"\s*-\s*예스24.*$", "", title)

    # Try pipe-separated: "제목 | 저자 | 출판사"
    parts = [p.strip() for p in title.split("|")]
    if len(parts) >= 3:
        return parts[0], parts[1], parts[2]
    elif len(parts) == 2:
        return parts[0], parts[1], ""

    return title.strip(), "", ""


def parse_creators_from_string(author_str):
    """Parse Korean author/translator string into Zotero creators.

    Examples:
        "그레고리 번스" → [{"creatorType": "author", "lastName": "그레고리 번스"}]
        "그레고리 번스 저/홍우진 역" → author + translator
        "김성회 지음" → author
        "마이클 샌델 지음 ;함규진 옮김" → author + translator
    """
    if not author_str:
        return []

    creators = []

    # Split by semicolon first (data4library style)
    parts = re.split(r"\s*;\s*", author_str)

    for part in parts:
        part = part.strip()
        if not part:
            continue

        # Try "NAME 저/TRANSLATOR (역)?" combined — MUST be before single 저/역
        m = re.match(r"(.+?)\s*저\s*/\s*(.+?)(?:\s*역)?$", part)
        if m:
            creators.append({"creatorType": "author", "name": m.group(1).strip()})
            creators.append({"creatorType": "translator", "name": m.group(2).strip()})
            continue

        # Try "NAME 옮김/역" pattern (translator)
        m = re.match(r"(.+?)\s*(?:옮김|옮긴이|역)$", part)
        if m:
            name = re.sub(r"\s*:\s*$", "", m.group(1).strip())
            creators.append({"creatorType": "translator", "name": name})
            continue

        # Try "NAME 지음/저/글" pattern (author)
        m = re.match(r"(.+?)\s*(?:지음|저|글|글쓴이|지은이)$", part)
        if m:
            name = re.sub(r"\s*:\s*$", "", m.group(1).strip())
            creators.append({"creatorType": "author", "name": name})
            continue

        # Try "NAME 그림" pattern (contributor)
        m = re.match(r"(.+?)\s*(?:그림|그린이)$", part)
        if m:
            continue  # skip illustrators

        # Fallback: treat as author
        if part:
            creators.append({"creatorType": "author", "name": part})

    return creators


# ---------------------------------------------------------------------------
# data4library API
# ---------------------------------------------------------------------------

def d4l_search_by_title(api_key, title, max_results=5):
    """Search data4library by title, return list of book dicts."""
    url = (
        f"https://data4library.kr/api/srchBooks"
        f"?authKey={urllib.parse.quote(api_key)}"
        f"&title={urllib.parse.quote(title)}"
        f"&format=json&pageSize={max_results}"
    )

    try:
        req = urllib.request.Request(url, headers={"User-Agent": "enrich-books/1.0"})
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            docs = data.get("response", {}).get("docs", [])
            return [d.get("doc", {}) for d in docs]
    except Exception as e:
        log_warn(f"  d4l search failed: {e}")
        return []


def d4l_lookup_isbn(api_key, isbn):
    """Look up full details by ISBN from data4library."""
    url = (
        f"https://data4library.kr/api/srchDtlList"
        f"?authKey={urllib.parse.quote(api_key)}"
        f"&isbn13={urllib.parse.quote(isbn)}&format=json"
    )

    try:
        req = urllib.request.Request(url, headers={"User-Agent": "enrich-books/1.0"})
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            detail = data.get("response", {}).get("detail", [])
            if detail:
                return detail[0].get("book", {})
    except Exception as e:
        log_warn(f"  d4l isbn lookup failed: {e}")

    return None


def title_similarity(a, b):
    """Calculate title similarity ratio (0.0~1.0).

    Uses longest common subsequence ratio for robust Korean matching.
    """
    a = a.lower().replace(" ", "")
    b = b.lower().replace(" ", "")
    if not a or not b:
        return 0.0

    # Exact containment
    if a == b:
        return 1.0
    if a in b or b in a:
        return min(len(a), len(b)) / max(len(a), len(b))

    # LCS length
    m, n = len(a), len(b)
    # Optimize: if lengths are too different, skip
    if min(m, n) / max(m, n) < 0.4:
        return 0.0

    prev = [0] * (n + 1)
    for i in range(m):
        curr = [0] * (n + 1)
        for j in range(n):
            if a[i] == b[j]:
                curr[j + 1] = prev[j] + 1
            else:
                curr[j + 1] = max(curr[j], prev[j + 1])
        prev = curr

    lcs_len = prev[n]
    return (2.0 * lcs_len) / (m + n)


def find_isbn_by_title(api_key, clean_title):
    """Search data4library by title and find best matching ISBN.

    Returns (isbn13, book_detail) or (None, None).
    Requires similarity >= 0.6 to avoid false positives.
    """
    if not clean_title:
        return None, None

    # Try full title first
    results = d4l_search_by_title(api_key, clean_title)

    # If no results, try first significant word (but only if title has multiple words)
    if not results:
        words = clean_title.split()
        if len(words) >= 2:
            results = d4l_search_by_title(api_key, words[0])

    if not results:
        return None, None

    # Find best match with strict similarity
    clean_norm = re.sub(r"\s*[:：].*$", "", clean_title)  # Remove subtitle for matching
    best = None
    best_score = 0.0

    for book in results:
        book_title = book.get("bookname", "").strip()
        # Remove subtitle from d4l title too
        book_title_norm = re.sub(r"\s*[:：].*$", "", book_title)

        score = title_similarity(clean_norm, book_title_norm)

        if score > best_score:
            best_score = score
            best = book

    # Require high similarity (0.8+) to prevent false positives
    if best and best_score >= 0.8:
        isbn = best.get("isbn13", "")
        if isbn:
            log_info(f"  match: \"{best.get('bookname', '')[:50]}\" (score={best_score:.2f})")
            detail = d4l_lookup_isbn(api_key, isbn)
            return isbn, detail or best
        return None, None

    if best:
        log_warn(f"  low match: \"{best.get('bookname', '')[:50]}\" (score={best_score:.2f}, need 0.8+)")

    return None, None


# ---------------------------------------------------------------------------
# Zotero API
# ---------------------------------------------------------------------------

def zotero_get_item(api_key, user_id, item_key):
    """Get a single item from Zotero API (for current version)."""
    url = f"https://api.zotero.org/users/{user_id}/items/{item_key}"
    req = urllib.request.Request(url, headers={
        "Zotero-API-Key": api_key,
        "User-Agent": "enrich-books/1.0",
    })
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            return data.get("version", data.get("data", {}).get("version")), data
    except Exception as e:
        log_warn(f"  zotero get failed: {e}")
        return None, None


def zotero_patch_item(api_key, user_id, item_key, version, patch_data):
    """PATCH a Zotero item with updated fields."""
    url = f"https://api.zotero.org/users/{user_id}/items/{item_key}"
    body = json.dumps(patch_data).encode("utf-8")
    req = urllib.request.Request(url, data=body, method="PATCH", headers={
        "Zotero-API-Key": api_key,
        "Content-Type": "application/json",
        "If-Unmodified-Since-Version": str(version),
        "User-Agent": "enrich-books/1.0",
    })
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return resp.status
    except urllib.error.HTTPError as e:
        log_warn(f"  zotero patch failed: HTTP {e.code}")
        return e.code
    except Exception as e:
        log_warn(f"  zotero patch failed: {e}")
        return None


# ---------------------------------------------------------------------------
# Citation key generation (KDC)
# ---------------------------------------------------------------------------

CHOSUNG = [
    "ㄱ", "ㄲ", "ㄴ", "ㄷ", "ㄸ", "ㄹ", "ㅁ", "ㅂ", "ㅃ",
    "ㅅ", "ㅆ", "ㅇ", "ㅈ", "ㅉ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ",
]

def get_chosung(char):
    code = ord(char)
    if 0xAC00 <= code <= 0xD7A3:
        return CHOSUNG[(code - 0xAC00) // 588]
    return ""

def is_korean(char):
    code = ord(char)
    return (0xAC00 <= code <= 0xD7A3) or (0x3131 <= code <= 0x318E)

def cutter_number(char):
    code = ord(char)
    if 0xAC00 <= code <= 0xD7A3:
        return 10 + ((code - 0xAC00) * 89) // (0xD7A3 - 0xAC00)
    elif char.isalpha():
        return 10 + (ord(char.lower()) - ord("a")) * 89 // 25
    return 50

def make_author_code(author_name, title):
    name = author_name.strip()
    if not name:
        return "unknown"
    surname = name[0]
    cn = cutter_number(name[1]) if len(name) > 1 else 50
    title_cho = ""
    for ch in title:
        cho = get_chosung(ch)
        if cho:
            title_cho = cho
            break
    if not title_cho:
        for ch in title:
            if ch.isalpha():
                title_cho = ch.lower()
                break
        if not title_cho:
            title_cho = "x"
    return f"{surname}{cn}{title_cho}"


def make_kdc_citation_key(kdc, author_name, title):
    """Generate KDC citation key: e.g. 325.24-김74ㄴ"""
    author_code = make_author_code(author_name, title)
    return f"{kdc}-{author_code}"


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def build_patch(clean_title, d4l_book, creators, kdc, isbn):
    """Build Zotero PATCH payload from enriched data."""
    patch = {}

    # Title
    if clean_title:
        patch["title"] = clean_title

    # ISBN
    if isbn:
        patch["ISBN"] = isbn

    # Date
    year = d4l_book.get("publication_year", "") if d4l_book else ""
    if year:
        patch["date"] = year

    # Publisher
    publisher = d4l_book.get("publisher", "").strip() if d4l_book else ""
    if publisher:
        patch["publisher"] = publisher

    # Creators
    if creators:
        patch["creators"] = creators

    # Abstract
    desc = d4l_book.get("description", "").strip() if d4l_book else ""
    if desc:
        patch["abstractNote"] = desc

    # Call number (KDC)
    if kdc:
        patch["callNumber"] = kdc

    # Citation key
    if kdc and creators:
        author_name = ""
        for c in creators:
            if c.get("creatorType") == "author":
                author_name = c.get("name", c.get("lastName", ""))
                break
        if author_name:
            patch["citationKey"] = make_kdc_citation_key(kdc, author_name, clean_title)

    # Collections: add KDC section + Book parent
    if kdc:
        kdc_first = kdc[0] if kdc else ""
        section_key = KDC_COLLECTION_MAP.get(kdc_first)
        collections = [BOOK_COLLECTION]
        if section_key:
            collections.append(section_key)
        patch["collections"] = collections

    return patch


def process_item(item, api_key_d4l, api_key_zotero, user_id, dry_run=False):
    """Process a single book- item: parse, lookup, patch."""
    data = item.get("data", {})
    zotero_key = item.get("key", data.get("key", ""))
    raw_title = data.get("title", "")
    existing_key = data.get("citationKey", "")

    log_info(f"Processing {zotero_key}: {raw_title[:60]}...")

    # Step 1: Parse title
    clean_title, parsed_author, parsed_publisher = parse_yes24_title(raw_title)
    if clean_title == raw_title.strip():
        # Not a yes24 title, just clean basic patterns
        clean_title = re.sub(r"\s*-\s*예스24.*$", "", clean_title)
        clean_title = re.sub(r"^\[전자책\]", "", clean_title).strip()

    log_info(f"  title: \"{clean_title}\"")
    if parsed_author:
        log_info(f"  parsed author: \"{parsed_author}\"")

    # Step 2: Get creators from parsed author or existing (cleaned)
    d4l_authors_str = ""
    creators = []

    # Step 3: Search ISBN via data4library
    isbn, d4l_book = find_isbn_by_title(api_key_d4l, clean_title)

    if isbn and d4l_book:
        log_ok(f"  ISBN found: {isbn}")
        log_ok(f"  KDC: {d4l_book.get('class_no', 'N/A')} ({d4l_book.get('class_nm', '')})")
        d4l_authors_str = d4l_book.get("authors", "")
        # Prefer data4library authors (more structured)
        creators = parse_creators_from_string(d4l_authors_str)
    else:
        log_warn(f"  ISBN not found for \"{clean_title}\"")
        # Use parsed info from title or reconstruct from mangled creators
        existing_creators = data.get("creators", [])
        if existing_creators:
            # Zotero mangled pattern: lastName="역", firstName="그레고리 번스 저/홍우진"
            # Reconstruct by combining all parts
            for c in existing_creators:
                first = (c.get("firstName") or "").strip()
                last = (c.get("lastName") or "").strip()
                name = c.get("name") or ""
                if not name:
                    # Remove "역" as standalone lastName
                    if last == "역" and first:
                        name = first
                    elif last and first:
                        name = f"{last}{first}"
                    else:
                        name = last or first
                if name:
                    creators.extend(parse_creators_from_string(name))
        if not creators and parsed_author:
            creators = [{"creatorType": "author", "name": parsed_author}]
        if not creators and parsed_publisher:
            # At minimum, use the publisher from title as hint
            pass

    kdc = d4l_book.get("class_no", "").strip() if d4l_book else ""

    # Step 4: Build patch
    patch = build_patch(clean_title, d4l_book, creators, kdc, isbn)

    if not patch:
        log_warn(f"  No enrichment data, skipping")
        return False

    # Step 5: Apply
    if dry_run:
        log_info(f"  [DRY-RUN] Would PATCH:")
        for k, v in patch.items():
            val_str = json.dumps(v, ensure_ascii=False)
            if len(val_str) > 80:
                val_str = val_str[:77] + "..."
            log_info(f"    {k}: {val_str}")
        return True

    # Get current version
    version, _ = zotero_get_item(api_key_zotero, user_id, zotero_key)
    if version is None:
        log_error(f"  Cannot get version for {zotero_key}")
        return False

    time.sleep(0.3)

    status = zotero_patch_item(api_key_zotero, user_id, zotero_key, version, patch)
    if status == 204:
        ck = patch.get("citationKey", existing_key)
        log_ok(f"  PATCHED → {ck}")
        return True
    else:
        log_error(f"  PATCH failed (HTTP {status})")
        return False


def main():
    parser = argparse.ArgumentParser(description="Enrich book- prefix books via data4library")
    parser.add_argument("--items", required=True, help="Path to items.json")
    parser.add_argument("--sync-dir", default=".sync", help="Sync directory")
    parser.add_argument("--data4lib-key", default="", help="DATA4LIBRARY API key")
    parser.add_argument("--zotero-key", default="", help="Zotero API key")
    parser.add_argument("--zotero-user-id", default="", help="Zotero user ID")
    parser.add_argument("--dry-run", action="store_true", help="Preview without PATCHing")
    parser.add_argument("--max", type=int, default=0, help="Max items to process (0=all)")
    args = parser.parse_args()

    # Load items
    with open(args.items, "r", encoding="utf-8") as f:
        items = json.load(f)

    # Find book- prefix items
    targets = []
    for item in items:
        data = item.get("data", {})
        if data.get("itemType") != "book":
            continue
        ck = data.get("citationKey", "")
        if not ck.startswith("book-"):
            continue
        targets.append(item)

    log_info(f"Found {len(targets)} book- prefix items")

    if not targets:
        log_ok("Nothing to enrich")
        return

    if args.max > 0:
        targets = targets[:args.max]
        log_info(f"Processing first {len(targets)} items (--max {args.max})")

    success = 0
    failed = 0

    for item in targets:
        try:
            ok = process_item(
                item, args.data4lib_key, args.zotero_key, args.zotero_user_id,
                dry_run=args.dry_run,
            )
            if ok:
                success += 1
            else:
                failed += 1
        except Exception as e:
            log_error(f"  Exception: {e}")
            failed += 1

        time.sleep(0.5)  # rate limit

    log_info(f"Done: {success} enriched, {failed} failed")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
gen-bibtex.py - Zotero JSON -> BibTeX 변환 엔진

Converts Zotero API JSON items to citar-compatible BibTeX files.
Splits output by BibTeX entry type: Book.bib, Online.bib, Software.bib, etc.

Network-free renderer. Citation keys already set on Zotero items are kept
as-is. Missing keys get a local BBT-style fallback. KDC / data4library is
NOT called here — book classification is a human ritual (see operator skill);
assistive lookup lives in `bibcli lookup` and optional `./run.sh enrich`.

Usage:
    python3 gen-bibtex.py \
        --items .sync/items.json \
        --book-bib ~/org/resources/Book.bib \
        --output-dir ~/org/resources \
        --sync-dir .sync
"""

import argparse
import json
import os
import re
from datetime import datetime, timezone

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# Stop words for shorttitle generation
STOP_WORDS = frozenset(
    "a an the of and in on for to with is are was were by at from".split()
)

# BBT citekeyFormat prefix map
PREFIX_MAP = {
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

# Types that do NOT get a year suffix
NO_YEAR_TYPES = frozenset(
    ["encyclopediaArticle", "webpage", "newspaperArticle", "interview", "dictionaryEntry"]
)

# BibTeX entry type -> output file stem (types not listed go to Misc.bib)
BIB_FILE_MAP = {
    "online": "Online",
    "software": "Software",
    "inreference": "Reference",
    "video": "Video",
    "article": "Article",
}
DEFAULT_BIB_STEM = "Misc"

# Zotero itemType -> BibTeX entryType
ENTRY_TYPE_MAP = {
    "book": "book",
    "bookSection": "incollection",
    "journalArticle": "article",
    "webpage": "online",
    "blogPost": "online",
    "forumPost": "online",
    "encyclopediaArticle": "inreference",
    "dictionaryEntry": "inreference",
    "film": "video",
    "videoRecording": "video",
    "tvBroadcast": "video",
    "computerProgram": "software",
    "conferencePaper": "inproceedings",
    "thesis": "thesis",
    "report": "report",
}

# ---------------------------------------------------------------------------
# Citation key helpers
# ---------------------------------------------------------------------------

def is_korean(char):
    """Check if character is Korean (syllable or jamo)."""
    code = ord(char)
    return (0xAC00 <= code <= 0xD7A3) or (0x3131 <= code <= 0x318E)


def shorttitle(title, max_words=3):
    """First N meaningful words of title, camelCase, ASCII-safe."""
    if not title:
        return "untitled"

    # Split on whitespace and punctuation
    words = re.findall(r"[\w]+", title, re.UNICODE)
    meaningful = []
    for w in words:
        if w.lower() in STOP_WORDS:
            continue
        meaningful.append(w)
        if len(meaningful) >= max_words:
            break

    if not meaningful:
        meaningful = words[:max_words] if words else ["untitled"]

    # CamelCase
    result = ""
    for w in meaningful:
        if is_korean(w[0]) if w else False:
            result += w
        else:
            result += w.capitalize() if w else ""

    return result


def shortyear(date_str):
    """Extract last 2 digits of year from date string."""
    if not date_str:
        return ""
    m = re.search(r"(\d{4})", date_str)
    if m:
        return m.group(1)[2:]
    return ""


def get_first_author(creators):
    """Get first author name from creators list."""
    for c in creators:
        if c.get("creatorType") == "author":
            name = c.get("name", "")
            if not name:
                last = c.get("lastName", "")
                first = c.get("firstName", "")
                name = last if last else first
            return name
    # Fallback: first creator of any type
    if creators:
        c = creators[0]
        name = c.get("name", "")
        if not name:
            name = c.get("lastName", c.get("firstName", ""))
        return name
    return ""


def clean_title(title):
    """Clean yes24/online bookstore artifacts from title.

    Examples:
        "나라는 착각 | 그레고리 번스 | 흐름출판 - 예스24" → "나라는 착각"
        "[전자책]롤랑 바르트의 인문학" → "롤랑 바르트의 인문학"
        "Do it! LLM을 활용한 AI 에이전트 개발 입문 - 예스24" → "Do it! LLM을 활용한 AI 에이전트 개발 입문"
    """
    if not title:
        return title
    # Remove [전자책] prefix
    title = re.sub(r"^\[전자책\]", "", title)
    # Remove " - 예스24" suffix
    title = re.sub(r"\s*-\s*예스24\s*$", "", title)
    # Remove " | author | publisher - 예스24" pattern (pipe-separated)
    title = re.sub(r"\s*\|.*$", "", title)
    return title.strip()


def generate_citation_key(item_data):
    """Resolve a citation key without network I/O.

    - Existing citationKey on the Zotero item is sacred — keep as-is.
      (Book KDC keys are human-curated in Zotero; this renderer never upgrades.)
    - Missing key → local BBT-style fallback (book-…, web-…, etc.).
    """
    existing = item_data.get("citationKey", "")
    if existing:
        return existing, False

    item_type = item_data.get("itemType", "misc")
    title = item_data.get("title", "")
    date = item_data.get("date", "")
    creators = item_data.get("creators", [])

    # Clean title (yes24 등 온라인 서점 아티팩트 제거)
    title = clean_title(title)

    # BBT-style local fallback (no KDC / no data4library)
    prefix = PREFIX_MAP.get(item_type, "")
    st = shorttitle(title)

    # Author component for non-prefixed types
    author_part = ""
    if not prefix:
        author = get_first_author(creators)
        if author:
            # Use last name or full name for Korean
            if is_korean(author[0]) if author else False:
                author_part = author
            else:
                # Last name only
                parts = author.split(",")
                if len(parts) > 1:
                    author_part = parts[0].strip()
                else:
                    parts = author.split()
                    author_part = parts[-1] if parts else ""

    key = f"{prefix}{author_part}{st}"

    # Year suffix
    if item_type not in NO_YEAR_TYPES:
        sy = shortyear(date)
        if sy:
            key += sy

    # Clean key: remove problematic characters
    key = re.sub(r"[{}\s,\\#%&~]", "", key)

    if not key:
        key = "unknown"

    return key, True


# ---------------------------------------------------------------------------
# BibTeX formatting
# ---------------------------------------------------------------------------

def escape_bibtex(value):
    """Escape only { and } inside BibTeX field values."""
    # Don't escape - values are wrapped in braces by the formatter
    # Only escape unbalanced braces
    return value


def format_creator(creator):
    """Format a single creator for BibTeX author field."""
    name = creator.get("name", "")
    if name:
        # Single-field name (e.g., Korean names, organizations)
        return "{" + name + "}"

    last = creator.get("lastName", "")
    first = creator.get("firstName", "")

    if last and first:
        # Check if Korean
        if is_korean(last[0]) if last else False:
            return "{" + last + first + "}"
        return f"{last}, {first}"
    return last or first or ""


def format_creators(creators, creator_type):
    """Format all creators of a given type into BibTeX field value."""
    matching = [c for c in creators if c.get("creatorType") == creator_type]
    if not matching:
        return ""
    return " and ".join(format_creator(c) for c in matching)


def item_to_bibtex(item_data, citation_key, entry_type):
    """Convert a single Zotero item to a BibTeX entry string."""
    fields = []

    def add(bib_field, value):
        if value:
            fields.append(f"  {bib_field} = {{{value}}}")

    # Title (clean online bookstore artifacts)
    add("title", clean_title(item_data.get("title", "")))

    # Creators
    creators = item_data.get("creators", [])
    author = format_creators(creators, "author")
    if author:
        add("author", author)
    editor = format_creators(creators, "editor")
    if editor:
        add("editor", editor)
    translator = format_creators(creators, "translator")
    if translator:
        add("translator", translator)

    # Date fields — biblatex 호환 형식만 통과, 비표준은 연도만 추출
    date_val = item_data.get("date", "")
    if date_val and not re.match(r"^\d{4}(-\d{2}(-\d{2}(T.+)?)?)?$", date_val):
        m = re.search(r"(?<!\+)(?<!-)\b(\d{4})\b", date_val)
        date_val = m.group(1) if m else ""
    add("date", date_val)
    add("shorttitle", item_data.get("shortTitle", ""))

    # Publisher / location
    add("publisher", item_data.get("publisher", ""))
    add("location", item_data.get("place", ""))
    add("edition", item_data.get("edition", ""))
    add("series", item_data.get("series", ""))
    add("volume", item_data.get("volume", ""))
    add("pagetotal", item_data.get("numPages", ""))

    # Identifiers
    add("isbn", item_data.get("ISBN", ""))
    add("doi", item_data.get("DOI", ""))
    add("url", item_data.get("url", ""))

    # Access date (first 10 chars only)
    access_date = item_data.get("accessDate", "")
    if access_date:
        add("urldate", access_date[:10])

    add("langid", item_data.get("language", ""))
    add("abstract", item_data.get("abstractNote", ""))

    # Tags -> keywords
    tags = item_data.get("tags", [])
    if tags:
        kw = ", ".join(t.get("tag", "") for t in tags if t.get("tag"))
        add("keywords", kw)

    # Extra -> annotation
    add("annotation", item_data.get("extra", ""))

    # Call number
    add("callnumber", item_data.get("callNumber", ""))

    # Original date
    add("origdate", item_data.get("originalDate", "") if "originalDate" in item_data else "")

    # Critical citar fields
    add("datemodified", item_data.get("dateModified", ""))
    add("dateadded", item_data.get("dateAdded", ""))

    # Build entry
    fields_str = ",\n".join(fields)
    return f"@{entry_type}{{{citation_key},\n{fields_str}\n}}"


# ---------------------------------------------------------------------------
# Main processing
# ---------------------------------------------------------------------------

def process_items(items):
    """Process all items and return (book_entries, typed_entries, new_keys).

    typed_entries is a dict mapping file stem (Online, Software, etc.) to entry lists.
    """
    book_entries = []
    typed_entries = {}  # stem -> [entries]
    new_keys = {}
    seen_keys = set()

    for item in items:
        data = item.get("data", {})
        item_type = data.get("itemType", "")

        # Skip attachments and notes
        if item_type in ("attachment", "note"):
            continue

        # Generate citation key (local only — no network)
        citation_key, is_new = generate_citation_key(data)

        # Deduplicate
        original_key = citation_key
        counter = 1
        while citation_key in seen_keys:
            citation_key = f"{original_key}-{counter}"
            counter += 1
        seen_keys.add(citation_key)

        # Track new keys
        if is_new:
            zotero_key = item.get("key", data.get("key", ""))
            if zotero_key:
                new_keys[zotero_key] = citation_key

        # Map entry type
        entry_type = ENTRY_TYPE_MAP.get(item_type, "misc")

        # Generate BibTeX
        entry = item_to_bibtex(data, citation_key, entry_type)

        # Split: books -> Book.bib, others -> by entry type
        if item_type == "book":
            book_entries.append(entry)
        else:
            stem = BIB_FILE_MAP.get(entry_type, DEFAULT_BIB_STEM)
            typed_entries.setdefault(stem, []).append(entry)

    return book_entries, typed_entries, new_keys


def write_bib_file(path, entries, label):
    """Write a BibTeX file only when its bibliography content changed."""
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    header = (
        f"% -*- bibtex -*-\n"
        f"% {label}\n"
        f"%\n"
        f"% Entries:  {len(entries)}\n"
        f"% Updated:  {now}\n"
        f"% Source:   Zotero Cloud API (headless)\n"
        f"%\n"
    )
    content = header + "\n" + "".join(f"{entry}\n\n" for entry in entries)

    os.makedirs(os.path.dirname(path), exist_ok=True)

    if os.path.exists(path):
        with open(path, "r", encoding="utf-8") as f:
            existing = f.read()
        # The generation timestamp is metadata, not a bibliography change.
        # Preserve the existing file (and mtime) when that is the only delta.
        timestamp_line = r"(?m)^% Updated:  .*?$"
        if re.sub(timestamp_line, "", existing, count=1) == re.sub(
            timestamp_line, "", content, count=1
        ):
            print(f"  Unchanged: {path}")
            return

    with open(path, "w", encoding="utf-8") as f:
        f.write(content)

    print(f"  Wrote {len(entries)} entries to {path}")


def main():
    parser = argparse.ArgumentParser(description="Zotero JSON -> BibTeX converter")
    parser.add_argument("--items", required=True, help="Path to items.json")
    parser.add_argument("--book-bib", required=True, help="Output path for Book.bib")
    parser.add_argument("--output-dir", required=True, help="Output directory for type-based .bib files")
    parser.add_argument("--sync-dir", default=".sync", help="Sync directory path")
    # Accepted but ignored: kept so older callers/wrappers do not break.
    parser.add_argument(
        "--data4lib-key",
        default="",
        help=argparse.SUPPRESS,
    )
    args = parser.parse_args()

    # Load items
    with open(args.items, "r", encoding="utf-8") as f:
        items = json.load(f)

    print(f"Processing {len(items)} items...")

    # Process (network-free)
    book_entries, typed_entries, new_keys = process_items(items)

    # Write Book.bib
    write_bib_file(args.book_bib, book_entries, "Zotero Books")

    # Write type-based .bib files
    for stem in sorted(typed_entries):
        entries = typed_entries[stem]
        path = os.path.join(args.output_dir, f"{stem}.bib")
        write_bib_file(path, entries, f"Zotero {stem}")

    # Save new keys mapping
    if new_keys:
        new_keys_path = os.path.join(args.sync_dir, "new-keys.json")
        os.makedirs(args.sync_dir, exist_ok=True)
        with open(new_keys_path, "w", encoding="utf-8") as f:
            json.dump(new_keys, f, ensure_ascii=False, indent=2)
        print(f"  Saved {len(new_keys)} new key mappings to {new_keys_path}")

    print("Done.")


if __name__ == "__main__":
    main()

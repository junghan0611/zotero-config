#!/usr/bin/env python3
"""
gen-bibtex.py - Zotero JSON -> BibTeX 변환 엔진

Converts Zotero API JSON items to citar-compatible BibTeX files.
Splits output into Book.bib and Slipbox.bib.

Usage:
    python3 gen-bibtex.py \
        --items .sync/items.json \
        --book-bib ~/org/resources/Book.bib \
        --slipbox-bib ~/org/resources/Slipbox.bib \
        --data4lib-key API_KEY \
        --sync-dir .sync
"""

import argparse
import json
import os
import re
import sys
import urllib.request
import urllib.error
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

# Korean 초성 table
CHOSUNG = [
    "ㄱ", "ㄲ", "ㄴ", "ㄷ", "ㄸ", "ㄹ", "ㅁ", "ㅂ", "ㅃ",
    "ㅅ", "ㅆ", "ㅇ", "ㅈ", "ㅉ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ",
]

# ---------------------------------------------------------------------------
# Korean helpers
# ---------------------------------------------------------------------------

def get_chosung(char):
    """Extract Korean 초성 from a syllable character."""
    code = ord(char)
    if 0xAC00 <= code <= 0xD7A3:
        return CHOSUNG[(code - 0xAC00) // 588]
    return ""


def is_korean(char):
    """Check if character is Korean (syllable or jamo)."""
    code = ord(char)
    return (0xAC00 <= code <= 0xD7A3) or (0x3131 <= code <= 0x318E)


def cutter_number(char):
    """Derive a 2-digit cutter number from a character (Unicode-based approximation)."""
    code = ord(char)
    if 0xAC00 <= code <= 0xD7A3:
        # Map Korean syllable range to 10-99
        return 10 + ((code - 0xAC00) * 89) // (0xD7A3 - 0xAC00)
    elif char.isalpha():
        # ASCII letters: map a-z to 10-99
        c = char.lower()
        return 10 + (ord(c) - ord("a")) * 89 // 25
    return 50  # fallback


def make_author_code(author_name, title):
    """
    Generate 4-char Korean library author code: 성(1) + 커터번호(2) + 제목초성(1).
    Example: 김74ㄴ
    """
    name = author_name.strip()
    if not name:
        return "unknown"

    surname = name[0]

    # Cutter from second character of name
    if len(name) > 1:
        cn = cutter_number(name[1])
    else:
        cn = 50

    # Title 초성: first Korean character's 초성
    title_cho = ""
    for ch in title:
        cho = get_chosung(ch)
        if cho:
            title_cho = cho
            break

    if not title_cho:
        # Fallback: first letter of title
        for ch in title:
            if ch.isalpha():
                title_cho = ch.lower()
                break
        if not title_cho:
            title_cho = "x"

    return f"{surname}{cn}{title_cho}"


# ---------------------------------------------------------------------------
# Citation key helpers
# ---------------------------------------------------------------------------

def normalize_isbn(isbn_field):
    """Extract first ISBN and remove hyphens."""
    if not isbn_field:
        return ""
    # Take first ISBN (space-separated)
    first = isbn_field.strip().split()[0]
    return first.replace("-", "")


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


def lookup_kdc(isbn, api_key):
    """Look up KDC classification from DATA4LIBRARY API."""
    if not isbn or not api_key:
        return ""

    url = (
        f"https://data4library.kr/api/srchDtlList"
        f"?authKey={api_key}&isbn13={isbn}&format=json"
    )

    try:
        req = urllib.request.Request(url, headers={"User-Agent": "zotero-to-bib/1.0"})
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            # Navigate the response structure
            detail = data.get("response", {}).get("detail", [])
            if detail:
                book_info = detail[0].get("book", {})
                class_no = book_info.get("class_no", "")
                if class_no:
                    return class_no.strip()
    except Exception:
        pass

    return ""


def generate_citation_key(item_data, api_key=""):
    """Generate a citation key for an item following BBT rules."""
    # If citationKey already set, use it
    existing = item_data.get("citationKey", "")
    if existing:
        return existing, False  # (key, is_new)

    item_type = item_data.get("itemType", "misc")
    title = item_data.get("title", "")
    date = item_data.get("date", "")
    creators = item_data.get("creators", [])
    isbn = normalize_isbn(item_data.get("ISBN", ""))

    # Book with ISBN -> try KDC
    if item_type == "book" and isbn:
        kdc = lookup_kdc(isbn, api_key)
        if kdc:
            author = get_first_author(creators)
            author_code = make_author_code(author, title)
            return f"{kdc}-{author_code}", True

    # BBT-style key
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

    # Title
    add("title", item_data.get("title", ""))

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

    # Date fields
    add("date", item_data.get("date", ""))
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

def process_items(items, api_key=""):
    """Process all items and return (book_entries, slipbox_entries, new_keys)."""
    book_entries = []
    slipbox_entries = []
    new_keys = {}
    seen_keys = set()

    for item in items:
        data = item.get("data", {})
        item_type = data.get("itemType", "")

        # Skip attachments and notes
        if item_type in ("attachment", "note"):
            continue

        # Generate citation key
        citation_key, is_new = generate_citation_key(data, api_key)

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

        # Split: books -> Book.bib, everything else -> Slipbox.bib
        if item_type == "book":
            book_entries.append(entry)
        else:
            slipbox_entries.append(entry)

    return book_entries, slipbox_entries, new_keys


def write_bib_file(path, entries, label):
    """Write a BibTeX file with header."""
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

    os.makedirs(os.path.dirname(path), exist_ok=True)

    with open(path, "w", encoding="utf-8") as f:
        f.write(header)
        f.write("\n")
        for entry in entries:
            f.write(entry)
            f.write("\n\n")

    print(f"  Wrote {len(entries)} entries to {path}")


def main():
    parser = argparse.ArgumentParser(description="Zotero JSON -> BibTeX converter")
    parser.add_argument("--items", required=True, help="Path to items.json")
    parser.add_argument("--book-bib", required=True, help="Output path for Book.bib")
    parser.add_argument("--slipbox-bib", required=True, help="Output path for Slipbox.bib")
    parser.add_argument("--data4lib-key", default="", help="DATA4LIBRARY API key")
    parser.add_argument("--sync-dir", default=".sync", help="Sync directory path")
    args = parser.parse_args()

    # Load items
    with open(args.items, "r", encoding="utf-8") as f:
        items = json.load(f)

    print(f"Processing {len(items)} items...")

    # Process
    book_entries, slipbox_entries, new_keys = process_items(items, args.data4lib_key)

    # Write BibTeX files
    write_bib_file(args.book_bib, book_entries, "Zotero Books")
    write_bib_file(args.slipbox_bib, slipbox_entries, "Zotero Slipbox")

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

---
name: bibcli
description: Search and view 8,000+ BibTeX entries from personal bibliography. Use when user mentions papers, books, citations, references, or asks to find/show bibliographic entries.
---

# bibcli - BibTeX Search CLI

Search and view bibliographic entries from the user's personal library (8,000+ entries across 8 BibTeX files).

## Prerequisites

Binary must be in PATH. Build from source:

```bash
# Clone (if not already)
git clone https://github.com/junghan0611/zotero-config.git
cd zotero-config

# Build + install to ~/.local/bin
./run.sh build
```

Requires Go 1.21+. No external dependencies (stdlib only).

Set `BIBCLI_DIR` environment variable to the bib directory (already configured in `.envrc`).

## Commands

### Search entries

```bash
bibcli search "emacs org-mode" --max 10
bibcli search "knowledge graph" --type Book
bibcli search "한국" --type Book --max 5
```

- Multiple words = AND condition (all must match)
- Searches: title, author, keywords, citationKey, date, abstract
- Case-insensitive (Korean included)

### Show single entry (full details)

```bash
bibcli show "165.84-박82ㅅ"
bibcli show "web-MermaidAscii터미널에서"
```

Returns all fields including abstract, url, isbn, keywords.

### List entries by type

```bash
bibcli list --type Book --max 10
bibcli list --type Online --max 20
bibcli list --type Software --max 5
```

### Statistics

```bash
bibcli stats
```

## Flags

| Flag | Description | Default |
|------|-------------|---------|
| `--dir DIR` | Bib files directory | `$BIBCLI_DIR` |
| `--type TYPE` | Filter by type: `Book`, `Online`, `Software`, `Reference`, `Video`, `Article`, `Misc` | all |
| `--max N` | Max results | search: 20, list: 50 |

## Output

All output is JSON. Examples:

**search/list** returns brief entries:
```json
[{"key": "book-pkm2024", "type": "book", "title": "...", "author": "...", "date": "2024", "file": "Book.bib"}]
```

**show** returns full entry with all fields:
```json
{"key": "...", "type": "book", "title": "...", "author": "...", "isbn": "...", "abstract": "...", "file": "Book.bib"}
```

**stats** returns counts:
```json
{"total": 8030, "files": {"Book.bib": 1463, "Online.bib": 2610, ...}}
```

## BibTeX File Types

| File | Content | Count |
|------|---------|-------|
| Book.bib | Books (KDC citation keys for Korean) | ~1,463 |
| Online.bib | Webpages, blog posts, forum posts | ~2,610 |
| Software.bib | Software projects | ~1,082 |
| github-starred.bib | GitHub starred repos | ~2,140 |
| Reference.bib | Encyclopedias, dictionaries | ~365 |
| Video.bib | Videos, films, broadcasts | ~239 |
| Article.bib | Journal articles | ~69 |
| Misc.bib | Everything else | ~62 |

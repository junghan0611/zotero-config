---
name: bibcli
description: Search and view 8,000+ BibTeX entries from personal bibliography. Use when user mentions papers, books, citations, references, or asks to find/show bibliographic entries.
---

# bibcli - BibTeX Search CLI

Search and view bibliographic entries from the user's personal library (8,000+ entries across 8 BibTeX files).

## Prerequisites

Binary is bundled in the skill directory. Invoke via `{baseDir}/bibcli`.
Use `--dir` flag to specify bib files location.

## Environment Paths

Bib files location differs by environment. Use `--dir` accordingly:

| Environment | Bib Path | Example |
|-------------|----------|---------|
| **Local** (Claude Code) | `~/sync/emacs/zotero-config/output` | `bibcli search "query"` (uses `$BIBCLI_DIR`) |
| **Local** (alt) | `~/org/resources` | `bibcli search "query" --dir ~/org/resources` |
| **Container** (OpenClaw) | `~/org/resources` | `{baseDir}/bibcli search "query" --dir ~/org/resources` |

## Commands

### Search entries

```bash
{baseDir}/bibcli search "emacs org-mode" --dir ~/org/resources --max 10
{baseDir}/bibcli search "knowledge graph" --dir ~/org/resources --type Book
{baseDir}/bibcli search "한국" --dir ~/org/resources --type Book --max 5
```

- Multiple words = AND condition (all must match)
- Searches: title, author, keywords, citationKey, date, abstract
- Case-insensitive (Korean included)

### Show single entry (full details)

```bash
{baseDir}/bibcli show "165.84-박82ㅅ" --dir ~/org/resources
{baseDir}/bibcli show "web-MermaidAscii터미널에서" --dir ~/org/resources
```

Returns all fields including abstract, url, isbn, keywords.

### List entries by type

```bash
{baseDir}/bibcli list --dir ~/org/resources --type Book --max 10
{baseDir}/bibcli list --dir ~/org/resources --type Online --max 20
{baseDir}/bibcli list --dir ~/org/resources --type Software --max 5
```

### Statistics

```bash
{baseDir}/bibcli stats --dir ~/org/resources
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

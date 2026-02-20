# bibcli - BibTeX CLI for AI Agents

## Overview

Go CLI that reads output/*.bib files and provides search/view capabilities.
Designed for AI agent consumption (JSON-only output, stateless invocations).

## Commands

```
bibcli search <query> [--type Book|Online|...] [--max 20]
bibcli show <citation-key>
bibcli list [--type Book|Online|...] [--max 50]
bibcli stats
```

| Command | Description | Output |
|---------|-------------|--------|
| search | Full-text search across title/author/keywords/key | JSON array of matching entries |
| show | Get single entry by citationKey | JSON object with all fields |
| list | List entries by type or all | JSON array (brief format) |
| stats | Per-file/per-type statistics | JSON stats object |

### search behavior

- Case-insensitive
- Searches: title, author, keywords, citationKey fields
- Multiple words = AND condition
- `--type` filters to specific bib file
- `--max` limits results (default 20)

## Architecture

```
zotero-config/bibcli/
├── main.go         # CLI entry + subcommand routing
├── parser.go       # BibTeX parser (regex-based)
├── search.go       # Search logic (case-insensitive, multi-field AND)
└── go.mod          # stdlib only, no external dependencies
```

### Data flow

```
output/*.bib → parser.go (regex) → []Entry → search/filter → JSON output
```

### BibTeX parser

gen-bibtex.py output format is consistent:

```bibtex
@type{key,
  field1 = {value1},
  field2 = {value2}
}
```

Parser:
1. `@(\w+)\{([^,]+),` → type + key
2. `(\w+)\s*=\s*\{...\}` → field + value (handle nested braces)
3. Store as `map[string]string`

### Performance target

- 8,000 entries from ~4MB of .bib files
- Parse + search < 100ms
- No caching needed (fast enough cold)

## JSON Output Format

### search / list (brief)

```json
[
  {
    "key": "book-pkm2024",
    "type": "book",
    "title": "PKM Systems",
    "author": "Kim, Jung Han",
    "date": "2024",
    "file": "Book.bib"
  }
]
```

### show (full)

```json
{
  "key": "802.041-김74ㄴ",
  "type": "book",
  "title": "나의 한국현대사",
  "author": "{유시민}",
  "date": "2014",
  "publisher": "돌베개",
  "isbn": "9788971998304",
  "keywords": "한국현대사",
  "dateadded": "2025-05-06T22:33:39Z",
  "file": "Book.bib"
}
```

### stats

```json
{
  "total": 8030,
  "files": {
    "Book.bib": 1463,
    "Online.bib": 2610,
    "github-starred.bib": 2140
  }
}
```

## Constraints

- Go stdlib only (no external dependencies)
- JSON-only output (no text mode)
- Read-only (no write operations)
- Bib files located relative to binary or via `--dir` flag
- NixOS-friendly (single static binary)

## Future

- Claude Code skill integration (`/bib search`, `/bib show`)
- Org-mode note cross-reference (find org files citing a key)

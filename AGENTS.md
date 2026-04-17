# Agent Instructions

This project uses **br** (beads_rust) for issue tracking. Use `br ready`, `br list`, or `br info` to inspect the workspace and find work. (`br onboard` is not available in the current br build.)

**Note:** `br` is non-invasive and never executes git commands. After `br sync --flush-only`, you must manually run `git add .beads/ && git commit`.

## Project Overview

Headless bibliographic workflow: Zotero Cloud API → citar-compatible BibTeX.
No Zotero GUI, no Better BibTeX plugin.

### Key Scripts

| Script | Purpose |
|--------|---------|
| `run.sh` | Main entry point (`bib`, `starred`, `save`, `server`, `build`) |
| `scripts/zotero-to-bib.sh` | Zotero API fetcher (pagination, incremental sync, merge) |
| `scripts/gen-bibtex.py` | BibTeX engine (citation key generation, KDC lookup, type-based splitting) |
| `scripts/writeback-keys.sh` | citationKey writeback to Zotero Cloud (PATCH) |
| `scripts/gh-starred-to-bib.sh` | GitHub starred repos → BibTeX (gh + jq) |
| `scripts/run.sh` | Translation Server lifecycle management |
| `scripts/zotero-save-url.sh` | URL saver via Translation Server |
| `bibcli/` | BibTeX search CLI for AI agents (Go, JSON output) |

### Output Files (in `output/`)

Type-based BibTeX files, symlinked from `~/org/resources/`:

- `Book.bib` — itemType=book (KDC citation keys for Korean books)
- `Online.bib` — webpage, blogPost, forumPost
- `Software.bib` — computerProgram
- `Reference.bib` — encyclopediaArticle, dictionaryEntry
- `Video.bib` — videoRecording, film, tvBroadcast
- `Article.bib` — journalArticle
- `Misc.bib` — everything else
- `github-starred.bib` — GitHub starred repos

### Environment Variables (`.envrc`)

- `ZOTERO_API_KEY` — Zotero Web API key
- `ZOTERO_USER_ID` — Zotero user ID
- `DATA4LIBRARY_API_KEY` — Korean library API for ISBN→KDC lookup

### State Files (`.sync/`, gitignored)

- `items.json` — Cached Zotero items (full library)
- `last-version` — API version number for incremental sync
- `new-keys.json` — Pending citationKey writebacks (renamed to `.done` after completion)

## Quick Reference

```bash
br create --title "book 메타정보 자동" --description "## 현황..."
br ready              # Find available work
br show <id>          # View issue details
br update <id> --status in_progress  # Claim work
br close <id>         # Complete work
br sync --flush-only  # Export to JSONL
```

## Agent Workflow

### Translation Server + Zotero save

```bash
./run.sh server start
./run.sh save "https://example.com"
./run.sh bib sync
```

Notes:
- Translation Server default endpoint: `http://localhost:1969`
- `save` writes to Zotero Web Library through the translation server
- `bib sync` refreshes `output/*.bib` and copies them to `~/org/resources/`
- after sync, use `bibcli` (local binary or pi skill) to search/show the new citation key

### Bibliography integration rule

When an agent creates or enriches a `bib/` note, do not leave `#+print_bibliography:` orphaned if a Zotero-backed source can be added with one extra step.
Preferred flow:
1. save URL to Zotero
2. sync bib files
3. search/show citation key with `bibcli`
4. insert `#+reference:` into the note

## Delegates / coding agents

- Do not auto-push or auto-commit unless the user explicitly asked for it
- Prepare changes, tests, and handoff notes; GLG decides the final commit/push
- `br` is optional support for issue tracking, not a mandatory landing workflow for every task

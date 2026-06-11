# Agent Instructions

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
./run.sh bib sync       # Incremental sync (Zotero Cloud → output/*.bib → ~/org/resources/)
./run.sh bib full       # Full rebuild (also drops items deleted on Zotero Cloud)
./run.sh bib status     # Sync state
./run.sh server start   # Translation Server (localhost:1969)
./run.sh save --sync --json <url>   # Save URL → sync → return resolved citation key
./run.sh build          # Build bibcli
```

## Agent Workflow

### Save a URL and get its citation key (preferred — one shot)

```bash
./run.sh server status || ./run.sh server start
./run.sh save --sync --json "https://example.com/article"
# => { saved:[...], resolved:[{zoteroKey, citationKey, title, ...}] }
```

`--sync` runs `bib sync` after saving; `--json` returns the resolved
`citationKey` **deterministically** — no need to grep the bib by title.
Take the `citationKey` from `resolved[]` and drop it straight into the note's
`#+reference:`.

If you only need an *existing* key (no new save), search the local bib with the
`bibcli` skill instead — see `~/.claude/skills/bibcli/SKILL.md`.

### Fallback (when `--sync --json` is unavailable)

```bash
./run.sh save "https://example.com/article"   # writes to Zotero Cloud
./run.sh bib sync                              # refresh output/*.bib + ~/org/resources/
# then recover the key by distinctive title/author words:
bibcli search "distinctive title author words" --dir ~/org/resources --max 5
```

### Bibliography integration rule

When an agent creates or enriches a `bib/` note, do not leave
`#+print_bibliography:` orphaned if a Zotero-backed source can be added with one
extra step. Preferred flow: `save --sync --json` → take `resolved[].citationKey`
→ insert `#+reference:` into the note.

## Delegates / coding agents

- Do not auto-push or auto-commit unless the user explicitly asked for it
- Prepare changes, tests, and handoff notes; GLG decides the final commit/push

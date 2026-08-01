# Agent Instructions

## Project Overview

Headless bibliographic workflow: Zotero Cloud API → citar-compatible BibTeX.
No Zotero GUI, no Better BibTeX plugin, no MCP.

**Operator skill (doctrine + reflexes):**
`.claude/skills/zotero-config/SKILL.md` — read when capturing, syncing, or
touching mutation boundaries. Global search CLI skill: `bibcli` in agent-config.

### Doctrine — capture vault vs meta-bib SSOT

```text
Zotero Cloud  = capture vault (phone / browser Connector / save URL)
local *.bib   = meta bibliography SSOT (output/ → ~/org/resources/)
bibcli        = the only hand that reads the SSOT for agents
```

- What is not yet in local `*.bib` is not yet bibliography SSOT — even if it
  sits in Zotero Cloud. After phone/browser capture, run `./run.sh bib sync`
  **without waiting to be asked**, then `bibcli search`.
- **Books** are carefully curated (KDC, author/translator, stable citation
  keys). Do not bulk-automate or casually writeback. `lookup`/data4library is
  assistive correction, not a full autopilot.
- **Online / Video / web** are the convenient inflow — capture freely, pull
  with sync. Do not expand the boundary to YouTube starred lists or other
  scrapers; only what entered Zotero is eligible for the SSOT.
- Code stays thin; operational detail lives in the skills.

### Mental model — three access scenarios

> Zotero Cloud is the treasure vault, the Translation Server is a translator you
> only switch on to save a URL, and `bibcli` is the local search hand you use
> straight from org.

| # | Need | Command | Server / Cloud |
|---|------|---------|----------------|
| 1 | Cite a source **already in Zotero** | `bibcli search "…" --dir ~/org/resources` → `bibcli show "key"` | **None** — reads local `~/org/resources/*.bib` only; no GUI, no server, no API |
| 2 | Save a **new URL** and cite it now | `./run.sh server status \|\| ./run.sh server start` → `./run.sh save --sync --json <url>` | Translation Server extracts metadata → Zotero Cloud → `bib sync` (read-only) → returns `resolved[].citationKey` from the generated key |
| 3 | Refresh local bib from Cloud | `./run.sh bib sync` | Downloads Zotero Cloud → `.sync/items.json` → `output/*.bib` → `~/org/resources/`. **Read-only — never writes to Zotero Cloud.** |

`bib sync` / `bib full` are **read-only** with respect to Zotero Cloud: they pull
the vault down and regenerate the citar/export BibTeX. The citation key is
deterministic and lives in `output/*.bib` (the source of truth for citar) plus
`.sync/new-keys.json`; no PATCH-back happens during a sync. For both scenario 2
and 3 the note gets `#+reference: <key>` + `#+print_bibliography:`.

**Consistency rule — never hand-edit `.bib`.** Every entry (yours from the
browser Zotero Connector, an agent's from the Translation Server) enters as a
**Zotero Cloud item** and is rendered by the single renderer `gen-bibtex.py`, so
format is identical regardless of origin. Translation Server uses the same
translators as the browser Connector — prefer it for URLs. `.bib` files are
outputs; a hand-edit is clobbered on the next `bib full`.

**Pinning keys to Cloud is now explicit and opt-in.** `./run.sh bib writeback`
PATCHes generated citation keys onto their Zotero items — run it deliberately
(e.g. after curating book KDC keys), never as a side effect of a routine pull.
Books are still curated by hand in Zotero; sync only reads them.

**External-capture reflex:** if GLG saved from phone/browser and asks to find
or cite it, `./run.sh bib sync` first — do not require a separate "please sync"
instruction. `bib sync` is read-only against Cloud.

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
./run.sh bib sync       # Incremental sync (Zotero Cloud → output/*.bib → ~/org/resources/) — read-only
./run.sh bib full       # Full rebuild (also drops items deleted on Zotero Cloud) — read-only
./run.sh bib writeback  # Explicit: pin generated citation keys onto Zotero Cloud (mutates)
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

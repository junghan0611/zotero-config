# Agent Instructions

## Project Overview

Headless bibliographic workflow: Zotero Cloud API → citar-compatible BibTeX.
No Zotero GUI, no Better BibTeX plugin, no MCP.

**Operator skill (doctrine + book ritual + reflexes):**
`.claude/skills/zotero-config/SKILL.md` — read when capturing, syncing, touching
books/KDC, or any mutation boundary. Global search CLI skill: `bibcli` in
agent-config.

**Public steward face (botlog 담당자 문서):**
`denote:20260304T105300` — `§zotero-config: 캡처 금고와 메타 서지의 얇은 손`
(`~/org/botlog/20260304T105300--….org`). After meaningful posture/boundary changes,
update that room (히스토리 + 현재 보고) — do **not** mint a new botlog/llmlog.
Session handoff stays in `NEXT.md`.

### Doctrine — capture vault vs meta-bib SSOT

```text
Zotero Cloud  = capture vault (phone / browser Connector / save URL)
local *.bib   = meta bibliography SSOT (output/ → ~/org/resources/)
bibcli        = the only hand that reads the SSOT for agents
```

- What is not yet in local `*.bib` is not yet bibliography SSOT — even if it
  sits in Zotero Cloud. After phone/browser capture, run `./run.sh bib sync`
  **without waiting to be asked**, then `bibcli search`.
- **Books** are a human ritual (yes24 → Connector → hand-edit title/author/
  translator/date/shorttitle/abstract → approximate KDC key via library OPAC
  sense, e.g. Suwon lib). Do not bulk-automate or casually writeback.
  `bibcli lookup`/data4library is **candidate assist only**. Sync never calls it.
- **`dateAdded` / `dateModified` are sacred.** They record when 힣 met a theme,
  not just bibliographic facts. Never risk them with bulk enrich/PATCH.
- **Online / Video / web** are the convenient inflow — capture freely, pull
  with sync. Do not expand the boundary to YouTube starred lists or other
  scrapers; only what entered Zotero is eligible for the SSOT.
- **Repo identity:** publishing the *process* of tending a bibliography, not
  recommending individual books. Code stays thin; ritual detail lives in the
  skill.

### Mental model — three access scenarios

> Zotero Cloud is the treasure vault, the Translation Server is a translator you
> only switch on to save a URL, and `bibcli` is the local search hand you use
> straight from org.

| # | Need | Command | Server / Cloud |
|---|------|---------|----------------|
| 1 | Cite a source **already in Zotero** | `bibcli search "…" --dir ~/org/resources` → `bibcli show "key"` | **None** — reads local `~/org/resources/*.bib` only; no GUI, no server, no API |
| 2 | Save a **new URL** and cite it now | `./run.sh server status \|\| ./run.sh server start` → `./run.sh save --sync --json <url>` | Translation Server extracts metadata → Zotero Cloud → `bib sync` (read-only) → returns `resolved[].citationKey` from the generated key |
| 3 | Refresh local bib from Cloud | `./run.sh bib sync` | Downloads Zotero Cloud → `.sync/items.json` → `output/*.bib` → `~/org/resources/`. **Read-only — never writes to Zotero Cloud.** Render is network-free. |

`bib sync` / `bib full` are **read-only** with respect to Zotero Cloud: they pull
the vault down and regenerate the citar/export BibTeX. Existing `citationKey`
values are kept as-is; missing keys get a local BBT-style fallback only.
No data4library/KDC on this path. No PATCH-back during sync.

For both scenario 2 and 3 the note gets `#+reference: <key>` +
`#+print_bibliography:`.

**Consistency rule — never hand-edit `.bib`.** Every entry (yours from the
browser Zotero Connector, an agent's from the Translation Server) enters as a
**Zotero Cloud item** and is rendered by the single renderer `gen-bibtex.py`, so
format is identical regardless of origin. Translation Server uses the same
translators as the browser Connector — prefer it for URLs. `.bib` files are
outputs; a hand-edit is clobbered on the next `bib full`.

**Pinning keys to Cloud is explicit and opt-in.** `./run.sh bib writeback`
PATCHes generated citation keys onto their Zotero items — run it deliberately
(e.g. after curating book KDC keys in Zotero), never as a side effect of a
routine pull. Books are curated by hand in Zotero; sync only reads them.

**External-capture reflex:** if GLG saved from phone/browser and asks to find
or cite it, `./run.sh bib sync` first — do not require a separate "please sync"
instruction. `bib sync` is read-only against Cloud.

### Key Scripts

| Script | Purpose |
|--------|---------|
| `run.sh` | Main entry point (`bib`, `starred`, `save`, `pin`, `server`, `build`, `enrich`) |
| `scripts/zotero-to-bib.sh` | Zotero API fetcher (pagination, incremental sync, merge) |
| `scripts/gen-bibtex.py` | Network-free BibTeX renderer (keep keys / local fallback / type split) |
| `scripts/pin-item.py` | Agent-styled fields + citationKey whitelist PATCH; optional `--sync` |
| `scripts/writeback-keys.sh` | Batch citationKey writeback (legacy; prefer `pin` for singles) |
| `scripts/enrich-books.py` | Opt-in `book-` enrich via data4library — **danger zone**, explicit only |
| `scripts/gh-starred-to-bib.sh` | GitHub starred repos → BibTeX (gh + jq) |
| `scripts/run.sh` | Translation Server lifecycle management |
| `scripts/zotero-save-url.sh` | URL saver via Translation Server |
| `bibcli/` | BibTeX search CLI + `lookup` assist (Go, JSON output) |

### Output Files (in `output/`)

Type-based BibTeX files, symlinked from `~/org/resources/`:

- `Book.bib` — itemType=book (human KDC-style keys when curated)
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
- `DATA4LIBRARY_API_KEY` — optional; **only** for `bibcli lookup` / `./run.sh enrich`
  (not required for `bib sync`)

### State Files (`.sync/`, gitignored)

- `items.json` — Cached Zotero items (full library)
- `last-version` — API version number for incremental sync
- `new-keys.json` — Pending citationKey writebacks (renamed to `.done` after completion)

## Quick Reference

```bash
./run.sh bib sync       # Incremental sync — read-only, network-free render
./run.sh bib full       # Full rebuild — read-only
./run.sh bib status
./run.sh server start
./run.sh save --json <url>          # Capture raw item → zoteroKey
./run.sh pin --sync --json '{...}'  # Style + unique citationKey + sync (org one-shot)
./run.sh save --sync --json <url>   # Web/video when fallback key is enough
./run.sh build
bibcli lookup <isbn|title>          # optional assist only
```

**Org agents:** URL in hand → finish key in the **same session** (`save` → style/KDC
judgment → `pin --sync`). Do not report “not in bibliography” and stop. See
bibcli skill §2 and this repo skill §1b.

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

### Books

Read skill §1b. Agent **judges** style + approximate KDC key (unique in SSOT),
then `./run.sh pin --sync`. `lookup` is optional. Never leave `book-…` as the
final key when citing from org. Never run `enrich` unless explicitly asked.
Never touch `dateAdded`.

## Steward botlog hygiene

| When | Where |
|------|--------|
| Doctrine / pin / collection / skill boundary shifted | Update `20260304T105300` (히스토리 line + short 현재 보고 if needed) |
| Next concrete step only | `NEXT.md` |
| Routine bib refresh | no steward note |

Never create a second `§zotero-config` botlog. Prefer empty-room reopen only if
this ID were retired (it is the living face).

## Delegates / coding agents

- Do not auto-push or auto-commit unless the user explicitly asked for it
- Prepare changes, tests, and handoff notes; GLG decides the final commit/push

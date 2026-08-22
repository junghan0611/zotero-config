# zotero-config

**Headless bibliographic workflow: Zotero Cloud API to citar-compatible BibTeX**

> No Zotero GUI. No Better BibTeX plugin. Just API, scripts, and Emacs.

> **AI Agent Skills**: repo operator doctrine is `.claude/skills/zotero-config/SKILL.md`
> (capture vault vs local bib SSOT, **book ritual**, sacred `dateAdded`, sync reflex).
> Global search CLI skill + binary: `agent-config/skills/bibcli` (built from `bibcli/` here).
> Public steward botlog: Denote ID **`20260304T105300`** (`§zotero-config`) — update that room when posture changes; no extra llmlog.

[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

---

## What This Does

Fetches your entire Zotero library via Cloud API and generates citar-compatible BibTeX files split by type. Local `*.bib` in `~/sync/org/resources/bib` is the meta-bibliography SSOT; Zotero Cloud is the capture vault. The renderer writes that directory directly and Syncthing carries it between devices, so registering a source never involves a git pull or push — and any device can do it. Citation-key writeback to Cloud is explicit and opt-in (`./run.sh bib writeback`), not part of routine sync.

This public repo is not a book-recommendation list. It publishes a **personal bibliography and the process of tending it** — capture, hand curation, approximate classification, and a thin render path others can study without needing to copy.

```
./run.sh bib full       # Full sync: ~6,000 items → 7 BibTeX files in the live bib dir
./run.sh bib sync       # Incremental sync (delta only, seconds; network-free render)
./run.sh bib status     # Show sync state
./run.sh starred        # GitHub starred repos → github-starred.bib
                         # default account: junghan0611
./run.sh save <url>     # Save URL → Translation Server → Zotero Cloud
./run.sh save --sync --json <url>  # Save → bib sync → citation key recovery
./run.sh server start   # Start Translation Server (localhost:1969)
./run.sh build          # Build bibcli (search CLI for AI agents)
```

---

## Pipeline

```
run.sh bib full|sync
│
├── 1. Fetch items from Zotero Cloud API (JSON, paginated)
│   └── /users/{id}/items/top?format=json&limit=100
│
├── 2. Render BibTeX (gen-bibtex.py) — network-free
│   ├── Existing citationKey → keep as-is  (book KDC keys are human-set)
│   └── Missing key → local BBT-style fallback only
│       └── e.g. "book-…", "web-perplexity", "blog-AiVampire26"
│
├── 3. Redact (sanitize_bib.py), then sort by (citationKey, Zotero item key)
│   ├── redaction runs BEFORE the sort — it can rewrite a key, so sorting
│   │   first and redacting after leaves inversions in the published bytes
│   └── cache array order / last-version / clock never affect the bytes
│
├── 4. Write type-based BibTeX files into $ZOTERO_BIB_DIR
│   │   (default ~/sync/org/resources/bib)
│   │   staged, byte-compared, then installed by a same-filesystem rename;
│   │   an unchanged file is left untouched (no generation timestamp exists,
│   │   so equality is plain byte equality)
│   ├── Book.bib
│   ├── Online.bib    ← webpage, blogPost, forumPost
│   ├── Software.bib  ← computerProgram
│   ├── Reference.bib ← encyclopediaArticle, dictionaryEntry
│   ├── Video.bib     ← videoRecording, film, tvBroadcast
│   ├── Article.bib   ← journalArticle
│   └── Misc.bib      ← everything else
│
└── 5. Commit device-local state — cache first, cursor last
    ├── .sync/items.json written temp + atomic rename
    ├── .sync/last-version only after the cache is safely in place, so an
    │   interrupted sync can never skip pages on the next run
    ├── .sync/ is that device's private cache: neither Git-tracked nor shared
    └── writeback is NOT part of sync — explicit: ./run.sh bib writeback

run.sh starred
│
└── GitHub starred repos → github-starred.bib
    ├── redaction rules come from sanitize_bib.py and are applied to the key
    │   BEFORE sorting, so the published order is final
    ├── entries sorted by key, no generation timestamp (deterministic)
    ├── staged in the bib dir, byte-compared, installed by rename — an
    │   unchanged render leaves the file and its mtime alone
    ├── default account: junghan0611
    ├── if active gh account differs: gh auth switch --user <account>
    └── gh api --paginate user/starred → jq → @software{} entries
```

**KDC / data4library is off the sync path.** Book classification is a human ritual (library OPAC sense + hand-entered citation key in Zotero). Assistive candidates: `bibcli lookup`. Optional danger zone: `./run.sh enrich` (explicit only).

---

## Citation Key Patterns

| Type | Example | Who sets it |
|------|---------|-------------|
| book (curated) | `843.5-조68ㅍ2`, `802.041-김74ㄴ` | Human in Zotero (KDC-sense + author code) |
| book (fallback) | `book-SomeTitle26` | Local render if key still missing |
| webpage | `web-perplexity` | Local / existing |
| blogPost | `blog-AiVampire26` | Local / existing |
| software | `200okchorganice24` | Local / existing |

---

## Book ritual (summary)

Full doctrine: `.claude/skills/zotero-config/SKILL.md` §1b.

1. Find a book (often yes24) → Firefox Zotero Connector → Cloud vault  
2. Hand-edit in Zotero: title, author, translator, date, shorttitle, abstract  
3. Set citation key with approximate decimal-class sense (e.g. Suwon library OPAC)  
4. `./run.sh bib sync` → local `Book.bib`  
5. Never bulk-automate; never risk `dateAdded` / `dateModified` — they record *when the theme was met*

---

## Directory Structure

```
zotero-config/
├── run.sh                 # Main entry point
├── scripts/
│   ├── zotero-to-bib.sh   # Zotero API fetcher (bash + curl + jq)
│   ├── gen-bibtex.py       # Network-free BibTeX renderer
│   ├── writeback-keys.sh   # citationKey → Zotero Cloud (PATCH, explicit)
│   ├── enrich-books.py     # Opt-in book- enrich (danger zone)
│   ├── gh-starred-to-bib.sh # GitHub starred → BibTeX (gh + jq)
│   ├── run.sh              # Translation Server manager
│   ├── zotero-save-url.sh  # URL saver via Translation Server
│   ├── sanitize_bib.py     # Redaction rules SSOT (Python + --jq-filter export)
│   ├── gh-starred.jq       # Starred render program (rules injected before sort)
│   └── lib-install.sh      # Shared staging install (byte compare → rename)
├── bibcli/                 # BibTeX search CLI for AI agents (Go)
│   ├── main.go             # CLI: search/show/list/lookup/stats
│   ├── parser.go           # BibTeX parser
│   ├── search.go           # Case-insensitive multi-field AND search
│   └── lookup.go           # data4library assist (ISBN/제목) — not used by sync
├── .claude/skills/zotero-config/SKILL.md  # Operator doctrine
├── tests/                  # Determinism / path checks (no network, no Cloud)
├── config/                 # BBT preferences (reference only)
├── plugins/                # Zotero plugin XPIs (archive)
└── .sync/                  # Sync state (gitignored)
    ├── items.json
    ├── last-version
    └── new-keys.json       # Pending citationKey writebacks
```

---

## Setup

### Requirements

- `curl`, `jq`, `python3` (no pip packages needed)
- Zotero account with API access
- (Optional) [DATA4LIBRARY API key](https://data4library.kr/) — only for `bibcli lookup` / `enrich`

### Environment

Create `.envrc` in the project root:

```bash
export ZOTERO_API_KEY="your-key"
export ZOTERO_USER_ID="your-user-id"
export DATA4LIBRARY_API_KEY="your-key"  # optional; lookup/enrich only — not needed for bib sync
export GH_STARRED_ACCOUNT="junghan0611" # optional override for ./run.sh starred
```

### First Run

```bash
git clone https://github.com/junghan0611/zotero-config.git
cd zotero-config
# Create .envrc with your API keys
./run.sh bib full    # Full sync for ~6000 items → the live bib dir
```

### Determinism

Same library in, **byte-identical** files out — on any device, on any rerun.
The render depends only on the *set* of Zotero items: not on the order they sit
in the device-local `.sync/items.json`, not on `last-version`, not on the clock.
Entries are sorted by `(citationKey, Zotero item key)` before dedup suffixes are
assigned, redaction runs before that sort, and **no generation timestamp is
emitted** — there is no `% Updated:` header, so comparison is plain byte
equality. Zotero's `dateAdded` / `dateModified` survive as BibTeX fields; they
are content, not render metadata.

```bash
./tests/render-determinism.sh             # fixture-based contract test
./tests/render-determinism-live-cache.sh  # same contract on this device's real cache
./tests/bib-dir-and-install.sh            # path resolution + staged install
./tests/sync-cursor.sh                    # cursor safety (mock curl, no network)
./tests/sync-lock.sh                      # single-writer lock under concurrency
./tests/starred-determinism.sh            # starred ordering (synthetic, no GitHub)
```

They render only into `mktemp` directories — never into the live bib dir, and
never calling the Zotero API.

### Where the BibTeX lands

The renderer writes **directly into `~/sync/org/resources/bib/`** — no copy
step, no symlink, and no Git. That directory is shared by Syncthing, so a source
registered on one device is citable on every device without a pull or a push.
Every device is symmetric: Zotero Cloud is the capture authority, each device
keeps its own private `.sync/` cache, and only the bib directory is shared.

```bash
./run.sh bib sync    # → ~/sync/org/resources/bib/*.bib
```

Files are written via a staging file in the same directory and installed with a
rename, so a concurrent citar/bibcli read never sees a half-written file.

`ZOTERO_BIB_DIR` is the single override, used by both the renderer and `bibcli`.
(`BIBCLI_DIR` is retired and ignored — a stale value of it used to make `bibcli`
read a retired export directory.)

Override the surface with `ZOTERO_BIB_DIR` if you want it elsewhere:

```bash
ZOTERO_BIB_DIR=/tmp/bibs ./run.sh bib sync
```

### Emacs Integration

Point citar at the same directory:

```elisp
(setq citar-bibliography
      '("~/sync/org/resources/bib/Book.bib"
        "~/sync/org/resources/bib/Online.bib"
        "~/sync/org/resources/bib/Software.bib"
        "~/sync/org/resources/bib/Reference.bib"
        "~/sync/org/resources/bib/Video.bib"
        "~/sync/org/resources/bib/Article.bib"
        "~/sync/org/resources/bib/Misc.bib"
        "~/sync/org/resources/bib/github-starred.bib"))
```

---

## bibcli — BibTeX Search CLI

Go CLI for AI agents to search/view the full bibliography. JSON-only output, stdlib only, single static binary.

```bash
./run.sh build                           # Build + install to ~/.local/bin
bibcli search "emacs" --max 5            # Full-text search
bibcli search "한국" --type Book          # Korean + type filter
bibcli show "165.84-박82ㅅ"               # Full entry by citation key
bibcli lookup 9791192300283              # ISBN → KDC candidate (assist only)
bibcli lookup "슈바이처" --max 3           # Title search (data4library)
bibcli stats                              # Per-file counts
```

See the `bibcli` skill doc at `~/.claude/skills/bibcli/SKILL.md` for full usage.

---

## Translation Server

For saving URLs directly to Zotero Cloud without the GUI:

```bash
./run.sh server start                         # Start localhost:1969
./run.sh save "https://example.com"          # Save URL to Zotero
./run.sh save --sync --json "https://example.com"
# => { saved:[...], resolved:[{zoteroKey,citationKey,title,...}] }
./run.sh server stop
```

Uses [Zotero Translation Server](https://github.com/zotero/translation-server) (cloned to `~/repos/3rd/translation-server`).

---

## Links

- **Digital Garden**: [notes.junghanacs.com](https://notes.junghanacs.com)
- **Zotero Group Library**: [@junghanacs](https://www.zotero.org/groups/5570207/junghanacs/library)

---

**Author**: [@junghanacs](https://github.com/junghan0611)  
**Philosophy**: Life is a book. Everyone is an author.  
**This repo**: the process of tending a bibliography is the point — not the titles alone.

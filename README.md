# zotero-config

**Headless bibliographic workflow: Zotero Cloud API to citar-compatible BibTeX**

> No Zotero GUI. No Better BibTeX plugin. Just API, scripts, and Emacs.

> **AI Agent Skills**: repo operator doctrine is `.claude/skills/zotero-config/SKILL.md` (capture vault vs local bib SSOT, sync reflex). Global search CLI skill + binary: `agent-config/skills/bibcli` (built from `bibcli/` here).

[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

---

## What This Does

Fetches your entire Zotero library via Cloud API and generates citar-compatible BibTeX files split by type. Local `*.bib` is the meta-bibliography SSOT; Zotero Cloud is the capture vault. Citation-key writeback to Cloud is explicit and opt-in (`./run.sh bib writeback`), not part of routine sync.

```
./run.sh bib full       # Full sync: ~6,000 items → 7 BibTeX files (~90s)
./run.sh bib sync       # Incremental sync (delta only, seconds)
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
├── 2. Generate citation keys (gen-bibtex.py)
│   ├── Existing citationKey → keep as-is
│   ├── book + ISBN → DATA4LIBRARY API → KDC classification
│   │   └── e.g. "802.041-김74ㄴ" (KDC-AuthorCode)
│   └── Others → BBT-style rules
│       └── e.g. "web-perplexity", "blog-AiVampire26"
│
├── 3. Write type-based BibTeX files
│   ├── Book.bib      (1,463 entries)  ← book
│   ├── Online.bib    (2,610 entries)  ← webpage, blogPost, forumPost
│   ├── Software.bib  (1,082 entries)  ← computerProgram
│   ├── Reference.bib   (365 entries)  ← encyclopediaArticle, dictionaryEntry
│   ├── Video.bib       (239 entries)  ← videoRecording, film, tvBroadcast
│   ├── Article.bib      (69 entries)  ← journalArticle
│   └── Misc.bib         (62 entries)  ← everything else
│
├── 4. Writeback new citationKeys → Zotero Cloud API (PATCH)
│
└── 5. Save state (.sync/last-version, items.json)

run.sh starred
│
└── GitHub starred repos → github-starred.bib (2,140 entries)
    ├── default account: junghan0611
    ├── if active gh account differs: gh auth switch --user <account>
    └── gh api --paginate user/starred → jq → @software{} entries
```

---

## Citation Key Patterns

| Type | English | Korean (KDC) |
|------|---------|-------------|
| book | `HowTakeSmart17` | `802.041-김74ㄴ` |
| book | `CLRSIntroductionAlgorithms09` | `005-포14ㅋ` |
| webpage | `web-perplexity` | — |
| blogPost | `blog-AiVampire26` | — |
| software | `200okchorganice24` | — |

Korean books with ISBN get a KDC classification number + 4-char author code via [DATA4LIBRARY](https://data4library.kr/) API.

---

## Directory Structure

```
zotero-config/
├── run.sh                 # Main entry point
├── scripts/
│   ├── zotero-to-bib.sh   # Zotero API fetcher (bash + curl + jq)
│   ├── gen-bibtex.py       # BibTeX engine (Python, citar-compatible)
│   ├── writeback-keys.sh   # citationKey → Zotero Cloud (PATCH)
│   ├── gh-starred-to-bib.sh # GitHub starred → BibTeX (gh + jq)
│   ├── run.sh              # Translation Server manager
│   └── zotero-save-url.sh  # URL saver via Translation Server
├── bibcli/                 # BibTeX search CLI for AI agents (Go)
│   ├── main.go             # CLI: search/show/list/lookup/stats
│   ├── parser.go           # BibTeX parser (8,000 entries in 18ms)
│   ├── search.go           # Case-insensitive multi-field AND search
│   └── lookup.go           # data4library 서지검색 (ISBN/제목)
│                           # (skill doc SKILL.md currently in agent-config; relocation planned)
├── output/                 # Generated BibTeX files (symlinked from ~/org/resources/)
│   ├── Book.bib
│   ├── Online.bib
│   ├── Software.bib
│   ├── Reference.bib
│   ├── Video.bib
│   ├── Article.bib
│   ├── Misc.bib
│   └── github-starred.bib
├── config/                 # BBT preferences (reference only)
├── plugins/                # Zotero plugin XPIs (archive)
└── .sync/                  # Sync state (gitignored)
    ├── items.json           # Cached Zotero items
    ├── last-version         # API version for incremental sync
    └── new-keys.json        # Pending citationKey writebacks
```

---

## Setup

### Requirements

- `curl`, `jq`, `python3` (no pip packages needed)
- Zotero account with API access
- (Optional) [DATA4LIBRARY API key](https://data4library.kr/) for Korean KDC

### Environment

Create `.envrc` in the project root:

```bash
export ZOTERO_API_KEY="your-key"
export ZOTERO_USER_ID="your-user-id"
export DATA4LIBRARY_API_KEY="your-key"  # optional, for KDC lookup
export GH_STARRED_ACCOUNT="junghan0611" # optional override for ./run.sh starred
```

### First Run

```bash
git clone https://github.com/junghan0611/zotero-config.git
cd zotero-config
# Create .envrc with your API keys
./run.sh bib full    # Full sync (~90 seconds for ~6000 items)
```

### Emacs Integration

BibTeX files in `output/` are symlinked to `~/org/resources/`:

```bash
ln -s /path/to/zotero-config/output/Book.bib ~/org/resources/Book.bib
# ... repeat for each .bib file
```

Then configure citar:

```elisp
(setq citar-bibliography
      '("~/org/resources/Book.bib"
        "~/org/resources/Online.bib"
        "~/org/resources/Software.bib"
        "~/org/resources/Reference.bib"
        "~/org/resources/Video.bib"
        "~/org/resources/Article.bib"
        "~/org/resources/Misc.bib"
        "~/org/resources/github-starred.bib"))
```

---

## bibcli — BibTeX Search CLI

Go CLI for AI agents to search/view the full bibliography (8,030 entries). JSON-only output, stdlib only, single static binary.

```bash
./run.sh build                           # Build + install to ~/.local/bin
bibcli search "emacs" --max 5            # Full-text search
bibcli search "한국" --type Book          # Korean + type filter
bibcli show "165.84-박82ㅅ"               # Full entry by citation key
bibcli lookup 9791192300283              # ISBN → KDC, 저자, 출판사, 연도
bibcli lookup "슈바이처" --max 3           # 제목 검색 (data4library)
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

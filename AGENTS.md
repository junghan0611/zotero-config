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
Zotero Cloud            = capture vault (phone / browser Connector / save URL)
~/sync/org/resources/bib/*.bib = meta bibliography SSOT — the renderer writes HERE directly
bibcli                  = the only hand that reads the SSOT for agents
```

**Every device is symmetric.** Any device's org steward may run `save` / `pin`
/ `bib sync` locally. Zotero Cloud is the capture authority; that device's
`.sync/` is a private cache; Syncthing shares **only** the live bib directory.
There is no central writer and no Git on the daily path — the steward never runs
a git command to register a URL.

The live directory is `$HOME/sync/org/resources/bib`, overridable with
`ZOTERO_BIB_DIR` (tests do exactly this) — the **one** env var for it, shared by
renderer and reader. `BIBCLI_DIR` is retired and ignored: a stale value left in
a shell profile silently fed thousands of obsolete entries to `bibcli` calls
that passed no `--dir`. The repo's `output/` has no role here
and is not managed by this repo.

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
| 1 | Cite a source **already in Zotero** | `bibcli search "…"` → `bibcli show "key"` | **None** — reads the local bib dir only; no GUI, no server, no API |
| 2 | Save a **new URL** and cite it now | `./run.sh server status \|\| ./run.sh server start` → `./run.sh save --sync --json <url>` | Translation Server extracts metadata → Zotero Cloud → `bib sync` (read-only) → returns `resolved[].citationKey` from the generated key |
| 3 | Refresh local bib from Cloud | `./run.sh bib sync` | Downloads Zotero Cloud → `.sync/items.json` → renders **straight into `$ZOTERO_BIB_DIR/*.bib`** — staged, byte-compared, then installed by a same-filesystem rename. **Read-only — never writes to Zotero Cloud.** Render is network-free, and no Git step is involved. |

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
| `scripts/gh-starred.jq` | The starred render program; `@@KEYSAN@@` is filled from the rules SSOT |
| `scripts/lib-install.sh` | Shared staging install (byte compare → rename, mode preserved) |
| `scripts/run.sh` | Translation Server lifecycle management |
| `scripts/zotero-save-url.sh` | URL saver via Translation Server |
| `scripts/sanitize_bib.py` | Redaction rules SSOT — applied by the renderer *before* sorting |
| `bibcli/` | BibTeX search CLI + `lookup` assist (Go, JSON output) |

### Output Files (in `$ZOTERO_BIB_DIR`, default `~/sync/org/resources/bib/`)

Type-based BibTeX files, written directly by the renderer and carried between
devices by Syncthing:

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

### Determinism contract (`gen-bibtex.py`)

Same library in, **byte-identical** files out — on any device, on any rerun.

- Entries are sorted by `(citationKey, Zotero item key)` **before** the
  duplicate-suffix counter runs, so `-1`/`-2` suffixes are stable too. Cache
  array order, `last-version`, and the clock never reach the bytes.
- Sanitization (`sanitize_bib.py`) runs **before** the sort. The rules rewrite
  identifiers that can sit inside a fallback key, so sanitizing afterwards left
  real inversions in the published bytes (measured: `web-tbdhnygokweol` sat
  above `web-gordonnovakjr`).
- **No generation timestamp is emitted at all** — there is no `% Updated:`
  header. Comparison before install is plain byte equality, so an unchanged
  library never rewrites a file and Syncthing sees no no-op change.
- `github-starred.bib` is rendered outside the Zotero path but follows the same
  rules, from the same source: `scripts/gh-starred-to-bib.sh` asks
  `sanitize_bib.py --jq-filter` for the redaction rules and applies them to the
  bib key **before** `sort_by`, then to the whole entry. No rule is duplicated
  in the shell, so the two renderers cannot drift. No current-time header; its
  `dateadded` / `datemodified` come from `starred_at` / `pushed_at`, which are
  content. Verify: `./tests/starred-determinism.sh` (synthetic response, no
  GitHub call).

Zotero Cloud `dateAdded` / `dateModified` stay as BibTeX `dateadded` /
`datemodified` fields. They are the time axis of the library — semantic content,
not metadata about when the render ran.

Install is staging → byte compare → same-filesystem rename, shared by both
renderers via `scripts/lib-install.sh`. Staging lives inside the bib dir
(hidden, non-`.bib`) so a concurrent citar/bibcli glob never sees a half-written
file, and it is removed on exit. `github-starred.bib` follows the same path, so
an unchanged starred render leaves the file (and its mtime) untouched instead of
rewriting it on every run.

Verify (no network, no Cloud, never touches the live bib dir):

```bash
./tests/render-determinism.sh             # fixture contract
./tests/render-determinism-live-cache.sh  # same contract on this device's cache
./tests/bib-dir-and-install.sh            # path resolution + staged install
./tests/sync-cursor.sh                    # cursor safety under interruption
./tests/sync-lock.sh                      # single-writer lock under concurrency
```

### Cache / cursor commit order (`.sync/last-version`)

`last-version` is a **cursor**: the next incremental sync asks Zotero only for
items modified after it. It may therefore never run ahead of `items.json` — if
it does, every page fetched after a crash is skipped forever and those items
silently vanish from the bibliography.

Measured incident: `bib full` was killed at page 44/63. The old loop wrote the
cursor once **per page**, before any merge, so `items.json` stayed at the old
6223 items while `last-version` had already jumped to 35790. A retry would have
asked for "changes since 35790" and never re-fetched pages 44–63.

The enforced order is:

```text
fetch every page → commit cache (temp + atomic rename)
                 → prune deletions
                 → ONLY THEN commit cursor
```

Deletions are part of that order, not an optional extra: `/deleted?since=` only
reveals them to a request carrying the **old** cursor, so a failed or malformed
deletion response makes `prune_deleted` return nonzero and `do_sync` refuse to
commit the cursor. Skipping it with a warning would advance past deletions that
are then invisible forever.

A signal, timeout, or malformed response anywhere before the last step leaves
the old (cache, cursor) pair intact. The one remaining asymmetry is deliberate
and harmless: a crash between cache commit and cursor commit leaves the cache
*newer* than the cursor, so the next sync re-fetches a superset and the upsert
merge absorbs it. Pages are also accumulated as files and combined once at the
end (the old per-page jq concat was quadratic and a large part of why the full
sync ran long enough to be killed).

Verify: `./tests/sync-cursor.sh` — mock-`curl` fixtures, no network. It covers
SIGKILL mid-fetch, malformed item response, failed/malformed deletion response,
empty incremental, normal full and incremental, plus static checks that the
cursor has exactly one write site and that it lives outside the fetch loop.

### Single-writer lock (`.sync/.lock`)

`.sync/` is per-device, but several local writers reach for it: an org steward's
`pin --sync`, a `save --sync`, a manual `bib full`, an OpenClaw bot. Two
concurrent fetches corrupt each other — measured: a second `bib full` deleted
the first one's **active** fetch staging directory, so the first silently lost
every page from 26 on and ended with `Fetched 0 items total`.

- `full`, `sync`, `writeback` take an exclusive **non-blocking** `flock` first
  and are rejected honestly (with the holder's pid) if someone else holds it.
- `status` is read-only and takes no lock.
- The lock lives on a file descriptor, so the kernel releases it when the
  holding process dies. Bash's `{fd}>` redirection is *not* close-on-exec
  (measured), so a killed run can leave a short-lived child holding the fd; when
  the recorded holder pid is gone, the next run waits up to 10s for the kernel
  rather than breaking anyone's lock by force.
- Fetch staging residue is cleaned by age (`-mmin +60`) only. The blanket
  `rm -rf .sync/.fetch.*` that caused the incident is gone.

Verify: `./tests/sync-lock.sh` — a slow mock fetch holds the lock while a second
invocation must reject and leave the first one's staging, cache, and cursor
untouched.

### State Files (`.sync/`, gitignored — per device, never shared)

`.sync/` is deliberately **not** in Git and **not** in Syncthing. It is that
device's private API cache; sharing it would put two devices' fetch state in
conflict for no gain, because the rendered `.bib` is already the shared
artifact. Every device keeps its own.

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

./tests/render-determinism.sh            # 결정론 계약 (fixture, 네트워크·Cloud 없음)
./tests/render-determinism-live-cache.sh # 같은 계약을 이 기기 실제 캐시로 재확인
./tests/bib-dir-and-install.sh           # 출력면 경로 + staged install
./tests/sync-cursor.sh                   # 커서 안전성 (mock curl, 네트워크 없음)
./tests/sync-lock.sh                     # .sync 단일 쓰기 락 (동시 실행 거부)
./tests/starred-determinism.sh           # github-starred 정렬·비식별화 (합성 입력)
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
./run.sh bib sync                              # refresh $ZOTERO_BIB_DIR/*.bib (no Git)
# then recover the key by distinctive title/author words:
bibcli search "distinctive title author words" --max 5
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

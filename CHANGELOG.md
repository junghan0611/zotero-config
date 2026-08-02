# Changelog

All notable changes, tracked by CalVer date tags.

## Unreleased

### Features

- Added `./run.sh pin --sync` (`scripts/pin-item.py`): whitelist PATCH for
  agent-styled fields + unique `citationKey`, preserves `dateAdded`, optional
  immediate `bib sync` so org/Emacs can cite in the same session.
- **Zotero collection filing on pin:** leaves Unfiled Items — reverse of local
  type-split bib render.
  - Book: KDC leading digit → `Book` + `N00-…` (`001.3-…` → 000-정보)
  - Non-book: itemType → Category leaf (Video, BlogPost, @Web, Software, …)
  - Optional `fileUnder` / `collections` / `noCollections`
- Global **bibcli skill** is the org-agent handbook for any URL (YouTube, book,
  blog, web): save → style/key → `pin --sync` → cite in one session.

### Bibliography

- Styled, pinned, and filed 김정운 『말하지 않고 말하기』 as `001.3-김74ㅁ`
  under My Library → Book → 000-정보.

## v2026.8.2-books.1 — book ritual off the sync path

### Breaking (ops)

- **`bib sync` / `gen-bibtex.py` no longer call data4library for KDC.**
  Render is network-free: existing `citationKey` is kept; missing keys get a
  local BBT-style fallback only. Book classification stays a human ritual in
  Zotero. Assistive candidates remain on `bibcli lookup` / explicit `enrich`.

### Documentation

- Expanded operator skill (`.claude/skills/zotero-config/SKILL.md`) with the
  **book inflow ritual** (yes24 → Connector → hand-edit → library OPAC sense →
  citation key), sacred `dateAdded`/`dateModified`, and repo identity
  (publishing the *process* of tending a bibliography, not book recommendations).
- Aligned `AGENTS.md` / `README.md` pipeline diagrams: writeback is not a sync
  step; KDC is off the main path.
- Pointed `bibcli` skill at the same boundary (`lookup` = candidate only).

### Bibliography

- Pulled curated book entries (incl. 이준호 3권) and related online/video
  refreshes into `output/*.bib`.

### Fixes

- Sync no longer stalls when data4library is unreachable (root cause of
  “Processing N items…” hangs during book-key upgrade attempts).

## v2026.8.2 — capture-vault doctrine + operator skill

### Documentation

- Stated the operating doctrine in-repo: Zotero Cloud is the **capture vault**;
  local `output/` → `~/org/resources/*.bib` is the **meta-bibliography SSOT**.
- Added repo operator skill `.claude/skills/zotero-config/SKILL.md` (nixos-config
  pattern): external-capture → `bib sync` reflex without asking, book (KDC,
  careful) vs online/video (pull freely) split, mutation boundary, out-of-scope
  edges (no MCP, no starred-list scrapers, no casual writeback).
- Pointed `AGENTS.md` / `README.md` at the skill; clarified that routine sync
  does not write citation keys back to Cloud.

### Notes since v2026.6.11

- Bibliography output refreshes and the read-only sync / explicit-writeback
  split landed on main between tags; this tag bookmarks the doctrine surface
  agents actually load.

## v2026.6.11

### Features

- Added the Zotero save-sync citation workflow (Translation Server → save URL → `bib sync` → `bibcli`).
- Added `enrich-books.py` to auto-enrich `book-` prefixed entries with metadata, including a Google Books API fallback and original-title search.
- Added the `bibcli lookup` command for data4library bibliographic search.
- Added a public sanitize step to the bib build so outputs are safe to publish.

### Fixes

- Pruned Zotero-deleted items on every incremental sync and hardened writeback so a deleted key is skipped instead of crashing the run.
- Pinned the `junghan0611` account for GitHub starred export.
- Prevented repeated writeback when a `book-` key fails KDC lookup.
- Raised the enrich-books ISBN match threshold to 0.8 to avoid mismatches.

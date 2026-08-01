# Changelog

All notable changes, tracked by CalVer date tags.

## Unreleased

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
- Fixed the incremental sync bug that overwrote `items.json`.
- Built `bibcli` as a static binary (`CGO_ENABLED=0` + `-trimpath`).

## v0.2.0

- Pre-CalVer baseline.

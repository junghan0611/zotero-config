# Changelog

All notable changes, tracked by CalVer date tags.

## Unreleased

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

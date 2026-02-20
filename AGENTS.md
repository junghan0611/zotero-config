# Agent Instructions

This project uses **br** (beads_rust) for issue tracking. Run `br onboard` to get started.

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
br ready              # Find available work
br show <id>          # View issue details
br update <id> --status in_progress  # Claim work
br close <id>         # Complete work
br sync --flush-only  # Export to JSONL
git add .beads/
git commit -m "sync beads"
```

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   br sync --flush-only
   git add .beads/
   git commit -m "sync beads"
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds

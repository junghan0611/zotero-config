#!/usr/bin/env python3
"""
pin-item.py — style + citationKey PATCH onto one Zotero Cloud item.

Agent-owned judgment (title/author/date/KDC key) happens *before* this tool.
This script only:
  1. checks citationKey uniqueness against local bib SSOT
  2. PATCHes a whitelist of fields (never dateAdded)
  3. optionally runs bib sync so Emacs/org can cite immediately

Usage:
  ./run.sh pin --json '{"zoteroKey":"ABCD","citationKey":"001.3-김74ㅁ","title":"…", ...}'
  ./run.sh pin --sync --json '...'
  echo '{...}' | ./run.sh pin --sync --json -

Exit codes:
  0 ok, 1 usage/validation, 2 duplicate key, 3 API/PATCH failure
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request

API = "https://api.zotero.org"
UA = "zotero-config-pin/1.0"

# Fields agents may set. dateAdded / dateModified / key / version are NEVER accepted.
ALLOWED = frozenset(
    {
        "title",
        "creators",
        "date",
        "publisher",
        "place",
        "ISBN",
        "language",
        "abstractNote",
        "shortTitle",
        "url",
        "accessDate",
        "volume",
        "edition",
        "series",
        "pages",
        "numPages",
        "citationKey",
        "callNumber",
        "extra",
        "rights",
        "tags",
    }
)

REQUIRED = ("zoteroKey", "citationKey")


def die(code: int, msg: str) -> None:
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(code)


def load_payload(raw: str) -> dict:
    if raw == "-":
        raw = sys.stdin.read()
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as e:
        die(1, f"invalid JSON: {e}")
    if not isinstance(data, dict):
        die(1, "JSON payload must be an object")
    return data


def bib_key_exists(citation_key: str, bib_dir: str) -> bool:
    """True if local SSOT already has this citation key."""
    bibcli = os.environ.get("BIBCLI") or os.path.expanduser("~/.local/bin/bibcli")
    if os.path.isfile(bibcli) and os.access(bibcli, os.X_OK):
        try:
            r = subprocess.run(
                [bibcli, "show", citation_key, "--dir", bib_dir],
                capture_output=True,
                text=True,
                timeout=30,
            )
            if r.returncode == 0 and r.stdout.strip().startswith("{"):
                return True
            # bibcli prints 'entry not found' on miss
            return False
        except Exception:
            pass
    # Fallback: scan *.bib @type{key,
    if not os.path.isdir(bib_dir):
        return False
    needle = "{" + citation_key + ","
    for name in os.listdir(bib_dir):
        if not name.endswith(".bib"):
            continue
        path = os.path.join(bib_dir, name)
        try:
            with open(path, "r", encoding="utf-8") as f:
                if needle in f.read():
                    return True
        except OSError:
            continue
    return False


def zotero_get(api_key: str, user_id: str, item_key: str) -> dict:
    url = f"{API}/users/{user_id}/items/{item_key}"
    req = urllib.request.Request(
        url, headers={"Zotero-API-Key": api_key, "User-Agent": UA}
    )
    with urllib.request.urlopen(req, timeout=20) as resp:
        return json.loads(resp.read().decode("utf-8"))


def zotero_patch(
    api_key: str, user_id: str, item_key: str, version: int, patch: dict
) -> int:
    url = f"{API}/users/{user_id}/items/{item_key}"
    body = json.dumps(patch, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=body,
        method="PATCH",
        headers={
            "Zotero-API-Key": api_key,
            "Content-Type": "application/json",
            "If-Unmodified-Since-Version": str(version),
            "User-Agent": UA,
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            return resp.status
    except urllib.error.HTTPError as e:
        err = e.read().decode("utf-8", errors="replace")[:400]
        print(f"error: PATCH HTTP {e.code}: {err}", file=sys.stderr)
        return e.code


def main() -> None:
    parser = argparse.ArgumentParser(description="Pin styled fields + citationKey to Zotero")
    parser.add_argument("--json", required=True, help="JSON object or '-' for stdin")
    parser.add_argument(
        "--bib-dir",
        default=os.path.expanduser("~/org/resources"),
        help="Local bib SSOT for uniqueness check",
    )
    parser.add_argument(
        "--allow-overwrite-key",
        action="store_true",
        help="Allow citationKey that already exists (same item re-pin)",
    )
    parser.add_argument(
        "--repo-dir",
        default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        help="zotero-config repo root (for optional --sync)",
    )
    parser.add_argument(
        "--sync",
        action="store_true",
        help="Run ./run.sh bib sync after successful PATCH",
    )
    args = parser.parse_args()

    api_key = os.environ.get("ZOTERO_API_KEY", "")
    user_id = os.environ.get("ZOTERO_USER_ID", "")
    if not api_key or not user_id:
        die(1, "ZOTERO_API_KEY / ZOTERO_USER_ID required")

    payload = load_payload(args.json)
    for req in REQUIRED:
        if not payload.get(req):
            die(1, f"missing required field: {req}")

    zotero_key = str(payload["zoteroKey"])
    citation_key = str(payload["citationKey"]).strip()
    if not citation_key:
        die(1, "citationKey empty")

    # Forbidden keys
    for bad in ("dateAdded", "dateModified", "key", "version", "itemType"):
        if bad in payload and bad not in ("itemType",):
            die(1, f"field not allowed in pin payload: {bad}")
    if "itemType" in payload:
        # itemType changes are dangerous; reject
        die(1, "itemType changes are not allowed via pin")

    if bib_key_exists(citation_key, args.bib_dir) and not args.allow_overwrite_key:
        # Same-key re-pin (style fix) is OK when the live Zotero item already owns it.
        try:
            probe = zotero_get(api_key, user_id, zotero_key)
            owned = (probe.get("data") or {}).get("citationKey") == citation_key
        except Exception:
            owned = False
        if not owned:
            die(2, f"citationKey already in SSOT: {citation_key}")

    patch = {"citationKey": citation_key}
    for k, v in payload.items():
        if k in ("zoteroKey", "citationKey"):
            continue
        if k not in ALLOWED:
            die(1, f"field not allowed: {k}")
        patch[k] = v

    try:
        cur = zotero_get(api_key, user_id, zotero_key)
    except Exception as e:
        die(3, f"GET failed: {e}")

    version = cur.get("version")
    before = cur.get("data", {})
    date_added = before.get("dateAdded")

    status = zotero_patch(api_key, user_id, zotero_key, version, patch)
    if status not in (200, 204):
        die(3, f"PATCH failed with status {status}")

    try:
        after_wrap = zotero_get(api_key, user_id, zotero_key)
    except Exception as e:
        die(3, f"GET after PATCH failed: {e}")
    after = after_wrap.get("data", {})
    if date_added and after.get("dateAdded") != date_added:
        die(3, "dateAdded changed after PATCH — stop and inspect")

    result = {
        "zoteroKey": zotero_key,
        "citationKey": after.get("citationKey", citation_key),
        "title": after.get("title"),
        "dateAdded": after.get("dateAdded"),
        "dateModified": after.get("dateModified"),
        "patched": sorted(patch.keys()),
        "synced": False,
    }

    if args.sync:
        run_sh = os.path.join(args.repo_dir, "run.sh")
        r = subprocess.run(
            [run_sh, "bib", "sync"],
            cwd=args.repo_dir,
            capture_output=True,
            text=True,
        )
        if r.returncode != 0:
            print(r.stderr or r.stdout, file=sys.stderr)
            die(3, "bib sync failed after pin")
        result["synced"] = True

    json.dump(result, sys.stdout, ensure_ascii=False, indent=2)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
pin-item.py — style + citationKey PATCH onto one Zotero Cloud item.

Agent-owned judgment (title/author/date/KDC key) happens *before* this tool.
This script only:
  1. checks citationKey uniqueness against local bib SSOT
  2. PATCHes a whitelist of fields (never dateAdded)
  3. files into Zotero collections (Book → N00-… from KDC digit) so the
     item leaves Unfiled Items — reverse of local type-split bib render
  4. optionally runs bib sync so Emacs/org can cite immediately

Usage:
  ./run.sh pin --json '{"zoteroKey":"ABCD","citationKey":"001.3-김74ㅁ","title":"…", ...}'
  ./run.sh pin --sync --json '...'
  echo '{...}' | ./run.sh pin --sync --json -

Collection control (optional payload keys, not Zotero native fields):
  collections: ["KEY", ...]   explicit collection keys (merged with auto)
  fileUnder: "000-정보"       force section by name
  noCollections: true         skip collection filing

Exit codes:
  0 ok, 1 usage/validation, 2 duplicate key, 3 API/PATCH failure
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request

API = "https://api.zotero.org"
UA = "zotero-config-pin/1.0"

# My Library → Book → N00-… (SSOT keys; also in enrich-books.py)
BOOK_COLLECTION = "MC24XQEC"
KDC_COLLECTION_MAP = {
    "0": "S7W5Z692",  # 000-정보
    "1": "LS25E24L",  # 100-철학
    "2": "J2ES338U",  # 200-영성
    "3": "VF5GEFUJ",  # 300-사회
    "4": "NQRCWT8U",  # 400-자연
    "5": "6NNNFHJD",  # 500-기술
    "6": "B3N2AXFF",  # 600-예술
    "7": "PGQXIXD6",  # 700-언어
    "8": "ZRD2LLTI",  # 800-문학
    "9": "FEEZYYIH",  # 900-역사
}
SECTION_NAME_TO_KEY = {
    "000-정보": "S7W5Z692",
    "100-철학": "LS25E24L",
    "200-영성": "J2ES338U",
    "300-사회": "VF5GEFUJ",
    "400-자연": "NQRCWT8U",
    "500-기술": "6NNNFHJD",
    "600-예술": "B3N2AXFF",
    "700-언어": "PGQXIXD6",
    "800-문학": "ZRD2LLTI",
    "900-역사": "FEEZYYIH",
    "Book": BOOK_COLLECTION,
    # Category leaves (dominant filing pattern in this library)
    "@Web": "BD6TWS5S",
    "BlogPost": "RVJ9H9MG",
    "Video": "QZMJ3EUK",
    "Film": "8KCWR24J",
    "Software": "MA243JTT",
    "Wikipedia": "RG9K9W3P",
    "Forum": "3QZ6RB4C",
    "Document": "N7QB2MR7",
    "Dictionary": "2JTYWDNZ",
    "Person": "VW2MYDKR",
    "Presentation": "P5DHRJFU",
    "Dataset": "HIFXUXZB",
    "Image": "KIHRLPNM",
    "Music": "687F5APW",
    "Programming": "KH75T2UA",
}

# Zotero itemType → default Category leaf (non-book). Mirrors local *.bib split.
ITEM_TYPE_COLLECTION = {
    "webpage": "BD6TWS5S",  # @Web
    "blogPost": "RVJ9H9MG",  # BlogPost
    "videoRecording": "QZMJ3EUK",  # Video
    "tvBroadcast": "QZMJ3EUK",
    "film": "8KCWR24J",  # Film
    "computerProgram": "MA243JTT",  # Software
    "encyclopediaArticle": "RG9K9W3P",  # Wikipedia
    "dictionaryEntry": "2JTYWDNZ",
    "forumPost": "3QZ6RB4C",
    "document": "N7QB2MR7",
    "presentation": "P5DHRJFU",
    "interview": "VW2MYDKR",  # Person-ish
    "artwork": "KIHRLPNM",
    "audioRecording": "687F5APW",
}

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
        "collections",
    }
)

# Control keys stripped before PATCH (not sent as Zotero fields as-is without merge)
CONTROL_KEYS = frozenset({"zoteroKey", "citationKey", "fileUnder", "noCollections"})

REQUIRED = ("zoteroKey", "citationKey")


def collections_for_citation_key(citation_key: str) -> list[str]:
    """Book + KDC hundred-section from leading digit of citationKey."""
    m = re.match(r"^([0-9])", citation_key.strip())
    if not m:
        return []
    section = KDC_COLLECTION_MAP.get(m.group(1))
    if not section:
        return []
    return [BOOK_COLLECTION, section]


def collections_for_item_type(item_type: str) -> list[str]:
    """Category leaf from Zotero itemType (webpage→@Web, video→Video, …)."""
    key = ITEM_TYPE_COLLECTION.get(item_type or "")
    return [key] if key else []


def resolve_collections(
    payload: dict, citation_key: str, existing: list, item_type: str = ""
) -> list[str] | None:
    """Merge existing + auto (KDC book or itemType category) + explicit.

    None = do not PATCH collections.
    """
    if payload.get("noCollections") is True:
        return None

    out: list[str] = []
    seen: set[str] = set()

    def add(keys):
        for k in keys or []:
            if not k or k in seen:
                continue
            seen.add(k)
            out.append(k)

    add(existing)

    file_under = payload.get("fileUnder")
    auto: list[str] = []
    if file_under:
        key = SECTION_NAME_TO_KEY.get(str(file_under))
        if not key:
            die(1, f"unknown fileUnder section: {file_under}")
        # Book sections need Book parent; Category leaves stand alone.
        if key in KDC_COLLECTION_MAP.values() or key == BOOK_COLLECTION:
            auto = [BOOK_COLLECTION, key] if key != BOOK_COLLECTION else [BOOK_COLLECTION]
        else:
            auto = [key]
        add(auto)
    else:
        # Prefer KDC book filing when citationKey looks like decimal class.
        auto = collections_for_citation_key(citation_key)
        if not auto:
            auto = collections_for_item_type(item_type)
        add(auto)

    explicit = payload.get("collections")
    if explicit is not None:
        if not isinstance(explicit, list):
            die(1, "collections must be a list of collection keys")
        add(explicit)

    if not out and explicit is None and not file_under and not auto:
        return None
    return out


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
        default=os.environ.get("ZOTERO_BIB_DIR")
        or os.path.expanduser("~/sync/org/resources/bib"),
        # %(default)s → --help 이 실제로 해석된 경로를 보여준다 (override 포함)
        help="Local bib SSOT for uniqueness check (default: %(default)s)",
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

    try:
        cur = zotero_get(api_key, user_id, zotero_key)
    except Exception as e:
        die(3, f"GET failed: {e}")

    version = cur.get("version")
    before = cur.get("data", {})
    date_added = before.get("dateAdded")
    existing_cols = list(before.get("collections") or [])

    patch: dict = {"citationKey": citation_key}
    for k, v in payload.items():
        if k in CONTROL_KEYS or k == "collections":
            continue
        if k not in ALLOWED:
            die(1, f"field not allowed: {k}")
        patch[k] = v

    item_type = str(before.get("itemType") or "")
    resolved_cols = resolve_collections(
        payload, citation_key, existing_cols, item_type=item_type
    )
    if resolved_cols is not None:
        patch["collections"] = resolved_cols

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
        "collections": after.get("collections") or [],
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

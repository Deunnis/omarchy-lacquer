#!/usr/bin/env python3
"""Emit one JSON array describing every installed Omarchy shell plugin.

QML cannot glob a directory tree, and the host's registry snapshot only covers
bar widgets — panel, service and overlay plugins carry settings too. Reading
the manifests straight off disk is the one source that covers both, and it also
survives the host stripping metadata from what it hands third-party plugins.

Each record: id, name, description, kinds, dir, firstParty, schema, defaults,
and where its settings live (bar section, or the top-level plugins list).
"""
import json
import os
import sys

HOME = os.path.expanduser("~")
FIRST_PARTY = "/usr/share/omarchy/shell/plugins"
USER = os.path.join(HOME, ".config/omarchy/plugins")


def manifests(root, first_party):
    """Both conventions: <dir>/manifest.json, and <dir>/<Name>.manifest.json
    for the simple first-party widgets that live as single files."""
    found = []
    if not os.path.isdir(root):
        return found
    for base, dirs, files in os.walk(root):
        # Hidden directories are skipped wholesale: `omarchy plugin remove`
        # leaves the removed plugin behind as `.<id>.bak.<stamp>`, and walking
        # into it would list a plugin the user has just uninstalled.
        dirs[:] = [d for d in dirs
                   if not d.startswith(".") and d not in ("node_modules", "assets")]
        for name in files:
            if name == "manifest.json" or name.endswith(".manifest.json"):
                found.append((os.path.join(base, name), first_party))
    return found


def load(path, first_party):
    try:
        if not os.path.isfile(path) or os.path.getsize(path) > 256 * 1024:
            return None
        with open(path, "r", encoding="utf-8") as handle:
            data = json.loads(handle.read(256 * 1024 + 1))
    except Exception:
        return None
    if not isinstance(data, dict) or not data.get("id"):
        return None
    widget = data.get("barWidget") or {}
    kinds = data.get("kinds") or []
    return {
        "id": str(data["id"]),
        "name": str(data.get("name") or data["id"]),
        "description": str(data.get("description") or ""),
        "kinds": [str(k) for k in kinds],
        "dir": os.path.dirname(path),
        "firstParty": bool(first_party),
        "isBarWidget": "bar-widget" in kinds,
        "displayName": str(widget.get("displayName") or data.get("name") or data["id"]),
        "category": str(widget.get("category") or ""),
        "schema": widget.get("schema") or [],
        "defaults": widget.get("defaults") or {},
    }


def main():
    seen = {}
    # A user plugin with the same id shadows the packaged one, which is what
    # `omarchy plugin clone` produces, so user manifests are read last.
    for root, first_party in ((FIRST_PARTY, True), (USER, False)):
        for path, fp in manifests(root, first_party):
            record = load(path, fp)
            if record:
                seen[record["id"]] = record
    out = sorted(seen.values(), key=lambda r: (not r["isBarWidget"], r["name"].lower()))
    json.dump(out, sys.stdout)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Met à jour sidestore/source.json (format de source AltStore / SideStore)."""
import argparse
import datetime as dt
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "sidestore/source.json"

p = argparse.ArgumentParser()
p.add_argument("--version", required=True)
p.add_argument("--build", required=True)
p.add_argument("--size", type=int, required=True)
p.add_argument("--url", required=True)
p.add_argument("--repo", default="")
p.add_argument("--notes", default="")
a = p.parse_args()

data = json.loads(SOURCE.read_text(encoding="utf-8"))
app = data["apps"][0]
if a.repo:
    raw = f"https://raw.githubusercontent.com/{a.repo}/main"
    data["sourceURL"] = f"{raw}/sidestore/source.json"
    data["iconURL"] = app["iconURL"] = f"{raw}/App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
    data["website"] = f"https://github.com/{a.repo}"

entry = {
    "version": a.version,
    "buildVersion": a.build,
    "date": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "localizedDescription": a.notes or f"Build {a.build}",
    "downloadURL": a.url,
    "size": a.size,
    "minOSVersion": "18.0",
}
others = [v for v in app.get("versions", []) if v.get("buildVersion") != a.build]
app["versions"] = [entry] + others[:9]
SOURCE.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"source.json → {a.version} ({a.build})")

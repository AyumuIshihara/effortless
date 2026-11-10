#!/usr/bin/env bash
# Runs effortless's own tests. `claude plugin test .` runs every *.test.ts under the folder and has no exclude, so a
# plugin kept in a subfolder (textless/) would have its tests run against effortless. This runs them on a copy of the
# working tree without those folders: tracked files plus new ones not ignored, as they are on disk now.
set -euo pipefail
cd "$(dirname "$0")/.."
# This fork publishes by hand: plugin.json's version and the newest entry of public.json and releases.json must agree.
# Read as JSON, so a nested "version", a duplicate key or a broken file is not taken for the real one.
PY=$(command -v python3 || command -v python || true)
if [ -z "$PY" ]; then
  echo "版を確かめられません: python が見つかりません" >&2
  exit 1
fi
PYTHONIOENCODING=utf-8 "$PY" - <<'EOF'
import json, re, sys

def pairs(items):
    keys = [k for k, _ in items]
    dup = {k for k in keys if keys.count(k) > 1}
    if dup:
        raise ValueError("重複したキー: " + ", ".join(sorted(dup)))
    return dict(items)

def load(path):
    try:
        with open(path, encoding="utf-8-sig") as f:
            return json.load(f, object_pairs_hook=pairs)
    except (OSError, ValueError) as e:
        sys.exit(f"版を確かめられません: {path} を JSON として読めません ({e})")

def version(value, where):
    if not isinstance(value, str) or not re.fullmatch(r"\d+\.\d+\.\d+", value):
        sys.exit(f"版を確かめられません: {where} の version が数字 3 つの形ではありません ({value!r})")
    return value

plugin = load(".claude-plugin/plugin.json")
own = version(plugin.get("version") if isinstance(plugin, dict) else None, "plugin.json")
for path in ("public.json", "releases.json"):
    data = load(path)
    top = data[0] if isinstance(data, list) and data else None
    got = version(top.get("version") if isinstance(top, dict) else None, f"{path} の先頭")
    if got != own:
        sys.exit(f"版が揃っていません: plugin.json は {own}、{path} の先頭は {got}")
EOF
OTHER='^textless/'
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
git ls-files -z --cached --others --exclude-standard | grep -zvE "$OTHER" | while IFS= read -r -d '' f; do
  [ -f "$f" ] && cp --parents -- "$f" "$tmp"
done
cd "$tmp"
CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1 claude plugin test .

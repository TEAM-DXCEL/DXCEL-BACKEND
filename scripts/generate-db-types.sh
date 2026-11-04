#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_dir"
mkdir -p generated
types_tmp=$(mktemp generated/database.types.ts.XXXXXX)
trap 'rm -f "$types_tmp"' EXIT HUP INT TERM

pnpm --silent run supabase gen types typescript --schema public > "$types_tmp"
test -s "$types_tmp"
mv "$types_tmp" generated/database.types.ts

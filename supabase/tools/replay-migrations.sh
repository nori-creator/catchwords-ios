#!/bin/sh
# Replays the web repo's migrations on a scratch local PostgreSQL (with local-stubs.sql standing in for
# Supabase's own schemas) so the final schema can be compared with production and dumped as a baseline.
# Usage: replay-migrations.sh <migrations dir> <psql connection args...>
set -eu
dir=$1; shift
here=$(cd "$(dirname "$0")" && pwd)
err=$(mktemp)
trap 'rm -f "$err"' EXIT
psql "$@" -v ON_ERROR_STOP=1 -q -f "$here/local-stubs.sql" 2>&1 | grep -v -e wal_level -e HINT || true
for f in $(ls "$dir"); do
  case $f in
    # Same statements as 20260820200000_wordbooks.sql (Lovable wrote the change twice); production ran it once.
    20260821055316_f30ea74a-0580-4ae3-a517-906589138006.sql) continue ;;
  esac
  psql "$@" -v ON_ERROR_STOP=1 -q -1 -f "$dir/$f" >/dev/null 2>"$err" || { echo "FAILED: $f"; cat "$err"; exit 1; }
done
echo "replayed $(ls "$dir" | wc -l) files"

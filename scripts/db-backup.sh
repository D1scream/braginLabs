#!/usr/bin/env bash
set -euo pipefail
umask 077

if [[ $# != 1 || -z $1 ]]; then
  printf 'Usage: %s OUTPUT.sql.zst.gpg\n' "$0" >&2
  exit 2
fi
: "${GPG_RECIPIENT:?Set GPG_RECIPIENT to a public encryption key fingerprint}"
: "${PGDATABASE:?Set PGDATABASE to the database to back up}"

output=$1
mkdir -p -- "$(dirname -- "$output")"
if [[ -e $output || -L $output ]]; then
  printf 'Backup already exists: %s\n' "$output" >&2
  exit 1
fi

tmpdir=$(mktemp -d -- "${output}.tmp.XXXXXXXX")
trap 'rm -f -- "$tmpdir/backup"; rmdir -- "$tmpdir"' EXIT

pg_dump --no-password --format=plain --no-owner --no-privileges |
  zstd -T0 -3 |
  gpg --batch --compress-algo none --encrypt --recipient "$GPG_RECIPIENT" \
    --output "$tmpdir/backup"

# Publish atomically without overwriting a file created by another invocation.
ln -T -- "$tmpdir/backup" "$output"
printf 'Saved encrypted backup: %s\n' "$output"

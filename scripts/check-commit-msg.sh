#!/usr/bin/env bash
set -euo pipefail

if [[ $# != 1 || ! -f $1 ]]; then
  printf 'Usage: %s COMMIT_MESSAGE_FILE\n' "$0" >&2
  exit 2
fi

convco check --from-stdin --strip <"$1"

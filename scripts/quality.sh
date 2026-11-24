#!/usr/bin/env bash
set -euo pipefail

case ${1:-} in
  fmt | chk) mode=$1 ;;
  *)
    printf 'Usage: %s {fmt|chk}\n' "$0" >&2
    exit 2
    ;;
esac

cd "$(git rev-parse --show-toplevel)"
markdown=()
shell=()
while IFS= read -r -d '' path; do
  [[ -f $path ]] || continue
  case $path in
    *.md | *.markdown) markdown+=("./$path") ;;
    *.sh | *.bash | .envrc) shell+=("./$path") ;;
  esac
done < <(git ls-files --deduplicate --cached --others --exclude-standard -z -- . ':(exclude)Labs')

if [[ $mode == fmt ]]; then
  if ((${#markdown[@]})); then mdformat --wrap 88 "${markdown[@]}"; fi
  if ((${#shell[@]})); then shfmt -ln bash -i 2 -ci -w "${shell[@]}"; fi
  cargo fmt --all
else
  if ((${#markdown[@]})); then mdformat --wrap 88 --check "${markdown[@]}"; fi
  if ((${#shell[@]})); then
    shfmt -ln bash -i 2 -ci -d "${shell[@]}"
    shellcheck -s bash "${shell[@]}"
  fi
  cargo fmt --all --check
  cargo clippy --locked --all-targets -- -D warnings
fi

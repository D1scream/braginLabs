#!/usr/bin/env bash

# pass sources this file and provides PREFIX.
selected=$(
  find "$PREFIX" -type f -name '*.gpg' -printf '%P\n' |
    sed 's/\.gpg$//' |
    fzf --prompt='pass> ' --height=40% --layout=reverse
) || return 0

if [[ -n $selected ]]; then
  pass show --clip -- "$selected"
fi

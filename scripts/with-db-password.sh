#!/usr/bin/env bash
set -euo pipefail

profile=${PIES_SECRETS_PROFILE:-development}
case $profile in
  development | staging) ;;
  *)
    printf 'PIES_SECRETS_PROFILE must be development or staging\n' >&2
    exit 2
    ;;
esac

: "${PGPORT:?Run inside the project devenv shell}"
export PGUSER="pies_$profile"
export DATABASE_URL="postgresql://$PGUSER@127.0.0.1:$PGPORT/prediction_pies"
exec secretspec run --profile "$profile" -- "$@"

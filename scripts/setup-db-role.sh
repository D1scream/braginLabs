#!/usr/bin/env bash
set -euo pipefail

: "${PGPASSWORD:?Set the password with secretspec before starting the secrets profile}"
case ${PGUSER:-} in
  pies_development | pies_staging) ;;
  *)
    printf 'Run this script through with-db-password.sh\n' >&2
    exit 2
    ;;
esac

# Bootstrap through the private socket as the initdb user.
psql -Xw --set ON_ERROR_STOP=1 --host "${DEVENV_RUNTIME:?}/postgres" \
  --username "$(id -un)" --dbname prediction_pies <<'SQL'
\getenv app_role PGUSER
\getenv app_password PGPASSWORD
BEGIN;

SELECT 'CREATE ROLE pies_owner NOLOGIN'
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'pies_owner')
\gexec

SELECT format('CREATE ROLE %I LOGIN', :'app_role')
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = :'app_role')
\gexec

SET LOCAL password_encryption = 'scram-sha-256';
ALTER ROLE :"app_role" WITH PASSWORD :'app_password';
GRANT pies_owner TO :"app_role";
ALTER DATABASE prediction_pies OWNER TO pies_owner;

-- Preserve tables already created in the earlier labs.
ALTER TABLE IF EXISTS public.pies OWNER TO pies_owner;
ALTER TABLE IF EXISTS public._sqlx_migrations OWNER TO pies_owner;

-- Both secret profiles use the same owner for subsequent migrations.
ALTER ROLE :"app_role" IN DATABASE prediction_pies SET role TO pies_owner;
COMMIT;
SQL

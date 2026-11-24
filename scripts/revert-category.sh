#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname -- "${BASH_SOURCE[0]}")/.."
source_dir=$(mktemp -d)
trap 'rm -f -- "$source_dir/"*.sql; rmdir -- "$source_dir"' EXIT

cp migrations/001_initial.sql migrations/002_add_prediction_category.sql "$source_dir/"
cp scripts/sql/002_remove_prediction_category.sql "$source_dir/002_add_prediction_category.down.sql"
sqlx migrate revert --source "$source_dir" --target-version 1

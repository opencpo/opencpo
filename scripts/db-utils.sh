#!/usr/bin/env bash
# db-utils.sh — Shared database utility functions for OpenCPO
#
# Source this file from update.sh or container scripts:
#   source /app/opencpo/scripts/db-utils.sh
#
# Provides:
#   pg_dump, pg_restore, run_migrations, list_backups

set -euo pipefail

# ── Defaults (overridable via environment) ──
: "${PG_HOST:=postgres}"
: "${PG_PORT:=5432}"
: "${PG_USER:=ocpp}"
: "${PG_NAME:=ocpp}"
: "${PG_PASSWORD:=ocpp}"
: "${BACKUP_DIR:=/app/backups}"
: "${RETENTION_COUNT:=5}"

# ── Load .env if present and not already loaded ──
load_env() {
  local env_file="${1:-}"
  if [ -z "$env_file" ]; then
    # Try relative to BACKUP_DIR's parent or cwd
    if [ -f "./.env" ]; then
      env_file="./.env"
    elif [ -f "$(dirname "$BACKUP_DIR")/.env" ]; then
      env_file="$(dirname "$BACKUP_DIR")/.env"
    fi
  fi
  if [ -n "$env_file" ] && [ -f "$env_file" ]; then
    set -a
    source "$env_file"
    set +a
  fi
}

# ── PGPASSWORD helper ──
_pg_env() {
  echo "PGPASSWORD=${PG_PASSWORD}"
}

# ── Create a custom-format dump of the database ──
# Usage: db_backup [output_path]
# Returns the backup file path.
db_backup() {
  local output_path="${1:-}"
  if [ -z "$output_path" ]; then
    mkdir -p "$BACKUP_DIR"
    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)
    output_path="${BACKUP_DIR}/opencpo-${PG_NAME}-${timestamp}.dump"
  fi

  mkdir -p "$(dirname "$output_path")"

  # Use a temp file inside the container/VM to avoid incomplete writes
  local tmp_output
  tmp_output="$(mktemp)"

  echo "[db-utils] Backing up database ${PG_NAME}@${PG_HOST}:${PG_PORT} → ${output_path}"

  PGPASSWORD="${PG_PASSWORD}" pg_dump \
    -h "$PG_HOST" \
    -p "$PG_PORT" \
    -U "$PG_USER" \
    -d "$PG_NAME" \
    --format=custom \
    --no-owner \
    --no-acl \
    --verbose \
    -f "$tmp_output" 2>&1 | tail -5 || {
    local rc=$?
    rm -f "$tmp_output"
    echo "[db-utils] ERROR: pg_dump failed (exit code $rc)" >&2
    return $rc
  }

  mv "$tmp_output" "$output_path"
  echo "[db-utils] Backup complete: ${output_path} ($(du -h "$output_path" | cut -f1))"
  echo "$output_path"
}

# ── Restore a custom-format dump ──
# Usage: db_restore <backup_file>
db_restore() {
  local backup_file="$1"
  if [ ! -f "$backup_file" ]; then
    echo "[db-utils] ERROR: Backup file not found: ${backup_file}" >&2
    return 1
  fi

  echo "[db-utils] Restoring database ${PG_NAME}@${PG_HOST}:${PG_PORT} from ${backup_file}"

  PGPASSWORD="${PG_PASSWORD}" pg_restore \
    -h "$PG_HOST" \
    -p "$PG_PORT" \
    -U "$PG_USER" \
    -d "$PG_NAME" \
    --format=custom \
    --clean \
    --if-exists \
    --no-owner \
    --no-acl \
    --verbose \
    "$backup_file" 2>&1 | tail -10 || {
    local rc=$?
    echo "[db-utils] ERROR: pg_restore failed (exit code $rc)" >&2
    return $rc
  }

  echo "[db-utils] Restore complete"
}

# ── Run Alembic migrations ──
# Usage: run_migrations [app_directory]
# Requires alembic to be available on PATH or at the given app directory.
run_migrations() {
  local app_dir="${1:-/app}"

  echo "[db-utils] Running database migrations in ${app_dir}..."

  if [ ! -d "$app_dir" ]; then
    echo "[db-utils] ERROR: App directory does not exist: ${app_dir}" >&2
    return 1
  fi

  if [ ! -f "${app_dir}/alembic.ini" ] && [ ! -f "${app_dir}/alembic/alembic.ini" ]; then
    echo "[db-utils] WARNING: No alembic.ini found in ${app_dir} — skipping migrations"
    return 0
  fi

  # Set DB connection string for Alembic (respect existing env if set)
  export PG_HOST PG_PORT PG_USER PG_NAME PG_PASSWORD

  local alembic_dir
  if [ -f "${app_dir}/alembic.ini" ]; then
    alembic_dir="$app_dir"
  else
    alembic_dir="${app_dir}/alembic"
  fi

  cd "$alembic_dir" || cd "$app_dir" || {
    echo "[db-utils] ERROR: Cannot cd to migration directory" >&2
    return 1
  }

  alembic upgrade head 2>&1 || {
    local rc=$?
    echo "[db-utils] ERROR: Alembic migration failed (exit code $rc)" >&2
    return $rc
  }

  echo "[db-utils] Migrations complete"
}

# ── List available backups with metadata ──
# Usage: list_backups [--json]
list_backups() {
  local json_output=false
  if [ "${1:-}" = "--json" ]; then
    json_output=true
  fi

  if [ ! -d "$BACKUP_DIR" ]; then
    if [ "$json_output" = true ]; then
      echo '[]'
    else
      echo "[db-utils] No backups directory found at ${BACKUP_DIR}"
    fi
    return 0
  fi

  local backup_files=()
  while IFS= read -r -d '' f; do
    backup_files+=("$f")
  done < <(find "$BACKUP_DIR" -maxdepth 1 -name '*.dump' -type f -printf '%T@ %p\0' | sort -rz)

  if [ ${#backup_files[@]} -eq 0 ]; then
    if [ "$json_output" = true ]; then
      echo '[]'
    else
      echo "[db-utils] No backups found in ${BACKUP_DIR}"
    fi
    return 0
  fi

  if [ "$json_output" = true ]; then
    local first=true
    echo -n '['
    for entry in "${backup_files[@]}"; do
      local file="${entry#* }"  # strip timestamp prefix
      local ts="${entry%% *}"
      local size
      size=$(stat --format=%s "$file" 2>/dev/null || echo 0)
      local name
      name=$(basename "$file")
      if [ "$first" = true ]; then
        first=false
      else
        echo -n ','
      fi
      printf '{"file":"%s","size":%d,"timestamp":%d,"name":"%s"}' "$file" "$size" "${ts%.*}" "$name"
    done
    echo ']'
  else
    echo "[db-utils] Backups in ${BACKUP_DIR}:"
    local idx=0
    for entry in "${backup_files[@]}"; do
      local file="${entry#* }"
      local name
      name=$(basename "$file")
      local size
      size=$(du -h "$file" | cut -f1)
      local mtime
      mtime=$(stat --format='%y' "$file" | cut -d. -f1)
      idx=$((idx + 1))
      printf "  %2d. %-45s  %8s  %s\n" "$idx" "$name" "$size" "$mtime"
    done
  fi
}

# ── Prune old backups, keeping only the N most recent ──
# Usage: prune_backups [keep_count]
prune_backups() {
  local keep="${1:-$RETENTION_COUNT}"

  if [ ! -d "$BACKUP_DIR" ]; then
    return 0
  fi

  local count
  count=$(find "$BACKUP_DIR" -maxdepth 1 -name '*.dump' -type f | wc -l)

  if [ "$count" -le "$keep" ]; then
    return 0
  fi

  local to_remove=$((count - keep))
  echo "[db-utils] Pruning ${to_remove} old backup(s), keeping ${keep}..."

  find "$BACKUP_DIR" -maxdepth 1 -name '*.dump' -type f -printf '%T@ %p\0' \
    | sort -z \
    | head -z -n "$to_remove" \
    | while IFS= read -r -d '' entry; do
        local file="${entry#* }"
        echo "  Removing: $(basename "$file")"
        rm -f "$file"
      done

  echo "[db-utils] Pruning complete — $(find "$BACKUP_DIR" -maxdepth 1 -name '*.dump' -type f | wc -l) backup(s) remaining"
}

# ── If invoked directly as a script (not sourced), dispatch subcommands ──
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  load_env "${OPENCPO_ENV:-}"
  case "${1:-}" in
    backup)
      db_backup "${2:-}"
      ;;
    restore)
      shift
      db_restore "$@"
      ;;
    migrate|migrations)
      shift
      run_migrations "$@"
      ;;
    list|ls)
      shift
      list_backups "${1:-}"
      ;;
    prune)
      shift
      prune_backups "${1:-$RETENTION_COUNT}"
      ;;
    *)
      echo "Usage: $0 <command> [args]"
      echo ""
      echo "Commands:"
      echo "  backup [path]          Create a database backup"
      echo "  restore <file>         Restore from a backup file"
      echo "  migrate [app_dir]      Run Alembic migrations"
      echo "  list [--json]          List available backups"
      echo "  prune [keep=N]         Remove old backups, keep N most recent"
      exit 1
      ;;
  esac
fi

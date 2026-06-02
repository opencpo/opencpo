#!/usr/bin/env bash
# update.sh — OpenCPO Self-Update v0.4.0
#
# Fetches the latest release from GitHub, backs up the database,
# preserves .env and Docker volumes, rebuilds changed images,
# runs migrations, and restarts services.
#
# Usage:
#   ./update.sh                          update to latest release
#   ./update.sh v0.4.0                   update to a specific version
#   ./update.sh --status                 show current + latest version
#   ./update.sh --status --json          JSON output for API consumption
#   ./update.sh --check                  check if an update is available
#   ./update.sh --backup                 only back up the DB, skip update
#   ./update.sh --restore <file>         restore from a backup file
#   ./update.sh --list-backups           list available backups
#   ./update.sh --list-backups --json    list available backups (JSON)
#
# Called from core's admin API or directly from the CLI.

set -euo pipefail

# ── Constants ──
REPO="opencpo/opencpo"
INSTALL_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION_FILE="$INSTALL_DIR/version.txt"
ENV_FILE="$INSTALL_DIR/.env"
DOCKER_COMPOSE="$INSTALL_DIR/docker-compose.yml"
BACKUP_DIR="${INSTALL_DIR}/backups"
RETENTION_COUNT=5

# ── Source DB utilities ──
DB_UTILS="${INSTALL_DIR}/scripts/db-utils.sh"
if [ -f "$DB_UTILS" ]; then
  # shellcheck source=scripts/db-utils.sh
  source "$DB_UTILS"
else
  # Inline minimal functions if db-utils.sh is missing (should not happen)
  db_backup()   { echo "[update] ERROR: db-utils.sh not found" >&2; return 1; }
  db_restore()  { echo "[update] ERROR: db-utils.sh not found" >&2; return 1; }
  run_migrations() { echo "[update] ERROR: db-utils.sh not found" >&2; return 1; }
  list_backups()   { echo "[update] ERROR: db-utils.sh not found" >&2; return 1; }
  prune_backups()  { echo "[update] ERROR: db-utils.sh not found" >&2; return 1; }
  load_env()       { :; }
fi

# ── Colors (honors NO_COLOR) ──
if [ -n "${NO_COLOR:-}" ] || [ ! -t 1 ]; then
  RED='' GREEN='' CYAN='' YELLOW='' BOLD='' DIM='' NC=''
else
  printf -v RED   "\033[0;31m"
  printf -v GREEN "\033[0;32m"
  printf -v CYAN  "\033[0;36m"
  printf -v YELLOW "\033[1;33m"
  printf -v BOLD  "\033[1m"
  printf -v DIM   "\033[2m"
  printf -v NC    "\033[0m"
fi

# ── Output helpers ──
info()  { echo -e "${CYAN}  ->${NC} $1"; }
ok()    { echo -e "${GREEN}  v${NC} $1"; }
warn()  { echo -e "${YELLOW}  !${NC} $1"; }
fail()  { echo -e "${RED}  x${NC} $1"; }

# JSON output mode: all output goes to stderr, only JSON goes to stdout
JSON_OUTPUT=false

# ── Semver comparison ──
# Returns: -1 if v1 < v2, 0 if v1 == v2, 1 if v1 > v2
semver_compare() {
  local v1="$1" v2="$2"
  v1="${v1#v}"; v2="${v2#v}"
  local IFS=.
  local a=($v1) b=($v2)
  for i in 0 1 2; do
    if [ "${a[$i]:-0}" -lt "${b[$i]:-0}" ]; then echo -1; return; fi
    if [ "${a[$i]:-0}" -gt "${b[$i]:-0}" ]; then echo 1; return; fi
  done
  echo 0
}

# ── Read current version ──
current_version() {
  if [ -f "$VERSION_FILE" ]; then
    cat "$VERSION_FILE"
  else
    echo "unknown"
  fi
}

# ── Fetch latest version from GitHub ──
latest_version() {
  local tag
  tag=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null \
        | grep -o '"tag_name": "[^"]*"' | cut -d'"' -f4 || echo "")
  if [ -z "$tag" ]; then
    # Fallback: try tags endpoint
    tag=$(curl -fsSL "https://api.github.com/repos/${REPO}/git/refs/tags" 2>/dev/null \
          | grep -o '"ref": "refs/tags/[^"]*"' | tail -1 | sed 's/.*tags\///;s/"//' || echo "")
  fi
  echo "${tag:-unknown}"
}

# ── Validate version format (vMAJOR.MINOR.PATCH) ──
valid_version() {
  [[ "$1" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

# ── Fetch release notes from GitHub ──
fetch_changelog() {
  local version="$1"
  local max_len="${2:-2000}"
  curl -fsSL "https://api.github.com/repos/${REPO}/releases/tags/${version}" 2>/dev/null \
    | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    body = d.get('body', '')
    if len(body) > $max_len:
        body = body[:$max_len] + '\n\n... (truncated)'
    print(body)
except Exception:
    print('(release notes unavailable)')
" 2>/dev/null || echo "(could not fetch release notes)"
}

# ── Load .env for DB credentials ──
load_env_file() {
  if [ -f "$ENV_FILE" ]; then
    set -a
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    set +a
  fi
}

# ── Header display ──
header() {
  echo ""
  printf '%s\n' "${CYAN}╭─────────────────────────────────────────────────────────────────╮${NC}"
  printf '%s\n' "${CYAN}│${NC}  ${BOLD}$1${NC}"
  printf '%s\n' "${CYAN}╰─────────────────────────────────────────────────────────────────╯${NC}"
  echo ""
}

# ╔═════════════════════════════════════════════════════════════════════════╗
# ║  ARGUMENT PARSING                                                      ║
# ╚═════════════════════════════════════════════════════════════════════════╝

MODE="update"  # update, status, check, backup, restore, list-backups
RESTORE_FILE=""
TARGET=""

# Parse arguments: --json can appear anywhere
ARGS=("$@")
for arg in "${ARGS[@]}"; do
  if [ "$arg" = "--json" ]; then
    JSON_OUTPUT=true
  fi
done

# Filter --json out and parse remaining args
FILTERED_ARGS=()
for arg in "${ARGS[@]}"; do
  if [ "$arg" = "--json" ]; then
    continue
  fi
  FILTERED_ARGS+=("$arg")
done

if [ ${#FILTERED_ARGS[@]} -ge 1 ]; then
  case "${FILTERED_ARGS[0]}" in
    --status)
      MODE="status"
      ;;
    --check)
      MODE="check"
      ;;
    --backup)
      MODE="backup"
      ;;
    --restore)
      MODE="restore"
      if [ ${#FILTERED_ARGS[@]} -lt 2 ]; then
        fail "Usage: $0 --restore <backup_file>"
        exit 1
      fi
      RESTORE_FILE="${FILTERED_ARGS[1]}"
      ;;
    --list-backups)
      MODE="list-backups"
      ;;
    --help|-h)
      echo "OpenCPO Update Script v0.4.0"
      echo ""
      echo "Usage:"
      echo "  $0                          Update to latest release"
      echo "  $0 v0.4.0                   Update to a specific version"
      echo "  $0 --status                 Show current + latest version"
      echo "  $0 --status --json          JSON output for API consumption"
      echo "  $0 --check                  Check if update is available"
      echo "  $0 --backup                 Only back up the DB, skip update"
      echo "  $0 --restore <file>         Restore from a backup file"
      echo "  $0 --list-backups           List available backups"
      echo "  $0 --list-backups --json    List available backups (JSON)"
      echo "  $0 --help                   Show this help"
      exit 0
      ;;
    v*)
      TARGET="${FILTERED_ARGS[0]}"
      ;;
    *)
      fail "Unknown argument: ${FILTERED_ARGS[0]}"
      echo "Run '$0 --help' for usage information."
      exit 1
      ;;
  esac
fi

# ╔═════════════════════════════════════════════════════════════════════════╗
# ║  MODE: status                                                          ║
# ╚═════════════════════════════════════════════════════════════════════════╝

if [ "$MODE" = "status" ]; then
  CURRENT=$(current_version)
  LATEST=$(latest_version)
  NEEDS_UPDATE=false
  if [ "$CURRENT" != "unknown" ] && [ "$LATEST" != "unknown" ]; then
    cmp=$(semver_compare "$CURRENT" "$LATEST")
    if [ "$cmp" -lt 0 ]; then
      NEEDS_UPDATE=true
    fi
  fi

  if [ "$JSON_OUTPUT" = true ]; then
    cat <<EOF
{"current":"$CURRENT","latest":"$LATEST","needs_update":$NEEDS_UPDATE}
EOF
  else
    echo "Current version: $CURRENT"
    echo "Latest version:  $LATEST"
    if [ "$LATEST" = "unknown" ]; then
      echo "Status: unable to check — no internet?"
      exit 2
    elif [ "$NEEDS_UPDATE" = false ]; then
      echo "Status: ✅ up to date"
      exit 0
    else
      echo "Status: 🔄 update available"
      exit 1
    fi
  fi
  exit 0
fi

# ╔═════════════════════════════════════════════════════════════════════════╗
# ║  MODE: check                                                           ║
# ╚═════════════════════════════════════════════════════════════════════════╝

if [ "$MODE" = "check" ]; then
  CURRENT=$(current_version)
  LATEST=$(latest_version)
  NEEDS_UPDATE=false
  if [ "$CURRENT" != "unknown" ] && [ "$LATEST" != "unknown" ]; then
    cmp=$(semver_compare "$CURRENT" "$LATEST")
    if [ "$cmp" -lt 0 ]; then
      NEEDS_UPDATE=true
    fi
  fi

  if [ "$JSON_OUTPUT" = true ]; then
    cat <<EOF
{"current":"$CURRENT","latest":"$LATEST","needs_update":$NEEDS_UPDATE}
EOF
  else
    if [ "$NEEDS_UPDATE" = true ]; then
      echo "Update available: $CURRENT → $LATEST"
      exit 0
    else
      echo "Already up to date ($CURRENT)"
      exit 0
    fi
  fi
  exit 0
fi

# ╔═════════════════════════════════════════════════════════════════════════╗
# ║  MODE: backup (standalone)                                             ║
# ╚═════════════════════════════════════════════════════════════════════════╝

if [ "$MODE" = "backup" ]; then
  load_env_file
  header "Database Backup"
  mkdir -p "$BACKUP_DIR"
  CURRENT=$(current_version)
  backup_path=$(db_backup "${BACKUP_DIR}/opencpo-${CURRENT}-$(date +%Y%m%d-%H%M%S).dump")
  if [ "$JSON_OUTPUT" = true ]; then
    cat <<EOF
{"status":"ok","backup_file":"$backup_path"}
EOF
  else
    ok "Backup saved: $backup_path"
  fi
  prune_backups "$RETENTION_COUNT"
  exit 0
fi

# ╔═════════════════════════════════════════════════════════════════════════╗
# ║  MODE: restore                                                         ║
# ╚═════════════════════════════════════════════════════════════════════════╝

if [ "$MODE" = "restore" ]; then
  load_env_file
  header "Database Restore"

  if [ ! -f "$RESTORE_FILE" ]; then
    fail "Backup file not found: $RESTORE_FILE"
    exit 1
  fi

  # Confirm unless AUTO_CONFIRM is set
  if [ -z "${AUTO_CONFIRM:-}" ] && [ -z "${AUTO:-}" ]; then
    echo ""
    echo "  ${BOLD}Restore:${NC} ${RESTORE_FILE}"
    echo "  ${YELLOW}⚠ WARNING: This will OVERWRITE the current database!${NC}"
    echo -n "  ${CYAN}Proceed?${NC} [y/N] "
    read -r REPLY
    if [ "$REPLY" != "y" ] && [ "$REPLY" != "Y" ]; then
      warn "Restore cancelled"
      exit 0
    fi
  fi

  db_restore "$RESTORE_FILE" && ok "Restore complete" || {
    fail "Restore failed"
    exit 1
  }
  exit 0
fi

# ╔═════════════════════════════════════════════════════════════════════════╗
# ║  MODE: list-backups                                                    ║
# ╚═════════════════════════════════════════════════════════════════════════╝

if [ "$MODE" = "list-backups" ]; then
  JSON_FLAG=""
  if [ "$JSON_OUTPUT" = true ]; then
    JSON_FLAG="--json"
  fi
  list_backups $JSON_FLAG
  exit 0
fi

# ╔═════════════════════════════════════════════════════════════════════════╗
# ║  MODE: update                                                          ║
# ╚═════════════════════════════════════════════════════════════════════════╝

load_env_file

# ── Determine target version ──
if [ -z "$TARGET" ]; then
  info "Fetching latest release..."
  TARGET=$(latest_version)
  if [ "$TARGET" = "unknown" ]; then
    fail "Could not determine latest version — check internet connection"
    exit 1
  fi
  ok "Latest: $TARGET"
fi

if ! valid_version "$TARGET"; then
  fail "Invalid version format: $TARGET (expected vMAJOR.MINOR.PATCH)"
  exit 1
fi

CURRENT=$(current_version)
if [ "$CURRENT" = "$TARGET" ]; then
  ok "Already at $TARGET — nothing to do"
  exit 0
fi

# Only proceed if target is actually newer
if [ "$CURRENT" != "unknown" ]; then
  cmp=$(semver_compare "$CURRENT" "$TARGET")
  if [ "$cmp" -ge 0 ]; then
    warn "Requested version $TARGET is not newer than current $CURRENT"
    if [ -z "${AUTO_CONFIRM:-}" ] && [ -z "${AUTO:-}" ]; then
      echo -n "  ${CYAN}Proceed anyway?${NC} [y/N] "
      read -r REPLY
      if [ "$REPLY" != "y" ] && [ "$REPLY" != "Y" ]; then
        warn "Update cancelled"
        exit 0
      fi
    fi
  fi
fi

# ── Confirm ──
if [ -z "${AUTO_CONFIRM:-}" ] && [ -z "${AUTO:-}" ]; then
  echo ""
  echo "  ${BOLD}Update:${NC} ${DIM}$CURRENT${NC} → ${BOLD}$TARGET${NC}"
  echo -n "  ${CYAN}Proceed?${NC} [Y/n] "
  read -r REPLY
  if [ -n "$REPLY" ] && [ "$REPLY" != "y" ] && [ "$REPLY" != "Y" ]; then
    warn "Update cancelled"
    exit 0
  fi
fi

# ── Changelog display ──
header "What's new in $TARGET"
info "Fetching release notes..."
fetch_changelog "$TARGET"
echo ""

# ╔═════════════════════════════════════════════════════════════════════════╗
# ║  STEP 1: Database backup                                               ║
# ╚═════════════════════════════════════════════════════════════════════════╝

header "Step 1: Database Backup"

mkdir -p "$BACKUP_DIR"
BACKUP_FILE="${BACKUP_DIR}/opencpo-${CURRENT}-$(date +%Y%m%d-%H%M%S).dump"
BACKUP_DONE=false

info "Backing up database before update..."

# Strategy 1: pg_dump via docker compose exec into container, then copy out
if docker compose ps postgres 2>/dev/null | grep -q "(healthy)"; then
  TMP_CONTAINER_DUMP="/tmp/opencpo-backup-$(date +%s).dump"

  if docker compose exec -T postgres pg_dump \
    -U "${POSTGRES_USER:-ocpp}" \
    -d "${POSTGRES_DB:-ocpp}" \
    --format=custom \
    -f "$TMP_CONTAINER_DUMP" 2>/dev/null; then

    # Copy the dump from container to host
    if docker compose cp "postgres:${TMP_CONTAINER_DUMP}" "$BACKUP_FILE" 2>/dev/null; then
      docker compose exec -T postgres rm -f "$TMP_CONTAINER_DUMP" 2>/dev/null || true
      if [ -s "$BACKUP_FILE" ]; then
        ok "Backup saved: ${BACKUP_FILE} ($(du -h "$BACKUP_FILE" | cut -f1))"
        BACKUP_DONE=true
      fi
    fi
  fi
fi

# Strategy 2: direct pg_dump if available (fallback)
if [ "$BACKUP_DONE" = false ]; then
  if command -v pg_dump &>/dev/null; then
    info "Trying direct pg_dump (host)..."

    # Determine pg connection parameters
    PG_HOST_DIRECT="${PG_HOST:-localhost}"
    PG_PORT_DIRECT="${PG_PORT:-5432}"
    # If the host is 'postgres' (docker service name), try localhost
    if [ "$PG_HOST_DIRECT" = "postgres" ]; then
      PG_HOST_DIRECT="localhost"
    fi

    if PGPASSWORD="${POSTGRES_PASSWORD:-ocpp}" pg_dump \
      -h "$PG_HOST_DIRECT" \
      -p "$PG_PORT_DIRECT" \
      -U "${POSTGRES_USER:-ocpp}" \
      -d "${POSTGRES_DB:-ocpp}" \
      --format=custom \
      -f "$BACKUP_FILE" 2>/dev/null; then
      if [ -s "$BACKUP_FILE" ]; then
        ok "Backup saved directly: ${BACKUP_FILE} ($(du -h "$BACKUP_FILE" | cut -f1))"
        BACKUP_DONE=true
      fi
    fi
  fi
fi

# Strategy 3: use the pg_dump from inside the postgres container via docker exec
if [ "$BACKUP_DONE" = false ]; then
  if docker ps 2>/dev/null | grep -q "postgres"; then
    info "Trying docker exec pg_dump (direct container access)..."
    PG_CONTAINER_ID=$(docker ps --filter "name=postgres" --format '{{.ID}}' | head -1)
    if [ -n "$PG_CONTAINER_ID" ]; then
      if docker exec "$PG_CONTAINER_ID" pg_dump \
        -U "${POSTGRES_USER:-ocpp}" \
        -d "${POSTGRES_DB:-ocpp}" \
        --format=custom \
        -f "/tmp/backup-final.dump" 2>/dev/null; then
        if docker cp "${PG_CONTAINER_ID}:/tmp/backup-final.dump" "$BACKUP_FILE" 2>/dev/null; then
          docker exec "$PG_CONTAINER_ID" rm -f /tmp/backup-final.dump 2>/dev/null || true
          if [ -s "$BACKUP_FILE" ]; then
            ok "Backup saved via docker exec: ${BACKUP_FILE} ($(du -h "$BACKUP_FILE" | cut -f1))"
            BACKUP_DONE=true
          fi
        fi
      fi
    fi
  fi
fi

if [ "$BACKUP_DONE" = false ]; then
  warn "Could not back up database — continuing without backup (update only, no rollback possible)"
  BACKUP_FILE=""
else
  prune_backups "$RETENTION_COUNT"
fi

# ╔═════════════════════════════════════════════════════════════════════════╗
# ║  STEP 2: Backup .env                                                   ║
# ╚═════════════════════════════════════════════════════════════════════════╝

header "Step 2: Environment Backup"
if [ -f "$ENV_FILE" ]; then
  cp "$ENV_FILE" "$ENV_FILE.update-bak"
  ok ".env backed up to .env.update-bak"
else
  warn "No .env found — will create if needed"
fi

# ╔═════════════════════════════════════════════════════════════════════════╗
# ║  STEP 3: Download new release                                          ║
# ╚═════════════════════════════════════════════════════════════════════════╝

header "Step 3: Downloading $TARGET"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

TAR_URL="https://github.com/${REPO}/archive/refs/tags/${TARGET}.tar.gz"
info "Downloading from ${TAR_URL} ..."

for attempt in 1 2 3; do
  code=$(curl -fsSL -w "%{http_code}" "$TAR_URL" -o "$TMPDIR/release.tar.gz" 2>/dev/null || echo "000")
  if [ -s "$TMPDIR/release.tar.gz" ] && [ "$code" != "000" ]; then
    ok "Downloaded (attempt $attempt)"
    break
  fi
  if [ "$attempt" -lt 3 ]; then
    warn "Retrying (attempt $attempt/3)..."
    sleep 2
  else
    fail "Download failed after 3 attempts"
    rm -rf "$TMPDIR"
    exit 1
  fi
done

# ╔═════════════════════════════════════════════════════════════════════════╗
# ║  STEP 4: Extract                                                       ║
# ╚═════════════════════════════════════════════════════════════════════════╝

header "Step 4: Extracting"
EXTRACT_DIR="$TMPDIR/extract"
mkdir -p "$EXTRACT_DIR"
tar -xzf "$TMPDIR/release.tar.gz" -C "$EXTRACT_DIR"

# Find the extracted repo root
SRC_DIR=""
for candidate in "$EXTRACT_DIR"/*/; do
  if [ -f "${candidate}install.sh" ] || [ -f "${candidate}setup.sh" ] || [ -f "${candidate}docker-compose.yml" ]; then
    SRC_DIR="${candidate%/}"
    break
  fi
done

if [ -z "$SRC_DIR" ] || [ ! -d "$SRC_DIR" ]; then
  fail "Extraction failed — no valid opencpo directory found"
  rm -rf "$TMPDIR"
  exit 1
fi
ok "Extracted to temporary directory"

# ╔═════════════════════════════════════════════════════════════════════════╗
# ║  STEP 5: Copy new files (preserve .env)                                ║
# ╚═════════════════════════════════════════════════════════════════════════╝

header "Step 5: Updating files"

# Remove old update.sh (we'll overwrite it)
rm -f "$INSTALL_DIR/update.sh"

# Copy new files
cp -r "$SRC_DIR"/* "$INSTALL_DIR/" 2>/dev/null || true

# Restore .env
if [ -f "$ENV_FILE.update-bak" ]; then
  cp "$ENV_FILE.update-bak" "$ENV_FILE"
  ok ".env restored"
fi

# Write new version
echo "$TARGET" > "$VERSION_FILE"
chmod +x "$INSTALL_DIR/update.sh" 2>/dev/null || true
chmod +x "$INSTALL_DIR/scripts/db-utils.sh" 2>/dev/null || true
ok "Files updated to $TARGET"

# ╔═════════════════════════════════════════════════════════════════════════╗
# ║  STEP 6: Run database migrations                                       ║
# ╚═════════════════════════════════════════════════════════════════════════╝

header "Step 6: Running database migrations"

MIGRATION_OK=false
cd "$INSTALL_DIR"

# Try via docker compose exec into core container
if docker compose ps ocpp-core 2>/dev/null | grep -q "(healthy)"; then
  info "Running migrations in ocpp-core container..."
  if docker compose exec -T ocpp-core bash -c "
    export PG_HOST=postgres
    export PG_PORT=5432
    export PG_NAME='${POSTGRES_DB:-ocpp}'
    export PG_USER='${POSTGRES_USER:-ocpp}'
    export PG_PASSWORD='${POSTGRES_PASSWORD:-ocpp}'
    cd /app 2>/dev/null || cd /app/opencpo 2>/dev/null || true
    alembic upgrade head 2>&1
  "; then
    MIGRATION_OK=true
    ok "Database migrations completed successfully"
  else
    warn "Migration via container exec failed — trying as standalone..."
  fi
fi

# Fallback: run migrations directly if alembic is available
if [ "$MIGRATION_OK" = false ]; then
  if command -v alembic &>/dev/null; then
    info "Running migrations directly..."
    if run_migrations "$INSTALL_DIR/opencpo-core" 2>&1; then
      MIGRATION_OK=true
      ok "Database migrations completed successfully"
    fi
  fi
fi

# If migration failed, attempt rollback
if [ "$MIGRATION_OK" = false ]; then
  warn "Migration failed! Attempting rollback..."

  # Restore the backup if we have one
  if [ -n "${BACKUP_FILE:-}" ] && [ -f "$BACKUP_FILE" ]; then
    info "Restoring database from backup: ${BACKUP_FILE}"
    db_restore "$BACKUP_FILE" && ok "Database restored from backup" || {
      fail "Restore from backup also failed — manual intervention required!"
      echo ""
      echo "  Backup file: ${BACKUP_FILE}"
      echo "  .env backup: ${ENV_FILE}.update-bak"
      echo ""
      echo "  To restore manually:"
      echo "    pg_restore -U ${POSTGRES_USER:-ocpp} -d ${POSTGRES_DB:-ocpp} --clean --if-exists '${BACKUP_FILE}'"
      exit 1
    }
  else
    fail "No backup available to restore from — migrations failed, database may be in an inconsistent state"
    exit 1
  fi

  fail "Update rolled back due to migration failure"
  exit 1
fi

# ╔═════════════════════════════════════════════════════════════════════════╗
# ║  STEP 7: Rebuild and restart                                           ║
# ╚═════════════════════════════════════════════════════════════════════════╝

header "Step 7: Rebuilding containers"

if [ ! -f "$DOCKER_COMPOSE" ]; then
  fail "docker-compose.yml not found — cannot rebuild"
  exit 1
fi

info "Building images..."
docker compose build 2>&1 || {
  warn "Docker build had warnings (continuing)..."
}

info "Starting services..."
docker compose up -d 2>&1 || {
  fail "Docker compose up failed"
  exit 1
}

# ╔═════════════════════════════════════════════════════════════════════════╗
# ║  STEP 8: Verify                                                        ║
# ╚═════════════════════════════════════════════════════════════════════════╝

header "Step 8: Verifying"
sleep 5
HEALTHY=true
for svc in ocpp-core cpo-admin; do
  if docker compose ps "$svc" 2>/dev/null | grep -q "(healthy)"; then
    ok "$svc — healthy"
  else
    warn "$svc — status unknown (may still be starting)"
    HEALTHY=false
  fi
done

# ── Clean up backup ──
rm -f "$ENV_FILE.update-bak"

echo ""
if [ "$HEALTHY" = true ]; then
  echo -e "${GREEN}  ✅ Update complete — $TARGET is live${NC}"
else
  echo -e "${YELLOW}  ⚠️  Update applied — check service status with: docker compose ps${NC}"
fi
echo ""

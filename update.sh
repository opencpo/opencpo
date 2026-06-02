#!/usr/bin/env bash
# update.sh — OpenCPO Self-Update
#
# Fetches the latest release from GitHub, preserves .env and Docker
# volumes, rebuilds changed images, and restarts services.
#
# Usage:
#   ./update.sh                    # update to latest release
#   ./update.sh v0.2.10            # update to a specific version
#   ./update.sh --check            # just check what version is available
#   ./update.sh --status           # print current + latest version, exit 0/1
#
# Called from core's admin API or directly from the CLI.

set -euo pipefail

REPO="opencpo/opencpo"
INSTALL_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION_FILE="$INSTALL_DIR/version.txt"
ENV_FILE="$INSTALL_DIR/.env"
DOCKER_COMPOSE="$INSTALL_DIR/docker-compose.yml"

# ── Colors (honors NO_COLOR) ──
if [ -n "${NO_COLOR:-}" ] || [ ! -t 1 ] || [ "${1:-}" = "--json" ]; then
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
info()  { echo -e "${CYAN}  ->${NC} $1"; }
ok()    { echo -e "${GREEN}  v${NC} $1"; }
warn()  { echo -e "${YELLOW}  !${NC} $1"; }
fail()  { echo -e "${RED}  x${NC} $1"; }

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

# ── Check mode ──
if [ "${1:-}" = "--check" ] || [ "${1:-}" = "--status" ]; then
  CURRENT=$(current_version)
  LATEST=$(latest_version)
  NEEDS_UPDATE=false
  if [ "$CURRENT" != "unknown" ] && [ "$LATEST" != "unknown" ] && [ "$CURRENT" != "$LATEST" ]; then
    NEEDS_UPDATE=true
  fi

  if [ "${1:-}" = "--json" ] || [ -n "${JSON_OUTPUT:-}" ]; then
    cat <<EOF
{"current":"$CURRENT","latest":"$LATEST","needs_update":$NEEDS_UPDATE}
EOF
  else
    echo "Current version: $CURRENT"
    echo "Latest version:  $LATEST"
    if [ "$LATEST" = "unknown" ]; then
      echo "Status: unable to check — no internet?"
      exit 2
    elif [ "$CURRENT" = "$LATEST" ]; then
      echo "Status: ✅ up to date"
      exit 0
    else
      echo "Status: 🔄 update available"
      exit 1
    fi
  fi
  exit 0
fi

# ── Target version ──
TARGET="${1:-}"
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

echo ""
header() {
  echo ""
  printf '%s\n' "${CYAN}╭─────────────────────────────────────────────────────────────────╮${NC}"
  printf '%s\n' "${CYAN}│${NC}  ${BOLD}$1${NC}"
  printf '%s\n' "${CYAN}╰─────────────────────────────────────────────────────────────────╯${NC}"
  echo ""
}

# ── Step 1: Backup .env ──
header "Backup"
if [ -f "$ENV_FILE" ]; then
  cp "$ENV_FILE" "$ENV_FILE.update-bak"
  ok ".env backed up to .env.update-bak"
else
  warn "No .env found — will create if needed"
fi

# ── Step 2: Download new release ──
header "Downloading $TARGET"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

TAR_URL="https://github.com/${REPO}/archive/refs/tags/${TARGET}.tar.gz"
info "Downloading from ${TAR_URL} ..."

for attempt in 1 2 3; do
  curl -fsSL "$TAR_URL" -o "$TMPDIR/release.tar.gz" 2>/dev/null
  if [ -s "$TMPDIR/release.tar.gz" ]; then
    ok "Downloaded ($attempt)"
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

# ── Step 3: Extract ──
header "Extracting"
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

# ── Step 4: Copy new files (preserve .env) ──
header "Updating files"

# Remove old files (except .env, version.txt, backups, Docker volumes)
rm -f "$INSTALL_DIR/install.sh" "$INSTALL_DIR/setup.sh" "$INSTALL_DIR/uninstall.sh" "$INSTALL_DIR/configure.py"
rm -f "$INSTALL_DIR/update.sh"  # we'll overwrite this anyway

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
ok "Files updated to $TARGET"

# ── Step 5: Rebuild and restart ──
header "Rebuilding containers"

if [ ! -f "$DOCKER_COMPOSE" ]; then
  fail "docker-compose.yml not found — cannot rebuild"
  exit 1
fi

cd "$INSTALL_DIR"

info "Building images..."
docker compose build 2>&1 | while IFS= read -r line; do
  echo "  ${DIM}$line${NC}"
done

info "Starting services..."
docker compose up -d 2>&1 | while IFS= read -r line; do
  echo "  ${DIM}$line${NC}"
done

# ── Step 6: Verify ──
header "Verifying"
sleep 3
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

#!/usr/bin/env bash
# uninstall.sh — OpenCPO Removal Script
#
# Usage:
#   ./uninstall.sh              # Interactive (asks for confirmation)
#   ./uninstall.sh --auto       # Non-interactive, no prompts
#   ./uninstall.sh --help       # This message
#
# This script:
#   1. Stops and removes OpenCPO Docker containers
#   2. Removes OpenCPO Docker images
#   3. Removes cloned component repos
#   4. Removes .env and other generated files
#   5. Optionally removes Docker itself

set -euo pipefail

AUTO=0

for arg in "$@"; do
  case "$arg" in
    --auto) AUTO=1 ;;
    --help)
      head -20 "$0" | grep "^#" | sed 's/^#//'
      exit 0
      ;;
  esac
done

# ── Colors (honors NO_COLOR env var) ──
if [ -n "${NO_COLOR:-}" ] || [ ! -t 1 ]; then
  RED='' GREEN='' YELLOW='' CYAN='' BOLD='' DIM='' NC=''
else
  printf -v RED   '\033[0;31m'
  printf -v GREEN '\033[0;32m'
  printf -v YELLOW '\033[1;33m'
  printf -v CYAN  '\033[0;36m'
  printf -v BOLD  '\033[1m'
  printf -v DIM   '\033[2m'
  printf -v NC    '\033[0m'
fi

info()  { echo -e "${CYAN}  ->${NC} $1"; }
ok()    { echo -e "${GREEN}  v${NC} $1"; }
warn()  { echo -e "${YELLOW}  !${NC} $1"; }
fail()  { echo -e "${RED}  x${NC} $1"; }

confirm() {
  if [ "$AUTO" = "1" ]; then return 0; fi
  local prompt="${1:-Continue?} [y/N] "
  read -r -p "$prompt" response
  case "$response" in
    [yY]|[yY][eE][sS]) return 0 ;;
    *) return 1 ;;
  esac
}

# Determine the OpenCPO root directory (where this script lives)
OPENCPO_DIR="$(cd "$(dirname "$0")" && pwd)"

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}  ${BOLD}OpenCPO — Uninstall${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${DIM}This will remove OpenCPO from:${NC}"
echo -e "  ${DIM}  $OPENCPO_DIR${NC}"
echo ""

confirm "Remove OpenCPO?" || {
  echo ""
  info "Cancelled."
  exit 0
}

# ── 1. Stop and remove Docker containers ──
header() {
  echo ""
  echo -e "${CYAN}  ---${NC} $1"
}

RUNNING=0
DOCKER_CMD="docker compose"
if docker compose ps &>/dev/null 2>&1; then
  RUNNING=1
elif sudo docker compose ps &>/dev/null 2>&1; then
  RUNNING=1
  DOCKER_CMD="sudo docker compose"
fi

if [ "$RUNNING" = "1" ]; then
  header "Stopping Docker containers"
  if $DOCKER_CMD down -v 2>/dev/null; then
    ok "Containers stopped and volumes removed"
  else
    warn "No containers to stop"
  fi

  header "Removing OpenCPO Docker images"
  # Remove images built from local component directories
  IMAGES=$($DOCKER_CMD images 2>/dev/null | grep -E "opencpo" | awk '{print $3}' || true)
  if [ -n "$IMAGES" ]; then
    # shellcheck disable=SC2086
    docker rmi -f $IMAGES 2>/dev/null || sudo docker rmi -f $IMAGES 2>/dev/null || true
    ok "Docker images removed"
  else
    info "No OpenCPO Docker images found"
  fi
else
  info "No running OpenCPO containers"
fi

# ── 2. Remove cloned component repos ──
header "Removing component repos"
COMPONENTS_REMOVED=0
COMPONENTS=(
  opencpo-core
  opencpo-admin
  opencpo-charge-app
  opencpo-tester
  opencpo-charger-farm
)
for repo in "${COMPONENTS[@]}"; do
  if [ -d "$OPENCPO_DIR/$repo" ]; then
    rm -rf "$OPENCPO_DIR/$repo"
    COMPONENTS_REMOVED=1
  fi
done
if [ "$COMPONENTS_REMOVED" = "1" ]; then
  ok "Component repos removed"
else
  info "No component repos found"
fi

# ── 3. Remove generated files ──
header "Removing generated files"
for f in .env .env.bak .python-version; do
  if [ -f "$OPENCPO_DIR/$f" ]; then
    rm -f "$OPENCPO_DIR/$f"
    ok "Removed $f"
  fi
done

# ── 4. Remove this script ──
header "Removing uninstaller"
rm -f "$0"
ok "Removed uninstall.sh"

# ── Done ──
echo ""
echo -e "${GREEN}  v OpenCPO has been removed from:${NC}"
echo "    $OPENCPO_DIR"
echo ""
echo -e "  ${DIM}Note: Docker, Python, and system packages were NOT removed.${NC}"
echo -e "  ${DIM}To remove Docker:  sudo apt-get purge docker-ce docker-ce-cli containerd.io${NC}"
echo -e "  ${DIM}To remove Python3:  sudo apt-get purge python3${NC}"
echo ""

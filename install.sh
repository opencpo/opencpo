#!/usr/bin/env bash
# install.sh — OpenCPO Bootstrap Installer
#
# One-liner:
#   curl -fsSL https://raw.githubusercontent.com/opencpo/opencpo/main/install.sh | bash
#
# Or download and run:
#   wget -qO- https://raw.githubusercontent.com/opencpo/opencpo/main/install.sh | bash
#
# This script requires ONLY bash and a working internet connection.
# It will download the OpenCPO repo and hand off to setup.sh,
# which handles Python, Docker, Compose, and everything else.
#
# Tested on: Ubuntu, Debian, Fedora, Arch, macOS

set -euo pipefail

REPO="opencpo/opencpo"
BRANCH="main"
# Fetch the current HEAD SHA to bypass GitHub CDN cache on archive download
INSTALLER_SHA=$(curl -fsSL "https://api.github.com/repos/${REPO}/git/refs/heads/${BRANCH}" 2>/dev/null | grep -o '"sha": "[a-f0-9]*"' | head -1 | cut -d'"' -f4 || echo "")
if [ -n "$INSTALLER_SHA" ]; then
  TAR_URL="https://github.com/${REPO}/archive/${INSTALLER_SHA}.tar.gz"
else
  TAR_URL="https://github.com/${REPO}/archive/refs/heads/${BRANCH}.tar.gz"
fi
INSTALL_DIR="${INSTALL_DIR:-opencpo}"

# ── Colors (honors NO_COLOR env var) ──
if [ -n "${NO_COLOR:-}" ] || [ ! -t 1 ]; then
  RED='' GREEN='' YELLOW='' CYAN='' BOLD='' DIM='' NC=''
else
  # printf -v stores actual ESC bytes, not literal \033
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

banner() {
  printf '\n'
  printf '%s\n' "${CYAN}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
  printf '%s\n' "${CYAN}║${NC}                                                                         ${CYAN}║${NC}"
  printf '%s\n' "${CYAN}║${NC}               ____                    _____ _____   ____                 ${CYAN}║${NC}"
  printf '%s\n' "${CYAN}║${NC}              / __ \                  / ____|  __ \ / __ \                ${CYAN}║${NC}"
  printf '%s\n' "${CYAN}║${NC}             | |  | |_ __   ___ _ __ | |    | |__) | |  | |               ${CYAN}║${NC}"
  printf '%s\n' "${CYAN}║${NC}             | |  | | '_ \ / _ \ '_ \| |    |  ___/| |  | |               ${CYAN}║${NC}"
  printf '%s\n' "${CYAN}║${NC}             | |__| | |_) |  __/ | | | |____| |    | |__| |               ${CYAN}║${NC}"
  printf '%s\n' "${CYAN}║${NC}              \____/| .__/ \___|_| |_|\_____|_|     \____/                ${CYAN}║${NC}"
  printf '%s\n' "${CYAN}║${NC}                    | |                                                   ${CYAN}║${NC}"
  printf '%s\n' "${CYAN}║${NC}                    |_|                                                   ${CYAN}║${NC}"
  printf '%s\n' "${CYAN}║${NC}                                                                         ${CYAN}║${NC}"
  printf '%s\n' "${CYAN}║${NC}          Open Source EV Charging Platform                               ${CYAN}║${NC}"
  printf '%s\n' "${CYAN}║${NC}                                                                         ${CYAN}║${NC}"
  printf '%s\n' "${CYAN}║${NC}       Zero Trust . OCPP 1.6/2.0.1 . ISO 15118 . PKI                    ${CYAN}║${NC}"
  printf '%s\n' "${CYAN}║${NC}                                                                         ${CYAN}║${NC}"
  printf '%s\n' "${CYAN}╚══════════════════════════════════════════════════════════════════════════╝${NC}"
  printf '\n'
}

header() {
  echo ""
  echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║${NC}  $1"
  echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
  echo ""
}

# ── Trap cleanup ──
cleanup() {
  if [ -n "${TMPDIR:-}" ] && [ -d "$TMPDIR" ]; then
    rm -rf "$TMPDIR"
  fi
}
trap cleanup EXIT

# ── Banner ──
banner

# ── Detect OS ──
header "System"

OS="unknown"
PKG_CMD=""
if [ -f /etc/os-release ]; then
  . /etc/os-release
  case "$ID" in
    ubuntu|debian)     OS="debian"; PKG_CMD="apt-get install -y" ;;
    fedora|rhel|centos) OS="fedora"; PKG_CMD="dnf install -y" ;;
    arch|manjaro)      OS="arch"; PKG_CMD="pacman -S --noconfirm" ;;
    alpine)            OS="alpine"; PKG_CMD="apk add" ;;
  esac
fi
if [ "$(uname)" = "Darwin" ]; then
  OS="macos"
fi
ok "Detected: ${OS^}"

# ── Find download tool ──
header "Tools"

DL_CMD=""
DL_NAME=""
if command -v curl &>/dev/null; then
  DL_CMD="curl -fsSL"
  DL_NAME="curl"
  ok "curl available"
elif command -v wget &>/dev/null; then
  DL_CMD="wget -qO-"
  DL_NAME="wget"
  ok "wget available"
else
  warn "Neither curl nor wget found -- installing curl..."
  case "$OS" in
    debian)
      apt-get update -qq && apt-get install -y -qq curl
      ;;
    fedora)
      dnf install -y curl
      ;;
    arch)
      pacman -S --noconfirm curl
      ;;
    alpine)
      apk add curl
      ;;
    macos)
      if command -v brew &>/dev/null; then
        brew install curl
      else
        fail "Install curl manually: https://curl.se/download.html"
        exit 1
      fi
      ;;
    *)
      fail "No curl or wget available. Install one first."
      exit 1
      ;;
  esac
  DL_CMD="curl -fsSL"
  DL_NAME="curl"
  ok "curl installed"
fi

if ! command -v tar &>/dev/null; then
  warn "tar not found -- installing..."
  case "$OS" in
    debian) apt-get install -y -qq tar ;;
    fedora) dnf install -y tar ;;
    arch)   pacman -S --noconfirm tar ;;
    alpine) apk add tar ;;
    macos)  # tar is built into macOS
    ;;
  esac
fi
ok "tar available"

# ── Download OpenCPO ──
header "Downloading OpenCPO"

TMPDIR=$(mktemp -d)
ARCHIVE="${TMPDIR}/opencpo.tar.gz"

info "Downloading from ${TAR_URL} ..."
# Retry up to 3 times on failure
for attempt in 1 2 3; do
  if [ "$DL_NAME" = "curl" ]; then
    $DL_CMD "$TAR_URL" -o "$ARCHIVE" 2>/dev/null
  else
    $DL_CMD "$TAR_URL" > "$ARCHIVE" 2>/dev/null
  fi
  if [ -s "$ARCHIVE" ]; then break; fi
  if [ "$attempt" -lt 3 ]; then
    warn "Download failed, retrying (attempt $attempt/3)..."
    sleep 2
  fi
done

if [ ! -s "$ARCHIVE" ]; then
  fail "Download failed -- check internet connection"
  exit 1
fi
ok "Downloaded (${DL_NAME})"

# ── Extract ──
header "Extracting"

EXTRACT_DIR="${TMPDIR}/extract"
mkdir -p "$EXTRACT_DIR"
tar -xzf "$ARCHIVE" -C "$EXTRACT_DIR"

SRC_DIR=$(find "$EXTRACT_DIR" -maxdepth 1 -type d | tail -1)

if [ -z "$SRC_DIR" ] || [ ! -d "$SRC_DIR" ]; then
  fail "Extraction failed"
  exit 1
fi

TARGET="${INSTALL_DIR}"
if [ -d "$TARGET" ]; then
  # Clean up Docker volumes/data from previous install
  if [ -f "$TARGET/docker-compose.yml" ]; then
    docker compose -f "$TARGET/docker-compose.yml" down -v 2>/dev/null || \
      sudo docker compose -f "$TARGET/docker-compose.yml" down -v 2>/dev/null || true
  fi
  rm -rf "$TARGET"
  warn "Removed existing '$TARGET' directory"
fi

mv "$SRC_DIR" "$TARGET"
ok "Extracted to $(pwd)/${TARGET}"

# ── Hand off to setup.sh ──
header "Starting Setup"

cd "$TARGET"

if [ ! -f setup.sh ]; then
  fail "setup.sh not found in $TARGET -- download may be corrupted"
  exit 1
fi

chmod +x setup.sh

exec bash setup.sh --auto "$@"

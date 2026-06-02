#!/usr/bin/env bash
# setup.sh — OpenCPO Bootstrap Installer
# Run this ONCE after cloning the repo. It handles:
#   1. Dependency installation (Python, Docker, Compose, Git)
#   2. Component repo cloning
#   3. Configuration wizard (interactive or --auto)
#   4. Docker image building
#
# Usage:
#   ./setup.sh              # Interactive (recommended)
#   ./setup.sh --auto       # All defaults, no prompts
#   ./setup.sh --skip-deps  # Skip dependency checks
#   ./setup.sh --help       # This message

set -euo pipefail

ORG="${ORG:-opencpo}"
BASE_URL="https://github.com/$ORG"
AUTO=0
SKIP_DEPS=0

for arg in "$@"; do
  case "$arg" in
    --auto) AUTO=1 ;;
    --skip-deps) SKIP_DEPS=1 ;;
    --help)
      head -20 "$0" | grep "^#" | sed 's/^#//'
      exit 0
      ;;
  esac
done

# ── Colors ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

info()  { echo -e "${CYAN}  →${NC} $1"; }
ok()    { echo -e "${GREEN}  ✓${NC} $1"; }
warn()  { echo -e "${YELLOW}  ⚠${NC} $1"; }
fail()  { echo -e "${RED}  ✗${NC} $1"; }

banner() {
  echo ""
  echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║${NC}                                                                         ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}               ____                    _____ _____   ____                 ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}              / __ \                  / ____|  __ \ / __ \                ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}             | |  | |_ __   ___ _ __ | |    | |__) | |  | |               ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}             | |  | | '_ \ / _ \ '_ \| |    |  ___/| |  | |               ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}             | |__| | |_) |  __/ | | | |____| |    | |__| |               ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}              \____/| .__/ \___|_| |_|\_____|_|     \____/                ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}                    | |                                                   ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}                    |_|                                                   ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}                                                                         ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}          ⚡ Open Source EV Charging Platform ⚡                          ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}                                                                         ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}       Zero Trust · OCPP 1.6/2.0.1 · ISO 15118 · PKI                    ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}                                                                         ${CYAN}║${NC}"
  echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════╝${NC}"
  echo ""
}

header() {
  echo ""
  echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║${NC}  $1"
  echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
  echo ""
}

confirm() {
  if [ "$AUTO" = "1" ]; then return 0; fi
  local prompt="${1:-Continue?} [Y/n] "
  read -r -p "$prompt" response
  case "$response" in
    [nN]|[nN][oO]) return 1 ;;
    *) return 0 ;;
  esac
}

# ── Banner ─────────────────────────────────────────────────────────────────
banner

# ── Detect OS ──────────────────────────────────────────────────────────────
header "System"

OS="unknown"
PKG_INSTALL=""
if [ -f /etc/os-release ]; then
  . /etc/os-release
  case "$ID" in
    ubuntu|debian)
      OS="debian"
      PKG_INSTALL="apt-get install -y"
      ok "Detected: $NAME $VERSION_ID"
      ;;
    fedora|rhel|centos)
      OS="fedora"
      PKG_INSTALL="dnf install -y"
      ok "Detected: $NAME $VERSION_ID"
      ;;
    arch|manjaro)
      OS="arch"
      PKG_INSTALL="pacman -S --noconfirm"
      ok "Detected: $NAME"
      ;;
    alpine)
      OS="alpine"
      PKG_INSTALL="apk add"
      ok "Detected: Alpine Linux"
      ;;
    *)
      warn "Unknown distro: $ID — will check tools individually"
      ;;
  esac
elif [ "$(uname)" = "Darwin" ]; then
  OS="macos"
  ok "Detected: macOS $(sw_vers -productVersion 2>/dev/null || echo 'unknown')"
fi

# ── Dependency Check / Install ──────────────────────────────────────────────
if [ "$SKIP_DEPS" = "0" ]; then
  header "Dependencies"

  NEED_INSTALL=""
  ALL_OK=1

  # ── git ──
  if command -v git &>/dev/null; then
    ok "git: $(git --version 2>&1 | head -1)"
  else
    fail "git is required"
    NEED_INSTALL="$NEED_INSTALL git"
    ALL_OK=0
  fi

  # ── Python 3 ──
  PYTHON=""
  for cmd in python3 python; do
    if command -v "$cmd" &>/dev/null; then
      VER=$("$cmd" --version 2>&1 | grep -oP '\d+\.\d+' | head -1)
      MAJOR="${VER%%.*}"
      if [ "$MAJOR" -ge 3 ] 2>/dev/null; then
        PYTHON="$cmd"
        break
      fi
    fi
  done

  if [ -n "$PYTHON" ]; then
    ok "python3: $($PYTHON --version 2>&1)"
  else
    fail "Python 3 is required"
    NEED_INSTALL="$NEED_INSTALL python3"
    ALL_OK=0
  fi

  # ── Docker ──
  DOCKER_OK=0
  if command -v docker &>/dev/null; then
    if docker info &>/dev/null 2>&1; then
      ok "Docker: $(docker --version 2>&1)"
      DOCKER_OK=1
    else
      warn "Docker installed but daemon not running (or no socket access)"
      warn "  Try: sudo usermod -aG docker \$USER && newgrp docker"
      ALL_OK=0
    fi
  else
    fail "Docker is required"
    NEED_INSTALL="$NEED_INSTALL docker"
    ALL_OK=0
  fi

  # ── Docker Compose (standalone or plugin) ──
  COMPOSE_OK=0
  if command -v docker-compose &>/dev/null; then
    ok "Docker Compose (standalone): $(docker-compose --version 2>&1)"
    COMPOSE_OK=1
    COMPOSE_CMD="docker-compose"
  elif docker compose version &>/dev/null 2>&1; then
    ok "Docker Compose (plugin): $(docker compose version 2>&1)"
    COMPOSE_OK=1
    COMPOSE_CMD="docker compose"
  else
    fail "Docker Compose is required"
    NEED_INSTALL="$NEED_INSTALL docker-compose"
    ALL_OK=0
  fi

  echo ""

  # ── Auto-install ──
  if [ -n "$NEED_INSTALL" ]; then
    echo -e "${YELLOW}  Missing: $NEED_INSTALL${NC}"
    echo ""

    if [ "$AUTO" = "1" ]; then
      PROCEED="y"
    else
      echo -n "  Install missing dependencies? [Y/n]: "
      read -r PROCEED
      PROCEED="${PROCEED:-y}"
    fi

    if [ "$PROCEED" = "y" ] || [ "$PROCEED" = "Y" ]; then
      if [ "$OS" = "unknown" ] && [ "$(uname)" != "Darwin" ]; then
        warn "Cannot auto-install on unknown OS. Install manually:"
        echo ""
        echo "  Ubuntu/Debian:"
        echo "    sudo apt-get update"
        echo "    sudo apt-get install -y git python3 python3-venv docker.io docker-compose-plugin"
        echo "    sudo usermod -aG docker \$USER"
        echo "    # Then log out and back in"
        echo ""
        echo "  Fedora:"
        echo "    sudo dnf install -y git python3 docker docker-compose-plugin"
        echo ""
        echo "  macOS:"
        echo "    brew install git python docker docker-compose"
        echo ""
        exit 1
      fi

      SUDO=""
      if [ "$(id -u)" -ne 0 ]; then
        if command -v sudo &>/dev/null; then
          SUDO="sudo"
        else
          warn "Need root to install packages. Run with sudo or install manually."
          exit 1
        fi
      fi

      case "$OS" in
        debian)
          info "Installing: git, python3, python3-venv"
          $SUDO apt-get update -qq && $SUDO apt-get install -y -qq git python3 python3-venv

          # Docker via official script (handles repo setup, compose plugin, all deps)
          if ! command -v docker &>/dev/null; then
            info "Installing Docker via official script..."
            if command -v curl &>/dev/null; then
              curl -fsSL https://get.docker.com | $SUDO sh
            elif command -v wget &>/dev/null; then
              wget -qO- https://get.docker.com | $SUDO sh
            else
              $SUDO apt-get install -y -qq curl
              curl -fsSL https://get.docker.com | $SUDO sh
            fi
          elif ! docker compose version &>/dev/null 2>&1 && ! command -v docker-compose &>/dev/null; then
            info "Docker found but Compose missing — installing compose plugin..."
            if command -v curl &>/dev/null; then
              curl -fsSL https://get.docker.com | $SUDO sh
            elif command -v wget &>/dev/null; then
              wget -qO- https://get.docker.com | $SUDO sh
            else
              $SUDO apt-get install -y -qq curl
              curl -fsSL https://get.docker.com | $SUDO sh
            fi
          fi
          $SUDO usermod -aG docker "${USER:-root}" 2>/dev/null || true
          ok "Packages installed! You may need to log out and back in for Docker group to take effect."
          ;;
        fedora)
          info "Installing: git, python3, docker, docker-compose-plugin"
          $SUDO dnf install -y git python3 docker docker-compose-plugin
          $SUDO systemctl enable --now docker
          $SUDO usermod -aG docker "${USER:-root}" 2>/dev/null || true
          ok "Packages installed!"
          ;;
        arch)
          info "Installing: git, python, docker, docker-compose"
          $SUDO pacman -S --noconfirm git python docker docker-compose
          $SUDO systemctl enable --now docker
          $SUDO usermod -aG docker "${USER:-root}" 2>/dev/null || true
          ok "Packages installed!"
          ;;
        macos)
          if ! command -v brew &>/dev/null; then
            info "Installing Homebrew..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
          fi
          brew install git python docker docker-compose 2>/dev/null || true
          ok "Packages installed! Open Docker.app to start the daemon."
          ;;
      esac

      # Re-check
      ALL_OK=1
      command -v git &>/dev/null || ALL_OK=0
      command -v python3 &>/dev/null || ALL_OK=0
      docker info &>/dev/null 2>&1 || ALL_OK=0
      command -v docker-compose &>/dev/null || docker compose version &>/dev/null 2>&1 || ALL_OK=0

      if [ "$ALL_OK" = "0" ]; then
        warn "Some dependencies still missing after install. Run setup.sh again once resolved."
        echo ""
        echo "  If Docker group was just added, you need to:"
        echo "    newgrp docker"
        echo "  or log out and back in."
        echo ""
      fi
    else
      warn "Skipping dependency installation. The build may fail."
      echo ""
    fi
  fi

  # Detect compose command (maybe just installed)
  if command -v docker-compose &>/dev/null; then
    COMPOSE_CMD="docker-compose"
  elif docker compose version &>/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
  else
    COMPOSE_CMD="docker compose"
  fi
fi

# ── Clone Components ───────────────────────────────────────────────────────
header "Components"

COMPONENTS=(
  opencpo-core
  opencpo-admin
  opencpo-charge-app
  opencpo-tester
  opencpo-charger-farm
)

for repo in "${COMPONENTS[@]}"; do
  if [ -d "$repo/.git" ]; then
    ok "$repo already exists — pulling latest"
    git -C "$repo" pull --ff-only 2>/dev/null || true
  else
    info "Cloning $repo ..."
    git clone "$BASE_URL/$repo.git" 2>/dev/null && ok "$repo cloned" || fail "Failed to clone $repo"
  fi
done

echo ""

# ── .env File ──────────────────────────────────────────────────────────────
if [ ! -f .env ] && [ -f .env.example ]; then
  cp .env.example .env
  ok "Created .env from .env.example"
fi

# ── Configuration Wizard ────────────────────────────────────────────────────
header "Configuration"

if [ -n "$PYTHON" ] || PYTHON=$(command -v python3 || command -v python); then
  if [ "$AUTO" = "1" ]; then
    info "Running configure.py --auto ..."
    "$PYTHON" configure.py --auto
  else
    info "Starting configuration wizard..."
    "$PYTHON" configure.py
  fi
else
  warn "Python 3 not found. Configure manually:"
  warn "  Edit .env with your settings, then run: docker compose build && docker compose up -d"
fi

echo ""

# ── Build ──────────────────────────────────────────────────────────────────
header "Building Docker Images"

if [ "${ALL_OK:-1}" = "1" ] || [ "$SKIP_DEPS" = "1" ]; then
  info "Running $COMPOSE_CMD build ..."
  if $COMPOSE_CMD build; then
    ok "All images built successfully!"
  else
    fail "Build failed. Check the output above for errors."
    exit 1
  fi
else
  warn "Skipping build due to missing dependencies. Fix them first then run:"
  echo "  $COMPOSE_CMD build"
fi

# ── Done ────────────────────────────────────────────────────────────────────
header "${GREEN}${BOLD}OpenCPO is ready!${NC}"

echo ""
echo -e "  ${BOLD}Start the platform:${NC}"
echo "    $COMPOSE_CMD up -d"
echo ""
echo -e "  ${BOLD}Open in your browser:${NC}"
echo "    Admin Panel:  http://localhost:8080"
echo "    Charge App:   http://localhost:8003"
echo "    Compliance:   http://localhost:8090"
echo "    Charger Farm: http://localhost:8087"
echo ""
echo -e "  ${BOLD}Need help?${NC}"
echo "    Docs:    https://github.com/opencpo/opencpo"
echo "    Discord: https://discord.gg/ra9pnygmrt"
echo ""

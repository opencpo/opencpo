#!/usr/bin/env bash
# setup.sh — OpenCPO Setup Script
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

VERSION="v0.2.3"

# ── Global cleanup on exit ──
cleanup() {
  local rc=$?
  if [ "$rc" -ne 0 ] && [ "$rc" -ne 130 ] && [ "$rc" -ne 143 ]; then
    echo ""
    warn "Setup failed (exit code $rc). Common fixes:"
    warn "  • Docker daemon not running?  sudo systemctl start docker"
    warn "  • Port conflict?              sudo lsof -i :8080"
    warn "  • Missing deps?              ./setup.sh --skip-deps"
    warn "  • Service crash?             docker compose logs --tail=50"
    warn "  • Full reinstall:            ./uninstall.sh && curl ... | bash"
    echo ""
  fi
}
trap cleanup EXIT

ORG="${ORG:-opencpo}"
BASE_URL="https://github.com/$ORG"
# Auto-detect non-interactive mode: when piped (curl | bash), stdin is not a TTY
if [ ! -t 0 ]; then
  AUTO=1
fi
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

# ── Colors (honors NO_COLOR env var) ──
if [ -n "${NO_COLOR:-}" ] || [ ! -t 1 ]; then
  RED='' GREEN='' YELLOW='' CYAN='' BOLD='' DIM='' NC=''
  G1='' G2='' G3='' G4='' G5='' G6=''
else
  # printf -v stores actual ESC bytes, not literal \033
  printf -v RED   "\033[0;31m"
  printf -v GREEN "\033[0;32m"
  printf -v YELLOW "\033[1;33m"
  printf -v CYAN  "\033[0;36m"
  printf -v BOLD  "\033[1m"
  printf -v DIM   "\033[2m"
  printf -v NC    "\033[0m"
  # Gradient: bright cyan → teal → green (used in banner)
  printf -v G1 "\033[38;2;0;229;255m"   # #00E5FF
  printf -v G2 "\033[38;2;0;184;212m"   # #00B8D4
  printf -v G3 "\033[38;2;0;150;136m"   # #009688
  printf -v G4 "\033[38;2;56;142;60m"   # #388E3C
  printf -v G5 "\033[38;2;27;94;32m"    # #1B5E20
  printf -v G6 "\033[38;2;13;60;20m"    # #0D3C14
fi

info()  { echo -e "${CYAN}  ->${NC} $1"; }
ok()    { echo -e "${GREEN}  v${NC} $1"; }
warn()  { echo -e "${YELLOW}  !${NC} $1"; }
fail()  { echo -e "${RED}  x${NC} $1"; }

banner() {
  printf '\n'
  printf '%s\n' "${G1}   ██████╗ ██████╗ ███████╗███╗   ██╗ ██████╗██████╗  ██████╗ ${NC}"
  printf '%s\n' "${G2}  ██╔═══██╗██╔══██╗██╔════╝████╗  ██║██╔════╝██╔══██╗██╔═══██╗${NC}"
  printf '%s\n' "${G3}  ██║   ██║██████╔╝█████╗  ██╔██╗ ██║██║     ██████╔╝██║   ██║${NC}"
  printf '%s\n' "${G4}  ██║   ██║██╔═══╝ ██╔══╝  ██║╚██╗██║██║     ██╔═══╝ ██║   ██║${NC}"
  printf '%s\n' "${G5}  ╚██████╔╝██║     ███████╗██║ ╚████║╚██████╗██║     ╚██████╔╝${NC}"
  printf '%s\n' "${G6}   ╚═════╝ ╚═╝     ╚══════╝╚═╝  ╚═══╝ ╚═════╝╚═╝      ╚═════╝ ${NC}"
  printf '\n'
  printf '%s\n' "${DIM}  Open Source EV Charging Platform · Zero Trust · OCPP 1.6/2.0.1 · ISO 15118 · PKI${NC}"
  printf '%s\n' "${DIM}  ${VERSION}${NC}"
  printf '\n'
}

header() {
  echo ""
  printf '%s\n' "${CYAN}╭─────────────────────────────────────────────────────────────────╮${NC}"
  printf '%s\n' "${CYAN}│${NC}  ${BOLD}$1${NC}"
  printf '%s\n' "${CYAN}╰─────────────────────────────────────────────────────────────────╯${NC}"
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
# Skip banner in auto-mode (install.sh already showed it)
if [ "${AUTO:-0}" != "1" ]; then
  banner
fi

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
      warn "Unknown distro: $ID -- will check tools individually"
      ;;
  esac
elif [ "$(uname)" = "Darwin" ]; then
  OS="macos"
  ok "Detected: macOS $(sw_vers -productVersion 2>/dev/null || echo 'unknown')"
fi

# ── Pre-flight: disk space ──
MIN_SPACE_MB=2048
AVAILABLE_MB=$(df -m . 2>/dev/null | awk 'NR==2 {print $4}' || echo "99999")
if [ "${AVAILABLE_MB}" -lt "${MIN_SPACE_MB}" ] 2>/dev/null; then
  warn "Low disk space: ${AVAILABLE_MB}MB available (recommended: ${MIN_SPACE_MB}MB)"
  warn "The Docker build may fail if disk space runs out."
fi

# ── Pre-flight: RAM + swap ──
# Docker builds can OOM on low-memory VMs.  Create a 2GB swapfile if the
# system has less than 6GB RAM and no swap configured.
RAM_MB=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo "99999")
if [ "${RAM_MB}" -lt 6000 ] 2>/dev/null; then
  SWAP_MB=$(awk '/SwapTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo "0")
  if [ "${SWAP_MB}" -lt 1000 ] 2>/dev/null; then
    warn "Low RAM (${RAM_MB}MB) with no swap — adding 2GB swapfile for builds"
    if [ "$(id -u)" -eq 0 ]; then
      fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile
    else
      sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile >/dev/null && sudo swapon /swapfile
    fi
    ok "Swap added ($(free -h | awk '/Swap:/{print $2}'))"
  fi
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
      VER=$("$cmd" --version 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
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
  if command -v docker &>/dev/null; then
    if docker info &>/dev/null 2>&1; then
      ok "Docker: $(docker --version 2>&1)"
    elif sudo docker info &>/dev/null 2>&1; then
      ok "Docker: $(sudo docker --version 2>&1) (via sudo)"
    else
      # Docker binary exists but daemon not running — try to start it
      warn "Docker daemon not running — attempting to start..."
      sudo systemctl start docker 2>/dev/null || sudo service docker start 2>/dev/null || true
      sleep 2
      if docker info &>/dev/null 2>&1 || sudo docker info &>/dev/null 2>&1; then
        ok "Docker daemon started"
      else
        warn "Docker installed but daemon not running (or no socket access)"
        warn "  Try: sudo systemctl start docker"
        ALL_OK=0
      fi
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
          # Wait for any background apt/dpkg processes to finish
          # (cloud-init packages can still be installing on first boot)
          for _ in $(seq 1 30); do
            if ! $SUDO fuser /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock 2>/dev/null; then
              break
            fi
            sleep 2
          done
          info "Installing: git, python3, python3-venv"
          $SUDO apt-get update -qq && $SUDO apt-get install -y -qq git python3 python3-venv

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
            info "Docker found but Compose missing -- installing compose plugin..."
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
      # Re-check with sudo fallback (docker group may not apply to current shell)
      ALL_OK=1
      command -v git &>/dev/null || ALL_OK=0
      command -v python3 &>/dev/null || ALL_OK=0
      docker info &>/dev/null 2>&1 || sudo docker info &>/dev/null 2>&1 || ALL_OK=0
      command -v docker-compose &>/dev/null || docker compose version &>/dev/null 2>&1 || sudo docker compose version &>/dev/null 2>&1 || ALL_OK=0

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
fi

# Detect compose command (may need sudo if docker group not yet active)
COMPOSE_CMD="docker compose"
if command -v docker-compose &>/dev/null; then
  COMPOSE_CMD="docker-compose"
elif docker compose version &>/dev/null 2>&1; then
  COMPOSE_CMD="docker compose"
elif sudo docker compose version &>/dev/null 2>&1; then
  COMPOSE_CMD="sudo docker compose"
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
    ok "$repo already exists -- pulling latest"
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

# Remove stale docker volumes if .env was regenerated (passwords changed)
if [ -f .env.bak ]; then
  info "New .env detected — removing stale docker volumes ..."
  $COMPOSE_CMD down -v 2>/dev/null || true
  ok "Stale volumes removed"
fi

# Source .env for shell commands (psql -U, etc.) — docker compose reads .env
# automatically for containers, but the shell needs it for exec commands.
if [ -f .env ]; then
  set -a
  # shellcheck source=/dev/null
  . ./.env 2>/dev/null || true
  set +a
fi

echo ""

# ── Build ──────────────────────────────────────────────────────────────────
header "Building Docker Images"

BUILD_OK=0
COMPOSE_TRIES=("$COMPOSE_CMD")
if [ "$COMPOSE_CMD" != "sudo docker compose" ]; then
  COMPOSE_TRIES+=("sudo $COMPOSE_CMD")
fi

# Build only services whose source directories actually exist.
# This makes charge-app, tester, and charger-farm optional — they won't
# block the install if the user hasn't cloned those repos yet.
BUILD_SERVICES="postgres redis ocpp-core cpo-admin"
for svc in charge-app compliance-tester charger-farm; do
  REPODIR=""
  case "$svc" in
    charge-app)          REPODIR="opencpo-charge-app" ;;
    compliance-tester)   REPODIR="opencpo-tester" ;;
    charger-farm)        REPODIR="opencpo-charger-farm" ;;
  esac
  if [ -d "$REPODIR" ] && [ -f "$REPODIR/Dockerfile" ]; then
    BUILD_SERVICES="$BUILD_SERVICES $svc"
  else
    warn "Skipping $svc — $REPODIR/Dockerfile not found"
  fi
done

BUILD_LOG=$(mktemp)

for cmd in "${COMPOSE_TRIES[@]}"; do
  # If docker daemon isn't reachable, try starting it
  if ! docker info &>/dev/null 2>&1 && ! sudo docker info &>/dev/null 2>&1; then
    info "Docker daemon not reachable — attempting to start..."
    sudo systemctl start docker 2>/dev/null || sudo service docker start 2>/dev/null || true
    sleep 2
  fi
  info "Building images ($BUILD_SERVICES) ..."
  # Capture full build output to a temp file so we can show it on failure.
  # --progress=plain exposes pip install errors that -q would hide.
  if $cmd build --progress=plain $BUILD_SERVICES >"$BUILD_LOG" 2>&1; then
    # Success: show last 10 lines as a preview
    tail -10 "$BUILD_LOG"
    BUILD_OK=1
    COMPOSE_CMD="$cmd"
    rm -f "$BUILD_LOG"
    break
  fi
  # Build failed — show full output so the user can see the error
  echo ""
  fail "Build failed. Full build output:"
  echo "══════════════════════════════════════════════════════════════════"
  cat "$BUILD_LOG"
  echo "══════════════════════════════════════════════════════════════════"
  echo ""
done

if [ "$BUILD_OK" = "1" ]; then
  ok "All images built successfully!"
  echo ""

  # ── Sanity check: verify core imports before starting ──
  # Catches runtime import errors (missing deps, bad imports) early.
  info "Running import sanity check ..."
  SANITY_OK=0
  if $COMPOSE_CMD run --rm ocpp-core python -c "
import api.main
import api.admin_auth
import api.admin_setup
print('OK')
" 2>&1; then
    SANITY_OK=1
  fi

  if [ "$SANITY_OK" = "0" ]; then
    echo ""
    warn "Import check failed — the core image has a broken dependency chain."
    warn "This is usually caused by a missing pip dependency or stale build cache."
    echo ""
    info "Retrying with --no-cache to force a clean rebuild..."
    REBUILD_LOG=$(mktemp)
    if $COMPOSE_CMD build --no-cache --progress=plain ocpp-core cpo-admin >"$REBUILD_LOG" 2>&1; then
      tail -10 "$REBUILD_LOG"
      ok "Rebuild successful"
      rm -f "$REBUILD_LOG"
      SANITY_OK=1
    else
      fail "Build still fails after --no-cache. Full output:"
      echo "══════════════════════════════════════════════════════════════════"
      cat "$REBUILD_LOG"
      echo "══════════════════════════════════════════════════════════════════"
      echo ""
      warn "Common causes:"
      warn "  • Missing Python package  →  add to opencpo-core/requirements.txt"
      warn "  • Syntax error in code    →  fix the file and re-run"
      echo ""
      rm -f "$REBUILD_LOG"
      exit 1
    fi
  fi

  # ── Start services ──
  header "Starting Services"

  # Start infrastructure first (postgres, redis)
  info "Starting database and cache ..."
  if $COMPOSE_CMD up -d postgres redis; then
    ok "Infrastructure started"
  else
    fail "Failed to start infrastructure"
    exit 1
  fi

  # Wait for postgres to accept connections
  info "Waiting for postgres to be ready ..."
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    if $COMPOSE_CMD exec -T postgres pg_isready -U "${POSTGRES_USER:-ocpp}" &>/dev/null; then
      ok "Postgres ready"
      break
    fi
    if [ "$i" = "15" ]; then
      fail "Postgres did not become ready in time"
      exit 1
    fi
    sleep 3
  done

  # Apply database schema (idempotent — checks if tables exist first)
  if [ -f "opencpo-core/db/schema.sql" ]; then
    TABLE_COUNT=$($COMPOSE_CMD exec -T postgres psql -U "${POSTGRES_USER:-ocpp}" -d "${POSTGRES_DB:-ocpp}" -t -A -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='public'" 2>/dev/null || echo "0")
    if [ "$TABLE_COUNT" = "0" ]; then
      info "Applying database schema ..."
      if $COMPOSE_CMD exec -T postgres psql -U "${POSTGRES_USER:-ocpp}" -d "${POSTGRES_DB:-ocpp}" < "opencpo-core/db/schema.sql" &>/dev/null; then
        ok "Database schema applied"
      else
        fail "Failed to apply database schema"
        exit 1
      fi
    else
      ok "Database schema already present ($TABLE_COUNT tables)"
    fi
  fi

  # Apply migrations
  for migration in opencpo-core/db/migrations/*.sql; do
    if [ -f "$migration" ]; then
      migration_name=$(basename "$migration")
      info "Applying migration: $migration_name ..."
      $COMPOSE_CMD exec -T postgres psql -U "${POSTGRES_USER:-ocpp}" -d "${POSTGRES_DB:-ocpp}" < "$migration" &>/dev/null || true
    fi
  done

  # Start all services
  info "Starting all services ..."
  if $COMPOSE_CMD up -d; then
    ok "All services started"

    # Poll up to 90s for all services to become healthy
    info "Waiting for services to pass health checks ..."
    for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
      UNHEALTHY=$($COMPOSE_CMD ps --format '{{.Status}}' 2>/dev/null | grep -cE "unhealthy|exited" || true)
      if [ "$UNHEALTHY" = "0" ]; then
        ok "All services healthy!"
        break
      fi
      if [ "$i" = "15" ]; then
        echo ""
        warn "Some services not healthy after 90s."
        echo ""
        $COMPOSE_CMD ps --format 'table {{.Name}}\t{{.Status}}'
        echo ""
        # Show crash logs for any unhealthy service
        for svc in $($COMPOSE_CMD ps --format '{{.Name}}' 2>/dev/null); do
          STATUS=$($COMPOSE_CMD ps --format '{{.Status}}' "$svc" 2>/dev/null)
          case "$STATUS" in
            *unhealthy*|*exited*)
              warn "--- $svc logs (last 15 lines) ---"
              $COMPOSE_CMD logs --tail=15 "$svc" 2>/dev/null || true
              echo ""
              ;;
          esac
        done
        warn "Trying to restart unhealthy services..."
        $COMPOSE_CMD restart 2>/dev/null || true
        sleep 10
        $COMPOSE_CMD ps --format 'table {{.Name}}\t{{.Status}}'
        echo ""
        warn "If services still fail:"
        warn "  docker compose logs --tail=50 <service>"
        warn "  docker compose down && docker compose up -d"
        warn "  docker compose build --no-cache <service>"
        warn ""
        break
      fi
      printf '.'
      sleep 6
    done
    echo ""
  else
    fail "Failed to start services."
    echo ""
    warn "--- all services status ---"
    $COMPOSE_CMD ps --format 'table {{.Name}}\t{{.Status}}' 2>/dev/null || true
    echo ""
    # Show crash logs for each unhealthy/exited service
    for svc in $($COMPOSE_CMD ps --format '{{.Name}}' 2>/dev/null); do
      STATUS=$($COMPOSE_CMD ps --format '{{.Status}}' "$svc" 2>/dev/null)
      case "$STATUS" in
        *unhealthy*|*exited*)
          warn "--- $svc logs (last 20 lines) ---"
          $COMPOSE_CMD logs --tail=20 "$svc" 2>/dev/null || true
          echo ""
          ;;
      esac
    done
    warn "Quick fixes:"
    warn "  docker compose down && docker compose up -d"
    warn "  docker compose build --no-cache <service>"
    warn "  docker compose logs --tail=50 <service>"
    echo ""
    exit 1
  fi
else
  fail "Docker build failed. The Docker daemon may need to be started, or"
  fail "you may need to add your user to the docker group:"
  echo ""
  echo "    sudo usermod -aG docker \$USER && newgrp docker"
  echo "    cd $(pwd) && $COMPOSE_CMD build"
  echo ""
  exit 1
fi

# ── Done ────────────────────────────────────────────────────────────────────
header "${GREEN}${BOLD}OpenCPO is ready!${NC}"

echo ""
echo -e "  ${BOLD}Start the platform:${NC}"
echo "    $COMPOSE_CMD up -d"
echo ""
echo -e "  ${BOLD}Open in your browser:${NC}"
echo "    Admin Panel:  http://localhost:8080  (create your admin account on first visit)"
echo "    Charge App:   http://localhost:8003"
echo "    Compliance:   http://localhost:8090"
echo "    Charger Farm: http://localhost:8087"
echo ""
echo -e "  ${BOLD}Need help?${NC}"
echo "    Docs:    https://github.com/opencpo/opencpo"
echo "    Discord: https://discord.gg/ra9pnygmrt"
echo ""

#!/usr/bin/env bash
# setup.sh — Clone all OCPP Platform component repos
# Run this once after cloning ocpp-platform.

set -euo pipefail

ORG="${ORG:-opencpo}"
BASE_URL="https://github.com/$ORG"

REPOS=(
  opencpo-core
  opencpo-admin
  opencpo-charge-app
  opencpo-tester
  opencpo-charger-farm
)

echo "╔══════════════════════════════════════╗"
echo "║     OCPP Platform — Setup            ║"
echo "╚══════════════════════════════════════╝"
echo ""
echo "Cloning components from github.com/$ORG ..."
echo ""

for repo in "${REPOS[@]}"; do
  if [ -d "$repo/.git" ]; then
    echo "  ✓ $repo already exists — pulling latest"
    git -C "$repo" pull --ff-only
  else
    echo "  ↓ Cloning $repo ..."
    git clone "$BASE_URL/$repo.git"
  fi
done

echo ""
echo "All components cloned."
echo ""

# Copy env file if not present
if [ ! -f .env ]; then
  cp .env.example .env
  echo "Created .env from .env.example — review it before starting."
  echo ""
fi

echo "Building all Docker images with docker compose build ..."
echo ""
docker compose build
echo ""
echo "Build complete."
echo ""

echo "Next step:"
echo ""

echo "  docker compose up -d"

echo ""
echo "Then open:"
echo "  CPO Admin:    http://localhost:8080"
echo "  Driver PWA:   http://localhost:8003"
echo "  Compliance:   http://localhost:8090"
echo "  Charger Farm: http://localhost:8087"
echo ""

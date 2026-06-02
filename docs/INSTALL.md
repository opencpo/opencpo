# OpenCPO — Installation Guide

## Prerequisites

- **Linux** (x86_64 or arm64) or **macOS** (Apple Silicon / Intel)
- **Docker** 24+ and **Docker Compose** v2.28+ ([install Docker](https://docs.docker.com/engine/install/))
- **Git** 2.30+
- **4 GB RAM** minimum (8 GB recommended)
- **Ports available**: 8000, 8080, 8003, 8090, 8087, 9100, 9201, 5432, 6379 (defaults — customizable)

## Quick Start (5 minutes)

```bash
# 1. Clone the orchestrator
git clone https://github.com/opencpo/opencpo.git
cd opencpo

# 2. Clone all component repos
./setup.sh

# 3. Run the configuration wizard
python3 configure.py

# 4. Open the dashboard
open http://localhost:8080
```

The wizard will:
- Check your system for Docker + Compose
- Ask for your org name, database passwords, and ports
- Generate a `.env` file with your settings
- Build all Docker images
- Start all services

## Manual Installation

If you prefer to configure manually instead of using the wizard:

```bash
git clone https://github.com/opencpo/opencpo.git
cd opencpo
./setup.sh

# Create .env from example
cp .env.example .env

# Edit .env with your values
nano .env

# Build and start
docker compose build
docker compose up -d
```

## Verifying Your Installation

Once all services are running:

| Service | URL | Credentials |
|---------|-----|-------------|
| **CPO Admin** | http://localhost:8080 | First user registers via UI |
| **Driver PWA** | http://localhost:8003 | — |
| **Compliance Tester** | http://localhost:8090 | — |
| **Charger Farm** | http://localhost:8087 | — |
| **OCPP 1.6 WebSocket** | ws://localhost:9100/{charger-id} | — |
| **OCPP 2.0.1 WebSocket** | ws://localhost:9201/{charger-id} | — |
| **CSMS REST API** | http://localhost:8000 | API key from .env |

Check health:

```bash
docker compose ps
docker compose logs ocpp-core --tail=20
curl http://localhost:8000/health
```

## Production Deployment

### Minimum Production Changes

| Setting | Dev Default | Production Best Practice |
|---------|-------------|--------------------------|
| `POSTGRES_PASSWORD` | `ocpp` | **32+ char random** |
| `SECRET_KEY` | auto-generated | **48+ char random** |
| `PUBLIC_URL` | `http://localhost` | Your public domain |
| `LOG_LEVEL` | `info` | `warning` (or `info` with log rotation) |

### Running Behind a Reverse Proxy

```nginx
# Nginx example — OCPP 1.6 WebSocket
server {
    listen 443 ssl;
    server_name ocpp.example.com;

    ssl_certificate /etc/ssl/certs/example.crt;
    ssl_certificate_key /etc/ssl/private/example.key;

    location /ocpp-1.6/ {
        proxy_pass http://127.0.0.1:9100/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
    }

    location /ocpp-2.0.1/ {
        proxy_pass http://127.0.0.1:9201/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
    }

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

### Docker Compose Profiles for Production

For a production deployment, consider running only the services you need:

```bash
# Start just core + database
docker compose up -d postgres redis ocpp-core

# Start admin dashboard on a separate machine
docker compose up -d cpo-admin

# Start charger farm (test environment only)
docker compose up -d charger-farm
```

## Architecture Overview

```
┌──────────────┐  ┌──────────────┐  ┌──────────────────┐
│  Drivers     │  │  Operators   │  │  Manufacturers   │
│  (PWA)       │  │  (Admin UI)  │  │  (Compliance)    │
│  :8003       │  │  :8080       │  │  :8090           │
└──────┬───────┘  └──────┬───────┘  └───────┬──────────┘
       │  HTTP API       │  HTTP API        │  OCPP WS
       └────────┬────────┴──────────┬───────┘
                │                   │
       ┌────────▼───────────────────▼────────┐
       │        ocpp-core (CSMS)             │
       │  OCPP 1.6 WS :9100                 │
       │  OCPP 2.0.1 WS :9201               │
       │  REST API :8000                     │
       └────────┬────────────────────────────┘
                │
       ┌────────▼────────┐  ┌──────────────┐
       │   PostgreSQL    │  │    Redis     │
       │   TimescaleDB   │  │   Session    │
       │   (persistent)  │  │   (cache)    │
       └─────────────────┘  └──────────────┘

┌──────────────────────────────────────────┐
│  Charger Farm (:8087)                    │
│  Virtual charger simulator + load tester │
└──────────────────────────────────────────┘
```

## Network Ports Reference

| Port | Service | Protocol | Config Variable |
|------|---------|----------|-----------------|
| 5432 | PostgreSQL | TCP | `POSTGRES_PORT` |
| 6379 | Redis | TCP | `REDIS_PORT` |
| 8000 | CSMS REST API | HTTP | `OCPP_API_PORT` |
| 8080 | CPO Admin UI | HTTP | `CPO_ADMIN_PORT` |
| 8003 | Driver PWA | HTTP | `CHARGE_APP_PORT` |
| 8090 | Compliance Tester | HTTP | `COMPLIANCE_PORT` |
| 8087 | Charger Farm | HTTP | `CHARGER_FARM_PORT` |
| 9100 | OCPP 1.6 | WebSocket | `OCPP_16_WS_PORT` |
| 9201 | OCPP 2.0.1 | WebSocket | `OCPP_201_WS_PORT` |

## Upgrading

```bash
cd opencpo
git pull
./setup.sh            # pulls latest component versions
docker compose build  # rebuild images with latest code
docker compose up -d  # restart with new images
```

Check the [changelog](https://github.com/opencpo/opencpo/releases) for breaking changes between versions.

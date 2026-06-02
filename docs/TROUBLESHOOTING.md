# OpenCPO — Troubleshooting Guide

## Quick Diagnosis

First, check the system status:

```bash
# Are all services running?
docker compose ps

# Check logs for errors
docker compose logs --tail=50

# Check core health
curl http://localhost:8000/health

# Check Docker system health
docker info
```

## Common Issues

### 1. "build: ./opencpo-core" — directory not found

**Problem**: `docker compose build` fails because component directories are missing.

**Fix**: Run the setup script first:
```bash
./setup.sh
```
This clones all component repos from `github.com/opencpo`.

### 2. Port already in use

**Problem**: `docker compose up` fails with "port already allocated".

**Fix**: Change the port in `.env`:
```bash
# In .env, change the conflicting port
CPO_ADMIN_PORT=8081
```
Then rebuild and restart.

### 3. PostgreSQL connection refused

**Problem**: `ocpp-core` crashes with connection to PostgreSQL refused.

**Possible causes**:
- PostgreSQL needs more time to initialize on first run
- The health check is too aggressive

**Fix**: Wait 30-60 seconds on first run, then check:
```bash
docker compose logs ocpp-core --tail=20
docker compose logs postgres --tail=20
```

### 4. Charger won't connect

**Problem**: A charger connects but immediately disconnects.

**Check**:
1. Is the charger using the correct WebSocket URL? `ws://<host>:9100/<charger-id>`
2. Is the charger registered in the admin dashboard?
3. Does the charger's OCPP version match? 1.6 → port 9100, 2.0.1 → port 9201

**Diagnose**:
```bash
docker compose logs ocpp-core --tail=50 | grep -i "disconnect\|error\|reject"
```

### 5. Admin dashboard shows "Can't reach core API"

**Problem**: The CPO Admin dashboard loads but shows API errors.

**Fix**:
```bash
# Check if core is healthy
curl http://localhost:8000/health

# Check admin → core connectivity
docker compose exec cpo-admin curl http://ocpp-core:8000/health
```

### 6. Docker not installed

**Problem**: `docker compose` command not found.

**Fix**:
```bash
# Linux
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
# Log out and back in, then retry

# macOS
# Install Docker Desktop from https://docs.docker.com/desktop/setup/install/mac-install/
```

### 7. Build fails — out of memory

**Problem**: Docker build fails with "Killed" or "exit code 137".

**Fix**: Increase Docker memory limit:
- **Docker Desktop**: Settings → Resources → Advanced → Memory (set to 4 GB+)
- **Linux**: No limit by default — check `free -h` for available RAM

### 8. OCPP chargers timeout on WebSocket

**Problem**: Chargers connect but get timeout errors.

**Check**:
- Network connectivity: can the charger reach the OpenCPO host?
- Firewall: port 9100 and 9201 must be open for WebSocket traffic
- Proxy: if behind a reverse proxy, ensure WebSocket upgrade headers are forwarded

**Test**:
```bash
# From the charger's network, test connectivity
nc -zv <opencpo-host> 9100
curl -i -H "Upgrade: websocket" -H "Connection: Upgrade" http://<opencpo-host>:9100/test-id
```

## Logs Reference

### Viewing Logs

```bash
# All services
docker compose logs --tail=100 -f

# Single service
docker compose logs ocpp-core --tail=100 -f

# With timestamps
docker compose logs -t --tail=50
```

### Log Levels

Set `LOG_LEVEL` in `.env`:

| Level | When to Use |
|-------|-------------|
| `debug` | Development — very verbose, includes OCPP message dumps |
| `info` | Default — normal operations |
| `warning` | Production — only warnings and errors |
| `error` | Silent operation — only critical errors |

### Where Logs Go

- **Docker logs**: Capture via `docker compose logs`
- **Application logs**: Written to stdout by each service
- **Database logs**: Inside the PostgreSQL container — `docker compose exec postgres cat /var/log/postgresql/postgresql-16-main.log`

## Known Issues

1. **First build is slow** (5-15 minutes depending on internet speed). Subsequent builds use Docker cache and take <30 seconds.

2. **PostgreSQL health check** may fail on very slow machines. Set `COMPOSE_HTTP_TIMEOUT=120` if you see health check timeouts.

3. **Re-opening `.env` after running configure.py**: The wizard creates `.env` with a backup at `.env.bak`. Always edit `.env` directly for manual changes.

4. **Reset everything**:
```bash
docker compose down -v   # WARNING: deletes all data!
docker compose build
docker compose up -d
```

## Getting Help

- **GitHub Issues**: [github.com/opencpo/opencpo/issues](https://github.com/opencpo/opencpo/issues)
- **Discord**: [discord.gg/ra9pnygmrt](https://discord.gg/ra9pnygmrt)
- **Documentation**: [github.com/opencpo/opencpo](https://github.com/opencpo/opencpo)

When reporting an issue, please include:
- Output of `docker compose ps`
- The last 50 lines of `docker compose logs ocpp-core`
- Your `.env` file (redact passwords!)
- OS and Docker version (`docker --version` and `docker compose version`)

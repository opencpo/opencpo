# OpenCPO — Configuration Reference

All configuration is done via environment variables in `.env`. Below is the complete reference.

## Environment Variables

### Organization

| Variable | Default | Description |
|----------|---------|-------------|
| `ORG_NAME` | `OpenCPO Demo` | Your organization name, shown in the admin UI |
| `PUBLIC_URL` | `http://localhost` | Public base URL for QR codes, deep links, and charge app |

### PostgreSQL Database

| Variable | Default | Description |
|----------|---------|-------------|
| `POSTGRES_DB` | `ocpp` | Database name |
| `POSTGRES_USER` | `ocpp` | Database user |
| `POSTGRES_PASSWORD` | `ocpp` | **Change in production!** Database password |
| `POSTGRES_PORT` | `5432` | PostgreSQL port (change if you run another Postgres) |

### Redis Cache

| Variable | Default | Description |
|----------|---------|-------------|
| `REDIS_PORT` | `6379` | Redis port |

### Core CSMS (ocpp-core)

| Variable | Default | Description |
|----------|---------|-------------|
| `SECRET_KEY` | auto-generated | Secret key for JWT tokens, session signing |
| `LOG_LEVEL` | `info` | Log level: `debug`, `info`, `warning`, `error`, `critical` |
| `OCPP_16_WS_PORT` | `9100` | OCPP 1.6 WebSocket server port |
| `OCPP_201_WS_PORT` | `9201` | OCPP 2.0.1 WebSocket server port |
| `OCPP_API_PORT` | `8000` | REST API port |

### Services Ports

| Variable | Default | Description |
|----------|---------|-------------|
| `CPO_ADMIN_PORT` | `8080` | CPO Admin dashboard |
| `CHARGE_APP_PORT` | `8003` | Driver-facing PWA |
| `COMPLIANCE_PORT` | `8090` | Compliance tester web UI |
| `CHARGER_FARM_PORT` | `8087` | Virtual charger farm UI |

## Configuration File Locations

### ocpp-core

| Path | Purpose |
|------|---------|
| `.env.example` | Reference for all variables |
| `.env` | **Actual configuration — keep secret!** |

### opencpo-charge-app

| Path | Purpose |
|------|---------|
| `skins/` | Skin directories for branding |
| `skins/default/` | Built-in neutral skin |
| `skins/<name>/skin.json` | Custom skin metadata |
| `plugins/` | Plugin directories |

### opencpo-admin

| Path | Purpose |
|------|---------|
| `routes/` | Dashboard route modules |
| `static/` | Static assets (CSS, JS, images) |
| `templates/` | Jinja2 HTML templates |

## PKI / mTLS Configuration

OpenCPO includes a built-in Certificate Authority for mTLS-secured charger connections:

1. **First run**: A root CA is generated automatically at `data/pki/`
2. **Charger certs**: Issue per-charger certificates from the admin dashboard
3. **Revocation**: Use the PKI management section in the CPO Admin

## Skin System

The charge app supports custom skins for operator branding:

```bash
# Switch to a different skin
echo 'SKIN=stroom-electron' >> .env
```

Built-in skins: `default` (generic), `voltage-backstage`, `stroom-electron`, `ion-flux`, `voltage-industrial`, `current-flow`

Each skin lives in `skins/<name>/` and can override templates, CSS, and assets.

## Further Reading

- [Installation Guide](INSTALL.md)
- [Troubleshooting Guide](TROUBLESHOOTING.md)
- [GitHub: opencpo/opencpo](https://github.com/opencpo/opencpo)

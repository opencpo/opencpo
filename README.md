# OpenCPO

⚡ **Open Source EV Charging Platform** — Zero Trust · OCPP 1.6/2.0.1 · ISO 15118 · PKI

The only EV charging platform where chargers are invisible on the internet.
Enterprise-grade security. Open source. No compromise.

Built by an actual CPO running real chargers. Includes a complete guide to becoming a CPO.

## Quick Start

```bash
git clone https://github.com/opencpo/opencpo.git
cd opencpo
./setup.sh
python3 configure.py
```

Open http://localhost:8080 — your CPO admin panel is ready.

## The Stack

| Component | Description | Port(s) |
|-----------|-------------|---------|
| **ocpp-core** | OCPP 1.6/2.0.1 CSMS | 9100 (WS 1.6), 9201 (WS 2.0.1), 8000 (REST) |
| **cpo-admin** | Network management dashboard | 8080 |
| **charge-app** | Driver-facing PWA | 8003 |
| **compliance-tester** | Charger certification suite | 8090 |
| **charger-farm** | Virtual charger simulator | 8087 |

## Components

Each component lives in its own repository:
- [opencpo-core](https://github.com/opencpo/opencpo-core) — CSMS backend
- [opencpo-admin](https://github.com/opencpo/opencpo-admin) — Operator dashboard
- [opencpo-charge-app](https://github.com/opencpo/opencpo-charge-app) — Driver PWA
- [opencpo-tester](https://github.com/opencpo/opencpo-tester) — Compliance tester
- [opencpo-charger-farm](https://github.com/opencpo/opencpo-charger-farm) — Charger simulator
- [opencpo-bastion](https://github.com/opencpo/opencpo-bastion) — Zero trust gateway

## Documentation

- [Installation Guide](docs/INSTALL.md)
- [Configuration Reference](docs/CONFIGURATION.md)
- [Troubleshooting Guide](docs/TROUBLESHOOTING.md)

## License

Apache 2.0

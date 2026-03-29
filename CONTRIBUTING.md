# Contributing to OCPP Platform

Thanks for your interest in contributing! This is an umbrella repo — it contains only orchestration (compose, scripts, docs). Application code lives in the individual component repos.

---

## Where to Contribute

| What you want to change | Repo |
|-------------------------|------|
| OCPP protocol handling, CSMS logic, REST API | [ocpp-core](https://github.com/your-org/ocpp-core) |
| Operator dashboard UI, admin features | [ocpp-cpo-admin](https://github.com/your-org/ocpp-cpo-admin) |
| Driver PWA, QR flow, payment | [ocpp-charge-app](https://github.com/your-org/ocpp-charge-app) |
| Compliance test cases, certification reports | [ocpp-compliance-tester](https://github.com/your-org/ocpp-compliance-tester) |
| Charger simulator, stress test scenarios | [ocpp-charger-farm](https://github.com/your-org/ocpp-charger-farm) |
| `docker-compose.yml`, `setup.sh`, this README | **here** (ocpp-platform) |

---

## Contributing to a Component

1. **Fork** the relevant component repo on GitHub
2. **Clone** your fork locally
3. **Create a branch** — `git checkout -b feat/my-feature` or `fix/issue-123`
4. **Make your changes** — keep commits focused and atomic
5. **Test locally** — run the component's own test suite before opening a PR
6. **Open a PR** against the component's `main` branch
7. Fill in the PR template — describe what changed and why

---

## Contributing to This Repo

For changes to orchestration (compose, scripts, docs):

1. Fork `ocpp-platform`
2. Make your changes
3. Test that `docker compose up` still works end-to-end
4. Open a PR with a clear description

---

## Code Style

Each component has its own style guide in its `CONTRIBUTING.md`. In general:

- **Python:** [Black](https://black.readthedocs.io/) + [Ruff](https://docs.astral.sh/ruff/)
- **TypeScript/JS:** ESLint + Prettier (config in each repo)
- **YAML/Shell:** keep it readable, comment non-obvious parts

---

## Reporting Issues

- **Bug in a component?** Open an issue in that component's repo.
- **Integration bug** (only reproducible when running the full stack)? Open an issue here.
- **Security vulnerability?** Please do **not** open a public issue. Email the maintainers directly (see repo contacts).

---

## Testing the Full Stack

After cloning all components with `./setup.sh`:

```bash
# Start everything
docker compose up -d

# Check all services are healthy
docker compose ps

# Run the charger farm smoke test (spins up 10 virtual chargers)
docker compose exec charger-farm farm test --count 10

# Run the compliance suite against ocpp-core
docker compose exec compliance-tester tester run --target ws://ocpp-core:9100 --profile ocpp16-core
```

---

## Commit Messages

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add OCPP 2.0.1 smart charging support
fix: handle reconnect race condition in charger-farm
docs: update architecture diagram
chore: bump timescaledb to latest-pg16
```

---

## License

By contributing, you agree that your contributions will be licensed under the [Apache 2.0 License](LICENSE).

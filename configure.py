#!/usr/bin/env python3
"""
OpenCPO — Configuration Wizard

Interactive CLI to configure and deploy an OpenCPO EV charging platform.
Run this after a fresh clone, before 'docker compose up'.

Usage:
  python configure.py        # Interactive wizard (recommended)
  python configure.py --auto  # Non-interactive, use defaults
  python configure.py --help  # This message
"""

import os
import re
import sys
import shutil
import subprocess
import json
import secrets
import string

# ── ANSI Colors ─────────────────────────────────────────────────────────────

RESET = "\033[0m"
BOLD = "\033[1m"
DIM = "\033[2m"
CYAN = "\033[96m"
GREEN = "\033[92m"
YELLOW = "\033[93m"
RED = "\033[91m"
BLUE = "\033[94m"
MAGENTA = "\033[95m"
WHITE = "\033[97m"
BG_DARK = "\033[40m"
BG_BLUE = "\033[44m"

# ── Banner ─────────────────────────────────────────────────────────────────

BANNER = (
    "\n" + BOLD + CYAN + "\n"
    + "   \u2554\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u255d\n"
    + "   \u2551                                                             \u2551\n"
    + "   \u2551               ____                    _____ _____   ____     \u2551\n"
    + "   \u2551              / __ \\                  / ____|  __ \\ / __ \\    \u2551\n"
    + "   \u2551             | |  | |_ __   ___ _ __ | |    | |__) | |  | |   \u2551\n"
    + "   \u2551             | |  | | '_ \\ / _ \\ '_ \\| |    |  ___/| |  | |   \u2551\n"
    + "   \u2551             | |__| | |_) |  __/ | | | |____| |    | |__| |   \u2551\n"
    + "   \u2551              \\____/| .__/ \\___|_| |_|\\_____|_|     \\____/    \u2551\n"
    + "   \u2551                    | |                                       \u2551\n"
    + "   \u2551                    |_|                                       \u2551\n"
    + "   \u2551                                                             \u2551\n"
    + "   \u2551            Open Source EV Charging Platform                \u2551\n"
    + "   \u2551                                                             \u2551\n"
    + "   \u2551       Zero Trust \u00b7 OCPP 1.6/2.0.1 \u00b7 ISO 15118 \u00b7 PKI       \u2551\n"
    + "   \u2551                                                             \u2551\n"
    + "   \u255a\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u255d"
    + "\n" + RESET + "\n"
)




# ── Helpers ────────────────────────────────────────────────────────────────


def color(text, *codes):
    return "".join(codes) + text + RESET


def ask(prompt, default="", secret=False):
    """Prompt user with a default value displayed."""
    if default:
        prompt = f"{prompt} [{color(default, DIM)}]"
    prompt = f"{color('→', CYAN)} {prompt}: "

    if secret:
        import getpass
        value = getpass.getpass(prompt)
    else:
        value = input(prompt).strip()

    if not value and default:
        return default
    return value


def confirm(prompt, default=True):
    default_str = "Y/n" if default else "y/N"
    prompt = f"{color('→', YELLOW)} {prompt} [{default_str}]: "
    value = input(prompt).strip().lower()
    if not value:
        return default
    return value in ("y", "yes", "true", "1")


def section(title):
    """Print a section header."""
    width = 56
    padding = width - len(title) - 6
    left = padding // 2
    right = padding - left
    print()
    print(color(f"╔{'═' * (width-2)}╗", CYAN))
    print(color(f"║  {' ' * left}{title}{' ' * right}  ║", CYAN + BOLD))
    print(color(f"╚{'═' * (width-2)}╝", CYAN))


def check_docker():
    """Check if Docker and Docker Compose are available."""
    section("System Requirements Check")

    checks = []

    # Check Docker
    try:
        result = subprocess.run(
            ["docker", "--version"],
            capture_output=True, text=True, timeout=5
        )
        docker_ok = result.returncode == 0
        docker_version = result.stdout.strip() if docker_ok else ""
        checks.append(("Docker", docker_ok, docker_version))
    except (FileNotFoundError, subprocess.TimeoutExpired):
        checks.append(("Docker", False, "not found"))

    # Check Docker Compose
    for cmd in [["docker", "compose", "version"], ["docker-compose", "--version"]]:
        try:
            result = subprocess.run(
                cmd, capture_output=True, text=True, timeout=5
            )
            if result.returncode == 0:
                checks.append(("Docker Compose", True, result.stdout.strip()))
                break
        except (FileNotFoundError, subprocess.TimeoutExpired):
            continue
    else:
        checks.append(("Docker Compose", False, "not found"))

    for name, ok, detail in checks:
        status = color("✓", GREEN) if ok else color("✗", RED)
        detail_str = f"({detail})" if detail else ""
        print(f"  {status} {name} {color(detail_str, DIM)}")

    all_ok = all(ok for _, ok, _ in checks)

    if not all_ok:
        print()
        print(color("  ⚠  Missing dependencies detected.", YELLOW))
        print()
        print("  OpenCPO setup.sh can install these automatically:")
        print("    Run: ./setup.sh")
        print()
        print("  Or install manually:")
        for name, ok, _ in checks:
            if not ok:
                if "Docker" in name:
                    if "Compose" in name:
                        print("    • Docker Compose:  sudo apt install docker-compose-plugin")
                    else:
                        print("    • Docker:          curl -fsSL https://get.docker.com | sh")
        print()
        print("  Linux (apt):")
        print("    sudo apt-get update && sudo apt-get install -y \\")
        for name, ok, _ in checks:
            if not ok:
                if "Docker" in name and "Compose" not in name:
                    print("         docker.io \\")
                elif "Compose" in name:
                    print("         docker-compose-plugin \\")
        print()
        if not confirm("  Continue anyway?", default=False):
            print(color("  Aborting.", RED))
            sys.exit(1)
        print()

    return all_ok


def generate_secret(length=48):
    """Generate a cryptographically random secret."""
    alphabet = string.ascii_letters + string.digits + "!@#$%^&*"
    return "".join(secrets.choice(alphabet) for _ in range(length))


def generate_password(length=24):
    """Generate a random password without ambiguous characters."""
    alphabet = string.ascii_letters + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(length))


def validate_url(url):
    """Basic URL validation."""
    pattern = r"^https?://[a-zA-Z0-9][-a-zA-Z0-9.]*(:\d+)?(/.*)?$"
    return bool(re.match(pattern, url))


def validate_port(port):
    """Port validation."""
    try:
        p = int(port)
        return 1 <= p <= 65535
    except (ValueError, TypeError):
        return False


# ── Configuration ──────────────────────────────────────────────────────────


def gather_config():
    """Interactive configuration gathering."""
    config = {}

    section("Organization")

    config["org_name"] = ask("Organization name", "OpenCPO Demo")
    config["public_url"] = ask("Public URL (for QR codes, links)", "http://localhost")

    section("PostgreSQL Database")

    config["db_name"] = ask("Database name", "ocpp")
    config["db_user"] = ask("Database user", "ocpp")
    config["db_password"] = ask("Database password", generate_password(16), secret=True)
    config["db_port"] = ask("Database port", "5432")

    section("Redis Cache")

    config["redis_port"] = ask("Redis port", "6379")

    section("Core CSMS")

    config["secret_key"] = ask("Secret key (leave blank to generate)", generate_secret())
    config["log_level"] = ask("Log level", "INFO")
    config["ocpp16_port"] = ask("OCPP 1.6 WebSocket port", "9100")
    config["ocpp201_port"] = ask("OCPP 2.0.1 WebSocket port", "9201")
    config["api_port"] = ask("REST API port", "8000")

    section("Services Ports")

    config["admin_port"] = ask("CPO Admin dashboard port", "8080")
    config["charge_app_port"] = ask("Driver PWA port", "8003")
    config["compliance_port"] = ask("Compliance tester port", "8090")
    config["charger_farm_port"] = ask("Charger farm port", "8087")

    print()
    return config


def write_env(config):
    """Write .env file from gathered config."""
    env_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".env")

    content = f"""# ── OpenCPO Configuration ──────────────────────────────────────────────
# Generated by configure.py on {os.uname().nodename}
# ⚠  Keep this file secret — it contains database passwords and API keys.

# ── Organization ───────────────────────────────────────────────────────────
ORG_NAME={config["org_name"]}
PUBLIC_URL={config["public_url"]}

# ── PostgreSQL ─────────────────────────────────────────────────────────────
POSTGRES_DB={config["db_name"]}
POSTGRES_USER={config["db_user"]}
POSTGRES_PASSWORD={config["db_password"]}
POSTGRES_PORT={config["db_port"]}

# ── Redis ──────────────────────────────────────────────────────────────────
REDIS_PORT={config["redis_port"]}

# ── Core CSMS (ocpp-core) ──────────────────────────────────────────────────
SECRET_KEY={config["secret_key"]}
LOG_LEVEL={config["log_level"]}
OCPP_16_WS_PORT={config["ocpp16_port"]}
OCPP_201_WS_PORT={config["ocpp201_port"]}
OCPP_API_PORT={config["api_port"]}

# ── CPO Admin Dashboard ────────────────────────────────────────────────────
CPO_ADMIN_PORT={config["admin_port"]}

# ── Driver PWA ─────────────────────────────────────────────────────────────
CHARGE_APP_PORT={config["charge_app_port"]}

# ── Compliance Tester ──────────────────────────────────────────────────────
COMPLIANCE_PORT={config["compliance_port"]}

# ── Virtual Charger Farm ───────────────────────────────────────────────────
CHARGER_FARM_PORT={config["charger_farm_port"]}
"""

    # Backup existing .env if present
    if os.path.exists(env_path):
        backup = env_path + ".bak"
        shutil.copy2(env_path, backup)
        print(color(f"  Existing .env backed up to .env.bak", DIM))

    with open(env_path, "w") as f:
        f.write(content)

    return env_path


# ── Summary ────────────────────────────────────────────────────────────────


def show_summary(config, env_path):
    """Display a configuration summary."""
    print()
    print(color("┌" + "─" * 56 + "┐", CYAN))
    print(color("│", CYAN) + f"  {color('✓', GREEN)} {color('Configuration Complete', BOLD)}".ljust(55) + color("│", CYAN))
    print(color("├" + "─" * 56 + "┤", CYAN))

    services = [
        ("CPO Admin", f"http://localhost:{config['admin_port']}"),
        ("Driver PWA", f"http://localhost:{config['charge_app_port']}"),
        ("Compliance", f"http://localhost:{config['compliance_port']}"),
        ("Charger Farm", f"http://localhost:{config['charger_farm_port']}"),
        ("OCPP 1.6 WS", f"ws://localhost:{config['ocpp16_port']}"),
        ("OCPP 2.0.1 WS", f"ws://localhost:{config['ocpp201_port']}"),
        ("REST API", f"http://localhost:{config['api_port']}"),
        ("PostgreSQL", f"localhost:{config['db_port']}"),
        ("Redis", f"localhost:{config['redis_port']}"),
    ]

    for name, url in services:
        print(color("│", CYAN) + f"  {name:20s} {color(url, GREEN)}".ljust(55) + color("│", CYAN))

    print(color("│", CYAN) + f"  {color('─' * 53, DIM)}".ljust(55) + color("│", CYAN))
    print(color("│", CYAN) + f"  {color('Org:', DIM)} {config['org_name']}".ljust(55) + color("│", CYAN))
    print(color("│", CYAN) + f"  {color('URL:', DIM)} {config['public_url']}".ljust(55) + color("│", CYAN))
    print(color("│", CYAN) + f"  {color('Key:', DIM)} {config['secret_key'][:16]}...".ljust(55) + color("│", CYAN))

    print(color("└" + "─" * 56 + "┘", CYAN))

    print()
    print(color(f"  Config saved to: {env_path}", DIM))


# ── Deploy ─────────────────────────────────────────────────────────────────


def build_and_start():
    """Build Docker images and start services."""
    print()
    section("Build & Deploy")

    if confirm("Build Docker images now?"):
        print()
        print(color("  Building all images (first build: 5-10 minutes)...", DIM))
        print()
        result = subprocess.run(
            ["docker", "compose", "build"],
            cwd=os.path.dirname(os.path.abspath(__file__)),
        )
        if result.returncode != 0:
            print()
            print(color("  ⚠  Build failed. Check the output above.", RED))
            if confirm("  Start with existing images anyway?", default=False):
                pass
            else:
                return

        if confirm("Start all services now?"):
            print()
            print(color("  Starting services...", DIM))
            subprocess.run(
                ["docker", "compose", "up", "-d"],
                cwd=os.path.dirname(os.path.abspath(__file__)),
            )
            print()
            print(color("  ✓ Services started!", GREEN))
            print()
            print("  Check status:    docker compose ps")
            print("  View logs:       docker compose logs -f")
    else:
        print()
        print("  Run later:")
        print("    docker compose build && docker compose up -d")


# ── Main ───────────────────────────────────────────────────────────────────


def _defaults():
    """Return default config for --auto mode."""
    return {
        "org_name": "OpenCPO Demo",
        "public_url": "http://localhost",
        "db_name": "ocpp",
        "db_user": "ocpp",
        "db_password": generate_password(16),
        "db_port": "5432",
        "redis_port": "6379",
        "secret_key": generate_secret(),
        "log_level": "INFO",
        "ocpp16_port": "9100",
        "ocpp201_port": "9201",
        "api_port": "8000",
        "admin_port": "8080",
        "charge_app_port": "8003",
        "compliance_port": "8090",
        "charger_farm_port": "8087",
    }


def main():
    auto_mode = "--auto" in sys.argv

    print(BANNER)

    if auto_mode:
        config = _defaults()
        print(color("  Auto-mode: using defaults", DIM))
    else:
        check_docker()
        if not confirm("Ready to configure OpenCPO?"):
            print(color("\n  Exiting. Run 'python configure.py' when ready.", DIM))
            return
        config = gather_config()

    env_path = write_env(config)
    show_summary(config, env_path)

    if not auto_mode:
        build_and_start()

        print()
        print(color("  ──────────────────────────────────────────────────────", DIM))
        print(color(f"  ⚡  {color('OpenCPO is ready!', BOLD + GREEN)}", BOLD))
        print(color("  ──────────────────────────────────────────────────────", DIM))
        print()
        print("  Next steps:")
        print(f"    1. Open {color('http://localhost:' + config['admin_port'], CYAN + BOLD)} — CPO Admin")
        print(f"    2. Add chargers via the dashboard")
        print(f"    3. Configure your network under Settings")
        print(f"    4. Download certs for your chargers")
        print()
        print("  Docs:  https://github.com/opencpo/opencpo")
        print("  Community:  https://discord.gg/ra9pnygmrt")
        print()
    else:
        print()
        print(color(f"  Auto-config complete. .env written to {env_path}", DIM))


if __name__ == "__main__":
    main()

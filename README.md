# Container Sentinel 🛡️

A wrapper around [Trivy](https://github.com/aquasecurity/trivy) that scans your running Docker containers for known vulnerabilities, feeds the results to an LLM for a human-readable summary, and optionally emails you the report.

We stand on the shoulders of giants — Trivy does the real work. We just glue it together with some AI and a nice terminal experience.

**Minimal footprint** — everything runs inside a hardened container. When the scan is done, we try to leave as little trace as possible. Not quite forensic-grade, but we do our best.

## Quick Install

```bash
bash <(curl -sSL https://raw.githubusercontent.com/doradame/container-sentinel/main/install.sh)
```

Or if you prefer to inspect first (you should):

```bash
curl -sSL https://raw.githubusercontent.com/doradame/container-sentinel/main/install.sh -o install.sh
less install.sh
bash install.sh
```

## What it does

1. Scans **all running Docker containers** for HIGH/CRITICAL vulnerabilities using [Trivy](https://github.com/aquasecurity/trivy)
2. Sends the results to an **LLM** (OpenAI or Anthropic) for a summary with remediation suggestions
3. **Saves a report** to `~/.container-sentinel/reports/` (always, with automatic rotation)
4. Optionally **emails you the report** via [Resend](https://resend.com)
5. Tracks when the last scan ran — if it's been too long, it reminds you

## Requirements

- Docker (that's it)

## Security considerations

We tried to be careful, but this is a small project — not a hardened enterprise product. Here's what we do:

- **API keys are passed via mounted secret files**, not environment variables (invisible to `docker inspect`)
- Docker socket is mounted **read-only** (but honestly, r/o on the socket doesn't mean much — it's still the Docker socket)
- The sentinel container runs with **zero capabilities** (`--cap-drop=ALL`)
- **`--security-opt=no-new-privileges`** — no privilege escalation
- **Memory capped at 1GB** — protects the host from OOM
- Trivy image is **pinned to a specific SHA256 digest** (supply chain protection)
- The sentinel container is **excluded from its own scan**
- Secrets are **wiped** after each run
- Config file permissions: `600`

The Docker socket remains a risk — there's no way around that if you want to scan running containers. If you know a better way, PRs welcome.

## Configuration

On first run, the installer will ask you for:

| Parameter | Required | Description |
|-----------|----------|-------------|
| LLM Provider | ✅ | `openai` or `anthropic` |
| LLM Model | ✅ | e.g. `gpt-4o`, `claude-sonnet-4-20250514` |
| LLM API Key | ✅ | Your API key for the chosen provider |
| Resend API Key | ❌ | For email reports |
| Sender Email | ❌ | Verified sender on Resend |
| Recipient Email | ❌ | Where to send reports |

Config is stored in `~/.container-sentinel/config` (mode 600).

## Usage

```bash
# Run a scan
container-sentinel

# Verbose output
container-sentinel --verbose

# Dry run — show what would happen
container-sentinel --dry-run

# Reconfigure
container-sentinel --setup

# Schedule weekly/daily scans
container-sentinel --schedule

# Show version
container-sentinel --version

# Uninstall
container-sentinel --uninstall
```

## Reports

Reports are **always saved** to `~/.container-sentinel/reports/` as markdown files, regardless of email configuration. Automatic rotation keeps the last 30.

Each report includes server info:

| Field | Example |
|-------|---------|
| Hostname | prod-web-01 |
| Public IP | 203.0.113.42 |
| OS/Kernel | Linux 6.1.0 x86_64 |
| Uptime | up 42 days |
| Docker | 24.0.7 |
| Containers | 8 running |
| Compose | /opt/myapp/docker-compose.yml |

## How it works

```
┌─────────────────────────────────────────────────┐
│  Host                                           │
│                                                 │
│  sentinel.sh                                    │
│    ├── writes API key to secret file            │
│    └── docker run (hardened)                    │
│          ├── reads key from /run/secrets/       │
│          ├── trivy scans all containers         │
│          ├── pre-filters results (top 10 CVEs)  │
│          ├── LLM summarizes findings            │
│          ├── saves report + raw scan to volume  │
│          └── (optional) emails summary + raw    │
│                                                 │
│  Hardening:                                     │
│    --cap-drop=ALL                               │
│    --security-opt=no-new-privileges             │
│    --memory=1g                                  │
│                                                 │
│  After run: secrets wiped, container removed    │
└─────────────────────────────────────────────────┘
```

## Error handling

- **API key validation** before scanning (fails fast)
- **Retry with exponential backoff** on LLM API calls (handles 429/5xx)
- **Disk space check** before starting (warns at 85%, blocks at 95%)
- **Graceful degradation** — if email fails, report is still saved
- **Self-exclusion** — won't scan its own container

## Credits

- [Trivy](https://github.com/aquasecurity/trivy) by Aqua Security — the actual vulnerability scanner. Without them, this project wouldn't exist.
- [Resend](https://resend.com) — for making email not terrible.
- OpenAI and Anthropic — for the AI summarization.

## Limitations

- The Docker socket gives broad access. We mitigate with hardening, but it's not perfect.
- LLM analysis quality depends on the model and the amount of vulnerabilities (large scans get truncated).
- This is a small side project, not a replacement for proper security tooling. Use it alongside your existing practices, not instead of them.

## Uninstall

```bash
container-sentinel --uninstall
```

## License

MIT

## Author

[@doradame](https://github.com/doradame) — [mojalab.com](https://mojalab.com)

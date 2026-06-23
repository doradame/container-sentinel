# Container Sentinel 🛡️

Automated container vulnerability scanner with AI-powered summaries and optional email reports.

**Zero footprint on your host** — everything runs inside containers. When the scan is done, nothing is left behind. Like a forensic tool.

## Quick Install

```bash
curl -sSL https://raw.githubusercontent.com/doradame/container-sentinel/main/install.sh | bash
```

## What it does

1. Scans **all running Docker containers** for known vulnerabilities using [Trivy](https://github.com/aquasecurity/trivy) (pinned version for reproducibility)
2. Sends the results to an **LLM** (OpenAI or Anthropic) for a human-readable summary with remediation suggestions
3. **Saves a report** to `~/.container-sentinel/reports/` (always, with automatic rotation)
4. Optionally **emails you the report** via [Resend](https://resend.com)
5. Tracks when the last scan ran — if it's been too long, it nags you: *"Toc toc... it's been 3 weeks..."*

## Requirements

- Docker (that's it)

## Security

- **API keys are passed via mounted secret files**, not environment variables (invisible to `docker inspect`)
- The Docker socket is mounted **read-only**
- The sentinel container is **excluded from its own scan** (no infinite loops)
- Secrets are **securely wiped** after each run
- Config file permissions: `600` (owner-only)

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
# Run a scan now
container-sentinel

# Run with verbose output
container-sentinel --verbose

# Dry run — show what would happen without scanning
container-sentinel --dry-run

# Reconfigure
container-sentinel --setup

# Schedule weekly/daily scan (sets up cron)
container-sentinel --schedule

# Show version
container-sentinel --version

# Uninstall
container-sentinel --uninstall
```

## Reports

Reports are **always saved** to `~/.container-sentinel/reports/` as markdown files, regardless of email configuration. Automatic rotation keeps the last 30 reports.

```
~/.container-sentinel/reports/
├── sentinel-report_2026-06-24_083012.md
├── sentinel-report_2026-06-17_080005.md
└── sentinel-report_2026-06-10_080003.md
```

Each report includes a server info table:

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
│  Host (your machine)                            │
│                                                 │
│  sentinel.sh                                    │
│    ├── writes API key to secret file            │
│    └── docker run container-sentinel            │
│          ├── reads key from /run/secrets/       │
│          ├── trivy scan all containers ───┐     │
│          ├── LLM summarize + suggest      │     │
│          ├── save report to volume        │     │
│          └── (optional) email via Resend  │     │
│                                           │     │
│  /var/run/docker.sock (ro) ◄──────────────┘     │
│                                                 │
│  After run: secrets wiped, container removed    │
└─────────────────────────────────────────────────┘
```

## Error Handling

- **API key validation** before scanning (fails fast, not after 10 minutes of trivy)
- **Retry with exponential backoff** on LLM API calls (handles 429/5xx)
- **Graceful degradation** — if email fails, report is still saved and displayed
- **Self-exclusion** — the sentinel container won't scan itself

## Uninstall

```bash
container-sentinel --uninstall
# Removes: ~/.container-sentinel (config, secrets, reports), binary, cron entry
# Removes the sentinel Docker image
# Secrets are securely shredded
```

## License

MIT

## Author

[@doradame](https://github.com/doradame) — [mojalab.com](https://mojalab.com)

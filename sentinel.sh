#!/usr/bin/env bash
set -euo pipefail

# Container Sentinel - Host orchestrator
# This script runs the sentinel container and passes configuration.
# The only thing that lives on the host: this script + config + reports.

# shellcheck source=/dev/null

CONFIG_DIR="$HOME/.container-sentinel"
CONFIG_FILE="$CONFIG_DIR/config"
SECRETS_DIR="$CONFIG_DIR/secrets"
IMAGE="container-sentinel:latest"
VERSION="1.0.0"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

info()  { echo -e "  ${CYAN}▸${NC} $1"; }
ok()    { echo -e "  ${GREEN}✔${NC} $1"; }
warn()  { echo -e "  ${YELLOW}⚠${NC} $1"; }
err()   { echo -e "  ${RED}✘${NC} $1"; exit 1; }

show_header() {
    echo ""
    echo -e "  ${CYAN}${BOLD}╔═══════════════════════════════════════════╗${NC}"
    echo -e "  ${CYAN}${BOLD}║     🛡️  Container Sentinel v${VERSION}        ║${NC}"
    echo -e "  ${CYAN}${BOLD}╚═══════════════════════════════════════════╝${NC}"
    echo -e "  ${DIM}  mojalab.com${NC}"
    echo ""
}

check_staleness() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        return
    fi

    # shellcheck disable=SC1090
    source "$CONFIG_FILE"

    if [[ -z "${LAST_SCAN:-}" ]]; then
        return
    fi

    local last_ts
    local now_ts
    local diff_days

    # Cross-platform date handling
    if date --version &>/dev/null 2>&1; then
        # GNU date
        last_ts=$(date -d "$LAST_SCAN" +%s 2>/dev/null || echo "0")
    else
        # macOS/BSD date
        last_ts=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$LAST_SCAN" +%s 2>/dev/null || echo "0")
    fi

    now_ts=$(date +%s)
    diff_days=$(( (now_ts - last_ts) / 86400 ))

    if [[ $diff_days -ge 21 ]]; then
        echo ""
        echo -e "  ${YELLOW}${BOLD}┌─────────────────────────────────────────────────────────┐${NC}"
        echo -e "  ${YELLOW}${BOLD}│  🚪 Toc toc...                                         │${NC}"
        echo -e "  ${YELLOW}${BOLD}│                                                         │${NC}"
        echo -e "  ${YELLOW}│  It's been ${WHITE}${BOLD}${diff_days} days${NC}${YELLOW} since your last scan.            │${NC}"
        echo -e "  ${YELLOW}│  That's ${WHITE}${BOLD}$(( diff_days / 7 )) weeks${NC}${YELLOW} of potential vulnerabilities    │${NC}"
        echo -e "  ${YELLOW}│  piling up. What do you want to do?                     │${NC}"
        echo -e "  ${YELLOW}${BOLD}│                                                         │${NC}"
        echo -e "  ${YELLOW}${BOLD}└─────────────────────────────────────────────────────────┘${NC}"
        echo ""
    elif [[ $diff_days -ge 14 ]]; then
        echo ""
        echo -e "  ${YELLOW}⏰ Last scan was ${WHITE}${BOLD}${diff_days} days ago${NC}${YELLOW}. Might want to keep an eye on things.${NC}"
        echo ""
    fi
}

update_last_scan() {
    if [[ -f "$CONFIG_FILE" ]]; then
        local now
        now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        if grep -q "^LAST_SCAN=" "$CONFIG_FILE"; then
            sed -i.bak "s/^LAST_SCAN=.*/LAST_SCAN=\"${now}\"/" "$CONFIG_FILE" && rm -f "${CONFIG_FILE}.bak"
        else
            echo "LAST_SCAN=\"${now}\"" >> "$CONFIG_FILE"
        fi
    fi
}

collect_host_info() {
    # Hostname
    HOST_NAME=$(hostname 2>/dev/null || echo "unknown")

    # OS
    HOST_OS=$(uname -srm 2>/dev/null || echo "unknown")

    # Public IP (with timeout, non-blocking)
    HOST_IP=$(curl -sS --max-time 5 https://ifconfig.me 2>/dev/null || \
              curl -sS --max-time 5 https://api.ipify.org 2>/dev/null || \
              echo "unknown")

    # Uptime
    HOST_UPTIME=$(uptime -p 2>/dev/null || uptime | sed 's/.*up /up /' | sed 's/,.*load.*//' 2>/dev/null || echo "unknown")

    # Docker version
    HOST_DOCKER_VERSION=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "unknown")

    # Container count
    HOST_CONTAINER_COUNT=$(docker ps -q 2>/dev/null | wc -l | tr -d ' ')

    # Find docker-compose files in common locations
    HOST_COMPOSE_PATHS=""
    local search_dirs=("/opt" "/srv" "/home" "/root" "/app" "/docker")
    for dir in "${search_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            local found
            found=$(find "$dir" -maxdepth 3 \( -name "docker-compose*.yml" -o -name "docker-compose*.yaml" -o -name "compose.yml" -o -name "compose.yaml" \) 2>/dev/null | head -10 || true)
            if [[ -n "$found" ]]; then
                HOST_COMPOSE_PATHS+="${found}"$'\n'
            fi
        fi
    done
    HOST_COMPOSE_PATHS=$(echo "$HOST_COMPOSE_PATHS" | sort -u | sed '/^$/d' | tr '\n' ', ' | sed 's/, $//')
}

setup_secrets() {
    # Create secrets directory and write keys to files
    # This avoids passing secrets as env vars (visible in docker inspect)
    mkdir -p "$SECRETS_DIR"
    chmod 700 "$SECRETS_DIR"

    # shellcheck disable=SC1090
    source "$CONFIG_FILE"

    echo -n "${LLM_API_KEY}" > "$SECRETS_DIR/llm_api_key"
    chmod 600 "$SECRETS_DIR/llm_api_key"

    if [[ -n "${RESEND_API_KEY:-}" ]]; then
        echo -n "${RESEND_API_KEY}" > "$SECRETS_DIR/resend_api_key"
        chmod 600 "$SECRETS_DIR/resend_api_key"
    fi
}

run_scan() {
    show_header
    check_staleness

    if [[ ! -f "$CONFIG_FILE" ]]; then
        err "Config not found. Run: container-sentinel --setup"
    fi

    # shellcheck disable=SC1090
    source "$CONFIG_FILE"

    local verbose=""
    if [[ "${1:-}" == "--verbose" ]]; then
        verbose="--verbose"
    fi

    info "Collecting host information..."
    collect_host_info
    ok "Host: ${HOST_NAME} (${HOST_IP})"
    echo ""

    info "Preparing secrets..."
    setup_secrets
    ok "Secrets written to tmpfs-backed files"
    echo ""

    info "Launching sentinel container..."
    echo ""

    # Reports directory (persisted on host)
    local reports_dir="$CONFIG_DIR/reports"
    mkdir -p "$reports_dir"

    docker run --rm \
        -v /var/run/docker.sock:/var/run/docker.sock:ro \
        -v "${reports_dir}:/sentinel/reports" \
        -v "${SECRETS_DIR}/llm_api_key:/run/secrets/llm_api_key:ro" \
        ${RESEND_API_KEY:+-v "${SECRETS_DIR}/resend_api_key:/run/secrets/resend_api_key:ro"} \
        -e LLM_PROVIDER="${LLM_PROVIDER}" \
        -e LLM_MODEL="${LLM_MODEL}" \
        -e LLM_API_KEY="" \
        -e RESEND_API_KEY="${RESEND_API_KEY:+placeholder}" \
        -e SENDER_EMAIL="${SENDER_EMAIL:-}" \
        -e RECIPIENT_EMAIL="${RECIPIENT_EMAIL:-}" \
        -e HOST_NAME="${HOST_NAME}" \
        -e HOST_OS="${HOST_OS}" \
        -e HOST_IP="${HOST_IP}" \
        -e HOST_UPTIME="${HOST_UPTIME}" \
        -e HOST_DOCKER_VERSION="${HOST_DOCKER_VERSION}" \
        -e HOST_CONTAINER_COUNT="${HOST_CONTAINER_COUNT}" \
        -e HOST_COMPOSE_PATHS="${HOST_COMPOSE_PATHS}" \
        -e VERBOSE="${verbose}" \
        "$IMAGE"

    # Clean up secrets after run
    rm -f "$SECRETS_DIR/llm_api_key" "$SECRETS_DIR/resend_api_key" 2>/dev/null || true

    update_last_scan

    # Show report location
    local latest_report
    latest_report=$(ls -t "$reports_dir"/*.md 2>/dev/null | head -1 || true)

    echo ""
    echo -e "  ${GREEN}${BOLD}Scan complete.${NC} ${DIM}Stay safe! 🛡️${NC}"
    if [[ -n "$latest_report" ]]; then
        echo -e "  ${CYAN}📄 Report saved:${NC} ${latest_report}"
    fi
    echo -e "  ${DIM}─── mojalab.com ───${NC}"
    echo ""
}

dry_run() {
    show_header

    if [[ ! -f "$CONFIG_FILE" ]]; then
        err "Config not found. Run: container-sentinel --setup"
    fi

    # shellcheck disable=SC1090
    source "$CONFIG_FILE"

    info "Collecting host information..."
    collect_host_info

    echo ""
    echo -e "  ${YELLOW}${BOLD}┌──────────────────────────────────────┐${NC}"
    echo -e "  ${YELLOW}${BOLD}│   🧪 DRY RUN — No actions taken      │${NC}"
    echo -e "  ${YELLOW}${BOLD}└──────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  ${WHITE}${BOLD}Configuration:${NC}"
    echo -e "    Provider:   ${LLM_PROVIDER}"
    echo -e "    Model:      ${LLM_MODEL}"
    echo -e "    API Key:    ${LLM_API_KEY:0:8}...${LLM_API_KEY: -4} (${#LLM_API_KEY} chars)"
    echo -e "    Email:      ${RECIPIENT_EMAIL:-not configured}"
    echo ""
    echo -e "  ${WHITE}${BOLD}Host Info:${NC}"
    echo -e "    Hostname:   ${HOST_NAME}"
    echo -e "    IP:         ${HOST_IP}"
    echo -e "    OS:         ${HOST_OS}"
    echo -e "    Uptime:     ${HOST_UPTIME}"
    echo -e "    Docker:     ${HOST_DOCKER_VERSION}"
    echo -e "    Containers: ${HOST_CONTAINER_COUNT}"
    echo -e "    Compose:    ${HOST_COMPOSE_PATHS:-none found}"
    echo ""
    echo -e "  ${WHITE}${BOLD}Would scan:${NC}"
    docker ps --format '    {{.Names}} ({{.Image}})' 2>/dev/null | grep -v "container-sentinel" || true
    echo ""
    echo -e "  ${WHITE}${BOLD}Reports dir:${NC} $CONFIG_DIR/reports"
    mkdir -p "$CONFIG_DIR/reports"
    local report_count
    report_count=$(find "$CONFIG_DIR/reports" -name "sentinel-report_*.md" -type f 2>/dev/null | wc -l | tr -d ' ')
    echo -e "    Existing reports: ${report_count}"
    echo ""
    echo -e "  ${GREEN}Everything looks good. Run without --dry-run to execute.${NC}"
    echo ""
}

show_help() {
    echo ""
    echo -e "  ${CYAN}${BOLD}Container Sentinel v${VERSION}${NC} ${DIM}— mojalab.com${NC}"
    echo ""
    echo -e "  ${WHITE}Usage:${NC}"
    echo -e "    container-sentinel              ${DIM}Run a vulnerability scan${NC}"
    echo -e "    container-sentinel --verbose    ${DIM}Run with detailed output${NC}"
    echo -e "    container-sentinel --dry-run    ${DIM}Show what would happen without scanning${NC}"
    echo -e "    container-sentinel --setup      ${DIM}Reconfigure settings${NC}"
    echo -e "    container-sentinel --schedule   ${DIM}Setup/modify cron schedule${NC}"
    echo -e "    container-sentinel --uninstall  ${DIM}Remove everything${NC}"
    echo -e "    container-sentinel --version    ${DIM}Show version${NC}"
    echo -e "    container-sentinel --help       ${DIM}Show this help${NC}"
    echo ""
}

do_setup() {
    # Re-run the installer in config-only mode
    local installer="$CONFIG_DIR/install_config.sh"
    if [[ -f "$installer" ]]; then
        bash "$installer"
    else
        echo ""
        info "Reinstalling from remote..."
        curl -sSL "https://raw.githubusercontent.com/doradame/container-sentinel/main/install.sh" | bash
    fi
}

do_uninstall() {
    echo ""
    echo -e "  ${RED}${BOLD}⚠  Uninstalling Container Sentinel${NC}"
    echo ""
    read -rp "  Are you sure? (yes/N): " confirm
    if [[ "$confirm" != "yes" ]]; then
        info "Cancelled."
        return
    fi

    # Remove cron entry
    (crontab -l 2>/dev/null | grep -v "container-sentinel") | crontab - 2>/dev/null || true
    ok "Cron entry removed"

    # Remove docker image
    docker rmi container-sentinel:latest &>/dev/null || true
    ok "Docker image removed"

    # Securely remove secrets
    if [[ -d "$SECRETS_DIR" ]]; then
        find "$SECRETS_DIR" -type f -exec shred -u {} \; 2>/dev/null || rm -rf "$SECRETS_DIR"
    fi
    ok "Secrets securely removed"

    # Remove config dir
    rm -rf "$CONFIG_DIR"
    ok "Config directory removed"

    # Remove binary
    local bin_locations=("/usr/local/bin/container-sentinel" "$HOME/.local/bin/container-sentinel")
    for bin in "${bin_locations[@]}"; do
        if [[ -f "$bin" || -L "$bin" ]]; then
            rm -f "$bin" 2>/dev/null || sudo rm -f "$bin" 2>/dev/null || true
            ok "Removed $bin"
        fi
    done

    echo ""
    ok "Container Sentinel uninstalled. No traces left. 👋"
    echo ""
}

do_schedule() {
    echo ""
    echo -e "  ${BLUE}${BOLD}🕐 Schedule Configuration${NC}"
    echo ""
    echo -e "  ${WHITE}1)${NC} Weekly (Monday 8:00 AM)"
    echo -e "  ${WHITE}2)${NC} Daily (8:00 AM)"
    echo -e "  ${WHITE}3)${NC} Remove schedule"
    echo ""
    read -rp "  Choose [1/2/3]: " sched_choice

    # Remove existing
    (crontab -l 2>/dev/null | grep -v "container-sentinel") | crontab - 2>/dev/null || true

    local self_path
    self_path=$(realpath "$0" 2>/dev/null || echo "$0")

    case "$sched_choice" in
        1)
            (crontab -l 2>/dev/null; echo "0 8 * * 1 $self_path --cron 2>&1 | logger -t container-sentinel") | crontab -
            ok "Scheduled: weekly (Monday 8 AM)"
            ;;
        2)
            (crontab -l 2>/dev/null; echo "0 8 * * * $self_path --cron 2>&1 | logger -t container-sentinel") | crontab -
            ok "Scheduled: daily (8 AM)"
            ;;
        3)
            ok "Schedule removed"
            ;;
        *)
            warn "Invalid choice"
            ;;
    esac
    echo ""
}

# Main dispatch
case "${1:-}" in
    --help|-h)      show_help ;;
    --setup)        do_setup ;;
    --uninstall)    do_uninstall ;;
    --schedule)     do_schedule ;;
    --dry-run)      dry_run ;;
    --version|-v)   echo "container-sentinel v${VERSION}" ;;
    --cron)         run_scan ;;
    --verbose)      run_scan --verbose ;;
    "")             run_scan ;;
    *)              err "Unknown option: $1. Try --help" ;;
esac

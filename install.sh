#!/usr/bin/env bash
set -euo pipefail

# Container Sentinel Installer
#
# USAGE (download and run — required for interactive prompts):
#   bash <(curl -sSL https://raw.githubusercontent.com/doradame/container-sentinel/main/install.sh)
#
# Alternative:
#   curl -sSL https://raw.githubusercontent.com/doradame/container-sentinel/main/install.sh -o /tmp/install-sentinel.sh && bash /tmp/install-sentinel.sh

REPO="doradame/container-sentinel"
BRANCH="main"
BASE_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}"
INSTALL_DIR="$HOME/.container-sentinel"
BIN_PATH="/usr/local/bin/container-sentinel"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Rainbow colors for animation
RAINBOW=('\033[38;5;196m' '\033[38;5;202m' '\033[38;5;208m' '\033[38;5;214m' '\033[38;5;220m' '\033[38;5;226m' '\033[38;5;118m' '\033[38;5;46m' '\033[38;5;48m' '\033[38;5;51m' '\033[38;5;45m' '\033[38;5;39m' '\033[38;5;33m' '\033[38;5;63m' '\033[38;5;129m' '\033[38;5;165m')

info()  { echo -e "  ${CYAN}▸${NC} $1"; }
ok()    { echo -e "  ${GREEN}✔${NC} $1"; }
warn()  { echo -e "  ${YELLOW}⚠${NC} $1"; }
err()   { echo -e "  ${RED}✘${NC} $1"; exit 1; }

# Animated text — used in the wizard
type_text() {
    local text="$1"
    local color="${2:-$NC}"
    for (( i=0; i<${#text}; i++ )); do
        echo -ne "${color}${text:$i:1}${NC}"
        sleep 0.02
    done
    echo ""
}

banner() {
    clear 2>/dev/null || true
    echo ""
    
    # Animated shield entrance
    local shield=(
        "                    ▄▄▄▄▄▄▄▄▄▄▄"
        "               ▄█████████████████▄"
        "              ███████████████████████"
        "             █████████████████████████"
        "             █████████████████████████"
        "             █████  ▄▄███▄▄  █████████"
        "             █████ ████████  █████████"
        "             █████  ▀▀███▀▀  █████████"
        "             ██████▄▄     ▄▄██████████"
        "              ████████████████████████"
        "               ██████████████████████"
        "                ████████████████████"
        "                  ████████████████"
        "                    ████████████"
        "                      ████████"
        "                        ████"
        "                         ██"
    )
    
    for i in "${!shield[@]}"; do
        local color_idx=$(( i % ${#RAINBOW[@]} ))
        echo -e "  ${RAINBOW[$color_idx]}${shield[$i]}${NC}"
        sleep 0.04
    done
    
    echo ""
    sleep 0.2
    
    # Main title with gradient
    echo -e "  ${RAINBOW[8]}   ██████╗ ██████╗ ███╗   ██╗████████╗ █████╗ ██╗███╗   ██╗███████╗██████╗ ${NC}"
    sleep 0.03
    echo -e "  ${RAINBOW[9]}  ██╔════╝██╔═══██╗████╗  ██║╚══██╔══╝██╔══██╗██║████╗  ██║██╔════╝██╔══██╗${NC}"
    sleep 0.03
    echo -e "  ${RAINBOW[10]}  ██║     ██║   ██║██╔██╗ ██║   ██║   ███████║██║██╔██╗ ██║█████╗  ██████╔╝${NC}"
    sleep 0.03
    echo -e "  ${RAINBOW[11]}  ██║     ██║   ██║██║╚██╗██║   ██║   ██╔══██║██║██║╚██╗██║██╔══╝  ██╔══██╗${NC}"
    sleep 0.03
    echo -e "  ${RAINBOW[12]}  ╚██████╗╚██████╔╝██║ ╚████║   ██║   ██║  ██║██║██║ ╚████║███████╗██║  ██║${NC}"
    sleep 0.03
    echo -e "  ${RAINBOW[13]}   ╚═════╝ ╚═════╝ ╚═╝  ╚═══╝   ╚═╝   ╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝${NC}"
    echo ""
    echo -e "  ${MAGENTA}  ███████╗███████╗███╗   ██╗████████╗██╗███╗   ██╗███████╗██╗     ${NC}"
    sleep 0.03
    echo -e "  ${MAGENTA}  ██╔════╝██╔════╝████╗  ██║╚══██╔══╝██║████╗  ██║██╔════╝██║     ${NC}"
    sleep 0.03
    echo -e "  ${MAGENTA}  ███████╗█████╗  ██╔██╗ ██║   ██║   ██║██╔██╗ ██║█████╗  ██║     ${NC}"
    sleep 0.03
    echo -e "  ${MAGENTA}  ╚════██║██╔══╝  ██║╚██╗██║   ██║   ██║██║╚██╗██║██╔══╝  ██║     ${NC}"
    sleep 0.03
    echo -e "  ${MAGENTA}  ███████║███████╗██║ ╚████║   ██║   ██║██║ ╚████║███████╗███████╗${NC}"
    sleep 0.03
    echo -e "  ${MAGENTA}  ╚══════╝╚══════╝╚═╝  ╚═══╝   ╚═╝   ╚═╝╚═╝  ╚═══╝╚══════╝╚══════╝${NC}"
    
    echo ""
    echo -e "  ${DIM}─────────────────────────────────────────────────────────────────────────${NC}"
    echo ""
    
    # Mojalab.com branding with pulsing effect
    echo -e "  ${WHITE}${BOLD}                    ╔══════════════════════╗${NC}"
    echo -e "  ${WHITE}${BOLD}                    ║   ${CYAN}★ ${YELLOW}M O J A L A B${CYAN} ★${WHITE}   ║${NC}"
    echo -e "  ${WHITE}${BOLD}                    ║     ${DIM}${CYAN}mojalab.com${NC}${WHITE}${BOLD}      ║${NC}"
    echo -e "  ${WHITE}${BOLD}                    ╚══════════════════════╝${NC}"
    
    echo ""
    echo -e "  ${DIM}─────────────────────────────────────────────────────────────────────────${NC}"
    echo -e "  ${DIM}  Vulnerability Scanner • AI-Powered Analysis • Zero Footprint${NC}"
    echo -e "  ${DIM}─────────────────────────────────────────────────────────────────────────${NC}"
    echo ""
    
    sleep 0.5
    type_text "  Initializing setup..." "$DIM"
}

check_docker() {
    if ! command -v docker &>/dev/null; then
        err "Docker is not installed. Please install Docker first: https://docs.docker.com/get-docker/"
    fi
    if ! docker info &>/dev/null; then
        err "Docker daemon is not running or you don't have permission. Try: sudo usermod -aG docker \$USER"
    fi
    ok "Docker is available and running"
}

# Progress bar animation
progress_bar() {
    local current=$1
    local total=$2
    local label="${3:-}"
    local width=40
    local pct=$(( current * 100 / total ))
    local filled=$(( current * width / total ))
    local empty=$(( width - filled ))
    
    local bar=""
    for (( i=0; i<filled; i++ )); do bar+="█"; done
    for (( i=0; i<empty; i++ )); do bar+="░"; done
    
    local color_idx=$(( current * ${#RAINBOW[@]} / total ))
    [[ $color_idx -ge ${#RAINBOW[@]} ]] && color_idx=$(( ${#RAINBOW[@]} - 1 ))
    
    echo -ne "\r  ${RAINBOW[$color_idx]}${bar}${NC} ${DIM}${pct}%${NC} ${label}"
}

prompt_config() {
    echo ""
    echo -e "  ${CYAN}${BOLD}┌──────────────────────────────────────┐${NC}"
    echo -e "  ${CYAN}${BOLD}│       ⚙️  Configuration Wizard        │${NC}"
    echo -e "  ${CYAN}${BOLD}└──────────────────────────────────────┘${NC}"
    echo ""

    # LLM Provider
    echo -e "  ${WHITE}${BOLD}LLM Provider${NC}"
    echo -e "  ${DIM}Which AI brain should analyze your vulnerabilities?${NC}"
    echo ""
    echo -e "    ${GREEN}1)${NC} OpenAI    ${DIM}(GPT-4o, GPT-4-turbo, ...)${NC}"
    echo -e "    ${MAGENTA}2)${NC} Anthropic ${DIM}(Claude Sonnet, Claude Opus, ...)${NC}"
    echo ""
    while true; do
        read -rp "  Choose [1/2]: " provider_choice < /dev/tty
        case "$provider_choice" in
            1) LLM_PROVIDER="openai"; break ;;
            2) LLM_PROVIDER="anthropic"; break ;;
            *) warn "Pick 1 or 2, amico" ;;
        esac
    done
    ok "Provider: $LLM_PROVIDER"
    echo ""

    # LLM Model
    if [[ "$LLM_PROVIDER" == "openai" ]]; then
        DEFAULT_MODEL="gpt-4o"
        echo -e "  ${WHITE}${BOLD}Model${NC} ${DIM}(popular: gpt-4o, gpt-4-turbo, gpt-4o-mini)${NC}"
    else
        DEFAULT_MODEL="claude-sonnet-4-20250514"
        echo -e "  ${WHITE}${BOLD}Model${NC} ${DIM}(popular: claude-sonnet-4-20250514, claude-opus-4-20250514)${NC}"
    fi
    read -rp "  Model [$DEFAULT_MODEL]: " LLM_MODEL < /dev/tty
    LLM_MODEL="${LLM_MODEL:-$DEFAULT_MODEL}"
    ok "Model: $LLM_MODEL"
    echo ""

    # API Key
    echo -e "  ${WHITE}${BOLD}API Key${NC} ${DIM}(hidden input)${NC}"
    if [[ "$LLM_PROVIDER" == "openai" ]]; then
        echo -e "  ${DIM}Get yours at: https://platform.openai.com/api-keys${NC}"
    else
        echo -e "  ${DIM}Get yours at: https://console.anthropic.com/settings/keys${NC}"
    fi
    while true; do
        read -rsp "  🔑 Key: " LLM_API_KEY < /dev/tty
        echo ""
        [[ -n "$LLM_API_KEY" ]] && break
        warn "API key cannot be empty"
    done
    ok "API Key saved (${#LLM_API_KEY} chars)"

    # Email (optional)
    echo ""
    echo -e "  ${DIM}─────────────────────────────────────────${NC}"
    echo -e "  ${YELLOW}${BOLD}📧 Email Reports ${DIM}(optional)${NC}"
    echo -e "  ${DIM}Get vulnerability reports delivered to your inbox via Resend${NC}"
    echo ""
    read -rp "  Enable email reports? (y/N): " ENABLE_EMAIL < /dev/tty
    RESEND_API_KEY=""
    SENDER_EMAIL=""
    RECIPIENT_EMAIL=""

    if [[ "$ENABLE_EMAIL" =~ ^[Yy] ]]; then
        echo ""
        read -rsp "  Resend API Key: " RESEND_API_KEY < /dev/tty
        echo ""
        read -rp "  Sender email (verified on Resend): " SENDER_EMAIL < /dev/tty
        read -rp "  Recipient email: " RECIPIENT_EMAIL < /dev/tty
        ok "Email configured: $SENDER_EMAIL → $RECIPIENT_EMAIL"
    else
        info "No email — that's cool, you can add it later with --setup"
    fi

    # Schedule
    echo ""
    echo -e "  ${DIM}─────────────────────────────────────────${NC}"
    echo -e "  ${BLUE}${BOLD}🕐 Scheduling${NC}"
    echo -e "  ${DIM}Run automatically every Monday at 8:00 AM${NC}"
    echo ""
    read -rp "  Schedule weekly scan via cron? (y/N): " ENABLE_CRON < /dev/tty
    echo ""
}

save_config() {
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR/secrets"
    chmod 700 "$INSTALL_DIR/secrets"
    
    cat > "$INSTALL_DIR/config" << EOF
# Container Sentinel Configuration
# Generated on $(date -u +"%Y-%m-%dT%H:%M:%SZ")

LLM_PROVIDER="${LLM_PROVIDER}"
LLM_MODEL="${LLM_MODEL}"
LLM_API_KEY="${LLM_API_KEY}"

# Email settings (optional)
RESEND_API_KEY="${RESEND_API_KEY}"
SENDER_EMAIL="${SENDER_EMAIL}"
RECIPIENT_EMAIL="${RECIPIENT_EMAIL}"

# Tracking
LAST_SCAN=""
INSTALL_DATE="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
EOF
    chmod 600 "$INSTALL_DIR/config"
    ok "Configuration saved to $INSTALL_DIR/config"
}

download_files() {
    info "Downloading Container Sentinel..."

    local total=3
    local current=0

    for file in Dockerfile analyze.sh sentinel.sh; do
        current=$((current + 1))
        progress_bar "$current" "$total" "$file"
        curl -sSL "${BASE_URL}/${file}" -o "$INSTALL_DIR/${file}"
        sleep 0.3
    done
    echo ""

    chmod +x "$INSTALL_DIR/sentinel.sh"
    chmod +x "$INSTALL_DIR/analyze.sh"

    ok "Files downloaded"
}

build_image() {
    info "Building Container Sentinel image..."
    echo -e "  ${DIM}(this may take a minute on first run)${NC}"
    echo ""
    
    docker build -t container-sentinel:latest "$INSTALL_DIR" -f "$INSTALL_DIR/Dockerfile" --quiet &
    local build_pid=$!
    
    local frames=('⣾' '⣽' '⣻' '⢿' '⡿' '⣟' '⣯' '⣷')
    local colors=("${RAINBOW[@]}")
    local i=0
    while kill -0 "$build_pid" 2>/dev/null; do
        local c_idx=$(( i % ${#colors[@]} ))
        echo -ne "\r  ${colors[$c_idx]}${frames[$(( i % ${#frames[@]} ))]}${NC} ${DIM}Building image...${NC}  "
        i=$((i + 1))
        sleep 0.1
    done
    
    wait "$build_pid" && echo -ne "\r" && ok "Docker image built: container-sentinel:latest        " || err "Docker build failed"
    echo ""
}

install_binary() {
    info "Installing 'container-sentinel' command..."

    # Try /usr/local/bin first, fall back to ~/.local/bin
    if [[ -w "/usr/local/bin" ]] || sudo -n true 2>/dev/null; then
        if [[ -w "/usr/local/bin" ]]; then
            ln -sf "$INSTALL_DIR/sentinel.sh" "$BIN_PATH"
        else
            sudo ln -sf "$INSTALL_DIR/sentinel.sh" "$BIN_PATH"
        fi
        ok "Installed to $BIN_PATH"
    else
        LOCAL_BIN="$HOME/.local/bin"
        mkdir -p "$LOCAL_BIN"
        ln -sf "$INSTALL_DIR/sentinel.sh" "$LOCAL_BIN/container-sentinel"
        BIN_PATH="$LOCAL_BIN/container-sentinel"
        warn "Installed to $BIN_PATH (make sure $LOCAL_BIN is in your PATH)"
    fi
}

setup_cron() {
    if [[ "$ENABLE_CRON" =~ ^[Yy] ]]; then
        # Weekly scan: Monday at 8:00 AM
        CRON_CMD="0 8 * * 1 $BIN_PATH --cron 2>&1 | logger -t container-sentinel"
        (crontab -l 2>/dev/null | grep -v "container-sentinel"; echo "$CRON_CMD") | crontab -
        ok "Cron job set: weekly scan every Monday at 8:00 AM"
    fi
}

finish_banner() {
    echo ""
    echo ""
    
    # Success animation
    local success_art=(
        "  ███████╗██╗   ██╗ ██████╗ ██████╗███████╗███████╗███████╗██╗"
        "  ██╔════╝██║   ██║██╔════╝██╔════╝██╔════╝██╔════╝██╔════╝██║"
        "  ███████╗██║   ██║██║     ██║     █████╗  ███████╗███████╗██║"
        "  ╚════██║██║   ██║██║     ██║     ██╔══╝  ╚════██║╚════██║╚═╝"
        "  ███████║╚██████╔╝╚██████╗╚██████╗███████╗███████║███████║██╗"
        "  ╚══════╝ ╚═════╝  ╚═════╝ ╚═════╝╚══════╝╚══════╝╚══════╝╚═╝"
    )
    
    for i in "${!success_art[@]}"; do
        local c_idx=$(( (i * 2) % ${#RAINBOW[@]} ))
        echo -e "${RAINBOW[$c_idx]}${success_art[$i]}${NC}"
        sleep 0.05
    done
    
    echo ""
    echo -e "  ${DIM}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${GREEN}${BOLD}Container Sentinel is ready to protect your containers!${NC}"
    echo ""
    echo -e "  ${WHITE}  Run your first scan    ${CYAN}→${NC}  container-sentinel"
    echo -e "  ${WHITE}  Reconfigure            ${CYAN}→${NC}  container-sentinel --setup"
    echo -e "  ${WHITE}  Show help              ${CYAN}→${NC}  container-sentinel --help"
    echo -e "  ${WHITE}  Uninstall              ${CYAN}→${NC}  container-sentinel --uninstall"
    echo ""
    echo -e "  ${DIM}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${DIM}Made with ☕ and paranoia by${NC}"
    echo ""
    echo -e "  ${YELLOW}  ███╗   ███╗ ██████╗      ██╗ █████╗ ██╗      █████╗ ██████╗ ${NC}"
    echo -e "  ${YELLOW}  ████╗ ████║██╔═══██╗     ██║██╔══██╗██║     ██╔══██╗██╔══██╗${NC}"
    echo -e "  ${YELLOW}  ██╔████╔██║██║   ██║     ██║███████║██║     ███████║██████╔╝${NC}"
    echo -e "  ${YELLOW}  ██║╚██╔╝██║██║   ██║██   ██║██╔══██║██║     ██╔══██║██╔══██╗${NC}"
    echo -e "  ${YELLOW}  ██║ ╚═╝ ██║╚██████╔╝╚█████╔╝██║  ██║███████╗██║  ██║██████╔╝${NC}"
    echo -e "  ${YELLOW}  ╚═╝     ╚═╝ ╚═════╝  ╚════╝ ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═════╝ ${NC}"
    echo ""
    echo -e "  ${DIM}                    ${CYAN}https://mojalab.com${NC}"
    echo ""
}

main() {
    banner
    check_docker
    prompt_config
    save_config
    download_files
    build_image
    install_binary
    setup_cron
    finish_banner
}

# Ensure entire script is parsed before execution.
# This is critical for `curl | bash` — without this, bash may
# try to execute lines before the full script has been downloaded.
main "$@"; exit $?

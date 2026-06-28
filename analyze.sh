#!/usr/bin/env bash
set -euo pipefail

# Container Sentinel - Analysis Engine
# Runs inside the container: scans, summarizes, emails
#
# IMPORTANT: All UI output goes to stderr (&2).
# Only final data (report content) goes to stdout for piping.

# Colors (yes, even inside the container we're fancy)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

RAINBOW=('\033[38;5;196m' '\033[38;5;208m' '\033[38;5;220m' '\033[38;5;46m' '\033[38;5;51m' '\033[38;5;33m' '\033[38;5;129m' '\033[38;5;165m')

# UI helpers — all go to stderr
info()  { echo -e "  ${CYAN}▸${NC} $1" >&2; }
ok()    { echo -e "  ${GREEN}✔${NC} $1" >&2; }
warn()  { echo -e "  ${YELLOW}⚠${NC} $1" >&2; }
err()   { echo -e "  ${RED}✘${NC} $1" >&2; exit 1; }
ui()    { echo -e "$1" >&2; }

SCAN_DIR="/tmp/sentinel-scans"
REPORT_DIR="/sentinel/reports"
MAX_REPORTS=30
SELF_CONTAINER_ID=""

mkdir -p "$SCAN_DIR"

# ─────────────────────────────────────────────────────────────
# Detect our own container ID to exclude from scanning
# ─────────────────────────────────────────────────────────────
detect_self() {
    # Try cgroup method (works on most Docker setups)
    if [[ -f /proc/self/cgroup ]]; then
        SELF_CONTAINER_ID=$(grep -oP '[a-f0-9]{64}' /proc/self/cgroup 2>/dev/null | head -1 || true)
    fi
    # Try hostname (Docker sets it to short container ID by default)
    if [[ -z "$SELF_CONTAINER_ID" ]]; then
        SELF_CONTAINER_ID=$(hostname 2>/dev/null || true)
    fi
}

# ─────────────────────────────────────────────────────────────
# Step 0: Validate API key with a lightweight call
# ─────────────────────────────────────────────────────────────
validate_api_key() {
    ui "  ${CYAN}${BOLD}┌──────────────────────────────────────┐${NC}"
    ui "  ${CYAN}${BOLD}│   🔑 Validating API Credentials      │${NC}"
    ui "  ${CYAN}${BOLD}└──────────────────────────────────────┘${NC}"
    ui ""

    # Read API key from mounted secret file if available, else from env
    if [[ -f /run/secrets/llm_api_key ]]; then
        LLM_API_KEY=$(cat /run/secrets/llm_api_key)
    fi

    if [[ -z "${LLM_API_KEY:-}" ]]; then
        err "No API key provided. Check your configuration."
    fi

    local valid=false

    if [[ "$LLM_PROVIDER" == "openai" ]]; then
        local resp
        resp=$(curl -sS -o /dev/null -w "%{http_code}" \
            --max-time 10 \
            https://api.openai.com/v1/models \
            -H "Authorization: Bearer ${LLM_API_KEY}" 2>/dev/null || echo "000")
        [[ "$resp" == "200" ]] && valid=true
    elif [[ "$LLM_PROVIDER" == "anthropic" ]]; then
        local resp
        resp=$(curl -sS -o /dev/null -w "%{http_code}" \
            --max-time 10 \
            https://api.anthropic.com/v1/messages \
            -H "x-api-key: ${LLM_API_KEY}" \
            -H "anthropic-version: 2023-06-01" \
            -H "Content-Type: application/json" \
            -d '{"model":"claude-sonnet-4-20250514","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}' 2>/dev/null || echo "000")
        # 200 = valid, 400 = valid key but bad request (still means key works)
        [[ "$resp" == "200" || "$resp" == "400" ]] && valid=true
    fi

    if [[ "$valid" == "true" ]]; then
        ok "API key is valid (${LLM_PROVIDER})"
    else
        err "API key validation failed. Check your ${LLM_PROVIDER} key and try again."
    fi
    ui ""
}

# ─────────────────────────────────────────────────────────────
# Step 1: Discover running containers
# ─────────────────────────────────────────────────────────────
discover_containers() {
    ui "  ${CYAN}${BOLD}┌──────────────────────────────────────┐${NC}"
    ui "  ${CYAN}${BOLD}│   📦 Discovering Running Containers  │${NC}"
    ui "  ${CYAN}${BOLD}└──────────────────────────────────────┘${NC}"
    ui ""

    local all_containers
    all_containers=$(docker ps --format '{{.ID}}|{{.Image}}|{{.Names}}' 2>/dev/null || true)

    if [[ -z "$all_containers" ]]; then
        warn "No running containers found."
        ui "  ${DIM}Nothing to scan. Start some containers and try again.${NC}"
        exit 0
    fi

    # Filter out ourselves
    local containers=""
    while IFS='|' read -r id image name; do
        # Skip if this is our own container
        if [[ -n "$SELF_CONTAINER_ID" ]]; then
            if [[ "$id" == "${SELF_CONTAINER_ID:0:12}" ]] || [[ "$name" == "container-sentinel"* ]]; then
                ui "    ${DIM}├─ ${name} (self — skipped)${NC}"
                continue
            fi
        fi
        if [[ -n "$containers" ]]; then
            containers+=$'\n'
        fi
        containers+="${id}|${image}|${name}"
    done <<< "$all_containers"

    if [[ -z "$containers" ]]; then
        warn "No containers to scan (only found ourselves)."
        exit 0
    fi

    local count
    count=$(echo "$containers" | wc -l | tr -d ' ')
    ok "Found ${WHITE}${BOLD}${count}${NC} running container(s)"
    ui ""

    echo "$containers" | while IFS='|' read -r id image name; do
        ui "    ${DIM}├─${NC} ${GREEN}${name}${NC} ${DIM}(${image})${NC}"
    done
    ui ""

    # Return data on stdout
    echo "$containers"
}

# ─────────────────────────────────────────────────────────────
# Step 2: Scan each container with Trivy
# ─────────────────────────────────────────────────────────────
scan_containers() {
    local containers="$1"

    ui "  ${MAGENTA}${BOLD}┌──────────────────────────────────────┐${NC}"
    ui "  ${MAGENTA}${BOLD}│   🔍 Scanning for Vulnerabilities    │${NC}"
    ui "  ${MAGENTA}${BOLD}└──────────────────────────────────────┘${NC}"
    ui ""

    local total
    total=$(echo "$containers" | wc -l | tr -d ' ')
    local current=0
    local all_results=""
    local scanned_ok=0
    local scan_failed=0

    while IFS='|' read -r id image name; do
        current=$((current + 1))
        local c_idx=$(( (current - 1) % ${#RAINBOW[@]} ))
        ui "  ${RAINBOW[$c_idx]}[$current/$total]${NC} Scanning ${WHITE}${BOLD}${name}${NC} ${DIM}(${image})${NC}..."

        local scan_file="$SCAN_DIR/${name}.json"

        # Run trivy scan on the container image (memory-optimized flags)
        # Try local image first (for locally-built images), fall back to remote
        local trivy_stderr="/tmp/trivy_err_${name}.log"
        if trivy image --format json --severity HIGH,CRITICAL --quiet \
            --scanners vuln \
            --image-src docker \
            "$image" > "$scan_file" 2>"$trivy_stderr"; then
            local vuln_count
            vuln_count=$(jq '[.Results[]?.Vulnerabilities[]? // empty] | length' "$scan_file" 2>/dev/null || echo "0")

            if [[ "$vuln_count" -gt 0 ]]; then
                ui "    ${RED}⚠  Found ${BOLD}${vuln_count}${NC}${RED} HIGH/CRITICAL vulnerabilities${NC}"
            else
                ui "    ${GREEN}✔  Clean — no HIGH/CRITICAL vulnerabilities${NC}"
            fi
            scanned_ok=$((scanned_ok + 1))
            all_results+="--- Container: ${name} (Image: ${image}) [SCANNED OK] ---"$'\n'
            all_results+=$(cat "$scan_file")
            all_results+=$'\n\n'
        else
            local trivy_error
            trivy_error=$(cat "$trivy_stderr" 2>/dev/null | tail -3 || true)
            ui "    ${YELLOW}⚠  Could not scan image${NC}"
            if [[ -n "${VERBOSE:-}" && -n "$trivy_error" ]]; then
                ui "    ${DIM}${trivy_error}${NC}"
            elif [[ -n "$trivy_error" ]]; then
                ui "    ${DIM}(run with --verbose to see details)${NC}"
            fi
            scan_failed=$((scan_failed + 1))
            all_results+="--- Container: ${name} (Image: ${image}) [SCAN FAILED - could not analyze this image] ---"$'\n'
            all_results+='{"Results":[], "_error": "Trivy could not scan this image. Results are NOT available — do not assume it is clean."}'$'\n\n'
        fi

    done <<< "$containers"

    # Add scan summary for LLM context
    all_results+="--- SCAN SUMMARY ---"$'\n'
    all_results+="Successfully scanned: ${scanned_ok}/${total} containers"$'\n'
    all_results+="Failed to scan: ${scan_failed}/${total} containers"$'\n'
    if [[ "$scan_failed" -gt 0 ]]; then
        all_results+="IMPORTANT: Failed scans mean NO vulnerability data is available for those containers. They are NOT confirmed clean — they simply could not be analyzed."$'\n'
    fi
    all_results+=$'\n'

    ui ""
    if [[ "$scan_failed" -gt 0 ]]; then
        ui "  ${YELLOW}⚠  ${scan_failed}/${total} images could not be scanned${NC}"
        ui ""
    fi

    # Return data on stdout
    echo "$all_results"
}

# ─────────────────────────────────────────────────────────────
# Step 3: Call LLM for analysis (with retry + backoff)
# ─────────────────────────────────────────────────────────────
call_llm() {
    local scan_results="$1"

    ui "  ${YELLOW}${BOLD}┌──────────────────────────────────────┐${NC}"
    ui "  ${YELLOW}${BOLD}│   🧠 AI Analysis in Progress...      │${NC}"
    ui "  ${YELLOW}${BOLD}└──────────────────────────────────────┘${NC}"
    ui ""

    # Prepare the prompt
    local system_prompt
    system_prompt="You are a security analyst assistant. Analyze the following Trivy vulnerability scan results from Docker containers running on a server. Provide:

1. **Executive Summary** - Quick overview of the security posture
2. **Critical Findings** - List the most severe vulnerabilities, grouped by container
3. **Remediation Steps** - Specific, actionable steps to fix each issue (e.g., upgrade package X to version Y)
4. **Risk Assessment** - Overall risk level and what could happen if not addressed

Server Information:
- Hostname: ${HOST_NAME:-unknown}
- Public IP: ${HOST_IP:-unknown}
- OS/Kernel: ${HOST_OS:-unknown}
- Uptime: ${HOST_UPTIME:-unknown}
- Docker Version: ${HOST_DOCKER_VERSION:-unknown}
- Running Containers: ${HOST_CONTAINER_COUNT:-unknown}
- Compose file(s): ${HOST_COMPOSE_PATHS:-none found}
- Scan Date: $(date -u +"%Y-%m-%d %H:%M UTC")

Keep the output concise but actionable. Use markdown formatting. If there are no vulnerabilities, congratulate the user but remind them to keep scanning regularly."

    # Truncate scan results if too large (keep under ~100k chars for API limits)
    local max_chars=90000
    if [[ ${#scan_results} -gt $max_chars ]]; then
        scan_results="${scan_results:0:$max_chars}... [TRUNCATED - too many results to fit in one analysis]"
    fi

    local response=""
    local max_retries=3
    local retry_delay=5

    for (( attempt=1; attempt<=max_retries; attempt++ )); do
        if [[ "$LLM_PROVIDER" == "openai" ]]; then
            response=$(call_openai "$system_prompt" "$scan_results" 2>/dev/null) && break
        elif [[ "$LLM_PROVIDER" == "anthropic" ]]; then
            response=$(call_anthropic "$system_prompt" "$scan_results" 2>/dev/null) && break
        else
            err "Unknown LLM provider: $LLM_PROVIDER"
        fi

        if [[ $attempt -lt $max_retries ]]; then
            warn "LLM call failed (attempt $attempt/$max_retries). Retrying in ${retry_delay}s..."
            sleep "$retry_delay"
            retry_delay=$(( retry_delay * 2 ))
        else
            err "LLM call failed after $max_retries attempts. Check your API key and network."
        fi
    done

    if [[ -z "$response" ]]; then
        err "LLM returned empty response after $max_retries attempts."
    fi

    ok "Analysis complete (${LLM_PROVIDER}/${LLM_MODEL})"
    ui ""

    # Return data on stdout
    echo "$response"
}

call_openai() {
    local system_prompt="$1"
    local user_content="$2"

    local payload
    payload=$(jq -n \
        --arg model "$LLM_MODEL" \
        --arg sys "$system_prompt" \
        --arg user "$user_content" \
        '{
            model: $model,
            messages: [
                {role: "system", content: $sys},
                {role: "user", content: ("Here are the Trivy scan results:\n\n" + $user)}
            ],
            temperature: 0.3,
            max_tokens: 4096
        }')

    local result
    local http_code
    local tmp_file="/tmp/openai_response.json"

    http_code=$(curl -sS -w "%{http_code}" -o "$tmp_file" \
        --max-time 120 \
        https://api.openai.com/v1/chat/completions \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${LLM_API_KEY}" \
        -d "$payload" 2>/dev/null || echo "000")

    result=$(cat "$tmp_file" 2>/dev/null || echo "{}")
    rm -f "$tmp_file"

    # Handle rate limits and server errors
    if [[ "$http_code" == "429" || "$http_code" == "500" || "$http_code" == "502" || "$http_code" == "503" ]]; then
        return 1
    fi

    # Extract content
    local content
    content=$(echo "$result" | jq -r '.choices[0].message.content // empty' 2>/dev/null)

    if [[ -z "$content" ]]; then
        local error_msg
        error_msg=$(echo "$result" | jq -r '.error.message // "Unknown error"' 2>/dev/null)
        warn "OpenAI API error: $error_msg" 
        return 1
    fi

    echo "$content"
}

call_anthropic() {
    local system_prompt="$1"
    local user_content="$2"

    local payload
    payload=$(jq -n \
        --arg model "$LLM_MODEL" \
        --arg sys "$system_prompt" \
        --arg user "$user_content" \
        '{
            model: $model,
            system: $sys,
            messages: [
                {role: "user", content: ("Here are the Trivy scan results:\n\n" + $user)}
            ],
            temperature: 0.3,
            max_tokens: 4096
        }')

    local result
    local http_code
    local tmp_file="/tmp/anthropic_response.json"

    http_code=$(curl -sS -w "%{http_code}" -o "$tmp_file" \
        --max-time 120 \
        https://api.anthropic.com/v1/messages \
        -H "Content-Type: application/json" \
        -H "x-api-key: ${LLM_API_KEY}" \
        -H "anthropic-version: 2023-06-01" \
        -d "$payload" 2>/dev/null || echo "000")

    result=$(cat "$tmp_file" 2>/dev/null || echo "{}")
    rm -f "$tmp_file"

    # Handle rate limits and server errors
    if [[ "$http_code" == "429" || "$http_code" == "500" || "$http_code" == "502" || "$http_code" == "503" ]]; then
        return 1
    fi

    # Extract content
    local content
    content=$(echo "$result" | jq -r '.content[0].text // empty' 2>/dev/null)

    if [[ -z "$content" ]]; then
        local error_msg
        error_msg=$(echo "$result" | jq -r '.error.message // "Unknown error"' 2>/dev/null)
        warn "Anthropic API error: $error_msg"
        return 1
    fi

    echo "$content"
}

# ─────────────────────────────────────────────────────────────
# Step 4: Send email via Resend (optional)
# ─────────────────────────────────────────────────────────────
send_email() {
    local report="$1"

    if [[ -z "${RESEND_API_KEY:-}" || -z "${SENDER_EMAIL:-}" || -z "${RECIPIENT_EMAIL:-}" ]]; then
        return 0
    fi

    # Read Resend key from secret file if available
    if [[ -f /run/secrets/resend_api_key ]]; then
        RESEND_API_KEY=$(cat /run/secrets/resend_api_key)
    fi

    ui "  ${MAGENTA}${BOLD}┌──────────────────────────────────────┐${NC}"
    ui "  ${MAGENTA}${BOLD}│   📧 Sending Email Report...         │${NC}"
    ui "  ${MAGENTA}${BOLD}└──────────────────────────────────────┘${NC}"
    ui ""

    local subject
    subject="🛡️ Container Sentinel Report — ${HOST_NAME:-unknown} — $(date -u +"%Y-%m-%d")"

    # Ensure from field is properly formatted for Resend
    local from_field="$SENDER_EMAIL"
    # If it doesn't contain < > and is just an email, wrap it with a display name
    if [[ "$from_field" != *"<"* ]]; then
        from_field="Container Sentinel <${SENDER_EMAIL}>"
    fi

    # Convert markdown to HTML (using jq for proper escaping)
    local html_body
    html_body=$(jq -n --arg report "$report" --arg host "${HOST_NAME:-unknown}" --arg os "${HOST_OS:-unknown}" --arg ip "${HOST_IP:-unknown}" '
    "<html><body style=\"font-family: -apple-system, sans-serif; padding: 20px; background: #1a1a2e; color: #e0e0e0;\">
    <div style=\"max-width: 800px; margin: 0 auto;\">
    <div style=\"text-align: center; padding: 20px; border-bottom: 2px solid #333;\">
    <h1 style=\"color: #00d4ff;\">🛡️ Container Sentinel</h1>
    <p style=\"color: #888;\">Automated Vulnerability Report</p>
    <p style=\"color: #666; font-size: 12px;\">Host: \($host) | IP: \($ip) | OS: \($os)</p>
    </div>
    <div style=\"padding: 20px; white-space: pre-wrap;\">\($report)</div>
    <div style=\"text-align: center; padding: 20px; border-top: 2px solid #333; color: #666;\">
    <p>Generated by Container Sentinel — <a href=\"https://mojalab.com\" style=\"color: #ffaa00;\">mojalab.com</a></p>
    </div>
    </div>
    </body></html>"' | jq -r '.')

    local payload
    payload=$(jq -n \
        --arg from "$from_field" \
        --arg to "$RECIPIENT_EMAIL" \
        --arg subject "$subject" \
        --arg html "$html_body" \
        '{
            from: $from,
            to: [$to],
            subject: $subject,
            html: $html
        }')

    local result
    result=$(curl -sS --max-time 30 https://api.resend.com/emails \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${RESEND_API_KEY}" \
        -d "$payload" 2>/dev/null || echo '{"message":"Network error"}')

    local email_id
    email_id=$(echo "$result" | jq -r '.id // empty' 2>/dev/null)

    if [[ -n "$email_id" ]]; then
        ok "Email sent to ${RECIPIENT_EMAIL} (id: ${email_id})"
    else
        local error_msg
        error_msg=$(echo "$result" | jq -r '.message // "Unknown error"' 2>/dev/null)
        warn "Email failed: $error_msg"
    fi
    ui ""
}

# ─────────────────────────────────────────────────────────────
# Step 5: Save report to file (always — email or not)
# ─────────────────────────────────────────────────────────────
save_report() {
    local report="$1"

    mkdir -p "$REPORT_DIR"

    local timestamp
    timestamp=$(date -u +"%Y-%m-%d_%H%M%S")
    local report_file="${REPORT_DIR}/sentinel-report_${timestamp}.md"

    # Build the full report with header
    {
        echo "# 🛡️ Container Sentinel Report"
        echo ""
        echo "| Field | Value |"
        echo "|-------|-------|"
        echo "| Date | $(date -u +"%Y-%m-%d %H:%M UTC") |"
        echo "| Host | ${HOST_NAME:-unknown} |"
        echo "| IP | ${HOST_IP:-unknown} |"
        echo "| OS | ${HOST_OS:-unknown} |"
        echo "| Uptime | ${HOST_UPTIME:-unknown} |"
        echo "| Docker | ${HOST_DOCKER_VERSION:-unknown} |"
        echo "| Containers | ${HOST_CONTAINER_COUNT:-unknown} running |"
        echo "| Compose | ${HOST_COMPOSE_PATHS:-none found} |"
        echo "| Analyzer | ${LLM_PROVIDER} (${LLM_MODEL}) |"
        echo ""
        echo "---"
        echo ""
        echo "$report"
        echo ""
        echo "---"
        echo ""
        echo "*Generated by [Container Sentinel](https://github.com/doradame/container-sentinel) — mojalab.com*"
    } > "$report_file"

    # Rotate old reports (keep MAX_REPORTS most recent)
    local report_count
    report_count=$(find "$REPORT_DIR" -name "sentinel-report_*.md" -type f 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$report_count" -gt "$MAX_REPORTS" ]]; then
        local to_delete=$(( report_count - MAX_REPORTS ))
        find "$REPORT_DIR" -name "sentinel-report_*.md" -type f -print0 2>/dev/null | \
            xargs -0 ls -t | tail -n "$to_delete" | xargs rm -f 2>/dev/null || true
        info "Rotated old reports (keeping last $MAX_REPORTS)"
    fi

    ok "Report saved: ${report_file}"
    ui ""
}

# ─────────────────────────────────────────────────────────────
# Step 6: Display report
# ─────────────────────────────────────────────────────────────
display_report() {
    local report="$1"

    ui ""
    ui "  ${GREEN}${BOLD}┌──────────────────────────────────────────────────────────────┐${NC}"
    ui "  ${GREEN}${BOLD}│   📋 Vulnerability Analysis Report                           │${NC}"
    ui "  ${GREEN}${BOLD}└──────────────────────────────────────────────────────────────┘${NC}"
    ui ""
    ui "${DIM}────────────────────────────────────────────────────────────────────${NC}"
    ui ""
    # Report content goes to stderr for display AND is already saved to file
    echo "$report" >&2
    ui ""
    ui "${DIM}────────────────────────────────────────────────────────────────────${NC}"
}

# ─────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────
main() {
    # Detect ourselves to avoid scanning our own container
    detect_self

    # Validate credentials before doing expensive scans
    validate_api_key

    # Discover
    local containers
    containers=$(discover_containers)

    # Scan
    local scan_results
    scan_results=$(scan_containers "$containers")

    # Analyze with LLM (retry-enabled)
    local report
    report=$(call_llm "$scan_results")

    # Save report (always, with rotation)
    save_report "$report"

    # Display
    display_report "$report"

    # Email (if configured)
    send_email "$report"
}

main "$@"

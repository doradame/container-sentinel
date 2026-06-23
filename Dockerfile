# Container Sentinel - Vulnerability Scanner + AI Analysis
# Zero-footprint: runs, reports, disappears.

# Pin trivy to a specific version for reproducibility
FROM aquasec/trivy:0.62.1 AS trivy

FROM alpine:3.20

# Install runtime dependencies
RUN apk add --no-cache \
    bash \
    curl \
    jq \
    docker-cli \
    coreutils \
    ca-certificates \
    && rm -rf /var/cache/apk/*

# Copy trivy binary from official image (pinned version)
COPY --from=trivy /usr/local/bin/trivy /usr/local/bin/trivy

# Create workspace and reports directory
WORKDIR /sentinel
RUN mkdir -p /sentinel/reports

# Copy analysis script
COPY analyze.sh /sentinel/analyze.sh
RUN chmod +x /sentinel/analyze.sh

# Healthcheck: verify trivy is functional
RUN trivy --version

ENTRYPOINT ["/sentinel/analyze.sh"]

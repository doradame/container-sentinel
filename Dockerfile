# Container Sentinel - Vulnerability Scanner + AI Analysis
# Zero-footprint: runs, reports, disappears.

# Pin trivy to a specific version AND digest for supply chain security
FROM aquasec/trivy:0.62.1@sha256:fc10faf341a1d8fa8256c5ff1a6662ef74dd38b65034c8ce42346cf958a02d5d AS trivy

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

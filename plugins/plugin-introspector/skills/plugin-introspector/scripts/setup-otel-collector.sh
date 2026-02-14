#!/usr/bin/env bash
# Plugin Introspector — OTel Collector Setup
# Downloads, configures, and starts OTel Collector Contrib for Tier 1 collection.
#
# Usage:
#   setup-otel-collector.sh install   # Download otelcol-contrib
#   setup-otel-collector.sh start     # Start collector as background process
#   setup-otel-collector.sh stop      # Stop collector
#   setup-otel-collector.sh status    # Check if collector is running
#   setup-otel-collector.sh env       # Print env vars to set in shell profile
#
# After setup, add to your shell profile (~/.bashrc or ~/.zshrc):
#   export CLAUDE_CODE_ENABLE_TELEMETRY=1
#   export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"
COLLECTOR_DIR="${INTROSPECTOR_BASE}/otel-collector"
PID_FILE="${INTROSPECTOR_BASE}/otel-collector.pid"
EXPORT_DIR="${INTROSPECTOR_BASE}/otel-export"
CONFIG_FILE="${SCRIPT_DIR}/otel-config.yaml"
OTELCOL_VERSION="0.96.0"

detect_arch() {
  local arch
  arch=$(uname -m)
  case "$arch" in
    x86_64|amd64)  echo "amd64" ;;
    aarch64|arm64)  echo "arm64" ;;
    *)              echo "unsupported: $arch" >&2; return 1 ;;
  esac
}

detect_os() {
  local os
  os=$(uname -s | tr '[:upper:]' '[:lower:]')
  case "$os" in
    linux|darwin) echo "$os" ;;
    *)            echo "unsupported: $os" >&2; return 1 ;;
  esac
}

cmd_install() {
  local os arch
  os=$(detect_os)
  arch=$(detect_arch)

  mkdir -p "$COLLECTOR_DIR"

  local binary="${COLLECTOR_DIR}/otelcol-contrib"
  if [ -f "$binary" ]; then
    echo "OTel Collector already installed at: $binary"
    "$binary" --version 2>/dev/null || true
    return 0
  fi

  local url="https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v${OTELCOL_VERSION}/otelcol-contrib_${OTELCOL_VERSION}_${os}_${arch}.tar.gz"

  echo "Downloading OTel Collector Contrib v${OTELCOL_VERSION}..."
  echo "URL: $url"
  echo "Note: Binary is ~100MB+, this may take a moment."
  echo ""

  local tmp_file
  tmp_file=$(mktemp "${TMPDIR:-/tmp}/otelcol-contrib.XXXXXX.tar.gz")
  trap "rm -f '$tmp_file' '${TMPDIR:-/tmp}/otelcol-checksums.'*" EXIT

  if command -v curl &>/dev/null; then
    curl -L --progress-bar -o "$tmp_file" "$url"
  elif command -v wget &>/dev/null; then
    wget -O "$tmp_file" "$url"
  else
    echo "Error: curl or wget required for download" >&2
    return 1
  fi

  # Verify download integrity via SHA256 checksum
  local checksums_url="https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v${OTELCOL_VERSION}/otelcol-contrib_${OTELCOL_VERSION}_checksums.txt"
  local expected_name="otelcol-contrib_${OTELCOL_VERSION}_${os}_${arch}.tar.gz"
  if command -v sha256sum &>/dev/null; then
    local checksums_file
    checksums_file=$(mktemp "${TMPDIR:-/tmp}/otelcol-checksums.XXXXXX")
    if curl -fsSL -o "$checksums_file" "$checksums_url" 2>/dev/null || wget -qO "$checksums_file" "$checksums_url" 2>/dev/null; then
      local expected_hash
      expected_hash=$(grep "$expected_name" "$checksums_file" | awk '{print $1}')
      if [ -n "$expected_hash" ]; then
        local actual_hash
        actual_hash=$(sha256sum "$tmp_file" | awk '{print $1}')
        if [ "$actual_hash" != "$expected_hash" ]; then
          echo "Error: SHA256 checksum mismatch!" >&2
          echo "  Expected: $expected_hash" >&2
          echo "  Actual:   $actual_hash" >&2
          rm -f "$checksums_file" "$tmp_file"
          return 1
        fi
        echo "SHA256 checksum verified."
      else
        echo "Warning: Could not find checksum for $expected_name, skipping verification." >&2
      fi
    else
      echo "Warning: Could not download checksums file, skipping verification." >&2
    fi
    rm -f "$checksums_file"
  else
    echo "Warning: sha256sum not available, skipping checksum verification." >&2
  fi

  echo "Extracting..."
  tar -xzf "$tmp_file" -C "$COLLECTOR_DIR" otelcol-contrib 2>/dev/null \
    || tar -xzf "$tmp_file" -C "$COLLECTOR_DIR" 2>/dev/null
  rm -f "$tmp_file"

  chmod +x "$binary"
  echo "Installed: $binary"
  "$binary" --version 2>/dev/null || true
}

cmd_start() {
  local binary="${COLLECTOR_DIR}/otelcol-contrib"
  if [ ! -f "$binary" ]; then
    echo "OTel Collector not installed. Run: setup-otel-collector.sh install" >&2
    return 1
  fi

  if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null; then
    echo "OTel Collector already running (PID: $(cat "$PID_FILE"))"
    return 0
  fi

  mkdir -p "$EXPORT_DIR"

  echo "Starting OTel Collector..."
  echo "Config: $CONFIG_FILE"
  echo "Export: $EXPORT_DIR"

  # Expand HOME in config path for file exporter.
  # Use awk instead of sed to avoid & and \ in HOME breaking substitution.
  local runtime_config="${COLLECTOR_DIR}/runtime-config.yaml"
  awk -v home="$HOME" '{gsub(/\$\{HOME\}/, home); print}' "$CONFIG_FILE" > "$runtime_config"

  nohup "$binary" --config "$runtime_config" \
    > "${COLLECTOR_DIR}/collector.log" 2>&1 &
  local pid=$!
  echo "$pid" > "$PID_FILE"

  sleep 1
  if kill -0 "$pid" 2>/dev/null; then
    echo "OTel Collector started (PID: $pid)"
    echo ""
    echo "Tier 1 collection is now active."
    echo "Set these environment variables in your shell:"
    echo "  export CLAUDE_CODE_ENABLE_TELEMETRY=1"
    echo "  export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317"
  else
    echo "Failed to start OTel Collector. Check: ${COLLECTOR_DIR}/collector.log" >&2
    rm -f "$PID_FILE"
    return 1
  fi
}

cmd_stop() {
  if [ ! -f "$PID_FILE" ]; then
    echo "OTel Collector is not running (no PID file)"
    return 0
  fi

  local pid
  pid=$(cat "$PID_FILE" 2>/dev/null)
  if kill -0 "$pid" 2>/dev/null; then
    echo "Stopping OTel Collector (PID: $pid)..."
    kill "$pid"
    sleep 2
    if kill -0 "$pid" 2>/dev/null; then
      kill -9 "$pid" 2>/dev/null || true
    fi
    echo "Stopped."
  else
    echo "OTel Collector was not running (stale PID file)"
  fi
  rm -f "$PID_FILE"
}

cmd_status() {
  echo "=== OTel Collector Status ==="
  echo ""

  # Binary
  local binary="${COLLECTOR_DIR}/otelcol-contrib"
  if [ -f "$binary" ]; then
    echo "Binary:    $binary"
    echo "Version:   $("$binary" --version 2>/dev/null || echo 'unknown')"
  else
    echo "Binary:    NOT INSTALLED"
    echo "  Run: setup-otel-collector.sh install"
    echo ""
    return 0
  fi

  # Process
  if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null; then
    echo "Status:    RUNNING (PID: $(cat "$PID_FILE"))"
  else
    echo "Status:    STOPPED"
  fi

  # Export data
  if [ -d "$EXPORT_DIR" ]; then
    local file_count
    file_count=$(ls -1 "$EXPORT_DIR" 2>/dev/null | wc -l)
    local total_size
    total_size=$(du -sh "$EXPORT_DIR" 2>/dev/null | cut -f1)
    echo "Export:    $EXPORT_DIR ($file_count files, ${total_size:-0})"
  else
    echo "Export:    $EXPORT_DIR (not created yet)"
  fi

  # Environment
  echo ""
  echo "=== Environment ==="
  echo "CLAUDE_CODE_ENABLE_TELEMETRY=${CLAUDE_CODE_ENABLE_TELEMETRY:-not set}"
  echo "OTEL_EXPORTER_OTLP_ENDPOINT=${OTEL_EXPORTER_OTLP_ENDPOINT:-not set}"
}

cmd_env() {
  echo "# Add these to your shell profile (~/.bashrc or ~/.zshrc):"
  echo "export CLAUDE_CODE_ENABLE_TELEMETRY=1"
  echo "export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317"
}

# Main dispatch
case "${1:-}" in
  install) cmd_install ;;
  start)   cmd_start ;;
  stop)    cmd_stop ;;
  status)  cmd_status ;;
  env)     cmd_env ;;
  *)
    echo "Usage: setup-otel-collector.sh {install|start|stop|status|env}"
    echo ""
    echo "  install  Download OTel Collector Contrib (~100MB+)"
    echo "  start    Start collector as background process"
    echo "  stop     Stop collector"
    echo "  status   Show collector status and environment"
    echo "  env      Print environment variables to set"
    ;;
esac

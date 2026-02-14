# OTel Collector Setup Guide

> Plugin Introspector v1.0.0 — Tier 1 Observability Stack

## Quick Start

### Option 1: ClickStack/HyperDX (Recommended)

Unified observability stack. Analyze logs, metrics, and traces in a single database with ClickHouse + HyperDX UI.

```bash
# Run all-in-one Docker image
docker run -d --name hyperdx \
  -p 8080:8080 \
  -p 4317:4317 \
  -p 4318:4318 \
  docker.hyperdx.io/hyperdx/hyperdx-all-in-one
```

**Resource Requirements:** 4GB+ RAM, 2+ CPU cores

### Option 2: grafana/otel-lgtm (Lightweight)

Lightweight stack for development/testing. Loki + Grafana + Tempo + Mimir all-in-one.

```bash
docker run -d --name otel-lgtm \
  -p 3000:3000 \
  -p 4317:4317 \
  -p 4318:4318 \
  grafana/otel-lgtm
```

**Resource Requirements:** 1-2GB RAM, 2 CPU cores

---

## Claude Code Configuration

### Required Environment Variables

```bash
# Add to ~/.bashrc or ~/.zshrc
export CLAUDE_CODE_ENABLE_TELEMETRY=1
export OTEL_METRICS_EXPORTER=otlp
export OTEL_LOGS_EXPORTER=otlp
export OTEL_EXPORTER_OTLP_PROTOCOL=grpc
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317

# Required for PI security analysis
export OTEL_LOG_TOOL_DETAILS=1

# Privacy (default: disabled)
export OTEL_LOG_USER_PROMPTS=0
```

### Verify Environment Variables

```bash
source ~/.bashrc  # or ~/.zshrc
echo $CLAUDE_CODE_ENABLE_TELEMETRY  # Should be 1
```

---

## Docker Compose Setup (PI + HyperDX)

Create `docker-compose.otel.yml` in project root:

```yaml
version: "3.9"

services:
  hyperdx:
    image: docker.hyperdx.io/hyperdx/hyperdx-all-in-one
    container_name: pi-hyperdx
    ports:
      - "8080:8080"    # HyperDX UI
      - "4317:4317"    # OTel gRPC
      - "4318:4318"    # OTel HTTP
    volumes:
      - hyperdx-data:/var/lib/clickhouse
    environment:
      - HYPERDX_LOG_LEVEL=info
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3

volumes:
  hyperdx-data:
```

### Start

```bash
docker compose -f docker-compose.otel.yml up -d
```

### Stop

```bash
docker compose -f docker-compose.otel.yml down
```

---

## Verification

### 1. Check Collector Status

```bash
# HyperDX
curl http://localhost:8080/health

# grafana/otel-lgtm
curl http://localhost:3000/api/health
```

### 2. Run Claude Code Session

```bash
claude  # or start Claude Code
```

### 3. Verify Data

**HyperDX UI:** http://localhost:8080
- Search: `service.name:claude-code`
- Check tool calls in Traces tab

**Grafana (otel-lgtm):** http://localhost:3000
- Explore: Tempo: Recent traces
- Loki: `{service_name="claude-code"}`

---

## PI Integration

### Automatic Tier Detection

PI hook scripts automatically detect OTel Collector status:

```bash
# Collector detection in _common.sh (detect_otel_tier)
OTEL_EXPORT_DIR="${INTROSPECTOR_BASE}/otel-export"
if [ -d "$OTEL_EXPORT_DIR" ]; then
  pid_file="${INTROSPECTOR_BASE}/otel-collector.pid"
  if [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
    echo 1; return  # Collector process running
  fi
  if [ -n "$(ls -A "$OTEL_EXPORT_DIR" 2>/dev/null)" ]; then
    echo 1; return  # Export dir has data
  fi
fi
echo 0  # Tier 0 fallback
```

### Native OTel Data Merging

At session end, `merge-otel-data.sh` merges OTel data with PI JSONL:

```bash
# Manual merge (if needed)
./scripts/merge-otel-data.sh [session-id]
```

---

## HyperDX Query Examples

### Search Security Events

```sql
-- Search for CRITICAL/WARNING commands
SELECT *
FROM logs
WHERE service.name = 'claude-code'
  AND tool_name = 'Bash'
  AND body LIKE '%rm -rf%'
ORDER BY timestamp DESC
LIMIT 100
```

### Analyze Token Usage

```sql
-- Token usage by model
SELECT
  attributes['gen_ai.request.model'] as model,
  SUM(attributes['gen_ai.usage.input_tokens']) as input_tokens,
  SUM(attributes['gen_ai.usage.output_tokens']) as output_tokens
FROM logs
WHERE service.name = 'claude-code'
GROUP BY model
```

### Analyze Tool Decisions

```sql
-- Tool decision source distribution
SELECT
  attributes['decision'] as decision,
  attributes['source'] as source,
  COUNT(*) as count
FROM logs
WHERE event_name = 'claude_code.tool_decision'
GROUP BY decision, source
ORDER BY count DESC
```

---

## Grafana Dashboard Import

### Dashboards (for otel-lgtm)

Pre-built Grafana dashboards are not yet included. Create custom dashboards using:

1. **Security:** Query Loki for `security_events.jsonl` patterns (`dlp_violation`, `command_risk`)
2. **Tokens:** Query Loki for `api_traces.jsonl` fields (`input_tokens`, `output_tokens`)

**Import Method:** Grafana: Dashboards: New: Add visualization with Loki/Tempo data source.

---

## Troubleshooting

### OTel Data Not Being Collected

```bash
# 1. Check environment variables
echo $CLAUDE_CODE_ENABLE_TELEMETRY  # Should be 1

# 2. Check Collector connection
curl -v http://localhost:4317

# 3. Restart Claude Code
# Environment variable changes require Claude Code restart
```

### Cannot Access HyperDX UI

```bash
# Check container status
docker ps | grep hyperdx

# Check logs
docker logs pi-hyperdx --tail 50
```

### Out of Memory

```bash
# Check Docker resources
docker stats

# HyperDX minimum requirements: 4GB RAM
# If insufficient, use grafana/otel-lgtm (1-2GB) instead
```

---

## Stack Comparison

| Aspect | PI Tier 0 | grafana/otel-lgtm | ClickStack/HyperDX |
|--------|-----------|-------------------|-------------------|
| **Memory** | 0 | 1-2GB | 4GB+ |
| **UI** | Terminal | Grafana | HyperDX |
| **Query** | jq | PromQL/LogQL | SQL + Lucene |
| **Scalability** | Limited | Medium | High |
| **Use Case** | Individual dev | Local testing | Unified analysis |
| **Complexity** | None | Low | Low |

---

## Next Steps

1. **Create security dashboard:** Custom Grafana/HyperDX dashboard for DLP and command risk events
2. **OTel security mapping:** `scripts/otel-security-mapper.sh`
3. **Configure alerts:** HyperDX Alerts or Grafana Alerting

---

*Document Created: 2026-02-06*
*Version: 1.0.0*

# CI/CD Integration Guide

> Guide for integrating Plugin Introspector with GitHub Actions and other CI/CD pipelines.

---

## 1. GitHub Actions — Security Scan on PR

Workflow that automatically runs security scans when plugin files change.

### Basic Setup

```yaml
# .github/workflows/plugin-security.yml
name: Plugin Security Scan

on:
  push:
    paths:
      - 'plugins/**'
  pull_request:
    paths:
      - 'plugins/**'

jobs:
  security-scan:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Install jq
        run: sudo apt-get install -y jq

      - name: Run Plugin Introspector Security Scan
        id: scan
        run: |
          chmod +x plugins/plugin-introspector/skills/plugin-introspector/scripts/security-scan.sh

          # Scan all plugins
          for plugin_dir in plugins/*/; do
            plugin_name=$(basename "$plugin_dir")
            echo "Scanning: $plugin_name"

            ./plugins/plugin-introspector/skills/plugin-introspector/scripts/security-scan.sh \
              --target "$plugin_dir" \
              --output "/tmp/scan-${plugin_name}.json" || true
          done

      - name: Check for CRITICAL findings
        run: |
          CRITICAL_COUNT=0
          for scan_file in /tmp/scan-*.json; do
            if [ -f "$scan_file" ]; then
              RISK=$(jq -r '.risk_score // "UNKNOWN"' "$scan_file")
              PLUGIN=$(jq -r '.plugin // "unknown"' "$scan_file")

              if [ "$RISK" = "CRITICAL" ]; then
                echo "::error::CRITICAL security risk in $PLUGIN"
                CRITICAL_COUNT=$((CRITICAL_COUNT + 1))
              elif [ "$RISK" = "HIGH" ]; then
                echo "::warning::HIGH security risk in $PLUGIN"
              fi
            fi
          done

          if [ "$CRITICAL_COUNT" -gt 0 ]; then
            echo "::error::$CRITICAL_COUNT plugin(s) have CRITICAL security issues"
            exit 1
          fi

      - name: Upload scan results
        uses: actions/upload-artifact@v4
        if: always()
        with:
          name: security-scan-results
          path: /tmp/scan-*.json
```

---

## 2. GitHub Actions — Full Analysis on Schedule

Workflow that runs full plugin analysis weekly or nightly.

```yaml
# .github/workflows/plugin-analysis.yml
name: Weekly Plugin Analysis

on:
  schedule:
    - cron: '0 2 * * 1'  # Every Monday at 2 AM UTC
  workflow_dispatch:      # Manual trigger

jobs:
  full-analysis:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Install dependencies
        run: sudo apt-get install -y jq

      - name: Run full security scan
        run: |
          chmod +x plugins/plugin-introspector/skills/plugin-introspector/scripts/security-scan.sh

          mkdir -p reports

          for plugin_dir in plugins/*/; do
            plugin_name=$(basename "$plugin_dir")
            ./plugins/plugin-introspector/skills/plugin-introspector/scripts/security-scan.sh \
              --target "$plugin_dir" \
              --output "reports/${plugin_name}-security.json" || true
          done

      - name: Generate summary report
        run: |
          echo "# Weekly Security Scan Report" > reports/summary.md
          echo "" >> reports/summary.md
          echo "| Plugin | Risk Score | Findings |" >> reports/summary.md
          echo "|--------|------------|----------|" >> reports/summary.md

          for report in reports/*-security.json; do
            if [ -f "$report" ]; then
              PLUGIN=$(jq -r '.plugin // "unknown"' "$report")
              RISK=$(jq -r '.risk_score // "UNKNOWN"' "$report")
              FINDINGS=$(jq '.findings | length // 0' "$report")
              echo "| $PLUGIN | $RISK | $FINDINGS |" >> reports/summary.md
            fi
          done

      - name: Upload reports
        uses: actions/upload-artifact@v4
        with:
          name: weekly-analysis-reports
          path: reports/
```

---

## 3. Pre-commit Hook

Run security scans before commits during local development.

### Setup

```bash
# .git/hooks/pre-commit (or .husky/pre-commit)
#!/bin/bash

# Check if any plugin files are staged
STAGED_PLUGINS=$(git diff --cached --name-only | grep '^plugins/' | cut -d'/' -f2 | sort -u)

if [ -n "$STAGED_PLUGINS" ]; then
  echo "Running security scan on changed plugins..."

  for plugin in $STAGED_PLUGINS; do
    echo "Scanning: $plugin"

    RESULT=$(./plugins/plugin-introspector/skills/plugin-introspector/scripts/security-scan.sh \
      --target "plugins/$plugin" 2>/dev/null)

    RISK=$(echo "$RESULT" | jq -r '.risk_score // "UNKNOWN"')

    if [ "$RISK" = "CRITICAL" ]; then
      echo "ERROR: CRITICAL security risk in $plugin"
      echo "Please fix security issues before committing."
      exit 1
    fi
  done

  echo "Security scan passed."
fi
```

---

## 4. GitLab CI

```yaml
# .gitlab-ci.yml
security-scan:
  stage: test
  image: ubuntu:latest
  before_script:
    - apt-get update && apt-get install -y jq bash
  script:
    - chmod +x plugins/plugin-introspector/skills/plugin-introspector/scripts/security-scan.sh
    - |
      for plugin_dir in plugins/*/; do
        plugin_name=$(basename "$plugin_dir")
        ./plugins/plugin-introspector/skills/plugin-introspector/scripts/security-scan.sh \
          --target "$plugin_dir" \
          --output "scan-${plugin_name}.json" || true
      done
    - |
      # Fail on CRITICAL
      for scan_file in scan-*.json; do
        if [ -f "$scan_file" ]; then
          RISK=$(jq -r '.risk_score // "UNKNOWN"' "$scan_file")
          if [ "$RISK" = "CRITICAL" ]; then
            echo "CRITICAL security risk found!"
            exit 1
          fi
        fi
      done
  artifacts:
    paths:
      - scan-*.json
    expire_in: 1 week
  rules:
    - changes:
        - plugins/**/*
```

---

## 5. Jenkins Pipeline

```groovy
// Jenkinsfile
pipeline {
    agent any

    stages {
        stage('Security Scan') {
            when {
                changeset 'plugins/**'
            }
            steps {
                sh '''
                    chmod +x plugins/plugin-introspector/skills/plugin-introspector/scripts/security-scan.sh

                    for plugin_dir in plugins/*/; do
                        plugin_name=$(basename "$plugin_dir")
                        ./plugins/plugin-introspector/skills/plugin-introspector/scripts/security-scan.sh \
                            --target "$plugin_dir" \
                            --output "scan-${plugin_name}.json" || true
                    done
                '''
            }
            post {
                always {
                    archiveArtifacts artifacts: 'scan-*.json', allowEmptyArchive: true
                }
            }
        }

        stage('Check Results') {
            steps {
                script {
                    def criticalFound = sh(
                        script: '''
                            for f in scan-*.json; do
                                [ -f "$f" ] && jq -e '.risk_score == "CRITICAL"' "$f" >/dev/null && exit 1
                            done
                            exit 0
                        ''',
                        returnStatus: true
                    )
                    if (criticalFound != 0) {
                        error("CRITICAL security issues found in plugins")
                    }
                }
            }
        }
    }
}
```

---

## 6. Environment Variables

See [SKILL.md Environment Variables](../SKILL.md#environment-variables) for the full list. CI/CD-specific additions:

| Variable | Default | Description |
|----------|---------|-------------|
| `INTROSPECTOR_BASE` | `~/.claude/plugin-introspector` | Data storage path override |
| `INTROSPECTOR_SCRIPTS` | Auto-detected | Scripts path override |

---

## 7. Exit Codes

Exit codes for `security-scan.sh`:

| Code | Meaning |
|------|---------|
| 0 | Scan completed (CLEAN, LOW, MEDIUM) |
| 1 | Scan completed (HIGH found) |
| 2 | Scan completed (CRITICAL found) |
| 10 | Plugin path not found |
| 11 | jq not installed |

---

## 8. Best Practices

1. **Set as required PR check** — Block merge on CRITICAL findings
2. **Weekly full scan** — Run periodically to detect new patterns
3. **Archive results** — Retain scan results for trend analysis
4. **Alert integration** — Send Slack/Teams alerts on CRITICAL findings

---

*Last updated: 2026-02-06*

#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# rotate-data.sh — Plugin Introspector Data Rotation Script
# ═══════════════════════════════════════════════════════════════════════════════
#
# Cleans up old session data based on retention policy.
#
# Environment Variables:
#   PI_RETENTION_DAYS  — Number of days to keep session directories (default: 30)
#   PI_RETENTION_LINES — Number of lines to keep in JSONL files (default: 1000)
#   PI_DRY_RUN         — If "1", only show what would be deleted without deleting
#
# Usage:
#   ./rotate-data.sh                    # Run with defaults
#   PI_RETENTION_DAYS=7 ./rotate-data.sh  # Keep only 7 days
#   PI_DRY_RUN=1 ./rotate-data.sh        # Dry run
#
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

# ── Configuration ─────────────────────────────────────────────────────────────
PI_RETENTION_DAYS="${PI_RETENTION_DAYS:-30}"
PI_RETENTION_LINES="${PI_RETENTION_LINES:-1000}"
PI_DRY_RUN="${PI_DRY_RUN:-0}"

# ── Colors (if terminal supports) ─────────────────────────────────────────────
if [ -t 1 ]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  BLUE='\033[0;34m'
  RESET='\033[0m'
else
  RED='' GREEN='' YELLOW='' BLUE='' RESET=''
fi

# ── Logging ───────────────────────────────────────────────────────────────────
log_info()  { echo -e "${BLUE}[INFO]${RESET} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${RESET} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${RESET} $*"; }
log_dry()   { echo -e "${YELLOW}[DRY-RUN]${RESET} $*"; }

# ── POSIX-portable human-readable size ────────────────────────────────────────
format_size() {
  awk -v s="$1" 'BEGIN {
    if (s >= 1073741824) printf "%.1fGiB", s/1073741824
    else if (s >= 1048576) printf "%.1fMiB", s/1048576
    else if (s >= 1024) printf "%.1fKiB", s/1024
    else printf "%dB", s
  }'
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
  echo "═══════════════════════════════════════════════════════════════════"
  echo " Plugin Introspector — Data Rotation"
  echo "═══════════════════════════════════════════════════════════════════"
  echo ""
  log_info "Base directory: $INTROSPECTOR_BASE"
  log_info "Retention: ${PI_RETENTION_DAYS} days, ${PI_RETENTION_LINES} lines per JSONL"
  [ "$PI_DRY_RUN" = "1" ] && log_warn "DRY RUN MODE — no files will be deleted"
  echo ""

  # Check if base directory exists
  if [ ! -d "$INTROSPECTOR_BASE" ]; then
    log_warn "Base directory does not exist: $INTROSPECTOR_BASE"
    log_info "Nothing to rotate."
    exit 0
  fi

  local sessions_deleted=0
  local bytes_freed=0

  # ── 1. Rotate old session directories ─────────────────────────────────────
  log_info "Scanning for sessions older than ${PI_RETENTION_DAYS} days..."

  local sessions_dir="$INTROSPECTOR_BASE/sessions"
  if [ -d "$sessions_dir" ]; then
    local now_epoch
    now_epoch=$(date +%s)
    local retention_seconds=$((PI_RETENTION_DAYS * 86400))

    for session_dir in "$sessions_dir"/*/; do
      [ -d "$session_dir" ] || continue
      # Get modification time (GNU stat -c, BSD stat -f fallback)
      local mod_time
      mod_time=$(stat -c %Y "$session_dir" 2>/dev/null || stat -f %m "$session_dir" 2>/dev/null || echo 0)
      local age=$((now_epoch - mod_time))
      [ "$age" -gt "$retention_seconds" ] || continue

      local session_name
      session_name=$(basename "$session_dir")
      local session_size
      session_size=$(du -sb "$session_dir" 2>/dev/null | cut -f1 || du -sk "$session_dir" 2>/dev/null | awk '{print $1*1024}' || echo 0)

      if [ "$PI_DRY_RUN" = "1" ]; then
        log_dry "Would delete: $session_name ($(format_size "$session_size"))"
      else
        rm -rf "$session_dir"
        log_ok "Deleted: $session_name"
      fi

      sessions_deleted=$((sessions_deleted + 1))
      bytes_freed=$((bytes_freed + session_size))
    done
  fi

  # ── 2. Trim JSONL files ───────────────────────────────────────────────────
  log_info "Trimming JSONL files to ${PI_RETENTION_LINES} lines..."

  local jsonl_files=(
    "session_history.jsonl"
    "evaluation_history.jsonl"
    "alerts.jsonl"
    "improvement_log.jsonl"
  )

  for jsonl in "${jsonl_files[@]}"; do
    local jsonl_path="$INTROSPECTOR_BASE/$jsonl"
    if [ -f "$jsonl_path" ]; then
      local current_lines
      current_lines=$(wc -l < "$jsonl_path" 2>/dev/null || echo 0)

      if [ "$current_lines" -gt "$PI_RETENTION_LINES" ]; then
        local to_remove=$((current_lines - PI_RETENTION_LINES))

        if [ "$PI_DRY_RUN" = "1" ]; then
          log_dry "Would trim $jsonl: $current_lines → $PI_RETENTION_LINES lines (remove $to_remove)"
        else
          tail -n "$PI_RETENTION_LINES" "$jsonl_path" > "$jsonl_path.tmp"
          mv "$jsonl_path.tmp" "$jsonl_path"
          log_ok "Trimmed $jsonl: $current_lines → $PI_RETENTION_LINES lines"
        fi
      else
        log_info "$jsonl: $current_lines lines (under limit, skipped)"
      fi
    fi
  done

  # ── 3. Summary ────────────────────────────────────────────────────────────
  echo ""
  echo "═══════════════════════════════════════════════════════════════════"
  echo " Summary"
  echo "═══════════════════════════════════════════════════════════════════"

  if [ "$PI_DRY_RUN" = "1" ]; then
    log_dry "Sessions that would be deleted: $sessions_deleted"
    log_dry "Space that would be freed: $(format_size "$bytes_freed")"
  else
    log_ok "Sessions deleted: $sessions_deleted"
    log_ok "Space freed: $(format_size "$bytes_freed")"
  fi

  # Count remaining sessions
  local remaining_sessions=0
  if [ -d "$sessions_dir" ]; then
    remaining_sessions=0
    for _d in "$sessions_dir"/*/; do [ -d "$_d" ] && remaining_sessions=$((remaining_sessions + 1)); done
  fi
  log_info "Remaining sessions: $remaining_sessions"

  echo ""
  log_ok "Data rotation complete."
}

# ── Entry Point ───────────────────────────────────────────────────────────────
main "$@"

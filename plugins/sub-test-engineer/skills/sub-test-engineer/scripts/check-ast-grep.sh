#!/usr/bin/env bash
# check-ast-grep.sh — Checks ast-grep CLI availability and version compatibility.
# Returns 0 if ast-grep is available (>=0.30.0), 1 otherwise.
# Usage: check-ast-grep.sh [--install-hint]

set -euo pipefail

MIN_VERSION="0.30.0"
INSTALL_HINT="${1:-}"

# --- Locate binary ---
SG_BIN=""
if command -v ast-grep &>/dev/null; then
    SG_BIN="ast-grep"
elif command -v sg &>/dev/null; then
    # Verify it's ast-grep's sg, not GNU sg (setgroups)
    if sg --version 2>/dev/null | grep -q "ast-grep"; then
        SG_BIN="sg"
    fi
fi

if [ -z "$SG_BIN" ]; then
    echo "[ast-grep] NOT FOUND"
    if [ "$INSTALL_HINT" = "--install-hint" ]; then
        echo ""
        echo "Install ast-grep using one of:"
        echo "  npm install -g @ast-grep/cli"
        echo "  cargo install ast-grep --locked"
        echo "  brew install ast-grep"
        echo "  pip install ast-grep-cli"
        echo ""
        echo "See: https://ast-grep.github.io/guide/quick-start.html"
    fi
    exit 1
fi

# --- Check version ---
VERSION=$($SG_BIN --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)

if [ -z "$VERSION" ]; then
    echo "[ast-grep] Found ($SG_BIN) but could not determine version"
    exit 1
fi

# Compare versions (major.minor.patch)
version_ge() {
    local IFS=.
    local i ver1=($1) ver2=($2)
    for ((i=0; i<3; i++)); do
        local v1=${ver1[i]:-0}
        local v2=${ver2[i]:-0}
        if ((v1 > v2)); then return 0; fi
        if ((v1 < v2)); then return 1; fi
    done
    return 0
}

if version_ge "$VERSION" "$MIN_VERSION"; then
    echo "[ast-grep] OK — $SG_BIN v$VERSION (>=$MIN_VERSION)"
    exit 0
else
    echo "[ast-grep] OUTDATED — $SG_BIN v$VERSION (need >=$MIN_VERSION)"
    if [ "$INSTALL_HINT" = "--install-hint" ]; then
        echo "  Update: npm update -g @ast-grep/cli"
    fi
    exit 1
fi

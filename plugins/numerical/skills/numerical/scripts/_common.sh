#!/usr/bin/env bash
# _common.sh — Shared utilities for numerical scripts
# Source this file from other scripts: source "$(dirname "$0")/_common.sh"

set -euo pipefail

# Colors (disabled if not terminal)
if [ -t 1 ]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  BLUE='\033[0;34m'
  NC='\033[0m'
else
  RED='' GREEN='' YELLOW='' BLUE='' NC=''
fi

log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $*"; }

# --- Project root detection ---
find_project_root() {
  local dir="${1:-.}"
  dir="$(cd "$dir" && pwd)"
  while [ "$dir" != "/" ]; do
    if [ -f "$dir/pyproject.toml" ] || [ -f "$dir/setup.py" ] || \
       [ -f "$dir/pubspec.yaml" ] || [ -f "$dir/requirements.txt" ]; then
      echo "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  # Fallback to git root
  git rev-parse --show-toplevel 2>/dev/null || echo "."
}

# --- Language detection ---
detect_language() {
  local root="${1:-.}"
  local has_python=false
  local has_dart=false

  if [ -f "$root/pyproject.toml" ] || [ -f "$root/setup.py" ] || \
     [ -f "$root/requirements.txt" ] || [ -f "$root/Pipfile" ]; then
    has_python=true
  fi

  if [ -f "$root/pubspec.yaml" ]; then
    has_dart=true
  fi

  if $has_python && $has_dart; then
    echo "mixed"
  elif $has_python; then
    echo "python"
  elif $has_dart; then
    echo "dart"
  else
    # Check for files
    local py_count dart_count
    py_count=$(find "$root" -maxdepth 3 -name "*.py" -not -path "*/\.*" 2>/dev/null | head -5 | wc -l)
    dart_count=$(find "$root" -maxdepth 3 -name "*.dart" -not -path "*/\.*" 2>/dev/null | head -5 | wc -l)

    if [ "$py_count" -gt 0 ] && [ "$dart_count" -gt 0 ]; then
      echo "mixed"
    elif [ "$py_count" -gt 0 ]; then
      echo "python"
    elif [ "$dart_count" -gt 0 ]; then
      echo "dart"
    else
      echo "unknown"
    fi
  fi
}

# --- Cache management ---
CACHE_DIR="${HOME}/.claude/cache"

ensure_cache_dir() {
  mkdir -p "$CACHE_DIR"
}

compute_project_hash() {
  local root="${1:-.}"
  echo -n "$root" | md5sum 2>/dev/null | cut -d' ' -f1 || echo "nohash"
}

get_cache_path() {
  local root="${1:-.}"
  local suffix="$2"
  local hash
  hash=$(compute_project_hash "$root")
  local name
  name=$(basename "$root")
  echo "${CACHE_DIR}/numerical-${hash}-${name}-${suffix}"
}

# --- File counting ---
count_numeric_files() {
  local root="${1:-.}"
  local lang="${2:-python}"
  local count=0

  case "$lang" in
    python|mixed)
      count=$(find "$root" -name "*.py" -not -path "*/\.*" -not -path "*/__pycache__/*" 2>/dev/null | wc -l)
      ;;
    dart)
      count=$(find "$root" -name "*.dart" -not -path "*/\.*" -not -path "*/.dart_tool/*" 2>/dev/null | wc -l)
      ;;
  esac

  echo "$count"
}

# --- Changed files ---
get_changed_files() {
  local root="${1:-.}"
  local ext="${2:-py}"
  git -C "$root" diff --name-only HEAD -- "*.${ext}" 2>/dev/null || true
}

# --- Numeric library detection (Python) ---
detect_python_libs() {
  local root="${1:-.}"
  local libs=""

  for file in "$root/pyproject.toml" "$root/requirements.txt" "$root/setup.py" "$root/setup.cfg" "$root/Pipfile"; do
    if [ -f "$file" ]; then
      local content
      content=$(cat "$file" 2>/dev/null || true)

      for lib in numpy scipy cupy torch tensorflow jax numba dask xarray pandas; do
        if echo "$content" | grep -qi "$lib" 2>/dev/null; then
          libs="${libs:+$libs,}$lib"
        fi
      done
    fi
  done

  echo "$libs"
}

# --- Numeric library detection (Dart) ---
detect_dart_libs() {
  local root="${1:-.}"
  local libs=""

  if [ -f "$root/pubspec.yaml" ]; then
    local content
    content=$(cat "$root/pubspec.yaml" 2>/dev/null || true)

    for lib in dart_tensor_preprocessing ml_linalg ml_dataframe tflite_flutter onnxruntime; do
      if echo "$content" | grep -qi "$lib" 2>/dev/null; then
        libs="${libs:+$libs,}$lib"
      fi
    done
  fi

  echo "$libs"
}

# --- GPU detection ---
detect_gpu_support() {
  local root="${1:-.}"
  local gpu_libs=""

  # Check Python files for GPU usage
  if grep -rql "cupy\|torch\.cuda\|tensorflow.*gpu\|jax\.devices\|numba\.cuda" \
     "$root" --include="*.py" 2>/dev/null | head -1 > /dev/null 2>&1; then
    gpu_libs="cuda"
  fi

  # Check for GPU packages in dependencies
  for file in "$root/pyproject.toml" "$root/requirements.txt"; do
    if [ -f "$file" ] && grep -qi "cupy\|torch.*cuda\|tensorflow-gpu\|jax\[cuda\]" "$file" 2>/dev/null; then
      gpu_libs="${gpu_libs:-cuda}"
    fi
  done

  echo "$gpu_libs"
}

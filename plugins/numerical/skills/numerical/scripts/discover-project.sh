#!/usr/bin/env bash
# discover-project.sh — Automatic numeric project profile detection
# Usage: ./discover-project.sh [--refresh] [--project path]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

# --- Parse arguments ---
REFRESH=false
PROJECT_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --refresh) REFRESH=true; shift ;;
    --project) PROJECT_DIR="$2"; shift 2 ;;
    *) PROJECT_DIR="$1"; shift ;;
  esac
done

PROJECT_DIR="${PROJECT_DIR:-$(find_project_root)}"
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"

ensure_cache_dir

CACHE_FILE=$(get_cache_path "$PROJECT_DIR" "profile.md")

# --- Check cache ---
if [ "$REFRESH" = false ] && [ -f "$CACHE_FILE" ]; then
  log_info "Using cached profile: $CACHE_FILE"
  cat "$CACHE_FILE"
  exit 0
fi

log_info "Discovering project: $PROJECT_DIR"

# --- Step 1: Language detection ---
LANGUAGE=$(detect_language "$PROJECT_DIR")
log_info "Language: $LANGUAGE"

# --- Step 2: Numeric library detection ---
PYTHON_LIBS=""
DART_LIBS=""

case "$LANGUAGE" in
  python|mixed)
    PYTHON_LIBS=$(detect_python_libs "$PROJECT_DIR")
    log_info "Python libs: ${PYTHON_LIBS:-none}"
    ;;
esac

case "$LANGUAGE" in
  dart|mixed)
    DART_LIBS=$(detect_dart_libs "$PROJECT_DIR")
    log_info "Dart libs: ${DART_LIBS:-none}"
    ;;
esac

ALL_LIBS="${PYTHON_LIBS}${PYTHON_LIBS:+${DART_LIBS:+,}}${DART_LIBS}"

# --- Step 3: Native extension detection ---
HAS_NATIVE=false
EXT_LANGS=""

if find "$PROJECT_DIR" -maxdepth 3 -name "*.pyx" 2>/dev/null | head -1 | grep -q .; then
  HAS_NATIVE=true
  EXT_LANGS="${EXT_LANGS:+$EXT_LANGS,}cython"
fi

if find "$PROJECT_DIR" -maxdepth 3 \( -name "*.c" -o -name "*.cpp" -o -name "*.h" \) -not -path "*/\.*" 2>/dev/null | head -1 | grep -q .; then
  HAS_NATIVE=true
  EXT_LANGS="${EXT_LANGS:+$EXT_LANGS,}c/cpp"
fi

if find "$PROJECT_DIR" -maxdepth 3 \( -name "*.f90" -o -name "*.f" -o -name "*.f77" \) 2>/dev/null | head -1 | grep -q .; then
  HAS_NATIVE=true
  EXT_LANGS="${EXT_LANGS:+$EXT_LANGS,}fortran"
fi

# Dart FFI
if [ "$LANGUAGE" = "dart" ] || [ "$LANGUAGE" = "mixed" ]; then
  if grep -rq "dart:ffi" "$PROJECT_DIR/lib" --include="*.dart" 2>/dev/null; then
    HAS_NATIVE=true
    EXT_LANGS="${EXT_LANGS:+$EXT_LANGS,}dart-ffi"
  fi
fi

# --- Step 4: GPU detection ---
GPU_SUPPORT=$(detect_gpu_support "$PROJECT_DIR")

# --- Step 5: Test framework detection ---
TEST_FRAMEWORK=""
HAS_NUMERIC_ASSERT=false
HAS_PROPERTY_TEST=false

case "$LANGUAGE" in
  python|mixed)
    if [ -f "$PROJECT_DIR/pytest.ini" ] || [ -f "$PROJECT_DIR/conftest.py" ] || \
       grep -q "pytest" "$PROJECT_DIR/pyproject.toml" 2>/dev/null; then
      TEST_FRAMEWORK="pytest"
    elif find "$PROJECT_DIR" -name "test_*.py" -maxdepth 3 2>/dev/null | head -1 | grep -q .; then
      TEST_FRAMEWORK="unittest"
    fi

    if grep -rq "numpy\.testing\|assert_allclose\|assert_array_equal" "$PROJECT_DIR" --include="*.py" 2>/dev/null; then
      HAS_NUMERIC_ASSERT=true
    fi

    if grep -rq "hypothesis" "$PROJECT_DIR" --include="*.py" 2>/dev/null; then
      HAS_PROPERTY_TEST=true
      TEST_FRAMEWORK="${TEST_FRAMEWORK:+$TEST_FRAMEWORK,}hypothesis"
    fi
    ;;
esac

case "$LANGUAGE" in
  dart|mixed)
    if [ -d "$PROJECT_DIR/test" ] || grep -q "test:" "$PROJECT_DIR/pubspec.yaml" 2>/dev/null; then
      TEST_FRAMEWORK="${TEST_FRAMEWORK:+$TEST_FRAMEWORK,}dart_test"
    fi
    ;;
esac

# --- Step 6: Analysis tool detection ---
ANALYSIS_TOOLS=""
TOOLS_FILE="$PROJECT_DIR/.numerical/analysis-tools.txt"

if [ -f "$TOOLS_FILE" ]; then
  ANALYSIS_TOOLS=$(tr '\n' ',' < "$TOOLS_FILE" | sed 's/,$//')
else
  # Auto-detect
  case "$LANGUAGE" in
    python|mixed)
      if grep -q "ruff" "$PROJECT_DIR/pyproject.toml" 2>/dev/null || [ -f "$PROJECT_DIR/ruff.toml" ]; then
        ANALYSIS_TOOLS="${ANALYSIS_TOOLS:+$ANALYSIS_TOOLS,}ruff"
      fi
      if grep -q "mypy" "$PROJECT_DIR/pyproject.toml" 2>/dev/null || [ -f "$PROJECT_DIR/mypy.ini" ]; then
        ANALYSIS_TOOLS="${ANALYSIS_TOOLS:+$ANALYSIS_TOOLS,}mypy"
      fi
      if [ -f "$PROJECT_DIR/.flake8" ] || grep -q "flake8" "$PROJECT_DIR/setup.cfg" 2>/dev/null; then
        ANALYSIS_TOOLS="${ANALYSIS_TOOLS:+$ANALYSIS_TOOLS,}flake8"
      fi
      if [ -f "$PROJECT_DIR/.pylintrc" ]; then
        ANALYSIS_TOOLS="${ANALYSIS_TOOLS:+$ANALYSIS_TOOLS,}pylint"
      fi
      ;;
  esac

  case "$LANGUAGE" in
    dart|mixed)
      if [ -f "$PROJECT_DIR/analysis_options.yaml" ]; then
        ANALYSIS_TOOLS="${ANALYSIS_TOOLS:+$ANALYSIS_TOOLS,}dart_analyze"
      fi
      ;;
  esac
fi

# --- Step 7: Detect primary dtype ---
PRIMARY_DTYPE="float64"
if grep -rq "float32\|np\.float32\|Float32" "$PROJECT_DIR" --include="*.py" --include="*.dart" 2>/dev/null; then
  float32_count=$(grep -rc "float32\|np\.float32\|Float32" "$PROJECT_DIR" --include="*.py" --include="*.dart" 2>/dev/null | awk -F: '{s+=$2} END{print s}' || echo 0)
  float64_count=$(grep -rc "float64\|np\.float64\|Float64" "$PROJECT_DIR" --include="*.py" --include="*.dart" 2>/dev/null | awk -F: '{s+=$2} END{print s}' || echo 0)
  if [ "${float32_count:-0}" -gt "${float64_count:-0}" ]; then
    PRIMARY_DTYPE="float32"
  fi
fi

# --- Generate profile ---
PROFILE="## Numeric Profile

- **project-dir**: $PROJECT_DIR
- **language**: $LANGUAGE
- **numeric-libs**: [${ALL_LIBS:-none}]
- **has-native-extensions**: $HAS_NATIVE
- **extension-languages**: [${EXT_LANGS:-none}]
- **gpu-support**: ${GPU_SUPPORT:-false}
- **gpu-framework**: [${GPU_SUPPORT:-none}]
- **test-framework**: [${TEST_FRAMEWORK:-none}]
- **has-numeric-assertions**: $HAS_NUMERIC_ASSERT
- **has-property-tests**: $HAS_PROPERTY_TEST
- **primary-dtype**: $PRIMARY_DTYPE
- **analysis-tools**: [${ANALYSIS_TOOLS:-none}]"

# --- Cache profile ---
echo "$PROFILE" > "$CACHE_FILE"
log_ok "Profile cached: $CACHE_FILE"

echo ""
echo "$PROFILE"

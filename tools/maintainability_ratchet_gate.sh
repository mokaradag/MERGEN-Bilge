#!/usr/bin/env bash

# ==============================================================================
# Dosya Yolu: tools/maintainability_ratchet_gate.sh
# Açıklama:
#   AI ajanları ve Git pre-commit kancası için iki zorunlu bakım ratchet testini
#   tek giriş noktasından çalıştırır.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

if ! command -v Rscript >/dev/null 2>&1; then
  echo "ERROR: Rscript is required for the maintainability ratchet gate." >&2
  echo "Run: bash tools/setup_ai_r_environment.sh" >&2
  exit 127
fi

export LANG="${LANG:-C.utf8}"
export TZ="${TZ:-UTC}"
export MERGEN_RUN_APP="${MERGEN_RUN_APP:-false}"
export MERGEN_DISABLE_FUTURES="${MERGEN_DISABLE_FUTURES:-true}"
export LOCAL_LLM_ENDPOINT="${LOCAL_LLM_ENDPOINT:-http://test.local/v1}"
export DB_DSN="${DB_DSN:-test-dsn}"
export AI_KEYS_MASTER="${AI_KEYS_MASTER:-test-master-key-0123456789}"

echo "== MERGEN mandatory maintainability ratchets =="
echo "- tests/testthat/test-maintainability-ratchet.R"
echo "- tests/testthat/test-frontend-maintainability-ratchet.R"

Rscript - <<'RSCRIPT'
library(testthat)

testthat::local_edition(3)

results <- testthat::test_dir(
  file.path("tests", "testthat"),
  filter = "^(maintainability-ratchet|frontend-maintainability-ratchet)$",
  reporter = "summary",
  stop_on_failure = TRUE,
  stop_on_warning = TRUE
)

invisible(results)
RSCRIPT

echo "== MERGEN maintainability ratchets passed =="

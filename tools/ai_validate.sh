#!/usr/bin/env bash

# ==============================================================================
# Dosya Yolu: tools/ai_validate.sh
# Açıklama:
#   AI ajanları için tek girişli doğrulama komutu.
#   Rscript yoksa önce tools/setup_ai_r_environment.sh ile ortamı hazırlar,
#   ardından tests/scripts/ai_repo_check.R çalıştırır.
#
# Kullanım:
#   bash tools/ai_validate.sh quick
#   bash tools/ai_validate.sh full --boot-smoke
#   bash tools/ai_validate.sh quick --answer .ai/proposed_answer.md
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

PROFILE="${1:-quick}"
shift || true

case "${PROFILE}" in
  quick|full)
    ;;
  *)
    echo "ERROR: First argument must be 'quick' or 'full'." >&2
    echo "Usage: bash tools/ai_validate.sh quick|full [--boot-smoke] [--answer path]" >&2
    exit 2
    ;;
esac

if ! command -v Rscript >/dev/null 2>&1; then
  echo "Rscript is unavailable. Running setup first..."
  bash tools/setup_ai_r_environment.sh
fi

if ! command -v Rscript >/dev/null 2>&1; then
  echo "ERROR: Rscript is unavailable even after setup." >&2
  exit 127
fi

export TZ="${TZ:-UTC}"
export MERGEN_RUN_APP="${MERGEN_RUN_APP:-false}"
export MERGEN_DISABLE_FUTURES="${MERGEN_DISABLE_FUTURES:-true}"
export LOCAL_LLM_ENDPOINT="${LOCAL_LLM_ENDPOINT:-http://test.local/v1}"
export DB_DSN="${DB_DSN:-test-dsn}"
export AI_KEYS_MASTER="${AI_KEYS_MASTER:-test-master-key-0123456789}"

echo "== MERGEN AI validation =="
echo "Profile: ${PROFILE}"
echo "Rscript: $(command -v Rscript)"

Rscript tests/scripts/ai_repo_check.R --profile "${PROFILE}" "$@"
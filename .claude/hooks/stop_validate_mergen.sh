#!/usr/bin/env bash

# ==============================================================================
# Dosya Yolu: .claude/hooks/stop_validate_mergen.sh
# Açıklama:
#   Claude Code Stop hook doğrulaması.
#   Repo üzerinde değişiklik varsa Claude'un final yanıta geçmeden önce
#   MERGEN hızlı doğrulamasını çalıştırır. Başarısızlık halinde Claude'u
#   durdurmak yerine çalışmaya devam etmeye zorlar.
#
# Kullanım:
#   Claude Code tarafından otomatik çağrılır.
# ==============================================================================

set -euo pipefail

INPUT="$(cat || true)"

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "${PROJECT_DIR}"

if [[ ! -f "app.R" || ! -d "R" || ! -d "tests" ]]; then
  exit 0
fi

if git diff --quiet --exit-code && git diff --cached --quiet --exit-code; then
  exit 0
fi

LOG_DIR="artifacts/claude-stop-validation"
mkdir -p "${LOG_DIR}"
LOG_PATH="${LOG_DIR}/$(date -u +%Y%m%d-%H%M%S)-quick.log"

set +e
bash tools/ai_validate.sh quick >"${LOG_PATH}" 2>&1
STATUS=$?
set -e

if [[ "${STATUS}" -eq 0 ]]; then
  exit 0
fi

TAIL_OUTPUT="$(tail -n 80 "${LOG_PATH}" | sed 's/\\/\\\\/g; s/"/\\"/g')"

printf '{'
printf '"decision":"block",'
printf '"reason":"MERGEN validation failed before final answer. Run/fix `bash tools/ai_validate.sh quick`. Log: %s\n\nLast log lines:\n%s"' \
  "\"${LOG_PATH}\"" \
  "${TAIL_OUTPUT}"
printf '}\n'
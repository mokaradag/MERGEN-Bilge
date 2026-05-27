#!/usr/bin/env bash

# ==============================================================================
# Dosya Yolu: tools/validation_doctor.sh
# Açıklama:
#   tests/scripts/validation_doctor.R için küçük kolaylık sarmalayıcısı.
#   Ağır doğrulama çalıştırmaz; yalnızca profil rehberi ve secret-safe ortam
#   özetini üretir.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${REPO_ROOT}"

if ! command -v Rscript >/dev/null 2>&1; then
  echo "ERROR: Rscript bulunamadı. Önce R kurulumunu veya tools/setup_ai_r_environment.sh akışını tamamlayın." >&2
  exit 127
fi

if [[ "$#" -gt 0 && "${1}" != --* ]]; then
  PROFILE="${1}"
  shift
  set -- --profile "${PROFILE}" "$@"
fi

Rscript tests/scripts/validation_doctor.R "$@"
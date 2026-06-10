#!/usr/bin/env bash

# ==============================================================================
# Dosya Yolu: tools/seam_doctor.sh
# Açıklama:
#   tests/scripts/seam_doctor.R için küçük kolaylık sarmalayıcısı.
#   Üretim-kritik dikiş (seam) kayıt defterini ve frontend bölge sahiplik
#   haritasını manifest gerçekliğine karşı doğrular; secret-safe JSON artifact
#   üretir. Ağır doğrulama (app boot, tarayıcı, DB, LLM) ÇALIŞTIRMAZ.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${REPO_ROOT}"

if ! command -v Rscript >/dev/null 2>&1; then
  echo "ERROR: Rscript bulunamadı. Önce R kurulumunu veya tools/setup_ai_r_environment.sh akışını tamamlayın." >&2
  exit 127
fi

Rscript tests/scripts/seam_doctor.R "$@"

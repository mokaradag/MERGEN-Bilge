#!/usr/bin/env bash

# ==============================================================================
# Dosya Yolu: tools/vm_evidence_gate.sh
# Açıklama:
#   tests/scripts/run_vm_evidence_gate.R için kolaylık sarmalayıcısı.
#   MERGEN Bilge'nin TEK tekrarlanabilir preflight doğrulama yolunu çalıştırır
#   ve artifacts/vm-evidence/<timestamp>/evidence.json altında secret-güvenli
#   kanıt artifact'ı üretir.
#
# Kullanım:
#   bash tools/vm_evidence_gate.sh                  # profil otomatik (SSO'ya göre)
#   MERGEN_EVIDENCE_PROFILE=vm bash tools/vm_evidence_gate.sh
#   MERGEN_EVIDENCE_PROFILE=cloud bash tools/vm_evidence_gate.sh
#   MERGEN_EVIDENCE_STEPS=seam_doctor,renv_status bash tools/vm_evidence_gate.sh
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${REPO_ROOT}"

# POSIX/C locale altinda R, UTF-8 icerikli betikleri sessizce kirpabilir.
# Mevcut locale UTF-8 degilse cocuk R surecleri icin UTF-8 locale zorla.
case "${LC_ALL:-${LANG:-}}" in
  *UTF-8*|*utf8*) : ;;
  *)
    export LANG=C.UTF-8 LC_ALL=C.UTF-8
    ;;
esac

if ! command -v Rscript >/dev/null 2>&1; then
  echo "ERROR: Rscript bulunamadı. Önce R kurulumunu veya tools/setup_ai_r_environment.sh akışını tamamlayın." >&2
  exit 127
fi

# Ana betik .Renviron dosyasini kendi yukler; --vanilla .Rprofile yan etkilerini disarida tutar.
Rscript --vanilla tests/scripts/run_vm_evidence_gate.R "$@"
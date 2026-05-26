#!/usr/bin/env bash

# ==============================================================================
# Dosya Yolu: tools/setup_ai_r_environment.sh
# Açıklama:
#   Codex / Claude Code / AI agent Linux sandbox ortamlarında Rscript yoksa
#   R çalışma zamanını ve MERGEN test bağımlılıklarını kurar.
#
# Kullanım:
#   bash tools/setup_ai_r_environment.sh
#
# Notlar:
#   - Betik idempotent çalışacak şekilde tasarlanmıştır.
#   - Rscript zaten varsa sistem R kurulumuna dokunmaz.
#   - Paket kurulumunu mevcut tests/scripts/ci_install_packages.R üzerinden yapar.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

echo "== MERGEN AI R environment setup =="
echo "Repo root: ${REPO_ROOT}"

if command -v Rscript >/dev/null 2>&1; then
  echo "OK: Rscript already available: $(command -v Rscript)"
else
  echo "Rscript not found. Attempting Linux apt installation..."

  if ! command -v apt-get >/dev/null 2>&1; then
    echo "ERROR: apt-get is not available in this environment." >&2
    echo "Install R manually or run this repo in a Codex/Claude environment that supports apt." >&2
    exit 127
  fi

  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    SUDO=""
  fi

  export DEBIAN_FRONTEND=noninteractive

  # apt-get update güvenli çalıştırıcı: engellenen PPA'lar (deadsnakes, ondrej,
  # ppa.launchpadcontent.net) HTTP 403 döndürdüğünde ilgili kaynak dosyalarını
  # devre dışı bırakıp tekrar dener; yalnızca ikinci deneme de başarısız olursa
  # hata verir. Hem klasik .list hem de deb822 .sources formatını destekler.
  _safe_apt_update() {
    if ${SUDO} apt-get update 2>&1; then
      return 0
    fi
    echo "apt-get update failed. Disabling blocked PPAs and retrying..." >&2
    local blocked_pattern='deadsnakes|ondrej|ppa\.launchpadcontent\.net|launchpad\.net'

    # Klasik .list dosyaları: deb satırlarını yorum satırına çevir
    while IFS= read -r f; do
      [[ -f "${f}" ]] || continue
      if grep -Eiq "${blocked_pattern}" "${f}" 2>/dev/null; then
        echo "  Commenting out blocked entries in: ${f}" >&2
        ${SUDO} sed -i -E \
          "s|^(deb[[:space:]].*(deadsnakes|ondrej|ppa\.launchpadcontent\.net|launchpad\.net).*)$|# DISABLED-BLOCKED-PPA \1|I" \
          "${f}" || true
      fi
    done < <(find /etc/apt/sources.list /etc/apt/sources.list.d/ -name '*.list' 2>/dev/null || true)

    # deb822 .sources dosyaları: 'Enabled: no' ekle veya güncelle
    while IFS= read -r f; do
      [[ -f "${f}" ]] || continue
      if grep -Eiq "${blocked_pattern}" "${f}" 2>/dev/null; then
        echo "  Disabling blocked deb822 source: ${f}" >&2
        if grep -qi '^Enabled:' "${f}" 2>/dev/null; then
          ${SUDO} sed -i -E 's|^(Enabled:.*)$|Enabled: no|I' "${f}" || true
        else
          ${SUDO} sed -i '1s|^|Enabled: no\n|' "${f}" || true
        fi
      fi
    done < <(find /etc/apt/sources.list.d/ -name '*.sources' 2>/dev/null || true)

    ${SUDO} apt-get update
  }

  _safe_apt_update

  ${SUDO} apt-get install -y --no-install-recommends \
    r-base \
    r-base-dev \
    build-essential \
    make \
    curl \
    git \
    pandoc \
    ca-certificates \
    unixodbc-dev \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    libfontconfig1-dev \
    libfreetype6-dev \
    libharfbuzz-dev \
    libfribidi-dev \
    libpng-dev \
    libjpeg-dev \
    libudunits2-dev \
    libpoppler-cpp-dev \
    libgit2-dev \
    libglpk-dev \
    libavfilter-dev \
    libavformat-dev \
    libavcodec-dev \
    libavdevice-dev \
    libavutil-dev \
    libswscale-dev

  if ! dpkg -s libtiff5-dev >/dev/null 2>&1; then
    ${SUDO} apt-get install -y --no-install-recommends libtiff5-dev || \
    ${SUDO} apt-get install -y --no-install-recommends libtiff-dev || true
  fi
fi

if ! command -v Rscript >/dev/null 2>&1; then
  echo "ERROR: Rscript is still unavailable after setup." >&2
  exit 127
fi

echo "Rscript: $(command -v Rscript)"
Rscript --version

export LANG="${LANG:-C.utf8}"
export TZ="${TZ:-UTC}"
export MERGEN_RUN_APP="${MERGEN_RUN_APP:-false}"
export MERGEN_DISABLE_FUTURES="${MERGEN_DISABLE_FUTURES:-true}"
export LOCAL_LLM_ENDPOINT="${LOCAL_LLM_ENDPOINT:-http://test.local/v1}"
export DB_DSN="${DB_DSN:-test-dsn}"
export AI_KEYS_MASTER="${AI_KEYS_MASTER:-test-master-key-0123456789}"
# Ubuntu Noble (24.04) üzerinde jammy RSPM URL'si çalışmaz; noble veya CRAN kullan.
if [[ -z "${RSPM:-}" ]]; then
  if grep -qi 'noble\|24\.04' /etc/os-release 2>/dev/null; then
    RSPM="https://packagemanager.posit.co/cran/__linux__/noble/latest"
  else
    RSPM="https://packagemanager.posit.co/cran/__linux__/jammy/latest"
  fi
fi
export RSPM

INSTALL_R_PACKAGES="${MERGEN_AI_SETUP_INSTALL_PACKAGES:-true}"

if [[ "${INSTALL_R_PACKAGES}" == "true" ]]; then
  echo "Installing/checking R package dependencies..."
  Rscript tests/scripts/ci_install_packages.R
else
  echo "Skipping R package installation because MERGEN_AI_SETUP_INSTALL_PACKAGES=false."
  echo "R packages will be installed later by the explicit validation step if requested."
fi

echo "OK: MERGEN AI R environment is ready."
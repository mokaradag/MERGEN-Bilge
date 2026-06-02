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

  # En güncel R sürümünü (on-prem VM ile uyum için, ör. R 4.5.x) CRAN apt
  # deposundan kurmayı dene. Bu en iyi çaba ile çalışır; anahtar/depo eklenemezse
  # dağıtımın varsayılan r-base sürümüne (ör. Ubuntu Noble 4.3.x) sessizce geri
  # düşülür. cloud.r-project.org ağ allowlist'inde açık olmalıdır.
  # Kapatmak/sabitlemek için: MERGEN_AI_INSTALL_LATEST_R=false
  _add_cran_apt_repo_for_latest_r() {
    command -v curl >/dev/null 2>&1 || return 0

    local codename=""
    if [[ -r /etc/os-release ]]; then
      codename="$(. /etc/os-release 2>/dev/null && echo "${VERSION_CODENAME:-}")"
    fi
    [[ -n "${codename}" ]] || return 0

    echo "CRAN apt deposu ekleniyor (en güncel R): ${codename}-cran40"
    if curl -fsSL https://cloud.r-project.org/bin/linux/ubuntu/marutter_pubkey.asc \
         | ${SUDO} tee /etc/apt/trusted.gpg.d/cran_ubuntu_key.asc >/dev/null 2>&1; then
      echo "deb https://cloud.r-project.org/bin/linux/ubuntu ${codename}-cran40/" \
        | ${SUDO} tee /etc/apt/sources.list.d/cran-r.list >/dev/null 2>&1 || true
    else
      echo "WARN: CRAN apt anahtarı alınamadı; dağıtımın varsayılan R sürümü kullanılacak." >&2
    fi
  }

  if [[ "${MERGEN_AI_INSTALL_LATEST_R:-true}" == "true" ]]; then
    _add_cran_apt_repo_for_latest_r
  fi

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

# MERGEN_AI_SETUP_INSTALL_APT_R_PACKAGES=true olduğunda, CRAN'dan kaynak kod
# derlemek yerine mevcut Ubuntu binary R paketlerini apt üzerinden kurmaya çalış.
# Özellikle duckdb gibi uzun süren native derlemeleri Codex doğrulamasından önce
# çözmek için best-effort çalışır.
install_available_apt_r_packages() {
  local requested_packages=(
    r-cran-testthat
    r-cran-withr
    r-cran-processx
    r-cran-callr
    r-cran-jsonlite
    r-cran-bit
    r-cran-bit64
    r-cran-duckdb
    r-cran-dbi
    r-cran-dplyr
    r-cran-data.table
    r-cran-dt
    r-cran-shiny
    r-cran-htmltools
    r-cran-httr
    r-cran-curl
    r-cran-openssl
    r-cran-pdftools
    r-cran-readr
    r-cran-readxl
    r-cran-stringi
    r-cran-stringr
    r-cran-tibble
    r-cran-tidyr
    r-cran-xml2
    r-cran-av
    r-cran-arrow
    r-cran-base64enc
    r-cran-cellranger
    r-cran-cli
    r-cran-commonmark
    r-cran-fastmatch
    r-cran-future
    r-cran-glue
    r-cran-later
    r-cran-lubridate
    r-cran-markdown
    r-cran-odbc
    r-cran-pool
    r-cran-promises
    r-cran-purrr
    r-cran-shinybs
    r-cran-shinycssloaders
    r-cran-shinydashboard
    r-cran-shinyjs
    r-cran-shinywidgets
    r-cran-stringdist
    r-cran-urltools
    r-cran-writexl
  )

  local available_packages=()
  local missing_packages=()

  echo "Checking available Ubuntu binary R packages..."

  for pkg in "${requested_packages[@]}"; do
    if apt-cache show "${pkg}" >/dev/null 2>&1; then
      available_packages+=("${pkg}")
    else
      missing_packages+=("${pkg}")
    fi
  done

  if [[ "${#missing_packages[@]}" -gt 0 ]]; then
    echo "WARNING: These apt R packages are not available in this image:"
    printf '  %s\n' "${missing_packages[@]}"
  fi

  if [[ "${#available_packages[@]}" -eq 0 ]]; then
    echo "No apt R packages are available to install."
    return 0
  fi

  echo "Installing available Ubuntu binary R packages:"
  printf '  %s\n' "${available_packages[@]}"

  ${SUDO} apt-get install -y --no-install-recommends "${available_packages[@]}"
}

if [[ "${MERGEN_AI_SETUP_INSTALL_APT_R_PACKAGES:-false}" == "true" ]]; then
  if ! command -v apt-get >/dev/null 2>&1; then
    echo "WARNING: apt-get unavailable; skipping apt R package install."
  else
    if command -v sudo >/dev/null 2>&1; then
      SUDO="sudo"
    else
      SUDO=""
    fi

    export DEBIAN_FRONTEND=noninteractive
    install_available_apt_r_packages
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
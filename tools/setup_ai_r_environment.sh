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

  apt_update_with_blocked_ppa_recovery() {
    echo "Running apt-get update..."

    if ${SUDO} apt-get update; then
      return 0
    fi

    echo "WARNING: apt-get update failed. Attempting to disable blocked third-party PPAs..."

    local apt_files=()
    if [[ -f /etc/apt/sources.list ]]; then
      apt_files+=("/etc/apt/sources.list")
    fi

    if compgen -G "/etc/apt/sources.list.d/*.list" >/dev/null; then
      while IFS= read -r file; do
        apt_files+=("${file}")
      done < <(find /etc/apt/sources.list.d -maxdepth 1 -type f -name "*.list" | sort)
    fi

    for file in "${apt_files[@]}"; do
      if grep -Eiq "deadsnakes|ondrej|ppa\.launchpadcontent\.net|launchpad\.net" "${file}"; then
        echo "Disabling blocked PPA entries in ${file}"
        ${SUDO} sed -i.bak -E \
          '/deadsnakes|ondrej|ppa\.launchpadcontent\.net|launchpad\.net/I s/^/# disabled by MERGEN AI bootstrap: /' \
          "${file}"
      fi
    done

    echo "Retrying apt-get update after disabling blocked PPA entries..."
    ${SUDO} apt-get update
  }

  apt_update_with_blocked_ppa_recovery

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

export TZ="${TZ:-UTC}"
export MERGEN_RUN_APP="${MERGEN_RUN_APP:-false}"
export MERGEN_DISABLE_FUTURES="${MERGEN_DISABLE_FUTURES:-true}"
export LOCAL_LLM_ENDPOINT="${LOCAL_LLM_ENDPOINT:-http://test.local/v1}"
export DB_DSN="${DB_DSN:-test-dsn}"
export AI_KEYS_MASTER="${AI_KEYS_MASTER:-test-master-key-0123456789}"
export RSPM="${RSPM:-https://packagemanager.posit.co/cran/__linux__/jammy/latest}"

echo "Installing/checking R package dependencies..."
Rscript tests/scripts/ci_install_packages.R

echo "OK: MERGEN AI R environment is ready."
#!/usr/bin/env bash

# ==============================================================================
# Dosya Yolu: .claude/hooks/session-start.sh
# Açıklama:
#   Claude Code (web / uzak) SessionStart hook'u.
#   Oturum başlarken R çalışma zamanını ve MERGEN test bağımlılıklarını kurar,
#   böylece ajan yanıt vermeden önce repo testlerini çalıştırabilir.
#
#   Paket listesi BİLEREK burada tekrar tanımlanmaz; mevcut
#   tools/setup_ai_r_environment.sh betiği R/config_packages.R içindeki
#   required_packages listesini tek kaynak olarak okur.
#
# Kullanım:
#   Claude Code tarafından oturum başında otomatik çağrılır.
#   Elle test: CLAUDE_CODE_REMOTE=true bash .claude/hooks/session-start.sh
# ==============================================================================

set -euo pipefail

# Yalnızca Claude Code web / uzak ortamda çalış. Yerel makineye dokunma.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "${PROJECT_DIR}"

# Beklenen repo yapısı yoksa sessizce çık (yanlış dizinde çalıştırma koruması).
if [ ! -f "app.R" ] || [ ! -d "R" ] || [ ! -d "tests" ]; then
  exit 0
fi

# Test/ajan modu ortam değişkenlerini tüm oturum için kalıcı yap.
# Bu sayede ad-hoc `Rscript -e '...'` ve `Rscript tests/testthat.R` komutları
# Shiny uygulamasını veya future worker cluster'ını başlatmaz.
# LOCAL_LLM_ENDPOINT / DB_DSN / AI_KEYS_MASTER yalnızca güvenli placeholder'dır;
# gerçek sır, DSN veya kimlik bilgisi DEĞİLDİR (config_file_store.R bunları
# zorunlu saydığı için boot sırasında ihtiyaç duyulur).
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  {
    echo 'export TZ="UTC"'
    echo 'export LANG="C.utf8"'
    echo 'export MERGEN_RUN_APP="false"'
    echo 'export MERGEN_DISABLE_FUTURES="true"'
    echo 'export LOCAL_LLM_ENDPOINT="http://test.local/v1"'
    echo 'export DB_DSN="test-dsn"'
    echo 'export AI_KEYS_MASTER="test-master-key-0123456789"'
  } >> "${CLAUDE_ENV_FILE}"
fi

# R + sistem kütüphaneleri + R paketlerini kur (idempotent).
# Sıcak (cache'lenmiş) konteynerde Rscript ve paketler zaten kuruluysa hızlı geçer.
echo "== MERGEN SessionStart: R ortamı hazırlanıyor =="
if bash tools/setup_ai_r_environment.sh; then
  echo "== MERGEN SessionStart: R ortamı hazır =="
else
  # Kurulum tam tamamlanmazsa (ör. ağ allowlist eksikse) oturumu bloklama;
  # ajan yine de durumu teşhis edip hafif doğrulama (parse/cloud-quick) deneyebilir.
  echo "WARN: R ortam kurulumu tam tamamlanamadı. Ağ allowlist (packagemanager.posit.co / cloud.r-project.org) ve apt erişimini kontrol edin." >&2
fi

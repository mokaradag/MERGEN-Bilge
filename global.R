# ==============================================================================
# Dosya Adı: global.R
# Açıklama:  Shiny uygulamasının giriş noktası ve küresel yapılandırma dosyası.
#            Kodlama ayarlarını yapar, veritabanı hedeflerini tanımlar ve
#            uygulamanın çalışması için gerekli tüm modül, yardımcı fonksiyon
#            ve yapılandırma dosyalarını (R/ klasörü altındaki) yükler.
# ==============================================================================

# Küresel olarak UTF-8 kodlamasını zorla
options(encoding = "UTF-8")

# Future paketinin RNG (rastgele sayı üretimi) hatalarını yoksay
options(future.rng.onMisuse = "ignore")

# Yerel ayarları İngilizce UTF-8 olarak ayarlamayı dene (hataları gizle)
try(suppressWarnings(Sys.setlocale("LC_ALL", "en_US.UTF-8")), silent = TRUE)

# Sadece bu yerel ayar çağrısı için uyarıları bastır (Türkçe karakter desteği)
try(suppressWarnings(Sys.setlocale("LC_CTYPE", "Turkish_Turkey.UTF-8")), silent = TRUE)

# ------------------------------------------------------------------------------
# VERİTABANI HEDEF TANIMLARI (DATABASE TARGET CONSTANTS)
# ------------------------------------------------------------------------------
# Uygulama genelinde hangi veritabanına gidileceğini belirten standart etiketler.
# 'library_queries.R' içindeki sorgularda bu etiketleri kullanacağız.
DB_TARGETS <- list(
  PRIMARY   = "primary",   # Ana veritabanı (Varsayılan) -> .Renviron: DB_DSN
  SECONDARY = "secondary", # İkincil veritabanı          -> .Renviron: DB_DSN_2
  TERTIARY  = "tertiary"   # Üçüncül veritabanı          -> .Renviron: DB_DSN_3
)

# Yorumlu yanıtlara izin ver (LLM'in ikinci yazım geçişi açık kalsın)
options(mergen.ai.strict_data_only = FALSE)

# ==============================================================================
# MODÜLERLEŞTİRİLMİŞ YAPILANDIRMA DOSYALARI
# ==============================================================================
source("R/config_packages.R",    encoding = "UTF-8")  # Paket yüklemeleri
source("R/utils_common.R",       encoding = "UTF-8")  # Ortak yardımcı fonksiyonlar (%||%, safe_nzchar, vb.)
source("R/config_logging.R",     encoding = "UTF-8")  # Loglama altyapısı
source("R/utils_rate_limiter.R", encoding = "UTF-8")  # Hız sınırlama + işçi havuzu
source("R/utils_path_helpers.R", encoding = "UTF-8")  # Yol normalizasyon yardımcıları
source("R/utils_file_index.R",   encoding = "UTF-8")  # Önbellekli dosya indeks mekanizması
source("R/config_file_store.R",  encoding = "UTF-8")  # Dosya deposu altyapısı
source("R/utils_excel_reader.R", encoding = "UTF-8")  # Excel okuyucu yardımcıları

# --- MODÜLLERİ VE YARDIMCILARI YÜKLE ---
# Shiny uygulamaları için standart göreceli yollar kullanmak en güvenilir yöntemdir.
source("R/config_characters.R", encoding = "UTF-8")
source("welcome_screen.R",     encoding = "UTF-8")
source("R/helpers_database.R", encoding ="UTF-8")
source("R/helpers_language.R", encoding ="UTF-8")
source("R/helpers_messaging.R", encoding ="UTF-8")
source("R/helpers_mcp_tools.R", encoding ="UTF-8")
source("R/helpers_chartlab.R",    encoding = "UTF-8")
source("R/helpers_image_gallery.R", encoding = "UTF-8")
source("R/helpers_preview.R",     encoding = "UTF-8")
source("R/helpers_file_pipeline.R", encoding = "UTF-8")
source("R/helpers_files.R",     encoding = "UTF-8")
source("R/helpers_chat_runtime.R", encoding = "UTF-8")
source("R/helpers_summarization_modes.R", encoding = "UTF-8")
source("R/helpers_summarization_prompts.R", encoding = "UTF-8")
source("R/helpers_followup_questions.R", encoding = "UTF-8")
source("R/library_queries.R", encoding = "UTF-8")
source("R/config_sql_loader.R",  encoding = "UTF-8")
source("R/module_summarization.R", encoding = "UTF-8")
source("R/module_proje_kaynak_analizi.R", encoding = "UTF-8")
source("R/module_chat_history.R", encoding ="UTF-8")
source("R/module_file_manager.R", encoding ="UTF-8")
source("R/module_saved_chats.R", encoding ="UTF-8")
source("R/module_settings.R", encoding ="UTF-8")
source("R/module_character_video.R", encoding ="UTF-8")
source("R/module_performance.R", encoding ="UTF-8")
source("R/module_ai_processing.R", encoding ="UTF-8")
source("R/module_tts.R", encoding ="UTF-8")
source("R/module_stt.R", encoding = "UTF-8")
source("R/module_session_timeout.R", encoding = "UTF-8")
source("R/module_file_preview.R", encoding = "UTF-8")
source("R/module_api_key.R", encoding = "UTF-8")
source("R/module_message_search.R", encoding = "UTF-8")
source("R/module_followup_questions.R", encoding = "UTF-8")
source("R/module_chat_actions.R",  encoding = "UTF-8")
source("R/module_chat_export.R",   encoding = "UTF-8")
source("R/module_admin_analytics.R", encoding = "UTF-8")
source("R/module_feedback.R", encoding = "UTF-8")
source("R/module_quick_actions.R", encoding = "UTF-8")
source("R/module_image_generation.R", encoding = "UTF-8")
source("R/module_image_gallery.R", encoding = "UTF-8")
source("R/module_user_identity.R", encoding = "UTF-8")
source("R/server_session_cache.R", encoding = "UTF-8")
source("R/server_observers_settings.R", encoding = "UTF-8")
source("R/server_observers_storage.R", encoding = "UTF-8")
source("R/server_outputs_chat.R", encoding = "UTF-8")
source("R/server_observers_files.R", encoding = "UTF-8")
source("R/server_observers_saved_chats.R", encoding = "UTF-8")
source("R/server_observers_image_gallery.R", encoding = "UTF-8")
source("R/server_observers_chat_ui.R", encoding = "UTF-8")
source("R/server_observers_navigation.R", encoding = "UTF-8")
source("R/server_observers_file_clicks.R", encoding = "UTF-8")
source("R/server_observers_startup.R", encoding = "UTF-8")
source("R/server_observers_chat_input.R", encoding = "UTF-8")
source("R/server_observers_misc.R", encoding = "UTF-8")
source("R/server_outputs_downloads.R", encoding = "UTF-8")
source("R/server_tts_handlers.R", encoding = "UTF-8")
source("R/server_music_handlers.R", encoding = "UTF-8")
source("R/server_welcome_handlers.R", encoding = "UTF-8")
source("R/server_llm_response_handlers.R", encoding = "UTF-8")
source("R/server_send_message.R", encoding = "UTF-8")
source("R/config_api.R",         encoding = "UTF-8")
source("R/helpers_llm_tool_formatters.R", encoding = "UTF-8")
source("R/helpers_llm_api.R",            encoding = "UTF-8")
source("R/helpers_llm_worker.R",         encoding = "UTF-8")
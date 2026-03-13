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
# GÜVENLİ KAYNAK YÜKLEME FONKSİYONU (SAFE SOURCE)
# ------------------------------------------------------------------------------
# Bazı Windows sanal makinelerinde (özellikle Türkçe yerel ayarlı sistemlerde)
# source(encoding = "UTF-8") dosya düzeyinde UTF-8 baytlarını yanlış okuyarak
# INCOMPLETE_STRING hatasına neden olur. Bu fonksiyon dosyayı önce metin olarak
# okuyup ardından parse() ile değerlendirir ve bu sorunu tamamen ortadan kaldırır.
# ------------------------------------------------------------------------------
safe_source <- function(file, encoding = "UTF-8", envir = globalenv()) {
  # Read as raw bytes — no encoding conversion happens here
  raw <- readBin(file, "raw", file.info(file)$size)
  text <- rawToChar(raw)
  Encoding(text) <- encoding
  # Remove BOM if present
  text <- sub("^\uFEFF", "", text)
  # Split into lines (handle both \r\n and \n)
  lines <- strsplit(text, "\r?\n")[[1]]
  Encoding(lines) <- encoding
  exprs <- parse(text = lines, keep.source = FALSE, encoding = encoding)
  eval(exprs, envir = envir)
  invisible(NULL)
}

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

# Destek ek dosyalarını sunmak için kaynak yolu tanımla
destek_uploads_dir <- file.path(getwd(), "destek_uploads")
if (dir.exists(destek_uploads_dir)) {
  shiny::addResourcePath("destek_uploads", destek_uploads_dir)
}

# ==============================================================================
# BAĞIMLILIK YÜKLEME MANİFESTİ
# ==============================================================================
# Yükleme sırası önemlidir. Her grup, bir önceki grubun tanımlarına bağımlıdır.
# Yeni dosya eklerken ait olduğu gruba ve bağımlılık sırasına dikkat ediniz.
# ==============================================================================

# ------------------------------------------------------------------------------
# GRUP 1: Temel Altyapı (paketler, yardımcılar, loglama)
# Hiçbir uygulama koduna bağımlı değildir, diğer her şeyden önce yüklenir.
# ------------------------------------------------------------------------------
safe_source("R/config_packages.R",    encoding = "UTF-8")  # Paket yüklemeleri
safe_source("R/utils_common.R",       encoding = "UTF-8")  # Ortak yardımcı fonksiyonlar (%||%, safe_nzchar, vb.)
safe_source("R/config_logging.R",     encoding = "UTF-8")  # Loglama altyapısı
safe_source("R/utils_rate_limiter.R", encoding = "UTF-8")  # Hız sınırlama + işçi havuzu
safe_source("R/utils_path_helpers.R", encoding = "UTF-8")  # Yol normalizasyon yardımcıları
safe_source("R/utils_file_index.R",   encoding = "UTF-8")  # Önbellekli dosya indeks mekanizması
safe_source("R/utils_excel_reader.R", encoding = "UTF-8")  # Excel okuyucu yardımcıları

# ------------------------------------------------------------------------------
# GRUP 2: Yapılandırma Dosyaları
# Temel altyapıya bağımlıdır, uygulama genelinde kullanılan sabitleri tanımlar.
# ------------------------------------------------------------------------------
safe_source("R/config_sso.R",              encoding = "UTF-8")  # SSO yapılandırması ve küresel mod anahtarı
safe_source("R/config_file_store.R",       encoding = "UTF-8")  # Dosya deposu altyapısı
safe_source("R/config_characters.R",       encoding = "UTF-8")  # Karakter/persona tanımları
safe_source("R/config_version_history.R",  encoding = "UTF-8")  # Sürüm geçmişi
safe_source("R/config_api.R",              encoding = "UTF-8")  # API yapılandırması ve uç noktaları

# ------------------------------------------------------------------------------
# GRUP 3: Veritabanı ve Sorgu Altyapısı
# Yapılandırma dosyalarına bağımlıdır, modüller tarafından kullanılır.
# ------------------------------------------------------------------------------
safe_source("R/helpers_database.R",   encoding = "UTF-8")  # Veritabanı bağlantı yönetimi
safe_source("R/library_queries.R",    encoding = "UTF-8")  # Hazır SQL sorguları
safe_source("R/config_sql_loader.R",  encoding = "UTF-8")  # SQL yükleme yapılandırması

# ------------------------------------------------------------------------------
# GRUP 4: Çekirdek Yardımcı Fonksiyonlar
# Veritabanı ve yapılandırmaya bağımlıdır, modüller tarafından kullanılır.
# ------------------------------------------------------------------------------
safe_source("R/helpers_language.R",              encoding = "UTF-8")  # Dil araçları ve çeviri
safe_source("R/helpers_messaging.R",             encoding = "UTF-8")  # Mesaj biçimlendirme
safe_source("R/helpers_mcp_tools.R",             encoding = "UTF-8")  # MCP araç tanımları
safe_source("R/helpers_chartlab.R",              encoding = "UTF-8")  # Grafik özellikleri
safe_source("R/helpers_image_gallery.R",         encoding = "UTF-8")  # Görsel galeri işlemleri
safe_source("R/helpers_preview.R",               encoding = "UTF-8")  # Dosya önizleme
safe_source("R/helpers_file_pipeline.R",         encoding = "UTF-8")  # Dosya işleme hattı
safe_source("R/helpers_files.R",                 encoding = "UTF-8")  # Dosya yardımcıları
safe_source("R/helpers_chat_runtime.R",          encoding = "UTF-8")  # Sohbet çalışma zamanı
safe_source("R/helpers_summarization_modes.R",   encoding = "UTF-8")  # Özetleme stratejileri
safe_source("R/helpers_summarization_prompts.R", encoding = "UTF-8")  # Özetleme şablonları
safe_source("R/helpers_followup_questions.R",    encoding = "UTF-8")  # Takip sorusu üretimi
safe_source("R/helpers_deep_analysis.R",         encoding = "UTF-8")  # Derin analiz yardımcıları
safe_source("R/helpers_sso.R",                   encoding = "UTF-8")  # SSO yardımcı fonksiyonları (JWT, token doğrulama)
safe_source("R/helpers_destek_database.R",       encoding = "UTF-8")  # Destek sayfası veritabanı işlemleri
safe_source("R/helpers_admin_analytics.R",       encoding = "UTF-8")  # Yönetici analitik yardımcıları
safe_source("R/helpers_ai_expert.R",             encoding = "UTF-8")  # AI Uzman yardımcıları

# ------------------------------------------------------------------------------
# GRUP 5: LLM (Büyük Dil Modeli) Entegrasyon Katmanı
# API yapılandırması ve yardımcı fonksiyonlara bağımlıdır.
# ------------------------------------------------------------------------------
safe_source("R/helpers_llm_tool_formatters.R", encoding = "UTF-8")  # Araç şeması biçimlendirme
safe_source("R/helpers_llm_api.R",             encoding = "UTF-8")  # LLM API istek oluşturma
safe_source("R/helpers_llm_worker.R",          encoding = "UTF-8")  # Arka plan LLM çağrıları

# ------------------------------------------------------------------------------
# GRUP 6: Shiny Modülleri (UI + Sunucu)
# Yardımcı fonksiyonlara bağımlıdır, server.R tarafından bağlanır.
# ------------------------------------------------------------------------------

# -- Sohbet ve İletişim Modülleri --
safe_source("R/module_chat_history.R",      encoding = "UTF-8")
safe_source("R/module_saved_chats.R",       encoding = "UTF-8")
safe_source("R/module_message_search.R",    encoding = "UTF-8")
safe_source("R/module_chat_search.R",       encoding = "UTF-8")
safe_source("R/module_followup_questions.R", encoding = "UTF-8")
safe_source("R/module_chat_actions.R",      encoding = "UTF-8")
safe_source("R/module_chat_export.R",       encoding = "UTF-8")
safe_source("R/module_feedback.R",          encoding = "UTF-8")

# -- Dosya ve Medya Modülleri --
safe_source("R/module_file_manager.R",      encoding = "UTF-8")
safe_source("R/module_file_preview.R",      encoding = "UTF-8")
safe_source("R/module_image_generation.R",  encoding = "UTF-8")
safe_source("R/module_image_gallery.R",     encoding = "UTF-8")
safe_source("R/module_summarization.R",     encoding = "UTF-8")

# -- Yapılandırma ve Ayar Modülleri --
safe_source("R/module_settings_kisisel.R",       encoding = "UTF-8")
safe_source("R/module_settings_yapilandirma.R",  encoding = "UTF-8")
safe_source("R/module_settings.R",               encoding = "UTF-8")
safe_source("R/module_api_key.R",                encoding = "UTF-8")

# -- AI Uzman, TTS/STT ve Karakter Modülleri --
safe_source("R/module_ai_processing.R",    encoding = "UTF-8")
safe_source("R/module_ai_expert.R",        encoding = "UTF-8")
safe_source("R/module_tts.R",              encoding = "UTF-8")
safe_source("R/module_stt.R",              encoding = "UTF-8")
safe_source("R/module_character_video.R",  encoding = "UTF-8")

# -- SSO ve Oturum Modülleri --
safe_source("R/module_sso.R",             encoding = "UTF-8")  # SSO kimlik doğrulama modülü
safe_source("R/module_session_timeout.R",  encoding = "UTF-8")
safe_source("R/module_performance.R",      encoding = "UTF-8")
safe_source("R/module_user_identity.R",    encoding = "UTF-8")
safe_source("R/module_startup_screen.R",   encoding = "UTF-8")
safe_source("R/module_quick_actions.R",    encoding = "UTF-8")

# -- Proje Analiz Modülleri --
safe_source("R/module_proje_kaynak_analizi.R", encoding = "UTF-8")

# -- Destek Sayfası Modülleri --
safe_source("R/module_destek_yardim.R",         encoding = "UTF-8")
safe_source("R/module_destek_hakkinda.R",       encoding = "UTF-8")
safe_source("R/module_destek_surum.R",          encoding = "UTF-8")
safe_source("R/module_destek_hata_bildir.R",    encoding = "UTF-8")
safe_source("R/module_destek_geri_bildirim.R",  encoding = "UTF-8")
safe_source("R/module_destek.R",                encoding = "UTF-8")

# -- Yönetici Paneli Modülleri --
safe_source("R/module_admin_genel_bakis.R",           encoding = "UTF-8")
safe_source("R/module_admin_kullanici_analizi.R",     encoding = "UTF-8")
safe_source("R/module_admin_yz_performans.R",         encoding = "UTF-8")
safe_source("R/module_admin_geri_bildirim_genel.R",   encoding = "UTF-8")
safe_source("R/module_admin_sohbet_kalitesi.R",       encoding = "UTF-8")
safe_source("R/module_admin_zaman_analizi.R",         encoding = "UTF-8")
safe_source("R/module_admin_gelismis_analizler.R",    encoding = "UTF-8")
safe_source("R/module_admin_analytics.R",             encoding = "UTF-8")
safe_source("R/module_admin_geri_bildirim.R",         encoding = "UTF-8")
safe_source("R/module_admin_hata_analizi.R",          encoding = "UTF-8")
safe_source("R/module_admin_yanit_analizi.R",         encoding = "UTF-8")

# ------------------------------------------------------------------------------
# GRUP 7: Sunucu Tarafı İşleyiciler ve Gözlemciler
# Modüllere ve yardımcılara bağımlıdır, server.R içinden çağrılır.
# ------------------------------------------------------------------------------

# -- Oturum ve Önbellek --
safe_source("R/server_session_cache.R",     encoding = "UTF-8")

# -- Sohbet İşleyicileri --
safe_source("R/server_outputs_chat.R",              encoding = "UTF-8")
safe_source("R/server_llm_response_handlers.R",     encoding = "UTF-8")
safe_source("R/server_handler_summarization.R",     encoding = "UTF-8")
safe_source("R/server_handler_image_generation.R",  encoding = "UTF-8")
safe_source("R/server_send_message.R",              encoding = "UTF-8")

# -- Medya İşleyicileri --
safe_source("R/server_tts_handlers.R",      encoding = "UTF-8")
safe_source("R/server_music_handlers.R",    encoding = "UTF-8")

# -- AI Uzman İşleyicileri --
safe_source("R/server_ai_expert_handlers.R", encoding = "UTF-8")

# -- Hoş Geldin Ekranı --
safe_source("welcome_screen.R",            encoding = "UTF-8")
safe_source("R/server_welcome_handlers.R",  encoding = "UTF-8")

# -- Gözlemciler (Observer'lar) --
safe_source("R/server_observers_settings.R",       encoding = "UTF-8")
safe_source("R/server_observers_storage.R",        encoding = "UTF-8")
safe_source("R/server_observers_files.R",          encoding = "UTF-8")
safe_source("R/server_observers_saved_chats.R",    encoding = "UTF-8")
safe_source("R/server_observers_image_gallery.R",  encoding = "UTF-8")
safe_source("R/server_observers_chat_ui.R",        encoding = "UTF-8")
safe_source("R/server_observers_navigation.R",     encoding = "UTF-8")
safe_source("R/server_observers_file_clicks.R",    encoding = "UTF-8")
safe_source("R/server_observers_startup.R",        encoding = "UTF-8")
safe_source("R/server_observers_chat_input.R",     encoding = "UTF-8")
safe_source("R/server_observers_misc.R",           encoding = "UTF-8")

# -- Çıktılar ve İndirmeler --
safe_source("R/server_outputs_downloads.R", encoding = "UTF-8")
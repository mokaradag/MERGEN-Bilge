# ==============================================================================
# Dosya Adı: global.R
# Açıklama:  Shiny uygulamasının giriş noktası ve küresel yapılandırma dosyası.
#            Kodlama ayarlarını yapar, veritabanı hedeflerini tanımlar ve
#            uygulamanın çalışması için gerekli tüm modül, yardımcı fonksiyon
#            ve yapılandırma dosyalarını (R/ klasörü altındaki) yükler.
# ==============================================================================

# Küresel olarak UTF-8 kodlamasını zorla
options(encoding = "UTF-8")

# Veritabanı istemci kodlamasını tek noktadan yönet (Windows + ODBC için)
# İhtiyaç halinde .Renviron içine DB_CLIENT_ENCODING=... yazılarak değiştirilebilir.
options(
  mergen.db.client_encoding = Sys.getenv("DB_CLIENT_ENCODING", "UTF-8"),
  mergen.db.name_encoding = Sys.getenv("DB_NAME_ENCODING", "UTF-8")
)

# Future paketinin RNG (rastgele sayı üretimi) hatalarını yoksay
options(future.rng.onMisuse = "ignore")

# Yerel ayarları İngilizce UTF-8 olarak ayarlamayı dene (hataları gizle)
try(suppressWarnings(Sys.setlocale("LC_ALL", "en_US.UTF-8")), silent = TRUE)

# Sadece bu yerel ayar çağrısı için uyarıları bastır (Türkçe karakter desteği)
try(suppressWarnings(Sys.setlocale("LC_CTYPE", "Turkish_Turkey.UTF-8")), silent = TRUE)

# ------------------------------------------------------------------------------
# GÜVENLİ KAYNAK YÜKLEME FONKSİYONU (SAFE SOURCE)
# ------------------------------------------------------------------------------
# Önce mevcut ve çalışan source() yolunu dener.
# Yalnızca kaynak yükleme encoding/parse hatası verirse kontrollü yedek
# çözüm devreye girer ve dosya farklı kodlamalarla okunup parse edilmeye çalışılır.
# ------------------------------------------------------------------------------
safe_source <- function(file, encoding = "UTF-8", envir = globalenv()) {
  tryCatch({
    source(file, encoding = encoding, local = envir)
    invisible(NULL)
  }, error = function(e) {
    hata_metni <- conditionMessage(e)

    encoding_hatasi_mi <- grepl(
      "INCOMPLETE_STRING|invalid multibyte|unexpected input|EOF within quoted string|nul character|invalid input",
      hata_metni,
      ignore.case = TRUE
    )

    if (!isTRUE(encoding_hatasi_mi)) {
      stop(e)
    }

    raw_size <- file.info(file)$size
    if (is.na(raw_size) || raw_size <= 0) {
      stop(e)
    }

    raw_content <- readBin(file, what = "raw", n = raw_size)

    denenecek_kodlamalar <- c("UTF-8", "WINDOWS-1254", "latin1")
    son_hata <- NULL

    for (kodlama in denenecek_kodlamalar) {
      metin <- tryCatch(
        iconv(list(raw_content), from = kodlama, to = "UTF-8")[[1]],
        error = function(err) NA_character_
      )

      if (is.na(metin) || !nzchar(metin)) next

      metin <- sub("^\ufeff", "", metin, perl = TRUE)

      exprs <- tryCatch(
        parse(text = metin, keep.source = FALSE, encoding = "UTF-8"),
        error = function(err) {
          son_hata <<- err
          NULL
        }
      )

      if (is.null(exprs)) next

      eval(exprs, envir = envir)
      return(invisible(NULL))
    }

    if (!is.null(son_hata)) {
      stop(son_hata)
    }

    stop(e)
  })
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
safe_source("R/config_claude_code.R",      encoding = "UTF-8")  # Claude Code yapılandırması

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
safe_source("R/helpers_claude_code.R",           encoding = "UTF-8")  # Claude Code CLI yardımcıları
safe_source("R/helpers_claude_code_streaming.R", encoding = "UTF-8")  # Claude Code canlı akış desteği
safe_source("R/helpers_claude_code_formatters.R", encoding = "UTF-8") # Claude Code HTML biçimlendiriciler

# ------------------------------------------------------------------------------
# GRUP 5: LLM (Büyük Dil Modeli) Entegrasyon Katmanı
# API yapılandırması ve yardımcı fonksiyonlara bağımlıdır.
# ------------------------------------------------------------------------------
safe_source("R/helpers_llm_tool_formatters.R",      encoding = "UTF-8")  # Araç şeması biçimlendirme
safe_source("R/helpers_llm_response_postprocess.R", encoding = "UTF-8")  # LLM yanıt son işleme ve Kaynakça yardımcıları
safe_source("R/helpers_llm_api.R",                  encoding = "UTF-8")  # LLM API istek oluşturma
safe_source("R/helpers_llm_sse.R",                  encoding = "UTF-8")  # Gerçek SSE akışı yardımcıları
safe_source("R/helpers_llm_worker.R",               encoding = "UTF-8")  # Arka plan LLM çağrıları

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
safe_source("R/module_tts_visualizer.R",   encoding = "UTF-8")
safe_source("R/module_stt.R",              encoding = "UTF-8")
safe_source("R/module_character_video.R",  encoding = "UTF-8")

# -- SSO ve Oturum Modülleri --
safe_source("R/module_sso.R",             encoding = "UTF-8")
safe_source("R/module_session_timeout.R",  encoding = "UTF-8")
safe_source("R/module_performance.R",      encoding = "UTF-8")
safe_source("R/module_user_identity.R",    encoding = "UTF-8")
safe_source("R/module_startup_screen.R",   encoding = "UTF-8")
safe_source("R/module_quick_actions.R",    encoding = "UTF-8")
safe_source("R/module_claude_code_klasor.R", encoding = "UTF-8")
safe_source("R/module_claude_code_akis.R",   encoding = "UTF-8")
safe_source("R/module_claude_code.R",        encoding = "UTF-8")

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
safe_source("R/module_health.R",                      encoding = "UTF-8")
safe_source("R/module_chartlab.R",                    encoding = "UTF-8")

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
safe_source("R/server_handler_true_streaming.R",    encoding = "UTF-8")
safe_source("R/server_send_message.R",              encoding = "UTF-8")

# -- Medya İşleyicileri --
safe_source("R/server_tts_handlers.R",      encoding = "UTF-8")
safe_source("R/server_music_handlers.R",    encoding = "UTF-8")

# -- AI Uzman İşleyicileri --
safe_source("R/server_ai_expert_handlers.R", encoding = "UTF-8")

# -- Hoş Geldin Ekranı --
safe_source("welcome_screen.R",            encoding = "UTF-8")
safe_source("R/welcome_screen_modern.R",   encoding = "UTF-8")
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

# Hızlı SSE işçilerini önceden ısıt
if (exists(".mergen_future_cluster", envir = .GlobalEnv, inherits = FALSE)) {
  try({
    .mergen_future_cluster <- get(".mergen_future_cluster", envir = .GlobalEnv)

    parallel::clusterEvalQ(.mergen_future_cluster, {
      options(encoding = "UTF-8")
      library(curl)
      library(jsonlite)
      NULL
    })

    parallel::clusterExport(
      .mergen_future_cluster,
      varlist = c(
        "%||%",
        "api_config",
        "log_info",
        "log_warn",
        "resolve_local_llm_credentials",
        "extract_llm_content_and_sources",
        "normalize_llm_scalar_content",
        "strip_planner_text",
        "decode_utf8_raw_chunk",
        "parse_llm_sse_event",
        "extract_llm_delta_text",
        "extract_llm_event_sources",
        "append_stream_delta_line",
        "call_local_llm_sse_worker"
      ),
      envir = globalenv()
    )

    log_info("[CHAT PERF] SSE işçileri önceden ısıtıldı")
  }, silent = TRUE)
}
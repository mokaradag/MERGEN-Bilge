# ==============================================================================
# Dosya Adı: global.R
# Açıklama:  Shiny uygulamasının giriş noktası ve küresel yapılandırma dosyası.
#            Kodlama ayarlarını yapar, veritabanı hedeflerini tanımlar ve
#            uygulamanın çalışması için gerekli modül, yardımcı fonksiyon ve
#            yapılandırma dosyalarını açık manifest üzerinden yükler.
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

# ------------------------------------------------------------------------------
# ÜRETİM DOSYA YÜKLEME SINIRI
# ------------------------------------------------------------------------------
# Büyük dosyalar Windows VM üzerinde Shiny upload, önizleme, özetleme ve dosya
# indeksleme hattını ağırlaştırabilir. Varsayılan sınır 25 MB'tır.
# .Renviron içinde MERGEN_UPLOAD_MAX_MB=... ile kontrollü şekilde değiştirilebilir.
# shiny.maxRequestSize, Shiny'nin HTTP upload seviyesinde erken reddetmesini sağlar.
# mergen.upload_max_mb ise uygulama içi validate_uploaded_file() kararlarında
# kullanılan merkezi sınırdır.
# ------------------------------------------------------------------------------
mergen_upload_max_mb <- suppressWarnings(
  as.integer(Sys.getenv("MERGEN_UPLOAD_MAX_MB", "25"))
)

if (is.na(mergen_upload_max_mb) || mergen_upload_max_mb <= 0L) {
  mergen_upload_max_mb <- 25L
}

# Üretim politikası: varsayılan ve üst sınır 25 MB.
# Yanlışlıkla .Renviron içinde MERGEN_UPLOAD_MAX_MB=30/50/100 kalsa bile
# bu uygulama profili 25 MB üstüne çıkmaz.
mergen_upload_max_mb <- min(mergen_upload_max_mb, 25L)

options(
  mergen.upload_max_mb = mergen_upload_max_mb,
  shiny.maxRequestSize = mergen_upload_max_mb * 1024^2
)

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
if (!exists("safe_source", mode = "function")) {
  source("R/utils_safe_source.R", encoding = "UTF-8", local = globalenv())
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

# ------------------------------------------------------------------------------
# GÜVENLİ / TEKRARLANABİLİR RESOURCE PATH KAYDI
# ------------------------------------------------------------------------------
# global.R Ctrl+Enter, test, smoke boot veya Shiny process yenilemelerinde birden
# fazla source edilebilir. addResourcePath aynı prefix için uyarı üretebildiğinden
# opsiyonel statik klasör kayıtlarını idempotent hale getiriyoruz.
# ------------------------------------------------------------------------------
register_global_resource_path <- function(prefix, directory, create = FALSE) {
  if (isTRUE(create) && !dir.exists(directory)) {
    dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  }

  if (!dir.exists(directory)) {
    return(invisible(FALSE))
  }

  withCallingHandlers(
    {
      shiny::addResourcePath(prefix, directory)
    },
    warning = function(w) {
      if (grepl("already", conditionMessage(w), ignore.case = TRUE)) {
        invokeRestart("muffleWarning")
      }
    }
  )

  invisible(TRUE)
}

# Destek ek dosyalarını sunmak için kaynak yolu tanımla
destek_uploads_dir <- file.path(getwd(), "destek_uploads")
register_global_resource_path("destek_uploads", destek_uploads_dir)

# Bilge Yolaç tarafından üretilen dosyaları yerel indirme bağlantısı olarak sun
bilge_yolac_downloads_dir <- file.path(getwd(), "bilge_yolac_downloads")
options(mergen.claude_code_download_root = bilge_yolac_downloads_dir)
register_global_resource_path(
  "bilge_yolac_downloads",
  bilge_yolac_downloads_dir,
  create = TRUE
)

# ------------------------------------------------------------------------------
# KAYNAK MANİFESTİ DOĞRULAMA VE YÜKLEME
# ------------------------------------------------------------------------------
# Manifest doğrulama yardımcıları bootstrap dosyasında, çalışma zamanı kaynak
# listesi ise config_source_manifest.R içinde tutulur. Böylece global.R yüksek
# seviyeli boot akışını korur; kaynak sırası yine açık ve gözden geçirilebilirdir.
# ------------------------------------------------------------------------------
if (!exists("source_manifest_validate", mode = "function") ||
    !exists("source_manifest_required_order", inherits = FALSE)) {
  safe_source("R/bootstrap_source_manifest.R", encoding = "UTF-8")
}

source_manifest_validate(
  order_rules = list(),
  paths = "R/config_source_manifest.R"
)

safe_source("R/config_source_manifest.R", encoding = "UTF-8")

source_manifest_validate_config_objects()
source_manifest_current_paths <- source_manifest_get_runtime_paths()

source_manifest_validate(
  order_rules = source_manifest_required_order,
  paths = source_manifest_current_paths
)

source_manifest_load(source_manifest_group_1_paths)

tryCatch({
  # Test/bootstrap ortamında paralel işçi başlatılmaz; sequential plana düşülür.
  # Böylece testthat oturumu gereksiz yere cluster ayağa kaldırmaz.
  if (isTRUE(as.logical(Sys.getenv("MERGEN_DISABLE_FUTURES", "false")))) {
    log_info("MERGEN_DISABLE_FUTURES aktif - future cluster atlandı, sequential plan kullanılıyor.")
    future::plan(future::sequential)
  } else {
    init_future_cluster()
  }
}, error = function(e) {
  log_error("Future cluster başlatılamadı: {conditionMessage(e)}")
  future::plan(future::sequential)
})

# ------------------------------------------------------------------------------
# GRACEFUL SHUTDOWN: Shiny süreci kapanırken future cluster'ı temiz indir.
# shiny::onStop mevcut oturum-dışı teardown sırasında tetiklenir. Üretimde
# shiny-server bazen process'i SIGTERM ile sonlandırır; bu hook kayıtlı olsa
# bile her zaman tetiklenmez, ancak tetiklendiğinde paralel worker'ların
# arkada kalmasını engeller. .cleanup_once bayrağı sayesinde global.R yeniden
# source edildiğinde (Ctrl+Enter) çift kayıt olmaz.
# ------------------------------------------------------------------------------
if (requireNamespace("shiny", quietly = TRUE) &&
    !isTRUE(getOption("mergen.onstop_registered", FALSE)) &&
    !isTRUE(as.logical(Sys.getenv("MERGEN_DISABLE_FUTURES", "false")))) {

  shiny::onStop(function() {
    try({
      log_info("onStop tetiklendi; future cluster kapatılıyor.")
      future::plan(future::sequential)
    }, silent = TRUE)
  })

  options(mergen.onstop_registered = TRUE)
}

source_manifest_load(source_manifest_after_future_paths)
# ==============================================================================
# R/config_packages.R
# Uygulama genelinde kullanılan tüm paketlerin yüklenmesi.
# global.R tarafından en başta source() ile çağrılır.
#
# Bu dosya, insan-okunur uygulama bağımlılık manifestidir (required_packages) ve
# açılıştaki eksik-paket doğrulamasını yapar. KESİN sürümler renv.lock içinde
# sabitlenir (Windows VM R 4.6.0'da üretilir). Ayrıntı: docs/dependency-locking.md
# ==============================================================================

# TEST-ONLY BAĞIMLILIKLAR BURADA YER ALMAZ.
#
# `required_packages` açılışta DOĞRULANIR ve eksik bir paket uygulamayı
# başlatmaz. `RSQLite` yalnızca çevrimdışı testlerde (gerçek SQLite ile DB
# havuzu / Ortak Oturum davranış testleri) ve soak betiklerinde kullanılır;
# çalışma zamanı hiçbir yolu ona dokunmaz. Listeye eklemek, üretim kurulumunda
# yokluğunda uygulamayı gereksiz yere durdururdu. CI iş akışı onu ayrıca kurar.
required_packages <- c(
  "arrow", "base64enc", "cellranger", "cli", "commonmark", "curl",
  "data.table", "DBI", "dplyr", "DT", "duckdb", "fastmatch",
  "future", "glue", "highcharter", "htmltools", "httr", "jsonlite", "later",
  "logger", "lubridate", "markdown", "odbc", "openssl", "pdftools", "pool",
  "promises", "purrr", "readr", "readxl", "shiny", "shinyBS",
  "shinycssloaders", "shinydashboard", "shinyjs", "shinyWidgets",
  "stringdist", "stringi", "stringr", "tibble", "tidyr", "urltools",
  "writexl", "xml2", "av"
)

validate_required_packages <- function(
  packages = required_packages,
  namespace_checker = function(pkg) requireNamespace(pkg, quietly = TRUE)
) {
  packages[!vapply(packages, namespace_checker, logical(1))]
}

attach_required_packages <- function(packages = required_packages) {
  invisible(lapply(packages, function(pkg) {
    library(pkg, character.only = TRUE)
  }))
}

# Faz 6 (§5.10): PK future işçisi bu manifesti KENDİ sürecinde source eder.
# Orada UI/medya/analitik yığınını attach etmek her işçide ayrı bir native heap
# açar (arrow/duckdb/av/pdftools bellek-kısıtlı bir dağıtımı OOM'a taşıyabilir)
# ve PK boru hattı bu paketlerin HİÇBİRİNE girmez. Namespace'ler yine kurulu
# kalır: bir yerde `pkg::fn` kullanılıyorsa çalışmaya devam eder.
mergen_worker_skip_packages <- function() {
  c("arrow", "duckdb", "av", "pdftools",
    "shinyBS", "shinycssloaders", "shinydashboard", "shinyjs", "shinyWidgets")
}

mergen_worker_bootstrap_mode <- function() {
  isTRUE(tolower(trimws(Sys.getenv("MERGEN_PK_WORKER_BOOTSTRAP", unset = ""))) %in%
           c("1", "true", "t", "yes", "on"))
}

# DOĞRULAMA LİSTESİ DE İŞÇİDE FİLTRELENİR.
#
# `validate_required_packages()` her girdi için `requireNamespace()` çağırır ve
# bu, paket NAMESPACE'ini (ve native DLL'lerini) YÜKLER. Yalnızca `library()`
# adımını atlamak bu yüzden yetersizdi: arrow/duckdb/av/pdftools işçi belleğini
# tam da bu daldan kaçınılmak istenen şekilde ZATEN ödemiş oluyordu.
#
# Atlanan paketler işçide DOĞRULANMAZ da: PK boru hattı hiçbirine girmez ve
# `pkg::fn` kullanımları gerektiğinde namespace'i kendisi yükler.
mergen_startup_validation_packages <- function() {
  if (isTRUE(mergen_worker_bootstrap_mode())) {
    return(setdiff(required_packages, mergen_worker_skip_packages()))
  }
  required_packages
}

missing_packages <- validate_required_packages(mergen_startup_validation_packages())

if (length(missing_packages) > 0) {
  stop(
    sprintf(
      paste(
        "Eksik R paketleri: %s",
        "Kurulum için şu komutu çalıştırın:",
        "install.packages(c(%s), dependencies = TRUE)",
        sep = "\n"
      ),
      paste(missing_packages, collapse = ", "),
      paste(sprintf('\"%s\"', missing_packages), collapse = ", ")
    )
  )
}

if (isTRUE(mergen_worker_bootstrap_mode())) {
  attach_required_packages(setdiff(required_packages, mergen_worker_skip_packages()))
} else {
  attach_required_packages()
}
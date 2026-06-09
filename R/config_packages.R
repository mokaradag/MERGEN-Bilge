# ==============================================================================
# R/config_packages.R
# Uygulama genelinde kullanılan tüm paketlerin yüklenmesi.
# global.R tarafından en başta source() ile çağrılır.
#
# Bu dosya, insan-okunur uygulama bağımlılık manifestidir (required_packages) ve
# açılıştaki eksik-paket doğrulamasını yapar. KESİN sürümler renv.lock içinde
# sabitlenir (Windows VM R 4.6.0'da üretilir). Ayrıntı: docs/dependency-locking.md
# ==============================================================================

required_packages <- c(
  "arrow", "base64enc", "cellranger", "cli", "commonmark", "curl",
  "data.table", "DBI", "dplyr", "DT", "duckdb", "fastmatch",
  "future", "glue", "htmltools", "httr", "jsonlite", "later",
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

missing_packages <- validate_required_packages()

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

attach_required_packages()
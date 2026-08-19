# ==============================================================================
# Dosya Yolu: tools/pk/helpers_meta_generator_db.R
# Aciklama: Faz 3b metadata ureticisi DB enjeksiyonlari icin ince sarmalayici.
#
# Uygulama havuzu uzun omurlu RStudio oturumunda onceki bir DSN/fiziksel
# baglantiyi tasiyabilir. Metadata ureticisi denetlenebilir ve tekrarlanabilir
# olmak zorundadir; bu nedenle uygulama/global pool'unu ASLA devralmaz.
#
# Asil DB/describe/sample uygulamasi helpers_meta_generator_db_impl.R icindedir.
# Bu dosya yalnizca iki dar uyumluluk duzeltmesini uygular:
#   1) metadata kosusu icin yapilandirilmis DSN'den dedicated ODBC baglantisi,
#   2) statik descriptor'a verilen kopyadan, read-only kapi zaten onaylamissa,
#      yalnizca tam SET NOCOUNT ON; onekinin kaldirilmasi.
#
# Uretim SQL dosyasi DEGISTIRILMEZ. Runtime SQL yurutmesi DEGISTIRILMEZ.
# Read-only ratchet'i DEGISTIRILMEZ veya gevsetilmez.
# ==============================================================================

.pkgd_wrapper_file <- tryCatch(
  normalizePath(sys.frame(1)$ofile, winslash = "/", mustWork = TRUE),
  error = function(e) ""
)
.pkgd_wrapper_dir <- if (nzchar(.pkgd_wrapper_file)) {
  dirname(.pkgd_wrapper_file)
} else {
  file.path(getwd(), "tools", "pk")
}
.pkgd_impl_file <- file.path(.pkgd_wrapper_dir, "helpers_meta_generator_db_impl.R")
if (!file.exists(.pkgd_impl_file)) {
  stop("[PK_META_GEN] helpers_meta_generator_db_impl.R bulunamadi.", call. = FALSE)
}
source(.pkgd_impl_file, encoding = "UTF-8", local = FALSE)
rm(.pkgd_wrapper_file, .pkgd_wrapper_dir, .pkgd_impl_file)

# Eski davranis yalnizca geriye donuk uyumluluk/yedek release icin saklanir.
.pkgd_release_application_handle <- pkg_default_release_fn
.pkgd_describe_original <- pkg_default_describe_fn

# Leading yorumlar + tam SET NOCOUNT ON; disinda hicbir session ayari tuketilmez.
.PKGD_DESCRIPTOR_NOCOUNT_PREFIX <- paste0(
  "(?is)^\\s*(?:(?:--[^\\r\\n]*(?:\\r\\n|\\n|\\r|$))|(?:/\\*.*?\\*/))\\s*",
  "SET\\s+NOCOUNT\\s+ON\\s*;\\s*"
)

.pkgd_descriptor_sql <- function(sql) {
  metin <- tryCatch(as.character(sql)[1], error = function(e) "")
  if (is.na(metin) || !nzchar(metin)) return(metin)

  # Descriptor normalizasyonu read-only kapinin YERINE GECMEZ. Yalnizca kapi
  # tum batch'i zaten kabul ettiyse zararsiz NOCOUNT oneki schema sondasindan
  # cikarilir. Boylece SET/EXEC/yazma batch'leri burada asla aklanmaz.
  kapi <- tryCatch(pk_sql_classify_readonly(metin), error = function(e) NULL)
  if (!is.list(kapi) || !isTRUE(kapi$allowed)) return(metin)

  if (!grepl(.PKGD_DESCRIPTOR_NOCOUNT_PREFIX, metin, perl = TRUE, useBytes = TRUE)) {
    return(metin)
  }
  sub(.PKGD_DESCRIPTOR_NOCOUNT_PREFIX, "", metin, perl = TRUE, useBytes = TRUE)
}

# Metadata ureticisi uygulama/global pool'unu kullanmaz. Pool uzun omurlu bir
# RStudio oturumunda farkli bir onceki DSN'e ait fiziksel baglantiyi koruyabilir;
# bu durumda descriptor, gercek query_library nesnelerini topluca
# `object_missing` olarak gorur. Her hedef icin inventory katmani zaten TEK
# baglantiyi cache'ler; dedicated baglanti acmak sorgu basina reconnect demek
# degildir.
pkg_default_connect_fn <- function(target = "primary", timeout_sec = NULL) {
  dogrulama <- pkg_meta_validate_db_target(target)
  if (!isTRUE(dogrulama$ok)) {
    stop(sprintf("[PK_META_GEN] %s", dogrulama$detail), call. = FALSE)
  }

  dsn_degiskeni <- dogrulama$env_var
  dsn <- trimws(Sys.getenv(dsn_degiskeni, unset = ""))
  if (!nzchar(dsn)) {
    stop(sprintf(
      "[PK_META_GEN] '%s' hedefi icin %s tanimli degil; metadata baglantisi acilmadi.",
      dogrulama$target, dsn_degiskeni
    ), call. = FALSE)
  }

  if (!requireNamespace("DBI", quietly = TRUE) ||
      !requireNamespace("odbc", quietly = TRUE)) {
    stop("[PK_META_GEN] Dedicated metadata baglantisi icin DBI ve odbc gerekli.",
         call. = FALSE)
  }

  istemci_kodlama <- get0(
    ".DEFAULT_DB_CLIENT_ENCODING", inherits = TRUE, ifnotfound = "UTF-8"
  )
  ad_kodlama <- get0(
    ".DEFAULT_DB_NAME_ENCODING", inherits = TRUE, ifnotfound = "UTF-8"
  )

  baglanti_args <- list(
    odbc::odbc(),
    dsn = dsn,
    encoding = istemci_kodlama,
    name_encoding = ad_kodlama,
    interruptible = TRUE
  )

  sinir <- suppressWarnings(as.numeric(timeout_sec)[1])
  if (length(sinir) == 1L && !is.na(sinir) && is.finite(sinir) && sinir > 0) {
    # ODBC login timeout saniye cozunurlugundedir; 0 sinirsiz demektir.
    baglanti_args$timeout <- max(1L, as.integer(floor(sinir)))
  }

  conn <- .pkgd_bounded(
    function() do.call(DBI::dbConnect, baglanti_args),
    timeout_sec
  )

  list(
    conn = conn,
    pooled = FALSE,
    checked_out = FALSE,
    pool = NULL,
    target = dogrulama$target,
    pkg_meta_dedicated = TRUE
  )
}

pkg_default_release_fn <- function(handle, timeout_sec = NULL) {
  if (is.null(handle)) return(invisible(NULL))

  if (!is.list(handle) || !isTRUE(handle$pkg_meta_dedicated)) {
    return(.pkgd_release_application_handle(handle, timeout_sec = timeout_sec))
  }

  conn <- handle$conn
  if (is.null(conn)) return(invisible(NULL))

  sinir <- suppressWarnings(as.numeric(timeout_sec)[1])
  if (length(sinir) != 1L || is.na(sinir) || !is.finite(sinir) || sinir <= 0) {
    sinir <- .PKGD_CLEANUP_MIN_SEC
  }

  invisible(tryCatch(
    .pkgd_bounded(function() DBI::dbDisconnect(conn), sinir),
    error = function(e) NULL
  ))
}

# SQL Server statik descriptor'u NOCOUNT session direktifini sema icin
# gerektirmez. Descriptor kopyasi dar bicimde normalize edilir; sorgunun kendisi
# ve runtime execution batch'i aynen kalir.
pkg_default_describe_fn <- function(conn, sql, timeout_sec = NULL) {
  .pkgd_describe_original(
    conn,
    .pkgd_descriptor_sql(sql),
    timeout_sec = timeout_sec
  )
}

# ==============================================================================
# Dosya Yolu: tools/pk/helpers_meta_generator_config.R
# Aciklama: Faz 3b metadata ureticisi -- yapilandirma cozumleme (SAF).
#
# BU DOSYA CALISMA ZAMANI KODU DEGILDIR. Kaynak manifestine EKLENMEZ; yalnizca
# operatorun VM'de elle calistirdigi `tools/pk/generate_query_meta.R` tarafindan
# source edilir.
#
# SAFTIR: DB'ye baglanmaz, SQL calistirmaz, dosya yazmaz, Shiny/reaktif okumaz.
# Yalnizca ortam degiskenlerini okur ve dogrulanmis bir yapilandirma listesi
# dondurur; bu sayede tamami cevrimdisi test edilebilir.
# ==============================================================================

# `%||%` calisma zamaninda R/utils_common.R icinde tanimlidir. Bu dosya izole
# testlerde ve operator oturumunda tek basina source edilebildigi icin yalnizca
# YOKSA tanimlanir; mevcut tanim ASLA ezilmez.
if (!exists("%||%", mode = "function", inherits = TRUE)) {
  `%||%` <- function(a, b) if (is.null(a)) b else a
}

# Yerelden BAGIMSIZ ASCII kucuk harf. Kip adi bir PROTOKOL BELIRTECIDIR:
# Turkce yerelde `tolower("DESCRIBE")` sorunsuzdur ama `tolower("SAMPLE_I")`
# gibi girdilerde noktasiz i uretebilir. Depo kurali geregi protokol
# belirtecleri asla yerele bagli katlanmaz.
.pkg_ascii_lower <- function(x) {
  if (exists("pk_ascii_lower", mode = "function", inherits = TRUE)) return(pk_ascii_lower(x))
  chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz", as.character(x))
}

# Master plan §9: gecerli kipler ve BELGELENMIS varsayilan.
PKG_META_MODES <- c("describe", "sample")
PKG_META_DEFAULT_MODE <- "sample"

# Uretici YALNIZCA bu dosyaya yazar. Izlenen hicbir dosyaya ve operatorun
# alias dosyasina ASLA dokunmaz.
PKG_META_OUTPUT_FILE <- "R/library_query_meta_local.R"

# Uretici tarafindan ASLA yazilmayacak dosyalar. Bu liste bir yorum degil,
# calisma zamaninda uygulanan bir kapidir (bkz. helpers_meta_generator_render.R).
PKG_META_FORBIDDEN_TARGETS <- c(
  "R/library_query_aliases_local.R",
  "R/library_query_meta.R",
  "R/library_query_meta_auto.R",
  "R/library_queries.R"
)

PKG_META_ARTIFACT_DIR <- "artifacts/pk-meta"

.pkg_env_text <- function(name, default = "") {
  ham <- Sys.getenv(name, unset = "")
  if (!nzchar(trimws(ham))) return(default)
  trimws(ham)
}

.pkg_env_whole <- function(name, default, min = 1L, max = .Machine$integer.max) {
  ham <- .pkg_env_text(name, "")
  if (!nzchar(ham)) return(as.integer(default))

  sayi <- suppressWarnings(as.numeric(ham))
  if (length(sayi) != 1L || is.na(sayi) || !is.finite(sayi) || sayi != trunc(sayi)) {
    stop(sprintf(
      "[PK_META_GEN] %s tam sayi olmalidir (alinan: '%s').", name, ham
    ), call. = FALSE)
  }
  if (sayi < min || sayi > max) {
    stop(sprintf(
      "[PK_META_GEN] %s %s..%s araliginda olmalidir (alinan: %s).",
      name, format(min), format(max), format(sayi)
    ), call. = FALSE)
  }
  as.integer(sayi)
}

.pkg_env_flag <- function(name, default = FALSE) {
  ham <- .pkg_ascii_lower(.pkg_env_text(name, ""))
  if (!nzchar(ham)) return(isTRUE(default))
  if (ham %in% c("true", "t", "1", "yes", "on", "evet", "acik")) return(TRUE)
  if (ham %in% c("false", "f", "0", "no", "off", "hayir", "kapali")) return(FALSE)
  stop(sprintf(
    "[PK_META_GEN] %s TRUE/FALSE olmalidir (alinan: '%s').", name, ham
  ), call. = FALSE)
}

#' Uretici kipini coz
#'
#' Gecersiz bir kip SESSIZCE varsayilana DUSMEZ; acikca hata verir. Yanlis
#' yazilmis bir kip ile beklenmeyen bir kipte calismak (ornegin `describe`
#' yazmak isterken `sample` calistirmak) uretim veritabaninda gereksiz yuk
#' demektir.
#'
#' @return list(mode, defaulted)
pkg_meta_resolve_mode <- function(raw = NULL) {
  ham <- if (is.null(raw)) Sys.getenv("MERGEN_PK_META_MODE", unset = "") else raw
  ham_metin <- if (length(ham) == 1L && !is.na(ham)) trimws(as.character(ham)) else ""

  if (!nzchar(ham_metin)) {
    return(list(mode = PKG_META_DEFAULT_MODE, defaulted = TRUE))
  }

  kip <- .pkg_ascii_lower(ham_metin)
  if (!(kip %in% PKG_META_MODES)) {
    stop(sprintf(
      paste0(
        "[PK_META_GEN] Gecersiz MERGEN_PK_META_MODE: '%s'. ",
        "Izinli kipler: %s."
      ),
      ham_metin, paste(PKG_META_MODES, collapse = ", ")
    ), call. = FALSE)
  }

  list(mode = kip, defaulted = FALSE)
}

#' Tum uretici yapilandirmasini coz
#'
#' Gizli deger OKUNMAZ ve RAPORLANMAZ: burada yalnizca kip, satir sinirlari ve
#' zaman asimi gibi calisma parametreleri vardir. DSN/kimlik bilgisi
#' `get_connection()` icinde kalir ve bu listeye ASLA girmez.
pkg_meta_resolve_config <- function(repo_root = ".", now = Sys.time()) {
  kip <- pkg_meta_resolve_mode()

  zaman_damgasi <- format(as.POSIXct(now), "%Y%m%d-%H%M%S")

  list(
    mode = kip$mode,
    mode_defaulted = kip$defaulted,
    repo_root = repo_root,
    output_path = file.path(repo_root, PKG_META_OUTPUT_FILE),
    output_rel = PKG_META_OUTPUT_FILE,
    state_path = file.path(repo_root, PKG_META_ARTIFACT_DIR, "generator-state.json"),
    artifact_dir = file.path(repo_root, PKG_META_ARTIFACT_DIR, zaman_damgasi),
    artifact_rel = file.path(PKG_META_ARTIFACT_DIR, zaman_damgasi),
    timestamp = zaman_damgasi,
    # `sample` kipinde sorgu basina getirilecek EN FAZLA satir. Bu bir kanit
    # siniri degildir: 500 satir 501 satirlik sonucu 5 milyondan AYIRT EDEMEZ.
    sample_rows = .pkg_env_whole("MERGEN_PK_META_SAMPLE_ROWS", 500L, min = 1L),
    # Yuksek kardinalite KANITI icin gereken farkli deger sayisi (tek yonlu:
    # bu esigin USTUNE cikmak TRUE kanitlar; altinda kalmak hicbir sey kanitlamaz).
    high_cardinality_threshold = .pkg_env_whole(
      "MERGEN_PK_META_HIGH_CARD_MIN", 50L, min = 2L
    ),
    sql_timeout_sec = .pkg_env_whole("MERGEN_PK_META_SQL_TIMEOUT_SEC", 120L, min = 1L),
    max_result_mb = .pkg_env_whole("MERGEN_PK_META_MAX_RESULT_MB", 64L, min = 1L),
    # Kesintiye ugrayan bir kosuyu kaldigi yerden surdurur. Operator temiz bir
    # kosu istediginde FALSE yapar.
    resume = .pkg_env_flag("MERGEN_PK_META_RESUME", TRUE)
  )
}

#' Yapilandirmayi gizli-guvenli ozetle
#'
#' Ciktida DSN, kimlik bilgisi, uc nokta veya jeton BULUNMAZ.
pkg_meta_config_summary <- function(config) {
  list(
    mode = config$mode,
    mode_defaulted = isTRUE(config$mode_defaulted),
    sample_rows = config$sample_rows,
    high_cardinality_threshold = config$high_cardinality_threshold,
    sql_timeout_sec = config$sql_timeout_sec,
    max_result_mb = config$max_result_mb,
    resume = isTRUE(config$resume),
    output_rel = config$output_rel,
    artifact_rel = config$artifact_rel
  )
}

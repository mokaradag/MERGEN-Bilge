# R/server_session_cache.R
# Dosya Yolu: R/server_session_cache.R
# Açıklama: Oturum önbellek (cache) ve MCP kayıt defteri yönetimi için fonksiyonlar.
# Bu modül oturum bazlı dosya önbellekleme ve MCP entegrasyonu işlemlerini yönetir.
 
#' Oturum Önbellek Sistemini Başlat
#' @description Oturum önbellek ve MCP kayıt defteri fonksiyonlarını kurar
#' @param session Shiny session nesnesi
#' @return Önbellek yönetim fonksiyonlarını içeren liste
sessionCacheInit <- function(session) {
 
  # MCP tarafından kaydedilen dosya yolunu tutan reaktif değer
  mcp_saved_path <- shiny::reactiveVal(NULL)
 
  # Oturum önbellek kök dizini oluştur
  cache_root <- getOption(
    "mergen.session_cache_dir",
    normalizePath(file.path(tempdir(), "mergen_session_cache"), winslash = "/", mustWork = FALSE)
  )
  dir.create(cache_root, recursive = TRUE, showWarnings = FALSE)
  cache_root <- safe_windows_short_path(cache_root, must_exist = dir.exists(cache_root))
 
  # Kullanıcıya özel önbellek dizini (setup_user_session ile ayarlanır)
  cache_env <- new.env(parent = emptyenv())
  cache_env$cache_dir <- NULL
 
  # Oturum belirtecini güvenli formata dönüştür
  cache_session_token <- function(tok) {
    if (is.null(tok) || !nzchar(tok)) {
      return(sprintf("sess_%s", format(Sys.time(), "%Y%m%d%H%M%S")))
    }
    gsub("[^A-Za-z0-9_-]", "_", tok)
  }
 
  # Kullanıcı oturumunu yapılandır ve önbellek dizinini oluştur
  setup_user_session <- function(user_id) {
    cache_env$cache_dir <- file.path(
      cache_root,
      paste0("user_", user_id),
      cache_session_token(session$token %||% "anon")
    )
    dir.create(cache_env$cache_dir, recursive = TRUE, showWarnings = FALSE)
 
    # Oturum sonlandığında önbellek dizinini temizle
    session$onSessionEnded(function() {
      try(unlink(cache_env$cache_dir, recursive = TRUE, force = TRUE), silent = TRUE)
    })
 
    cache_env$cache_dir
  }
 
  # MCP dosyasını yerel önbelleğe kopyala
  cache_mcp_file_locally <- function(src_path) {
    src_path_chr <- as.character(src_path %||% "")
    if (!nzchar(src_path_chr) || !path_exists_relaxed(src_path_chr)) {
      return(NULL)
    }
    dir.create(cache_env$cache_dir, recursive = TRUE, showWarnings = FALSE)
    dest <- file.path(cache_env$cache_dir, basename(src_path_chr))
    src_for_copy <- try(normalize_excel_path(src_path_chr), silent = TRUE)
    if (inherits(src_for_copy, "try-error") || is.null(src_for_copy) || !nzchar(src_for_copy)) {
      src_for_copy <- src_path_chr
    }
    copied <- FALSE
    try({
      copied <- isTRUE(file.copy(src_for_copy, dest, overwrite = TRUE))
    }, silent = TRUE)
    if (!copied && !path_exists_relaxed(dest)) {
      return(NULL)
    }
    dest_norm <- tryCatch(normalizePath(dest, winslash = "/", mustWork = FALSE), error = function(e) dest)
    if (path_exists_relaxed(dest_norm)) {
      dest_norm <- safe_windows_short_path(dest_norm, must_exist = TRUE)
    }
    dest_norm
  }
 
  # MCP kayıt defteri anlık görüntüsünü güncelle
  update_mcp_registry_snapshot <- function(files_snapshot = NULL) {
    if (is.null(files_snapshot)) {
      files_snapshot <- session$userData$current_session_files %||% list()
    }
    session$userData$mcp_registry_snapshot <- files_snapshot %||% list()
    session$userData$mcp_registry_snapshot
  }
 
  # Başlangıçta anlık görüntü nesnesini oluştur
  if (is.null(session$userData$mcp_registry_snapshot)) {
    session$userData$mcp_registry_snapshot <- session$userData$current_session_files %||% list()
  }
 
  # Fonksiyonları döndür
  list(
    mcp_saved_path = mcp_saved_path,
    cache_root = cache_root,
    cache_session_token = cache_session_token,
    setup_user_session = setup_user_session,
    cache_mcp_file_locally = cache_mcp_file_locally,
    update_mcp_registry_snapshot = update_mcp_registry_snapshot,
    get_cache_dir = function() cache_env$cache_dir
  )
}
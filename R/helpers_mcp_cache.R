# R/helpers_mcp_cache.R
# MCP dosya önbellekleme yardımcı fonksiyonları

#' Session Token'ı Temizle ve Normalize Et
#'
#' @description
#' Session token'ını alır ve dosya sistemi için güvenli bir formata dönüştürür.
#'
#' @param tok Session token string'i
#'
#' @return Normalize edilmiş token string'i
#'
#' @export
cache_session_token <- function(tok) {
  if (is.null(tok) || !nzchar(tok)) {
    return(sprintf("sess_%s", format(Sys.time(), "%Y%m%d%H%M%S")))
  }
  gsub("[^A-Za-z0-9_-]", "_", tok)
}

#' MCP Önbellek Dizinini Başlat
#'
#' @description
#' Session için MCP önbellek dizinini oluşturur ve yolunu döndürür.
#'
#' @param session Shiny session objesi
#' @param user_id Kullanıcı kimliği
#'
#' @return Önbellek dizini yolu (character)
#'
#' @export
initialize_mcp_cache_dir <- function(session, user_id) {
  # Kök önbellek dizinini al
  cache_root <- getOption(
    "mergen.session_cache_dir",
    normalizePath(file.path(tempdir(), "mergen_session_cache"), winslash = "/", mustWork = FALSE)
  )
  dir.create(cache_root, recursive = TRUE, showWarnings = FALSE)
  cache_root <- safe_windows_short_path(cache_root, must_exist = dir.exists(cache_root))
  
  # Kullanıcı ve session bazlı önbellek dizini
  cache_dir <- file.path(
    cache_root, 
    paste0("user_", user_id), 
    cache_session_token(session$token %||% "anon")
  )
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  cache_dir <- safe_windows_short_path(cache_dir, must_exist = dir.exists(cache_dir))
  
  # Session sonlandığında önbelleği temizle
  session$onSessionEnded(function() {
    try(unlink(cache_dir, recursive = TRUE, force = TRUE), silent = TRUE)
  })
  
  return(cache_dir)
}

#' MCP Dosyasını Yerel Önbelleğe Kopyala
#'
#' @description
#' Kaynak dosyayı session önbelleğine kopyalar ve yeni yolunu döndürür.
#'
#' @param src_path Kaynak dosya yolu
#' @param cache_dir Önbellek dizini yolu
#'
#' @return Kopyalanan dosyanın yolu veya NULL (hata durumunda)
#'
#' @export
cache_mcp_file_locally <- function(src_path, cache_dir) {
  src_path_chr <- as.character(src_path %||% "")
  if (!nzchar(src_path_chr) || !path_exists_relaxed(src_path_chr)) {
    return(NULL)
  }
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  dest <- file.path(cache_dir, basename(src_path_chr))
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
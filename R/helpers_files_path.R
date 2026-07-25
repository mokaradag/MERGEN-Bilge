# ================================================================================
# Dosya Yolu: R/helpers_files_path.R
# Açıklama: Dosya/MCP akışlarında kullanılan UNC, Windows path, encoding ve
#           karşılaştırma yardımcılarını toplar. Bu dosya yan etkisiz kalmalı;
#           dosya kopyalama, içerik okuma veya Shiny state mutasyonu içermez.
# ================================================================================

# UNC yolunu base R fonksiyonları (file(), readBin, pdftools vb.) için okunabilir formata çevirir.
# path_exists_relaxed() dosyanın varlığını doğrular ancak base R'ın açamayacağı bir yol döndürebilir.
# Bu fonksiyon file.exists() ile gerçekten açılabilecek varyantı bulur.
resolve_readable_path <- function(path) {
  if (is.null(path) || !nzchar(path)) return(path)

  p <- as.character(path[1])

  # Zaten base R ile çalışıyorsa dokunma
  if (tryCatch(isTRUE(file.exists(p)), error = function(e) FALSE)) return(p)

  # UNC forward slash -> backslash dene (\\server\share formatı)
  p_bs <- gsub("/", "\\\\", p, fixed = TRUE)
  if (tryCatch(isTRUE(file.exists(p_bs)), error = function(e) FALSE)) return(p_bs)

  # Tek slash başlangıcını çift slash ile dene
  p_fwd <- gsub("\\\\", "/", p, fixed = TRUE)
  if (grepl("^/[^/]", p_fwd)) {
    p_unc <- paste0("/", p_fwd)
    if (tryCatch(isTRUE(file.exists(p_unc)), error = function(e) FALSE)) return(p_unc)

    p_unc_bs <- gsub("/", "\\\\", p_unc, fixed = TRUE)
    if (tryCatch(isTRUE(file.exists(p_unc_bs)), error = function(e) FALSE)) return(p_unc_bs)
  }

  p
}

# Relaxed file.exists for UNC + long paths + Encoding variants
path_exists_relaxed <- function(path) {
  if (is.null(path) || length(path) == 0) return(FALSE)

  candidate <- as.character(path[1])
  if (!nzchar(candidate)) return(FALSE)

  # Generate variants: Slashes, Backslashes, UNC
  cand_slash <- gsub("\\\\", "/", candidate, fixed = TRUE)

  variants <- unique(trimws(Filter(nzchar, c(
    candidate,
    cand_slash,
    # UNC repairs
    sub("^//\\?/UNC", "//", cand_slash, perl = TRUE),
    sub("^//\\?/", "//", cand_slash, perl = TRUE),
    # Fix missing leading slash for UNC (common R issue on Windows)
    if (grepl("^/[^/]", cand_slash)) paste0("/", cand_slash) else NULL,
    gsub("/", "\\\\", cand_slash, fixed = TRUE)
  ))))

  for (chk in variants) {
    # 1. Check as is
    if (tryCatch(isTRUE(file.exists(chk)), error = function(e) FALSE)) return(TRUE)
    if (tryCatch(isTRUE(fs::file_exists(chk)), error = function(e) FALSE)) return(TRUE)

    # 2. Check UTF-8 encoded (for Turkish chars)
    chk_utf8 <- tryCatch(enc2utf8(chk), error = function(e) chk)
    if (tryCatch(isTRUE(file.exists(chk_utf8)), error = function(e) FALSE)) return(TRUE)
    if (tryCatch(isTRUE(fs::file_exists(chk_utf8)), error = function(e) FALSE)) return(TRUE)
  }

  FALSE
}

normalize_for_path_compare <- function(path) {
  if (is.null(path) || length(path) == 0) {
    return("")
  }

  candidate <- as.character(path[1])
  if (!nzchar(candidate)) {
    return("")
  }

  cleaned <- gsub("\\", "/", candidate, fixed = TRUE)
  cleaned <- sub("^//\\?/UNC", "//", cleaned, perl = TRUE)
  cleaned <- sub("^//\\?/", "//", cleaned, perl = TRUE)
  cleaned <- sub("^//(?=[A-Za-z]:)", "", cleaned, perl = TRUE)
  cleaned <- gsub("(?<!:)//+", "/", cleaned, perl = TRUE)
  cleaned <- trimws(cleaned)

  tolower(cleaned)
}

# Is path under MCP base?
is_under_mcp_base <- function(p) {
  # Önce doğru encoding'li seçeneği kullan (config_file_store.R'den)
  base <- getOption("mergen.mcp_base_dir", "")
  if (!nzchar(base)) base <- Sys.getenv("MCP_FILES_BASE")
  if (!nzchar(base)) return(FALSE)

  safe_norm <- function(x) {
    x <- gsub("\\\\", "/", x)
    if (.Platform$OS.type == "windows" && grepl("^/[^/]", x)) x <- paste0("/", x)
    enc2utf8(x)
  }

  np <- safe_norm(p)
  nb <- safe_norm(base)

  if (!nzchar(np) || !nzchar(nb)) return(FALSE)

  # Türkçe karakter bozulsa bile son klasör segmentleri ASCII kaldığı için
  # önce bunlar üzerinden hızlı ve güvenli tespit yap.
  np_parent <- tryCatch(basename(dirname(np)), error = function(e) "")
  np_grand  <- tryCatch(basename(dirname(dirname(np))), error = function(e) "")
  nb_base   <- tryCatch(basename(nb), error = function(e) "")

  if (
    grepl("^user_[0-9]+$", tolower(np_parent)) &&
    nzchar(np_grand) &&
    nzchar(nb_base) &&
    identical(tolower(np_grand), tolower(nb_base))
  ) {
    return(TRUE)
  }

  startsWith(normalize_for_path_compare(np), paste0(normalize_for_path_compare(nb), "/")) ||
    normalize_for_path_compare(np) == normalize_for_path_compare(nb)
}

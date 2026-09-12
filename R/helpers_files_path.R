# ==============================================================================
# Dosya Yolu: R/helpers_files_path.R
# Açıklama: Dosya/MCP akışlarında kullanılan UNC, Windows path, encoding ve
#           karşılaştırma yardımcılarını toplar. Bu dosya yan etkisiz kalmalı;
#           dosya kopyalama, içerik okuma veya Shiny state mutasyonu içermez.
# ==============================================================================

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

# Varlığı KANITLANAN yol varyantını döndürür (yoksa NA_character_).
# `path_exists_relaxed()` yalnızca TRUE/FALSE döndürüyordu; çağıranlar
# kanonikleştirme için ÖZGÜN yolu kullanmak zorunda kalıyor ve UNC/enc2utf8
# varyantı üzerinden var olan bir dosya "Geçersiz dosya yolu" ile reddediliyordu.
path_existing_variant <- function(path) {
  if (is.null(path) || length(path) == 0) return(NA_character_)

  candidate <- as.character(path[1])
  if (is.na(candidate) || !nzchar(candidate)) return(NA_character_)

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

  # Tek varyant sondası: base + fs denetimi tek hata kapsamında birleştirilir.
  var_mi <- function(p) isTRUE(tryCatch(
    isTRUE(file.exists(p)) || isTRUE(unname(fs::file_exists(p))),
    error = function(e) FALSE
  ))

  for (chk in variants) {
    if (var_mi(chk)) return(chk)

    # UTF-8 kodlanmış biçim (Türkçe adlar için)
    chk_utf8 <- tryCatch(enc2utf8(chk), error = function(e) chk)
    if (var_mi(chk_utf8)) return(chk_utf8)
  }

  NA_character_
}

# Relaxed file.exists for UNC + long paths + Encoding variants
path_exists_relaxed <- function(path) {
  !is.na(path_existing_variant(path))
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

  # Çözülmemiş '..' parçası taşıyan yol taban altında sayılmaz (önek kıyası
  # '..' çıkışını göremez).
  if (grepl("(^|/)\\.\\.(/|$)", np, perl = TRUE)) return(FALSE)

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

# ------------------------------------------------------------------------------
# KANONİK KAPSAMA DENETİMİ
# Yol tabanlı `unlink()`/`file.copy()` ata bileşenlerini İZLER; doğrulama ile
# işlem arasında bir ata bağlantı/junction ile değiştirilirse kök DIŞINDAKİ bir
# dosya silinebilir/ezilebilir. Base R tanıtıcı-bağıl (openat/unlinkat) temel
# işlem sunmadığı için pencere tamamen kapatılamaz; bu yardımcı yol tabanlı
# kaçışı reddeder, kaçış tespit edilirse işlem HİÇ denenmez.
# ------------------------------------------------------------------------------
mergen_path_inside_root <- function(candidate, root) {
  # `%||%` bu dosyada başka yerde kullanılmıyor; izole test/worker bağlamında
  # tanımlı olmayabilir, bu yüzden açık NULL denetimi yapılır.
  # Kök bilinmiyorsa kapsama KANITLANAMAZ: doğrulanmamış kökle silme/kopyalama
  # yapılmaması için kapalı-başarısız davranılır.
  if (is.null(root)) return(FALSE)
  root <- as.character(root)[1]
  if (is.na(root) || !nzchar(root)) return(FALSE)

  kok <- try(normalizePath(root, winslash = "/", mustWork = FALSE), silent = TRUE)
  coz <- try(normalizePath(as.character(candidate)[1], winslash = "/", mustWork = FALSE),
             silent = TRUE)
  if (inherits(kok, "try-error") || inherits(coz, "try-error")) return(FALSE)
  if (is.na(kok[1]) || is.na(coz[1]) || !nzchar(kok[1]) || !nzchar(coz[1])) return(FALSE)
  kok <- kok[1]
  coz <- coz[1]

  if (.Platform$OS.type == "windows") {
    kok <- tolower(kok)
    coz <- tolower(coz)
  }
  kok <- sub("/+$", "", kok)

  # `normalizePath(..., mustWork = FALSE)` çözülemeyen yolu OLDUĞU GİBİ döndürür
  # (ör. ata dizin geçiş izni vermiyorsa ya da yol diskte yoksa). Kalan '..'
  # parçası önek kıyasını atlatıp kök DIŞINDAKİ bir yolu onaylatabiliyordu
  # (bkz. is_under_mcp_base aynı denetim).
  if (grepl("(^|/)\\.\\.(/|$)", coz, perl = TRUE)) return(FALSE)

  identical(coz, kok) || startsWith(coz, paste0(kok, "/"))
}


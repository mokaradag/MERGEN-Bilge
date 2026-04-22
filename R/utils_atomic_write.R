# ==============================================================================
# Dosya Yolu: R/utils_atomic_write.R
# Açıklama: Disk üzerine dosya yazımı için atomik (hepsi-ya-hiçbiri) yardımcıları.
# Windows VM ortamında file.rename tek bir işlem gibi davranır; kısmi yazım
# nedeniyle bozuk kalan index/json dosyalarını önlemek için tüm kritik yazımlar
# bu yardımcıdan geçmelidir. jsonlite paketi zaten config_packages.R tarafından
# yüklü olduğu için ek bağımlılık gerektirmez.
# ==============================================================================

# Verilen içeriği aynı dizinde geçici dosyaya yazar, ardından file.rename ile
# hedefe taşır. Başarısızlık durumunda kopya+silme ile fallback yapar ve
# kalıcı hata üretir. final_path üzerinde kısmi yazım kalması engellenir.
atomic_write_text <- function(content, final_path, encoding = "UTF-8") {
  if (!is.character(final_path) || length(final_path) != 1L || !nzchar(final_path)) {
    stop("atomic_write_text: 'final_path' tek elemanli, bos olmayan karakter olmali.")
  }
  if (!is.character(content)) {
    stop("atomic_write_text: 'content' karakter vektoru olmali.")
  }

  dir_path <- dirname(final_path)
  dir.create(dir_path, recursive = TRUE, showWarnings = FALSE)

  tmp_path <- tempfile(
    pattern = "atomic_",
    tmpdir = dir_path,
    fileext = ".tmp"
  )

  on.exit({
    if (file.exists(tmp_path)) {
      try(unlink(tmp_path, force = TRUE), silent = TRUE)
    }
  }, add = TRUE)

  # UTF-8 metni text-connection ile yaz.
  # writeBin(charToRaw(...)) bazı Windows VM ortamlarında native codepage benzeri
  # bozuk baytlar bırakabiliyor; burada explicit UTF-8 text write kullanılır.
  icerik_utf8 <- enc2utf8(paste(content, collapse = "\n"))

  con <- file(tmp_path, open = "w", encoding = encoding)
  tryCatch({
    writeLines(icerik_utf8, con = con, sep = "")
  }, finally = {
    close(con)
  })

  tmp_info <- suppressWarnings(file.info(tmp_path))
  if (!file.exists(tmp_path) || is.na(tmp_info$size[1])) {
    stop("atomic_write_text: gecici dosya olusturulamadi.")
  }

  moved <- suppressWarnings(file.rename(tmp_path, final_path))
  if (!isTRUE(moved)) {
    moved <- isTRUE(file.copy(tmp_path, final_path, overwrite = TRUE))
    if (isTRUE(moved)) {
      try(unlink(tmp_path, force = TRUE), silent = TRUE)
    }
  }

  if (!isTRUE(moved)) {
    stop(sprintf("atomic_write_text: hedefe tasima basarisiz: %s", final_path))
  }

  invisible(TRUE)
}

# JSON serileştirme + atomik yazım. jsonlite::write_json doğrudan dosyaya yazdığı
# için kısmi yazım riski vardır; bu yardımcı önce metne serileştirir, sonra atomik
# yazar. pretty/auto_unbox parametreleri jsonlite::toJSON ile birebir geçirilir.
atomic_write_json <- function(data,
                              final_path,
                              pretty = TRUE,
                              auto_unbox = TRUE,
                              null = "null") {
  json_metni <- jsonlite::toJSON(
    data,
    pretty = pretty,
    auto_unbox = auto_unbox,
    null = null
  )
  atomic_write_text(as.character(json_metni), final_path)
}
# ==============================================================================
# Dosya Yolu: R/utils_atomic_write.R
# Açıklama: Disk üzerine dosya yazımı için atomik (hepsi-ya-hiçbiri) yardımcıları.
#           Windows VM ortamında file.rename başarısız olursa file.copy fallback
#           yolunu kullanır. UTF-8 içerik binary modda yazılarak Windows native
#           codepage bozulmaları ve kısmi JSON/index yazımları önlenir.
# ==============================================================================

# Verilen içeriği aynı dizinde geçici dosyaya yazar, ardından file.rename ile
# hedefe taşır. Başarısızlık durumunda file.copy + unlink fallback kullanır.
# final_path üzerinde kısmi yazım kalması engellenir.
#
# ÖNEMLİ:
# - file.rename() ve file.copy() burada bilerek namespace ile çağrılmaz.
#   tests/testthat/test-atomic-write-fallback.R bu fonksiyonları izole
#   atomic_env içinde stub ederek fallback davranışını doğrular.
# - Yazım binary modda yapılır; böylece Windows VM native codepage'e düşülmez.
atomic_write_text <- function(content, final_path, encoding = "UTF-8") {
  if (!is.character(final_path) ||
      length(final_path) != 1L ||
      is.na(final_path) ||
      !nzchar(final_path)) {
    stop("atomic_write_text: 'final_path' tek elemanli, bos olmayan karakter olmali.")
  }

  if (!is.character(content)) {
    stop("atomic_write_text: 'content' karakter vektoru olmali.")
  }

  final_path <- suppressWarnings(
    normalizePath(final_path, winslash = "/", mustWork = FALSE)
  )

  dir_path <- dirname(final_path)

  if (!dir.exists(dir_path)) {
    dir_ready <- tryCatch({
      if (requireNamespace("fs", quietly = TRUE)) {
        fs::dir_create(dir_path, recurse = TRUE)
      } else {
        dir.create(dir_path, recursive = TRUE, showWarnings = FALSE)
      }
      TRUE
    }, error = function(e) FALSE)

    if (!isTRUE(dir_ready) || !dir.exists(dir_path)) {
      stop(sprintf(
        "atomic_write_text: hedef dizin oluşturulamadı: %s",
        dir_path
      ))
    }
  }

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

  if (!dir.exists(dirname(tmp_path))) {
    stop(sprintf(
      "atomic_write_text: geçici dosya dizini bulunamadı: %s",
      dirname(tmp_path)
    ))
  }

  # İçeriği tek UTF-8 metne indir ve raw byte dizisine çevir.
  # Bu değişkenin adı aşağıdaki writeBin() ile aynı kalmalıdır.
  content_utf8 <- enc2utf8(paste(content, collapse = "\n"))
  content_raw <- charToRaw(content_utf8)

  con <- tryCatch(
    file(tmp_path, open = "wb"),
    error = function(e) {
      stop(sprintf(
        "atomic_write_text: geçici dosya açılamadı: %s | %s",
        tmp_path,
        conditionMessage(e)
      ), call. = FALSE)
    }
  )

  tryCatch(
    {
      writeBin(content_raw, con)
      flush(con)
    },
    finally = {
      close(con)
    }
  )

  tmp_info <- suppressWarnings(file.info(tmp_path))
  if (!file.exists(tmp_path) || is.na(tmp_info$size[1])) {
    stop("atomic_write_text: gecici dosya olusturulamadi.")
  }

  moved <- suppressWarnings(file.rename(tmp_path, final_path))

  if (!isTRUE(moved)) {
    # Windows VM'de kilitli dosya / rename başarısızlığı görülebilir.
    # Testler bu fallback yolunun çalıştığını doğrular.
    copied <- suppressWarnings(file.copy(tmp_path, final_path, overwrite = TRUE))

    if (isTRUE(copied)) {
      try(unlink(tmp_path, force = TRUE), silent = TRUE)
      moved <- TRUE
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

  atomic_write_text(
    as.character(json_metni),
    final_path = final_path,
    encoding = "UTF-8"
  )
}
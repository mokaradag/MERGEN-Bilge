# ==============================================================================
# Dosya Yolu: R/utils_safe_source.R
# Açıklama: Kaynak dosyaları UTF-8 güvenli şekilde yüklemek için ortak helper.
# ==============================================================================

safe_source <- function(file, encoding = "UTF-8", envir = globalenv()) {
  if (!file.exists(file)) {
    stop(sprintf("Kaynak dosya bulunamadı: %s", file))
  }

  tryCatch({
    source(file, encoding = encoding, local = envir)
    invisible(NULL)
  }, error = function(e) {
    hata_metni <- conditionMessage(e)

    encoding_hatasi_mi <- grepl(
      "INCOMPLETE_STRING|invalid multibyte|unexpected input|EOF within quoted string|nul character|invalid input",
      hata_metni,
      ignore.case = TRUE
    )

    if (!isTRUE(encoding_hatasi_mi)) {
      stop(e)
    }

    if (!file.exists(file)) {
      stop(sprintf("Kaynak dosya bulunamadı: %s", file))
    }

    read_text_with_encoding <- function(path, encoding_name) {
      paste(
        readLines(path, warn = FALSE, encoding = encoding_name),
        collapse = "\n"
      )
    }

    denenecek_kodlamalar <- c("UTF-8", "WINDOWS-1254", "latin1")
    son_hata <- NULL

    for (kodlama in denenecek_kodlamalar) {
      metin <- tryCatch(
        read_text_with_encoding(file, kodlama),
        error = function(err) {
          son_hata <<- err
          NA_character_
        }
      )

      if (is.na(metin) || !nzchar(metin)) next

      metin <- sub("^\\ufeff", "", metin, perl = TRUE)

      exprs <- tryCatch(
        parse(text = metin, keep.source = FALSE, encoding = "UTF-8"),
        error = function(err) {
          son_hata <<- err
          NULL
        }
      )

      if (is.null(exprs)) next

      eval(exprs, envir = envir)
      return(invisible(NULL))
    }

    if (!is.null(son_hata)) {
      stop(son_hata)
    }

    stop(e)
  })
}
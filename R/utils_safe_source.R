# ==============================================================================
# Dosya Yolu: R/utils_safe_source.R
# Açıklama: Kaynak dosyalari UTF-8 guvenli sekilde yuklemek icin ortak helper.
# ==============================================================================
safe_source <- function(file, encoding = "UTF-8", envir = globalenv()) {
  if (!file.exists(file)) {
    stop(sprintf("Kaynak dosya bulunamadi: %s", file))
  }

  # Kodlama/BOM kaynakli hata ve uyarilari tespit eder.
  is_encoding_issue <- function(message) {
    msg <- if (is.null(message) || length(message) == 0) "" else as.character(message)[1]
    msg <- tolower(enc2utf8(msg))

    patterns <- c(
      "incomplete_string",
      "invalid multibyte",
      "unexpected input",
      "eof within quoted string",
      "nul character",
      "invalid input",
      "byte order mark",
      "bom",
      "invalid token",
      "geçersiz giriş",
      "beklenmeyen giriş",
      "çok baytlı",
      "çokbaytlı",
      "eksik dize"
    )

    any(vapply(
      patterns,
      function(p) grepl(p, msg, fixed = TRUE),
      logical(1)
    ))
  }

  # Dosyayi ham bayt olarak okuyup secilen kodlama ile UTF-8 metne cevirir.
  read_text_with_encoding <- function(path, encoding_name) {
    size <- suppressWarnings(file.info(path)$size[1])
    if (is.na(size) || size <= 0) {
      return("")
    }

    con <- file(path, open = "rb")
    on.exit(close(con), add = TRUE)

    raw_data <- readBin(con, what = "raw", n = size)

    # UTF-8 BOM temizligi
    if (length(raw_data) >= 3L &&
        identical(as.integer(raw_data[1:3]), c(239L, 187L, 191L))) {
      raw_data <- raw_data[-(1:3)]
    }

    if (!length(raw_data)) {
      return("")
    }

    txt <- tryCatch(
      iconv(list(raw_data), from = encoding_name, to = "UTF-8", sub = NA)[[1]],
      error = function(e) NA_character_
    )

    if (is.na(txt)) {
      stop(sprintf(
        "Dosya metni '%s' kodlamasiyla UTF-8'e cevrilemedi.",
        encoding_name
      ))
    }

    txt <- gsub("\r\n?|\r", "\n", txt, perl = TRUE)
    enc2utf8(txt)
  }

  # Once normal source() yolunu dene.
  birincil_sonuc <- tryCatch(
    withCallingHandlers(
      {
        source(file, encoding = encoding, local = envir)
        invisible(NULL)
      },
      warning = function(w) {
        warning_text <- conditionMessage(w)
        if (isTRUE(is_encoding_issue(warning_text))) {
          stop(warning_text, call. = FALSE)
        }
      }
    ),
    error = function(e) e
  )

  if (!inherits(birincil_sonuc, "error")) {
    return(invisible(NULL))
  }

  hata_metni <- conditionMessage(birincil_sonuc)

  if (!isTRUE(is_encoding_issue(hata_metni))) {
    stop(birincil_sonuc)
  }

  denenecek_kodlamalar <- c("UTF-8", "WINDOWS-1254", "latin1")
  son_hata <- birincil_sonuc

  for (kodlama in denenecek_kodlamalar) {
    metin <- tryCatch(
      read_text_with_encoding(file, kodlama),
      error = function(err) {
        son_hata <<- err
        NA_character_
      }
    )

    if (is.na(metin) || !nzchar(metin)) {
      next
    }

    exprs <- tryCatch(
      parse(text = metin, keep.source = FALSE, encoding = "UTF-8"),
      error = function(err) {
        son_hata <<- err
        NULL
      }
    )

    if (is.null(exprs)) {
      next
    }

    eval(exprs, envir = envir)
    return(invisible(NULL))
  }

  stop(son_hata)
}
# ==============================================================================
# Dosya Yolu: R/utils_safe_source.R
# Açıklama: Kaynak dosyaları UTF-8 güvenli şekilde yüklemek için ortak helper.
# ==============================================================================

safe_source <- function(file, encoding = "UTF-8", envir = globalenv()) {
  if (!file.exists(file)) {
    stop(sprintf("Kaynak dosya bulunamadı: %s", file))
  }

  # Kodlama/BOM kaynaklı hata ve uyarıları tespit eder.
  is_encoding_issue <- function(message) {
    msg <- if (is.null(message) || length(message) == 0) "" else as.character(message)[1]
    msg <- tolower(msg)

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

  # Dosyayı ham bayt olarak okuyup UTF-8 metne çevirir.
  read_text_with_encoding <- function(path, encoding_name) {
    lines <- tryCatch(
      suppressWarnings(
        readLines(
          path,
          warn = FALSE,
          encoding = encoding_name,
          skipNul = TRUE
        )
      ),
      error = function(e) e
    )

    if (inherits(lines, "error")) {
      stop(sprintf(
        "Dosya metni '%s' kodlamasıyla okunamadı: %s",
        encoding_name,
        conditionMessage(lines)
      ))
    }

    if (!length(lines)) {
      return("")
    }

    metin_utf8 <- paste(lines, collapse = "\n")

    bom_char <- intToUtf8(65279L)
    if (startsWith(metin_utf8, bom_char)) {
      metin_utf8 <- substring(metin_utf8, 2L)
    }

    metin_utf8 <- gsub("\r\n?|\r", "\n", metin_utf8, perl = TRUE)
    enc2utf8(metin_utf8)
  }

  # Önce normal source() yolunu dener; kodlama uyarılarını da hata gibi ele alır.
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

    if (is.na(metin) || !nzchar(metin)) next

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

  stop(son_hata)
}
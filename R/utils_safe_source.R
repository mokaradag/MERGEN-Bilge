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

    patterns <- c(
      "INCOMPLETE_STRING",
      "invalid multibyte",
      "unexpected input",
      "EOF within quoted string",
      "nul character",
      "invalid input",
      "byte order mark",
      "bom",
      "invalid token"
    )

    any(vapply(
      patterns,
      function(p) grepl(p, msg, ignore.case = TRUE, fixed = TRUE),
      logical(1)
    ))
  }

  # Dosyayı ham bayt olarak okuyup UTF-8 metne çevirir.
  read_text_with_encoding <- function(path, encoding_name) {
    con <- file(path, open = "rb")
    on.exit(close(con), add = TRUE)

    raw_data <- readBin(con, what = "raw", n = file.info(path)$size)

    # UTF-8 BOM varsa temizler.
    if (length(raw_data) >= 3L &&
        identical(as.integer(raw_data[1:3]), c(239L, 187L, 191L))) {
      raw_data <- raw_data[-(1:3)]
    }

    if (!length(raw_data)) {
      return("")
    }

    metin <- rawToChar(raw_data)

    metin_utf8 <- iconv(
      metin,
      from = encoding_name,
      to = "UTF-8",
      sub = "byte"
    )

    if (is.na(metin_utf8)) {
      stop(sprintf(
        "Dosya metni '%s' kodlamasıyla UTF-8'e çevrilemedi.",
        encoding_name
      ))
    }

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
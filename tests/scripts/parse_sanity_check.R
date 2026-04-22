# ==============================================================================
# Dosya Yolu: tests/scripts/parse_sanity_check.R
# Açıklama: Repo içindeki ana R dosyalarının parse edilebildiğini doğrulayan
# yerel/CI ortak sözdizim kontrol betiği.
# UTF-8 / WINDOWS-1254 / latin1 fallback mantığı ile Windows VM ortamlarında
# kodlama kaynaklı sahte parse hatalarını azaltır.
# ==============================================================================

root_files <- c(
  "app.R",
  "global.R",
  "ui.R",
  "server.R",
  "welcome_screen.R"
)

root_files <- root_files[file.exists(root_files)]

r_files <- list.files(
  "R",
  pattern = "\\.R$",
  full.names = TRUE,
  recursive = TRUE
)

all_files <- unique(c(root_files, r_files))

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

read_text_with_encoding <- function(path, encoding_name) {
  con <- file(path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_data <- readBin(con, what = "raw", n = file.info(path)$size)

  # UTF-8 BOM temizliği
  if (length(raw_data) >= 3L &&
      identical(as.integer(raw_data[1:3]), c(239L, 187L, 191L))) {
    raw_data <- raw_data[-(1:3)]
  }

  if (!length(raw_data)) {
    return("")
  }

  text_raw <- rawToChar(raw_data)
  text_utf8 <- iconv(
    text_raw,
    from = encoding_name,
    to = "UTF-8",
    sub = "byte"
  )

  if (is.na(text_utf8)) {
    stop(sprintf(
      "Dosya metni '%s' kodlamasıyla UTF-8'e çevrilemedi.",
      encoding_name
    ))
  }

  enc2utf8(text_utf8)
}

parse_file_robust <- function(path) {
  primary_result <- tryCatch(
    withCallingHandlers(
      {
        parse(file = path, keep.source = FALSE, encoding = "UTF-8")
        TRUE
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

  if (isTRUE(primary_result)) {
    return(invisible(TRUE))
  }

  if (!inherits(primary_result, "error")) {
    return(invisible(TRUE))
  }

  error_text <- conditionMessage(primary_result)

  if (!isTRUE(is_encoding_issue(error_text))) {
    stop(primary_result)
  }

  encodings_to_try <- c("UTF-8", "WINDOWS-1254", "latin1")
  last_error <- primary_result

  for (enc in encodings_to_try) {
    text_utf8 <- tryCatch(
      read_text_with_encoding(path, enc),
      error = function(e) {
        last_error <<- e
        NA_character_
      }
    )

    if (is.na(text_utf8)) next

    exprs <- tryCatch(
      parse(text = text_utf8, keep.source = FALSE, encoding = "UTF-8"),
      error = function(e) {
        last_error <<- e
        NULL
      }
    )

    if (!is.null(exprs)) {
      return(invisible(TRUE))
    }
  }

  stop(last_error)
}

parse_errors <- character(0)

for (f in all_files) {
  tryCatch(
    suppressWarnings(parse_file_robust(f)),
    error = function(e) {
      parse_errors[[f]] <<- conditionMessage(e)
    }
  )
}

if (length(parse_errors) > 0) {
  for (f in names(parse_errors)) {
    cat(sprintf("[PARSE ERROR] %s: %s\n", f, parse_errors[[f]]))
  }
  stop(sprintf("%d dosyada parse hatası var.", length(parse_errors)))
}

cat(sprintf("OK: %d dosya parse edildi.\n", length(all_files)))
# ==============================================================================
# Dosya Yolu: tests/scripts/maintainability_report.R
# Açıklama: Büyük R dosyalarını, fonksiyon sayısını ve yaklaşık satır sayılarını
# raporlar. Bu script test değildir; üretim refactor planı için güvenli rapordur.
# ==============================================================================

repo_root <- normalizePath(".", winslash = "/", mustWork = TRUE)

if (!file.exists(file.path(repo_root, "app.R")) ||
    !dir.exists(file.path(repo_root, "R"))) {
  stop("Bu script repo kökünden çalıştırılmalıdır.", call. = FALSE)
}

read_text <- function(path) {
  size <- suppressWarnings(file.info(path)$size[1])
  if (is.na(size) || size <= 0) {
    return("")
  }

  con <- file(path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_data <- readBin(con, what = "raw", n = size)

  txt <- suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
  )

  if (is.na(txt)) {
    txt <- ""
  }

  txt <- gsub("\r\n?|\r", "\n", txt, perl = TRUE)
  enc2utf8(txt)
}

runtime_files <- c(
  file.path(repo_root, "app.R"),
  file.path(repo_root, "global.R"),
  file.path(repo_root, "ui.R"),
  file.path(repo_root, "server.R"),
  file.path(repo_root, "welcome_screen.R"),
  list.files(file.path(repo_root, "R"), pattern = "\\.R$", recursive = TRUE, full.names = TRUE)
)

runtime_files <- unique(runtime_files[file.exists(runtime_files)])

report <- lapply(runtime_files, function(path) {
  txt <- read_text(path)
  lines <- strsplit(txt, "\n", fixed = TRUE)[[1]]

  function_count <- length(gregexpr(
    "(<-|=)\\s*function\\s*\\(",
    txt,
    perl = TRUE
  )[[1]])

  if (identical(function_count, 1L) &&
      identical(gregexpr("(<-|=)\\s*function\\s*\\(", txt, perl = TRUE)[[1]][1], -1L)) {
    function_count <- 0L
  }

  data.frame(
    file = sub(paste0("^", gsub("([\\^$.|?*+(){}\\[\\]\\\\])", "\\\\\\1", repo_root), "/?"), "", normalizePath(path, winslash = "/", mustWork = TRUE), perl = TRUE),
    lines = length(lines),
    functions = function_count,
    stringsAsFactors = FALSE
  )
})

report <- do.call(rbind, report)
report <- report[order(report$lines, decreasing = TRUE), ]

print(utils::head(report, 30), row.names = FALSE)

cat("\nRefactor adayları:\n")
candidates <- subset(report, lines >= 800 | functions >= 25)
print(candidates, row.names = FALSE)

invisible(report)
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

# library_queries.R bilgi tabanı niteliğinde olduğu için maintainability
# skorundan hariç tutulur; bu dosya bilinçli olarak büyük kalabilir.
score_report <- subset(report, !grepl("(^|/)library_queries\\.R$", file, perl = TRUE))

candidates <- subset(score_report, lines >= 800 | functions >= 25)
print(candidates, row.names = FALSE)

total_files <- nrow(score_report)
large_files <- sum(score_report$lines >= 800)
large_function_files <- sum(score_report$functions >= 25)
very_large_files <- sum(score_report$lines >= 1500)
max_lines <- max(score_report$lines, na.rm = TRUE)
max_functions <- max(score_report$functions, na.rm = TRUE)

# 100 üzerinden basit, izlenebilir ve tartışılabilir bir bakım skoru.
# Amaç mutlak kaliteyi ölçmek değil; refactor yönünün iyileşip iyileşmediğini
# her koşumda görünür hale getirmektir.
maintainability_score <- 100 -
  (large_files * 3) -
  (large_function_files * 2) -
  (very_large_files * 5)

maintainability_score <- max(0, min(100, maintainability_score))

cat("\nMaintainability özeti:\n")
cat(sprintf("- Skor: %d/100\n", maintainability_score))
cat(sprintf("- Değerlendirilen dosya sayısı: %d\n", total_files))
cat(sprintf("- 800+ satır dosya sayısı: %d\n", large_files))
cat(sprintf("- 25+ fonksiyon dosya sayısı: %d\n", large_function_files))
cat(sprintf("- 1500+ satır dosya sayısı: %d\n", very_large_files))
cat(sprintf("- En büyük dosya satırı: %d\n", max_lines))
cat(sprintf("- En yüksek fonksiyon sayısı: %d\n", max_functions))

attr(report, "maintainability_score") <- maintainability_score
attr(report, "score_report") <- score_report

invisible(report)
# ==============================================================================
# Dosya Yolu: tests/scripts/parse_sanity_check.R
# Açıklama: Repo içindeki ana R dosyalarının UTF-8 ile parse edilebildiğini
# doğrulayan basit sözdizim kontrol betiği.
#
# NOT:
# - Bu betik BİLEREK fallback decode / text-reparse yapmaz.
# - Çünkü VM ortamında asıl bozulan şey parse değil, fallback decode yoluydu.
# - App ve testthat zaten çalışıyorsa, burada en güvenli kontrol parse(file=...)
#   ile doğrudan UTF-8 parse etmektir.
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

parse_errors <- character(0)

for (f in all_files) {
  tryCatch(
    {
      parse(file = f, keep.source = FALSE, encoding = "UTF-8")
      invisible(TRUE)
    },
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
# ==============================================================================
# Dosya Yolu: tests/testthat/helper_utf8_parse.R
# Açıklama: Bir R dosyasını yerel kod sayfasından ve options(encoding)
#           değerinden bağımsız olarak UTF-8 ayrıştırır. readLines() CP1254
#           oturumunda options(encoding = "UTF-8") varken baytları yerel koda
#           çevirip UTF-8 diye işaretler (geçersiz UTF-8); ham baytlar okunur ve
#           testthat'in kendi yükleyicisi gibi UTF-8 bağlantıdan ayrıştırılır.
# ==============================================================================

# BOM bayt düzeyinde atılır (geçersiz UTF-8'de de); CRLF ve tek başına CR satır
# sonları da ayrılır (R'nin metin kipi kaynak okuması gibi).
parse_r_file_utf8 <- function(path) {
  bayt <- readBin(path, what = "raw", n = file.info(path)$size)
  if (length(bayt) >= 3L && identical(bayt[1:3], as.raw(c(0xEF, 0xBB, 0xBF)))) bayt <- bayt[-(1:3)]
  metin <- rawToChar(bayt)
  Encoding(metin) <- "UTF-8"
  con <- textConnection(strsplit(metin, "\r\n|\r|\n")[[1]], encoding = "UTF-8")
  on.exit(close(con), add = TRUE)
  parse(con, keep.source = FALSE, encoding = "UTF-8")
}

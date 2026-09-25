# ==============================================================================
# Dosya Yolu: tests/testthat/helper_utf8_parse.R
# Açıklama: Bir R dosyasını yerel kod sayfasından ve options(encoding)
#           değerinden bağımsız olarak UTF-8 ayrıştırır. readLines() CP1254
#           oturumunda options(encoding = "UTF-8") varken baytları yerel koda
#           çevirip UTF-8 diye işaretler (geçersiz UTF-8); ham baytlar okunur ve
#           testthat'in kendi yükleyicisi gibi UTF-8 bağlantıdan ayrıştırılır.
# ==============================================================================

parse_r_file_utf8 <- function(path) {
  metin <- rawToChar(readBin(path, what = "raw", n = file.info(path)$size))
  Encoding(metin) <- "UTF-8"
  con <- textConnection(strsplit(sub("^\ufeff", "", metin), "\r?\n")[[1]], encoding = "UTF-8")
  on.exit(close(con), add = TRUE)
  parse(con, keep.source = FALSE, encoding = "UTF-8")
}

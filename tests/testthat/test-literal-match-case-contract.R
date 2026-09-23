# ==============================================================================
# Dosya Yolu: tests/testthat/test-literal-match-case-contract.R
# Açıklama: Çalışma zamanı kodu `fixed = TRUE` ile `ignore.case = TRUE`
#           birleşimini KULLANMAZ. R bu birleşimde `ignore.case` bağımsız
#           değişkenini YOK SAYAR ve her çağrıda uyarı üretir: arama sessizce
#           büyük/küçük harf duyarlı olur (ör. Kayıtlı Söyleşiler başlık
#           aramasının eşleşme bulunamadığında devreye giren yedeği). Büyük/küçük
#           harf duyarsız düz eşleşme `tolower()` ile yapılmalıdır.
# ==============================================================================

test_that("çalışma zamanı kodunda fixed + ignore.case birleşimi yoktur", {
  kok <- resolve_repo_root_for_tests()
  dosyalar <- c(list.files(file.path(kok, "R"), pattern = "\\.R$", full.names = TRUE),
                file.path(kok, c("app.R", "global.R", "ui.R", "server.R")))
  dosyalar <- dosyalar[file.exists(dosyalar)]
  birlesim <- "fixed\\s*=\\s*TRUE[^)]*ignore\\.case\\s*=\\s*TRUE|ignore\\.case\\s*=\\s*TRUE[^)]*fixed\\s*=\\s*TRUE"

  ihlaller <- character(0)
  for (f in dosyalar) {
    satirlar <- readLines(f, warn = FALSE, encoding = "UTF-8")
    kod <- !grepl("^\\s*#", satirlar)
    isabet <- which(kod & grepl(birlesim, satirlar, perl = TRUE))
    if (length(isabet)) ihlaller <- c(ihlaller, sprintf("%s:%d", basename(f), isabet))
  }
  expect_identical(ihlaller, character(0))

  # Kayıtlı Söyleşiler başlık aramasının düz eşleşme yedeği harf duyarsızdır.
  kayitli <- paste(readLines(file.path(kok, "R", "module_saved_chats.R"),
                             warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  expect_true(grepl("grepl(tolower(search_term), tolower(meta$title), fixed = TRUE)",
                    kayitli, fixed = TRUE))
})

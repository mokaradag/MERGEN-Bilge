# ==============================================================================
# Dosya Yolu: tests/testthat/test-testthat-encoding-guard-contract.R
# Açıklama: Test oturumu encoding koruması. Uygulama çalıştırılmış bir R
#           oturumunda global.R options(encoding = "UTF-8") bırakır; Windows
#           CP1254 yerel kod sayfasında bu durum testlerdeki
#           readLines(..., encoding = "UTF-8") okumalarını çift kod çözümüne
#           sokar ve grepl çağrıları satır başına "invalid UTF-8" uyarısı
#           üretir (VM'de görülen W seli). helper_bootstrap.R bu nedenle test
#           koşumunu native.enc varsayılanına sabitler; bu dosya o korumayı
#           ve okuma davranışını kilitler. DB/LLM/tarayıcı gerekmez.
# ==============================================================================

.enc_guard_read_bytes <- function(rel_path) {
  full_path <- file.path(resolve_repo_root_for_tests(), rel_path)
  size <- suppressWarnings(file.info(full_path)$size[1])
  if (is.na(size) || size <= 0) {
    # BOŞ DOSYA DA VACUOUS GEÇİRİR: bu dosyalardaki taramaların çoğu
    # `expect_false(grepl(...))` biçimindedir ve boş dize hepsini karşılar.
    stop(sprintf("Kaynak dosya BOŞ ya da okunamıyor: %s", full_path), call. = FALSE)
  }
  con <- file(full_path, open = "rb")
  on.exit(close(con), add = TRUE)
  raw_data <- readBin(con, what = "raw", n = size)
  txt <- suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
  )
  if (is.na(txt)) txt <- ""
  txt
}

testthat::test_that("helper_bootstrap test oturumunu native.enc varsayılanına sabitler", {
  txt <- .enc_guard_read_bytes("tests/testthat/helper_bootstrap.R")
  testthat::expect_true(nzchar(txt))
  testthat::expect_true(
    grepl('encoding = "native.enc"', txt, fixed = TRUE, useBytes = TRUE)
  )
  testthat::expect_true(
    grepl("withr::local_options", txt, fixed = TRUE, useBytes = TRUE)
  )
})

testthat::test_that("Türkçe içerikli runtime dosyası readLines+grepl uyarısız okunur", {
  # native.enc altında (taze oturum varsayılanı) çift kod çözümü oluşmaz.
  withr::local_options(list(encoding = "native.enc"))

  hedef <- file.path(resolve_repo_root_for_tests(), "R", "module_tts.R")
  satirlar <- readLines(hedef, warn = FALSE, encoding = "UTF-8")
  testthat::expect_true(length(satirlar) > 0)
  testthat::expect_identical(sum(!validUTF8(satirlar)), 0L)

  uyari_sayisi <- 0L
  withCallingHandlers(
    invisible(grepl("session", satirlar)),
    warning = function(w) {
      uyari_sayisi <<- uyari_sayisi + 1L
      invokeRestart("muffleWarning")
    }
  )
  testthat::expect_identical(uyari_sayisi, 0L)
})

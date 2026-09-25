# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-alias-template-behavior.R
# Açıklama: docs/templates/library_query_aliases_local.template.R şablonu
#           olduğu gibi kopyalandığında açılışı bozmayan BOŞ bir alias kaydı
#           üretmeli, örnekleri açıldığında ise üretimdeki alias bindirme
#           doğrulayıcısından hatasız geçmelidir. Şablon Windows VM'de
#           CP1254 yerelinde okunabilir kalmalıdır.
# ==============================================================================

.alias_sablon_yolu <- function() {
  file.path(resolve_repo_root_for_tests(), "docs", "templates", "library_query_aliases_local.template.R")
}

.alias_sablon_ortami <- function() {
  kok <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  for (dosya in c("helpers_pk_config.R", "helpers_pk_text_turkish.R",
                  "helpers_pk_query_meta_schema.R", "helpers_pk_query_meta_access.R",
                  "helpers_pk_query_meta_layers.R", "helpers_pk_query_meta.R")) {
    source(file.path(kok, "R", dosya), encoding = "UTF-8", local = env)
  }
  env
}

.alias_sablon_calistir <- function(satirlar) {
  env <- new.env(parent = globalenv())
  con <- textConnection(satirlar, encoding = "UTF-8")
  on.exit(close(con), add = TRUE)
  for (ifade in parse(con, keep.source = FALSE, encoding = "UTF-8")) eval(ifade, env)
  env$pk_query_aliases_local
}

.alias_sablon_satirlari <- function() {
  yol <- .alias_sablon_yolu()
  metin <- rawToChar(readBin(yol, what = "raw", n = file.info(yol)$size))
  Encoding(metin) <- "UTF-8"
  strsplit(metin, "\n", fixed = TRUE)[[1]]
}

test_that("alias şablonu CP1254'te temsil edilebilir ve olduğu gibi boş kayıt üretir", {
  satirlar <- .alias_sablon_satirlari()
  expect_false(anyNA(iconv(satirlar, from = "UTF-8", to = "WINDOWS-1254")))

  kayit <- .alias_sablon_calistir(satirlar)
  expect_identical(kayit, list())
})

test_that("açılan şablon örnekleri üretim alias doğrulayıcısından hatasız geçer", {
  skip_if_not_installed("stringi")
  satirlar <- .alias_sablon_satirlari()
  acik <- sub("^(\\s*)# (\"[^\"]+\"\\s*= c\\(.*)$", "\\1\\2", satirlar, perl = TRUE)
  acik <- sub("^(\\s*)# (list\\(sorgu = .*)$", "\\1\\2", acik, perl = TRUE)
  expect_gt(sum(acik != satirlar), 5L)

  kayit <- .alias_sablon_calistir(acik)
  expect_setequal(names(kayit), c("gen_00", "q042"))
  proje_adi <- enc2utf8(intToUtf8(c(0x50, 0x72, 0x6F, 0x6A, 0x65, 0x20, 0x41, 0x64, 0x0131)))
  expect_identical(unname(kayit$gen_00[[proje_adi]]["MKY"]), "Merkez Kampüs Yapım İşi")

  env <- .alias_sablon_ortami()
  meta <- list(
    gen_00 = list(column_meta = stats::setNames(
      list(list(role = "dimension"), list(role = "dimension")),
      names(kayit$gen_00)
    )),
    q042 = list(column_meta = stats::setNames(list(list(role = "dimension")), names(kayit$q042)))
  )
  sonuc <- env$pk_meta_apply_alias_overlay(meta, kayit)
  expect_identical(sonuc$errors, character(0))
  expect_identical(sonuc$meta$gen_00$column_meta[[proje_adi]]$alias_provenance, "local_overlay")
})

test_that("şablon yardımcısı adsız alias grubunu açık hatayla reddeder", {
  satirlar <- .alias_sablon_satirlari()
  bozuk <- sub("^(\\s*)# \"Altyap[^\"]*\"\\s*= (c\\(.*)$", "\\1\\2", satirlar, perl = TRUE)
  expect_error(.alias_sablon_calistir(bozuk), "alias_haritasi")
})

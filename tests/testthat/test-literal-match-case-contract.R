# ==============================================================================
# Dosya Yolu: tests/testthat/test-literal-match-case-contract.R
# Açıklama: Çalışma zamanı kodu `fixed = TRUE` ile `ignore.case = TRUE`
#           birleşimini KULLANMAZ. R bu birleşimde `ignore.case` bağımsız
#           değişkenini YOK SAYAR ve her çağrıda uyarı üretir: arama sessizce
#           büyük/küçük harf duyarlı olur (ör. Kayıtlı Söyleşiler başlık
#           aramasının eşleşme bulunamadığında devreye giren yedeği). Büyük/küçük
#           harf duyarsız düz eşleşme `tolower()` ile yapılmalıdır.
# ==============================================================================

# Ayrıştırılmış ifadelerde `fixed = TRUE` ve `ignore.case = TRUE` argümanlarını
# BİRLİKTE taşıyan çağrıları bulur. Satır satır tarama, argümanları ayrı
# satırlara bölünmüş bir çağrıyı göremezdi.
.lm_birlesik_cagrilar <- function(ifadeler) {
  dogru <- function(v) isTRUE(v) || identical(v, as.name("T"))
  bulunan <- character(0)
  yuru <- function(x) {
    if (!is.call(x) && !is.expression(x)) return(invisible(NULL))
    parcalar <- as.list(x)
    if (is.call(x)) {
      adlar <- names(parcalar) %||% rep("", length(parcalar))
      if ("fixed" %in% adlar && "ignore.case" %in% adlar &&
          dogru(parcalar[["fixed"]]) && dogru(parcalar[["ignore.case"]])) {
        bulunan <<- c(bulunan, paste(deparse(x[[1]]), collapse = ""))
      }
    }
    for (i in seq_along(parcalar)) {
      if (identical(parcalar[[i]], quote(expr = ))) next
      yuru(parcalar[[i]])
    }
    invisible(NULL)
  }
  yuru(ifadeler)
  bulunan
}

test_that("birleşim dedektörü çok satırlı çağrıyı da yakalar", {
  cok_satir <- parse(text = "f <- function(x) grepl('a', x,\n  fixed = TRUE,\n  ignore.case = TRUE)")
  expect_identical(.lm_birlesik_cagrilar(cok_satir), "grepl")
  expect_identical(.lm_birlesik_cagrilar(parse(text = "sub('a', 'b', x, ignore.case = T, fixed = T)")),
                   "sub")
  expect_length(.lm_birlesik_cagrilar(parse(text = "grepl('a', x[, 1], fixed = TRUE)")), 0L)
  expect_length(.lm_birlesik_cagrilar(parse(text = "grepl('a', x, ignore.case = TRUE)")), 0L)
})

test_that("çalışma zamanı kodunda fixed + ignore.case birleşimi yoktur", {
  kok <- resolve_repo_root_for_tests()
  dosyalar <- c(list.files(file.path(kok, "R"), pattern = "\\.R$", full.names = TRUE),
                file.path(kok, c("app.R", "global.R", "ui.R", "server.R")))
  dosyalar <- dosyalar[file.exists(dosyalar)]

  ihlaller <- character(0)
  for (f in dosyalar) {
    ifadeler <- tryCatch(parse(f, keep.source = FALSE, encoding = "UTF-8"),
                         error = function(e) NULL)
    expect_false(is.null(ifadeler), info = basename(f))
    isabet <- .lm_birlesik_cagrilar(ifadeler)
    if (length(isabet)) ihlaller <- c(ihlaller, sprintf("%s:%s", basename(f), isabet))
  }
  expect_identical(ihlaller, character(0))

  # Kayıtlı Söyleşiler başlık aramasının düz eşleşme yedeği harf duyarsızdır.
  kayitli <- paste(readLines(file.path(kok, "R", "module_saved_chats.R"),
                             warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  expect_true(grepl("grepl(tolower(search_term), tolower(meta$title), fixed = TRUE)",
                    kayitli, fixed = TRUE))
})

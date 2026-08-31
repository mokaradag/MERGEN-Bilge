# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-select-timeout-behavior.R
# Açıklama: Seçici HTTP zaman aşımı sözleşmesi (`pk_select_effective_timeout`).
#
# KORUNAN GERİLEME: v1 seçicisi TABAN zaman aşımını YALNIZCA bir async son
# tarihi yayımlanmışken kuruyordu. Sevk edilen varsayılanlar hiçbir son tarih
# yayımlamaz; asılı bir uç nokta ANA Shiny sürecini süresizce bloke edebiliyordu.
# Bu dosya "son tarih YOKKEN de sonlu bir taban vardır" iddiasını kilitler.
# ==============================================================================

.pk_sel_to_env <- function() {
  env <- new.env(parent = globalenv())
  kok <- resolve_repo_root_for_tests()
  # GERCEK PLANLAYICI YUKLENIR (PR #705 incelemesi, P3): `pk_sql_timeout_plan()`
  # testte YENIDEN TANIMLANINCA iddialar stub'in KENDI aritmetigini dogruluyor,
  # uretim kirpmasi bozulsa bile test yesil kaliyordu. Yalnizca
  # `pk_deadline_remaining_sec` stub'lanir (son tarih kaynagi).
  for (dosya in c("helpers_pk_config.R", "helpers_pk_async_cancel.R",
                  "helpers_pk_select_timeout.R")) {
    source(file.path(kok, "R", dosya), encoding = "UTF-8", local = env)
  }
  env
}

# `withr` `required_packages` ÜYESİ DEĞİLDİR ama bu dosyadaki beş test
# `withr::local_options()` çağırır. Muhafız YOKKEN paketin kurulu olmadığı
# bir koşucuda dosya ATLANMAK yerine HATA veriyor ve v1 seçici davranış
# testleri dâhil TÜM kapsam kayboluyordu.
testthat::skip_if_not_installed("withr")

test_that("son tarih YOKKEN bile sonlu bir taban zaman aşımı uygulanır", {
  env <- .pk_sel_to_env()
  withr::local_options(list(mergen.pk.async.deadline_at = NULL))

  plan <- env$pk_select_effective_timeout()

  expect_true(isTRUE(plan$dispatch))
  expect_true(is.finite(plan$timeout_sec))
  expect_gt(plan$timeout_sec, 0L)
})

test_that("geçersiz/eksik taban SINIRSIZ demek değildir", {
  env <- .pk_sel_to_env()
  withr::local_options(list(mergen.pk.async.deadline_at = NULL))

  for (ham in list(NA_integer_, "abc", -5L, 0L, character(0))) {
    plan <- env$pk_select_effective_timeout(base_sec = ham)
    expect_true(is.finite(plan$timeout_sec))
    expect_gte(plan$timeout_sec, 1L)
  }
})

test_that("açık taban değeri korunur", {
  env <- .pk_sel_to_env()
  withr::local_options(list(mergen.pk.async.deadline_at = NULL))

  plan <- env$pk_select_effective_timeout(base_sec = 17L)
  expect_identical(plan$timeout_sec, 17L)
})

test_that("kalan bütçe tabanı DARALTIR, genişletmez", {
  env <- .pk_sel_to_env()
  # Yalnizca KALAN BUTCE kaynagi stub'lanir; kirpmayi URETIM planlayicisi yapar.
  env$pk_deadline_remaining_sec <- function(x) 3
  withr::local_options(list(mergen.pk.async.deadline_at = Sys.time() + 3))

  plan <- env$pk_select_effective_timeout(base_sec = 60L)
  expect_identical(as.integer(plan$timeout_sec), 3L)

  # Kalan bütçe tabandan BÜYÜKKEN taban korunur.
  env$pk_deadline_remaining_sec <- function(x) 900
  plan <- env$pk_select_effective_timeout(base_sec = 60L)
  expect_identical(as.integer(plan$timeout_sec), 60L)
})

test_that("bütçe tükendiğinde istek HİÇ gönderilmez", {
  env <- .pk_sel_to_env()
  # ÜRETİM PLANLAYICISI SINANIR: `.pk_sel_to_env()` `R/helpers_pk_async_cancel.R`
  # dosyasını yükler ve `pk_sql_timeout_plan()` ORADA tanımlıdır. Test-yerel bir
  # planlayıcıyla değiştirmek, sınanmak istenen ÜRETİM zaman aşımı mantığını
  # devre dışı bırakıyordu.
  env$pk_deadline_remaining_sec <- function(x) 0.4
  withr::local_options(list(mergen.pk.async.deadline_at = Sys.time()))

  plan <- env$pk_select_effective_timeout(base_sec = 60L)
  expect_false(isTRUE(plan$dispatch))
  # Tükenmiş bütçe SIFIR zaman aşımı demektir (yuvarlanmış kalan < 1 sn).
  expect_identical(as.integer(plan$timeout_sec), 0L)
})

test_that("v1 ve v2 seçicileri AYNI yardımcıyı çağırır", {
  kok <- resolve_repo_root_for_tests()
  oku <- function(rel) {
    yol <- file.path(kok, rel)
    ham <- readBin(yol, what = "raw", n = file.info(yol)$size)
    iconv(rawToChar(ham), from = "UTF-8", to = "UTF-8", sub = "byte")
  }

  for (rel in c("R/helpers_pk_analysis_ai_selector.R",
                "R/helpers_pk_query_selection_ai.R")) {
    expect_true(
      grepl("pk_select_effective_timeout(", oku(rel), fixed = TRUE),
      info = sprintf("%s ortak zaman aşımı yardımcısını çağırmalıdır.", rel)
    )
  }

  # v1 hattı artık zaman aşımını KOŞULLU kurmaz: `request_timeout_sec` ataması
  # `pk_select_effective_timeout()` sonucundan gelir.
  v1 <- oku("R/helpers_pk_analysis_ai_selector.R")
  expect_false(
    grepl("if (is.finite(remaining_sec))", v1, fixed = TRUE),
    info = "v1 seçicisi taban zaman aşımını KOŞULLU kurmamalıdır."
  )
})

test_that("v1 seçicisi son tarih YOKKEN de SONLU zaman aşımı gönderir", {
  # KAYNAK TARAMASI YETMEZ: yukarıdaki iddialar tek bir LİTERALİN yokluğuna
  # bakar. Koşullu zaman aşımı farklı biçimle ya da yeniden adlandırılmış bir
  # değişkenle geri gelirse (`if (is.finite(kalan))`) tarama YEŞİL kalırdı.
  # Bu test DAVRANIŞI ölçer: yayınlanmış son tarih yokken bile
  # `call_local_llm()` SONLU ve POZİTİF bir `request_timeout_sec` görmelidir.
  kok <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a

  for (dosya in c("helpers_pk_config.R", "helpers_pk_safe_errors.R",
                  "helpers_pk_select_timeout.R",
                  "helpers_pk_analysis_ai_selector.R")) {
    source(file.path(kok, "R", dosya), encoding = "UTF-8", local = env)
  }

  # Asgari üretim yüzeyi taklit edilir: ağ, DB, LLM veya oturum GEREKMEZ.
  env$api_config <- list(local_models = "sentetik-model")
  env$resolve_local_llm_credentials <- function(model) {
    list(default_api_key = "sentetik-anahtar")
  }

  yakalanan <- new.env(parent = emptyenv())
  env$call_local_llm <- function(messages, config) {
    yakalanan$timeout <- config$request_timeout_sec
    list(content = "{\"match_id\": 1, \"confidence\": 90}")
  }

  kitaplik <- list(list(id = "q001", name = "Sentetik", description = "Sentetik"))

  # SON TARİH YAYINLANMAMIŞ: bütçe kurulmamış yolun ta kendisi.
  eski <- options(mergen.pk.async.deadline_at = NULL)
  on.exit(options(eski), add = TRUE)

  invisible(utils::capture.output(
    env$find_best_query_with_ai("sentetik soru", kitaplik, NULL)
  ))

  expect_false(is.null(yakalanan$timeout),
               info = "v1 seçicisi `request_timeout_sec` ATAMALIDIR.")
  timeout <- suppressWarnings(as.numeric(yakalanan$timeout)[1])
  expect_true(is.finite(timeout),
              info = "Son tarih yokken zaman aşımı SONSUZ/NA olamaz.")
  expect_gt(timeout, 0)
})

test_that("v1 seçicisi ATOMİK / ADSIZ JSON yanıtında HATA fırlatmaz", {
  # `jsonlite::fromJSON("5", simplifyVector = FALSE)` ATOMİK bir değer,
  # `fromJSON("[1,2]", ...)` ADSIZ bir liste döndürür. `parsed$match_id`
  # ilkinde "$ operator is invalid for atomic vectors" ile düşüyordu;
  # sözleşme ihlali HATA DEĞİL, "eşleşme yok" olmalıdır.
  kok <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a

  for (dosya in c("helpers_pk_config.R", "helpers_pk_safe_errors.R",
                  "helpers_pk_select_timeout.R",
                  "helpers_pk_analysis_ai_selector.R")) {
    source(file.path(kok, "R", dosya), encoding = "UTF-8", local = env)
  }

  env$api_config <- list(local_models = "sentetik-model")
  env$resolve_local_llm_credentials <- function(model) {
    list(default_api_key = "sentetik-anahtar")
  }

  kitaplik <- list(list(id = "q001", name = "Sentetik", description = "Sentetik"))

  for (govde in c("5", "[1,2]", "\"metin\"", "null")) {
    env$call_local_llm <- function(messages, config) list(content = govde)
    sonuc <- NULL
    invisible(utils::capture.output(
      expect_no_error(
        sonuc <- env$find_best_query_with_ai("sentetik soru", kitaplik, NULL)
      )
    ))
    expect_null(sonuc, info = sprintf("Sözleşme dışı yanıt eşleşme üretmemeli: %s", govde))
  }
})

test_that("`fixed = TRUE` yerine koyma metni LİTERALDİR (ters bölü ikilenmez)", {
  # PR incelemesinde "fixed = TRUE yerine koyma metnini de işler" iddiası
  # yükseltildi; bu YANLIŞTIR ve önerilen düzeltme çıktıya FAZLADAN ters bölü
  # ekleyerek gerçek bir kusur yaratırdı. Semantik burada SABİTLENİR ki
  # gelecekte yanlış yönde "düzeltilmesin".
  expect_identical(gsub("|", "\\|", "a|b", fixed = TRUE), "a\\|b")
  expect_identical(gsub("\\", "\\\\", "a\\b", fixed = TRUE), "a\\\\b")
  # `\1` yerine koyma metninde GERİ REFERANS DEĞİLDİR.
  expect_identical(sub("X", "\\1", "aXb", fixed = TRUE), "a\\1b")
  # Karşıtlık: regex kipinde yerine koyma metni İŞLENİR.
  expect_identical(gsub("a", "\\|", "a", fixed = FALSE), "|")
})

test_that("`.pk_select_inline()` boru/satır sonu davranışı SABİTLENİR", {
  # Yukarıdaki blok base R semantiğini sabitliyor ama ÜRETİM yardımcısını hiç
  # çağırmıyordu (PR #705 incelemesi). Gerileme burada doğrudan yakalanır.
  env <- new.env(parent = globalenv())
  kok <- resolve_repo_root_for_tests()
  env$`%||%` <- function(x, y) if (is.null(x)) y else x
  source(file.path(kok, "R", "helpers_pk_query_selection_payload.R"),
         encoding = "UTF-8", local = env)

  # Boru, Geçiş A satır ayırıcısıdır; eğik çizgiye çevrilir.
  expect_identical(env$.pk_select_inline("a|b"), "a/b")
  # Satır sonu/sekme tek boşluğa iner ve baştaki/sondaki boşluk kırpılır.
  expect_identical(env$.pk_select_inline("  a\nb\tc  "), "a b c")
  # Ters bölü LİTERAL kalır: ikilenmez, kaçış olarak yorumlanmaz.
  expect_identical(env$.pk_select_inline("a\\b"), "a\\b")
  # `NA`/boş girdi düz "NA" sızdırmaz.
  expect_identical(env$.pk_select_inline(NA_character_), "")
  expect_identical(env$.pk_select_inline(character(0)), "")
})

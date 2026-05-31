# ==============================================================================
# Dosya Yolu: tests/testthat/test-db-user-encoding-normalization-behavior.R
# Açıklama: MB_Users / SSO DB yazım sınırındaki görünür-vs-teknik metin
#           normalizasyonunun DAVRANIŞSAL testleri. Gerçek üretim fonksiyonları
#           çağrılır:
#             - normalize_sso_claims_for_db (R/helpers_db_user_encoding.R)
#             - normalize_db_visible_value / normalize_db_technical_value
#             - db_visible_text_has_mojibake (R/helpers_db_encoding.R)
#           Türkçe metin bütünlüğü bu deponun 1 numaralı kuralıdır: görünür
#           alanlar mojibake onarılır, teknik kimlik alanları onarılmaz.
#           DBI/ODBC/canlı DB GEREKMEZ; bu yardımcılar saf metin sınırıdır.
#           Çekirdek normalize_db_value/normalize_db_params davranışı zaten
#           test-db-normalization-contract.R içinde kapsanır; burada tekrar edilmez.
# ==============================================================================

.dbuserenc_source_once <- function() {
  root <- resolve_repo_root_for_tests()

  # utils_common.R'deki ile birebir aynı küçük operatör; yalnızca izole
  # çalıştırmalarda eksikse tanımlanır (db_client_encoding_is_utf8 çalışma
  # anında kullanır). Üretim tanımıyla aynı tutulur.
  if (!exists("%||%", inherits = TRUE)) {
    assign("%||%", function(a, b) if (is.null(a)) b else a, envir = globalenv())
  }
  if (!exists("normalize_text_utf8", mode = "function", inherits = TRUE)) {
    source(file.path(root, "R", "utils_text_encoding.R"),
           encoding = "UTF-8", local = globalenv())
  }
  if (!exists("db_unicode_escape_for_client_encoding", mode = "function", inherits = TRUE)) {
    source(file.path(root, "R", "helpers_db_unicode_escape.R"),
           encoding = "UTF-8", local = globalenv())
  }
  if (!exists("normalize_db_visible_value", mode = "function", inherits = TRUE)) {
    source(file.path(root, "R", "helpers_db_encoding.R"),
           encoding = "UTF-8", local = globalenv())
  }
  if (!exists("normalize_sso_claims_for_db", mode = "function", inherits = TRUE)) {
    source(file.path(root, "R", "helpers_db_user_encoding.R"),
           encoding = "UTF-8", local = globalenv())
  }
  invisible(TRUE)
}

# ------------------------------------------------------------------------------
# normalize_db_visible_value
# ------------------------------------------------------------------------------
testthat::test_that("normalize_db_visible_value NULL ve karakter-olmayanı değiştirmez", {
  .dbuserenc_source_once()
  testthat::expect_null(normalize_db_visible_value(NULL))
  testthat::expect_identical(normalize_db_visible_value(42L), 42L)
  testthat::expect_identical(normalize_db_visible_value(TRUE), TRUE)
})

testthat::test_that("normalize_db_visible_value görünür Türkçe mojibake'yi onarır, temizi korur", {
  .dbuserenc_source_once()
  testthat::expect_identical(normalize_db_visible_value("TÃ¼rkiye"), "Türkiye")
  testthat::expect_identical(normalize_db_visible_value("NasÄ±l"), "Nasıl")
  # Zaten temiz Türkçe metin değişmeden kalmalı.
  testthat::expect_identical(
    enc2utf8(normalize_db_visible_value("İş Dağılımı")),
    enc2utf8("İş Dağılımı")
  )
  # NA korunur ve uyarı üretilmez (strict runner).
  donen <- NULL
  uyarildi <- FALSE
  withCallingHandlers(
    donen <- normalize_db_visible_value(c("teÅŸekkÃ¼r", NA)),
    warning = function(w) { uyarildi <<- TRUE; invokeRestart("muffleWarning") }
  )
  testthat::expect_false(uyarildi)
  testthat::expect_identical(donen[1], "teşekkür")
  testthat::expect_true(is.na(donen[2]))
})

# ------------------------------------------------------------------------------
# normalize_db_technical_value
# ------------------------------------------------------------------------------
testthat::test_that("normalize_db_technical_value mojibake'yi ONARMAZ ama UTF-8 işaretler", {
  .dbuserenc_source_once()
  # Teknik alanlar (kullanıcı adı, email, sicil...) onarılmamalı; ham içerik korunur.
  testthat::expect_identical(normalize_db_technical_value("TÃ¼rkiye"), "TÃ¼rkiye")
  testthat::expect_identical(normalize_db_technical_value("kullanici01"), "kullanici01")
  testthat::expect_identical(Encoding(normalize_db_technical_value("TÃ¼rkiye")), "UTF-8")
  # NULL / sayısal değişmez.
  testthat::expect_null(normalize_db_technical_value(NULL))
  testthat::expect_identical(normalize_db_technical_value(1001L), 1001L)
})

# ------------------------------------------------------------------------------
# normalize_sso_claims_for_db
# ------------------------------------------------------------------------------
testthat::test_that("normalize_sso_claims_for_db NULL / liste-olmayan girdiyi değiştirmeden döndürür", {
  .dbuserenc_source_once()
  testthat::expect_null(normalize_sso_claims_for_db(NULL))
  testthat::expect_identical(normalize_sso_claims_for_db("metin"), "metin")
  testthat::expect_identical(normalize_sso_claims_for_db(123L), 123L)
})

testthat::test_that("normalize_sso_claims_for_db görünür alanları onarır, teknik alanları onarmaz", {
  .dbuserenc_source_once()
  claims <- list(
    full_name  = "Ã‡aÄŸrÄ± Ã–ztÃ¼rk",   # görünür -> onarılmalı
    first_name = "Ã‡aÄŸrÄ±",            # görünür -> onarılmalı
    department = "BiliÅŸim",            # görünür -> onarılmalı
    username   = "cÃ¶ztÃ¼rk",          # teknik  -> onarılmamalı
    email      = "test@kurum.local",   # teknik  -> aynen
    sicil      = "TÃ¼rk123"            # teknik  -> onarılmamalı (ham kalır)
  )

  donen <- normalize_sso_claims_for_db(claims)

  # Görünür alanlar mojibake'den arınmış olmalı.
  testthat::expect_identical(donen$full_name, "Çağrı Öztürk")
  testthat::expect_identical(donen$first_name, "Çağrı")
  testthat::expect_identical(donen$department, "Bilişim")

  # Teknik alanlar onarılmadan korunmalı.
  testthat::expect_identical(donen$username, "cÃ¶ztÃ¼rk")
  testthat::expect_identical(donen$email, "test@kurum.local")
  testthat::expect_identical(donen$sicil, "TÃ¼rk123")
})

testthat::test_that("normalize_sso_claims_for_db bilinmeyen alanları değiştirmez ve sayısal teknik alanları korur", {
  .dbuserenc_source_once()
  claims <- list(
    full_name = "Ã–mer",     # görünür
    rastgele  = "Ã§Ã¶pdeger", # bilinmeyen alan -> dokunulmaz
    token_exp = 1719000000,   # teknik ama sayısal -> aynen
    token_iat = 1718990000
  )

  donen <- normalize_sso_claims_for_db(claims)

  testthat::expect_identical(donen$full_name, "Ömer")
  # Bilinmeyen alan ne görünür ne teknik listesinde; aynen kalmalı.
  testthat::expect_identical(donen$rastgele, "Ã§Ã¶pdeger")
  # Sayısal teknik alanlar normalize_db_technical_value tarafından aynen döner.
  testthat::expect_identical(donen$token_exp, 1719000000)
  testthat::expect_identical(donen$token_iat, 1718990000)
})

# ------------------------------------------------------------------------------
# db_visible_text_has_mojibake
# ------------------------------------------------------------------------------
testthat::test_that("db_visible_text_has_mojibake boş/NULL/temiz Türkçe için FALSE döndürür", {
  .dbuserenc_source_once()
  testthat::expect_false(db_visible_text_has_mojibake(NULL))
  testthat::expect_false(db_visible_text_has_mojibake(character(0)))
  testthat::expect_false(db_visible_text_has_mojibake(""))
  # Temiz Türkçe karakterler (tek kod noktası) mojibake DEĞİLDİR.
  testthat::expect_false(db_visible_text_has_mojibake("İşte temiz Türkçe: çğıöşü ÇĞİÖŞÜ"))
})

testthat::test_that("db_visible_text_has_mojibake bilinen Türkçe mojibake dizilerini yakalar", {
  .dbuserenc_source_once()
  testthat::expect_true(db_visible_text_has_mojibake("TÃ¼rkiye"))
  testthat::expect_true(db_visible_text_has_mojibake("NasÄ±l gidiyor?"))
  testthat::expect_true(db_visible_text_has_mojibake("yardÄ±mcÄ± olabilir miyim"))
  testthat::expect_true(db_visible_text_has_mojibake("baÅŸkent"))
  # Vektör girdi: tek bir bozuk öğe bile TRUE döndürmeli (collapse sonrası).
  testthat::expect_true(db_visible_text_has_mojibake(c("temiz satir", "teÅŸekkÃ¼r ederim")))
})

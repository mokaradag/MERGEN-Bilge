# ==============================================================================
# Dosya Yolu: tests/testthat/test-tool-background-settings-behavior.R
# Açıklama: R/module_tool_background_settings.R içindeki saf ayar yardımcılarının
#           DAVRANIŞSAL testleri. Bu modül daha önce hiçbir test tarafından
#           çağrılmıyordu.
#
#           mb_tool_bg_coerce_enabled() mantıksal/numerik/karakter ve eksik
#           değerleri TOLERANSLI biçimde boole'a çevirir (followup bayrağı
#           çözümlemesine benzer). mb_tool_bg_apply_to_client() istemciye
#           custom message gönderir ve session yoksa/erişilemezse sessizce geçer.
#           Ağ/DB/Shiny sunucusu GEREKMEZ.
# ==============================================================================

.source_tool_bg_for_test <- function() {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())

  source(
    file.path(repo_root, "R", "module_tool_background_settings.R"),
    encoding = "UTF-8",
    local = env
  )

  env
}

testthat::test_that("mb_tool_bg_default_enabled varsayılan olarak TRUE döndürür", {
  env <- .source_tool_bg_for_test()
  testthat::expect_true(env$mb_tool_bg_default_enabled())
})

testthat::test_that("mb_tool_bg_coerce_enabled mantıksal değerleri olduğu gibi çözer", {
  env <- .source_tool_bg_for_test()
  testthat::expect_true(env$mb_tool_bg_coerce_enabled(TRUE))
  testthat::expect_false(env$mb_tool_bg_coerce_enabled(FALSE))
})

testthat::test_that("mb_tool_bg_coerce_enabled numerik değerleri pozitiflik ile çözer", {
  env <- .source_tool_bg_for_test()
  testthat::expect_true(env$mb_tool_bg_coerce_enabled(1L))
  testthat::expect_true(env$mb_tool_bg_coerce_enabled(2.5))
  testthat::expect_false(env$mb_tool_bg_coerce_enabled(0L))
  testthat::expect_false(env$mb_tool_bg_coerce_enabled(-3))
})

testthat::test_that("mb_tool_bg_coerce_enabled metin truthy/falsy değerleri büyük-küçük harf duyarsız çözer", {
  env <- .source_tool_bg_for_test()

  for (truthy in c("true", "TRUE", "  True ", "1", "yes", "YES", "on", "On")) {
    testthat::expect_true(
      env$mb_tool_bg_coerce_enabled(truthy),
      info = sprintf("'%s' truthy çözülmeli", truthy)
    )
  }
  for (falsy in c("false", "FALSE", " off ", "0", "no", "NO", "Off")) {
    testthat::expect_false(
      env$mb_tool_bg_coerce_enabled(falsy),
      info = sprintf("'%s' falsy çözülmeli", falsy)
    )
  }
})

testthat::test_that("mb_tool_bg_coerce_enabled eksik/geçersiz girdide varsayılana düşer", {
  env <- .source_tool_bg_for_test()

  # NULL, boş ve NA varsayılana düşer (varsayılan TRUE).
  testthat::expect_true(env$mb_tool_bg_coerce_enabled(NULL))
  testthat::expect_true(env$mb_tool_bg_coerce_enabled(character(0)))
  testthat::expect_true(env$mb_tool_bg_coerce_enabled(NA))

  # Açık default = FALSE verildiğinde eksik girdi FALSE'a düşer.
  testthat::expect_false(env$mb_tool_bg_coerce_enabled(NULL, default = FALSE))
  testthat::expect_false(env$mb_tool_bg_coerce_enabled(NA, default = FALSE))
  # Tanınmayan metin de varsayılana düşer.
  testthat::expect_false(env$mb_tool_bg_coerce_enabled("belki", default = FALSE))
  testthat::expect_true(env$mb_tool_bg_coerce_enabled("belki", default = TRUE))
})

testthat::test_that("mb_tool_bg_coerce_enabled yalnızca ilk elemanı dikkate alır", {
  env <- .source_tool_bg_for_test()
  # value[[1]] kullanılır; vektörün ilk elemanı belirleyicidir.
  testthat::expect_true(env$mb_tool_bg_coerce_enabled(c(TRUE, FALSE)))
  testthat::expect_false(env$mb_tool_bg_coerce_enabled(c(0L, 5L)))
})

testthat::test_that("mb_tool_bg_apply_to_client custom message gönderir ve flag'i boole'a indirger", {
  env <- .source_tool_bg_for_test()

  kaydedilen <- new.env()
  fake_session <- list(
    sendCustomMessage = function(type, message) {
      kaydedilen$type <- type
      kaydedilen$message <- message
      invisible(NULL)
    }
  )

  env$mb_tool_bg_apply_to_client(fake_session, "true")  # truthy-olmayan değer boole'a indirgenmeli

  testthat::expect_identical(kaydedilen$type, "toggleToolBackgrounds")
  # isTRUE("true") FALSE olduğu için flag FALSE olmalı (boole indirgeme davranışı).
  testthat::expect_false(kaydedilen$message$enabled)

  env$mb_tool_bg_apply_to_client(fake_session, TRUE)
  testthat::expect_true(kaydedilen$message$enabled)
})

testthat::test_that("mb_tool_bg_apply_to_client session yoksa veya erişilemezse sessizce geçer", {
  env <- .source_tool_bg_for_test()

  # NULL session: hata fırlatmadan invisible(NULL) döner.
  testthat::expect_silent(env$mb_tool_bg_apply_to_client(NULL, TRUE))

  # sendCustomMessage hata fırlatırsa yine sessiz geçilmeli (SSO bağlanma anı).
  patlayan_session <- list(
    sendCustomMessage = function(type, message) stop("session henüz hazır değil")
  )
  testthat::expect_silent(env$mb_tool_bg_apply_to_client(patlayan_session, TRUE))
})

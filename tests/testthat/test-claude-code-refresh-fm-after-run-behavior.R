# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-refresh-fm-after-run-behavior.R
# Açıklama: helpers_claude_code_run_lifecycle.R içindeki
#           cc_refresh_user_file_manager_after_run davranışını doğrular. Bu yardımcı
#           Bilge Yolaç çalışması bittikten sonra Dosya Yönetimi tablosunu üretilen
#           dosyalar için tazeler. Oturum/userData/file_manager_data/refresh
#           fonksiyonu eksikse güvenli FALSE döner; refresh varsa
#           "bilge_yolac_generated" tetikleyicisiyle çağrılır ve hata yutulur.
#           Gerçek DB/dosya yok; çevrimdışı ve deterministik.
# ==============================================================================

# Türkçe yorum: helpers_claude_code_run_lifecycle.R'yi yalıtılmış ortama yükler.
# log_warn / CLAUDE_CODE_LOG_PREFIX env içine stub edilir.
.ccRefreshEnv <- function() {
  env <- new.env(parent = globalenv())
  kok <- resolve_repo_root_for_tests()
  source(file.path(kok, "R", "helpers_claude_code_run_lifecycle.R"), encoding = "UTF-8", local = env)
  env$CLAUDE_CODE_LOG_PREFIX <- "[CC]"
  env$log_warn <- function(...) invisible(NULL)
  env
}

test_that("cc_refresh_user_file_manager_after_run NULL oturumda FALSE döner", {
  env <- .ccRefreshEnv()
  expect_false(env$cc_refresh_user_file_manager_after_run(NULL))
})

test_that("cc_refresh_user_file_manager_after_run userData yoksa FALSE döner", {
  env <- .ccRefreshEnv()
  expect_false(env$cc_refresh_user_file_manager_after_run(list(userData = NULL)))
})

test_that("cc_refresh_user_file_manager_after_run file_manager_data yoksa FALSE döner", {
  env <- .ccRefreshEnv()
  session <- list(userData = list(file_manager_data = NULL))
  expect_false(env$cc_refresh_user_file_manager_after_run(session))
})

test_that("cc_refresh_user_file_manager_after_run refresh fonksiyon değilse FALSE döner", {
  env <- .ccRefreshEnv()
  session <- list(userData = list(file_manager_data = list(refresh_persisted_files = "fonksiyon değil")))
  expect_false(env$cc_refresh_user_file_manager_after_run(session))
})

test_that("cc_refresh_user_file_manager_after_run refresh'i 'bilge_yolac_generated' ile çağırır", {
  env <- .ccRefreshEnv()
  yakalanan <- new.env(parent = emptyenv())
  session <- list(userData = list(file_manager_data = list(
    refresh_persisted_files = function(trigger) { yakalanan$trigger <- trigger; invisible(NULL) }
  )))
  res <- env$cc_refresh_user_file_manager_after_run(session)
  expect_true(res)
  expect_identical(yakalanan$trigger, "bilge_yolac_generated")
})

test_that("cc_refresh_user_file_manager_after_run refresh hatasını yutar ve yine TRUE döner", {
  env <- .ccRefreshEnv()
  uyari <- new.env(parent = emptyenv()); uyari$cagrildi <- FALSE
  env$log_warn <- function(...) { uyari$cagrildi <- TRUE; invisible(NULL) }
  session <- list(userData = list(file_manager_data = list(
    refresh_persisted_files = function(trigger) stop("tazeleme çöktü")
  )))
  res <- env$cc_refresh_user_file_manager_after_run(session)
  # Türkçe yorum: hata yakalanır, log_warn çağrılır, fonksiyon yine de TRUE döner
  expect_true(res)
  expect_true(uyari$cagrildi)
})

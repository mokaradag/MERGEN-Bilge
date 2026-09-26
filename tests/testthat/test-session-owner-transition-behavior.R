# ==============================================================================
# Dosya Yolu: tests/testthat/test-session-owner-transition-behavior.R
# Açıklama: Aynı Shiny oturumunda kullanıcı değişimi (A -> B) ve kimlik kaybı.
#           A'nın dosya kayıt defteri, özetleri ve kişisel API anahtarı B'ye
#           kalmaz; kayıtlı kancalar (süren özet işinin iptali) çalışır ve
#           reaktif kimlik sinyali artar.
# ==============================================================================

.owner_env <- function() {
  env <- new.env(parent = globalenv())
  kok <- resolve_repo_root_for_tests()
  source(file.path(kok, "R", "utils_session_cleanup.R"), encoding = "UTF-8", local = env)
  source(file.path(kok, "R", "helpers_user_session_identity.R"), encoding = "UTF-8", local = env)
  env
}

.owner_session <- function() {
  list(userData = new.env(parent = emptyenv()))
}

test_that("A -> B geçişi kullanıcıya bağlı depoları ve kişisel anahtarı temizler", {
  env <- .owner_env()
  oturum <- .owner_session()
  veri <- env$make_user_session_data_accessors(oturum)
  veri$write_identity(list(username = "a"), 7L, list(), TRUE, "keycloak")
  oturum$userData$current_session_files <- list(a.txt = list(path = "/k/user_7/a.txt"))
  oturum$userData$file_summaries <- list(a.txt = "ozet")
  oturum$userData$ai_api_key <- "anahtar-a"

  # Aynı kullanıcı profil tazelemesi depoları silmez.
  veri$write_identity(list(username = "a"), 7L, list(), TRUE, "keycloak")
  expect_length(oturum$userData$current_session_files, 1L)
  expect_identical(oturum$userData$ai_api_key, "anahtar-a")

  veri$write_identity(list(username = "b"), 8L, list(), TRUE, "keycloak")
  expect_length(oturum$userData$current_session_files, 0L)
  expect_length(oturum$userData$file_summaries, 0L)
  expect_null(oturum$userData$ai_api_key)
})

test_that("kimlik kaybı kancaları çalıştırır; A -> 0 -> B de sahip değişimi sayılır", {
  env <- .owner_env()
  oturum <- .owner_session()
  veri <- env$make_user_session_data_accessors(oturum)
  nedenler <- character(0)
  kaldir <- env$mergen_session_on_owner_change(oturum, function(neden) nedenler <<- c(nedenler, neden))

  veri$write_identity(list(username = "a"), 7L, list(), TRUE, "keycloak")
  oturum$userData$current_session_files <- list(a.txt = list(path = "/k/a.txt"))
  veri$set_auth_placeholder()
  expect_identical(nedenler, "kimlik_kaybi")
  # Kimlik kaybında aynı kullanıcı dönebilir; dosyalar korunur.
  expect_length(oturum$userData$current_session_files, 1L)

  veri$write_identity(list(username = "b"), 8L, list(), TRUE, "keycloak")
  expect_identical(nedenler, c("kimlik_kaybi", "sahip_degisti"))
  expect_length(oturum$userData$current_session_files, 0L)

  kaldir()
  veri$write_identity(list(username = "a"), 7L, list(), TRUE, "keycloak")
  expect_length(nedenler, 2L)
})

test_that("reaktif kimlik sinyali yalnız kimlik değişince artar", {
  env <- .owner_env()
  oturum <- .owner_session()
  veri <- env$make_user_session_data_accessors(oturum)
  sinyal <- env$mergen_session_identity_signal(oturum)
  veri$write_identity(list(username = "a"), 7L, list(), TRUE, "keycloak")
  expect_identical(shiny::isolate(sinyal()), 1L)
  veri$write_identity(list(username = "a"), 7L, list(), TRUE, "keycloak")
  expect_identical(shiny::isolate(sinyal()), 1L)
  veri$set_auth_placeholder()
  expect_identical(shiny::isolate(sinyal()), 2L)
  # Oturum ortamı olmayan çağıran için sabit sinyal döner.
  expect_identical(env$mergen_session_identity_signal(list())(), 0L)
})

# ==============================================================================
# Dosya Yolu: tests/testthat/test-update-sso-fields-behavior.R
# Açıklama: update_sso_fields (helpers_db_user_encoding.R) SSO/MB_Users yazım
#           sınırı davranışsal testleri. Var olan kolonlara göre UPDATE SET
#           parçaları, görünür/teknik normalizasyon ayrımı, SonGirisKaynagi
#           sabiti ve WHERE UserID parametresi doğrulanır. DBI taklit edilir;
#           gerçek SQL Server/DB/ağ GEREKMEZ.
# ==============================================================================

# update_sso_fields, normalize_db_visible_value/technical_value (helpers_db_encoding)
# ve normalize_sso_claims_for_db'ye bağlıdır; izole koşum için zinciri yükleriz.
.sso_fields_env <- function(existing_cols) {
  env <- new.env(parent = globalenv())
  for (f in c("utils_text_encoding.R", "helpers_db_unicode_escape.R",
              "helpers_db_encoding.R", "helpers_db_user_encoding.R")) {
    source(file.path(resolve_repo_root_for_tests(), "R", f), encoding = "UTF-8", local = env)
  }
  cap <- new.env()
  cap$update_query <- NULL
  cap$params <- NULL
  cap$execute_calls <- 0L

  env$dbGetQuery <- function(conn, query, ...) {
    data.frame(COLUMN_NAME = existing_cols, stringsAsFactors = FALSE)
  }
  env$dbExecute <- function(conn, query, params = NULL, ...) {
    cap$execute_calls <- cap$execute_calls + 1L
    cap$update_query <- query
    cap$params <- params
    1L
  }
  # normalize_db_params'ı kimlik yap ki ham parametreleri okuyabilelim.
  env$normalize_db_params <- function(x) x
  env$log_warn <- function(...) invisible(NULL)

  list(env = env, cap = cap)
}

testthat::test_that("update_sso_fields hiç kolon yoksa UPDATE çalıştırmaz", {
  fix <- .sso_fields_env(existing_cols = character(0))
  fix$env$update_sso_fields("CONN", 42L, list(sicil = "12345", email = "a@b.com"))
  testthat::expect_identical(fix$cap$execute_calls, 0L)
})

testthat::test_that("update_sso_fields var olan kolonlar ve eşleşen claim'ler için UPDATE üretir", {
  fix <- .sso_fields_env(existing_cols = c("Sicil", "Email", "Departman", "SonGirisKaynagi"))

  # Departman DB kolonu, claim anahtarı 'department' (İngilizce) ile beslenir.
  turkce_departman <- intToUtf8(c(66, 105, 108, 103, 105, 32, 304, 351, 108, 101, 109)) # "Bilgi İşlem" benzeri
  fix$env$update_sso_fields(
    "CONN", 77L,
    list(sicil = "12345", email = "kullanici@kurum.local", department = turkce_departman)
  )

  testthat::expect_identical(fix$cap$execute_calls, 1L)
  q <- fix$cap$update_query
  testthat::expect_true(grepl("UPDATE MB_Users SET", q, fixed = TRUE))
  testthat::expect_true(grepl("Sicil = ?", q, fixed = TRUE))
  testthat::expect_true(grepl("Email = ?", q, fixed = TRUE))
  testthat::expect_true(grepl("Departman = ?", q, fixed = TRUE))
  # SonGirisKaynagi kolonu varsa her zaman eklenir.
  testthat::expect_true(grepl("SonGirisKaynagi = ?", q, fixed = TRUE))
  testthat::expect_true(grepl("WHERE UserID = ?", q, fixed = TRUE))

  # Parametreler: Sicil, Email, Departman, SonGirisKaynagi, UserID = 5 adet.
  testthat::expect_length(fix$cap$params, 5L)
  # Son parametre user_id olmalı.
  testthat::expect_identical(fix$cap$params[[5]], 77L)
  # SonGirisKaynagi değeri sabit "keycloak".
  testthat::expect_identical(as.character(fix$cap$params[[4]]), "keycloak")
})

testthat::test_that("update_sso_fields yalnızca var olan kolonlar için SET parçası ekler", {
  # Sadece Email kolonu var; Sicil/Departman claim'leri olsa da eklenmez.
  fix <- .sso_fields_env(existing_cols = c("Email"))
  fix$env$update_sso_fields("CONN", 9L, list(sicil = "999", email = "x@y.z", department = "Test"))

  q <- fix$cap$update_query
  testthat::expect_true(grepl("Email = ?", q, fixed = TRUE))
  testthat::expect_false(grepl("Sicil = ?", q, fixed = TRUE))
  testthat::expect_false(grepl("Departman = ?", q, fixed = TRUE))
  # Email + UserID = 2 parametre.
  testthat::expect_length(fix$cap$params, 2L)
  testthat::expect_identical(fix$cap$params[[2]], 9L)
})

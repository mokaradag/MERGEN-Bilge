# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-sql-readonly-bootstrap-contract.R
# Açıklama: `R/helpers_pk_sql_readonly.R` bağımlılığını ÇALIŞMA ZAMANINDA
#           kardeş dosya source ederek çözmez. `MERGEN_REPO_ROOT` veya çalışma
#           dizinine göreli ilk eşleşen dosyayı değerlendirmek, BAYAT bir
#           checkout'un farklı bir ayrıştırıcı sağlayıp izin/ret kararını
#           değiştirmesine izin veriyordu. Bağımlılık manifestte AÇIKTIR;
#           eksikse kapalı-başarısız davranılır. Manifest sırası (statements
#           ÖNCE, readonly SONRA) ayrıca kilitlenir.
# ==============================================================================

test_that("kardeş yardımcı yokken salt-okunur kapısı KAPALI-BAŞARISIZ olur", {
  repo_root <- resolve_repo_root_for_tests()

  env <- new.env(parent = baseenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a

  # Çalışma zamanı kardeş source'u KALDIRILDI: bayat bir checkout farklı bir
  # ayrıştırıcı sağlayıp izin/ret kararını değiştiremez.
  withr::local_envvar(MERGEN_REPO_ROOT = NA)
  withr::with_dir(withr::local_tempdir(), {
    expect_error(
      source(file.path(repo_root, "R", "helpers_pk_sql_readonly.R"),
             encoding = "UTF-8", local = env),
      "helpers_pk_sql_statements"
    )
  })

  expect_false(exists("pk_sql_classify_readonly", envir = env, inherits = FALSE))
})

test_that("kardeş yardımcı manifest sırasıyla yüklendiğinde kapı çalışır", {
  repo_root <- resolve_repo_root_for_tests()

  env <- new.env(parent = baseenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  source(file.path(repo_root, "R", "helpers_pk_sql_statements.R"),
         encoding = "UTF-8", local = env)
  source(file.path(repo_root, "R", "helpers_pk_sql_readonly.R"),
         encoding = "UTF-8", local = env)

  tekli <- env$pk_sql_classify_readonly("SELECT 1 AS a")
  expect_true(isTRUE(tekli$allowed))

  # Noktalı virgülsüz ikinci ifade tespiti kardeş yardımcıya dayanır.
  coklu <- env$pk_sql_classify_readonly("SELECT 1 AS a\nSELECT 2 AS b")
  expect_false(isTRUE(coklu$allowed))
  expect_identical(coklu$reason, "multiple_statements")
})

test_that("kardeş yardımcı zaten yüklüyken yedek yükleme tekrar çalışmaz", {
  repo_root <- resolve_repo_root_for_tests()

  env <- new.env(parent = baseenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  source(file.path(repo_root, "R", "helpers_pk_sql_statements.R"),
         encoding = "UTF-8", local = env)
  isaret <- function(masked) NULL
  env$.pk_sql_extra_top_level_statement <- isaret

  source(file.path(repo_root, "R", "helpers_pk_sql_readonly.R"),
         encoding = "UTF-8", local = env)

  # Mevcut tanım korunur (kapı onu ezmez) ve çalışma zamanı source kalıntısı yoktur.
  expect_identical(env$.pk_sql_extra_top_level_statement, isaret)
  expect_false(exists(".pk_sql_readonly_hedef_ortam", envir = env, inherits = FALSE))
})

test_that("manifest sırası: helpers_pk_sql_statements.R readonly kapısından ÖNCE yüklenir", {
  yollar <- source_manifest_paths_for_tests()
  a <- match("R/helpers_pk_sql_statements.R", yollar)
  b <- match("R/helpers_pk_sql_readonly.R", yollar)
  expect_false(is.na(a))
  expect_false(is.na(b))
  expect_true(a < b)
})

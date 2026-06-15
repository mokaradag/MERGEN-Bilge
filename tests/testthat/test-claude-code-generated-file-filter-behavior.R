# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-generated-file-filter-behavior.R
# Açıklama: Bilge Yolaç üretilen-dosya indirme filtresi
#           cc_policy_filter_generated_file_paths() için ADVERSARIAL davranışsal
#           dal kapsaması. Bu fonksiyon, bir çalıştırma sonunda hangi üretilen
#           dosyaların indirilebilir kart olarak sunulacağına karar verir;
#           izin verilen kökler dışındaki yolları DÜŞÜRÜR (download-link üretim
#           güvenlik sınırı).
#
#           Mevcut sözleşme testi (test-claude-code-security-policy-contract.R)
#           yalnızca TEK durumu sınıyor (kök-içi + kök-dışı -> yalnızca içerideki
#           kalır). Bu test, davranışsal olarak hiç sınanmamış güvenlik-kritik
#           dalları kilitler:
#             - `..` ile kökten KAÇAN yol önce normalize edilir SONRA reddedilir
#               (traversal ile indirme filtresini atlatma savunması),
#             - `..` ile köke geri dönen yol normalize edilmiş biçimde KORUNUR,
#             - boş/NULL girdi -> character(0),
#             - aynı yolun tekrarı dedup edilir,
#             - NA/boş string elemanları elenir,
#             - birden fazla kök-içi yol normalize edilmiş biçimde korunur.
#
#           Tamamen offline/deterministik: izole test ortamı; CLI/ağ/DB GEREKMEZ.
# ==============================================================================

# Sözleşme testindeki kanıtlanmış desen: yardımcıları izole bir test ortamına
# stub'la ve path_policy dosyasını oraya source et. log_warn no-op olduğundan
# düşürme dalı sessizdir; CLAUDE_CODE_LOG_PREFIX tanımlıdır.
.ccgenfilter_test_env <- function() {
  repo_root <- resolve_repo_root_for_tests()
  te <- new.env(parent = globalenv())

  te$`%||%` <- function(x, y) if (is.null(x)) y else x
  te$log_warn <- function(...) invisible(NULL)
  te$CLAUDE_CODE_LOG_PREFIX <- "[TEST]"

  source(
    file.path(repo_root, "R", "helpers_claude_code_path_policy.R"),
    encoding = "UTF-8",
    local = te
  )
  te
}

# İzin verilen kök altında gerçek bir dizin üretir (normalize edilmiş, /-slash).
.ccgenfilter_allowed_root <- function(envir = parent.frame()) {
  root <- withr::local_tempdir(.local_envir = envir)
  allowed <- file.path(root, "allowed")
  dir.create(allowed, recursive = TRUE, showWarnings = FALSE)
  normalizePath(allowed, winslash = "/", mustWork = FALSE)
}

# ------------------------------------------------------------------------------
# Adversarial: `..` ile kökten kaçan yol normalize edilip reddedilir.
# ------------------------------------------------------------------------------
testthat::test_that("'..' ile izinli kökten kaçan üretilen yol düşürülür", {
  te <- .ccgenfilter_test_env()
  allowed <- .ccgenfilter_allowed_root()

  # <allowed>/sub/../../outside/evil.txt -> <parent>/outside/evil.txt (kök dışı)
  kacan <- file.path(allowed, "sub", "..", "..", "outside", "evil.txt")
  kept <- te$cc_policy_filter_generated_file_paths(kacan, allowed_roots = allowed)

  testthat::expect_identical(kept, character(0))
})

# ------------------------------------------------------------------------------
# `..` ile köke geri dönen yol normalize edilmiş biçimde korunur.
# ------------------------------------------------------------------------------
testthat::test_that("'..' ile köke geri dönen yol normalize edilmiş biçimde korunur", {
  te <- .ccgenfilter_test_env()
  allowed <- .ccgenfilter_allowed_root()

  geri <- file.path(allowed, "sub", "..", "keep.txt")
  kept <- te$cc_policy_filter_generated_file_paths(geri, allowed_roots = allowed)

  testthat::expect_identical(length(kept), 1L)
  # Korunan değer collapse edilmiş kanonik biçimdir (sub/.. çözülür).
  testthat::expect_identical(kept, file.path(allowed, "keep.txt"))
  testthat::expect_false(grepl("..", kept, fixed = TRUE))
})

# ------------------------------------------------------------------------------
# Boş/NULL girdi -> character(0).
# ------------------------------------------------------------------------------
testthat::test_that("boş/NULL girdi character(0) döndürür", {
  te <- .ccgenfilter_test_env()
  allowed <- .ccgenfilter_allowed_root()

  testthat::expect_identical(
    te$cc_policy_filter_generated_file_paths(character(0), allowed_roots = allowed),
    character(0)
  )
  testthat::expect_identical(
    te$cc_policy_filter_generated_file_paths(NULL, allowed_roots = allowed),
    character(0)
  )
})

# ------------------------------------------------------------------------------
# Aynı yolun tekrarı dedup edilir.
# ------------------------------------------------------------------------------
testthat::test_that("aynı kök-içi yolun tekrarı dedup edilir", {
  te <- .ccgenfilter_test_env()
  allowed <- .ccgenfilter_allowed_root()

  ayni <- file.path(allowed, "a.txt")
  kept <- te$cc_policy_filter_generated_file_paths(
    c(ayni, ayni),
    allowed_roots = allowed
  )

  testthat::expect_identical(length(kept), 1L)
  testthat::expect_identical(kept, ayni)
})

# ------------------------------------------------------------------------------
# NA / boş string elemanları elenir; geçerli kök-içi yol korunur.
# ------------------------------------------------------------------------------
testthat::test_that("NA/boş string elemanları elenir, geçerli yol korunur", {
  te <- .ccgenfilter_test_env()
  allowed <- .ccgenfilter_allowed_root()

  gecerli <- file.path(allowed, "b.txt")
  kept <- te$cc_policy_filter_generated_file_paths(
    c(NA_character_, "", gecerli),
    allowed_roots = allowed
  )

  testthat::expect_identical(kept, gecerli)
})

# ------------------------------------------------------------------------------
# Birden fazla kök-içi yol normalize edilmiş biçimde korunur.
# ------------------------------------------------------------------------------
testthat::test_that("birden fazla kök-içi yol korunur, kök-dışı düşürülür", {
  te <- .ccgenfilter_test_env()
  allowed <- .ccgenfilter_allowed_root()
  disari <- normalizePath(withr::local_tempdir(), winslash = "/", mustWork = FALSE)

  ic1 <- file.path(allowed, "rapor.txt")
  ic2 <- file.path(allowed, "alt", "ozet.md")
  dis <- file.path(disari, "gizli.txt")

  kept <- te$cc_policy_filter_generated_file_paths(
    c(ic1, dis, ic2),
    allowed_roots = allowed
  )

  testthat::expect_identical(length(kept), 2L)
  testthat::expect_true(all(c(ic1, ic2) %in% kept))
  testthat::expect_false(dis %in% kept)
})

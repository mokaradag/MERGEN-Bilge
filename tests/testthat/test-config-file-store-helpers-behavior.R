# ==============================================================================
# Dosya Yolu: tests/testthat/test-config-file-store-helpers-behavior.R
# Açıklama: R/config_file_store.R yardımcılarının davranışsal testleri.
#           env_or_default_path (ortam/varsayılan çözümü), .mark_utf8/.convert_to_utf8
#           (UTF-8 işaretleme/dönüştürme) ve mergen_clear_user_bucket (fiziksel
#           dosya + index kovası temizliği) doğrulanır. Dosya deposu helper_load_file_store
#           tarafından izole geçici dizinlere yüklenir.
# ==============================================================================

testthat::local_edition(3)

if (exists("reset_file_store_runtime_for_tests", mode = "function", inherits = TRUE)) {
  reset_file_store_runtime_for_tests()
}

.cfs_ready <- exists("env_or_default_path", mode = "function", inherits = TRUE) &&
  exists("mergen_clear_user_bucket", mode = "function", inherits = TRUE) &&
  exists(".load_index", mode = "function", inherits = TRUE)

if (isTRUE(.cfs_ready)) {
  testthat::expect_false(
    grepl("^//rehisds|^\\\\\\\\rehisds|MERGEN Bilge", MERGEN_INDEX_PATH, ignore.case = TRUE),
    info = paste("MERGEN_INDEX_PATH testte gerçek/ağ yolda kalmamalı:", MERGEN_INDEX_PATH)
  )
}

# -----------------------------------------------------------------------------
# env_or_default_path
# -----------------------------------------------------------------------------

test_that("env_or_default_path ortam değişkeni tanımlıysa onu, değilse varsayılanı döner", {
  skip_if_not(.cfs_ready, "config_file_store yüklü değil")

  withr::with_envvar(c(MERGEN_CFS_TEST_PATH = "/ozel/yol"), {
    expect_true(grepl("ozel/yol", env_or_default_path("MERGEN_CFS_TEST_PATH", "/varsayilan"), fixed = TRUE))
  })
  withr::with_envvar(c(MERGEN_CFS_TEST_PATH = ""), {
    expect_true(grepl("varsayilan/yol", env_or_default_path("MERGEN_CFS_TEST_PATH", "/varsayilan/yol"), fixed = TRUE))
  })
})

# -----------------------------------------------------------------------------
# .mark_utf8 / .convert_to_utf8
# -----------------------------------------------------------------------------

test_that(".mark_utf8 karakter dizisini UTF-8 olarak işaretler, sayısalı korur", {
  skip_if_not(.cfs_ready, "config_file_store yüklü değil")
  s <- "Türkçe metin"
  Encoding(s) <- "unknown"
  isaretli <- .mark_utf8(s)
  expect_identical(Encoding(isaretli), "UTF-8")
  # Sayısal değer değişmeden geçmeli.
  expect_identical(.mark_utf8(42L), 42L)
  # Liste yapısı korunur.
  expect_true(is.list(.mark_utf8(list(a = "x", b = "y"))))
})

test_that(".convert_to_utf8 karakter/liste içeriğini korur ve sayısalı geçirir", {
  skip_if_not(.cfs_ready, "config_file_store yüklü değil")
  expect_identical(.convert_to_utf8("abc"), "abc")
  expect_identical(.convert_to_utf8(list("a", "b"))[[2]], "b")
  expect_identical(.convert_to_utf8(7L), 7L)
})

# -----------------------------------------------------------------------------
# mergen_clear_user_bucket
# -----------------------------------------------------------------------------

test_that("mergen_clear_user_bucket fiziksel dosyaları siler ve index kovasını boşaltır", {
  skip_if_not(.cfs_ready, "config_file_store yüklü değil")

  uid <- "987654"
  withr::defer({
    idx <- .load_index()
    if (!is.null(idx[[uid]])) {
      idx[[uid]] <- NULL
      .save_index(idx)
    }
  })

  d <- mergen_user_upload_dir(uid)
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  fp <- file.path(d, "silinecek_dosya.txt")
  writeLines("içerik", fp)

  # Index kovasına bir kayıt ekle.
  idx <- .load_index()
  idx[[uid]] <- list(k = list(path = fp, display = "silinecek_dosya.txt"))
  .save_index(idx)

  expect_true(file.exists(fp))
  expect_false(is.null(.load_index()[[uid]]))

  res <- mergen_clear_user_bucket(uid)
  expect_true(isTRUE(res))
  # Fiziksel dosya silinmeli ve index kovası boşalmalı.
  expect_false(file.exists(fp))
  expect_null(.load_index()[[uid]])
})
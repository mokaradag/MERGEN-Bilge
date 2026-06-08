# ==============================================================================
# Dosya Yolu: tests/testthat/test-file-store-mutation-helpers-behavior.R
# Açıklama: R/config_file_store_listing_helpers.R indeks mutasyon yardımcılarının
#           davranış testleri: .file_store_drop_stale_entries (bayat/eksik
#           kayıtları yola göre düşürme) ve .file_store_apply_rehydrated_paths
#           (eski->yeni yol güncelleme). .file_store_mutate_index, kontrol
#           edilen bellek içi bir indekse uygulanacak şekilde stub'lanır; gerçek
#           DB/dosya/index.json GEREKMEZ. Yol karşılaştırması için gerçek
#           normalize_for_path_compare kullanılır.
# ==============================================================================

testthat::local_edition(3)

# İzole ortam: gerçek path-compare + listeleme yardımcıları + kontrol edilen
# bellek içi indeks mutasyonu.
.fsmut_env <- function(initial_idx) {
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_files_path.R"),
    encoding = "UTF-8", local = env
  )
  source(
    file.path(resolve_repo_root_for_tests(), "R", "config_file_store_listing_helpers.R"),
    encoding = "UTF-8", local = env
  )
  # Kontrol edilen indeksi tut; mutate_fn'i bu indekse uygula.
  env$.idx <- initial_idx
  env$.file_store_mutate_index <- function(mutate_fn) {
    env$.idx <- mutate_fn(env$.idx)
    invisible(TRUE)
  }
  env
}

# --- .file_store_drop_stale_entries -------------------------------------------

test_that("drop_stale: yolu eşleşen kaydı düşürür, eşleşmeyeni korur", {
  env <- .fsmut_env(list(
    u5 = list(
      k1 = list(path = "/data/a.pdf", display = "a.pdf"),
      k2 = list(path = "/data/b.pdf", display = "b.pdf")
    )
  ))
  recs <- data.frame(key = "k1", path = "/data/a.pdf", stringsAsFactors = FALSE)

  res <- env$.file_store_drop_stale_entries("u5", recs)
  expect_true(res)
  expect_identical(names(env$.idx$u5), "k2")
})

test_that("drop_stale: yol uyuşmazsa kayıt KORUNUR", {
  env <- .fsmut_env(list(
    u5 = list(k1 = list(path = "/data/a.pdf", display = "a.pdf"))
  ))
  recs <- data.frame(key = "k1", path = "/data/FARKLI.pdf", stringsAsFactors = FALSE)

  env$.file_store_drop_stale_entries("u5", recs)
  expect_true("k1" %in% names(env$.idx$u5))
})

test_that("drop_stale: tüm kayıtlar düşünce kullanıcı bucket'ı tamamen kaldırılır", {
  env <- .fsmut_env(list(
    u5 = list(
      k1 = list(path = "/data/a.pdf", display = "a.pdf"),
      k2 = list(path = "/data/b.pdf", display = "b.pdf")
    )
  ))
  recs <- data.frame(
    key = c("k1", "k2"),
    path = c("/data/a.pdf", "/data/b.pdf"),
    stringsAsFactors = FALSE
  )

  env$.file_store_drop_stale_entries("u5", recs)
  expect_null(env$.idx$u5)
})

test_that("drop_stale: düz karakter (list olmayan) kayıt da yola göre düşürülür", {
  env <- .fsmut_env(list(
    u5 = list(k1 = "/data/a.pdf", k2 = list(path = "/data/b.pdf"))
  ))
  recs <- data.frame(key = "k1", path = "/data/a.pdf", stringsAsFactors = FALSE)

  env$.file_store_drop_stale_entries("u5", recs)
  expect_identical(names(env$.idx$u5), "k2")
})

test_that("drop_stale: boş/NULL kayıt girdisi FALSE döndürür ve indeksi değiştirmez", {
  env <- .fsmut_env(list(u5 = list(k1 = list(path = "/data/a.pdf"))))
  expect_false(env$.file_store_drop_stale_entries("u5", NULL))
  bos <- data.frame(key = character(0), path = character(0), stringsAsFactors = FALSE)
  expect_false(env$.file_store_drop_stale_entries("u5", bos))
  expect_true("k1" %in% names(env$.idx$u5))
})

# --- .file_store_apply_rehydrated_paths ---------------------------------------

test_that("apply_rehydrated: eski yolu eşleşen kaydın yolu yeni yola güncellenir", {
  env <- .fsmut_env(list(
    u5 = list(k1 = list(path = "/old/a.pdf", display = "a.pdf"))
  ))
  rehyd <- list(k1 = list(old_path = "/old/a.pdf", new_path = "/new/a.pdf"))

  res <- env$.file_store_apply_rehydrated_paths("u5", rehyd)
  expect_true(res)
  expect_identical(env$.idx$u5$k1$path, "/new/a.pdf")
})

test_that("apply_rehydrated: eski yol uyuşmazsa yol GÜNCELLENMEZ", {
  env <- .fsmut_env(list(
    u5 = list(k1 = list(path = "/baska/a.pdf", display = "a.pdf"))
  ))
  rehyd <- list(k1 = list(old_path = "/old/a.pdf", new_path = "/new/a.pdf"))

  env$.file_store_apply_rehydrated_paths("u5", rehyd)
  expect_identical(env$.idx$u5$k1$path, "/baska/a.pdf")
})

test_that("apply_rehydrated: düz karakter kayıt eşleşince doğrudan yeni yolla değiştirilir", {
  env <- .fsmut_env(list(u5 = list(k1 = "/old/a.pdf")))
  rehyd <- list(k1 = list(old_path = "/old/a.pdf", new_path = "/new/a.pdf"))

  env$.file_store_apply_rehydrated_paths("u5", rehyd)
  expect_identical(env$.idx$u5$k1, "/new/a.pdf")
})

test_that("apply_rehydrated: boş rehydrated listesi FALSE döndürür ve indeksi değiştirmez", {
  env <- .fsmut_env(list(u5 = list(k1 = list(path = "/old/a.pdf"))))
  expect_false(env$.file_store_apply_rehydrated_paths("u5", list()))
  expect_identical(env$.idx$u5$k1$path, "/old/a.pdf")
})

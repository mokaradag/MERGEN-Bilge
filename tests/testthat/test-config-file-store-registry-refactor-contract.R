# ==============================================================================
# Dosya Yolu: tests/testthat/test-config-file-store-registry-refactor-contract.R
# Açıklama: File Store registry/index refactor sözleşmesini statik ve warning-safe
#           biçimde doğrular.
# ==============================================================================

.read_file_store_contract_text <- function(path) {
  repo_root <- resolve_repo_root_for_tests()
  full_path <- file.path(repo_root, path)

  size <- suppressWarnings(file.info(full_path)$size[1])
  if (is.na(size) || size <= 0) {
    return("")
  }

  con <- file(full_path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_data <- readBin(con, what = "raw", n = size)

  txt <- suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
  )

  if (is.na(txt)) {
    txt <- ""
  }

  txt <- gsub("\\r\\n?|\\r", "\\n", txt, perl = TRUE)
  enc2utf8(txt)
}

.file_store_has_definition <- function(name, txt) {
  txt <- gsub("\\r\\n?|\\r", "\n", txt, perl = TRUE)

  definition_variants <- c(
    paste0(name, " <- function"),
    paste0(name, "<- function")
  )

  any(vapply(
    definition_variants,
    function(pattern) {
      isTRUE(grepl(pattern, txt, fixed = TRUE, useBytes = TRUE))
    },
    logical(1)
  ))
}

.file_store_function_count <- function(txt) {
  hits <- gregexpr(
    "(<-|=)\\s*function\\s*\\(",
    txt,
    perl = TRUE
  )[[1]]

  if (length(hits) == 1L && identical(hits[1], -1L)) {
    return(0L)
  }

  length(hits)
}

test_that("file store public registry fonksiyonları config_file_store.R dışına taşınmıştır", {
  config_txt <- .read_file_store_contract_text("R/config_file_store.R")
  mutation_txt <- .read_file_store_contract_text("R/config_file_store_index_mutation.R")
  listing_txt <- .read_file_store_contract_text("R/config_file_store_listing_helpers.R")
  registry_txt <- .read_file_store_contract_text("R/config_file_store_registry.R")

  mutation_functions <- c(
    "recover_display_name_from_storage_name",
    "repair_index_display_names_from_path",
    "mergen_register_uploaded_file",
    "global_register_file",
    "mergen_remove_from_index"
  )

  registry_functions <- c(
    "resolve_uploaded_file",
    "mergen_user_upload_dir",
    "mergen_resolve_display_name",
    "mergen_list_user_files"
  )

  expect_false(
    any(vapply(c(mutation_functions, registry_functions), .file_store_has_definition, logical(1), txt = config_txt)),
    info = "Dosya kayıt/çözümleme public fonksiyonları R/config_file_store.R içine geri taşınmamalıdır."
  )

  expect_true(
    all(vapply(mutation_functions, .file_store_has_definition, logical(1), txt = mutation_txt)),
    info = "İndeks mutasyon public fonksiyonları R/config_file_store_index_mutation.R içinde kalmalıdır."
  )

  expect_true(
    all(vapply(registry_functions, .file_store_has_definition, logical(1), txt = registry_txt)),
    info = "Dosya çözümleme/listeleme public fonksiyonları R/config_file_store_registry.R içinde kalmalıdır."
  )
})

test_that("file store indeks mutasyonları yarış koruması kullanır", {
  mutation_txt <- .read_file_store_contract_text("R/config_file_store_index_mutation.R")
  registry_txt <- .read_file_store_contract_text("R/config_file_store_registry.R")

  expect_true(
    grepl(".file_store_with_index_lock <- function", mutation_txt, fixed = TRUE),
    info = "File Store indeks mutasyonları için lock helper korunmalıdır."
  )

  expect_true(
    grepl(".file_store_mutate_index <- function", mutation_txt, fixed = TRUE),
    info = "File Store indeks read-modify-write işlemleri ortak mutate helper üzerinden yapılmalıdır."
  )

  expect_true(
    grepl("dir.create(lock_dir", mutation_txt, fixed = TRUE),
    info = "İndeks kilidi warning-safe lock dizini oluşturma yaklaşımını kullanmalıdır."
  )

  expect_true(
    grepl(".file_store_mutate_index(function(idx)", mutation_txt, fixed = TRUE),
    info = "Yükleme kaydı ve indeks silme işlemleri mutate helper üzerinden yapılmalıdır."
  )

  expect_true(
    grepl(".file_store_mutate_index(function(idx_local)", registry_txt, fixed = TRUE),
    info = "Dosya listeleme içindeki stale prune/rehydrate yazımları mutate helper üzerinden yapılmalıdır."
  )

  expect_true(
    grepl("same_missing_path", registry_txt, fixed = TRUE),
    info = "Stale prune yeni yükleme girdisini silmemek için eski path karşılaştırması yapmalıdır."
  )

  expect_true(
    grepl("old_path", registry_txt, fixed = TRUE),
    info = "Rehydrate işlemi yeni path'i yalnızca eski path hâlâ aynıysa yazmalıdır."
  )
})

test_that("file store refactor fonksiyon yoğunluğunu dosyalar arasında böler", {
  config_txt <- .read_file_store_contract_text("R/config_file_store.R")
  mutation_txt <- .read_file_store_contract_text("R/config_file_store_index_mutation.R")
  listing_txt <- .read_file_store_contract_text("R/config_file_store_listing_helpers.R")
  registry_txt <- .read_file_store_contract_text("R/config_file_store_registry.R")

  expect_true(
    .file_store_function_count(config_txt) < 25L,
    info = "R/config_file_store.R refactor sonrası 25 fonksiyon eşiğinin altında kalmalıdır."
  )

  expect_true(
    .file_store_function_count(mutation_txt) < 25L,
    info = "R/config_file_store_index_mutation.R yeni function-heavy dosya olmamalıdır."
  )

  expect_true(
    .file_store_function_count(registry_txt) < 25L,
    info = "R/config_file_store_registry.R yeni function-heavy dosya olmamalıdır."
  )
  
  expect_true(
    .file_store_function_count(listing_txt) < 25L,
    info = "R/config_file_store_listing_helpers.R yeni function-heavy dosya olmamalıdır."
  )
})
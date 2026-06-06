# ==============================================================================
# Dosya Yolu: tests/testthat/test-file-store-persistence-roundtrip-smoke.R
# Açıklama: Kalıcı dosya deposunun desteklenen dosya türlerinde görünen adları
#           tekrar listeleme/refresh benzeri çağrılarda tekil ve UTF-8 güvenli
#           koruduğunu doğrular. Uygulamayı, DB'yi veya tarayıcıyı başlatmaz.
# ==============================================================================

testthat::test_that("file store preserves display names for supported file types across repeated listings", {
  testthat::skip_if_not_installed("fs")
  testthat::skip_if_not_installed("jsonlite")

  # Bu test gerçek repo/ağ yoluna yazmamalıdır.
  # File Store helper'ları daha önce yanlış/global MERGEN_* yollarıyla yüklenmiş
  # olsa bile, runtime değişkenlerini test özelinde tempdir altına zorlarız.
  smoke_root <- withr::local_tempdir(pattern = "mergen-file-store-smoke-")

  smoke_files_root <- normalizePath(
    file.path(smoke_root, "files_root"),
    winslash = "/",
    mustWork = FALSE
  )
  smoke_uploads_dir <- normalizePath(
    file.path(smoke_root, "uploads_root"),
    winslash = "/",
    mustWork = FALSE
  )
  smoke_mcp_base_dir <- normalizePath(
    file.path(smoke_root, "mcp_base"),
    winslash = "/",
    mustWork = FALSE
  )
  smoke_index_path <- normalizePath(
    file.path(smoke_files_root, "index.json"),
    winslash = "/",
    mustWork = FALSE
  )

  dir.create(smoke_files_root, recursive = TRUE, showWarnings = FALSE)
  dir.create(smoke_uploads_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(smoke_mcp_base_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(dirname(smoke_index_path), recursive = TRUE, showWarnings = FALSE)

  smoke_files_root <- normalizePath(smoke_files_root, winslash = "/", mustWork = TRUE)
  smoke_uploads_dir <- normalizePath(smoke_uploads_dir, winslash = "/", mustWork = TRUE)
  smoke_mcp_base_dir <- normalizePath(smoke_mcp_base_dir, winslash = "/", mustWork = TRUE)
  smoke_index_path <- normalizePath(smoke_index_path, winslash = "/", mustWork = FALSE)

  old_file_store_globals <- mget(
    c("MERGEN_FILES_ROOT", "MERGEN_UPLOADS_DIR", "MERGEN_INDEX_PATH", "MERGEN_MCP_BASE_DIR"),
    envir = globalenv(),
    ifnotfound = list(NULL)
  )
  old_file_store_exists <- vapply(
    names(old_file_store_globals),
    exists,
    logical(1),
    envir = globalenv(),
    inherits = FALSE
  )

  withr::defer({
    for (nm in names(old_file_store_globals)) {
      if (isTRUE(old_file_store_exists[[nm]])) {
        assign(nm, old_file_store_globals[[nm]], envir = globalenv())
      } else if (exists(nm, envir = globalenv(), inherits = FALSE)) {
        rm(list = nm, envir = globalenv())
      }
    }
  })

  withr::local_envvar(c(
    MERGEN_FILES_ROOT = smoke_files_root,
    MERGEN_UPLOADS_DIR = smoke_uploads_dir,
    MERGEN_INDEX_PATH = smoke_index_path,
    MERGEN_MCP_BASE_DIR = smoke_mcp_base_dir,
    MCP_FILES_BASE = smoke_mcp_base_dir
  ))

  withr::local_options(list(
    mergen.files_root = smoke_files_root,
    mergen.index_path = smoke_index_path,
    mergen.mcp_base_dir = smoke_mcp_base_dir
  ))

  assign("MERGEN_FILES_ROOT", smoke_files_root, envir = globalenv())
  assign("MERGEN_UPLOADS_DIR", smoke_uploads_dir, envir = globalenv())
  assign("MERGEN_INDEX_PATH", smoke_index_path, envir = globalenv())
  assign("MERGEN_MCP_BASE_DIR", smoke_mcp_base_dir, envir = globalenv())

  testthat::expect_true(dir.exists(dirname(MERGEN_INDEX_PATH)))
  testthat::expect_false(
    grepl("^//rehisds|^\\\\\\\\rehisds|MERGEN Bilge", MERGEN_INDEX_PATH, ignore.case = TRUE),
    info = paste("MERGEN_INDEX_PATH testte gerçek/ağ yolda kalmamalı:", MERGEN_INDEX_PATH)
  )

  required <- c(
    "mergen_register_uploaded_file",
    "mergen_list_user_files",
    "resolve_uploaded_file",
    "mergen_remove_from_index",
    "path_exists_relaxed"
  )

  missing <- required[!vapply(
    required,
    function(fn) exists(fn, envir = globalenv(), mode = "function", inherits = TRUE),
    logical(1)
  )]

  testthat::expect_equal(
    missing,
    character(0),
    info = paste("File Store helper eksik:", paste(missing, collapse = ", "))
  )

  user_id <- as.integer(880000000L + sample.int(99999L, 1L))

  display_names <- enc2utf8(c(
    "smoke_rapor.pdf",
    "smoke_belge.docx",
    "smoke_not.txt",
    "smoke_tablo.csv",
    "smoke_excel.xlsx",
    "Türkçe_çalışma_özeti_İstanbul.pdf"
  ))

  source_dir <- file.path(
    tempdir(),
    sprintf("mergen_file_store_roundtrip_%s", user_id)
  )
  dir.create(source_dir, recursive = TRUE, showWarnings = FALSE)

  registered_paths <- character(0)

  cleanup <- function() {
    for (nm in display_names) {
      try(mergen_remove_from_index(user_id, nm), silent = TRUE)
    }

    for (p in registered_paths) {
      try(unlink(p, force = TRUE), silent = TRUE)
    }

    try(unlink(source_dir, recursive = TRUE, force = TRUE), silent = TRUE)
  }

  on.exit(cleanup(), add = TRUE)

  for (nm in display_names) {
    src <- file.path(source_dir, nm)
    writeBin(
      charToRaw(enc2utf8(paste0("MERGEN file persistence smoke: ", nm, "\n"))),
      src
    )

    registered <- mergen_register_uploaded_file(
      src_path = src,
      as_name = nm,
      user_id = user_id,
      persist_under_mcp_base = TRUE
    )

    registered_paths <- c(registered_paths, registered)

    testthat::expect_true(
      path_exists_relaxed(registered),
      info = paste("Kayıtlı fiziksel dosya bulunamadı:", nm)
    )
  }

  listed_first <- mergen_list_user_files(user_id, prune_missing = FALSE)
  listed_second <- mergen_list_user_files(user_id, prune_missing = FALSE)

  for (listed in list(listed_first, listed_second)) {
    testthat::expect_true(is.data.frame(listed))
    testthat::expect_true(all(c("path", "name") %in% names(listed)))

    listed_names <- enc2utf8(as.character(listed$name))

    for (nm in display_names) {
      testthat::expect_equal(
        sum(listed_names == nm),
        1L,
        info = paste("Görünen ad tekil korunmalı:", nm)
      )
    }

    testthat::expect_false(
      any(grepl("^\\d{8}[-_]\\d{6}", listed_names)),
      info = "Storage timestamp/hex adı kullanıcıya görünen ad olarak sızmamalıdır."
    )
  }

  for (nm in display_names) {
    resolved <- resolve_uploaded_file(nm, user_id = user_id)

    testthat::expect_true(
      !is.null(resolved) && path_exists_relaxed(resolved),
      info = paste("Görünen adla resolve başarısız:", nm)
    )
  }
})
# ==============================================================================
# Dosya Yolu: tests/testthat/test-file-store-persistence-roundtrip-smoke.R
# Açıklama: Kalıcı dosya deposunun desteklenen dosya türlerinde görünen adları
#           tekrar listeleme/refresh benzeri çağrılarda tekil ve UTF-8 güvenli
#           koruduğunu doğrular. Uygulamayı, DB'yi veya tarayıcıyı başlatmaz.
# ==============================================================================

testthat::test_that("file store preserves display names for supported file types across repeated listings", {
  testthat::skip_if_not_installed("fs")
  testthat::skip_if_not_installed("jsonlite")

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
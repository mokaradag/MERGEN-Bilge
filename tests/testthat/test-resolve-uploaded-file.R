# ==============================================================================
# Dosya Yolu: tests/testthat/test-resolve-uploaded-file.R
# Açıklama: resolve_uploaded_file() fonksiyonunun kullanıcı kovası, display adı,
# basename ve hatalı senaryolarda doğru davrandığını doğrulayan testleri içerir.
# ==============================================================================

.find_repo_root_resolve_uploaded_file <- function() {
  candidates <- unique(normalizePath(
    c(
      getwd(),
      file.path(getwd(), ".."),
      file.path(getwd(), "..", "..")
    ),
    winslash = "/",
    mustWork = FALSE
  ))

  for (candidate in candidates) {
    if (file.exists(file.path(candidate, "app.R")) &&
        dir.exists(file.path(candidate, "tests", "testthat"))) {
      return(candidate)
    }
  }

  stop("resolve_uploaded_file testi repo kökünü bulamadı.", call. = FALSE)
}

repo_root_resolve_uploaded_file <- .find_repo_root_resolve_uploaded_file()

if (!exists("resolve_repo_root_for_tests", envir = globalenv(), inherits = FALSE)) {
  source(
    file.path(repo_root_resolve_uploaded_file, "tests", "testthat", "helper_bootstrap.R"),
    encoding = "UTF-8",
    local = globalenv()
  )
}

repo_root_resolve_uploaded_file <- resolve_repo_root_for_tests()

.resolve_uploaded_file_required_sources <- c(
  "R/utils_path_helpers.R",
  "R/helpers_files_path.R",
  "R/utils_atomic_write.R",
  "R/config_file_store.R",
  "R/config_file_store_index_mutation.R",
  "R/config_file_store_registry.R"
)

for (source_file in .resolve_uploaded_file_required_sources) {
  source(
    file.path(repo_root_resolve_uploaded_file, source_file),
    encoding = "UTF-8",
    local = globalenv()
  )
}

if (!exists("resolve_uploaded_file", envir = globalenv(), mode = "function", inherits = FALSE)) {
  stop("resolve_uploaded_file() test bootstrap sonrası bulunamadı.", call. = FALSE)
}

test_that("resolve_uploaded_file doğrudan fiziksel yolu varsayılan olarak reddeder", {
  gecici_dir <- tempfile("uploadtest_direct_deny_")
  dir.create(gecici_dir, recursive = TRUE)

  gecici_dosya <- file.path(gecici_dir, "direk.docx")
  writeLines("ornek", gecici_dosya, useBytes = TRUE)

  on.exit(unlink(gecici_dir, recursive = TRUE, force = TRUE), add = TRUE)

  sonuc <- resolve_uploaded_file(
    gecici_dosya,
    user_id = 1L
  )

  expect_null(
    sonuc,
    info = "Doğrudan fiziksel path, allow_direct_path=FALSE iken çözümlenmemelidir."
  )
})

test_that("resolve_uploaded_file doğrudan yolu sadece trusted_roots altında izinliyse çözer", {
  gecici_dir <- tempfile("uploadtest_trusted_root_")
  dir.create(gecici_dir, recursive = TRUE)

  trusted_dir <- file.path(gecici_dir, "trusted")
  outside_dir <- file.path(gecici_dir, "outside")

  dir.create(trusted_dir, recursive = TRUE)
  dir.create(outside_dir, recursive = TRUE)

  trusted_file <- file.path(trusted_dir, "izinli.xlsx")
  outside_file <- file.path(outside_dir, "reddedilen.xlsx")

  writeLines("ok", trusted_file, useBytes = TRUE)
  writeLines("no", outside_file, useBytes = TRUE)

  on.exit(unlink(gecici_dir, recursive = TRUE, force = TRUE), add = TRUE)

  sonuc_trusted <- resolve_uploaded_file(
    trusted_file,
    user_id = 1L,
    allow_direct_path = TRUE,
    trusted_roots = trusted_dir
  )

  expect_false(is.null(sonuc_trusted))
  expect_equal(
    normalizePath(sonuc_trusted, winslash = "/", mustWork = FALSE),
    normalizePath(trusted_file, winslash = "/", mustWork = FALSE)
  )

  sonuc_outside <- resolve_uploaded_file(
    outside_file,
    user_id = 1L,
    allow_direct_path = TRUE,
    trusted_roots = trusted_dir
  )

  expect_null(
    sonuc_outside,
    info = "allow_direct_path=TRUE olsa bile trusted_roots dışındaki path reddedilmelidir."
  )
})

# Display adı ile kullanıcı kovasında kayıtlı dosya bulunur.
test_that("resolve_uploaded_file kullanıcı kovasında display adı ile bulur", {
  eski_index_yol <- MERGEN_INDEX_PATH
  eski_uploads_dir <- MERGEN_UPLOADS_DIR
  eski_mcp_base_dir <- MERGEN_MCP_BASE_DIR

  gecici_dir <- tempfile("uploadidx_")
  dir.create(gecici_dir, recursive = TRUE)

  test_uploads_dir <- file.path(gecici_dir, "uploads")
  test_mcp_base_dir <- file.path(gecici_dir, "mcp")
  user_dir <- file.path(test_mcp_base_dir, "user_9")

  dir.create(user_dir, recursive = TRUE)

  gercek_dosya <- file.path(user_dir, "20240101120000_0001_Rapor.docx")
  writeLines("ornek", gercek_dosya, useBytes = TRUE)

  gecici_idx <- file.path(gecici_dir, "index.json")

  assign("MERGEN_INDEX_PATH", gecici_idx, envir = globalenv())
  assign("MERGEN_UPLOADS_DIR", test_uploads_dir, envir = globalenv())
  assign("MERGEN_MCP_BASE_DIR", test_mcp_base_dir, envir = globalenv())

  on.exit({
    assign("MERGEN_INDEX_PATH", eski_index_yol, envir = globalenv())
    assign("MERGEN_UPLOADS_DIR", eski_uploads_dir, envir = globalenv())
    assign("MERGEN_MCP_BASE_DIR", eski_mcp_base_dir, envir = globalenv())
    unlink(gecici_dir, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  idx <- list(
    "9" = list(
      "rapor.docx" = list(
        path = gercek_dosya,
        display = "Rapor.docx"
      )
    )
  )

  .save_index(idx)

  sonuc_display <- resolve_uploaded_file(
    "Rapor.docx",
    user_id = 9L
  )

  expect_false(is.null(sonuc_display))
  expect_equal(
    normalizePath(sonuc_display, winslash = "/", mustWork = FALSE),
    normalizePath(gercek_dosya, winslash = "/", mustWork = FALSE)
  )

  sonuc_base <- resolve_uploaded_file(
    "rapor.docx",
    user_id = 9L
  )

  expect_false(is.null(sonuc_base))
})

test_that("resolve_uploaded_file user_id NULL iken legacy haritayı varsayılan olarak kullanmaz", {
  eski_yol <- MERGEN_INDEX_PATH

  gecici_dir <- tempfile("uploadlegacy_deny_")
  dir.create(gecici_dir, recursive = TRUE)

  gercek_dosya <- file.path(gecici_dir, "legacy.xlsx")
  writeLines("ornek", gercek_dosya, useBytes = TRUE)

  gecici_idx <- file.path(gecici_dir, "index.json")
  assign("MERGEN_INDEX_PATH", gecici_idx, envir = globalenv())

  on.exit({
    assign("MERGEN_INDEX_PATH", eski_yol, envir = globalenv())
    unlink(gecici_dir, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  idx <- list(
    "legacy.xlsx" = list(
      path = gercek_dosya,
      display = "legacy.xlsx"
    )
  )

  .save_index(idx)

  sonuc_default <- resolve_uploaded_file(
    "legacy.xlsx",
    user_id = NULL
  )

  expect_null(
    sonuc_default,
    info = "user_id=NULL ve allow_cross_bucket=FALSE iken legacy harita kullanılmamalıdır."
  )

  sonuc_opt_in <- resolve_uploaded_file(
    "legacy.xlsx",
    user_id = NULL,
    allow_cross_bucket = TRUE
  )

  expect_false(
    is.null(sonuc_opt_in),
    info = "Legacy/cross-bucket çözümleme yalnızca açık opt-in ile çalışmalıdır."
  )
})

test_that("resolve_uploaded_file başka kullanıcının aynı adlı dosyasını varsayılan olarak döndürmez", {
  eski_index_yol <- MERGEN_INDEX_PATH
  eski_uploads_dir <- MERGEN_UPLOADS_DIR
  eski_mcp_base_dir <- MERGEN_MCP_BASE_DIR

  gecici_dir <- tempfile("cross_user_isolation_")
  dir.create(gecici_dir, recursive = TRUE)

  test_uploads_dir <- file.path(gecici_dir, "uploads")
  test_mcp_base_dir <- file.path(gecici_dir, "mcp")

  user_1_dir <- file.path(test_mcp_base_dir, "user_1")
  user_2_dir <- file.path(test_mcp_base_dir, "user_2")

  dir.create(user_1_dir, recursive = TRUE)
  dir.create(user_2_dir, recursive = TRUE)

  user_2_file <- file.path(user_2_dir, "shared.xlsx")
  writeLines("user 2 secret", user_2_file, useBytes = TRUE)

  gecici_idx <- file.path(gecici_dir, "index.json")

  assign("MERGEN_INDEX_PATH", gecici_idx, envir = globalenv())
  assign("MERGEN_UPLOADS_DIR", test_uploads_dir, envir = globalenv())
  assign("MERGEN_MCP_BASE_DIR", test_mcp_base_dir, envir = globalenv())

  on.exit({
    assign("MERGEN_INDEX_PATH", eski_index_yol, envir = globalenv())
    assign("MERGEN_UPLOADS_DIR", eski_uploads_dir, envir = globalenv())
    assign("MERGEN_MCP_BASE_DIR", eski_mcp_base_dir, envir = globalenv())
    unlink(gecici_dir, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  idx <- list(
    "2" = list(
      "shared.xlsx" = list(
        path = user_2_file,
        display = "shared.xlsx"
      )
    )
  )

  .save_index(idx)

  sonuc_user_1 <- resolve_uploaded_file(
    "shared.xlsx",
    user_id = 1L
  )

  expect_null(
    sonuc_user_1,
    info = "User 1, User 2 bucket içindeki aynı adlı dosyayı varsayılan olarak görememelidir."
  )

  sonuc_opt_in <- resolve_uploaded_file(
    "shared.xlsx",
    user_id = 1L,
    allow_cross_bucket = TRUE
  )

  expect_false(
    is.null(sonuc_opt_in),
    info = "Cross-bucket çözümleme yalnızca açık opt-in ile çalışmalıdır."
  )
})

# Hiç eşleşme yoksa NULL döner (hata fırlatmaz).
test_that("resolve_uploaded_file eşleşme yoksa NULL döndürür", {
  eski_yol <- MERGEN_INDEX_PATH
  gecici_dir <- tempfile("uploadmiss_")
  dir.create(gecici_dir, recursive = TRUE)
  gecici_idx <- file.path(gecici_dir, "index.json")
  assign("MERGEN_INDEX_PATH", gecici_idx, envir = globalenv())
  on.exit({
    assign("MERGEN_INDEX_PATH", eski_yol, envir = globalenv())
    unlink(gecici_dir, recursive = TRUE, force = TRUE)
  })

  # İndeks boş yazılır
  .save_index(list())

  sonuc <- resolve_uploaded_file("olmayan_dosya.xlsx", user_id = 3L)
  expect_null(sonuc)
})

# Boş veya NULL istek yine NULL dönmelidir.
test_that("resolve_uploaded_file geçersiz girişte NULL döndürür", {
  expect_null(resolve_uploaded_file(NULL, user_id = 1L))
  expect_null(resolve_uploaded_file("", user_id = 1L))
  expect_null(resolve_uploaded_file(character(0), user_id = 1L))
})
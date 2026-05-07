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

# Geçerli fiziksel yol verildiğinde fonksiyon doğrudan çözümleyebilmelidir.
test_that("resolve_uploaded_file var olan fiziksel yolu doğrudan döndürür", {
  gecici_dir <- tempfile("uploadtest_")
  dir.create(gecici_dir, recursive = TRUE)
  gecici_dosya <- file.path(gecici_dir, "direk.docx")
  writeLines("ornek", gecici_dosya, useBytes = TRUE)
  on.exit(unlink(gecici_dir, recursive = TRUE, force = TRUE))

  sonuc <- resolve_uploaded_file(gecici_dosya, user_id = 1L)
  expect_false(is.null(sonuc))
  expect_equal(normalizePath(sonuc, winslash = "/"),
               normalizePath(gecici_dosya, winslash = "/"))
})

# Display adı ile kullanıcı kovasında kayıtlı dosya bulunur.
test_that("resolve_uploaded_file kullanıcı kovasında display adı ile bulur", {
  eski_yol <- MERGEN_INDEX_PATH
  gecici_dir <- tempfile("uploadidx_")
  dir.create(gecici_dir, recursive = TRUE)
  gercek_dosya <- file.path(gecici_dir, "20240101120000_0001_Rapor.docx")
  writeLines("ornek", gercek_dosya, useBytes = TRUE)

  gecici_idx <- file.path(gecici_dir, "index.json")
  assign("MERGEN_INDEX_PATH", gecici_idx, envir = globalenv())
  on.exit({
    assign("MERGEN_INDEX_PATH", eski_yol, envir = globalenv())
    unlink(gecici_dir, recursive = TRUE, force = TRUE)
  })

  idx <- list(
    "9" = list(
      "rapor.docx" = list(
        path    = gercek_dosya,
        display = "Rapor.docx"
      )
    )
  )
  .save_index(idx)

  # Display adıyla arama
  sonuc_display <- resolve_uploaded_file("Rapor.docx", user_id = 9L)
  expect_false(is.null(sonuc_display))
  expect_equal(normalizePath(sonuc_display, winslash = "/"),
               normalizePath(gercek_dosya, winslash = "/"))

  # Basename anahtarı ile arama da çalışmalı
  sonuc_base <- resolve_uploaded_file("rapor.docx", user_id = 9L)
  expect_false(is.null(sonuc_base))
})

# Kovalar arası legacy harita ile çapraz eşleşme bulunabilir.
test_that("resolve_uploaded_file user_id verilmediğinde legacy haritada arar", {
  eski_yol <- MERGEN_INDEX_PATH
  gecici_dir <- tempfile("uploadlegacy_")
  dir.create(gecici_dir, recursive = TRUE)
  gercek_dosya <- file.path(gecici_dir, "legacy.xlsx")
  writeLines("ornek", gercek_dosya, useBytes = TRUE)

  gecici_idx <- file.path(gecici_dir, "index.json")
  assign("MERGEN_INDEX_PATH", gecici_idx, envir = globalenv())
  on.exit({
    assign("MERGEN_INDEX_PATH", eski_yol, envir = globalenv())
    unlink(gecici_dir, recursive = TRUE, force = TRUE)
  })

  idx <- list(
    "legacy.xlsx" = list(path = gercek_dosya, display = "legacy.xlsx")
  )
  .save_index(idx)

  sonuc <- resolve_uploaded_file("legacy.xlsx", user_id = NULL)
  expect_false(is.null(sonuc))
  expect_equal(normalizePath(sonuc, winslash = "/"),
               normalizePath(gercek_dosya, winslash = "/"))
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
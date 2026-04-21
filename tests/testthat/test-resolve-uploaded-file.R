# ==============================================================================
# Dosya Yolu: tests/testthat/test-resolve-uploaded-file.R
# Açıklama: resolve_uploaded_file() fonksiyonunun kullanıcı kovası, display adı,
# basename ve hatalı senaryolarda doğru davrandığını doğrulayan testleri içerir.
# ==============================================================================

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

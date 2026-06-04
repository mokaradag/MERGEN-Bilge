# ==============================================================================
# Dosya Yolu: tests/testthat/test-config-sql-loader-helpers-behavior.R
# Açıklama: R/config_sql_loader.R saf SQL yardımcılarının davranışsal testleri.
#           Placeholder üretimi, metin kontrolü, yol çözümleme, UTF-8 BOM temizliği
#           ve SQL dosya okuma doğrulanır. Dosya, query_library yoksa kaynak
#           anında stop() ettiği için yardımcılar stop öncesinde tanımlanır ve
#           hata yutularak izole ortamda kullanılır.
# ==============================================================================

testthat::local_edition(3)

# config_sql_loader.R, query_library bulunmazsa stop() eder. Bu stop'tan ÖNCE
# tanımlanan yardımcı fonksiyonlar tryCatch ile yutulan kaynak sonrası ortamda
# kalır. cat() çıktısı capture.output ile bastırılır.
.sqll_env <- new.env(parent = globalenv())

local({
  kok <- resolve_repo_root_for_tests()

  # Bu test yalnızca config_sql_loader.R içindeki saf yardımcıları test eder.
  # Eğer global ortamda query_library varsa config_sql_loader.R sona kadar çalışır
  # ve dosyanın sonundaki rm(...) helper fonksiyonları siler. Bu yüzden source()
  # sırasında query_library geçici olarak kaldırılır; dosya guard noktasında stop()
  # eder, fakat helper fonksiyonlar .sqll_env içinde kalır.
  had_query_library <- exists("query_library", envir = globalenv(), inherits = FALSE)
  old_query_library <- if (had_query_library) {
    get("query_library", envir = globalenv(), inherits = FALSE)
  } else {
    NULL
  }

  if (had_query_library) {
    rm(query_library, envir = globalenv())
  }

  on.exit({
    if (had_query_library) {
      assign("query_library", old_query_library, envir = globalenv())
    }
  }, add = TRUE)

  invisible(utils::capture.output(suppressMessages(suppressWarnings(tryCatch(
    source(file.path(kok, "R", "config_sql_loader.R"), encoding = "UTF-8", local = .sqll_env),
    error = function(e) NULL
  )))))
})

.sqll_ready <- exists(".sql_has_text", envir = .sqll_env, inherits = FALSE)

# -----------------------------------------------------------------------------
# .sql_placeholder_text
# -----------------------------------------------------------------------------

test_that(".sql_placeholder_text sorgu kimliğini içeren placeholder SELECT üretir", {
  skip_if_not(.sqll_ready, "config_sql_loader yardımcıları yüklenemedi")
  txt <- .sqll_env$.sql_placeholder_text("Q_42")
  expect_true(grepl("Q_42", txt, fixed = TRUE))
  expect_true(grepl("sql_loader_placeholder", txt, fixed = TRUE))
  expect_true(grepl("^SELECT", txt))
})

# -----------------------------------------------------------------------------
# .sql_has_text
# -----------------------------------------------------------------------------

test_that(".sql_has_text dolu metni TRUE, boş/NULL/sadece boşluk için FALSE döner", {
  skip_if_not(.sqll_ready, "config_sql_loader yardımcıları yüklenemedi")
  expect_true(.sqll_env$.sql_has_text("SELECT 1"))
  expect_false(.sqll_env$.sql_has_text(""))
  expect_false(.sqll_env$.sql_has_text(NULL))
  expect_false(.sqll_env$.sql_has_text("   "))
  expect_true(.sqll_env$.sql_has_text("  x  "))
})

# -----------------------------------------------------------------------------
# .remove_utf8_bom
# -----------------------------------------------------------------------------

test_that(".remove_utf8_bom baştaki UTF-8 BOM'u kaldırır, BOM yoksa metni korur", {
  skip_if_not(.sqll_ready, "config_sql_loader yardımcıları yüklenemedi")
  bom <- intToUtf8(65279L)
  expect_identical(.sqll_env$.remove_utf8_bom(paste0(bom, "SELECT 1")), "SELECT 1")
  expect_identical(.sqll_env$.remove_utf8_bom("SELECT 2"), "SELECT 2")
  expect_identical(.sqll_env$.remove_utf8_bom(""), "")
})

# -----------------------------------------------------------------------------
# .resolve_sql_file_path
# -----------------------------------------------------------------------------

test_that(".resolve_sql_file_path var olan dosyayı çözer, olmayan/boş için NULL döner", {
  skip_if_not(.sqll_ready, "config_sql_loader yardımcıları yüklenemedi")
  tf <- tempfile(fileext = ".sql")
  writeLines("SELECT 1", tf)
  cozulen <- .sqll_env$.resolve_sql_file_path(tf)
  expect_true(file.exists(cozulen))

  expect_null(.sqll_env$.resolve_sql_file_path(file.path(tempdir(), "yok_olan.sql")))
  expect_null(.sqll_env$.resolve_sql_file_path(""))
})

# -----------------------------------------------------------------------------
# .read_sql_file_text
# -----------------------------------------------------------------------------

test_that(".read_sql_file_text SQL içeriğini okur ve satır sonlarını normalize eder", {
  skip_if_not(.sqll_ready, "config_sql_loader yardımcıları yüklenemedi")
  sf <- tempfile(fileext = ".sql")
  writeBin(charToRaw("SELECT *\r\nFROM Tablo"), sf)
  out <- .sqll_env$.read_sql_file_text(sf)
  expect_true(grepl("SELECT", out, fixed = TRUE))
  expect_true(grepl("FROM Tablo", out, fixed = TRUE))
  # CRLF, LF'e normalize edilmeli (CR kalmamalı).
  expect_false(grepl("\r", out, fixed = TRUE))
})

test_that(".read_sql_file_text boş dosyada hata verir", {
  skip_if_not(.sqll_ready, "config_sql_loader yardımcıları yüklenemedi")
  ef <- tempfile(fileext = ".sql")
  file.create(ef)
  expect_error(.sqll_env$.read_sql_file_text(ef))
})

test_that(".read_sql_file_text UTF-8 BOM'lu dosyayı temizleyerek okur", {
  skip_if_not(.sqll_ready, "config_sql_loader yardımcıları yüklenemedi")
  sf <- tempfile(fileext = ".sql")
  writeBin(c(as.raw(c(239, 187, 191)), charToRaw("SELECT 1")), sf)
  out <- .sqll_env$.read_sql_file_text(sf)
  # BOM baytları sonuçta görünmemeli; içerik SELECT 1 ile başlamalı.
  expect_true(startsWith(trimws(out), "SELECT 1"))
})
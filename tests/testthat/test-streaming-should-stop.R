# ==============================================================================
# Dosya Yolu: tests/testthat/test-streaming-should-stop.R
# Açıklama: streaming_should_stop() yardımcısının akış iptal bayrak dosyası
# senaryolarında doğru çalıştığını doğrulayan birim testleri. SSE worker
# içindeki duran akış protokolü bu tek noktadan kontrol edilir.
# ==============================================================================

# helpers_llm_sse.R yalnızca bu yardımcı için yüklenir.
local({
  if (!exists("streaming_should_stop", envir = globalenv(), inherits = FALSE)) {
    source(
      file.path(repo_root_for_tests, "R", "helpers_llm_sse.R"),
      encoding = "UTF-8",
      local = globalenv()
    )
  }
})

# Bayrak dosyası henüz oluşturulmadığında FALSE dönmelidir.
test_that("streaming_should_stop dosya yoksa FALSE döndürür", {
  gecici_yol <- tempfile("stopflag_")
  # Dosya oluşturulmadı
  expect_false(streaming_should_stop(gecici_yol))
})

# Bayrak dosyası varsa TRUE dönmelidir (kullanıcı durdurma istedi).
test_that("streaming_should_stop dosya varsa TRUE döndürür", {
  gecici_yol <- tempfile("stopflag_")
  writeLines("stop", gecici_yol, useBytes = TRUE)
  on.exit(try(unlink(gecici_yol, force = TRUE), silent = TRUE))
  expect_true(streaming_should_stop(gecici_yol))
})

# NULL girişte güvenli şekilde FALSE dönmeli, çökmemeli.
test_that("streaming_should_stop NULL girişte FALSE döndürür", {
  expect_false(streaming_should_stop(NULL))
})

# Boş string girişte güvenli fallback.
test_that("streaming_should_stop boş/geçersiz değerde FALSE döndürür", {
  expect_false(streaming_should_stop(""))
  expect_false(streaming_should_stop(NA_character_))
  expect_false(streaming_should_stop(character(0)))
})

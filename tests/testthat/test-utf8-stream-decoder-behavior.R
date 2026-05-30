# ==============================================================================
# Dosya Yolu: tests/testthat/test-utf8-stream-decoder-behavior.R
# Açıklama: R/helpers_llm_stream_io.R UTF-8 akış sınır/çözücü yardımcılarının
#           DAVRANIŞSAL testleri. SSE parçaları çoklu baytlı UTF-8 karakterleri
#           böldüğünde "input string invalid UTF-8" hatasının önlendiğini
#           gerçek fonksiyonları çağırarak doğrular. Ağ/DB/LLM gerekmez.
# ==============================================================================

.utf8io_source_once <- function() {
  if (exists("find_last_utf8_boundary", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_llm_stream_io.R"),
    encoding = "UTF-8", local = globalenv()
  )
  invisible(TRUE)
}

testthat::test_that("find_last_utf8_boundary tam ve yarım karakterleri doğru keser", {
  .utf8io_source_once()
  testthat::expect_identical(find_last_utf8_boundary(raw(0)), 0L)
  # Saf ASCII: tüm baytlar tam.
  testthat::expect_identical(find_last_utf8_boundary(charToRaw("ABC")), 3L)
  # Tam 2 baytlı 'ç' (0xC3 0xA7): tamamı döner.
  testthat::expect_identical(find_last_utf8_boundary(as.raw(c(0xC3, 0xA7))), 2L)
  # Yarım kalan lead byte (0xC3) sonda: lead'den öncesi kesilir.
  testthat::expect_identical(find_last_utf8_boundary(as.raw(c(0x41, 0x42, 0xC3))), 2L)
  # 4 baytlı emoji'nin ilk 2 baytı: tam karakter yok, başa kes.
  testthat::expect_identical(find_last_utf8_boundary(as.raw(c(0xF0, 0x9F))), 0L)
})

testthat::test_that("create_utf8_stream_decoder bölünmüş çok baytlı karakteri yeniden birleştirir", {
  .utf8io_source_once()
  dec <- create_utf8_stream_decoder()

  # 'ç' = C3 A7; ikinci bayt sonraki parçaya düşüyor.
  out1 <- dec$decode(as.raw(c(0x41, 0xC3)))   # "A" + yarım ç
  out2 <- dec$decode(as.raw(0xA7))            # ç'nin kalanı
  testthat::expect_identical(out1, "A")
  testthat::expect_identical(out2, "ç")  # ç

  # 4 baytlı emoji 3 parçaya bölünüyor: F0 9F | 9A | 80
  dec2 <- create_utf8_stream_decoder()
  a <- dec2$decode(as.raw(c(0xF0, 0x9F)))
  b <- dec2$decode(as.raw(0x9A))
  c3 <- dec2$decode(as.raw(0x80))
  testthat::expect_identical(a, "")
  testthat::expect_identical(b, "")
  testthat::expect_identical(c3, "\U0001F680")  # 🚀
})

testthat::test_that("create_utf8_stream_decoder reset ve flush tutarlı çalışır", {
  .utf8io_source_once()
  dec <- create_utf8_stream_decoder()
  # Yarım bayt buffer'da kalır; reset onu temizler.
  testthat::expect_identical(dec$decode(as.raw(c(0x42, 0xC3))), "B")
  dec$reset()
  # reset sonrası tek başına geçerli continuation gelirse temizlenir (geçersiz).
  testthat::expect_identical(dec$flush(), "")

  # flush, buffer'da yarım kalan tek lead byte'ı güvenle (boş) döndürür.
  dec2 <- create_utf8_stream_decoder()
  dec2$decode(as.raw(0xC3))               # yalnızca yarım ç, "" döner
  testthat::expect_identical(dec2$flush(), "")
})

testthat::test_that("append_stream_delta_line + decode_stream_delta_payload tam tur eder", {
  .utf8io_source_once()
  testthat::skip_if_not_installed("base64enc")
  testthat::skip_if_not_installed("jsonlite")

  tmp <- tempfile(fileext = ".jsonl")
  on.exit(unlink(tmp), add = TRUE)

  append_stream_delta_line(tmp, "Merhaba \U0001F680 dünya")
  append_stream_reasoning_line(tmp, "düşünce")

  lines <- readLines(tmp, encoding = "UTF-8", warn = FALSE)
  testthat::expect_identical(length(lines), 2L)

  p1 <- jsonlite::fromJSON(lines[1])
  p2 <- jsonlite::fromJSON(lines[2])
  testthat::expect_identical(p1$type, "delta")
  testthat::expect_identical(p2$type, "reasoning_delta")
  testthat::expect_identical(decode_stream_delta_payload(p1), "Merhaba \U0001F680 dünya")
  testthat::expect_identical(decode_stream_delta_payload(p2), "düşünce")
})

testthat::test_that("create_stream_line_appender geçersiz tipi reddeder", {
  .utf8io_source_once()
  testthat::expect_error(create_stream_line_appender("bogus"))
  testthat::expect_silent(create_stream_line_appender("delta"))
  testthat::expect_silent(create_stream_line_appender("reasoning_delta"))
})

testthat::test_that("decode_stream_delta_payload text yedeğini ve boş girdiyi işler", {
  .utf8io_source_once()
  testthat::expect_identical(decode_stream_delta_payload(NULL), "")
  testthat::expect_identical(decode_stream_delta_payload(list()), "")
  # text_b64 yoksa düz text alanına düşer.
  testthat::expect_identical(decode_stream_delta_payload(list(text = "merhaba")), "merhaba")
})

testthat::test_that("streaming_should_stop yalnızca gerçek dosyayı stop sinyali sayar", {
  .utf8io_source_once()
  testthat::expect_false(streaming_should_stop(NULL))
  testthat::expect_false(streaming_should_stop(""))
  testthat::expect_false(streaming_should_stop(NA_character_))
  testthat::expect_false(streaming_should_stop(file.path(tempdir(), "yok-boyle-bir-dosya.stop")))

  f <- tempfile(); file.create(f); on.exit(unlink(f), add = TRUE)
  testthat::expect_true(streaming_should_stop(f))

  d <- file.path(tempdir(), paste0("stopdir_", as.integer(Sys.time())))
  dir.create(d, showWarnings = FALSE); on.exit(unlink(d, recursive = TRUE), add = TRUE)
  # Dizin stop sinyali sayılmaz.
  testthat::expect_false(streaming_should_stop(d))
})

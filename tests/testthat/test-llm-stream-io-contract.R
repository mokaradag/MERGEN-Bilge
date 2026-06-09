# ==============================================================================
# Dosya Yolu: tests/testthat/test-llm-stream-io-contract.R
# Açıklama: SSE akış dosyası satır protokolü yardımcılarının davranışını korur.
# ==============================================================================

local({
  if (!exists("append_stream_delta_line", envir = globalenv(), inherits = FALSE) ||
      !exists("decode_stream_delta_payload", envir = globalenv(), inherits = FALSE)) {
    source(
      file.path(repo_root_for_tests, "R", "helpers_llm_stream_io.R"),
      encoding = "UTF-8",
      local = globalenv()
    )
  }
})

.read_stream_lines <- function(path) {
  raw_lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  lapply(raw_lines, function(line) {
    jsonlite::fromJSON(line, simplifyVector = FALSE)
  })
}

test_that("append_stream_delta_line UTF-8 metni base64 satırına yazar", {
  stream_path <- tempfile("stream_io_delta_", fileext = ".jsonl")
  on.exit(try(unlink(stream_path, force = TRUE), silent = TRUE), add = TRUE)

  append_stream_delta_line(stream_path, "Merhaba İğdır")

  payloads <- .read_stream_lines(stream_path)

  expect_length(payloads, 1L)
  expect_identical(payloads[[1]]$type, "delta")
  expect_identical(decode_stream_delta_payload(payloads[[1]]), "Merhaba İğdır")
})

test_that("append_stream_reasoning_line reasoning satır tipini korur", {
  stream_path <- tempfile("stream_io_reasoning_", fileext = ".jsonl")
  on.exit(try(unlink(stream_path, force = TRUE), silent = TRUE), add = TRUE)

  append_stream_reasoning_line(stream_path, "Önce düşünüyorum.")

  payloads <- .read_stream_lines(stream_path)

  expect_length(payloads, 1L)
  expect_identical(payloads[[1]]$type, "reasoning_delta")
  expect_identical(decode_stream_delta_payload(payloads[[1]]), "Önce düşünüyorum.")
})

test_that("stream satırı açık bağlantıda flush edilerek eklenir", {
  stream_path <- tempfile("stream_io_con_", fileext = ".jsonl")
  on.exit(try(unlink(stream_path, force = TRUE), silent = TRUE), add = TRUE)

  con <- file(stream_path, open = "ab")
  on.exit({
    if (isTRUE(try(isOpen(con), silent = TRUE))) {
      try(close(con), silent = TRUE)
    }
  }, add = TRUE)

  append_stream_delta_line(stream_file = "", text_value = "ilk", stream_con = con)
  append_stream_reasoning_line(stream_file = "", text_value = "ikinci", stream_con = con)
  close(con)

  payloads <- .read_stream_lines(stream_path)

  expect_length(payloads, 2L)
  expect_identical(
    vapply(payloads, `[[`, character(1), "type"),
    c("delta", "reasoning_delta")
  )
  expect_identical(
    vapply(payloads, decode_stream_delta_payload, character(1)),
    c("ilk", "ikinci")
  )
})

test_that("boş metin stream dosyası oluşturmaz", {
  stream_path <- tempfile("stream_io_empty_", fileext = ".jsonl")

  append_stream_delta_line(stream_path, "")

  expect_false(file.exists(stream_path))
})
# ------------------------------------------------------------------------------
# decode_stream_delta_payload skaler dönüş garantisi
# ------------------------------------------------------------------------------
# Bozuk/yarım yazılmış satırlardan gelen liste/boş alan şekilleri if() içinde
# NA veya logical(0) üretmemelidir; fonksiyon her girişte tek elemanlı karakter
# döndürmelidir. (Üretim yazıcısı boş metni hiç yazmaz; bu guard yalnızca bozuk
# satır uçlarını okuyucu tarafında zararsızlaştırır.)

test_that("decode_stream_delta_payload bozuk alan şekillerinde güvenli skaler döner", {
  # text_b64 boş listeye çözünen satır ([] -> list()): eskiden NA koşulu üretirdi.
  bozuk_b64 <- jsonlite::fromJSON('{"type":"delta","text_b64":[]}', simplifyVector = TRUE)
  expect_identical(decode_stream_delta_payload(bozuk_b64), "")

  # text alanı boş listeye çözünen satır: character(0) yerine "" dönmelidir.
  bozuk_text <- jsonlite::fromJSON('{"type":"delta","text":[]}', simplifyVector = TRUE)
  expect_identical(decode_stream_delta_payload(bozuk_text), "")

  # NULL payload ve alansız payload "" döner.
  expect_identical(decode_stream_delta_payload(NULL), "")
  expect_identical(decode_stream_delta_payload(list(type = "delta")), "")

  # NA değerli alanlar "" döner (nzchar(NA) tuzağına düşülmez).
  expect_identical(decode_stream_delta_payload(list(text_b64 = NA_character_)), "")
  expect_identical(decode_stream_delta_payload(list(text = NA_character_)), "")
})

test_that("decode_stream_delta_payload geçerli b64 ve düz metin davranışını korur", {
  turkce <- "Türkçe akış: çğıİöşü"
  gecerli_b64 <- list(
    type = "delta",
    text_b64 = base64enc::base64encode(charToRaw(enc2utf8(turkce)))
  )
  expect_identical(decode_stream_delta_payload(gecerli_b64), turkce)

  # Düz text alanı (eski biçim) skaler olarak korunur.
  expect_identical(
    decode_stream_delta_payload(list(type = "delta", text = "düz metin")),
    "düz metin"
  )

  # Hem b64 hem text varsa b64 önceliklidir (mevcut davranış).
  ikili <- list(
    type = "delta",
    text_b64 = base64enc::base64encode(charToRaw(enc2utf8("b64 kazanır"))),
    text = "düz kaybeder"
  )
  expect_identical(decode_stream_delta_payload(ikili), "b64 kazanır")
})

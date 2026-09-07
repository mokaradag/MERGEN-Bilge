# ==============================================================================
# Dosya Yolu: tests/testthat/test-streaming-io-behavior.R
# Açıklama: R/helpers_streaming_io.R saf akış G/Ç yardımcılarının davranışsal
#           testleri: artımlı akış dosyası okuma (dedup/yarım-satır/kesme/
#           bozuk-UTF8), uyarlanır yoklama aralığı, delta taşımacılığı tercihi ve
#           savunmacı metin üst sınırı. Shiny/DB/LLM/ağ gerekmez.
# ==============================================================================

testthat::local_edition(3)

source("../../R/helpers_runtime_metrics.R")
source("../../R/helpers_streaming_io.R")

.write_bytes <- function(path, text, append = FALSE) {
  con <- file(path, open = if (append) "ab" else "wb")
  on.exit(close(con), add = TRUE)
  writeBin(charToRaw(text), con)
}

# ------------------------------------------------------------------------------
# Artımlı okuma: mergen_stream_read_new_lines
# ------------------------------------------------------------------------------

test_that("artimli okuma yalnizca eklenen tam satirlari dondurur", {
  tmp <- tempfile(fileext = ".jsonl")
  on.exit(unlink(tmp), add = TRUE)

  # Iki tam satir + yarim ucuncu satir.
  .write_bytes(tmp, "L1\nL2\nL3")
  r1 <- mergen_stream_read_new_lines(tmp, mergen_stream_read_state_new())
  expect_identical(r1$lines, c("L1", "L2"))   # L3 tamponlanir
  expect_false(r1$used_fallback)

  # L3 tamamlanir + yeni satir eklenir.
  .write_bytes(tmp, "x\nL4\n", append = TRUE)
  r2 <- mergen_stream_read_new_lines(tmp, r1$state)
  expect_identical(r2$lines, c("L3x", "L4"))

  # Yeni bayt yok -> bos.
  r3 <- mergen_stream_read_new_lines(tmp, r2$state)
  expect_identical(r3$lines, character(0))
  expect_identical(r3$read_bytes, 0)
})

test_that("ardisik okumalarda cift satir uretilmez", {
  tmp <- tempfile(fileext = ".jsonl")
  on.exit(unlink(tmp), add = TRUE)

  .write_bytes(tmp, "A\nB\nC\n")
  st <- mergen_stream_read_state_new()

  all_lines <- character(0)
  for (i in 1:5) {
    res <- mergen_stream_read_new_lines(tmp, st)
    st <- res$state
    all_lines <- c(all_lines, res$lines)
  }
  expect_identical(all_lines, c("A", "B", "C"))
})

test_that("bayat dusuk stat boyutu offset'i geri alip satirlari tekrarlamaz", {
  tmp <- tempfile(fileext = ".jsonl")
  on.exit(unlink(tmp), add = TRUE)

  .write_bytes(tmp, "A\nB\n")

  original_file_size <- get("file.size", envir = globalenv(), inherits = TRUE)
  assign("file.size", function(...) 2, envir = globalenv())
  on.exit(assign("file.size", original_file_size, envir = globalenv()), add = TRUE)

  r1 <- mergen_stream_read_new_lines(tmp, mergen_stream_read_state_new())
  expect_identical(r1$lines, c("A", "B"))
  expect_identical(r1$state$offset, 4)
  expect_identical(r1$state$last_size, 2)

  r2 <- mergen_stream_read_new_lines(tmp, r1$state)
  expect_false(r2$used_fallback)
  expect_identical(r2$lines, character(0))
  expect_identical(r2$state$offset, 4)
  expect_identical(r2$state$last_size, 2)
})

test_that("newline gormeyen yari satir sonraki okumada tamamlanir", {
  tmp <- tempfile(fileext = ".jsonl")
  on.exit(unlink(tmp), add = TRUE)

  .write_bytes(tmp, "ab")  # newline yok
  r1 <- mergen_stream_read_new_lines(tmp, mergen_stream_read_state_new())
  expect_identical(r1$lines, character(0))

  .write_bytes(tmp, "c\n", append = TRUE)
  r2 <- mergen_stream_read_new_lines(tmp, r1$state)
  expect_identical(r2$lines, "abc")
})

test_that("eksik dosya guvenle bos sonuc dondurur", {
  res <- mergen_stream_read_new_lines(file.path(tempdir(), "yok-olmayan-dosya.jsonl"),
                                      mergen_stream_read_state_new())
  expect_identical(res$lines, character(0))
  expect_false(res$used_fallback)

  # NULL/bos yol da guvenli.
  expect_identical(mergen_stream_read_new_lines(NULL)$lines, character(0))
  expect_identical(mergen_stream_read_new_lines("")$lines, character(0))
})

test_that("dosya kesilmesi guvenli tam-okuma fallback'ine duser ve cift uretmez", {
  tmp <- tempfile(fileext = ".jsonl")
  on.exit(unlink(tmp), add = TRUE)

  .write_bytes(tmp, "A\nB\nC\n")
  r1 <- mergen_stream_read_new_lines(tmp, mergen_stream_read_state_new())
  expect_identical(r1$lines, c("A", "B", "C"))

  # Dosya offset'in altina kesilir (rotasyon benzeri).
  .write_bytes(tmp, "A\n")  # overwrite, daha kucuk
  r2 <- mergen_stream_read_new_lines(tmp, r1$state)
  expect_true(r2$used_fallback)
  # Zaten 3 satir yayimlanmisti; kesilen dosyada toplam 1 satir var -> yeni yok.
  expect_identical(r2$lines, character(0))
})

test_that("fallback yarim SSE satirini yayimlamaz, tamamlaninca tam gonderir", {
  tmp <- tempfile(fileext = ".jsonl")
  on.exit(unlink(tmp), add = TRUE)

  # Kesme senaryosu: once BUYUK dosya, sonra kucultulup yarim satirla biter
  # (fallback yalnizca gozlemlenen boyut offset'in ALTINA dustugunde tetiklenir).
  .write_bytes(tmp, paste0(paste(sprintf("L%03d", 1:40), collapse = "\n"), "\n"))
  durum <- mergen_stream_read_new_lines(tmp, mergen_stream_read_state_new())$state

  .write_bytes(tmp, 'data: {"a":1}\ndata: {"b":')
  r1 <- mergen_stream_read_new_lines(tmp, durum)
  expect_true(isTRUE(r1$used_fallback))
  # Yarim satir YAYIMLANMAZ; ham baytlar partial icinde tutulur.
  expect_false(any(grepl('{"b":', r1$lines, fixed = TRUE)))
  expect_true(length(r1$state$partial) > 0L)

  # Satir tamamlaninca TEK PARCA halinde gelir (iki yariya bolunmez).
  .write_bytes(tmp, '2}\n', append = TRUE)
  r2 <- mergen_stream_read_new_lines(tmp, r1$state)
  # TEK PARCA: fallback ayni SSE satirini iki kez yayimlarsa istemci yinelenen
  # olay alir; eslesme sayisi TAM OLARAK bir beklenir.
  expect_identical(sum(grepl('data: {"b":2}', r2$lines, fixed = TRUE)), 1L)
})

test_that("fallback ham okuma basarisiz olursa islenmis satir sayaci korunur", {
  tmp <- tempfile(fileext = ".jsonl")
  on.exit(unlink(tmp), add = TRUE)
  .write_bytes(tmp, "L1\nL2\nL3\n")

  durum <- mergen_stream_read_new_lines(tmp, mergen_stream_read_state_new())$state
  expect_identical(durum$processed_line_count, 3L)

  # Dosya BOS: ham okuma icerik dondurmez. Sayac sifirlanirsa bir sonraki
  # basarili fallback zaten yayimlanmis satirlari ikinci kez gonderirdi.
  .write_bytes(tmp, "")
  bos <- .mergen_stream_read_full_fallback(tmp, durum)
  expect_identical(bos$lines, character(0))
  expect_identical(bos$state$processed_line_count, 3L)
  expect_identical(bos$state$offset, durum$offset)
})

test_that("bozuk UTF-8 baytlari cokmeden ele alinir", {
  tmp <- tempfile(fileext = ".jsonl")
  on.exit(unlink(tmp), add = TRUE)

  con <- file(tmp, open = "wb")
  writeBin(c(charToRaw("ok"), as.raw(0xFF), charToRaw("\n")), con)
  close(con)

  res <- mergen_stream_read_new_lines(tmp, mergen_stream_read_state_new())
  expect_length(res$lines, 1L)
  # Gecersiz bayt dusurulur; "ok" korunur.
  expect_identical(res$lines[[1]], "ok")
})

test_that("artimli okuma Turkce/emoji satirlari bozmaz", {
  tmp <- tempfile(fileext = ".jsonl")
  on.exit(unlink(tmp), add = TRUE)

  emoji <- intToUtf8(0x1F680L)
  satir <- paste0("Türkçe çğıİöşü ", emoji)
  .write_bytes(tmp, enc2utf8(paste0(satir, "\n")))

  res <- mergen_stream_read_new_lines(tmp, mergen_stream_read_state_new())
  expect_identical(enc2utf8(res$lines[[1]]), enc2utf8(satir))
})

# ------------------------------------------------------------------------------
# Uyarlanir yoklama: mergen_stream_next_poll_interval_ms
# ------------------------------------------------------------------------------

.cfg_on <- function(...) {
  base <- list(enabled = TRUE, min_ms = 25L, max_ms = 250L, factor = 1.5, reset_on_delta = TRUE)
  modifyList(base, list(...))
}

test_that("yeni satir aralIgi min'e dondurur, bos yoklama geri ceker", {
  cfg <- .cfg_on()
  expect_identical(mergen_stream_next_poll_interval_ms(200L, TRUE, cfg), 25L)
  expect_identical(mergen_stream_next_poll_interval_ms(25L, FALSE, cfg), 38L)   # ceil(25*1.5)
  expect_identical(mergen_stream_next_poll_interval_ms(200L, FALSE, cfg), 250L) # max'a sinirli
})

test_that("geri cekilme kapaliyken aralik degismez", {
  cfg <- .cfg_on(enabled = FALSE)
  expect_identical(mergen_stream_next_poll_interval_ms(100L, FALSE, cfg), 100L)
  expect_identical(mergen_stream_next_poll_interval_ms(100L, TRUE, cfg), 100L)
})

test_that("reset_on_delta FALSE iken yeni satir mevcut araligi korur", {
  cfg <- .cfg_on(reset_on_delta = FALSE)
  expect_identical(mergen_stream_next_poll_interval_ms(100L, TRUE, cfg), 100L)
})

test_that("yoklama backoff yapilandirmasi varsayilanlari guvenlidir", {
  withr::with_envvar(c(
    MERGEN_STREAM_POLL_IDLE_BACKOFF = "", MERGEN_STREAM_POLL_MIN_MS = "",
    MERGEN_STREAM_POLL_MAX_MS = "", MERGEN_STREAM_POLL_BACKOFF_FACTOR = "",
    MERGEN_STREAM_POLL_RESET_ON_DELTA = ""
  ), {
    cfg <- mergen_stream_poll_backoff_config()
    expect_false(cfg$enabled)
    expect_identical(cfg$min_ms, 25L)
    expect_identical(cfg$max_ms, 250L)
    expect_identical(cfg$factor, 1.5)
    expect_true(cfg$reset_on_delta)
  })
})

# ------------------------------------------------------------------------------
# Delta tasimaciligi: mergen_stream_use_delta_transport
# ------------------------------------------------------------------------------

test_that("delta tasimaciligi karari profil ve ortam bayraklarini onurlandirir", {
  withr::with_envvar(c(MERGEN_STREAM_DELTA_DEFAULT = "", MERGEN_STREAM_FULL_UPDATE_LEGACY = ""), {
    expect_true(mergen_stream_use_delta_transport(list(use_delta_transport = TRUE)))
    expect_false(mergen_stream_use_delta_transport(list()))   # varsayilan: kapali
  })

  withr::with_envvar(c(MERGEN_STREAM_DELTA_DEFAULT = "true", MERGEN_STREAM_FULL_UPDATE_LEGACY = ""), {
    expect_true(mergen_stream_use_delta_transport(list()))    # genis delta
  })

  withr::with_envvar(c(MERGEN_STREAM_FULL_UPDATE_LEGACY = "true", MERGEN_STREAM_DELTA_DEFAULT = "true"), {
    expect_false(mergen_stream_use_delta_transport(list(use_delta_transport = TRUE)))  # legacy kazanir
  })
})

# ------------------------------------------------------------------------------
# SavunmacI metin ust siniri: mergen_stream_apply_text_cap
# ------------------------------------------------------------------------------

test_that("metin ust siniri guvenle kirpar ve not ekler", {
  res <- mergen_stream_apply_text_cap("abcdef", 3)
  expect_true(res$truncated)
  expect_identical(res$text, "abc")

  res2 <- mergen_stream_apply_text_cap("abcdef", 3, note = "X")
  expect_identical(res2$text, "abcX")

  res3 <- mergen_stream_apply_text_cap("ab", 5)
  expect_false(res3$truncated)
  expect_identical(res3$text, "ab")
})

test_that("sinir <=0 ise kirpma yapilmaz (sinirsiz)", {
  res <- mergen_stream_apply_text_cap("abcdef", 0)
  expect_false(res$truncated)
  expect_identical(res$text, "abcdef")

  res2 <- mergen_stream_apply_text_cap("abcdef", -1)
  expect_false(res2$truncated)
  expect_identical(res2$text, "abcdef")
})

test_that("ust sinir UTF-8 karakter sinirinda calisir (Turkce/emoji bozulmaz)", {
  turk <- paste(rep("ç", 10), collapse = "")
  res <- mergen_stream_apply_text_cap(turk, 4)
  expect_identical(nchar(res$text), 4L)
  expect_identical(res$text, "çççç")

  emoji <- paste(rep(intToUtf8(0x1F680L), 5), collapse = "")
  res2 <- mergen_stream_apply_text_cap(emoji, 2)
  expect_identical(nchar(res2$text), 2L)
})

test_that("metin ust siniri sayaci kirpinca artirir", {
  mergen_runtime_metrics_reset()
  mergen_stream_apply_text_cap("abcdef", 3, metric_name = "stream_text_truncated")
  expect_equal(mergen_runtime_metric_get("stream_text_truncated"), 1)
  # Sinir altinda artmaz.
  mergen_stream_apply_text_cap("ab", 50, metric_name = "stream_text_truncated")
  expect_equal(mergen_runtime_metric_get("stream_text_truncated"), 1)
})
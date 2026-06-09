# ==============================================================================
# Dosya Yolu: tests/testthat/test-streaming-poll-lifecycle-behavior.R
# Açıklama: R/helpers_streaming_poll_lifecycle.R saf karar yardımcılarının
#           DAVRANIŞSAL testleri. True-streaming yoklama döngüsündeki JSONL
#           satır sınıflandırması, yoklama aralığı / kalıcılaştırma gecikmesi
#           kararları ve worker dönüşü reasoning geri kazanım planını gerçek
#           fonksiyonları çağırarak doğrular. Shiny/DB/LLM/tarayıcı gerekmez.
# ==============================================================================

.poll_lifecycle_repo_root <- function() {
  if (exists("repo_root_for_tests", inherits = TRUE)) {
    return(get("repo_root_for_tests", inherits = TRUE))
  }

  candidates <- unique(normalizePath(
    c(getwd(), file.path(getwd(), ".."), file.path(getwd(), "..", "..")),
    winslash = "/",
    mustWork = FALSE
  ))

  for (candidate in candidates) {
    if (file.exists(file.path(candidate, "app.R")) &&
        dir.exists(file.path(candidate, "tests", "testthat"))) {
      return(candidate)
    }
  }

  stop("Streaming poll lifecycle testi repo kökünü bulamadı.", call. = FALSE)
}

.poll_lifecycle_source_once <- function() {
  root <- .poll_lifecycle_repo_root()

  if (!exists("%||%", envir = globalenv(), mode = "function", inherits = TRUE)) {
    source(
      file.path(root, "R", "utils_common.R"),
      encoding = "UTF-8",
      local = globalenv()
    )
  }

  if (!exists("mergen_stream_classify_poll_lines", envir = globalenv(),
              mode = "function", inherits = TRUE)) {
    source(
      file.path(root, "R", "helpers_streaming_poll_lifecycle.R"),
      encoding = "UTF-8",
      local = globalenv()
    )
  }

  invisible(TRUE)
}

# Gerçek worker yazıcısıyla aynı biçimde base64 JSONL satırı üretir.
.poll_lifecycle_b64_line <- function(line_type, text_value) {
  as.character(jsonlite::toJSON(
    list(
      type = line_type,
      text_b64 = base64enc::base64encode(charToRaw(enc2utf8(text_value)))
    ),
    auto_unbox = TRUE,
    null = "null"
  ))
}

# Yalnızca payload$text okuyan deterministik sahte çözücü.
.poll_lifecycle_plain_decode <- function(payload) {
  value <- as.character(payload$text %||% "")[1]
  if (is.na(value)) "" else enc2utf8(value)
}

# ------------------------------------------------------------------------------
# mergen_stream_poll_interval_ms
# ------------------------------------------------------------------------------

testthat::test_that("yoklama aralığı: eksik/boş profil varsayılan 50 ms döner", {
  .poll_lifecycle_source_once()

  testthat::expect_identical(mergen_stream_poll_interval_ms(list()), 50L)
  testthat::expect_identical(mergen_stream_poll_interval_ms(NULL), 50L)
})

testthat::test_that("yoklama aralığı: 15 ms hızlı profil değeri olduğu gibi korunur", {
  .poll_lifecycle_source_once()

  testthat::expect_identical(
    mergen_stream_poll_interval_ms(list(poll_interval_ms = 15L)),
    15L
  )
  testthat::expect_identical(
    mergen_stream_poll_interval_ms(list(poll_interval_ms = 50L)),
    50L
  )
  testthat::expect_identical(
    mergen_stream_poll_interval_ms(list(poll_interval_ms = "30")),
    30L
  )
})

testthat::test_that("yoklama aralığı: minimum altı veya geçersiz değer varsayılana döner", {
  .poll_lifecycle_source_once()

  testthat::expect_identical(
    mergen_stream_poll_interval_ms(list(poll_interval_ms = 5L)),
    50L
  )
  testthat::expect_identical(
    mergen_stream_poll_interval_ms(list(poll_interval_ms = NA_integer_)),
    50L
  )
  testthat::expect_identical(
    mergen_stream_poll_interval_ms(list(poll_interval_ms = "gecersiz")),
    50L
  )
})

# ------------------------------------------------------------------------------
# mergen_stream_persist_delay
# ------------------------------------------------------------------------------

testthat::test_that("kalıcılaştırma gecikmesi: hızlı profiller 0.30, diğerleri 0 alır", {
  .poll_lifecycle_source_once()

  testthat::expect_identical(mergen_stream_persist_delay("plain_fast"), 0.30)
  testthat::expect_identical(mergen_stream_persist_delay("coding_fast"), 0.30)
  testthat::expect_identical(mergen_stream_persist_delay("standard"), 0)
  testthat::expect_identical(mergen_stream_persist_delay(""), 0)
  testthat::expect_identical(mergen_stream_persist_delay(NULL), 0)
  testthat::expect_identical(mergen_stream_persist_delay(NA_character_), 0)
})

# ------------------------------------------------------------------------------
# mergen_stream_classify_poll_lines
# ------------------------------------------------------------------------------

testthat::test_that("satır sınıflandırma: boş girişte sıfır sayaç ve boş metin döner", {
  .poll_lifecycle_source_once()

  for (input in list(character(0), NULL)) {
    batches <- mergen_stream_classify_poll_lines(
      input,
      decode_fn = .poll_lifecycle_plain_decode
    )

    testthat::expect_identical(batches$delta_count, 0L)
    testthat::expect_identical(batches$reasoning_count, 0L)
    testthat::expect_identical(batches$delta_text, "")
    testthat::expect_identical(batches$reasoning_text, "")
    testthat::expect_identical(batches$debug_lines, character(0))
  }
})

testthat::test_that("satır sınıflandırma: delta/reasoning/debug ayrımı ve sıra korunur", {
  .poll_lifecycle_source_once()

  lines <- c(
    '{"type":"reasoning_delta","text":"Önce "}',
    '{"type":"delta","text":"Merhaba "}',
    '{"type":"stream_debug","text":"[DEBUG] ilk"}',
    '{"type":"delta","text":"dünya"}',
    '{"type":"reasoning_delta","text":"düşün"}'
  )

  batches <- mergen_stream_classify_poll_lines(
    lines,
    decode_fn = .poll_lifecycle_plain_decode
  )

  testthat::expect_identical(batches$delta_count, 2L)
  testthat::expect_identical(batches$delta_text, "Merhaba dünya")
  testthat::expect_identical(batches$reasoning_count, 2L)
  testthat::expect_identical(batches$reasoning_text, "Önce düşün")
  testthat::expect_identical(batches$debug_lines, "[DEBUG] ilk")
})

testthat::test_that("satır sınıflandırma: bozuk JSON, boş delta ve bilinmeyen tip atlanır", {
  .poll_lifecycle_source_once()

  lines <- c(
    '{"type":"delta","text":"Geçerli"}',
    '{bozuk json satiri',
    '{"type":"delta","text":""}',
    '{"type":"tanimsiz_tip","text":"yok sayılır"}',
    '{"baska_alan":1}'
  )

  batches <- mergen_stream_classify_poll_lines(
    lines,
    decode_fn = .poll_lifecycle_plain_decode
  )

  testthat::expect_identical(batches$delta_count, 1L)
  testthat::expect_identical(batches$delta_text, "Geçerli")
  testthat::expect_identical(batches$reasoning_count, 0L)
  testthat::expect_identical(batches$debug_lines, character(0))
})

testthat::test_that("satır sınıflandırma: gerçek base64 çözücüyle Türkçe ve emoji korunur", {
  .poll_lifecycle_source_once()

  testthat::skip_if_not_installed("base64enc")

  root <- .poll_lifecycle_repo_root()
  if (!exists("decode_stream_delta_payload", envir = globalenv(),
              mode = "function", inherits = TRUE)) {
    source(
      file.path(root, "R", "helpers_llm_stream_io.R"),
      encoding = "UTF-8",
      local = globalenv()
    )
  }

  # Emoji literal yerine parser-güvenli intToUtf8 kullanılır (repo kuralı).
  emoji <- intToUtf8(0x1F680L)
  turkce_delta <- "Türkiye'nin başkenti Ankara'dır: çğıİöşü "
  reasoning_metni <- "Düşünce: önce şehirleri karşılaştır"

  lines <- c(
    .poll_lifecycle_b64_line("delta", turkce_delta),
    .poll_lifecycle_b64_line("delta", emoji),
    .poll_lifecycle_b64_line("reasoning_delta", reasoning_metni)
  )

  batches <- mergen_stream_classify_poll_lines(
    lines,
    decode_fn = get("decode_stream_delta_payload", envir = globalenv())
  )

  testthat::expect_identical(batches$delta_count, 2L)
  testthat::expect_identical(batches$delta_text, paste0(turkce_delta, emoji))
  testthat::expect_identical(batches$reasoning_count, 1L)
  testthat::expect_identical(batches$reasoning_text, reasoning_metni)
})

testthat::test_that("satır sınıflandırma: decode_fn verilmezse düz metin fallback'i çalışır", {
  .poll_lifecycle_source_once()

  # Varsayılan yol globalde decode_stream_delta_payload varsa onu kullanır;
  # her iki durumda da düz {"text": ...} payload'u aynı sonuca çözülmelidir.
  batches <- mergen_stream_classify_poll_lines(
    '{"type":"delta","text":"fallback metni"}'
  )

  testthat::expect_identical(batches$delta_count, 1L)
  testthat::expect_identical(batches$delta_text, "fallback metni")
})

# ------------------------------------------------------------------------------
# mergen_stream_reasoning_recovery_plan
# ------------------------------------------------------------------------------

testthat::test_that("reasoning geri kazanımı: worker boşsa plan 'none' olur", {
  .poll_lifecycle_source_once()

  for (worker_value in list(NULL, "", NA_character_)) {
    plan <- mergen_stream_reasoning_recovery_plan(
      accumulated_reasoning = "canlı metin",
      result_reasoning = worker_value
    )

    testthat::expect_identical(plan$action, "none")
    testthat::expect_identical(plan$delta, "")
    testthat::expect_false(plan$mark_stream_started)
  }
})

testthat::test_that("reasoning geri kazanımı: canlı panel boşsa tam metin gönderilir", {
  .poll_lifecycle_source_once()

  worker_metni <- "Düşünce akışı: çğıİöşü değerlendirildi"

  plan <- mergen_stream_reasoning_recovery_plan(
    accumulated_reasoning = "",
    result_reasoning = worker_metni,
    stream_started = FALSE
  )

  testthat::expect_identical(plan$action, "replace_full")
  testthat::expect_identical(plan$delta, worker_metni)
  testthat::expect_identical(plan$accumulated, worker_metni)
  testthat::expect_true(plan$started_payload)
  testthat::expect_true(plan$mark_stream_started)
})

testthat::test_that("reasoning geri kazanımı: akış zaten başladıysa started bayrağı FALSE gider", {
  .poll_lifecycle_source_once()

  plan <- mergen_stream_reasoning_recovery_plan(
    accumulated_reasoning = "",
    result_reasoning = "tam metin",
    stream_started = TRUE
  )

  testthat::expect_identical(plan$action, "replace_full")
  testthat::expect_false(plan$started_payload)
  testthat::expect_true(plan$mark_stream_started)
})

testthat::test_that("reasoning geri kazanımı: canlı metin önekse yalnız eksik kuyruk gönderilir", {
  .poll_lifecycle_source_once()

  canli <- "Düşün"
  worker_metni <- "Düşünüyorum: çğıİöşü sonucu"

  plan <- mergen_stream_reasoning_recovery_plan(
    accumulated_reasoning = canli,
    result_reasoning = worker_metni,
    stream_started = TRUE
  )

  testthat::expect_identical(plan$action, "append_suffix")
  testthat::expect_identical(plan$delta, "üyorum: çğıİöşü sonucu")
  testthat::expect_identical(plan$accumulated, worker_metni)
  testthat::expect_false(plan$started_payload)
  testthat::expect_false(plan$mark_stream_started)

  # Önek + kuyruk birleşimi worker metnini birebir vermelidir (UTF-8 sınırı).
  testthat::expect_identical(paste0(canli, plan$delta), worker_metni)
})

testthat::test_that("reasoning geri kazanımı: birebir aynı veya uyumsuz kökte plan 'none' olur", {
  .poll_lifecycle_source_once()

  ayni <- mergen_stream_reasoning_recovery_plan(
    accumulated_reasoning = "aynı metin",
    result_reasoning = "aynı metin"
  )
  testthat::expect_identical(ayni$action, "none")

  uyumsuz <- mergen_stream_reasoning_recovery_plan(
    accumulated_reasoning = "canlı panel farklı başladı",
    result_reasoning = "worker bambaşka bir kökle döndü"
  )
  testthat::expect_identical(uyumsuz$action, "none")

  # Worker metni canlı metinden kısaysa (önek olamaz) yine 'none'.
  kisa <- mergen_stream_reasoning_recovery_plan(
    accumulated_reasoning = "uzun canlı reasoning metni",
    result_reasoning = "uzun"
  )
  testthat::expect_identical(kisa$action, "none")
})

testthat::test_that("reasoning geri kazanımı: normalize_fn worker metnine uygulanır", {
  .poll_lifecycle_source_once()

  buyuten <- function(x) toupper(as.character(x %||% "")[1])

  plan <- mergen_stream_reasoning_recovery_plan(
    accumulated_reasoning = "",
    result_reasoning = "kucuk metin",
    normalize_fn = buyuten
  )

  testthat::expect_identical(plan$action, "replace_full")
  testthat::expect_identical(plan$delta, "KUCUK METIN")
})

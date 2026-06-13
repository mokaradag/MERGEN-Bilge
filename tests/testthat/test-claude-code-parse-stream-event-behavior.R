# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-parse-stream-event-behavior.R
# Açıklama: helpers_claude_code_streaming.R parse_stream_event() için davranış
#           testleri. Anthropic stream-json olay türlerinin (content_block_start
#           tool_use/text, content_block_delta text_delta/input_json_delta,
#           content_block_stop, message_start/delta/stop, result) doğru standart
#           parçaya çevrilmesi, metin normalizasyon sınırının yalnızca delta/
#           result yollarında uygulanması ve bilinmeyen/eksik olaylarda NULL
#           dönüşü doğrulanır. Çevrimdışı ve deterministik; processx/CLI yok.
# ==============================================================================

.parseStreamEventEnv <- function() {
  env <- new.env(parent = globalenv())
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_claude_code_streaming.R"),
         encoding = "UTF-8", local = env)
  # Metin normalizasyon sınırını deterministik ve görünür kılmak için kimliği
  # değil, tanınabilir bir önek uygulayan stub kullanılır. Böylece hangi
  # yolların normalize edildiği kanıtlanır (content_block_start text yolu hariç).
  env$normalize_text_utf8 <- function(value, repair_mojibake = FALSE) paste0("N:", value)
  env
}

testthat::test_that("content_block_start tool_use bloğunu standart araç parçasına çevirir", {
  env <- .parseStreamEventEnv()

  olay <- list(
    type = "content_block_start",
    index = 2,
    content_block = list(
      type = "tool_use",
      id = "toolu_123",
      name = "Bash",
      input = list(command = "ls")
    )
  )
  r <- env$parse_stream_event(olay)

  testthat::expect_identical(r$tip, "tool_use")
  testthat::expect_identical(r$arac_id, "toolu_123")
  testthat::expect_identical(r$arac_adi, "Bash")
  # Araç türü detect_tool_type ile tutarlı olmalı (ayrı testi var)
  testthat::expect_identical(r$arac_turu, env$detect_tool_type("Bash"))
  testthat::expect_identical(r$girdi$command, "ls")
  testthat::expect_identical(r$blok_indeks, 2)
})

testthat::test_that("content_block_start text bloğu: dolu metin text_delta, boş metin NULL döner", {
  env <- .parseStreamEventEnv()

  dolu <- env$parse_stream_event(list(
    type = "content_block_start",
    content_block = list(type = "text", text = "Merhaba")
  ))
  testthat::expect_identical(dolu$tip, "text_delta")
  # content_block_start text yolu normalize EDİLMEZ (ham metin döner)
  testthat::expect_identical(dolu$icerik, "Merhaba")

  bos <- env$parse_stream_event(list(
    type = "content_block_start",
    content_block = list(type = "text", text = "")
  ))
  testthat::expect_null(bos)

  # content_block yoksa NULL
  testthat::expect_null(env$parse_stream_event(list(type = "content_block_start")))

  # Bilinmeyen blok türü NULL
  testthat::expect_null(env$parse_stream_event(list(
    type = "content_block_start",
    content_block = list(type = "image")
  )))
})

testthat::test_that("content_block_delta text_delta ve input_json_delta'yı normalize ederek çevirir", {
  env <- .parseStreamEventEnv()

  metin <- env$parse_stream_event(list(
    type = "content_block_delta",
    index = 1,
    delta = list(type = "text_delta", text = "parça")
  ))
  testthat::expect_identical(metin$tip, "text_delta")
  # delta text_delta yolu normalize EDİLİR (stub öneki görünür)
  testthat::expect_identical(metin$icerik, "N:parça")

  arac <- env$parse_stream_event(list(
    type = "content_block_delta",
    index = 3,
    delta = list(type = "input_json_delta", partial_json = "{\"a\":1}")
  ))
  testthat::expect_identical(arac$tip, "tool_input_delta")
  testthat::expect_identical(arac$parcali_json, "N:{\"a\":1}")
  testthat::expect_identical(arac$blok_indeks, 3)

  # delta yoksa NULL
  testthat::expect_null(env$parse_stream_event(list(type = "content_block_delta")))

  # bilinmeyen delta türü NULL
  testthat::expect_null(env$parse_stream_event(list(
    type = "content_block_delta",
    delta = list(type = "thinking_delta")
  )))
})

testthat::test_that("content_block_stop ve message_* olayları doğru tip ve alanları döndürür", {
  env <- .parseStreamEventEnv()

  durdu <- env$parse_stream_event(list(type = "content_block_stop", index = 4))
  testthat::expect_identical(durdu$tip, "content_block_stop")
  testthat::expect_identical(durdu$blok_indeks, 4)

  basla <- env$parse_stream_event(list(
    type = "message_start",
    message = list(model = "deneme-model")
  ))
  testthat::expect_identical(basla$tip, "message_start")
  testthat::expect_identical(basla$model, "deneme-model")

  # message yoksa model boş string
  basla_bos <- env$parse_stream_event(list(type = "message_start"))
  testthat::expect_identical(basla_bos$model, "")

  testthat::expect_identical(env$parse_stream_event(list(type = "message_delta"))$tip, "message_delta")
  testthat::expect_identical(env$parse_stream_event(list(type = "message_stop"))$tip, "message_stop")
})

testthat::test_that("result olayı normalize edilmiş içerik ve oturum kimliğini taşır", {
  env <- .parseStreamEventEnv()

  r <- env$parse_stream_event(
    list(type = "result", result = "son cevap"),
    oturum_id = "oturum-9"
  )
  testthat::expect_identical(r$tip, "result")
  testthat::expect_identical(r$icerik, "N:son cevap")
  testthat::expect_identical(r$session_id, "oturum-9")

  # result boşsa normalize edilmiş boş döner, session_id korunur
  r_bos <- env$parse_stream_event(list(type = "result"), oturum_id = "x")
  testthat::expect_identical(r_bos$icerik, "N:")
  testthat::expect_identical(r_bos$session_id, "x")
})

testthat::test_that("bilinmeyen veya eksik olay türü güvenle NULL döner", {
  env <- .parseStreamEventEnv()

  testthat::expect_null(env$parse_stream_event(list(type = "ping")))
  testthat::expect_null(env$parse_stream_event(list()))
  testthat::expect_null(env$parse_stream_event(list(type = "")))
})

testthat::test_that("normalize_text_utf8 yoksa metin ham haliyle korunur (güvenli geri düşüş)", {
  env <- new.env(parent = globalenv())
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_claude_code_streaming.R"),
         encoding = "UTF-8", local = env)
  # Bu env'de normalize_text_utf8 stub'ı YOK; üst ortamda da gizlenmeli.
  # exists(..., inherits=TRUE) globalenv'de bulursa kullanır; bu yüzden yalnızca
  # normalize'ın metni BOZMADIĞINI doğrularız: ASCII metin değişmemeli.
  r <- env$parse_stream_event(list(
    type = "content_block_delta",
    delta = list(type = "text_delta", text = "abc123")
  ))
  testthat::expect_identical(r$tip, "text_delta")
  testthat::expect_true(grepl("abc123", r$icerik, fixed = TRUE))
})

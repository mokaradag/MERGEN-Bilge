# ==============================================================================
# Dosya Yolu: tests/testthat/test-ai-expert-call-llm-behavior.R
# Açıklama: helpers_ai_expert.R call_ai_expert_llm() için davranış testleri.
#           Uç nokta/model eksikliğinde güvenli NULL dönüşü, HTTP hatası ve
#           bağlantı hatasında NULL, geçerli yanıttan metin çıkarımı, üretim
#           parametrelerinin (max_tokens/temperature) güvenli kıstaslanması ve
#           telaffuz düzeltmesinin (Bilge Yola -> Bilge Yolaç) uygulanması
#           doğrulanır. httr çağrıları mock'lanır; gerçek ağ/LLM çağrısı YOKTUR.
# ==============================================================================

.aiExpertLlmEnv <- function() {
  env <- new.env(parent = globalenv())
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_ai_expert.R"),
         encoding = "UTF-8", local = env)
  env
}

# Yakalanan POST gövdesini ve sabit bir yanıt metnini paylaşan yardımcı.
# .env = parent.frame(): mock'u çağıran test_that bloğuna kapsar (yardımcı
# döndükten sonra da aktif kalır), yoksa gerçek httr::POST çalışırdı.
.aiExpertMockHttr <- function(response_text, status = 200L, capture = NULL, throw = FALSE) {
  testthat::local_mocked_bindings(
    POST = function(url, body = NULL, ...) {
      if (!is.null(capture)) {
        capture$url <- url
        capture$body <- body
      }
      if (isTRUE(throw)) stop("bağlantı koptu")
      structure(list(), class = "response")
    },
    status_code = function(resp) status,
    content = function(resp, as = NULL, encoding = NULL) response_text,
    add_headers = function(...) list(...),
    timeout = function(...) NULL,
    .package = "httr",
    .env = parent.frame()
  )
}

.aiExpertJsonResponse <- function(content_text) {
  jsonlite::toJSON(list(choices = list(list(message = list(content = content_text)))),
                   auto_unbox = TRUE)
}

testthat::test_that("uç nokta yapılandırılmamışsa güvenli NULL döner", {
  withr::local_envvar(c(LOCAL_LLM_ENDPOINT = "", AI_EXPERT_MODEL = ""))
  env <- .aiExpertLlmEnv()

  out <- utils::capture.output(
    r <- env$call_ai_expert_llm("sistem", "bağlam", model_name = "", endpoint = "")
  )
  testthat::expect_null(r)
})

testthat::test_that("model adı yoksa güvenli NULL döner", {
  withr::local_envvar(c(LOCAL_LLM_ENDPOINT = "", AI_EXPERT_MODEL = ""))
  env <- .aiExpertLlmEnv()

  out <- utils::capture.output(
    r <- env$call_ai_expert_llm("sistem", "bağlam", model_name = "",
                                endpoint = "http://yerel/llm")
  )
  testthat::expect_null(r)
})

testthat::test_that("geçerli yanıttan metin çıkarır ve telaffuzu düzeltir", {
  env <- .aiExpertLlmEnv()
  capture <- new.env()

  out <- utils::capture.output({
    .aiExpertMockHttr(.aiExpertJsonResponse("  Bilge Yola hakkında bilgi.  "), capture = capture)
    r <- env$call_ai_expert_llm("sistem", "bağlam", model_name = "uzman-model",
                                endpoint = "http://yerel/llm", api_key = "k")
  })

  testthat::expect_false(is.null(r))
  # trimws + telaffuz düzeltmesi: "Bilge Yola" -> "Bilge Yolaç"
  testthat::expect_identical(r, "Bilge Yolaç hakkında bilgi.")
})

testthat::test_that("istek gövdesi model/mesaj yapısını ve güvenli parametre kıstaslamasını taşır", {
  env <- .aiExpertLlmEnv()
  capture <- new.env()

  out <- utils::capture.output({
    .aiExpertMockHttr(.aiExpertJsonResponse("Yanıt"), capture = capture)
    # max_tokens çok küçük (64 altı) -> 500'e; temperature aralık dışı (5) -> 1.2'ye
    env$call_ai_expert_llm("S", "C", model_name = "m1", endpoint = "http://yerel/llm",
                           max_tokens = 1, temperature = 5)
  })

  body <- capture$body
  testthat::expect_identical(body$model, "m1")
  testthat::expect_false(body$stream)
  testthat::expect_identical(body$max_tokens, 500L)
  testthat::expect_identical(body$temperature, 1.2)
  testthat::expect_length(body$messages, 2L)
  testthat::expect_identical(body$messages[[1]]$role, "system")
  testthat::expect_identical(body$messages[[2]]$role, "user")
})

testthat::test_that("HTTP 4xx hatasında NULL döner", {
  env <- .aiExpertLlmEnv()

  out <- utils::capture.output({
    .aiExpertMockHttr(.aiExpertJsonResponse("yok"), status = 500L)
    r <- env$call_ai_expert_llm("S", "C", model_name = "m1", endpoint = "http://yerel/llm")
  })
  testthat::expect_null(r)
})

testthat::test_that("bağlantı hatasında (POST stop) NULL döner", {
  env <- .aiExpertLlmEnv()

  out <- utils::capture.output({
    .aiExpertMockHttr(.aiExpertJsonResponse("yok"), throw = TRUE)
    r <- env$call_ai_expert_llm("S", "C", model_name = "m1", endpoint = "http://yerel/llm")
  })
  testthat::expect_null(r)
})

testthat::test_that("yanıt boş içerik taşıyorsa NULL döner", {
  env <- .aiExpertLlmEnv()

  out <- utils::capture.output({
    .aiExpertMockHttr(.aiExpertJsonResponse("   "))  # yalnızca boşluk
    r <- env$call_ai_expert_llm("S", "C", model_name = "m1", endpoint = "http://yerel/llm")
  })
  testthat::expect_null(r)
})

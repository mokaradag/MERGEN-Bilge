# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-provenance-delivery-contract.R
# Açıklama: Köken alt bilgisi teslim sözleşmeleri:
#           derin analiz telemetrisi/kökeni, doğrudan yanıt dekorasyonu ve
#           TTS yükünden köken alt bilgisinin çıkarılması.
# ==============================================================================

.pk_p2_read_source <- function(rel_path) {
  path <- file.path(resolve_repo_root_for_tests(), rel_path)
  raw_bytes <- readBin(path, what = "raw", n = file.info(path)$size)
  iconv(rawToChar(raw_bytes), from = "UTF-8", to = "UTF-8", sub = "byte")
}

test_that("doğrudan AI yanıtları mesaj sınırında bekleyen köken alt bilgisini tüketir", {
  env <- new.env(parent = globalenv())
  source(
    file.path(resolve_repo_root_for_tests(), "R", "server_init_chat_runtime.R"),
    encoding = "UTF-8",
    local = env
  )

  captured <- new.env(parent = emptyenv())
  env$pk_provenance_decorate <- function(content, session) paste0(content, "|KOKEN")
  env$chat_add_message <- function(...) {
    args <- list(...)
    captured$content <- args$content
    args
  }

  runtime <- env$serverInitChatRuntime(
    session = list(),
    values = list(),
    settings_data = list(),
    output = list(),
    resolve_current_user_id = function() 7L,
    stop_generation = function() FALSE
  )

  runtime$add_message("Boş sonuç", "ai")
  expect_identical(captured$content, "Boş sonuç|KOKEN")

  runtime$add_message("Kullanıcı metni", "user")
  expect_identical(captured$content, "Kullanıcı metni")
})

test_that("derin analiz her sorguyu gözlemler ve tek birleşik köken alt bilgisi saklar", {
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
  # Faz 6 (D16): kimlik kapısı, son tarih aritmetiği, sınırlı SQL yürütme ve
  # gözlem/alt bilgi FABRİKASI ayrı sahip dosyalarındadır; izole test GERÇEK
  # sahipleri yükler (CLAUDE.md davranış-testi kuralı).
  for (yardimci in c("helpers_pk_config.R", "helpers_pk_async_cancel.R",
                     "helpers_pk_exec_context.R", "helpers_pk_result_size.R", "helpers_pk_sql_execute.R",
                     "helpers_deep_analysis_reconcile.R",
                     "helpers_deep_analysis_phase6.R",
                     "helpers_deep_analysis_selector.R",
                     "helpers_deep_analysis.R")) {
    source(
      file.path(resolve_repo_root_for_tests(), "R", yardimci),
      encoding = "UTF-8", local = env
    )
  }

  # D16 kimlik kapısı: ana yolun çözümleyicisi stub'lanır (SSO/DB yok).
  env$resolve_pk_analysis_username <- function(session) {
    list(ready = TRUE, username = "kullanici1", reason = "ok")
  }

  env$cat <- function(...) invisible(NULL)
  env$query_library <- list()
  env$get_analysis_detail_config <- function(level) list(id = level)
  env$get_connection <- function(...) list(conn = "PRIMARY")
  env$release_connection <- function(...) invisible(TRUE)
  env$get_user_rls_info <- function(username, conn) list(authorized = TRUE)
  env$find_multiple_queries_with_ai <- function(...) {
    list(
      list(id = "q1", name = "Sorgu Bir"),
      list(id = "q2", name = "Sorgu İki")
    )
  }
  env$select_smart_query <- function(...) NULL
  env$execute_single_deep_query <- function(query, ...) {
    list(
      query_name = query$name,
      success = TRUE,
      row_count = 3L,
      pk_observation = list(
        query_id = query$id,
        query_name = query$name,
        filter_status = "disabled",
        filters = list(),
        pre_rls_rows = 4L,
        authorized_rows = 3L,
        filtered_rows = 3L,
        outcome = "Basarili"
      )
    )
  }
  env$build_deep_analysis_context <- function(...) "BIRLESIK-BAGLAM"
  env$pk_provenance_current_request_id <- function(session) "req-deep"

  env$.observed <- list()
  env$pk_analysis_observe <- function(session, conn, info) {
    env$.observed[[length(env$.observed) + 1L]] <- info
    paste0(
      "\n\n---\n**Analiz Kaynağı**\n",
      "- **Sorgu:** ", info$query_id, " · ", info$query_name, "\n"
    )
  }
  env$.stashed <- NULL
  env$pk_provenance_stash <- function(session, footer, request_id = NULL, ...) {
    env$.stashed <- list(footer = footer, request_id = request_id)
    invisible(TRUE)
  }

  result <- env$pk_deep_analysis_process(
    "iki sorguyu karşılaştır",
    list(),
    list(userData = list(system_username = "kullanici")),
    detail_level = "standart",
    stop_check = function() FALSE
  )

  expect_identical(result, "BIRLESIK-BAGLAM")
  expect_length(env$.observed, 2L)
  expect_true(all(vapply(env$.observed, function(x) isTRUE(x$deep_thinking), logical(1))))
  expect_identical(vapply(env$.observed, function(x) x$query_id, character(1)), c("q1", "q2"))
  expect_true(grepl("Analiz Kaynağı (Derin Analiz)", env$.stashed$footer, fixed = TRUE))
  expect_true(grepl("Sorgu Bir", env$.stashed$footer, fixed = TRUE))
  expect_true(grepl("Sorgu İki", env$.stashed$footer, fixed = TRUE))
  expect_identical(env$.stashed$request_id, "req-deep")
})

test_that("TTS köken alt bilgisi sınırını sentezden önce kaldırır", {
  txt <- .pk_p2_read_source("R/server_tts_handlers.R")

  marker_pos <- regexpr("provenance_marker <-", txt, fixed = TRUE, useBytes = TRUE)
  buffered_tts_pos <- regexpr("synthesize_speech(current_text", txt, fixed = TRUE, useBytes = TRUE)
  streaming_tts_pos <- regexpr("mergen_speech_pcm_stream_start(session, persona_id, full_text", txt,
                                fixed = TRUE, useBytes = TRUE)

  expect_gt(marker_pos, 0L)
  expect_gt(buffered_tts_pos, marker_pos)
  expect_gt(streaming_tts_pos, marker_pos)
  expect_true(grepl("substr(full_text, 1L, marker_pos - 1L)", txt, fixed = TRUE, useBytes = TRUE))
})

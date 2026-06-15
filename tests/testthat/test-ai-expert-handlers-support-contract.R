# ==============================================================================
# Dosya Yolu: tests/testthat/test-ai-expert-handlers-support-contract.R
# Açıklama: AI Uzman sunucu işleyicilerinin saf karar yardımcılarının
#           (ai_expert_page_name_tr, ai_expert_first_idle_delay_ms,
#           ai_expert_idle_interval_ms, build_ai_expert_idle_user_context)
#           R/server_ai_expert_handlers.R'den ayrılıp
#           R/helpers_ai_expert_handlers_support.R dosyasına taşındığını, kaynak
#           sırasının (yardımcı ÖNCE) korunduğunu, handler'ın artık bu mantığı
#           inline taşımadığını ve yardımcı dosyanın Shiny/DB/ağ-bağsız kaldığını
#           doğrular. Yapısal sözleşme; davranış behavior testinde kapsanır.
# ==============================================================================

.read_repo_text_aix_handlers_support <- function(rel_path) {
  abs_path <- file.path(repo_root_for_tests, rel_path)

  if (!file.exists(abs_path)) {
    stop(sprintf("Dosya bulunamadı: %s", rel_path), call. = FALSE)
  }

  size <- suppressWarnings(file.info(abs_path)$size[1])
  if (is.na(size) || size <= 0) {
    return("")
  }

  con <- file(abs_path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_data <- readBin(con, what = "raw", n = size)
  txt <- suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
  )

  if (is.na(txt)) {
    txt <- ""
  }

  txt <- gsub("\r\n?|\r", "\n", txt, perl = TRUE)
  enc2utf8(txt)
}

.aix_handlers_support_public_fns <- c(
  "ai_expert_page_name_tr",
  "ai_expert_first_idle_delay_ms",
  "ai_expert_idle_interval_ms",
  "build_ai_expert_idle_user_context"
)

test_that("helpers_ai_expert_handlers_support.R exists and exposes the pure helpers", {
  helper_path <- file.path(
    repo_root_for_tests, "R", "helpers_ai_expert_handlers_support.R"
  )

  expect_true(
    file.exists(helper_path),
    info = "R/helpers_ai_expert_handlers_support.R dosyası eklenmelidir."
  )

  # Source yan etkisizdir: fonksiyon gövdeleri çalışmaz, sadece tanımlanır.
  support_env <- new.env(parent = globalenv())
  suppressWarnings(source(helper_path, encoding = "UTF-8", local = support_env))

  for (fn in .aix_handlers_support_public_fns) {
    expect_true(
      exists(fn, envir = support_env, mode = "function", inherits = FALSE),
      info = sprintf("Eksik AI Uzman handler yardımcısı: %s", fn)
    )
  }
})

test_that("runtime manifest sources the support helper before server_ai_expert_handlers.R", {
  expect_source_manifest_order_for_tests(
    c(
      "R/helpers_ai_expert_handlers_support.R",
      "R/server_ai_expert_handlers.R"
    ),
    label = "Kaynak sırası support helper -> server_ai_expert_handlers.R olmalıdır:"
  )
})

test_that("server_ai_expert_handlers.R no longer owns the extracted pure decision logic", {
  handler_txt <- .read_repo_text_aix_handlers_support("R/server_ai_expert_handlers.R")

  # Taşınan saf mantık handler'a geri dönmemeli.
  forbidden_inline <- c(
    "get_first_idle_delay_ms <- function",
    "get_idle_interval <- function",
    "switch(page,",
    "switch(current_page_val,",
    "context_parts <- list()"
  )

  for (pattern in forbidden_inline) {
    expect_false(
      grepl(pattern, handler_txt, fixed = TRUE),
      info = sprintf(
        "Bu mantık artık R/helpers_ai_expert_handlers_support.R içinde olmalıdır: %s",
        pattern
      )
    )
  }

  # Handler artık taşınan saf yardımcıları çağırmalı.
  expected_calls <- c(
    "ai_expert_page_name_tr(",
    "ai_expert_first_idle_delay_ms(",
    "ai_expert_idle_interval_ms(",
    "build_ai_expert_idle_user_context("
  )

  for (pattern in expected_calls) {
    expect_true(
      grepl(pattern, handler_txt, fixed = TRUE),
      info = sprintf("server_ai_expert_handlers.R şu yardımcıyı çağırmalıdır: %s", pattern)
    )
  }

  # Orkestrasyon sorumlulukları handler'da kalmalı.
  expect_true(
    grepl("aiExpertHandlersInit <- function", handler_txt, fixed = TRUE),
    info = "aiExpertHandlersInit handler dosyasında kalmalıdır."
  )
})

test_that("helpers_ai_expert_handlers_support.R stays pure (Shiny/DB/network-free)", {
  txt <- .read_repo_text_aix_handlers_support("R/helpers_ai_expert_handlers_support.R")

  # Saf karar yardımcısı: reaktif/observer/render/oturum yan etkisi olmamalı.
  expect_false(
    grepl("reactiveVal|observeEvent|renderUI|outputOptions|uiOutput|moduleServer", txt, perl = TRUE),
    info = "Support helper Shiny reaktif/observer/render bağlamamalıdır."
  )

  expect_false(
    grepl("sendCustomMessage|session\\$|tracked_future_promise", txt, perl = TRUE),
    info = "Support helper oturum/worker yan etkisi içermemelidir."
  )

  expect_false(
    grepl("dbGetQuery|dbConnect|DBI::|httr::|GET\\(|POST\\(", txt, perl = TRUE),
    info = "Support helper DB/ağ çağrısı içermemelidir."
  )
})

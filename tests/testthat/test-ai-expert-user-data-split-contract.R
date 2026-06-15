# ==============================================================================
# Dosya Yolu: tests/testthat/test-ai-expert-user-data-split-contract.R
# Açıklama: AI Uzman worker-safe DB okuyucularının (fetch_user_full_name,
#           fetch_user_work_context, fetch_recent_user_prompts,
#           fetch_user_last_login) R/helpers_ai_expert.R'den ayrılıp
#           R/helpers_ai_expert_user_data.R dosyasına taşındığını, kaynak
#           sırasının (okuyucular ÖNCE) korunduğunu ve helpers_ai_expert.R'nin
#           bu okuyucuları artık inline tanımlamadığını doğrular. Bu yapısal bir
#           sözleşmedir; okuyucuların davranışı test-ai-expert-db-fetch-behavior.R
#           içinde kapsanır. Gerçek DB/ağ GEREKMEZ.
# ==============================================================================

.read_repo_text_aix_user_data_split <- function(rel_path) {
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

.aix_user_data_reader_fns <- c(
  "fetch_user_full_name",
  "fetch_user_work_context",
  "fetch_recent_user_prompts",
  "fetch_user_last_login"
)

test_that("helpers_ai_expert_user_data.R exists and exposes the worker-safe DB readers", {
  helper_path <- file.path(
    repo_root_for_tests, "R", "helpers_ai_expert_user_data.R"
  )

  expect_true(
    file.exists(helper_path),
    info = "R/helpers_ai_expert_user_data.R dosyası eklenmelidir."
  )

  # Source yan etkisizdir: fonksiyon gövdeleri çalışmaz, sadece tanımlanır.
  reader_env <- new.env(parent = globalenv())
  suppressWarnings(source(helper_path, encoding = "UTF-8", local = reader_env))

  for (fn in .aix_user_data_reader_fns) {
    expect_true(
      exists(fn, envir = reader_env, mode = "function", inherits = FALSE),
      info = sprintf("Eksik AI Uzman DB okuyucusu: %s", fn)
    )
  }
})

test_that("runtime manifest sources user-data readers before helpers_ai_expert.R", {
  expect_source_manifest_order_for_tests(
    c(
      "R/helpers_ai_expert_user_data.R",
      "R/helpers_ai_expert.R"
    ),
    label = "Kaynak sırası user-data okuyucuları -> helpers_ai_expert.R olmalıdır:"
  )
})

test_that("helpers_ai_expert.R no longer owns the extracted DB readers", {
  module_txt <- .read_repo_text_aix_user_data_split("R/helpers_ai_expert.R")

  forbidden_inline_defs <- c(
    "fetch_user_full_name <- function",
    "fetch_user_work_context <- function",
    "fetch_recent_user_prompts <- function",
    "fetch_user_last_login <- function"
  )

  for (pattern in forbidden_inline_defs) {
    expect_false(
      grepl(pattern, module_txt, fixed = TRUE),
      info = sprintf(
        "Bu okuyucu artık R/helpers_ai_expert_user_data.R içinde olmalıdır: %s",
        pattern
      )
    )
  }

  # helpers_ai_expert.R orkestrasyon/prompt sorumluluklarını korumalıdır.
  expected_kept_defs <- c(
    "sanitize_ai_expert_pronunciation <- function",
    "call_ai_expert_llm <- function",
    "build_ai_expert_user_context <- function",
    "get_ai_expert_generation_config <- function",
    "build_ai_expert_system_prompt <- function"
  )

  for (pattern in expected_kept_defs) {
    expect_true(
      grepl(pattern, module_txt, fixed = TRUE),
      info = sprintf("helpers_ai_expert.R şu sorumluluğu korumalıdır: %s", pattern)
    )
  }
})

test_that("helpers_ai_expert_user_data.R keeps the read-boundary contract and stays Shiny-free", {
  txt <- .read_repo_text_aix_user_data_split("R/helpers_ai_expert_user_data.R")

  # Kullanıcıya görünen DB alanları kanonik görünür-değer normalizasyonundan
  # geçmelidir (eski mojibake TTS/altyazıya onarılmadan sızmasın).
  expect_true(
    grepl("normalize_db_read_visible_value", txt, fixed = TRUE),
    info = "Okuma sınırı normalize_db_read_visible_value üzerinden korunmalıdır."
  )

  expect_false(
    grepl("observeEvent\\s*\\(|renderUI\\s*\\(|outputOptions\\s*\\(|uiOutput\\s*\\(", txt, perl = TRUE),
    info = "AI Uzman DB okuyucu dosyası Shiny observer/render/output bağlamamalıdır."
  )

  expect_false(
    grepl("sendCustomMessage|session\\$close", txt, perl = TRUE),
    info = "AI Uzman DB okuyucu dosyası oturum yan etkisi içermemelidir."
  )
})

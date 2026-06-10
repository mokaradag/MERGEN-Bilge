# ==============================================================================
# Dosya Yolu: tests/testthat/test-config-api-split-contract.R
# Açıklama: config_api.R bölünme sınırını korur: Derin Düşünme yetenek/endpoint
#           kaydı R/helpers_deep_thinking_model_capabilities.R içinde, kullanıcı
#           API anahtarı kripto/saklama katmanı R/helpers_api_key_crypto.R
#           içinde kalmalıdır. Kaynak sırası, guard'lı delegasyon ve taşınan
#           mantığın config_api.R'ye geri dönmemesi doğrulanır.
# ==============================================================================

.read_repo_text_cfg_split <- function(rel_path) {
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

test_that("helpers_deep_thinking_model_capabilities.R exists and exposes pure helpers", {
  helper_path <- file.path(
    repo_root_for_tests, "R", "helpers_deep_thinking_model_capabilities.R"
  )

  expect_true(
    file.exists(helper_path),
    info = "R/helpers_deep_thinking_model_capabilities.R dosyası eklenmelidir."
  )

  dt_env <- new.env(parent = globalenv())
  source(helper_path, encoding = "UTF-8", local = dt_env)

  for (fn in c("collect_deep_thinking_model_ids",
               "apply_deep_thinking_model_capabilities")) {
    expect_true(
      exists(fn, envir = dt_env, mode = "function", inherits = FALSE),
      info = sprintf("Eksik deep-thinking yetenek helper'ı: %s", fn)
    )
  }
})

test_that("helpers_api_key_crypto.R exists and exposes the crypto/storage surface", {
  helper_path <- file.path(repo_root_for_tests, "R", "helpers_api_key_crypto.R")

  expect_true(
    file.exists(helper_path),
    info = "R/helpers_api_key_crypto.R dosyası eklenmelidir."
  )

  crypto_txt <- .read_repo_text_cfg_split("R/helpers_api_key_crypto.R")

  expected_defs <- c(
    ".api_user_file <- function",
    ".hash_key_hex <- function",
    ".enc_key <- function",
    ".dec_key <- function",
    "save_user_api_key <- function",
    "load_user_api_key <- function",
    "user_api_key_exists <- function",
    "verify_user_api_key <- function",
    # NUL-tuz regresyon guard'ı korunmalıdır (CLAUDE.md sözleşmesi).
    "salt[salt == as.raw(0L)] <- as.raw(1L)",
    # Atomik yazım yolu korunmalıdır.
    "atomic_write_json("
  )

  for (pattern in expected_defs) {
    expect_true(
      grepl(pattern, crypto_txt, fixed = TRUE),
      info = sprintf("helpers_api_key_crypto.R şu tanımı içermelidir: %s", pattern)
    )
  }
})

test_that("runtime manifest orders capability helpers before config_api and crypto after it", {
  expect_source_manifest_order_for_tests(
    c(
      "R/helpers_vision_model_capabilities.R",
      "R/helpers_deep_thinking_model_capabilities.R",
      "R/config_api.R",
      "R/helpers_api_key_crypto.R",
      "R/helpers_api_key_identity.R"
    ),
    label = "Kaynak sırası vision -> deep_thinking -> config_api -> api_key_crypto -> api_key_identity olmalıdır:"
  )
})

test_that("config_api.R delegates deep-thinking registration through the guarded helper call", {
  cfg_txt <- .read_repo_text_cfg_split("R/config_api.R")

  expect_true(
    grepl('exists("apply_deep_thinking_model_capabilities", mode = "function"',
          cfg_txt, fixed = TRUE),
    info = "config_api.R guard'lı apply_deep_thinking_model_capabilities çağrısını korumalıdır."
  )

  expect_true(
    grepl("api_config <- apply_deep_thinking_model_capabilities(api_config)",
          cfg_txt, fixed = TRUE),
    info = "config_api.R deep-thinking kaydını helper'a delege etmelidir."
  )

  # Vision delegasyonu da yerinde kalmalıdır.
  expect_true(
    grepl("apply_vision_model_capabilities(api_config", cfg_txt, fixed = TRUE),
    info = "config_api.R vision yetenek delegasyonunu korumalıdır."
  )
})

test_that("config_api.R no longer owns the moved deep-thinking or crypto logic", {
  cfg_txt <- .read_repo_text_cfg_split("R/config_api.R")

  forbidden_inline_logic <- c(
    # Eski iki-blok deep-thinking kayıt mekanizması geri dönmemelidir.
    ".mb_deep_thinking_capability_template",
    ".deep_thinking_capability_defaults",
    "for (.mb_dt_model",
    "for (.deep_model_id",
    # Kripto/saklama katmanı geri dönmemelidir.
    ".enc_key <- function",
    ".dec_key <- function",
    ".hash_key_hex <- function",
    "save_user_api_key <- function",
    "load_user_api_key <- function",
    "verify_user_api_key <- function",
    "aes_gcm_encrypt",
    "openssl::rand_bytes"
  )

  for (pattern in forbidden_inline_logic) {
    expect_false(
      grepl(pattern, cfg_txt, fixed = TRUE),
      info = sprintf("Bu mantık artık config_api.R içinde olmamalıdır: %s", pattern)
    )
  }

  # config_api.R sahip olduğu sorumlulukları korumalıdır.
  expect_true(
    grepl("validate_api_key <- function", cfg_txt, fixed = TRUE),
    info = "API anahtarı doğrulama orkestrasyonu config_api.R'de kalmalıdır."
  )
  expect_true(
    grepl("api_config <- list(", cfg_txt, fixed = TRUE),
    info = "api_config tanımı config_api.R'de kalmalıdır."
  )
})

test_that("helpers_deep_thinking_model_capabilities.R remains side-effect-free", {
  txt <- .read_repo_text_cfg_split("R/helpers_deep_thinking_model_capabilities.R")

  expect_false(
    grepl("observeEvent\\s*\\(|renderUI\\s*\\(|shiny::|sendCustomMessage", txt, perl = TRUE),
    info = "Deep-thinking yetenek helper'ı Shiny içermemelidir."
  )

  expect_false(
    grepl("dbConnect\\s*\\(|odbc::|httr::|curl::", txt, perl = TRUE),
    info = "Deep-thinking yetenek helper'ı DB/ağ çağrısı içermemelidir."
  )

  expect_false(
    grepl("file\\.create\\s*\\(|dir\\.create\\s*\\(|unlink\\s*\\(|writeLines\\s*\\(", txt, perl = TRUE),
    info = "Deep-thinking yetenek helper'ı dosya sistemi yan etkisi içermemelidir."
  )
})

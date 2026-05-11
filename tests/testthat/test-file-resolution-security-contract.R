# ==============================================================================
# Dosya Yolu: tests/testthat/test-file-resolution-security-contract.R
# Açıklama: Dosya çözümleme güvenlik sınırlarının yanlışlıkla gevşetilmesini
#           engelleyen statik kontrat testleri.
# ==============================================================================

.read_security_contract_text <- function(path) {
  repo_root <- resolve_repo_root_for_tests()
  full_path <- file.path(repo_root, path)

  if (!file.exists(full_path)) {
    return("")
  }

  txt <- paste(
    readLines(full_path, warn = FALSE, encoding = "UTF-8"),
    collapse = "\n"
  )

  enc2utf8(txt)
}

test_that("resolve_uploaded_file güvenli varsayılanlarla tanımlıdır", {
  txt <- .read_security_contract_text("R/config_file_store_registry.R")

  expect_true(
    grepl("allow_direct_path = FALSE", txt, fixed = TRUE),
    info = "resolve_uploaded_file() doğrudan path çözümlemeyi varsayılan olarak kapalı tutmalıdır."
  )

  expect_true(
    grepl("allow_cross_bucket = FALSE", txt, fixed = TRUE),
    info = "resolve_uploaded_file() çapraz kullanıcı/kova çözümlemeyi varsayılan olarak kapalı tutmalıdır."
  )

  expect_true(
    grepl("trusted_roots = character(0)", txt, fixed = TRUE),
    info = "Doğrudan path çözümleme sadece açık trusted_roots ile mümkün olmalıdır."
  )

  expect_true(
    grepl("if (isTRUE(allow_direct_path)", txt, fixed = TRUE),
    info = "Doğrudan path çözümleme explicit allow_direct_path kontrolü arkasında olmalıdır."
  )

  expect_true(
    grepl("if (isTRUE(allow_cross_bucket))", txt, fixed = TRUE),
    info = "Çapraz bucket fallback explicit allow_cross_bucket kontrolü arkasında olmalıdır."
  )
})

test_that("runtime çağrı noktaları user_id=NULL ile resolve_uploaded_file kullanmaz", {
  runtime_files <- c(
    "R/helpers_preview.R",
    "R/module_summarization.R",
    "R/module_file_preview.R",
    "R/helpers_send_message_core.R",
    "R/module_file_manager.R",
    "R/helpers_mcp_file_resolver.R"
  )

  offenders <- character(0)

  for (path in runtime_files) {
    txt <- .read_security_contract_text(path)

    has_bad_null_call <- grepl(
      "resolve_uploaded_file\\s*\\([^\\)]*user_id\\s*=\\s*NULL",
      txt,
      perl = TRUE
    )

    if (isTRUE(has_bad_null_call)) {
      offenders <- c(offenders, path)
    }
  }

  expect_length(
    offenders,
    0,
    info = paste(
      "Runtime dosyalarında resolve_uploaded_file(..., user_id = NULL) kullanılmamalıdır:",
      paste(offenders, collapse = ", ")
    )
  )
})

test_that("runtime çağrı noktaları güvenlik bayraklarını açmaz", {
  runtime_files <- c(
    "R/helpers_preview.R",
    "R/module_summarization.R",
    "R/module_file_preview.R",
    "R/helpers_send_message_core.R",
    "R/module_file_manager.R"
  )

  offenders <- character(0)

  for (path in runtime_files) {
    txt <- .read_security_contract_text(path)

    has_allow_direct <- grepl("allow_direct_path\\s*=\\s*TRUE", txt, perl = TRUE)
    has_allow_cross <- grepl("allow_cross_bucket\\s*=\\s*TRUE", txt, perl = TRUE)

    if (isTRUE(has_allow_direct) || isTRUE(has_allow_cross)) {
      offenders <- c(offenders, path)
    }
  }

  expect_length(
    offenders,
    0,
    info = paste(
      "Normal runtime akışları allow_direct_path=TRUE veya allow_cross_bucket=TRUE kullanmamalıdır:",
      paste(offenders, collapse = ", ")
    )
  )
})

test_that("MCP resolver mutlak path argümanını doğrudan kabul etmez", {
  txt <- .read_security_contract_text("R/helpers_mcp_file_resolver.R")

  expect_true(
    grepl("Absolute path argument ignored", txt, fixed = TRUE),
    info = "MCP resolver mutlak path argümanlarını doğrudan dosya okuma yetkisine çevirmemelidir."
  )

  expect_false(
    grepl("Absolute path exists ->", txt, fixed = TRUE),
    info = "Eski mutlak path kabul davranışı geri gelmemelidir."
  )
})
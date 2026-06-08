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

  size <- suppressWarnings(file.info(full_path)$size[1])
  if (is.na(size) || size <= 0) {
    return("")
  }

  con <- file(full_path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_data <- readBin(con, what = "raw", n = size)

  txt <- suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
  )

  if (is.na(txt)) {
    txt <- ""
  }

  txt <- gsub("\\r\\n?|\\r", "\n", txt, perl = TRUE)
  enc2utf8(txt)
}

test_that("resolve_uploaded_file güvenli varsayılanlarla tanımlıdır", {
  txt <- .read_security_contract_text("R/config_file_store_registry.R")

  expect_true(
    grepl("allow_direct_path\\s*=\\s*FALSE", txt, perl = TRUE),
    info = "resolve_uploaded_file() doğrudan path çözümlemeyi varsayılan olarak kapalı tutmalıdır."
  )

  expect_true(
    grepl("allow_cross_bucket\\s*=\\s*FALSE", txt, perl = TRUE),
    info = "resolve_uploaded_file() çapraz kullanıcı/kova çözümlemeyi varsayılan olarak kapalı tutmalıdır."
  )

  expect_true(
    grepl("trusted_roots\\s*=\\s*character\\(0\\)", txt, perl = TRUE),
    info = "Doğrudan path çözümleme sadece açık trusted_roots ile mümkün olmalıdır."
  )

  expect_true(
    grepl("if\\s*\\(\\s*isTRUE\\s*\\(\\s*allow_direct_path\\s*\\)", txt, perl = TRUE),
    info = "Doğrudan path çözümleme explicit allow_direct_path kontrolü arkasında olmalıdır."
  )

  expect_true(
    grepl("if\\s*\\(\\s*isTRUE\\s*\\(\\s*allow_cross_bucket\\s*\\)\\s*\\)", txt, perl = TRUE),
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

	expect_equal(
	  length(offenders),
	  0L,
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

	expect_equal(
	  length(offenders),
	  0L,
	  info = paste(
		"Normal runtime akışları allow_direct_path=TRUE veya allow_cross_bucket=TRUE kullanmamalıdır:",
		paste(offenders, collapse = ", ")
	  )
	)
})

test_that("MCP resolver mutlak path argümanını doğrudan kabul etmez", {
  txt <- .read_security_contract_text("R/helpers_mcp_file_resolver.R")

  # NOT: Üretim kodundaki güvenlik davranışı "ignored" yerine daha güçlü olan
  # "rejected" (ok = FALSE + Türkçe kullanıcı hatası) ile uygulanıyor. Bu
  # sözleşme artık kararlı davranış çıpalarına dayanır: hem mutlak-yol
  # reddetme kontrolü (is_abs) hem de kullanıcıya dönen Türkçe ret mesajı.
  expect_true(
    grepl("is_abs", txt, fixed = TRUE),
    info = "MCP resolver mutlak yol argümanını tespit eden is_abs kontrolünü korumalıdır."
  )

  expect_true(
    grepl("Mutlak dosya yolu kabul edilmez", txt, fixed = TRUE),
    info = "MCP resolver mutlak path argümanlarını doğrudan dosya okuma yetkisine çevirmemeli; reddetmelidir."
  )

  expect_false(
    grepl("Absolute path exists ->", txt, fixed = TRUE),
    info = "Eski mutlak path kabul davranışı geri gelmemelidir."
  )
})
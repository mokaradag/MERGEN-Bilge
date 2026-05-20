# ==============================================================================
# Dosya Yolu: tests/testthat/test-fragile-flow-manual-preflight-contract.R
# Açıklama: run_fragile_flow_manual_preflight.R betiğinin kritik yerel/VM akış
#           maddelerini koruduğunu doğrular.
# ==============================================================================

.find_manual_preflight_repo_root <- function() {
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

  stop("Manual preflight contract repo kökünü bulamadı.", call. = FALSE)
}

.manual_preflight_read_text <- function(...) {
  path <- file.path(.find_manual_preflight_repo_root(), ...)
  if (!file.exists(path)) {
    stop(sprintf("Beklenen dosya bulunamadı: %s", path), call. = FALSE)
  }

  size <- file.info(path)$size[1]
  if (is.na(size) || size <= 0) return("")

  con <- file(path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_data <- readBin(con, what = "raw", n = size)
  txt <- rawToChar(raw_data)
  Encoding(txt) <- "UTF-8"
  enc2utf8(gsub("\\r\\n?|\\r", "\n", txt, perl = TRUE))
}

test_that("fragile-flow manual preflight keeps required local and VM checks", {
  script <- .manual_preflight_read_text(
    "tests",
    "scripts",
    "run_fragile_flow_manual_preflight.R"
  )

  required_tokens <- c(
    "SSO_ENABLED=FALSE",
    "SSO_ENABLED=TRUE",
    "Press stop during streaming",
    "send button returns to normal",
    "typing/thinking wrapper disappears or resolves cleanly",
    "no duplicate assistant message appears",
    "Upload PDF, DOCX, TXT, CSV, XLSX",
    "Refresh browser and verify files remain visible once",
    "Fully restart app and verify files remain visible once",
    "TTS does not auto-play old AI messages",
    "authenticated user identity is correct",
    "recent chats show user-specific rows",
    "Söyleşi Geçmişi, Kayıtlı Söyleşiler",
    "Görsel Galerisi",
    "Türkçe_çalışma_özeti_İstanbul.pdf",
    "only one music track plays",
    "ducking recovers after TTS/STT",
    "run_vm_preflight_real.R",
    "MERGEN_PREFLIGHT_CHECK_FILE_STORE=TRUE",
    "UX_SMOKE_DONE:PASS",
    "collect_manual_preflight_context",
    "MERGEN_APP_URL",
    "git_ref",
    "sso_enabled_env",
    "mcp_files_base",
    "evidence",
    "fileEncoding = \"UTF-8\""
  )

  missing <- required_tokens[!vapply(
    required_tokens,
    function(token) grepl(token, script, fixed = TRUE, useBytes = TRUE),
    logical(1)
  )]

  expect_equal(
    missing,
    character(0),
    info = paste(
      "Manual fragile-flow preflight kapsamı eksik:",
      paste(missing, collapse = ", ")
    )
  )
})
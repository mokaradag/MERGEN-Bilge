# Canlı uygulamadan bağımsız Node -> Edge ve yerel fixture tanısı.
local({
  root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
  helper <- file.path(root, "tests/scripts/helpers_browser_ux_profile.R")
  if (!file.exists(helper)) stop("Run this diagnostic from the repository root.", call. = FALSE)
  source(helper, local = TRUE, encoding = "UTF-8")
  source(file.path(root, "R/utils_text_encoding.R"), local = TRUE, encoding = "UTF-8")
  node <- unname(Sys.which("node"))
  if (!nzchar(node)) stop("Node is unavailable.", call. = FALSE)
  candidates <- c(
    Sys.getenv("MERGEN_BROWSER_BIN", ""),
    file.path(Sys.getenv("PROGRAMFILES(X86)"), "Microsoft/Edge/Application/msedge.exe"),
    file.path(Sys.getenv("PROGRAMFILES"), "Microsoft/Edge/Application/msedge.exe"),
    unname(Sys.which(c("msedge", "google-chrome", "chromium")))
  )
  candidates <- candidates[nzchar(candidates) & file.exists(candidates)]
  if (!length(candidates)) stop("No browser binary was found.", call. = FALSE)
  browser <- normalizePath(candidates[[1]], winslash = "/", mustWork = TRUE)
  if (grepl("^msedge([.]exe)?$", basename(browser), ignore.case = TRUE)) ux_smoke_check_edge_policy()
  cat("Node browser diagnostic: three phases, at most 20 seconds per phase.\n")
  cat("The live app, port 8009, SSO and the prepared smoke profile are not used.\n")
  args <- c(shQuote(file.path(root, "tests/scripts/ux_smoke_startup_timing_regressions.js")),
            "--browser", shQuote(browser), "--diagnose")
  # Asıl contract testiyle aynı system2 sınırı korunur; UTF-8 baytları çevrilmez.
  result <- mark_text_utf8(system2(node, args, stdout = TRUE, stderr = TRUE))
  cat(paste(result, collapse = "\n"), "\n")
  status <- attr(result, "status")
  cat("Node diagnostic exit status:", if (is.null(status)) 0L else status, "\n")
})

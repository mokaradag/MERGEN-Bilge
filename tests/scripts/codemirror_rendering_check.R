#!/usr/bin/env Rscript

# ==============================================================================
# Dosya Yolu: tests/scripts/codemirror_rendering_check.R
# Açıklama:
#   Kod bloklarının GERÇEK CodeMirror ile çizildiğini headless tarayıcıda
#   doğrular: dil belirteçleri (cm-keyword, cm-def, ...), koyu/açık tema
#   renkleri ve zeminleri, oluk tıklamasıyla katlama, uzun kodun tamamı ve
#   kopyalamanın tam orijinal metni vermesi.
#
#   Sayfa çalışma anında R/config_ui_assets.R manifestinden üretilir (tüm CSS
#   + CodeMirror çekirdek/mod/eklenti + codemirror-manager.js), örnek kod
#   blokları R'nin create_code_block_html() çıktısıdır. www/ klasörü httpuv
#   statik yolu ile sunulur; Shiny oturumu, veritabanı veya internet gerekmez.
#
#   Kullanım:
#     Rscript tests/scripts/codemirror_rendering_check.R [--require-browser]
#   Tarayıcı yoksa SKIP (çıkış 0); MERGEN_BROWSER_BIN verilmişse veya
#   --require-browser kullanılmışsa tarayıcı zorunludur.
#   Not: CDN, npm, Playwright veya chromote kullanmaz; yerel tarayıcıyı
#   processx ile çağırır (tests/scripts/ai_browser_ux_smoke.R ile aynı desen).
# ==============================================================================

# Yerel ayardan bağımsız yükleme: dosya UTF-8 metin olarak ayrıştırılır
# (POSIX/Windows kod sayfasında source(encoding=) Türkçe yorumda düşebilir).
cm_render_check_source <- function(path, envir) {
  exprs <- parse(text = readLines(path, warn = FALSE, encoding = "UTF-8"),
                 keep.source = FALSE, encoding = "UTF-8")
  for (expr in exprs) eval(expr, envir)
  invisible(envir)
}

cm_render_check_find_browser <- function() {
  env_bin <- Sys.getenv("MERGEN_BROWSER_BIN", unset = "")
  if (nzchar(env_bin)) {
    resolved <- if (file.exists(env_bin)) env_bin else unname(Sys.which(env_bin))
    return(if (nzchar(resolved) && file.exists(resolved)) resolved else "")
  }

  found <- Sys.which(c(
    "google-chrome", "google-chrome-stable", "chromium", "chromium-browser",
    "microsoft-edge", "microsoft-edge-stable", "msedge", "chrome"
  ))
  found <- unname(found[nzchar(found)])
  if (length(found) > 0L) return(found[[1]])

  candidates <- character(0)
  pw_root <- Sys.getenv("PLAYWRIGHT_BROWSERS_PATH", unset = "")
  if (nzchar(pw_root)) candidates <- c(candidates, file.path(pw_root, "chromium"))
  if (.Platform$OS.type == "windows") {
    for (root in c(Sys.getenv("PROGRAMFILES"), Sys.getenv("PROGRAMFILES(X86)"), Sys.getenv("LOCALAPPDATA"))) {
      if (!nzchar(root)) next
      candidates <- c(candidates,
                      file.path(root, "Google", "Chrome", "Application", "chrome.exe"),
                      file.path(root, "Microsoft", "Edge", "Application", "msedge.exe"))
    }
  }
  hit <- candidates[file.exists(candidates)]
  if (length(hit) > 0L) normalizePath(hit[[1]], winslash = "/", mustWork = TRUE) else ""
}

cm_render_check_fixtures <- function(repo_root) {
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  # Uygulama HTML()'i shiny/htmltools'tan alır.
  env$HTML <- htmltools::HTML
  cm_render_check_source(file.path(repo_root, "R", "helpers_language.R"), env)
  cm_render_check_source(file.path(repo_root, "R", "helpers_messaging.R"), env)

  samples <- list(
    python = list(lang = "python", code = paste(
      "def fibonacci(n):",
      "    \"\"\"\u0130lk n adet Fibonacci say\u0131s\u0131n\u0131 \u00FCretir.\"\"\"",
      "    a, b = 0, 1",
      "    for _ in range(n):",
      "        yield a",
      "        a, b = b, a + b",
      "",
      "if __name__ == \"__main__\":",
      "    for num in fibonacci(10):",
      "        print(num)  # \u00E7\u0131kt\u0131", sep = "\n")),
    r = list(lang = "r", code = paste(
      "library(dplyr)",
      "# \u00D6zet istatistik",
      "ozet <- function(df, esik = 30) {",
      "  df %>% filter(gecikme > esik) %>%",
      "    summarise(n = n(), ort = mean(deger, na.rm = TRUE))",
      "}",
      "if (is.na(x[3])) print(\"eksik de\u011Fer\")", sep = "\n")),
    javascript = list(lang = "js", code = paste(
      "// Saya\u00E7 \u00FCreteci",
      "const sayac = (baslangic = 0) => {",
      "  let deger = baslangic;",
      "  return { artir() { return ++deger; } };",
      "};",
      "function selam(ad) { return typeof ad === \"string\" && ad.length > 3; }", sep = "\n")),
    sql = list(lang = "sql", code = paste(
      "-- Aktif projeler",
      "SELECT p.ProjeAdi, COUNT(*) AS AktiviteSayisi",
      "FROM dbo.Projeler p JOIN dbo.Aktiviteler a ON a.ProjeId = p.Id",
      "WHERE p.Durum = 'Aktif' AND a.Gecikme > 30",
      "GROUP BY p.ProjeAdi;", sep = "\n"))
  )
  uzun <- unlist(lapply(seq_len(600L), function(i) c(
    sprintf("def islem_%04d(deger):", i),
    sprintf("    sonuc = deger * %d + 1  # adim %d", i, i),
    "    return sonuc", "", "")))
  samples$long <- list(lang = "python", code = paste(c(uzun, "print('SON_SATIR')"), collapse = "\n"))

  lapply(samples, function(s) {
    list(code = s$code, html = as.character(env$create_code_block_html(s$code, s$lang)))
  })
}

cm_render_check_page <- function(repo_root, fixtures) {
  assets <- new.env(parent = globalenv())
  for (f in c("R/config_ui_assets.R", "R/config_ui_asset_validators.R")) {
    cm_render_check_source(file.path(repo_root, f), assets)
  }
  css <- assets$ui_asset_all_css()
  js <- c(assets$ui_asset_js_groups$codemirror_core,
          assets$ui_asset_js_groups$codemirror_modes,
          assets$ui_asset_js_groups$codemirror_addons,
          "js/codemirror-manager.js")

  fixtures_json <- jsonlite::toJSON(fixtures, auto_unbox = TRUE)
  fixtures_json <- gsub("</", "<\\/", fixtures_json, fixed = TRUE)
  probe <- paste(readLines(file.path(repo_root, "tests", "scripts", "codemirror_rendering_probe.js"),
                           warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  paste0(
    "<!doctype html>\n<html lang=\"tr\" data-theme=\"dark\"><head><meta charset=\"UTF-8\">",
    "<title>CodeMirror \u00e7izim denetimi</title>\n",
    paste0("<link rel=\"stylesheet\" href=\"/", css, "\">", collapse = "\n"),
    "\n</head><body>\n",
    "<div id=\"cm-check-status\">CODEMIRROR_RENDER_CHECK:RUNNING</div>\n",
    "<pre id=\"cm-check-log\"></pre>\n",
    "<div id=\"cm-check-host\" class=\"chat-container\" style=\"width:900px\"></div>\n",
    paste0("<script src=\"/", js, "\"></script>", collapse = "\n"),
    "\n<script>window.__CM_FIXTURES = ", fixtures_json, ";</script>\n",
    "<script>\n", probe, "\n</script>\n</body></html>\n"
  )
}

cm_render_check_run <- function(repo_root, browser_bin, timeout_seconds = 120L,
                                virtual_time_ms = 20000L) {
  www_dir <- normalizePath(file.path(repo_root, "www"), winslash = "/", mustWork = TRUE)
  page_dir <- tempfile("mergen-cm-check-")
  profile_dir <- tempfile("mergen-cm-profile-")
  dir.create(page_dir)
  dir.create(profile_dir)
  on.exit(unlink(c(page_dir, profile_dir), recursive = TRUE, force = TRUE), add = TRUE)

  page <- enc2utf8(cm_render_check_page(repo_root, cm_render_check_fixtures(repo_root)))
  con <- file(file.path(page_dir, "index.html"), open = "wb")
  writeBin(charToRaw(page), con)
  close(con)

  # Statik yollar httpuv arka plan iş parçacığında sunulur; tarayıcı
  # çalışırken R'nin servis döngüsüne gerek yoktur.
  port <- httpuv::randomPort()
  server <- httpuv::startServer("127.0.0.1", port, list(
    call = function(req) list(status = 404L, headers = list("Content-Type" = "text/plain"), body = ""),
    staticPaths = list(
      "/__cm_check" = httpuv::staticPath(page_dir, indexhtml = TRUE),
      "/" = httpuv::staticPath(www_dir, indexhtml = FALSE)
    )
  ))
  on.exit(httpuv::stopServer(server), add = TRUE)

  run_browser <- function(headless_flag) {
    args <- c(headless_flag, "--disable-gpu", "--disable-dev-shm-usage", "--no-first-run",
              "--no-default-browser-check", "--window-size=1280,2400",
              paste0("--user-data-dir=", profile_dir),
              paste0("--virtual-time-budget=", as.integer(virtual_time_ms)))
    if (.Platform$OS.type == "unix" && identical(unname(Sys.info()[["effective_user"]]), "root")) {
      args <- c(args, "--no-sandbox")
    }
    args <- c(args, "--dump-dom", sprintf("http://127.0.0.1:%d/__cm_check/index.html", port))
    tryCatch(
      processx::run(browser_bin, args, error_on_status = FALSE, timeout = timeout_seconds),
      error = function(e) list(status = 124L, stdout = "", stderr = conditionMessage(e))
    )
  }

  res <- run_browser("--headless=new")
  if (!identical(as.integer(res$status), 0L) &&
      grepl("headless=new|unknown|unrecognized", res$stderr %||% "", ignore.case = TRUE)) {
    res <- run_browser("--headless")
  }

  out <- res$stdout %||% ""
  status_txt <- regmatches(out, regexpr("<div id=\"cm-check-status\">[^<]*</div>", out))
  log_txt <- regmatches(out, regexpr("<pre id=\"cm-check-log\">[^<]*</pre>", out))
  list(
    page_rendered = length(status_txt) == 1L,
    passed = length(status_txt) == 1L && grepl("CODEMIRROR_RENDER_CHECK:PASS", status_txt, fixed = TRUE),
    status = if (length(status_txt)) status_txt else "",
    log = if (length(log_txt)) log_txt else "",
    browser_status = as.integer(res$status),
    stderr = res$stderr %||% ""
  )
}

`%||%` <- function(a, b) if (is.null(a)) b else a

# --dump-dom metni HTML varlıklarıyla serileştirir; rapor düz metne çevrilir.
cm_render_check_plain <- function(html) {
  txt <- gsub("<[^>]+>", "", html)
  txt <- gsub("&lt;", "<", txt, fixed = TRUE)
  txt <- gsub("&gt;", ">", txt, fixed = TRUE)
  txt <- gsub("&quot;", "\"", txt, fixed = TRUE)
  gsub("&amp;", "&", txt, fixed = TRUE)
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  repo_root <- normalizePath(".", winslash = "/", mustWork = TRUE)
  if (!file.exists(file.path(repo_root, "R", "config_ui_assets.R"))) {
    stop("Repo kökünden çalıştırın.", call. = FALSE)
  }
  require_browser <- "--require-browser" %in% args || nzchar(Sys.getenv("MERGEN_BROWSER_BIN", unset = ""))
  browser_bin <- cm_render_check_find_browser()
  if (!nzchar(browser_bin)) {
    cat("SKIP: Chrome/Chromium/Edge bulunamadı (MERGEN_BROWSER_BIN ile verilebilir).\n")
    quit(status = if (require_browser) 1L else 0L)
  }
  cat(sprintf("Tarayıcı: %s\n", browser_bin))
  res <- cm_render_check_run(repo_root, browser_bin)
  cat(cm_render_check_plain(res$log), "\n", sep = "")
  cat(cm_render_check_plain(res$status), "\n", sep = "")
  if (!isTRUE(res$passed)) {
    cat(sprintf("Tarayıcı çıkış kodu: %d\n", res$browser_status))
    cat(substr(res$stderr, 1L, 4000L), "\n")
    quit(status = 1L)
  }
  quit(status = 0L)
}

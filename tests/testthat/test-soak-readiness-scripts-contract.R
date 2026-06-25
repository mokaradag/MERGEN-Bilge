# ==============================================================================
# Dosya Yolu: tests/testthat/test-soak-readiness-scripts-contract.R
# Aciklama:
#   Soak readiness hardening kapsamindaki YENI bagimsiz betikler icin HIZLI,
#   OFFLINE, DETERMINISTIK sozlesme testi:
#     - tests/scripts/run_vm_sqlserver_pool_preflight_real.R
#     - tests/scripts/run_browser_concurrency_lane.R
#     - tests/scripts/soak_system_telemetry.R
#
#   Kapsanan sozlesmeler:
#     - ASCII-guvenlik (parser-stability) + parse edilebilirlik.
#     - SQL Server havuz preflight: guard'lar olmadan/eksikken GUVENLE atlar
#       (exit 0 + SKIP) ve gercek SQL Server/DB GEREKTIRMEZ.
#     - Browser eszamanlilik lane: etkin degilken/uygulama erisilemezken GUVENLE
#       atlar (exit 0 + SKIP) ve tarayici/uygulama GEREKTIRMEZ.
#     - quit() yok (source-safe), guard env adlari mevcut.
# ==============================================================================

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L || is.na(x[1])) y else x

local({
  for (loc in c("C.UTF-8", "en_US.UTF-8", "tr_TR.UTF-8")) {
    if (tryCatch(nzchar(Sys.setlocale("LC_CTYPE", loc)),
                 error = function(e) FALSE, warning = function(w) FALSE)) break
  }
})

srs_repo_root <- local({
  hit <- NULL
  for (cand in c(".", "..", "../..", "../../..")) {
    if (file.exists(file.path(cand, "tests", "scripts", "run_vm_sqlserver_pool_preflight_real.R"))) {
      hit <- normalizePath(cand, winslash = "/", mustWork = TRUE); break
    }
  }
  hit
})

srs_script <- function(rel) file.path(srs_repo_root, "tests", "scripts", rel)

srs_read_bytes <- function(path) {
  if (!file.exists(path)) return(raw(0))
  readBin(path, what = "raw", n = file.info(path)$size)
}

srs_new_scripts <- function() {
  c("run_vm_sqlserver_pool_preflight_real.R", "run_browser_concurrency_lane.R",
    "soak_system_telemetry.R")
}

srs_rscript_bin <- function() {
  rs <- file.path(R.home("bin"), "Rscript")
  if (.Platform$OS.type == "windows") rs <- paste0(rs, ".exe")
  if (!file.exists(rs)) rs <- unname(Sys.which("Rscript"))
  rs
}

# Bir betigi temiz bir Rscript cocuk surecinde calistirir (repo kokunde).
srs_run_script <- function(rel, env = character(0), timeout = 120) {
  rscript <- srs_rscript_bin()
  if (!nzchar(rscript) || !file.exists(rscript)) {
    return(list(status = NA_integer_, stdout = "", stderr = "rscript-not-found"))
  }
  res <- tryCatch(
    processx::run(
      command = rscript,
      args = srs_script(rel),
      wd = srs_repo_root,
      env = c("current", env, LC_ALL = "C.UTF-8"),
      error_on_status = FALSE,
      timeout = timeout
    ),
    error = function(e) list(status = 124L, stdout = "", stderr = conditionMessage(e))
  )
  list(status = as.integer(res$status %||% NA_integer_),
       stdout = res$stdout %||% "", stderr = res$stderr %||% "")
}

# ------------------------------------------------------------------------------
testthat::test_that("yeni readiness betikleri ASCII-guvenli + parse edilebilir", {
  testthat::skip_if(is.null(srs_repo_root), "Repo koku bulunamadi.")
  for (f in srs_new_scripts()) {
    bytes <- srs_read_bytes(srs_script(f))
    testthat::expect_length(which(as.integer(bytes) > 127L), 0L)
    testthat::expect_false(any(bytes == as.raw(0L)), info = f)
    testthat::expect_silent(parse(srs_script(f)))
  }
})

# ------------------------------------------------------------------------------
testthat::test_that("betikler quit() kullanmaz (source-safe) ve guard env adlarini icerir", {
  testthat::skip_if(is.null(srs_repo_root), "Repo koku bulunamadi.")

  # Yorum satirlarini cikar (CLAUDE.md repo-tarama kurali): aciklamalarda gecen
  # "quit()" kelimesi yanlis pozitif uretmesin (her iki betik de yorumda
  # "quit() KULLANILMAZ" der). Satir basindan ilk # sonrasini at.
  strip_comments <- function(path) {
    ll <- readLines(path, warn = FALSE, encoding = "UTF-8")
    code <- sub("#.*$", "", ll)
    paste(code, collapse = "\n")
  }
  sql_code <- strip_comments(srs_script("run_vm_sqlserver_pool_preflight_real.R"))
  bc_code <- strip_comments(srs_script("run_browser_concurrency_lane.R"))
  sql_txt <- paste(readLines(srs_script("run_vm_sqlserver_pool_preflight_real.R"),
                             warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  bc_txt <- paste(readLines(srs_script("run_browser_concurrency_lane.R"),
                            warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  # quit() KOD'da yok (source-safe sozlesme); yorumdaki aciklama haric.
  testthat::expect_false(grepl("quit\\s*\\(", sql_code))
  testthat::expect_false(grepl("quit\\s*\\(", bc_code))

  # Guard env adlari mevcut.
  testthat::expect_true(grepl("MERGEN_SQLSERVER_POOL_PREFLIGHT_REAL", sql_txt, fixed = TRUE))
  testthat::expect_true(grepl("MERGEN_DB_POOL_ENABLED", sql_txt, fixed = TRUE))
  testthat::expect_true(grepl("MERGEN_SQLSERVER_POOL_WRITE_TEST", sql_txt, fixed = TRUE))
  testthat::expect_true(grepl("MERGEN_BROWSER_CONCURRENCY_ENABLED", bc_txt, fixed = TRUE))
  testthat::expect_true(grepl("MERGEN_BROWSER_CONCURRENCY_MAX_USERS", bc_txt, fixed = TRUE))
})

# ------------------------------------------------------------------------------
testthat::test_that("SQL Server havuz preflight: guard yokken GUVENLE atlar (exit 0 + SKIP)", {
  testthat::skip_if(is.null(srs_repo_root), "Repo koku bulunamadi.")
  testthat::skip_if_not_installed("processx")

  # Guard kapali: gercek SQL Server/DB GEREKMEZ; exit 0 + SKIP.
  r <- srs_run_script("run_vm_sqlserver_pool_preflight_real.R",
                      env = c(MERGEN_SQLSERVER_POOL_PREFLIGHT_REAL = "FALSE"))
  testthat::skip_if(is.na(r$status), "Rscript cocuk sureci calistirilamadi.")
  testthat::expect_equal(r$status, 0L)
  testthat::expect_true(grepl("SKIP", r$stdout))

  # Guard acik ama DB_DSN yok: yine GUVENLE atlar (exit 0 + SKIP).
  r2 <- srs_run_script("run_vm_sqlserver_pool_preflight_real.R",
                       env = c(MERGEN_SQLSERVER_POOL_PREFLIGHT_REAL = "TRUE",
                               MERGEN_DB_POOL_ENABLED = "TRUE",
                               DB_DSN = ""))
  testthat::expect_equal(r2$status, 0L)
  testthat::expect_true(grepl("SKIP", r2$stdout))
})

# ------------------------------------------------------------------------------
testthat::test_that("Browser eszamanlilik lane: etkin degilken/uygulamasiz GUVENLE atlar", {
  testthat::skip_if(is.null(srs_repo_root), "Repo koku bulunamadi.")
  testthat::skip_if_not_installed("processx")

  # Etkin degil (varsayilan): exit 0 + SKIP, tarayici GEREKMEZ.
  r <- srs_run_script("run_browser_concurrency_lane.R",
                      env = c(MERGEN_BROWSER_CONCURRENCY_ENABLED = "false"))
  testthat::skip_if(is.na(r$status), "Rscript cocuk sureci calistirilamadi.")
  testthat::expect_equal(r$status, 0L)
  testthat::expect_true(grepl("SKIP", r$stdout))

  # Etkin ama erisilemez uygulama + sahte tarayici binary: exit 0 + SKIP.
  r2 <- srs_run_script("run_browser_concurrency_lane.R",
                       env = c(MERGEN_BROWSER_CONCURRENCY_ENABLED = "true",
                               MERGEN_BROWSER_BIN = "/bin/true",
                               MERGEN_BROWSER_CONCURRENCY_BASE_URL = "http://127.0.0.1:59997/"))
  testthat::expect_equal(r2$status, 0L)
  testthat::expect_true(grepl("SKIP", r2$stdout))
})

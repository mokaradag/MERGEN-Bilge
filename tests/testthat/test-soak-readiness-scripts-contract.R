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
  # Full-suite runs can execute after other tests temporarily change the working
  # directory, while focused `test_file()` runs usually start from the repo root
  # or tests/testthat. Prefer the bootstrap's already-resolved repo root when it
  # is available, then fall back to an upward search from the current wd.
  if (exists("repo_root_for_tests", mode = "character", inherits = TRUE) &&
      file.exists(file.path(repo_root_for_tests, "tests", "scripts",
                            "run_vm_sqlserver_pool_preflight_real.R"))) {
    return(normalizePath(repo_root_for_tests, winslash = "/", mustWork = TRUE))
  }

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
  # processx icin isimli env girdileri en tasinabilir override bicimidir. Bazi
  # VM cagrilari sozlesme env degerlerini "NAME=value" metinleri olarak
  # gecirirken, ebeveyn kabukta MERGEN_* guard'lari zaten acik olabilir; bu
  # metinleri normalize et ki cocuk surec test override'ini deterministik gorsun.
  normalize_env <- function(x) {
    if (length(x) == 0L) return(character(0))
    out_names <- names(x)
    out <- as.character(x)
    if (is.null(out_names)) out_names <- rep("", length(out))
    unnamed <- !nzchar(out_names)
    for (i in which(unnamed)) {
      m <- regexpr("=", out[[i]], fixed = TRUE)
      if (m[[1]] > 1L) {
        out_names[[i]] <- substr(out[[i]], 1L, m[[1]] - 1L)
        out[[i]] <- substr(out[[i]], m[[1]] + 1L, nchar(out[[i]]))
      }
    }
    names(out) <- out_names
    out
  }
  # Cocuk surece LC_ALL=C.UTF-8 ZORLAMA: Windows R "C.UTF-8" locale'ini DESTEKLEMEZ.
  # Uretim VM'inde (Turkce/Windows locale) bu deger cocuk R baslangicini bozup
  # betigin SKIP yoluna ulasmadan sifir-disi cikis vermesine yol acabilir (calisan
  # uygulama LC_ALL zorlamaz; Turkish_Turkey.UTF-8 kullanir). Bu yuzden Windows'ta
  # ebeveynin (zaten calisan) locale'ini MIRAS al; yalniz Unix'te determinizm icin zorla.
  child_env <- c("current", normalize_env(env))
  if (.Platform$OS.type != "windows") {
    child_env <- c(child_env, LC_ALL = "C.UTF-8")
  }
  # Windows VM/RStudio/processx kombinasyonlari, isimli cocuk env override'lari
  # verilse bile maintainer seviyesindeki MERGEN_* degiskenlerini miras alabilir.
  # Asagidaki sozlesme beklentileri uretim VM'inde deterministik kalmali; bu
  # nedenle istenen override'lari test edilen betigi source etmeden once cocuk R
  # oturumunun icinde de uygula. Bu, cocuk sureci source-safe tutar (hedef
  # betikler quit() cagirmaz) ve yanlislikla gercek tarayici/DB lane'lerini
  # calistirmayi onler.
  wrapper <- tempfile("srs-run-", fileext = ".R")
  env_norm <- normalize_env(env)
  on.exit(try(unlink(wrapper, force = TRUE), silent = TRUE), add = TRUE)
  writeLines(c(
    "env_values <- list(",
    if (length(env_norm) > 0L) {
      paste(sprintf("  %s = %s", encodeString(names(env_norm), quote = "`"),
                    encodeString(unname(env_norm), quote = "\"")), collapse = ",\n")
    } else "",
    ")",
    "if (length(env_values) > 0L) do.call(Sys.setenv, env_values)",
    sprintf("source(%s, encoding = 'UTF-8')", encodeString(srs_script(rel), quote = "\""))
  ), wrapper, useBytes = TRUE)
  res <- tryCatch(
    processx::run(
      command = rscript,
      args = wrapper,
      wd = srs_repo_root,
      env = child_env,
      error_on_status = FALSE,
      timeout = timeout
    ),
    error = function(e) list(status = 124L, stdout = "", stderr = conditionMessage(e))
  )
  list(status = as.integer(res$status %||% NA_integer_),
       stdout = res$stdout %||% "", stderr = res$stderr %||% "")
}

# Bir cocuk-surec sonucunu testthat info'suna gomulebilir tek satira indirger.
# Boylece exit 0 / SKIP beklentisi VM'de basarisiz olursa, gercek cocuk hatasi
# (stderr) test ciktisinda gorunur ve teshis tahmine kalmaz.
srs_diag <- function(r) {
  one_line <- function(x, n) substr(gsub("[[:space:]]+", " ", as.character(x %||% "")), 1L, n)
  sprintf("status=%s | stdout=%s | stderr=%s",
          as.character(r$status %||% NA),
          one_line(r$stdout, 300L),
          one_line(r$stderr, 600L))
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
  testthat::expect_true(grepl("MERGEN_SQLSERVER_POOL_PREFLIGHT_SKIP_RENVIRON", sql_txt, fixed = TRUE))
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
  testthat::expect_equal(r$status, 0L, info = srs_diag(r))
  testthat::expect_true(grepl("SKIP", r$stdout), info = srs_diag(r))

  # Guard acik ama DB_DSN yok: yine GUVENLE atlar (exit 0 + SKIP).
  # NOT: Uretim Windows VM'inde repo .Renviron GERCEK DB_DSN icerir; betik onu
  # YENIDEN yuklerse buradaki bos DB_DSN override'i ezilir ve guard yerine gercek
  # preflight kosup FAIL olur. MERGEN_SQLSERVER_POOL_PREFLIGHT_SKIP_RENVIRON ile bu
  # yeniden-yukleme kapatilir; boylece DB_DSN guard yolu deterministik kalir.
  r2 <- srs_run_script("run_vm_sqlserver_pool_preflight_real.R",
                       env = c(MERGEN_SQLSERVER_POOL_PREFLIGHT_REAL = "TRUE",
                               MERGEN_DB_POOL_ENABLED = "TRUE",
                               MERGEN_SQLSERVER_POOL_PREFLIGHT_SKIP_RENVIRON = "TRUE",
                               DB_DSN = ""))
  testthat::expect_equal(r2$status, 0L, info = srs_diag(r2))
  testthat::expect_true(grepl("SKIP", r2$stdout), info = srs_diag(r2))
})

# ------------------------------------------------------------------------------
testthat::test_that("Browser eszamanlilik lane: etkin degilken/uygulamasiz GUVENLE atlar", {
  testthat::skip_if(is.null(srs_repo_root), "Repo koku bulunamadi.")
  testthat::skip_if_not_installed("processx")

  # Etkin degil (varsayilan): exit 0 + SKIP, tarayici GEREKMEZ.
  r <- srs_run_script("run_browser_concurrency_lane.R",
                      env = c(MERGEN_BROWSER_CONCURRENCY_ENABLED = "false"))
  testthat::skip_if(is.na(r$status), "Rscript cocuk sureci calistirilamadi.")
  testthat::expect_equal(r$status, 0L, info = srs_diag(r))
  testthat::expect_true(grepl("SKIP", r$stdout), info = srs_diag(r))

  # Etkin ama erisilemez uygulama + sahte tarayici binary: exit 0 + SKIP.
  r2 <- srs_run_script("run_browser_concurrency_lane.R",
                       env = c(MERGEN_BROWSER_CONCURRENCY_ENABLED = "true",
                               MERGEN_BROWSER_BIN = "/bin/true",
                               MERGEN_BROWSER_CONCURRENCY_BASE_URL = "http://127.0.0.1:59997/"))
  testthat::expect_equal(r2$status, 0L, info = srs_diag(r2))
  testthat::expect_true(grepl("SKIP", r2$stdout), info = srs_diag(r2))
})

# ==============================================================================
# Dosya Yolu: tests/testthat/test-post-deploy-smoke-contract.R
# Açıklama: mergen_post_deploy_smoke_evaluate() saf değerlendiricisini ve
#           run_post_deploy_smoke.R kapı betiğinin sözleşmesini doğrular.
#           Betik çalıştırılmaz; saf karar mantığı ve kaynak sözleşmesi denetlenir.
#           Shiny/DB/HTTP gerektirmez.
# ==============================================================================

.find_smoke_repo_root <- function() {
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

  stop("Post-deploy smoke testi repo kökünü bulamadı.", call. = FALSE)
}

repo_root_smoke <- .find_smoke_repo_root()

source(
  file.path(repo_root_smoke, "tests", "scripts", "helpers_post_deploy_smoke.R"),
  encoding = "UTF-8",
  local = globalenv()
)

# Byte-güvenli okuyucu (Windows VM'de geçersiz UTF-8 baytlarına dayanıklı).
.read_repo_text_smoke <- function(rel_path) {
  abs_path <- file.path(repo_root_smoke, rel_path)
  if (!file.exists(abs_path)) {
    stop(sprintf("Dosya bulunamadı: %s", rel_path), call. = FALSE)
  }
  size <- suppressWarnings(file.info(abs_path)$size[1])
  if (is.na(size) || size <= 0) return("")
  con <- file(abs_path, open = "rb")
  on.exit(close(con), add = TRUE)
  raw_data <- readBin(con, what = "raw", n = size)
  txt <- suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
  )
  if (is.na(txt)) txt <- ""
  enc2utf8(gsub("\r\n?|\r", "\n", txt, perl = TRUE))
}

# --- Saf değerlendirici davranışı -------------------------------------------

test_that("tum kontroller ok ise genel durum pass ve should_fail FALSE", {
  checks <- list(
    list(id = "app.boot", status = "ok"),
    list(id = "db.primary", status = "ok"),
    list(id = "storage.disk_free", status = "ok")
  )
  res <- mergen_post_deploy_smoke_evaluate(checks)
  expect_identical(res$overall, "pass")
  expect_false(res$should_fail)
  expect_identical(res$total, 3L)
  expect_identical(as.integer(res$counts[["ok"]]), 3L)
})

test_that("kritik olmayan warning degraded yapar ama bloklamaz", {
  checks <- list(
    list(id = "llm.endpoint", status = "warning"),
    list(id = "app.boot", status = "ok")
  )
  res <- mergen_post_deploy_smoke_evaluate(checks)
  expect_identical(res$overall, "degraded")
  expect_false(res$should_fail)
})

test_that("herhangi bir critical durum bloklar", {
  checks <- list(list(id = "some.check", status = "critical"))
  res <- mergen_post_deploy_smoke_evaluate(checks)
  expect_true(res$should_fail)
  expect_identical(res$overall, "fail")
  expect_true("some.check" %in% res$failing)
})

test_that("kritik kimlikli kontrolun warning olmasi bloklar", {
  checks <- list(
    list(id = "db.primary", status = "warning"),
    list(id = "app.boot", status = "ok")
  )
  res <- mergen_post_deploy_smoke_evaluate(checks)
  expect_true(res$should_fail)
  expect_identical(res$overall, "fail")
  expect_true("db.primary" %in% res$critical_failures)
})

test_that("bos veya NULL kontrol seti no_checks ile bloklar", {
  res_empty <- mergen_post_deploy_smoke_evaluate(list())
  expect_true(res_empty$should_fail)
  expect_identical(res_empty$overall, "unknown")
  expect_identical(res_empty$reason, "no_checks")
  expect_identical(res_empty$total, 0L)

  res_null <- mergen_post_deploy_smoke_evaluate(NULL)
  expect_true(res_null$should_fail)
  expect_identical(res_null$reason, "no_checks")
})

test_that("durum takma adlari fallback ile normalize edilir", {
  expect_identical(
    mergen_post_deploy_smoke_evaluate(list(list(id = "x", status = "pass")))$overall,
    "pass"
  )
  res_fail <- mergen_post_deploy_smoke_evaluate(list(list(id = "x", status = "fail")))
  expect_true(res_fail$should_fail)
  expect_true("x" %in% res_fail$failing)
  expect_identical(
    mergen_post_deploy_smoke_evaluate(list(list(id = "x", status = "warn")))$overall,
    "degraded"
  )
})

test_that("fail_on_unknown kritik unknown davranisini kontrol eder", {
  checks <- list(
    list(id = "db.primary", status = "unknown"),
    list(id = "app.boot", status = "ok")
  )
  res_default <- mergen_post_deploy_smoke_evaluate(checks)
  expect_false(res_default$should_fail)
  expect_identical(res_default$overall, "degraded")

  res_strict <- mergen_post_deploy_smoke_evaluate(checks, fail_on_unknown = TRUE)
  expect_true(res_strict$should_fail)
  expect_identical(res_strict$overall, "fail")
})

test_that("eksik status alani unknown sayilir ve bloklamaz", {
  res <- mergen_post_deploy_smoke_evaluate(list(list(id = "x")))
  expect_false(res$should_fail)
  expect_identical(res$overall, "degraded")
})

test_that("ozel normalize_fn onurlandirilir", {
  always_ok <- function(s) "ok"
  res <- mergen_post_deploy_smoke_evaluate(
    list(list(id = "x", status = "critical")),
    normalize_fn = always_ok
  )
  expect_false(res$should_fail)
  expect_identical(res$overall, "pass")
})

# --- Kapı betiği sözleşmesi --------------------------------------------------

test_that("run_post_deploy_smoke.R kapi sozlesmesini icerir", {
  script_rel <- "tests/scripts/run_post_deploy_smoke.R"
  expect_true(
    file.exists(file.path(repo_root_smoke, script_rel)),
    info = "tests/scripts/run_post_deploy_smoke.R eklenmelidir."
  )

  txt <- .read_repo_text_smoke(script_rel)

  expect_true(grepl("health_collect_checks", txt, fixed = TRUE))
  expect_true(grepl("mergen_post_deploy_smoke_evaluate", txt, fixed = TRUE))
  expect_true(grepl("source(\"app.R\"", txt, fixed = TRUE))
  expect_true(grepl("stop(", txt, fixed = TRUE))
  expect_true(grepl("redact", txt, fixed = TRUE))
})

test_that("smoke betikleri base R ile parse edilebilir", {
  for (rel in c(
    "tests/scripts/helpers_post_deploy_smoke.R",
    "tests/scripts/run_post_deploy_smoke.R"
  )) {
    abs_path <- file.path(repo_root_smoke, rel)
    # parse(file=) lokale bağlı uyarı üretebilir; suite stop_on_warning=TRUE
    # ile çalıştığı için uyarıyı bastırıp yalnızca parse başarısını doğrula.
    parsed <- tryCatch(
      suppressWarnings(parse(file = abs_path, encoding = "UTF-8")),
      error = function(e) NULL
    )
    expect_false(is.null(parsed), info = rel)
    expect_true(length(parsed) > 0L, info = rel)
  }
})

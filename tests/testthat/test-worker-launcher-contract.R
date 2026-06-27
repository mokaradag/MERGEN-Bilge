# ==============================================================================
# Dosya Yolu: tests/testthat/test-worker-launcher-contract.R
# Açıklama: Çok-worker (yatay ölçekleme) başlatıcı sözleşmesi
#           (tools/run_mergen_workers.R).
#
# Doğrulananlar:
#   - Dosya ASCII-only'dir (operasyonel betik konvansiyonu) ve quit() içermez.
#   - VARSAYILAN tek-süreç davranışı korunur: MERGEN_WORKERS ayarlı değilken
#     worker sayısı 1, tek port (mevcut davranışla aynı).
#   - Port matematiği doğru: base + i (i = 0..n-1); üst sınır uygulanır.
#   - Launch planı LAUNCH YAPMADAN doğru env/komutu üretir (MERGEN_PORT,
#     MERGEN_RUN_APP=true, app.R).
#   - CDN / ağır tarayıcı-otomasyon bağımlılığı eklenmez.
#
# Bu test GERÇEK worker SÜREÇ BAŞLATMAZ; yalnızca define-only modda fonksiyonları
# source eder ve saf planlama davranışını doğrular.
# ==============================================================================

testthat::local_edition(3)

.worker_launcher_path <- function() {
  cand <- c(
    file.path("..", "..", "tools", "run_mergen_workers.R"),
    file.path(getwd(), "tools", "run_mergen_workers.R")
  )
  for (p in cand) if (file.exists(p)) return(normalizePath(p, mustWork = FALSE))
  cand[1]
}

.load_worker_launcher <- function() {
  env <- new.env(parent = globalenv())
  withr::local_envvar(c(MERGEN_WORKERS_DEFINE_ONLY = "true"))
  source(.worker_launcher_path(), local = env)
  env
}

# Yorum satirlarini (acIklayIcI metin) tarama oncesi atar; boylece acIklama
# metnindeki "quit()" / "CDN" gibi kelimeler yanlis pozitif uretmez (CLAUDE.md
# runner-contract kurali).
.strip_r_comments <- function(txt) {
  lines <- strsplit(txt, "\n", fixed = TRUE)[[1]]
  code <- lines[!grepl("^\\s*#", lines)]
  paste(code, collapse = "\n")
}

test_that("baslatici dosyasi ASCII-only'dir ve quit() icermez", {
  path <- .worker_launcher_path()
  expect_true(file.exists(path))
  raw <- readBin(path, what = "raw", n = file.info(path)$size)
  # Operasyonel betik: ASCII-only (locale-bagimsiz source/Rscript guvenligi).
  expect_false(any(as.integer(raw) > 127L), info = "run_mergen_workers.R ASCII-only olmalidir.")
  code <- .strip_r_comments(rawToChar(raw))
  expect_false(grepl("quit(", code, fixed = TRUE),
               info = "source(...)-guvenli olmali: quit() icermemeli.")
  # Hicbir CDN / agir tarayici-otomasyon bagimliligi eklenmemeli (kod satirlari).
  expect_false(grepl("(?i)(http://|https://|playwright|selenium|chromote|cdn)", code, perl = TRUE),
               info = "CDN/agir bagimlilik eklenmemeli.")
})

test_that("VARSAYILAN tek-surec davranisi korunur (MERGEN_WORKERS yokken 1)", {
  env <- .load_worker_launcher()
  withr::with_envvar(c(MERGEN_WORKERS = "", MERGEN_WORKERS_MAX = ""), {
    expect_equal(env$mergen_worker_count(), 1L)
    expect_identical(env$mergen_worker_ports(8009L, 1L), 8009L)
  })
})

test_that("port matematigi: base + i; ust sinir uygulanir", {
  env <- .load_worker_launcher()
  expect_identical(env$mergen_worker_ports(8009L, 4L), c(8009L, 8010L, 8011L, 8012L))
  withr::with_envvar(c(MERGEN_WORKERS = "99", MERGEN_WORKERS_MAX = "8"), {
    expect_equal(env$mergen_worker_count(), 8L)
  })
})

test_that("launch plani LAUNCH YAPMADAN dogru env/komut uretir", {
  env <- .load_worker_launcher()
  plan <- env$mergen_worker_launch_plan(base = 8009L, count = 3L, host = "0.0.0.0",
                                        repo_root = getwd())
  expect_length(plan, 3L)
  expect_equal(plan[[1]]$port, 8009L)
  expect_equal(plan[[3]]$port, 8011L)
  expect_identical(plan[[2]]$env[["MERGEN_PORT"]], "8010")
  expect_identical(plan[[2]]$env[["MERGEN_RUN_APP"]], "true")
  expect_true(any(grepl("app.R", plan[[1]]$args, fixed = TRUE)))
})

test_that("dry_run plani dondurur, gercek surec baslatmaz", {
  env <- .load_worker_launcher()
  withr::with_envvar(c(MERGEN_WORKERS = "2", MERGEN_BASE_PORT = "8009"), {
    plan <- suppressWarnings(env$mergen_start_workers(dry_run = TRUE))
    expect_length(plan, 2L)
    expect_equal(vapply(plan, function(s) s$port, integer(1)), c(8009L, 8010L))
  })
})

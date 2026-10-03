test_that("açık görev paketleri arama yolu olmadan ve uyarısız çözülür", {
  kok <- resolve_repo_root_for_tests()
  env <- new.env(parent = baseenv())
  source(file.path(kok, "R", "helpers_worker_monitor.R"), local = env, encoding = "UTF-8")
  env$getExportedValue <- function(...) stop("Kullanılmayan paket dışa aktarımı okundu")
  payload <- env$worker_monitor_serialize_explicit_task(
    function() c(head(1:5, 2L), median(1:5)), list(), c("utils", "stats")
  )
  dosya <- withr::local_tempfile(fileext = ".rds")
  betik <- withr::local_tempfile(fileext = ".R")
  saveRDS(payload, dosya)
  writeLines(c(
    "options(warn = 2)",
    "stopifnot(!'package:stats' %in% search(), !'package:utils' %in% search())",
    "fn <- unserialize(readRDS(commandArgs(trailingOnly = TRUE)[1]))",
    "stopifnot(identical(fn(), 1:3))",
    "stopifnot(!'package:stats' %in% search(), !'package:utils' %in% search())"
  ), betik, useBytes = TRUE)
  rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
  cikti <- system2(rscript,
                   c("--vanilla", "--default-packages=NULL", shQuote(betik), shQuote(dosya)),
                   stdout = TRUE, stderr = TRUE)
  expect_null(attr(cikti, "status"), info = paste(cikti, collapse = "\n"))
  expect_length(cikti, 0L)
})

test_that("açık paket görevi gizli küreseli okuyamaz ve verilen değer önceliklidir", {
  verilen_head <- function(...) 17L
  environment(verilen_head) <- baseenv()
  payload <- worker_monitor_serialize_explicit_task(
    function() head(1:5, 2L),
    list(head = verilen_head), c("utils", "stats")
  )
  expect_identical(unserialize(payload)(), 17L)
  eski <- new.env(parent = globalenv())
  eski$gizli_deger <- 99L
  fn <- function() gizli_deger
  environment(fn) <- eski
  payload <- worker_monitor_serialize_explicit_task(fn, list(), "utils")
  expect_error(unserialize(payload)(), "gizli_deger")
})

test_that("paket hazırlığı hatası görev kaydını açık bırakmaz", {
  onceki <- get_worker_monitor_info()$active_jobs
  expect_error(tracked_future_promise(
    function() 1L, task_type = "unit_package_failure", dependency_mode = "explicit",
    packages = "mergen_missing_worker_package"
  ), "Açık bağımlılık hazırlığı başarısız")
  expect_equal(get_worker_monitor_info()$active_jobs, onceki)
})

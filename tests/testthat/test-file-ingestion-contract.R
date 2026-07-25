# ==============================================================================
# Dosya Yolu: tests/testthat/test-file-ingestion-contract.R
# Açıklama: Bloklamayan dosya alım hattının YAPISAL sözleşmesi. Kaynak sırası,
#           katman ayrımı, worker'a canlı Shiny/reaktif nesne taşınmaması,
#           kalıcı indeks yazımının ANA SÜREÇTE kalması, her iki yükleme
#           girişinin ORTAK hattı kullanması ve tam-bir-kez kayıt korunur.
#           Çevrimdışı ve deterministiktir; uygulama boot edilmez.
# ==============================================================================

.read_ingestion_source <- function(relative_path) {
  kok <- resolve_repo_root_for_tests()
  ham <- readBin(
    file.path(kok, relative_path),
    what = "raw",
    n = file.info(file.path(kok, relative_path))$size
  )
  iconv(rawToChar(ham), from = "UTF-8", to = "UTF-8", sub = "byte")
}

.ingestion_manifest_paths <- function() {
  kok <- resolve_repo_root_for_tests()
  manifest_env <- new.env(parent = globalenv())
  source(file.path(kok, "R", "config_source_manifest.R"), encoding = "UTF-8", local = manifest_env)
  manifest_env$source_manifest_runtime_paths
}

test_that("alım hattı katmanları manifestte bağımlılık sırasında yüklenir", {
  yollar <- .ingestion_manifest_paths()

  sirali <- c(
    "R/helpers_files.R",
    "R/helpers_file_ingestion_task.R",
    "R/helpers_file_ingestion_worker.R",
    "R/helpers_file_ingestion_queue.R",
    "R/helpers_file_ingestion_runtime.R"
  )

  indeksler <- match(sirali, yollar)
  expect_false(anyNA(indeksler))
  expect_identical(indeksler, sort(indeksler))
})

test_that("saf plan ve worker katmanları Shiny/reaktif bağımlılığı taşımaz", {
  for (dosya in c("R/helpers_file_ingestion_task.R", "R/helpers_file_ingestion_worker.R")) {
    metin <- .read_ingestion_source(dosya)

    expect_false(grepl("reactiveVal", metin, fixed = TRUE), info = dosya)
    expect_false(grepl("reactiveValues", metin, fixed = TRUE), info = dosya)
    expect_false(grepl("observeEvent", metin, fixed = TRUE), info = dosya)
    expect_false(grepl("showToast", metin, fixed = TRUE), info = dosya)
    expect_false(grepl("session$", metin, fixed = TRUE), info = dosya)
    expect_false(grepl("sendCustomMessage", metin, fixed = TRUE), info = dosya)
  }
})

test_that("worker görevi izole global paketiyle gönderilir (oturum kapanışı serileşmez)", {
  metin <- .read_ingestion_source("R/helpers_file_ingestion_runtime.R")

  expect_true(grepl("dependency_mode = \"explicit\"", metin, fixed = TRUE))
  expect_true(grepl("task_type = \"file_ingestion\"", metin, fixed = TRUE))
  expect_true(grepl("file_ingestion_worker_globals()", metin, fixed = TRUE))
})

test_that("kalıcı indeks yazımı ana süreçte kalır, worker'a taşınmaz", {
  worker_txt <- .read_ingestion_source("R/helpers_file_ingestion_worker.R")
  runtime_txt <- .read_ingestion_source("R/helpers_file_ingestion_runtime.R")

  expect_false(grepl("mergen_index_persisted_files", worker_txt, fixed = TRUE))
  expect_false(grepl("global_register_file", worker_txt, fixed = TRUE))
  expect_false(grepl("mergen_register_uploaded_file", worker_txt, fixed = TRUE))

  expect_true(grepl("mergen_index_persisted_files\\(", runtime_txt, perl = TRUE))
})

test_that("toplu indeks yazımı tek mutasyonda yapılır", {
  metin <- .read_ingestion_source("R/config_file_store_index_mutation.R")

  expect_true(grepl("mergen_index_persisted_files <- function", metin, fixed = TRUE))
  expect_true(grepl(".file_store_index_entry <- function", metin, fixed = TRUE))

  govde <- sub("(?s).*mergen_index_persisted_files <- function", "", metin, perl = TRUE)
  govde <- sub("(?s)mergen_remove_from_index.*", "", govde, perl = TRUE)
  expect_equal(
    length(gregexpr(".file_store_mutate_index(", govde, fixed = TRUE)[[1]]),
    1L
  )
})

test_that("her iki yükleme girişi de ORTAK alım hattını kullanır", {
  fm_txt <- .read_ingestion_source("R/helpers_file_manager_upload_runtime.R")
  chat_txt <- .read_ingestion_source("R/helpers_file_pipeline.R")

  for (metin in list(fm_txt, chat_txt)) {
    expect_true(grepl("file_ingestion_plan_batch(", metin, fixed = TRUE))
    expect_true(grepl("file_ingestion_submit_batch(", metin, fixed = TRUE))
  }

  # Senkron toplu döngü geri gelmemeli.
  expect_false(grepl("withProgress", fm_txt, fixed = TRUE))
  expect_false(grepl("process_next", chat_txt, fixed = TRUE))
})

test_that("kalıcılaştırma tam olarak bir kez yapılır", {
  metin <- .read_ingestion_source("R/helpers_file_pipeline.R")

  expect_true(grepl("already_persisted", metin, fixed = TRUE))
  expect_true(grepl("zaten_kalici <- isTRUE(already_persisted) || is_under_mcp_base(dest)", metin, fixed = TRUE))
  expect_equal(length(gregexpr("global_register_file(", metin, fixed = TRUE)[[1]]), 1L)
  expect_equal(length(gregexpr("copy_to_mcp_base(", metin, fixed = TRUE)[[1]]), 1L)
})

test_that("eşzamanlılık ve kuyruk sınırları yapılandırılabilir ve varsayılanları güvenlidir", {
  metin <- .read_ingestion_source("R/helpers_file_ingestion_queue.R")

  expect_true(grepl("MERGEN_FILE_INGESTION_MAX_CONCURRENT", metin, fixed = TRUE))
  expect_true(grepl("MERGEN_FILE_INGESTION_MAX_QUEUE", metin, fixed = TRUE))
  expect_true(grepl("MERGEN_FILE_INGESTION_METRICS", metin, fixed = TRUE))
  expect_true(grepl("future::nbrOfFreeWorkers", metin, fixed = TRUE))

  ornek <- .read_ingestion_source(".Renviron.example")
  expect_true(grepl("MERGEN_FILE_INGESTION_MAX_CONCURRENT", ornek, fixed = TRUE))
  expect_true(grepl("MERGEN_FILE_INGESTION_MAX_QUEUE", ornek, fixed = TRUE))
})

test_that("gönderim çağrısı pahalı işi olay döngüsünde yapmaz", {
  kok <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())

  for (dosya in c(
    "R/utils_upload_validator.R",
    "R/helpers_files.R",
    "R/helpers_file_ingestion_task.R",
    "R/helpers_file_ingestion_worker.R",
    "R/helpers_file_ingestion_queue.R",
    "R/helpers_file_ingestion_runtime.R"
  )) {
    source(file.path(kok, dosya), encoding = "UTF-8", local = env)
  }

  env$cat <- function(...) invisible(NULL)
  env$file_ingestion_reset_state()
  env$file_ingestion_pool_has_capacity <- function() TRUE

  yuklemeler <- lapply(1:4, function(i) {
    yol <- tempfile(fileext = ".txt")
    writeBin(as.raw(rep(65L, 512L * 1024L)), yol)
    list(name = sprintf("buyuk_%d.txt", i), datapath = yol,
         size = file.info(yol)$size, type = "text/plain")
  })

  plan <- env$file_ingestion_plan_batch(
    uploads = yuklemeler, user_id = "42",
    allowed_ext = c("txt"), max_size_mb = 25L, batch_id = "perf"
  )
  expect_equal(length(plan$tasks), 4L)

  calisan <- 0L
  env$file_ingestion_run_job <- function(job) {
    calisan <<- calisan + 1L
    invisible(TRUE)
  }

  controller <- env$file_ingestion_create_controller(session = NULL)
  basladi <- Sys.time()
  outcome <- env$file_ingestion_submit_batch(controller, plan$tasks, "42", batch_id = "perf")
  gecen_ms <- as.numeric(difftime(Sys.time(), basladi, units = "secs")) * 1000

  expect_identical(outcome$status, "started")
  expect_equal(calisan, 1L)

  # Pahalı iş (kopyalama/doğrulama) gönderim sırasında YAPILMAZ.
  kullanici_dizini <- file.path(getOption("mergen.mcp_base_dir", tempdir()), "user_42")
  kopyalanan <- if (dir.exists(kullanici_dizini)) {
    length(list.files(kullanici_dizini, pattern = "buyuk_"))
  } else {
    0L
  }
  expect_equal(kopyalanan, 0L)
  expect_lt(gecen_ms, 500)
})

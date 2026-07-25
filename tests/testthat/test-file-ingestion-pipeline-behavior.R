# ==============================================================================
# Dosya Yolu: tests/testthat/test-file-ingestion-pipeline-behavior.R
# Açıklama: Bloklamayan dosya alım hattının (R/helpers_file_ingestion_*.R)
#           davranış sözleşmesi. Saf plan katmanı, worker yürütme katmanı
#           (gerçek geçici dosya sistemiyle), sınırlı eşzamanlılık/kuyruk
#           katmanı ve ana süreç commit/iptal katmanı doğrulanır.
#
#           Çevrimdışı ve deterministiktir: gerçek future/PSOCK worker, LLM,
#           veritabanı, tarayıcı, SSO veya ağ erişimi yoktur. Dosya deposu
#           yolları helper_load_file_store.R tarafından tempdir altına alınır.
# ==============================================================================

.ingestionEnv <- function() {
  env <- new.env(parent = globalenv())
  kok <- resolve_repo_root_for_tests()

  for (dosya in c(
    "R/utils_upload_validator.R",
    "R/helpers_worker_monitor.R",
    "R/helpers_files.R",
    "R/helpers_file_ingestion_task.R",
    "R/helpers_file_ingestion_worker.R",
    "R/helpers_file_ingestion_queue.R",
    "R/helpers_file_ingestion_runtime.R"
  )) {
    source(file.path(kok, dosya), encoding = "UTF-8", local = env)
  }

  env$cat <- function(...) invisible(NULL)
  env$log_warn <- function(...) invisible(NULL)
  env$file_ingestion_reset_state()
  env
}

.ingestionUpload <- function(name, content = "alim hatti test icerigi") {
  yol <- file.path(tempdir(), paste0("kaynak_", basename(tempfile()), "_", name))
  writeLines(content, yol)
  list(name = name, datapath = yol, size = file.info(yol)$size, type = "text/plain")
}

.ingestionTask <- function(env, upload, user_id = "42", allowed = c("txt", "pdf")) {
  env$file_ingestion_task_snapshot(
    upload = upload, user_id = user_id, max_size_mb = 25L,
    allowed_ext = allowed, batch_id = "b-test"
  )
}

# ------------------------------------------------------------------------------
# Saf plan katmanı
# ------------------------------------------------------------------------------

test_that("plan katmanı yinelenen, desteklenmeyen ve büyük dosyaları ayırır", {
  env <- .ingestionEnv()

  df <- data.frame(
    name = c("mevcut.txt", "Türkçe_çalışma.txt", "zararli.exe", "kocaman.txt"),
    datapath = c("/tmp/a.txt", "/tmp/b.txt", "/tmp/c.exe", "/tmp/d.txt"),
    size = c(10, 20, 30, 99 * 1024 * 1024),
    type = rep("text/plain", 4),
    stringsAsFactors = FALSE
  )

  plan <- env$file_ingestion_plan_batch(
    uploads = df, existing_names = "mevcut.txt", user_id = "42",
    allowed_ext = c("txt", "pdf"), max_size_mb = 25L, batch_id = "b1"
  )

  expect_equal(plan$duplicate_names, "mevcut.txt")
  expect_equal(length(plan$tasks), 1L)
  expect_identical(plan$tasks[[1]]$name, "Türkçe_çalışma.txt")

  kodlar <- vapply(plan$rejected, function(x) x$code, character(1))
  expect_true("ext_not_allowed" %in% kodlar)
  expect_true("too_large" %in% kodlar)
})

test_that("plan katmanı worker'a yalnızca düz skaler değer taşır", {
  env <- .ingestionEnv()
  gorev <- .ingestionTask(env, .ingestionUpload("rapor.txt"))

  expect_true(is.list(gorev))
  expect_true(all(vapply(gorev, function(x) is.atomic(x) || is.null(x), logical(1))))
  expect_false(any(vapply(gorev, is.environment, logical(1))))
  expect_false(any(vapply(gorev, is.function, logical(1))))
})

test_that("kalıcı depolama kökü ana süreçte çözülüp göreve iliştirilir", {
  env <- .ingestionEnv()
  withr::local_options(list(mergen.mcp_base_dir = "/kalici/kok"))

  gorev <- env$file_ingestion_task_snapshot(
    upload = list(name = "a.txt", datapath = "/tmp/a.txt", size = 1, type = ""),
    user_id = "42", max_size_mb = 25L, allowed_ext = "txt", batch_id = "b1"
  )

  expect_identical(gorev$storage_base, "/kalici/kok")
})

test_that("worker, ana süreçten gelen depolama kökünü zorlar (seçenekler worker'a taşınmaz)", {
  env <- .ingestionEnv()
  yukleme <- .ingestionUpload("kok_testi.txt")

  hedef_kok <- file.path(tempdir(), paste0("zorlanan_kok_", basename(tempfile())))
  dir.create(hedef_kok, recursive = TRUE, showWarnings = FALSE)

  gorev <- env$file_ingestion_task_snapshot(
    upload = yukleme, user_id = "42", max_size_mb = 25L,
    allowed_ext = "txt", batch_id = "b1", storage_base = hedef_kok
  )

  # Worker'ı taklit etmek için seçenek BİLEREK farklı bırakılır.
  withr::local_options(list(mergen.mcp_base_dir = file.path(tempdir(), "yanlis_kok")))
  sonuc <- env$file_ingestion_execute_task(gorev)

  expect_true(sonuc$ok)
  expect_true(startsWith(sonuc$dest, hedef_kok))
  expect_true(grepl("user_42", sonuc$dest, fixed = TRUE))
  # Görev bittiğinde çağıranın seçeneği geri yüklenmiş olmalı.
  expect_identical(getOption("mergen.mcp_base_dir"), file.path(tempdir(), "yanlis_kok"))
})

test_that("geçersiz kullanıcı kimlikleri kalıcı yazma için reddedilir", {
  env <- .ingestionEnv()

  expect_false(env$file_ingestion_valid_user_id("0"))
  expect_false(env$file_ingestion_valid_user_id("unknown"))
  expect_false(env$file_ingestion_valid_user_id(""))
  expect_false(env$file_ingestion_valid_user_id(NULL))
  expect_true(env$file_ingestion_valid_user_id("42"))
})

# ------------------------------------------------------------------------------
# Worker yürütme katmanı (gerçek geçici dosya sistemi)
# ------------------------------------------------------------------------------

test_that("worker geçerli dosyayı kullanıcı kovasına kopyalar ve doğrular", {
  env <- .ingestionEnv()
  yukleme <- .ingestionUpload("Türkçe_rapor.txt")

  sonuc <- env$file_ingestion_execute_task(.ingestionTask(env, yukleme))

  expect_true(sonuc$ok)
  expect_identical(sonuc$name, "Türkçe_rapor.txt")
  expect_true(file.exists(sonuc$dest))
  expect_true(grepl("user_42", sonuc$dest, fixed = TRUE))
  expect_equal(as.numeric(sonuc$size), as.numeric(file.info(yukleme$datapath)$size))
  expect_true(sonuc$total_ms >= 0)
})

test_that("worker toplu partide bir dosyanın hatası diğerlerini durdurmaz", {
  env <- .ingestionEnv()

  gorevler <- list(
    .ingestionTask(env, .ingestionUpload("iyi_bir.txt")),
    .ingestionTask(env, list(name = "yok.txt", datapath = "/olmayan/yol/yok.txt", size = 5, type = "")),
    .ingestionTask(env, .ingestionUpload("iyi_iki.txt"))
  )

  sonuclar <- env$file_ingestion_execute_batch(gorevler)

  expect_equal(length(sonuclar), 3L)
  expect_true(sonuclar[[1]]$ok)
  expect_false(sonuclar[[2]]$ok)
  expect_true(sonuclar[[3]]$ok)
  expect_true(file.exists(sonuclar[[1]]$dest))
  expect_true(file.exists(sonuclar[[3]]$dest))
})

test_that("worker doğrulama başarısız olursa hiçbir dosya kopyalamaz", {
  env <- .ingestionEnv()
  yukleme <- .ingestionUpload("zararli.exe")
  gorev <- .ingestionTask(env, yukleme, allowed = c("txt", "pdf"))

  sonuc <- env$file_ingestion_execute_task(gorev)

  expect_false(sonuc$ok)
  expect_identical(sonuc$code, "ext_not_allowed")
  expect_identical(sonuc$dest, "")
})

test_that("worker geçersiz kullanıcı kimliğinde kopyalama denemez", {
  env <- .ingestionEnv()
  gorev <- .ingestionTask(env, .ingestionUpload("rapor.txt"), user_id = "0")

  sonuc <- env$file_ingestion_execute_task(gorev)

  expect_false(sonuc$ok)
  expect_identical(sonuc$code, "invalid_user")
})

test_that("kopyalama hatası açık kodla raporlanır", {
  env <- .ingestionEnv()
  env$copy_to_mcp_base <- function(upload, user_id) stop("disk dolu (test)")

  sonuc <- env$file_ingestion_execute_task(.ingestionTask(env, .ingestionUpload("rapor.txt")))

  expect_false(sonuc$ok)
  expect_identical(sonuc$code, "copy_failed")
  expect_true(grepl("disk dolu", sonuc$error, fixed = TRUE))
})

test_that("bütünlük doğrulaması başarısızsa yarım hedef dosya temizlenir", {
  env <- .ingestionEnv()
  yukleme <- .ingestionUpload("rapor.txt", content = "cok daha uzun bir icerik satiri")

  bozuk_hedef <- file.path(tempdir(), paste0("bozuk_", basename(tempfile()), ".txt"))
  writeLines("x", bozuk_hedef)
  env$copy_to_mcp_base <- function(upload, user_id) bozuk_hedef

  sonuc <- env$file_ingestion_execute_task(.ingestionTask(env, yukleme))

  expect_false(sonuc$ok)
  expect_identical(sonuc$code, "size_mismatch")
  expect_false(file.exists(bozuk_hedef))
  expect_true(file.exists(yukleme$datapath))
})

test_that("worker global paketi canlı oturum/reaktif nesne taşımaz", {
  env <- .ingestionEnv()
  paket <- env$file_ingestion_worker_globals(refresh = TRUE)

  expect_true(length(paket) > 0L)
  expect_true(all(vapply(paket, function(x) is.function(x) || is.atomic(x), logical(1))))
  expect_true("copy_to_mcp_base" %in% names(paket))
  expect_true("file_ingestion_execute_batch" %in% names(paket))
  expect_false("session" %in% names(paket))
})

# ------------------------------------------------------------------------------
# Kalıcı indeks commit'i
# ------------------------------------------------------------------------------

test_that("parti indeks commit'i her dosyayı TEK kez kaydeder", {
  env <- .ingestionEnv()

  gorevler <- list(
    .ingestionTask(env, .ingestionUpload("indeks_bir.txt")),
    .ingestionTask(env, .ingestionUpload("indeks_iki.txt"))
  )
  sonuclar <- env$file_ingestion_execute_batch(gorevler)

  yazim_sayisi <- 0L
  env$mergen_index_persisted_files <- function(entries, user_id = NULL) {
    yazim_sayisi <<- yazim_sayisi + 1L
    vapply(entries, function(e) e$display, character(1))
  }

  commit <- env$file_ingestion_commit_index(sonuclar, "42")

  expect_equal(yazim_sayisi, 1L)
  expect_equal(length(commit$indexed), 2L)
  expect_true(commit$ms >= 0)
})

test_that("indeks yazımı çökerse commit hata fırlatmaz", {
  env <- .ingestionEnv()
  sonuclar <- env$file_ingestion_execute_batch(list(.ingestionTask(env, .ingestionUpload("hata.txt"))))
  env$mergen_index_persisted_files <- function(entries, user_id = NULL) stop("indeks kilidi kirik")

  commit <- expect_silent(env$file_ingestion_commit_index(sonuclar, "42"))
  expect_equal(length(commit$indexed), 0L)
})

test_that("aynı görünen adlı dosyalar kullanıcı bazında ayrı indekslenir", {
  env <- .ingestionEnv()

  bir <- env$file_ingestion_execute_task(.ingestionTask(env, .ingestionUpload("ortak_ad.txt"), user_id = "42"))
  iki <- env$file_ingestion_execute_task(.ingestionTask(env, .ingestionUpload("ortak_ad.txt"), user_id = "77"))

  expect_true(bir$ok)
  expect_true(iki$ok)
  expect_true(grepl("user_42", bir$dest, fixed = TRUE))
  expect_true(grepl("user_77", iki$dest, fixed = TRUE))
  expect_false(identical(bir$dest, iki$dest))

  mergen_index_persisted_files(list(list(path = bir$dest, display = "ortak_ad.txt")), user_id = "42")
  mergen_index_persisted_files(list(list(path = iki$dest, display = "ortak_ad.txt")), user_id = "77")

  expect_identical(resolve_uploaded_file("ortak_ad.txt", user_id = "42"), bir$dest)
  expect_identical(resolve_uploaded_file("ortak_ad.txt", user_id = "77"), iki$dest)
})

# ------------------------------------------------------------------------------
# Sınırlı eşzamanlılık ve kuyruk
# ------------------------------------------------------------------------------

test_that("eşzamanlı parti sayısı yapılandırılan sınırı aşmaz", {
  env <- .ingestionEnv()
  withr::local_options(list(mergen.file_ingestion.max_concurrent = 2L))
  env$file_ingestion_pool_has_capacity <- function() TRUE

  expect_true(env$file_ingestion_try_acquire_slot())
  expect_true(env$file_ingestion_try_acquire_slot())
  expect_false(env$file_ingestion_try_acquire_slot())

  env$file_ingestion_release_slot()
  expect_true(env$file_ingestion_try_acquire_slot())
  expect_equal(env$file_ingestion_queue_status()$active_batches, 2L)
})

test_that("worker havuzu doluyken yeni alım görevi gönderilmez", {
  env <- .ingestionEnv()
  env$file_ingestion_pool_has_capacity <- function() FALSE

  expect_false(env$file_ingestion_try_acquire_slot())
  expect_equal(env$file_ingestion_queue_status()$active_batches, 0L)
})

test_that("kuyruk dolduğunda iş sessizce düşürülmez, açık red döner", {
  env <- .ingestionEnv()
  withr::local_options(list(mergen.file_ingestion.max_queue = 2L))

  expect_true(env$file_ingestion_enqueue(list(id = "1", session_token = "t1")))
  expect_true(env$file_ingestion_enqueue(list(id = "2", session_token = "t1")))
  expect_false(env$file_ingestion_enqueue(list(id = "3", session_token = "t1")))
  expect_equal(env$file_ingestion_queue_status()$rejected_total, 1L)
})

test_that("kapanan oturumun bekleyen işleri kuyruktan düşer", {
  env <- .ingestionEnv()

  env$file_ingestion_enqueue(list(id = "1", session_token = "kapanan"))
  env$file_ingestion_enqueue(list(id = "2", session_token = "acik"))
  env$file_ingestion_enqueue(list(id = "3", session_token = "kapanan"))

  expect_equal(env$file_ingestion_cancel_session_jobs("kapanan"), 2L)
  expect_equal(env$file_ingestion_queue_status()$queued_batches, 1L)
})

test_that("kapasite yokken parti kuyruğa alınır, varken hemen başlar", {
  env <- .ingestionEnv()
  withr::local_options(list(mergen.file_ingestion.max_concurrent = 1L))
  env$file_ingestion_pool_has_capacity <- function() TRUE

  calistirilan <- character()
  env$file_ingestion_run_job <- function(job) {
    calistirilan <<- c(calistirilan, job$id)
    invisible(TRUE)
  }

  controller <- env$file_ingestion_create_controller(session = NULL)
  gorevler <- list(.ingestionTask(env, .ingestionUpload("kuyruk.txt")))

  ilk <- env$file_ingestion_submit_batch(controller, gorevler, "42", batch_id = "ilk")
  ikinci <- env$file_ingestion_submit_batch(controller, gorevler, "42", batch_id = "ikinci")

  expect_identical(ilk$status, "started")
  expect_identical(ikinci$status, "queued")
  expect_equal(calistirilan, "ilk")
})

test_that("boş görev listesi hatta gönderilmez", {
  env <- .ingestionEnv()
  controller <- env$file_ingestion_create_controller(session = NULL)

  expect_identical(env$file_ingestion_submit_batch(controller, list(), "42")$status, "empty")
})

# ------------------------------------------------------------------------------
# Ana süreç commit / iptal / oturum koruması
# ------------------------------------------------------------------------------

.ingestionJob <- function(env, controller, results_user = "42", on_complete = NULL) {
  list(
    id = "job-1",
    tasks = list(),
    user_id = results_user,
    controller = controller,
    epoch = controller$epoch,
    session_token = controller$session_token,
    on_complete = on_complete,
    on_failure = NULL,
    queued_at = Sys.time(),
    run = env$file_ingestion_run_job
  )
}

test_that("başarılı parti indekslenir ve UI geri çağrısı çalışır", {
  env <- .ingestionEnv()
  sonuclar <- env$file_ingestion_execute_batch(list(.ingestionTask(env, .ingestionUpload("commit.txt"))))

  yazilan <- NULL
  env$mergen_index_persisted_files <- function(entries, user_id = NULL) {
    yazilan <<- list(entries = entries, user_id = user_id)
    vapply(entries, function(e) e$display, character(1))
  }

  cagrildi <- NULL
  controller <- env$file_ingestion_create_controller(session = NULL)
  job <- .ingestionJob(env, controller, on_complete = function(results, ctx) {
    cagrildi <<- ctx
  })

  env$file_ingestion_finish_job(job, sonuclar)

  expect_false(is.null(yazilan))
  expect_identical(yazilan$user_id, "42")
  expect_false(is.null(cagrildi))
  expect_identical(cagrildi$batch_id, "job-1")
  expect_equal(cagrildi$summary$succeeded, 1L)
})

test_that("oturum kapandıysa UI geri çağrısı çalışmaz ama dosya yine indekslenir", {
  env <- .ingestionEnv()
  sonuclar <- env$file_ingestion_execute_batch(list(.ingestionTask(env, .ingestionUpload("kapali.txt"))))

  indekslendi <- FALSE
  env$mergen_index_persisted_files <- function(entries, user_id = NULL) {
    indekslendi <<- TRUE
    vapply(entries, function(e) e$display, character(1))
  }

  cagrildi <- FALSE
  controller <- env$file_ingestion_create_controller(session = NULL)
  job <- .ingestionJob(env, controller, on_complete = function(results, ctx) cagrildi <<- TRUE)

  controller$active <- FALSE
  env$file_ingestion_finish_job(job, sonuclar)

  expect_true(indekslendi)
  expect_false(cagrildi)
  expect_true(file.exists(sonuclar[[1]]$dest))
})

test_that("iptal edilen parti indekslenmez ve kopyaladığı dosyalar temizlenir", {
  env <- .ingestionEnv()
  sonuclar <- env$file_ingestion_execute_batch(list(.ingestionTask(env, .ingestionUpload("iptal.txt"))))
  hedef <- sonuclar[[1]]$dest
  expect_true(file.exists(hedef))

  indekslendi <- FALSE
  env$mergen_index_persisted_files <- function(entries, user_id = NULL) {
    indekslendi <<- TRUE
    character()
  }

  cagrildi <- FALSE
  controller <- env$file_ingestion_create_controller(session = NULL)
  job <- .ingestionJob(env, controller, on_complete = function(results, ctx) cagrildi <<- TRUE)

  env$file_ingestion_cancel_controller(controller)
  env$file_ingestion_finish_job(job, sonuclar)

  expect_false(indekslendi)
  expect_false(cagrildi)
  expect_false(file.exists(hedef))
})

test_that("worker hatası slotu serbest bırakır ve hata geri çağrısını tetikler", {
  env <- .ingestionEnv()
  env$file_ingestion_pool_has_capacity <- function() TRUE
  expect_true(env$file_ingestion_try_acquire_slot())

  hata <- NULL
  controller <- env$file_ingestion_create_controller(session = NULL)
  job <- .ingestionJob(env, controller)
  job$on_failure <- function(message, tasks) hata <<- message

  env$file_ingestion_fail_job(job, simpleError("worker cokti"))

  expect_identical(hata, "worker cokti")
  expect_equal(env$file_ingestion_queue_status()$active_batches, 0L)
})

test_that("metrik satırı dosya adı veya yol sızdırmaz", {
  env <- .ingestionEnv()
  ozet <- env$file_ingestion_summarize_results(list(
    list(ok = TRUE, size = 100, total_ms = 12),
    list(ok = FALSE, size = 0, total_ms = 3)
  ))

  satir <- env$file_ingestion_metrics_line("b1", ozet, queue_wait_ms = 5)

  expect_equal(ozet$succeeded, 1L)
  expect_equal(ozet$failed, 1L)
  expect_true(grepl("files=2", satir, fixed = TRUE))
  expect_false(grepl("\\.txt", satir))
  expect_false(grepl("user_", satir, fixed = TRUE))
})

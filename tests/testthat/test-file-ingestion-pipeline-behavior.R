# ==============================================================================
# Dosya Yolu: tests/testthat/test-file-ingestion-pipeline-behavior.R
# Açıklama: Bloklamayan dosya alım hattının (R/helpers_file_ingestion_*.R)
#           davranış sözleşmesi. Saf plan katmanı, worker yürütme katmanı
#           (gerçek geçici dosya sistemiyle), sınırlı eşzamanlılık/kuyruk
#           katmanı ve ana süreç commit/iptal katmanı doğrulanır.
#
#           Çevrimdışı çalışır: geri alma testleri bağımsız R işçisi kullanır;
#           LLM, veritabanı, tarayıcı, SSO veya ağ erişimi yoktur. Dosya deposu
#           yolları helper_load_file_store.R tarafından tempdir altına alınır.
# ==============================================================================

.ingestionEnv <- function() {
  env <- new.env(parent = globalenv())
  kok <- resolve_repo_root_for_tests()

  for (dosya in c(
    "R/utils_upload_validator.R",
    "R/helpers_worker_monitor.R",
    "R/helpers_files_path.R",
    # Rezervasyon primitifleri + sahiplik kanıtlı terfi: aşamalı kopya bunlara
    # bağlıdır (manifest sırası ile aynı).
    "R/utils_path_reservation.R",
    "R/helpers_files_promote_probe.R",
    "R/helpers_files_promote_target.R",
    "R/helpers_files_staging_copy.R",
    "R/helpers_files_copy_promote.R",
    "R/helpers_files.R",
    "R/helpers_file_ingestion_task.R",
    "R/helpers_file_ingestion_identity.R",
    "R/helpers_file_ingestion_worker.R",
    "R/helpers_file_ingestion_queue.R",
    "R/helpers_file_ingestion_sources.R",
    "R/helpers_file_ingestion_runtime.R",
    "R/helpers_file_ingestion_index_worker.R"
  )) {
    source(file.path(kok, dosya), encoding = "UTF-8", local = env)
  }

  env$cat <- function(...) invisible(NULL)
  env$log_warn <- function(...) invisible(NULL)
  env$file_ingestion_reset_state()
  env$tracked_future_promise <- function(task_fn, globals, ...) {
    environment(task_fn) <- list2env(globals, parent = env)
    promises::promise_resolve(task_fn())
  }
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

# Windows'ta iki yol AYNI fiziksel dosyayı gösterse de dize olarak farklı
# olabilir: kalıcı depolama kökü resolve_mcp_base_dir() tarafından bilinçli
# olarak 8.3 kısa yola çevrilir (UNC/Türkçe kök güvenliği), bu yüzden
# copy_to_mcp_base() kısa köklü bir hedef üretir; resolve_uploaded_file() ise
# normalize_mcp_path() üzerinden normalizePath() ile uzun yolu döndürür.
# Bu nedenle dize eşitliği yerine "aynı dosya mı" değişmezi doğrulanır.
.ingestionCanonicalPath <- function(env, path) {
  aday <- as.character(path %||% "")[1]
  if (!nzchar(aday)) return("")

  kanonik <- suppressWarnings(
    tryCatch(
      normalizePath(aday, winslash = "/", mustWork = FALSE),
      error = function(e) aday
    )
  )

  env$normalize_for_path_compare(kanonik)
}

.ingestionShortPath <- function(env, path) {
  aday <- as.character(path %||% "")[1]
  if (!nzchar(aday)) return("")
  if (!exists("safe_windows_short_path", mode = "function", inherits = TRUE)) return("")

  kisa <- tryCatch(
    safe_windows_short_path(aday, must_exist = TRUE),
    error = function(e) ""
  )

  env$normalize_for_path_compare(kisa)
}

.ingestionSamePath <- function(env, a, b) {
  bir <- .ingestionCanonicalPath(env, a)
  iki <- .ingestionCanonicalPath(env, b)

  if (nzchar(bir) && identical(bir, iki)) return(TRUE)

  # normalizePath() 8.3 kısa adı uzun ada çeviremediği Windows kurulumlarında
  # karşılaştırma kısa yol tarafından da denenir (iki yön de aynı dosyayı verir).
  bir_kisa <- .ingestionShortPath(env, a)
  iki_kisa <- .ingestionShortPath(env, b)

  nzchar(bir_kisa) && identical(bir_kisa, iki_kisa)
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
  sonuc_kok <- env$normalize_for_path_compare(sonuc$dest)
  hedef_kok_norm <- env$normalize_for_path_compare(hedef_kok)
  expect_true(startsWith(sonuc_kok, paste0(hedef_kok_norm, "/")))
  expect_true(grepl("user_42", sonuc$dest, fixed = TRUE))
  # Görev bittiğinde çağıranın seçeneği geri yüklenmiş olmalı.
  expect_identical(getOption("mergen.mcp_base_dir"), file.path(tempdir(), "yanlis_kok"))
})

test_that("şerit kilit dizini ana süreçte çözülür; işçi ana süreçle aynı muteksi alır", {
  env <- .ingestionEnv()
  kilitler <- file.path(withr::local_tempdir(), "serit-kilitleri")
  hedef_kok <- withr::local_tempdir()
  withr::local_options(list(mergen.upload_lock_dir = kilitler))
  gorev <- env$file_ingestion_task_snapshot(
    upload = .ingestionUpload("serit.txt"), user_id = "42", max_size_mb = 25L,
    allowed_ext = "txt", batch_id = "b1", storage_base = hedef_kok
  )
  expect_identical(gorev$upload_lock_dir, kilitler)
  # İşçiyi taklit: seçenek taşınmaz, ortamdaki indeks yolu farklıdır.
  withr::local_options(list(mergen.upload_lock_dir = NULL))
  env$MERGEN_INDEX_PATH <- file.path(withr::local_tempdir(), "isci-index.json")
  alinan <- character()
  asil <- env$mergen_upload_lane_lock
  env$mergen_upload_lane_lock <- function(path, ...) {
    alinan <<- c(alinan, env$mergen_upload_mutex_path(path))
    asil(path, ...)
  }
  sonuc <- env$file_ingestion_execute_task(gorev)
  expect_true(sonuc$ok)
  expect_gt(length(alinan), 0L)
  ebeveyn <- withr::with_options(list(mergen.upload_lock_dir = kilitler),
    env$mergen_upload_mutex_path(sonuc$dest))
  expect_true(ebeveyn %in% alinan)
  # Windows'ta dirname() ayıracı '/' yapar; aynı dizin kanonik yolla karşılaştırılır.
  expect_identical(unique(normalizePath(dirname(alinan), winslash = "/")),
    normalizePath(kilitler, winslash = "/"))
  expect_null(getOption("mergen.upload_lock_dir"))
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
  # İndeks kilidi durum ortamı işçiye yalnız boş, yeni bir ortam olarak gider.
  kilit <- paket$.FILE_STORE_LOCK_STATE
  expect_true(is.environment(kilit) && !length(ls(kilit, all.names = TRUE)))
  expect_false(identical(kilit, get0(".FILE_STORE_LOCK_STATE", envir = env)))
  paket$.FILE_STORE_LOCK_STATE <- NULL
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

test_that("indeks yazımı çökerse commit başarısız olur", {
  env <- .ingestionEnv()
  sonuclar <- env$file_ingestion_execute_batch(list(.ingestionTask(env, .ingestionUpload("hata.txt"))))
  env$mergen_index_persisted_files <- function(entries, user_id = NULL) stop("indeks kilidi kirik")

  expect_error(env$file_ingestion_commit_index(sonuclar, "42"), "indeks kilidi kirik")
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

  cozulen_42 <- resolve_uploaded_file("ortak_ad.txt", user_id = "42")
  cozulen_77 <- resolve_uploaded_file("ortak_ad.txt", user_id = "77")

  expect_true(env$path_exists_relaxed(cozulen_42))
  expect_true(env$path_exists_relaxed(cozulen_77))

  expect_true(
    .ingestionSamePath(env, cozulen_42, bir$dest),
    info = sprintf("42 -> cozulen='%s', beklenen='%s'", cozulen_42 %||% "", bir$dest)
  )
  expect_true(
    .ingestionSamePath(env, cozulen_77, iki$dest),
    info = sprintf("77 -> cozulen='%s', beklenen='%s'", cozulen_77 %||% "", iki$dest)
  )
  expect_false(.ingestionSamePath(env, cozulen_42, cozulen_77))
})

# ------------------------------------------------------------------------------
# Sınırlı eşzamanlılık ve kuyruk
# ------------------------------------------------------------------------------

test_that("eşzamanlı parti sayısı yapılandırılan sınırı aşmaz", {
  env <- .ingestionEnv()
  # Ortam değişkeni ayarlıysa R seçeneğinden önceliklidir (bkz.
  # file_ingestion_int_setting()); geliştirici/VM .Renviron dosyasında gerçek
  # bir değer varsa test override'ını sessizce geçersiz kılabilir.
  withr::local_envvar(c(MERGEN_FILE_INGESTION_MAX_CONCURRENT = ""))
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
  # Ortam değişkeni ayarlıysa R seçeneğinden önceliklidir (bkz.
  # file_ingestion_int_setting()); geliştirici/VM .Renviron dosyasında gerçek
  # bir değer varsa test override'ını sessizce geçersiz kılabilir.
  withr::local_envvar(c(MERGEN_FILE_INGESTION_MAX_QUEUE = ""))
  withr::local_options(list(mergen.file_ingestion.max_queue = 2L))

  expect_true(env$file_ingestion_enqueue(list(id = "1", session_token = "t1")))
  expect_true(env$file_ingestion_enqueue(list(id = "2", session_token = "t1")))
  expect_false(env$file_ingestion_enqueue(list(id = "3", session_token = "t1")))
  expect_equal(env$file_ingestion_queue_status()$rejected_total, 1L)
})

test_that("açık oturum iptal çağrısı bekleyen işleri kuyruktan düşürür", {
  env <- .ingestionEnv()

  env$file_ingestion_enqueue(list(id = "1", session_token = "kapanan"))
  env$file_ingestion_enqueue(list(id = "2", session_token = "acik"))
  env$file_ingestion_enqueue(list(id = "3", session_token = "kapanan"))

  expect_equal(env$file_ingestion_cancel_session_jobs("kapanan"), 2L)
  expect_equal(env$file_ingestion_queue_status()$queued_batches, 1L)
})

test_that("kapasite yokken parti kuyruğa alınır, varken hemen başlar", {
  env <- .ingestionEnv()
  # Ortam değişkeni ayarlıysa R seçeneğinden önceliklidir (bkz.
  # file_ingestion_int_setting()); geliştirici/VM .Renviron dosyasında gerçek
  # bir değer varsa test override'ını sessizce geçersiz kılabilir.
  withr::local_envvar(c(MERGEN_FILE_INGESTION_MAX_CONCURRENT = ""))
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

test_that("senkron gönderim hatası bağlı kaynakları ve yuvayı bir kez bırakır", {
  for (move in c(FALSE, TRUE)) {
    env <- .ingestionEnv()
    if (move) env$file.link <- function(...) FALSE
    env$file_ingestion_pool_has_capacity <- function() TRUE
    env$mergen_cancellable_worker_capacity <- function(...) 1L
    upload <- .ingestionUpload("dispatch.txt", "korunan kaynak")
    withr::defer(unlink(upload$datapath))
    captured <- NULL
    env$file_ingestion_run_job <- function(job) {
      captured <<- job
      expect_true(file.exists(job$tasks[[1]]$datapath))
      stop("serileştirme hatası")
    }
    result <- env$file_ingestion_submit_batch(env$file_ingestion_create_controller(),
      list(.ingestionTask(env, upload)), "42", batch_id = basename(tempfile("dispatch-")))
    expect_identical(result$status, "rejected")
    expect_identical(readLines(upload$datapath), "korunan kaynak")
    expect_false(dir.exists(captured$lease$sources))
    expect_true(captured$lease$released)
    expect_identical(env$file_ingestion_queue_status()$queued_batches, 0L)
    expect_identical(env$.file_ingestion_state()$active, 0L)
    expect_identical(env$.file_ingestion_state()$completed_total, 1L)
    expect_false(env$file_ingestion_release_job(captured))
    expect_identical(env$.file_ingestion_state()$completed_total, 1L)
  }
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
  for (i in 1:30) later::run_now(0)

  expect_false(is.null(yazilan))
  expect_identical(yazilan$user_id, "42")
  expect_false(is.null(cagrildi))
  expect_identical(cagrildi$batch_id, "job-1")
  expect_equal(cagrildi$summary$succeeded, 1L)
})

test_that("tarayıcı kapanışı kabul edilmiş yüklemeyi iptal etmez; yalnız UI geri çağrısı susar", {
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
  for (i in 1:30) later::run_now(0)

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
  for (i in 1:30) later::run_now(0)

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
test_that("commit edilmiş yapıt geç iptal ya da geri almayla silinmez", {
  env <- .ingestionEnv()
  result <- env$file_ingestion_execute_task(.ingestionTask(env, .ingestionUpload("iptal_indeks.txt")))
  expect_true(result$ok)
  mergen_index_persisted_files(list(list(path = result$dest, display = result$name)), "42")
  expect_true(.ingestionSamePath(env, resolve_uploaded_file(result$name, "42"), result$dest))
  env$file_ingestion_discard_results(list(result), "42")
  expect_true(file.exists(result$dest))
  expect_true(env$file_ingestion_artifact_owned(result))
  expect_true(.ingestionSamePath(env, resolve_uploaded_file(result$name, "42"), result$dest))
  uncommitted <- env$file_ingestion_execute_task(.ingestionTask(env, .ingestionUpload("iptal_kayitsiz.txt")))
  env$file_ingestion_discard_results(list(uncommitted), "42")
  expect_false(file.exists(uncommitted$dest))
})

test_that("geç indeks commit'i silinmiş kopyayı yeniden kaydetmez", {
  env <- .ingestionEnv()
  result <- env$file_ingestion_execute_task(.ingestionTask(env, .ingestionUpload("silinen.txt")))
  unlink(result$dest)
  commit <- env$file_ingestion_commit_index(list(result), "42")
  expect_length(commit$indexed, 0L)
  expect_null(.load_index()[["42"]][[tolower(result$name)]])
})

test_that("eski geri alma aynı yoldaki yeni kopyayı ve indeksini korur", {
  env <- .ingestionEnv()
  old <- env$file_ingestion_execute_task(.ingestionTask(env, .ingestionUpload("yenilenen.txt")))
  env$file_ingestion_commit_index(list(old), "42")
  unlink(c(old$dest, env$file_ingestion_owner_path(old$dest)))
  writeLines("yeni kullanıcının yüklemesi", old$dest)
  newer <- old
  newer$artifact_id <- env$file_ingestion_claim_artifact(newer$dest)
  env$file_ingestion_commit_index(list(newer), "42")
  env$file_ingestion_discard_results(list(old), "42")
  expect_true(file.exists(newer$dest))
  expect_identical(readLines(newer$dest), "yeni kullanıcının yüklemesi")
  expect_identical(.load_index()[["42"]][[tolower(newer$name)]]$artifact_id, newer$artifact_id)
})

test_that("sahip değişimi kopya veya indeks işçisi tamamlanmadan partiyi geçersiz kılar", {
  env <- .ingestionEnv()
  shiny::testServer(function(input, output, session) NULL, {
    session$userData$user_id <- session$userData$kimlik_sahibi <- 42L
    controller <- env$file_ingestion_create_controller(session)
    result <- env$file_ingestion_execute_task(.ingestionTask(env, .ingestionUpload("ozel.txt")))
    completed <- 0L
    job <- .ingestionJob(env, controller, on_complete = function(...) completed <<- completed + 1L)
    session$userData$user_id <- 77L
    mergen_session_owner_transition(session$userData, 42L, 77L)
    env$file_ingestion_finish_job(job, list(result))
    for (i in 1:30) later::run_now(0)
    expect_identical(completed, 0L)
    expect_false(file.exists(result$dest))
    expect_null(.load_index()[["42"]][[tolower(result$name)]])
  })
})

test_that("commit sonrası metrik hatası partiye ikinci hata veya geri alma üretmez", {
  env <- .ingestionEnv()
  result <- env$file_ingestion_execute_task(.ingestionTask(env, .ingestionUpload("metrik.txt")))
  controller <- env$file_ingestion_create_controller()
  completed <- failed <- 0L
  job <- .ingestionJob(env, controller, on_complete = function(...) completed <<- completed + 1L)
  job$on_failure <- function(...) failed <<- failed + 1L
  env$file_ingestion_try_acquire_slot()
  env$file_ingestion_log_metrics <- function(...) stop("metrik hatası")
  env$file_ingestion_finish_job(job, list(result))
  for (i in 1:30) later::run_now(0)
  expect_identical(completed, 1L)
  expect_identical(failed, 0L)
  expect_true(file.exists(result$dest))
  expect_identical(env$file_ingestion_queue_status()$active_batches, 0L)
  expect_identical(env$file_ingestion_queue_status()$completed_total, 1L)
})

test_that("son geri alma yolu kullanıcı kovasını da temizler", {
  env <- .ingestionEnv()
  result <- env$file_ingestion_execute_task(.ingestionTask(env, .ingestionUpload("son_geri_al.txt")))
  env$worker_monitor_serialize_explicit_task <- function(...) stop("serileştirme hatası")
  finished <- FALSE
  env$file_ingestion_fail_job <- function(...) finished <<- TRUE
  env$file_ingestion_rollback_job(list(user_id = "42", session_token = "test"),
                                   list(result), simpleError("işçi hatası"))
  expect_true(file.exists(result$dest))
  heartbeat <- FALSE
  later::later(function() heartbeat <<- TRUE, delay = 0)
  later::run_now(0)
  expect_true(heartbeat)
  deadline <- Sys.time() + 15
  while (!finished && Sys.time() < deadline) later::run_now(0.05)
  expect_true(finished)
  expect_false(file.exists(result$dest))
  expect_null(.load_index()[["42"]][[tolower(result$name)]])
})

test_that("iptal indeks kilidi hata verince sahiplik doğrulanmadan dosya silmez", {
  env <- .ingestionEnv()
  source_path <- withr::local_tempfile()
  copied <- withr::local_tempfile()
  failed <- withr::local_tempfile()
  file.create(source_path, copied, failed)
  env$.file_store_with_index_lock <- function(...) stop("kilit zaman aşımı")
  results <- list(list(ok = TRUE, dest = copied, source_path = source_path),
                  list(ok = FALSE, dest = failed, source_path = source_path))
  expect_error(env$file_ingestion_discard_results(results, "42"), "kilit zaman aşımı")
  expect_true(file.exists(copied))
  expect_true(file.exists(source_path))
  expect_true(file.exists(failed))
})

test_that("indeks gönderim veya işçi hatası kopyaları bağımsız işçide geri alır", {
  for (failure in c("dispatch", "worker", "write")) {
    env <- .ingestionEnv()
    source(file.path(resolve_repo_root_for_tests(), "R", "helpers_worker_monitor.R"),
           encoding = "UTF-8", local = env)
    source_path <- withr::local_tempfile()
    copied <- withr::local_tempfile()
    marker <- withr::local_tempfile()
    file.create(source_path, copied)
    controller <- env$file_ingestion_create_controller()
    complete <- FALSE
    error_message <- NULL
    job <- .ingestionJob(env, controller, on_complete = function(...) complete <<- TRUE)
    job$on_failure <- function(message, tasks) error_message <<- message
    cleanup_env <- new.env(parent = baseenv())
    cleanup_env$marker <- marker
    cleanup_env$file_ingestion_discard_results <- function(results, user_id) {
      writeLines(as.character(Sys.getpid()), marker)
      for (r in results) if (isTRUE(r$ok) && r$dest != r$source_path) unlink(r$dest)
      invisible(TRUE)
    }
    cleanup_env$file_ingestion_commit_index <- function(...) stop("indeks yazımı hatası")
    env$file_ingestion_worker_globals <- function() as.list(cleanup_env)
    env$tracked_future_promise <- function(task_fn, globals, ...) {
      if (failure == "dispatch") stop("gönderim hatası")
      if (failure == "worker") return(promises::promise_reject(simpleError("işçi hatası")))
      environment(task_fn) <- list2env(globals, parent = baseenv())
      promises::promise(function(resolve, reject) resolve(task_fn()))
    }
    env$file_ingestion_finish_job(job, list(list(ok = TRUE, dest = copied, source_path = source_path)))
    deadline <- Sys.time() + 15
    while (is.null(error_message) && Sys.time() < deadline) later::run_now(0.05)
    expect_false(complete)
    expect_match(error_message, "hatası", fixed = TRUE)
    expect_false(file.exists(copied))
    expect_true(file.exists(source_path))
    expect_false(identical(readLines(marker), as.character(Sys.getpid())))
    expect_identical(env$file_ingestion_queue_status()$active_batches, 0L)
  }
})

test_that("geri alma işçisi gerçek indeks paketiyle kaynak dosyayı korur", {
  env <- .ingestionEnv()
  upload <- .ingestionUpload("geri_al.txt")
  result <- env$file_ingestion_execute_task(.ingestionTask(env, upload))
  expect_true(result$ok)
  error_message <- NULL
  job <- .ingestionJob(env, env$file_ingestion_create_controller())
  job$on_failure <- function(message, tasks) error_message <<- message
  env$tracked_future_promise <- function(...) stop("işçi gönderim hatası")
  env$file_ingestion_finish_job(job, list(result))
  deadline <- Sys.time() + 15
  while (is.null(error_message) && Sys.time() < deadline) later::run_now(0.05)
  expect_match(error_message, "işçi gönderim hatası", fixed = TRUE)
  expect_false(file.exists(result$dest))
  expect_true(file.exists(upload$datapath))
  expect_null(.load_index()[["42"]][[tolower(result$name)]])
})

test_that("geri alma ve kilit hatasında sahiplik kanıtlanamayan hedef korunur", {
  for (failure in c("serialize", "launch", "process")) {
    env <- .ingestionEnv()
    source_path <- withr::local_tempfile()
    copied <- withr::local_tempfile()
    failed <- withr::local_tempfile()
    file.create(source_path, copied, failed)
    finished <- 0L
    reported <- 0L
    env$create_worker_task_id <- function(...) "rollback"
    env$register_worker_task <- function(...) NULL
    env$finish_worker_task <- function(...) finished <<- finished + 1L
    env$file_ingestion_fail_job <- function(...) reported <<- reported + 1L
    env$.file_store_mutate_index <- function(...) stop("UI indeks kilidini beklememeli")
    env$worker_monitor_serialize_explicit_task <- function(...) {
      if (failure == "serialize") stop("serileştirme hatası")
      raw(0)
    }
    testthat::local_mocked_bindings(r_bg = function(...) {
      if (failure == "launch") stop("süreç başlatma hatası")
      list(is_alive = function() FALSE, get_result = function() stop("geri alma süreç hatası"))
    }, .package = "callr")
    testthat::local_mocked_bindings(later = function(func, ...) { func(); NULL }, .package = "later")
    results <- list(list(ok = TRUE, dest = copied, source_path = source_path),
                    list(ok = TRUE, dest = source_path, source_path = source_path),
                    list(ok = FALSE, dest = failed, source_path = source_path))
    env$file_ingestion_rollback_job(list(session_token = "test"), results, simpleError("indeks hatası"))
    expect_true(file.exists(copied))
    expect_true(file.exists(source_path))
    expect_true(file.exists(failed))
    expect_identical(finished, 1L)
    expect_identical(reported, 1L)
  }
})

test_that("geri alma indeksi yeniden yazmaz; commit edilmiş dosya ve marker korunur", {
  env <- .ingestionEnv()
  result <- env$file_ingestion_execute_task(.ingestionTask(env, .ingestionUpload("kayit_hatasi.txt")))
  env$file_ingestion_commit_index(list(result), "42")
  env$.save_index <- function(...) stop("kalıcı indeks yazılamadı")
  expect_no_error(env$file_ingestion_discard_results(list(result), "42"))
  expect_true(file.exists(result$dest))
  expect_true(file.exists(env$file_ingestion_owner_path(result$dest)))
  expect_true(env$file_ingestion_artifact_owned(result))
})

test_that("kimlik yol gösteriminden bağımsızdır ve bayat marker yeniden yüklemeyi engellemez", {
  env <- .ingestionEnv()
  path <- withr::local_tempfile()
  writeLines("eski", path)
  old_id <- env$file_ingestion_claim_artifact(path)
  owner <- readRDS(env$file_ingestion_owner_path(path))
  rownames(owner$identity) <- "farkli/yol"
  saveRDS(owner, env$file_ingestion_owner_path(path))
  expect_true(env$file_ingestion_artifact_owned(list(dest = path, artifact_id = old_id)))
  writeLines("tamamen farklı yeni içerik", path)
  new_id <- env$file_ingestion_claim_artifact(path)
  expect_false(identical(old_id, new_id))
  expect_false(env$file_ingestion_artifact_owned(list(dest = path, artifact_id = old_id)))
  expect_true(env$file_ingestion_artifact_owned(list(dest = path, artifact_id = new_id)))
})

test_that("karışık kimlikli parti NULL kimlik yüzünden tamamlanmayı kaybetmez", {
  env <- .ingestionEnv()
  completed <- NULL
  job <- .ingestionJob(env, env$file_ingestion_create_controller(),
    on_complete = function(results, ctx) completed <<- results)
  results <- list(list(ok = TRUE, name = "eski", artifact_id = NULL),
                  list(ok = TRUE, name = "yeni", artifact_id = "new"))
  env$file_ingestion_apply_commit(job, results, list(indexed = c("eski", "yeni"), committed = "new", ms = 0))
  expect_length(completed, 2L)
  expect_true(completed[[1]]$ok)
  expect_true(completed[[2]]$ok)
})

test_that("kesilen kopyanın günlüğü staging ve hedef sahipliğini birlikte korur", {
  env <- .ingestionEnv()
  source <- withr::local_tempfile()
  target <- withr::local_tempfile()
  staging <- paste0(target, ".mergen-part")
  journal <- withr::local_tempfile()
  file.create(source)
  env$file_ingestion_begin_copy(target, staging, source, list(id = "A", journal = journal))
  writeLines("yarım kopya", staging)
  result <- readRDS(journal)
  expect_false(env$file_ingestion_artifact_owned(result))
  env$file_ingestion_discard_results(list(result), "42")
  expect_false(file.exists(staging))
  expect_false(file.exists(env$file_ingestion_owner_path(target)))
  expect_true(file.exists(source))

  env$file_ingestion_begin_copy(target, staging, source, list(id = "B", journal = journal))
  writeLines("tam kopya", staging)
  env$file_ingestion_prepare_promotion(staging, target, list(id = "B", journal = journal))
  expect_true(file.rename(staging, target))
  env$file_ingestion_claim_artifact(target, id = "B")
  env$file_ingestion_discard_results(list(result), "42")
  expect_identical(readLines(target), "tam kopya")
  expect_false(env$file_ingestion_artifact_owned(result))
  env$file_ingestion_discard_results(list(readRDS(journal)), "42")
  expect_false(file.exists(target))
})

test_that("kopya sonrası sahiplik hatası hedefi geri alma sonucunda tutar", {
  env <- .ingestionEnv()
  task <- .ingestionTask(env, .ingestionUpload("sahiplik_hatasi.txt"))
  task$result_journal <- withr::local_tempfile()
  task$transaction <- list(id = "claim-error", journal = task$result_journal)
  claim <- env$file_ingestion_claim_artifact
  calls <- 0L
  env$file_ingestion_claim_artifact <- function(...) {
    calls <<- calls + 1L
    if (calls == 1L) claim(...) else stop("sahiplik hatası")
  }
  # Kopya yardımcısının tamamladığı talep ikinci kez kilitle istenmez.
  ok <- env$file_ingestion_execute_batch(list(task))[[1]]
  expect_true(ok$ok)
  expect_identical(calls, 1L)
  env$file_ingestion_discard_results(list(ok), "42")
  task <- .ingestionTask(env, .ingestionUpload("sahiplik_hatasi.txt"))
  task$result_journal <- withr::local_tempfile()
  task$transaction <- list(id = "claim-error", journal = task$result_journal)
  env$file_ingestion_claimed_by <- function(...) FALSE
  calls <- 1L
  result <- env$file_ingestion_execute_batch(list(task))[[1]]
  expect_false(result$ok)
  expect_identical(result$code, "claim_failed")
  expect_true(nzchar(result$dest))
  expect_identical(result$artifact_id, "claim-error")
  expect_true(env$file_ingestion_artifact_owned(result))
  env$file_ingestion_discard_results(list(result), "42")
  expect_false(file.exists(result$dest))
  expect_false(file.exists(env$file_ingestion_owner_path(result$dest)))
})


test_that("tamamlanmış işlem rezervasyonu aynı yola yeni yüklemeyi engellemez", {
  env <- .ingestionEnv()
  task <- .ingestionTask(env, .ingestionUpload("yeniden.txt"))
  task$result_journal <- withr::local_tempfile()
  task$transaction <- list(id = "old-copy", journal = task$result_journal)
  old <- env$file_ingestion_execute_batch(list(task))[[1]]
  expect_true(old$ok)
  expect_true(env$file_ingestion_artifact_owned(old))
  unlink(old$dest)
  writeLines("yeni ve farklı içerik", old$dest)
  newer <- old
  newer$artifact_id <- env$file_ingestion_claim_artifact(old$dest)
  expect_true(env$file_ingestion_artifact_owned(newer))
  env$file_ingestion_discard_results(list(old), "42")
  expect_identical(readLines(newer$dest), "yeni ve farklı içerik")
  env$file_ingestion_discard_results(list(newer), "42")
  expect_false(file.exists(newer$dest))
})


test_that("kalıcı kaynak yeniden kullanılınca iptal kaynak sahipliğini devralmaz", {
  env <- .ingestionEnv()
  base <- withr::local_tempdir()
  upload <- .ingestionUpload("mevcut.txt")
  source <- file.path(base, "mevcut.txt")
  expect_true(file.copy(upload$datapath, source))
  upload$datapath <- source
  task <- .ingestionTask(env, upload)
  task$storage_base <- base
  journal <- withr::local_tempfile()
  task$transaction <- list(id = "ödünç", journal = journal)
  result <- env$file_ingestion_execute_task(task)
  expect_true(result$ok)
  expect_true(.ingestionSamePath(env, result$dest, source))
  expect_null(result$artifact_id)
  expect_false(env$file_ingestion_artifact_owned(result))
  expect_true(file.exists(source))
  expect_false(file.exists(env$file_ingestion_owner_path(source)))
  expect_false(file.exists(journal))
})


test_that("alım hata günlüğü çökse bile kapasite ve kuyruk ilerler", {
  env <- .ingestionEnv()
  released <- pumped <- 0L
  env$file_ingestion_release_slot <- function() released <<- released + 1L
  env$file_ingestion_pump <- function() pumped <<- pumped + 1L
  env$file_ingestion_controller_debug <- function(...) stop("günlük hatası")
  job <- list(lease = new.env(parent = emptyenv()), controller = list(active = FALSE))
  expect_error(env$file_ingestion_fail_job(job, simpleError("işçi hatası")), "günlük hatası")
  env$file_ingestion_release_job(job)
  expect_identical(released, 1L)
  expect_identical(pumped, 1L)
})

test_that("rezervasyon yabancı hedefi silmez ve canlı rezervasyon ezilmez", {
  env <- .ingestionEnv()
  source <- withr::local_tempfile()
  target <- withr::local_tempfile()
  staging <- paste0(target, ".mergen-part")
  journal <- withr::local_tempfile()
  writeLines("kaynak", source)
  env$file_ingestion_begin_copy(target, staging, source, list(id = "A", journal = journal))
  expect_error(env$file_ingestion_begin_copy(target, staging, source,
    list(id = "B", journal = withr::local_tempfile())), "başka bir işlem")
  expect_identical(env$file_ingestion_read_owner(target)$id, "A")
  writeLines("yabancı dosya", target)
  writeLines("yarım kopya", staging)
  env$file_ingestion_discard_results(list(readRDS(journal)), "42")
  expect_identical(readLines(target), "yabancı dosya")
  expect_false(file.exists(staging))
})

test_that("aynı kullanıcı ve isimde eşzamanlı planlar iki başarılı commit üretmez", {
  env <- .ingestionEnv()
  name <- paste0("aynı_", basename(tempfile()), ".txt")
  first <- env$file_ingestion_execute_task(.ingestionTask(env, .ingestionUpload(name, "birinci")))
  second <- env$file_ingestion_execute_task(.ingestionTask(env, .ingestionUpload(name, "ikinci")))
  expect_true(first$ok)
  expect_true(second$ok)
  # Eşzamanlılık: ikinci işlem, birincinin talebinden ÖNCE rezervasyon yapmıştır.
  Sys.setFileTime(env$file_ingestion_owner_path(second$dest), Sys.time() - 60)
  a <- env$file_ingestion_commit_index(list(first), "42")
  b <- env$file_ingestion_commit_index(list(second), "42")
  expect_identical(a$committed, first$artifact_id)
  expect_length(b$committed, 0L)
  env$file_ingestion_discard_results(list(second), "42")
  expect_true(file.exists(first$dest))
  expect_false(file.exists(second$dest))
  expect_identical(.load_index()[["42"]][[tolower(name)]]$artifact_id, first$artifact_id)
})

test_that("yavaş silme global indeks kilidinin dışında çalışır", {
  env <- .ingestionEnv()
  result <- env$file_ingestion_execute_task(.ingestionTask(env, .ingestionUpload("kilit_dışı.txt")))
  original <- env$file_ingestion_discard_dest
  observed <- FALSE
  env$file_ingestion_discard_dest <- function(...) {
    observed <<- TRUE
    expect_false(dir.exists(paste0(MERGEN_INDEX_PATH, ".lock")))
    original(...)
  }
  env$file_ingestion_discard_results(list(result), "42")
  expect_true(observed)
  expect_false(file.exists(result$dest))
})

test_that("native aday kopyadan önce günlüğe ve rezervasyona bağlanır", {
  env <- .ingestionEnv()
  old <- withr::local_tempfile()
  native <- withr::local_tempfile()
  journal <- withr::local_tempfile()
  tx <- list(id = "native", journal = journal)
  env$file_ingestion_begin_copy(old, paste0(old, ".mergen-part"), "kaynak", tx)
  env$file_ingestion_begin_copy(native, paste0(native, ".mergen-part"), "kaynak", tx)
  expect_identical(readRDS(journal)$dest, native)
  expect_identical(env$file_ingestion_read_owner(native)$id, "native")
  expect_false(file.exists(env$file_ingestion_owner_path(old)))
  writeLines("yarım", paste0(native, ".mergen-part"))
  env$file_ingestion_discard_results(list(readRDS(journal)), "42")
  expect_false(file.exists(paste0(native, ".mergen-part")))
})


test_that("bilinmeyen rollback durumu yeni yıkıcı işçi başlatmaz", {
  env <- .ingestionEnv()
  source(file.path(resolve_repo_root_for_tests(), "R/helpers_worker_cancellation.R"),
         encoding = "UTF-8", local = env)
  callbacks <- list()
  schedule <- function(func, ...) { callbacks[[length(callbacks) + 1L]] <<- func; function() NULL }
  env$mergen_cancellable_worker_schedule <- schedule
  testthat::local_mocked_bindings(later = schedule, .package = "later")
  alive <- NA
  launches <- 0L
  finished <- 0L
  env$create_worker_task_id <- function(...) "rollback"
  env$register_worker_task <- env$finish_worker_task <- function(...) NULL
  env$file_ingestion_fail_job <- function(...) finished <<- finished + 1L
  env$file_ingestion_worker_globals <- function(...) list()
  env$worker_monitor_serialize_explicit_task <- function(...) raw()
  testthat::local_mocked_bindings(r_bg = function(...) {
    launches <<- launches + 1L
    list(is_alive = function() alive, kill_tree = function(...) NULL,
      kill = function(...) NULL, get_result = function() NULL)
  }, .package = "callr")
  next_callback <- function() { f <- callbacks[[1L]]; callbacks <<- callbacks[-1L]; f() }
  env$file_ingestion_rollback_job(list(session_token = "test"), list(), simpleError("hata"))
  for (i in 1:4) next_callback()
  expect_identical(launches, 1L)
  expect_identical(finished, 0L)
  alive <- FALSE
  next_callback()
  expect_identical(launches, 1L)
  next_callback()
  expect_identical(launches, 2L)
  next_callback()
  expect_identical(finished, 1L)
})

test_that("yedek terfi sırasında yaşa dayalı devralma yeni hedefi ezdiremez", {
  env <- .ingestionEnv()
  root <- withr::local_tempdir()
  staging <- file.path(root, "staging")
  dest <- file.path(root, "hedef")
  writeLines("ilk yazar", staging)
  held <- character()
  entered <- FALSE
  env$file.link <- function(...) FALSE
  env$mergen_lock_owner_reclaimable <- function(...) TRUE
  env$mergen_reclaim_mutex <- function(path, ...) {
    if (path %in% held) return(NULL)
    held <<- c(held, path)
    path
  }
  testthat::local_mocked_bindings(unlock = function(lock, ...) held <<- setdiff(held, lock), .package = "filelock")
  env$file.rename <- function(from, to) {
    if (identical(from, staging)) {
      entered <<- env$mergen_reservation_takeover(paste0(dest, env$MERGEN_PROMOTE_RESERVATION_SUFFIX),
        "2147483646-yeni", stale_sec = -1)
      if (entered) writeLines("yeni yazar", dest)
    }
    base::file.rename(from, to)
  }
  result <- env$mergen_promote_staged_file(staging, dest, file.exists)
  expect_true(result$ok)
  expect_false(entered)
  expect_identical(readLines(dest), "ilk yazar")
  expect_length(held, 0L)
})

test_that("silinen ilk staging başarısı başarısız native kopyaya taşınmaz", {
  env <- .ingestionEnv()
  staging <- withr::local_tempfile()
  native <- paste0(staging, "-native")
  env$enc2native <- function(path) if (identical(path, staging)) native else path
  testthat::local_mocked_bindings(file_copy = function(...) stop("yedek"), .package = "fs")
  env$file.copy <- function(from, to, ...) {
    if (!identical(to, staging)) return(FALSE)
    writeLines("ilk kopya", to)
    TRUE
  }
  result <- env$mergen_stage_upload_copy("kaynak", "hedef", staging,
    file.exists, function(...) FALSE, function(path) unlink(path), rebind = function(...) NULL)
  expect_false(result$ok)
  expect_false(file.exists(result$staging))
})

test_that("native kopya başladığında günlük yeni staging sahibini taşır", {
  env <- .ingestionEnv()
  old <- withr::local_tempfile()
  native <- withr::local_tempfile()
  journal <- withr::local_tempfile()
  source <- withr::local_tempfile()
  tx <- list(id = "native-copy", journal = journal)
  env$file_ingestion_begin_copy(old, paste0(old, ".mergen-part"), source, tx)
  env$enc2native <- function(path) sub(old, native, path, fixed = TRUE)
  testthat::local_mocked_bindings(file_copy = function(...) stop("native gerekli"), .package = "fs")
  copied <- FALSE
  env$file.copy <- function(from, to, ...) {
    if (!identical(to, paste0(native, ".mergen-part"))) return(FALSE)
    expect_identical(readRDS(journal)$dest, native)
    expect_identical(readRDS(journal)$staging, to)
    expect_identical(env$file_ingestion_read_owner(native)$id, tx$id)
    expect_false(file.exists(env$file_ingestion_owner_path(old)))
    copied <<- TRUE
    writeLines("yarım", to)
    stop("iptal")
  }
  env$mergen_stage_upload_copy(source, old, paste0(old, ".mergen-part"),
    file.exists, file.exists, function(path) NULL,
    rebind = function(dest, stage) env$file_ingestion_begin_copy(dest, stage, source, tx))
  expect_true(copied)
  expect_true(file.exists(paste0(native, ".mergen-part")))
  env$file_ingestion_discard_results(list(readRDS(journal)), "42")
  expect_false(file.exists(paste0(native, ".mergen-part")))
})

test_that("sahiplik gevşek UNC varlık sözleşmesini korur", {
  env <- .ingestionEnv()
  result <- env$file_ingestion_execute_task(.ingestionTask(env, .ingestionUpload("unc-sahiplik.txt")))
  expect_true(result$ok)
  env$file.exists <- function(path) if (identical(path, result$dest)) FALSE else base::file.exists(path)
  expect_false(env$file.exists(result$dest))
  expect_true(env$path_exists_relaxed(result$dest))
  expect_true(env$file_ingestion_artifact_owned(result))
  env$file_ingestion_discard_results(list(result), "42")
  expect_false(base::file.exists(result$dest))
})


test_that("alım kuyruğu çalışan partinin kapasitesini bozmadan zaman aşımına uğrar", {
  env <- .ingestionEnv()
  withr::local_envvar(c(MERGEN_FILE_INGESTION_QUEUE_TIMEOUT = ""))
  withr::local_options(list(mergen.file_ingestion.queue_timeout = 300L))
  controller <- env$file_ingestion_create_controller()
  failed <- 0L
  job <- .ingestionJob(env, controller)
  job$queued_at <- Sys.time() - 301
  job$on_failure <- function(message, ...) { expect_match(message, "kuyrukta zaman aşımı"); failed <<- failed + 1L }
  job$lease <- new.env(); job$lease$released <- FALSE
  queue_state <- env$.file_ingestion_state()
  queue_state$active <- 2L
  env$file_ingestion_enqueue(job)
  env$file_ingestion_pump()
  expect_identical(failed, 1L)
  expect_identical(env$file_ingestion_queue_status()$active_batches, 2L)
  expect_identical(env$file_ingestion_queue_status()$queued_batches, 0L)
})

test_that("işlemli terfi kimliği kaybettiren kopya yedeğine dönmez", {
  env <- .ingestionEnv()
  root <- withr::local_tempdir()
  src <- file.path(root, "src.txt"); dest <- file.path(root, "dest.txt")
  writeLines("kopya", src)
  tx <- list(id = "promotion", journal = withr::local_tempfile())
  copy_called <- FALSE
  env$file.link <- env$file.rename <- function(...) FALSE
  env$file.copy <- function(...) { copy_called <<- TRUE; FALSE }
  expect_error(env$mergen_copy_upload_staged(src, dest, root, transaction = tx), "kalıcı ada taşınamadı")
  expect_false(copy_called)
  expect_false(file.exists(dest))
  expect_false(file.exists(paste0(dest, ".mergen-part")))
  env$file_ingestion_discard_results(list(readRDS(tx$journal)), "42")
  expect_false(file.exists(env$file_ingestion_owner_path(dest)))
})

test_that("aynı boyut ve zaman damgası farklı fiziksel dosyaya sahiplik vermez", {
  env <- .ingestionEnv()
  result <- env$file_ingestion_execute_task(.ingestionTask(env, .ingestionUpload("fiziksel-kimlik.txt")))
  old_identity <- env$file_ingestion_file_identity(result$dest)
  replacement <- tempfile(tmpdir = dirname(result$dest))
  writeLines("yabancı dosya", replacement)
  unlink(result$dest)
  expect_true(file.rename(replacement, result$dest))
  original <- env$file_ingestion_file_identity
  env$file_ingestion_file_identity <- function(path) {
    info <- original(path)
    if (is.character(path) && identical(path, result$dest)) {
      info$size <- old_identity$size; info$mtime <- old_identity$mtime; info$ctime <- old_identity$ctime
    }
    info
  }
  expect_false(env$file_ingestion_artifact_owned(result))
  env$file_ingestion_discard_results(list(result), "42")
  expect_identical(readLines(result$dest), "yabancı dosya")
})


test_that("terfi ile claim arasındaki yabancı hedef rezervasyonla sahiplenilemez", {
  env <- .ingestionEnv()
  task <- .ingestionTask(env, .ingestionUpload("terfi_yarisi.txt"))
  task$result_journal <- withr::local_tempfile()
  task$transaction <- list(id = "promotion-race", journal = task$result_journal)
  promote <- env$mergen_promote_staged_file
  replaced <- FALSE
  env$mergen_promote_staged_file <- function(...) {
    args <- list(...)
    result <- promote(...)
    if (isTRUE(result$promoted)) {
      expect_true(file.rename(args$hedef, paste0(args$hedef, ".held")))
      writeLines("yabancı dosya", args$hedef)
      replaced <<- TRUE
    }
    result
  }
  result <- env$file_ingestion_execute_batch(list(task))[[1]]
  pending <- readRDS(task$result_journal)
  expect_true(replaced)
  expect_false(result$ok)
  # Terfi sonrası talep kopya yardımcısında hata üretmez (UNC gecikmesi); yabancı
  # içerik doğrulamada yakalanır ve sahiplik kanıtlanmaz.
  expect_identical(result$code, "size_mismatch")
  expect_false(env$file_ingestion_artifact_owned(pending))
  env$file_ingestion_discard_results(list(pending), "42")
  expect_identical(readLines(pending$dest), "yabancı dosya")
  expect_false(file.exists(env$file_ingestion_owner_path(pending$dest)))
})

test_that("eksik dosya kimliği sahiplik veya silme kanıtı sayılmaz", {
  env <- .ingestionEnv()
  path <- withr::local_tempfile()
  writeLines("korunacak dosya", path)
  info <- file.info(path)[c("size", "mtime", "ctime")]
  info$size <- NA_real_
  expect_false(env$file_ingestion_identity_matches(info, info))
  identity <- env$file_ingestion_file_identity(path)
  attr(identity, "file_key") <- NULL
  env$file_ingestion_file_identity <- function(...) identity
  expect_error(env$file_ingestion_claim_artifact(path), "sahipliği doğrulanamadı")
  expect_false(file.exists(env$file_ingestion_owner_path(path)))
  expect_identical(readLines(path), "korunacak dosya")
})

test_that("iptal edilen çalışan parti ayrıntısız terminal UI temizliği alır", {
  for (path in c("discard", "failure", "commit")) {
    env <- .ingestionEnv()
    controller <- env$file_ingestion_create_controller()
    calls <- list()
    job <- .ingestionJob(env, controller)
    job$tasks <- list(list(name = "önceki sahibin dosyası"))
    job$on_failure <- function(message, tasks) calls[[length(calls) + 1L]] <<- list(message, tasks)
    cleared <- character()
    controller$clear_notification <- function(id) cleared <<- c(cleared, id)
    controller$epoch <- controller$epoch + 1L
    if (path == "discard") env$file_ingestion_finish_job(job, list())
    if (path == "failure") env$file_ingestion_fail_job(job, simpleError("özel hata"))
    if (path == "commit") env$file_ingestion_apply_commit(job, list(), list(indexed = character(), ms = 0))
    for (i in 1:30) later::run_now(0)
    expected <- if (path == "commit") list() else list(list("Dosya alımı iptal edildi.", list()))
    expect_identical(calls, expected, info = path)
    expect_identical(cleared, if (path == "commit") job$id else character(), info = path)
  }
})

test_that("başarısız kardeşin temizlik hatası sağlam dosyanın commit edilmesini engellemez", {
  env <- .ingestionEnv()
  kept <- env$file_ingestion_execute_task(.ingestionTask(env, .ingestionUpload("saglam.txt")))
  failed <- list(ok = FALSE, dest = "bekleyen", artifact_id = "failed")
  env$file_ingestion_discard_results <- function(...) stop("UNC kopyası henüz görünmüyor")
  rolled_back <- FALSE
  cleanup <- NULL
  env$file_ingestion_rollback_job <- function(job, results, error, journals, on_complete = NULL) {
    if (is.null(on_complete)) rolled_back <<- TRUE else {
      cleanup <<- results
      on_complete(FALSE, error)
    }
  }
  job <- .ingestionJob(env, env$file_ingestion_create_controller())
  env$file_ingestion_finish_job(job, list(kept, failed))
  for (i in 1:30) later::run_now(0)
  expect_false(rolled_back)
  expect_identical(cleanup[[1]]$artifact_id, failed$artifact_id)
  expect_true(file.exists(kept$dest))
  expect_identical(.load_index()[["42"]][[tolower(kept$name)]]$artifact_id, kept$artifact_id)
})

test_that("commit edilen yapıt, reddedilen kardeşin temizlik hatasında geri alınmaz", {
  env <- .ingestionEnv()
  kept <- env$file_ingestion_execute_task(.ingestionTask(env, .ingestionUpload("kabul.txt")))
  declined <- env$file_ingestion_execute_task(.ingestionTask(env, .ingestionUpload("ret.txt")))
  real_index <- get("mergen_index_persisted_files", envir = env)
  env$mergen_index_persisted_files <- function(entries, user_id = NULL) {
    result <- real_index(entries[1], user_id = user_id)
    attr(result, "accepted") <- seq_along(entries) == 1L
    result
  }
  real_discard <- env$file_ingestion_discard_results
  env$file_ingestion_discard_results <- function(results, ...) {
    if (any(vapply(results, function(r) identical(r$artifact_id, declined$artifact_id), logical(1))))
      stop("Sahip olunan kopya silinemedi.")
    real_discard(results, ...)
  }
  cleanup <- NULL
  env$file_ingestion_rollback_job <- function(job, results, error, journals, on_complete) {
    cleanup <<- results
    on_complete(FALSE, error)
  }
  completed <- failed <- 0L
  job <- .ingestionJob(env, env$file_ingestion_create_controller(),
                       on_complete = function(...) completed <<- completed + 1L)
  job$on_failure <- function(...) failed <<- failed + 1L
  env$file_ingestion_finish_job(job, list(kept, declined))
  for (i in 1:30) later::run_now(0)
  expect_identical(completed, 1L)
  expect_identical(failed, 0L)
  expect_identical(cleanup[[1]]$artifact_id, declined$artifact_id)
  expect_true(file.exists(kept$dest))
  expect_identical(.load_index()[["42"]][[tolower(kept$name)]]$artifact_id, kept$artifact_id)
})

test_that("terfi edilip henüz görünmeyen hedefin sahipliği geri almada bırakılmaz", {
  env <- .ingestionEnv()
  root <- withr::local_tempdir()
  dest <- file.path(root, "unc.txt")
  tx <- list(id = "unc-gecikme", journal = withr::local_tempfile())
  staging <- paste0(dest, ".mergen-part")
  env$file_ingestion_begin_copy(dest, staging, "kaynak", tx)
  writeLines("terfi", staging)
  env$file_ingestion_prepare_promotion(staging, dest, tx)
  file.rename(staging, dest)
  pending <- readRDS(tx$journal)
  gorunur <- FALSE
  # UNC görünürlük gecikmesi: hedef ne varlık ne de fiziksel kimlik yoklamasında görünür.
  env$path_exists_relaxed <- function(path) if (identical(path, dest)) gorunur && file.exists(path) else file.exists(path)
  real_key <- env$file_ingestion_physical_identity
  env$file_ingestion_physical_identity <- function(path) if (identical(path, dest) && !gorunur) NULL else real_key(path)
  expect_error(env$file_ingestion_discard_results(list(pending), "42"), "sahiplik korunuyor")
  expect_true(file.exists(env$file_ingestion_owner_path(dest)))
  gorunur <- TRUE
  env$file_ingestion_discard_results(list(pending), "42")
  expect_false(file.exists(dest))
  expect_false(file.exists(env$file_ingestion_owner_path(dest)))
})

test_that("okunamayan ya da ölü sahipli rezervasyon yalnız ortak kuralla geri kazanılır", {
  env <- .ingestionEnv()
  root <- withr::local_tempdir()
  dest <- file.path(root, "rezerv.txt")
  staging <- paste0(dest, ".mergen-part")
  marker <- env$file_ingestion_owner_path(dest)
  writeBin(as.raw(c(0x58, 0x0a, 0x00)), marker)
  tx <- list(id = "yeni", journal = withr::local_tempfile())
  expect_error(env$file_ingestion_begin_copy(dest, staging, "kaynak", tx), "ayrılmış")
  Sys.setFileTime(marker, Sys.time() - 7200)
  expect_no_error(env$file_ingestion_begin_copy(dest, staging, "kaynak", tx))
  expect_identical(env$file_ingestion_read_owner(dest)$id, "yeni")
  saveRDS(list(id = "olu", state = "copying", staging = staging, pid = 2147483647L,
               host = unname(Sys.info()[["nodename"]])), marker)
  writeLines("yarım kopya", staging)
  tx2 <- list(id = "sonraki", journal = withr::local_tempfile())
  env$file_ingestion_prepare_promotion(staging, dest, list(id = "olu"))
  expect_no_error(env$file_ingestion_begin_copy(dest, staging, "kaynak", tx2))
  expect_false(file.exists(staging))
  writeLines("var olan", dest)
  saveRDS(list(id = "olu", state = "copying", staging = staging, pid = 2147483647L,
               host = unname(Sys.info()[["nodename"]])), marker)
  expect_error(env$file_ingestion_begin_copy(dest, staging, "kaynak", list(id = "x", journal = tempfile())),
               "zaten var")
  expect_identical(readLines(dest), "var olan")
})

test_that("terfisi hiç başlamamış ölü sahibin güncel staging'i kanıtsız geri kazanılır; çelişkide korunur", {
  env <- .ingestionEnv()
  root <- withr::local_tempdir()
  dest <- file.path(root, "yarim.txt")
  staging <- env$mergen_upload_staging_path(dest)
  marker <- env$file_ingestion_owner_path(dest)
  olu <- function(staging_kaydi = staging, pid = 2147483647L) {
    writeLines("yarım kopya", staging)
    saveRDS(list(id = "olu", state = "copying", staging = staging_kaydi, pid = pid,
                 host = unname(Sys.info()[["nodename"]])), marker)
  }
  deneme <- function(id) list(id = id, journal = withr::local_tempfile())
  # Canlı sahip: staging ve rezervasyon korunur.
  olu(pid = Sys.getpid())
  expect_error(env$file_ingestion_begin_copy(dest, staging, "kaynak", deneme("canli")), "ayrılmış")
  expect_identical(readLines(staging), "yarım kopya")
  # Okunamayan terfi kanıtı belirsizdir; staging korunur.
  olu()
  writeBin(as.raw(c(0x00, 0x01)), paste0(marker, ".identity"))
  expect_error(env$file_ingestion_begin_copy(dest, staging, "kaynak", deneme("bozuk")), "doğrulanamadı")
  expect_identical(readLines(staging), "yarım kopya")
  unlink(paste0(marker, ".identity"))
  # İndeks talebi olan staging silinmez.
  env$.load_index <- function() list("42" = list(x = list(path = staging)))
  expect_error(env$file_ingestion_begin_copy(dest, staging, "kaynak", deneme("indeksli")), "doğrulanamadı")
  expect_identical(readLines(staging), "yarım kopya")
  env$.load_index <- function() list()
  # Staging'in kendi sahip marker'ı varsa silinmez.
  env$file_ingestion_write_owner(list(id = "baska", state = "claimed"), env$file_ingestion_owner_path(staging))
  expect_error(env$file_ingestion_begin_copy(dest, staging, "kaynak", deneme("sahipli")), "doğrulanamadı")
  expect_identical(readLines(staging), "yarım kopya")
  unlink(env$file_ingestion_owner_path(staging))
  # Birebir terk edilmiş güncel staging: yeniden deneme kalıcı olarak engellenmez.
  olu()
  expect_no_error(env$file_ingestion_begin_copy(dest, staging, "kaynak", deneme("sonraki")))
  expect_false(file.exists(staging))
  expect_identical(env$file_ingestion_read_owner(dest)$id, "sonraki")
})

test_that("ardışık yeniden yükleme eski kaydı değiştirir; kimliksiz yazım canlı yapıtı ezmez", {
  env <- .ingestionEnv()
  name <- paste0("tekrar_", basename(tempfile()), ".txt")
  first <- env$file_ingestion_execute_task(.ingestionTask(env, .ingestionUpload(name, "ilk")))
  env$file_ingestion_commit_index(list(first), "42")
  Sys.sleep(1.1)
  second <- env$file_ingestion_execute_task(.ingestionTask(env, .ingestionUpload(name, "ikinci sürüm")))
  b <- env$file_ingestion_commit_index(list(second), "42")
  expect_identical(b$committed, second$artifact_id)
  expect_identical(.load_index()[["42"]][[tolower(name)]]$artifact_id, second$artifact_id)
  expect_true(file.exists(first$dest))
  other <- withr::local_tempfile(fileext = ".txt")
  writeLines("kimliksiz", other)
  mergen_index_persisted_files(list(list(path = other, display = name)), "42")
  expect_identical(.load_index()[["42"]][[tolower(name)]]$artifact_id, second$artifact_id)
  idx <- .load_index(); idx[["42"]][[tolower(name)]] <- other; .save_index(idx)
  third <- env$file_ingestion_execute_task(.ingestionTask(env, .ingestionUpload(name, "üçüncü")))
  env$file_ingestion_commit_index(list(third), "42")
  expect_identical(.load_index()[["42"]][[tolower(name)]]$artifact_id, third$artifact_id)
})

test_that("tarayıcı kapanışı kabul edilen kuyruk kaynağını ve commit yolunu korur", {
  env <- .ingestionEnv()
  available <- new.env(); available$ready <- FALSE
  env$file_ingestion_pool_has_capacity <- function() available$ready
  upload <- .ingestionUpload("kuyruk_kapandi.txt", "kalıcı kuyruk içeriği")
  notified <- FALSE
  shiny::testServer(function(input, output, session) NULL, {
    controller <- env$file_ingestion_create_controller(session)
    state <- env$.file_ingestion_state()
    status <- env$file_ingestion_submit_batch(controller, list(.ingestionTask(env, upload)), "42",
      on_complete = function(...) notified <<- TRUE)
    expect_identical(status$status, "queued")
    job <- state$pending[[1]]
    owned_source <- job$tasks[[1]]$datapath
    expect_false(identical(owned_source, upload$datapath))
    unlink(upload$datapath)
    epoch <- controller$epoch
    session$close()
    expect_identical(controller$epoch, epoch)
    expect_false(isTRUE(controller$active))
    expect_identical(state$pending[[1]]$id, job$id)
    expect_identical(readLines(owned_source), "kalıcı kuyruk içeriği")
    available$ready <- TRUE
    env$file_ingestion_pump()
    for (i in 1:30) later::run_now(0)
    expect_false(notified)
    expect_identical(state$active, 0L)
    expect_length(state$pending, 0L)
    expect_false(file.exists(owned_source))
    node <- .load_index()[["42"]][[tolower(upload$name)]]
    expect_identical(readLines(node$path), "kalıcı kuyruk içeriği")
  })
})

test_that("kimliği okunamayan terfi edilmiş hedef sahipliğini korur, kardeş temizliği sürer", {
  env <- .ingestionEnv()
  source <- withr::local_tempfile()
  writeLines("kaynak", source)
  hazirla <- function(id) {
    target <- withr::local_tempfile(.local_envir = parent.frame(2))
    staging <- paste0(target, ".mergen-part")
    journal <- withr::local_tempfile(.local_envir = parent.frame(2))
    txn <- list(id = id, journal = journal)
    env$file_ingestion_begin_copy(target, staging, source, txn)
    writeLines("kopya", staging)
    list(target = target, staging = staging, txn = txn)
  }
  terfi <- hazirla("terfi")
  env$file_ingestion_prepare_promotion(terfi$staging, terfi$target, terfi$txn)
  expect_true(file.rename(terfi$staging, terfi$target))
  kardes <- hazirla("kardes")
  # Terfi sonrası hedef kimliği (UNC/izin) okunamaz: yapıt bizim de yabancı da olabilir.
  env$file_ingestion_physical_identity <- function(path) NULL
  expect_error(env$file_ingestion_discard_results(
    list(readRDS(terfi$txn$journal), readRDS(kardes$txn$journal)), "42"), "sahiplik korunuyor")
  expect_identical(readLines(terfi$target), "kopya")
  expect_true(file.exists(env$file_ingestion_owner_path(terfi$target)))
  expect_true(file.exists(paste0(env$file_ingestion_owner_path(terfi$target), ".identity")))
  # İlk yapıtın hatası kardeşin ara kopyasının ve işaretlerinin temizliğini durdurmaz.
  expect_false(file.exists(kardes$staging))
  expect_false(file.exists(env$file_ingestion_owner_path(kardes$target)))
})

test_that("indeks işçisi commit öncesi nesil iptalini izler, temizlik koşusu iptal edilmez", {
  env <- .ingestionEnv()
  controller <- env$file_ingestion_create_controller()
  checks <- list()
  env$tracked_future_promise <- function(task_fn, cancel_check, ...) {
    checks[[length(checks) + 1L]] <<- cancel_check
    promises::promise(function(resolve, reject) NULL)
  }
  job <- .ingestionJob(env, controller)
  env$file_ingestion_finish_job(job, list())
  expect_true(checks[[1]]())
  env$file_ingestion_cancel_controller(controller)
  expect_false(checks[[1]]())
  env$file_ingestion_finish_job(job, list())
  expect_true(checks[[2]]())
})

test_that("alım partisi taze callr işçisinde indeks kilidiyle uçtan uca tamamlanır", {
  skip_if_not_installed("callr")
  env <- .ingestionEnv()
  gercek <- new.env(parent = env)
  for (dosya in c("helpers_worker_cancellation.R", "helpers_worker_monitor.R"))
    source(file.path(resolve_repo_root_for_tests(), "R", dosya), encoding = "UTF-8", local = gercek)
  task <- .ingestionTask(env, .ingestionUpload("callr_alim.txt", "taze işçi içeriği"))
  task$result_journal <- withr::local_tempfile()
  task$transaction <- list(id = basename(task$result_journal), journal = task$result_journal)
  globals <- env$file_ingestion_worker_globals(refresh = TRUE)
  globals$tasks <- list(task)
  sonuc <- hata <- NULL
  p <- gercek$tracked_future_promise(task_fn = function() file_ingestion_execute_batch(tasks),
    task_type = "file_ingestion", cancel_check = function() TRUE, dependency_mode = "explicit",
    globals = globals, packages = c("fs", "digest"))
  promises::then(p, function(value) sonuc <<- value, function(e) hata <<- e)
  deadline <- Sys.time() + 60
  while (is.null(sonuc) && is.null(hata) && Sys.time() < deadline) later::run_now(0.05)
  expect_null(hata)
  expect_true(isTRUE(sonuc[[1]]$ok))
  expect_identical(readLines(sonuc[[1]]$dest), "taze işçi içeriği")
  expect_true(env$file_ingestion_artifact_owned(sonuc[[1]]))
})

test_that("kabul edilen alım, oturum geçici yüklemeyi silse de kaynağına ulaşır", {
  env <- .ingestionEnv()
  upload <- .ingestionUpload("oturum_kapandi.txt", "kapanıştan sonra da korunur")
  controller <- env$file_ingestion_create_controller()
  sonuclar <- NULL
  icsel <- env$tracked_future_promise
  env$tracked_future_promise <- function(task_fn, globals, ..., task_type = "generic") {
    # Tarayıcı kapanışı: Shiny oturumun geçici yükleme dosyasını siler.
    if (identical(task_type, "file_ingestion")) unlink(upload$datapath)
    icsel(task_fn, globals, ..., task_type = task_type)
  }
  durum <- env$file_ingestion_submit_batch(controller, list(.ingestionTask(env, upload)), "42",
    on_complete = function(results, ...) sonuclar <<- results, batch_id = "kapanis-b1")
  for (i in 1:30) later::run_now(0)
  expect_identical(durum$status, "started")
  expect_false(file.exists(upload$datapath))
  expect_true(isTRUE(sonuclar[[1]]$ok))
  expect_identical(readLines(sonuclar[[1]]$dest), "kapanıştan sonra da korunur")
  expect_false(dir.exists(file.path(tempdir(), "mergen_ingest_sources", "kapanis-b1")))
})


test_that("kuyruktaki senkron başlangıç hatası işe ait kaynakları tam bir kez bırakır", {
  env <- .ingestionEnv()
  env$file_ingestion_pool_has_capacity <- function() TRUE
  sources <- withr::local_tempdir()
  writeLines("yükleme", file.path(sources, "1"))
  lease <- new.env(); lease$released <- FALSE
  job <- .ingestionJob(env, env$file_ingestion_create_controller())
  job$lease <- lease
  job$run <- function(job) { job$lease$sources <- sources; stop("serileştirme") }
  failures <- 0L
  job$on_failure <- function(...) failures <<- failures + 1L
  env$file_ingestion_enqueue(job)
  env$file_ingestion_pump()
  expect_false(dir.exists(sources))
  expect_identical(failures, 1L)
  expect_identical(env$file_ingestion_queue_status()$active_batches, 0L)
  expect_identical(env$file_ingestion_queue_status()$completed_total, 1L)
})

test_that("kimliksiz aynı kaynak kaydının reddi başarı olarak sunulmaz", {
  env <- .ingestionEnv()
  winner <- env$file_ingestion_execute_task(.ingestionTask(env, .ingestionUpload("kimliksiz_cakisma.txt")))
  env$file_ingestion_commit_index(list(winner), "42")
  other <- .ingestionUpload("kimliksiz_cakisma.txt")$datapath
  result <- list(ok = TRUE, dest = other, name = winner$name, artifact_id = NULL)
  index_result <- env$file_ingestion_commit_index(list(result), "42")
  received <- NULL
  job <- .ingestionJob(env, env$file_ingestion_create_controller(), on_complete = function(results, ...) received <<- results)
  env$file_ingestion_apply_commit(job, list(result), index_result)
  expect_false(received[[1]]$ok)
  expect_identical(received[[1]]$code, "index_declined")
  expect_identical(.load_index()[["42"]][[tolower(winner$name)]]$artifact_id, winner$artifact_id)
  expect_true(file.exists(winner$dest))
})


test_that("terfi sahipliği geçici okuma hatasından sonra doğrulanır, belirsizlikte silme yetkisi vermez", {
  for (mode in c("transient", "unreadable", "foreign")) {
    env <- .ingestionEnv()
    root <- withr::local_tempdir()
    stage <- file.path(root, "stage")
    dest <- file.path(root, "target")
    writeLines("yükleme", stage)
    env$file.link <- function(...) FALSE
    original <- env$mergen_reservation_owner
    reads <- 0L
    env$mergen_reservation_owner <- function(path) {
      reads <<- reads + 1L
      if (reads > 1L && mode == "unreadable") return(NA_character_)
      if (reads == 2L && mode == "transient") return(NA_character_)
      if (reads > 1L && mode == "foreign") return("baska-sahip")
      original(path)
    }
    result <- env$mergen_promote_staged_file(stage, dest, file.exists)
    expect_identical(result$promoted, mode == "transient", info = mode)
    if (mode != "transient") expect_true(result$yabanci, info = mode)
  }
})

test_that("tek fiziksel işçide alım kabul edilir ve commit sonrası yuvasını bırakır", {
  withr::local_options(mergen.cancellable_workers = 1L)
  env <- .ingestionEnv()
  completed <- NULL
  result <- env$file_ingestion_submit_batch(env$file_ingestion_create_controller(),
    list(.ingestionTask(env, .ingestionUpload("tek_isci.txt"))), "42",
    on_complete = function(results, ...) completed <<- results)
  expect_identical(result$status, "started")
  for (i in 1:30) later::run_now(0)
  expect_true(completed[[1]]$ok)
  expect_identical(env$file_ingestion_queue_status()$queued_batches, 0L)
  expect_identical(env$file_ingestion_queue_status()$active_batches, 0L)
})

test_that("terfi sahipliği kaybolduktan sonra beliren yabancı hedef silinmez", {
  env <- .ingestionEnv()
  root <- withr::local_tempdir()
  source <- file.path(root, "source.txt")
  target <- file.path(root, "target.txt")
  writeLines("yükleme", source)
  env$file.link <- function(...) FALSE
  owner <- env$mergen_reservation_owner
  reads <- 0L
  env$mergen_reservation_owner <- function(path) {
    reads <<- reads + 1L
    if (reads > 1L) "baska-sahip" else owner(path)
  }
  promote <- env$mergen_promote_staged_file
  env$mergen_promote_staged_file <- function(...) {
    result <- promote(...)
    writeLines(enc2utf8("başka yüklemenin dosyası"), target, useBytes = TRUE)
    result
  }
  expect_error(env$mergen_copy_upload_staged(source, target, root), "kalıcı ada taşınamadı")
  expect_identical(readLines(target, encoding = "UTF-8"), "başka yüklemenin dosyası")
})

test_that("geç commit, kendisinden önce başlayan eşzamanlı yüklemeyi korur", {
  env <- .ingestionEnv()
  a <- env$file_ingestion_execute_task(.ingestionTask(env, .ingestionUpload("commit_yarisi.txt", "A")))
  b <- env$file_ingestion_execute_task(.ingestionTask(env, .ingestionUpload("commit_yarisi.txt", "B")))
  expect_true(env$file_ingestion_commit_index(list(a), "42")$accepted[[1]])
  expect_false(env$file_ingestion_commit_index(list(b), "42")$accepted[[1]])
  node <- .load_index()[["42"]][[tolower(a$name)]]
  expect_identical(node$artifact_id, a$artifact_id)
  expect_true(is.finite(node$committed_at))
  # Ardışık yükleme hâlâ önceki kalıcı kaydı değiştirebilir.
  c <- env$file_ingestion_execute_task(.ingestionTask(env, .ingestionUpload("commit_yarisi.txt", "C")))
  expect_true(env$file_ingestion_commit_index(list(c), "42")$accepted[[1]])
})

test_that("aynı yolun kimliksiz yeniden kaydı canlı yapıt kimliğini korur", {
  env <- .ingestionEnv()
  result <- env$file_ingestion_execute_task(.ingestionTask(env, .ingestionUpload("yeniden_kayit.txt")))
  env$file_ingestion_commit_index(list(result), "42")
  before <- .load_index()[["42"]][[tolower(result$name)]]
  repeated <- result; repeated$artifact_id <- NULL
  expect_true(env$file_ingestion_commit_index(list(repeated), "42")$accepted[[1]])
  after <- .load_index()[["42"]][[tolower(result$name)]]
  expect_identical(after$artifact_id, before$artifact_id)
  expect_identical(after$committed_at, before$committed_at)
})

test_that("uzun hedef adı sahiplik ve geçici marker sınırını aşmaz", {
  env <- .ingestionEnv()
  root <- withr::local_tempdir()
  source <- withr::local_tempfile()
  writeLines("uzun ad", source)
  long_target <- file.path(root, paste0(strrep("a", 250), ".txt"))
  stage <- env$mergen_upload_staging_path(long_target)
  expect_lt(nchar(basename(stage), type = "bytes"), 80L)
  expect_identical(dirname(stage), dirname(long_target))
  expect_false(identical(stage, env$mergen_upload_staging_path(sub("a.txt$", "b.txt", long_target))))
  marker <- env$file_ingestion_owner_path(long_target)
  expect_lt(nchar(basename(paste0(marker, ".identity.", Sys.getpid(), ".tmp")), type = "bytes"), 255L)
  # 181 bayt sıkıştırma eşiğini (180) aşar; derin Windows geçici kökünde de temsil edilir.
  target <- file.path(root, paste0(strrep("a", 177), ".txt"))
  usable <- isTRUE(suppressWarnings(file.create(target)))
  skip_if(!usable && .Platform$OS.type == "windows" && env$mergen_artifact_path_units(target) > 259L,
    "Host cannot represent this final-path fixture without Windows long-path support")
  expect_true(usable)
  unlink(target)
  stage <- env$mergen_upload_staging_path(target)
  tx <- list(id = "uzun-ad", journal = withr::local_tempfile())
  env$file_ingestion_begin_copy(target, stage, source, tx)
  expect_true(file.copy(source, stage))
  env$file_ingestion_prepare_promotion(stage, target, tx)
  expect_true(file.rename(stage, target))
  env$file_ingestion_claim_artifact(target, id = tx$id)
  result <- list(ok = TRUE, dest = target, source_path = source, artifact_id = tx$id, name = basename(target))
  expect_true(env$file_ingestion_artifact_owned(result))
  marker <- env$file_ingestion_owner_path(target)
  expect_lt(nchar(basename(paste0(marker, ".identity.", Sys.getpid(), ".tmp")), type = "bytes"), 255)
  env$file_ingestion_discard_results(list(result), "42")
  expect_false(file.exists(target))
  expect_false(file.exists(marker))
  expect_false(file.exists(paste0(marker, ".identity")))
})

test_that("kısa staging uzun ad ve ebeveynde baytları korur; olanaksız ad erken reddedilir", {
  env <- .ingestionEnv()
  root <- withr::local_tempdir()
  source <- withr::local_tempfile()
  bytes <- as.raw(c(0, 255, 195, 40, 10))
  writeBin(bytes, source)
  for (name in c("kisa.bin", paste0(strrep("a", 250), ".bin"))) {
    target <- file.path(root, name)
    expect_lt(nchar(basename(env$mergen_upload_staging_path(target)), type = "bytes"), 255L)
  }
  before <- list.files(root, all.files = TRUE)
  tx <- list(id = "unsupported", journal = withr::local_tempfile())
  expect_error(env$mergen_copy_upload_staged(source, file.path(root, strrep("x", 256)), root,
    transaction = tx), "dosya sistemi sınırını")
  expect_identical(list.files(root, all.files = TRUE), before)
  expect_false(file.exists(tx$journal))
  env$.Platform <- list(OS.type = "windows")
  expect_error(env$mergen_upload_staging_path(file.path(root, paste0(strrep("a", 254), "ö"))), NA)
  expect_error(env$mergen_upload_staging_path(file.path(root, strrep(intToUtf8(0x1f600), 128))),
    "dosya sistemi sınırını")
  long <- file.path(root, paste0(strrep("a", 220), ".txt"))
  expect_identical(basename(env$mergen_upload_staging_path(long)),
    basename(env$mergen_upload_staging_path(toupper(long))))
  native <- iconv(paste0(strrep("Ö", 100), ".txt"), from = "UTF-8", to = "latin1")
  expected <- basename(env$mergen_upload_staging_path(enc2utf8(native)))
  env$tolower <- function(value) {
    expect_identical(Encoding(value), "UTF-8")
    base::tolower(value)
  }
  expect_identical(basename(env$mergen_upload_staging_path(native)), expected)
  rm("tolower", envir = env)
  encoded_parent <- iconv(paste0("//server/share/", strrep("Ö", 90)), "UTF-8", "latin1")
  alias <- file.path(encoded_parent, paste0(strrep("n", 40), ".txt"))
  expect_identical(basename(env$mergen_upload_staging_path(alias)),
    basename(env$mergen_upload_staging_path(enc2utf8(alias))))
  parent <- paste0("//server/share/", strrep("p", 185))
  stage <- env$mergen_upload_staging_path(file.path(parent, paste0(strrep("n", 40), ".txt")))
  expect_identical(env$normalize_for_path_compare(dirname(stage)), env$normalize_for_path_compare(parent))
  expect_true(startsWith(chartr("\\", "/", stage), "//server/share/"))
  expect_lte(nchar(stage, type = "bytes"), 240L)
  deep <- paste0("//server/share/", strrep("p", 210))
  for (name in c("a.txt", paste0(strrep("Ö", 17), ".txt"))) {
    target <- file.path(deep, name)
    original <- paste0(target, env$MERGEN_UPLOAD_STAGING_SUFFIX)
    stage <- env$mergen_upload_staging_path(target)
    expect_lte(env$mergen_artifact_path_units(original), 260L)
    expect_identical(stage, original)
    expect_lte(env$mergen_artifact_path_units(stage), env$mergen_artifact_path_units(original))
  }
})

test_that("eski staging kanıtsız silinmez; güncel staging devri fail-closed kalır", {
  env <- .ingestionEnv()
  root <- withr::local_tempdir()
  source <- withr::local_tempfile()
  writeLines("kaynak", source)
  width <- 100L
  target <- file.path(root, paste0(strrep("ö", width), ".txt"))
  old_stage <- paste0(target, ".mergen-part")
  stage <- env$mergen_upload_staging_path(target)
  expect_false(identical(old_stage, stage))
  usable <- isTRUE(suppressWarnings(file.create(old_stage)))
  skip_if(!usable && .Platform$OS.type == "windows" && env$mergen_artifact_path_units(old_stage) > 259L,
    "Host cannot represent the legacy staging fixture under this temporary root")
  expect_true(usable)
  tx <- list(id = "new-stage", journal = withr::local_tempfile())
  marker <- env$file_ingestion_owner_path(target)
  env$file_ingestion_write_owner(list(id = "old-stage", staging = old_stage), marker)
  writeLines("eski", old_stage)
  env$file_ingestion_owner_reclaimable <- function(...) FALSE
  expect_error(env$file_ingestion_begin_copy(target, stage, source, tx), "başka bir işlem")
  expect_true(file.exists(old_stage))
  env$file_ingestion_owner_reclaimable <- function(...) TRUE
  env$file_ingestion_begin_copy(target, stage, source, tx)
  expect_true(file.exists(old_stage))
  expect_identical(env$file_ingestion_read_owner(target)$id, tx$id)
  expect_true(file.exists(tx$journal))
  # Eski ad artık başka yüklemenin sahipliği kanıtlı kalıcı dosyasıdır.
  writeLines(enc2utf8("başka yüklemenin dosyası"), old_stage, useBytes = TRUE)
  other_id <- env$file_ingestion_claim_artifact(old_stage)
  env$file_ingestion_write_owner(list(id = "old-stage", state = "copying", staging = old_stage), marker)
  env$file_ingestion_begin_copy(target, stage, source, tx)
  expect_true(env$file_ingestion_artifact_owned(list(dest = old_stage, artifact_id = other_id)))
  expect_identical(readLines(old_stage, encoding = "UTF-8"), "başka yüklemenin dosyası")
  # Güncel iç staging adı için önceki, sahiplikli temizleme yolu korunur.
  env$file_ingestion_write_owner(list(id = "old-stage", state = "copying", staging = stage), marker)
  writeLines("yarım", stage)
  env$file_ingestion_prepare_promotion(stage, target, list(id = "old-stage"))
  unlink(tx$journal)
  env$unlink <- function(...) 1L
  expect_error(env$file_ingestion_begin_copy(target, stage, source, tx), "staging temizlenemedi")
  expect_identical(env$file_ingestion_read_owner(target)$id, "old-stage")
  expect_false(file.exists(tx$journal))
  env$unlink <- base::unlink
  env$file_ingestion_begin_copy(target, stage, source, tx)
  expect_false(file.exists(stage))
  expect_true(env$file_ingestion_artifact_owned(list(dest = old_stage, artifact_id = other_id)))
  expect_identical(env$file_ingestion_read_owner(target)$staging, stage)
  # Marker içindeki keyfi bir yol hiçbir zaman silme yetkisi değildir.
  foreign <- file.path(root, "kullanici.txt")
  writeLines("koru", foreign)
  env$file_ingestion_write_owner(list(id = "foreign", staging = foreign), marker)
  env$file_ingestion_begin_copy(target, stage, source, tx)
  expect_true(file.exists(foreign))
})

for (width in c(235L, 245L, 255L)) test_that(paste("bağlantısız terfi kalıcı adı korur:", width), {
  env <- .ingestionEnv()
  root <- withr::local_tempdir()
  source <- withr::local_tempfile()
  bytes <- as.raw(c(0, 255, 195, 40))
  writeBin(bytes, source)
  env$file.link <- function(...) FALSE
  target <- file.path(root, strrep("a", width))
  reservation <- env$mergen_upload_artifact_path(target, env$MERGEN_PROMOTE_RESERVATION_SUFFIX,
    component_only = TRUE)
  expect_lte(env$mergen_artifact_path_units(basename(reservation)), 255L)
  quarantine <- env$mergen_reservation_quarantine_path(reservation, unique = FALSE)
  expect_lte(env$mergen_artifact_path_units(basename(quarantine)), 255L)
  usable <- isTRUE(suppressWarnings(file.create(target)))
  skip_if(!usable && .Platform$OS.type == "windows" && env$mergen_artifact_path_units(target) > 259L,
    "Host cannot represent this final-path fixture without Windows long-path support")
  expect_true(usable)
  unlink(target)
  tx <- list(id = paste0("long-", width), journal = withr::local_tempfile())
  expect_identical(env$mergen_copy_upload_staged(source, target, root, transaction = tx), target)
  expect_identical(readBin(target, "raw", 100L), bytes)
  expect_true(env$file_ingestion_artifact_owned(list(dest = target, artifact_id = tx$id)))
  expect_false(dir.exists(reservation))
  result <- list(ok = TRUE, dest = target, source_path = source, artifact_id = tx$id, name = basename(target))
  env$file_ingestion_discard_results(list(result), "42")
  expect_false(file.exists(target))
  expect_false(file.exists(env$mergen_upload_staging_path(target)))
  expect_false(file.exists(env$file_ingestion_owner_path(target)))
})

test_that("geçerli kısa rezervasyon kimlikleri değişmez", {
  env <- .ingestionEnv()
  for (windows in c(FALSE, TRUE)) {
    env$.Platform <- list(OS.type = if (windows) "windows" else "unix")
    root <- if (windows) "C:/r" else "/r"
    for (name in c("short.txt", strrep("a", if (windows) 235L else 244L))) {
      short <- file.path(root, name)
      expect_identical(env$mergen_upload_artifact_path(short, env$MERGEN_PROMOTE_RESERVATION_SUFFIX,
        component_only = TRUE), paste0(short, env$MERGEN_PROMOTE_RESERVATION_SUFFIX))
    }
  }
})

test_that("reddedilen kardeşin temizliği tamamlanana dek günlükler ve başarılı commit korunur", {
  env <- .ingestionEnv()
  kept <- env$file_ingestion_execute_task(.ingestionTask(env, .ingestionUpload("kalici_kardes.txt")))
  declined <- env$file_ingestion_execute_task(.ingestionTask(env, .ingestionUpload("gecici_ret.txt")))
  real_index <- get("mergen_index_persisted_files", envir = env)
  env$mergen_index_persisted_files <- function(entries, user_id) {
    indexed <- real_index(entries[1], user_id)
    attr(indexed, "accepted") <- c(TRUE, FALSE)
    indexed
  }
  real_discard <- env$file_ingestion_discard_results
  env$file_ingestion_discard_results <- function(...) stop("geçici silme hatası")
  journals <- c(withr::local_tempfile(), withr::local_tempfile())
  saveRDS(kept, journals[1]); saveRDS(declined, journals[2])
  pending <- done <- NULL
  env$file_ingestion_rollback_job <- function(job, results, error, journals, on_complete) {
    pending <<- results; done <<- on_complete
    expect_true(all(file.exists(journals)))
  }
  completed <- 0L
  job <- .ingestionJob(env, env$file_ingestion_create_controller(),
    on_complete = function(...) completed <<- completed + 1L)
  env$file_ingestion_finish_job(job, list(kept, declined), journals = journals)
  for (i in 1:30) later::run_now(0)
  expect_identical(completed, 0L)
  expect_identical(pending[[1]]$artifact_id, declined$artifact_id)
  expect_identical(.load_index()[["42"]][[tolower(kept$name)]]$artifact_id, kept$artifact_id)
  expect_true(all(file.exists(journals)))
  real_discard(pending, "42")
  unlink(journals)
  done(TRUE, NULL)
  expect_identical(completed, 1L)
  expect_false(file.exists(declined$dest))
  expect_false(any(file.exists(journals)))
  expect_true(file.exists(kept$dest))
})

test_that("farklı yüklemeler ayrı yayın muteksini kullanır ve listeye sızmaz", {
  env <- .ingestionEnv()
  root <- withr::local_tempdir()
  env$file.link <- function(...) FALSE
  # Şerit anahtarı rastgele geçici kökü içerir; ayrı şeride düşen ikinci ad seçilir.
  lane <- function(name) env$mergen_upload_mutex_path(file.path(root, name))
  adlar <- c("bir.txt", Find(function(n) !identical(lane(n), lane("bir.txt")), c("iki.txt", "uc.txt", "dort.txt")))
  for (name in adlar) {
    stage <- file.path(root, paste0(name, ".mergen-part"))
    writeLines(name, stage)
    result <- env$mergen_promote_staged_file(stage, file.path(root, name), file.exists)
    expect_true(result$ok)
  }
  # Kilide benzeyen kullanıcı adları görünür kalır; şerit kilitleri kovada oluşmaz.
  documents <- c("rapor.mergen-rsv.reclaim", ".up-abc", ".up-0123456789abcdef", "lane-abc.lock")
  for (document in documents) writeLines("kullanıcı belgesi", file.path(root, document))
  files <- list.files(root, all.files = TRUE, no.. = TRUE, full.names = TRUE)
  guards <- vapply(adlar, lane, character(1))
  expect_length(unique(guards), 2L)
  expect_true(all(file.exists(guards)))
  expect_false(any(env$normalize_for_path_compare(dirname(guards)) ==
    env$normalize_for_path_compare(normalizePath(root, winslash = "/"))))
  expect_setequal(basename(files), c(adlar, documents, ".mergen-rsv.reclaim"))
  expect_setequal(basename(.file_store_drop_upload_artifacts(files)), c(adlar, documents))
})

test_that("dizin muteksi çekişmesi başka hedefin terfi ve devralmasını hemen reddetmez", {
  skip_if_not_installed("callr")
  skip_if_not_installed("filelock")
  for (stale in c(FALSE, TRUE)) local({
  root <- withr::local_tempdir()
  guard <- filelock::lock(file.path(root, ".mergen-rsv.reclaim"), timeout = 0)
  withr::defer(if (!is.null(guard)) filelock::unlock(guard))
  stage <- file.path(root, "stage"); writeLines("çıktı", stage)
  if (stale) {
    reservation <- file.path(root, "dest.mergen-rsv")
    dir.create(reservation)
    writeLines(c("2147483647-dead", paste0("host=", Sys.info()[["nodename"]])),
      file.path(reservation, "owner"))
  }
  child <- callr::r_bg(function(repo, root) {
    env <- new.env(parent = globalenv())
    for (file in c("helpers_process_ownership.R", "utils_path_reservation.R",
                   "helpers_files_promote_probe.R", "helpers_files_promote_target.R"))
      source(file.path(repo, "R", file), encoding = "UTF-8", local = env)
    env$file.link <- function(...) FALSE
    # İşaret yalnız devralma korumasında yazılır; önce alınan şerit kilidi
    # işareti erken yazıp beklemeyi kanıtlanmış gösteremez.
    env$mergen_reclaim_mutex <- function(path, timeout = 0, exclusive = TRUE) {
      if (identical(basename(path), ".mergen-rsv.reclaim"))
        writeLines("bekliyor", file.path(root, "waiting"))
      filelock::lock(path, timeout = timeout, exclusive = exclusive)
    }
    env$mergen_promote_staged_file(file.path(root, "stage"), file.path(root, "dest"), file.exists)
  }, args = list(repo = resolve_repo_root_for_tests(), root = root))
  withr::defer(try(child$kill(), silent = TRUE))
  deadline <- Sys.time() + 20
  while (!file.exists(file.path(root, "waiting")) && child$is_alive() && Sys.time() < deadline)
    child$poll_io(50)
  expect_true(file.exists(file.path(root, "waiting")))
  child$poll_io(100)
  expect_true(child$is_alive())
  expect_false(file.exists(file.path(root, "dest")))
  filelock::unlock(guard); guard <- NULL
  child$wait(timeout = 10000)
  expect_true(child$get_result()$ok)
  expect_identical(readLines(file.path(root, "dest")), "çıktı")
  })
})

test_that("paylaşım marker saati uygulama saatinden sapınca commit sırası değişmez", {
  env <- .ingestionEnv()
  for (skew in c(-7200, 7200)) {
    name <- paste0("saat_", skew, ".txt")
    a <- env$file_ingestion_execute_task(.ingestionTask(env, .ingestionUpload(name, "A")))
    b <- env$file_ingestion_execute_task(.ingestionTask(env, .ingestionUpload(name, "B")))
    for (r in list(a, b)) Sys.setFileTime(env$file_ingestion_owner_path(r$dest), Sys.time() + skew)
    expect_true(env$file_ingestion_commit_index(list(a), "42")$accepted[[1]])
    expect_false(env$file_ingestion_commit_index(list(b), "42")$accepted[[1]])
    c <- env$file_ingestion_execute_task(.ingestionTask(env, .ingestionUpload(name, "C")))
    Sys.setFileTime(env$file_ingestion_owner_path(c$dest), Sys.time() + skew)
    expect_true(env$file_ingestion_commit_index(list(c), "42")$accepted[[1]])
  }
})

test_that("aynı partide son geçerli eş adlı kopya kazanır ve önceki kopya temizlenir", {
  env <- .ingestionEnv()
  a <- env$file_ingestion_execute_task(.ingestionTask(env, .ingestionUpload("parti_tekrar.txt", "A")))
  b <- env$file_ingestion_execute_task(.ingestionTask(env, .ingestionUpload("parti_tekrar.txt", "B")))
  received <- NULL
  job <- .ingestionJob(env, env$file_ingestion_create_controller(),
    on_complete = function(results, ...) received <<- results)
  env$file_ingestion_finish_job(job, list(a, b))
  for (i in 1:30) later::run_now(0)
  expect_false(received[[1]]$ok)
  expect_true(received[[2]]$ok)
  expect_false(file.exists(a$dest))
  expect_true(file.exists(b$dest))
  expect_identical(.load_index()[["42"]][[tolower(b$name)]]$artifact_id, b$artifact_id)
})

test_that("aynı partinin kimliksiz farklı yolu canlı yapıtı silemez", {
  env <- .ingestionEnv()
  owned <- env$file_ingestion_execute_task(.ingestionTask(env, .ingestionUpload("parti_kimliksiz.txt")))
  idless <- list(ok = TRUE, dest = owned$source_path, name = owned$name, artifact_id = NULL)
  result <- env$file_ingestion_commit_index(list(owned, idless), "42")
  expect_identical(result$accepted, c(TRUE, FALSE))
  expect_identical(.load_index()[["42"]][[tolower(owned$name)]]$artifact_id, owned$artifact_id)
  expect_true(file.exists(owned$dest))
})

test_that("native yeniden bağlama ilk başlangıcı korur ve aradaki commit'i ezmez", {
  env <- .ingestionEnv()
  a <- env$file_ingestion_execute_task(.ingestionTask(env, .ingestionUpload("native_yaris.txt", "A")))
  root <- withr::local_tempdir()
  old <- file.path(root, "old.txt"); native <- file.path(root, "native.txt")
  source <- withr::local_tempfile(); writeLines("B", source)
  tx <- list(id = "native-ilk", journal = withr::local_tempfile())
  stage <- paste0(old, ".mergen-part"); native_stage <- paste0(native, ".mergen-part")
  env$file_ingestion_begin_copy(old, stage, source, tx)
  started <- env$file_ingestion_read_owner(old)$started_at
  env$enc2native <- function(path) sub(old, native, path, fixed = TRUE)
  testthat::local_mocked_bindings(file_copy = function(...) stop("native gerekli"), .package = "fs")
  env$file.copy <- function(from, to, ...) {
    if (identical(to, stage)) {
      expect_true(env$file_ingestion_commit_index(list(a), "42")$accepted[[1]])
      return(FALSE)
    }
    base::file.copy(from, to, ...)
  }
  copied <- env$mergen_stage_upload_copy(source, old, stage, file.exists, file.exists,
    function(path) unlink(path), rebind = function(dest, stage)
      env$file_ingestion_begin_copy(dest, stage, source, tx))
  expect_true(copied$ok)
  expect_identical(env$file_ingestion_read_owner(native)$started_at, started)
  expect_identical(readRDS(tx$journal)$started_at, started)
  env$file_ingestion_prepare_promotion(native_stage, native, tx)
  expect_true(file.rename(native_stage, native))
  env$file_ingestion_claim_artifact(native, id = tx$id)
  b <- list(ok = TRUE, dest = native, name = a$name, artifact_id = tx$id)
  expect_false(env$file_ingestion_commit_index(list(b), "42")$accepted[[1]])
  expect_identical(.load_index()[["42"]][[tolower(a$name)]]$artifact_id, a$artifact_id)
  expect_true(file.exists(a$dest))
})

test_that("sahiplik ve günlük mevcut hedefi değiştirir, hata eski kanıtı korur", {
  env <- .ingestionEnv()
  target <- withr::local_tempfile()
  env$file_ingestion_write_owner(list(id = "A", state = "claimed"), target)
  env$file_ingestion_write_owner(list(id = "A", state = "deleting"), target)
  expect_identical(readRDS(target)$state, "deleting")
  env$file_ingestion_write_owner(list(artifact_id = "A", dest = "native"), target)
  expect_identical(readRDS(target)$dest, "native")
  before <- readBin(target, "raw", n = file.info(target)$size)
  testthat::local_mocked_bindings(file_move = function(...) stop("paylaşım ihlali"), .package = "fs")
  expect_error(env$file_ingestion_write_owner(list(id = "B"), target), "Sahiplik işareti")
  expect_identical(readBin(target, "raw", n = file.info(target)$size), before)
  expect_false(any(startsWith(basename(list.files(dirname(target), all.files = TRUE)), ".io-")))
})

test_that("kuyruk varsayılanı kalıcı bütçeyi korur; iptal, red ve süre kaynakları bırakır", {
  env <- .ingestionEnv()
  withr::local_envvar(c(MERGEN_FILE_INGESTION_QUEUE_TIMEOUT = "", MERGEN_FILE_INGESTION_MAX_QUEUE = ""))
  withr::local_options(list(mergen.file_ingestion.queue_timeout = NULL, mergen.file_ingestion.max_queue = 1L))
  env$file_ingestion_pool_has_capacity <- function() FALSE
  controller <- env$file_ingestion_create_controller()
  submit <- function() env$file_ingestion_submit_batch(controller,
    list(.ingestionTask(env, .ingestionUpload("bekleyen.txt"))), "42")
  expect_identical(submit()$status, "queued")
  state <- env$.file_ingestion_state()
  sources <- state$pending[[1]]$lease$sources
  state$pending[[1]]$queued_at <- Sys.time() - 600
  env$file_ingestion_pump()
  expect_length(state$pending, 1L)
  expect_true(dir.exists(sources))
  before <- list.dirs(file.path(tempdir(), "mergen_ingest_sources"), recursive = FALSE)
  expect_identical(submit()$status, "rejected")
  expect_setequal(list.dirs(file.path(tempdir(), "mergen_ingest_sources"), recursive = FALSE), before)
  env$file_ingestion_cancel_controller(controller)
  expect_false(dir.exists(sources))
  expect_identical(state$active, 0L)
  expect_identical(submit()$status, "queued")
  sources <- state$pending[[1]]$lease$sources
  state$pending[[1]]$queued_at <- Sys.time() - 1801
  state$active <- 2L
  env$file_ingestion_pump()
  expect_length(state$pending, 0L)
  expect_false(dir.exists(sources))
  expect_identical(state$active, 2L)
  # Bağ desteklenmezse kaynak atomik taşınarak yine işe ait kalır.
  env$file.link <- function(...) FALSE
  expect_identical(submit()$status, "queued")
  expect_length(state$pending, 1L)
  expect_true(file.exists(state$pending[[1]]$tasks[[1]]$datapath))
  expect_identical(state$active, 2L)
  env$file_ingestion_cancel_controller(controller)
  expect_length(state$pending, 0L)
})

test_that("görünürlük bekleyişi dizin muteksini başka terfilerden saklamaz", {
  skip_if_not_installed("callr")
  skip_if_not_installed("filelock")
  env <- .ingestionEnv()
  root <- withr::local_tempdir()
  stage <- file.path(root, "stage"); writeLines("çıktı", stage)
  env$file.link <- function(...) FALSE
  env$mergen_promote_wait_visible <- function(...) {
    child <- callr::r_bg(function(path) {
      guard <- filelock::lock(path, timeout = 0)
      if (is.null(guard)) return(FALSE)
      filelock::unlock(guard)
      TRUE
    }, args = list(path = file.path(root, ".mergen-rsv.reclaim")))
    on.exit(try(child$kill(), silent = TRUE), add = TRUE)
    child$wait(timeout = 10000)
    expect_true(child$get_result())
    TRUE
  }
  expect_true(env$mergen_promote_staged_file(stage, file.path(root, "dest"), file.exists)$ok)
  expect_false(dir.exists(file.path(root, "dest.mergen-rsv")))
})

test_that("iki gerçek indeks işçisi eşzamanlı eş adlı yüklemeye tek kabul verir", {
  skip_if_not_installed("callr")
  env <- .ingestionEnv()
  name <- paste0("yarış_", basename(tempfile()), ".txt")
  results <- lapply(c("A", "B"), function(content)
    env$file_ingestion_execute_task(.ingestionTask(env, .ingestionUpload(name, content))))
  expect_true(all(vapply(results, function(r) isTRUE(r$ok), logical(1))))
  root <- withr::local_tempdir()
  index_options <- options()[intersect(names(options()),
    c("mergen.mcp_base_dir", "mergen.index_path", "mergen.files_root"))]
  children <- lapply(seq_along(results), function(i) {
    globals <- env$file_ingestion_worker_globals(refresh = TRUE)
    globals$results <- list(results[[i]])
    globals$user_id <- "42"
    task <- function() {
      result <- file_ingestion_commit_index(results, user_id)
      if (!isTRUE(result$accepted[[1]])) file_ingestion_discard_results(results, user_id)
      result
    }
    payload <- worker_monitor_serialize_explicit_task(task, globals, c("fs", "digest", "jsonlite"))
    callr::r_bg(function(payload, settings, root, i) {
      options(settings)
      task <- unserialize(payload)
      list2env(as.list(environment(task), all.names = TRUE), envir = globalenv())
      writeLines("hazır", file.path(root, paste0("ready-", i)))
      deadline <- Sys.time() + 20
      while (!file.exists(file.path(root, "go")) && Sys.time() < deadline) Sys.sleep(0.01)
      if (!file.exists(file.path(root, "go"))) stop("test bariyeri açılmadı")
      task()
    }, args = list(payload = payload, settings = index_options, root = root, i = i))
  })
  withr::defer(lapply(children, function(child) try(child$kill(), silent = TRUE)))
  deadline <- Sys.time() + 20
  while (length(list.files(root, pattern = "^ready-")) < 2L && Sys.time() < deadline)
    children[[1]]$poll_io(50)
  expect_length(list.files(root, pattern = "^ready-"), 2L)
  writeLines("başla", file.path(root, "go"))
  commits <- lapply(children, function(child) { child$wait(timeout = 15000); child$get_result() })
  accepted <- vapply(commits, function(r) isTRUE(r$accepted[[1]]), logical(1))
  expect_identical(sum(accepted), 1L)
  winner <- results[[which(accepted)]]
  loser <- results[[which(!accepted)]]
  expect_identical(.load_index()[["42"]][[tolower(name)]]$artifact_id, winner$artifact_id)
  expect_true(file.exists(winner$dest))
  expect_false(file.exists(loser$dest))
  env$file_ingestion_discard_results(list(winner), "42")
  expect_true(file.exists(winner$dest))
  next_result <- env$file_ingestion_execute_task(.ingestionTask(env, .ingestionUpload(name, "sonraki")))
  expect_true(env$file_ingestion_commit_index(list(next_result), "42")$accepted[[1]])
})

test_that("bağsız dosya sistemi kaynağı devralır; eksik kardeş yalnız kendi hatasını döner", {
  env <- .ingestionEnv()
  env$mergen_cancellable_worker_capacity <- function(...) 1L
  available <- FALSE
  env$file_ingestion_pool_has_capacity <- function() available
  env$file.link <- function(...) FALSE
  good <- .ingestionUpload("bag_desteksiz.txt", "korunan baytlar")
  missing <- .ingestionUpload("kayip_kardes.txt")
  unlink(missing$datapath)
  logs <- character()
  controller <- env$file_ingestion_create_controller(debug_fn = function(tag, message)
    logs <<- c(logs, tag))
  withr::defer(env$file_ingestion_cancel_controller(controller))
  received <- NULL
  status <- env$file_ingestion_submit_batch(controller,
    list(.ingestionTask(env, good), .ingestionTask(env, missing)), "42",
    on_complete = function(results, ...) received <<- results)
  expect_identical(status$status, "queued")
  job <- env$.file_ingestion_state()$pending[[1]]
  expect_false(file.exists(good$datapath))
  expect_identical(readLines(job$tasks[[1]]$datapath), "korunan baytlar")
  expect_identical(logs, "ingest_source_link_error")
  expect_null(job$tasks[[1]]$source_error)
  expect_match(job$tasks[[2]]$source_error, "geçici kaynağı hazırlanamadı", fixed = TRUE)
  available <- TRUE
  env$file_ingestion_pump()
  for (i in 1:30) later::run_now(0)
  expect_length(received, 2L)
  expect_true(received[[1]]$ok)
  expect_false(received[[2]]$ok)
  expect_identical(received[[2]]$code, "source_unavailable")
  expect_identical(readLines(received[[1]]$dest), "korunan baytlar")
  expect_false(dir.exists(job$lease$sources))
  expect_identical(env$.file_ingestion_state()$active, 0L)
})

test_that("kuyruk reddi bağlantısız kaynağı iade eder; taşıma hatası dosya düzeyinde kalır", {
  env <- .ingestionEnv()
  env$mergen_cancellable_worker_capacity <- function(...) 1L
  env$file_ingestion_pool_has_capacity <- function() FALSE
  env$file.link <- function(...) FALSE
  withr::local_options(list(mergen.file_ingestion.max_queue = 1L))
  withr::local_envvar(c(MERGEN_FILE_INGESTION_MAX_QUEUE = ""))
  controller <- env$file_ingestion_create_controller()
  withr::defer(env$file_ingestion_cancel_controller(controller))
  first <- .ingestionUpload("dolu_ilk.txt")
  second <- .ingestionUpload("dolu_ikinci.txt", "iade")
  expect_identical(env$file_ingestion_submit_batch(controller,
    list(.ingestionTask(env, first)), "42")$status, "queued")
  expect_identical(env$file_ingestion_submit_batch(controller,
    list(.ingestionTask(env, second)), "42")$status, "rejected")
  expect_identical(readLines(second$datapath), "iade")
  env$file_ingestion_cancel_controller(controller)
  env$file.rename <- function(...) FALSE
  expect_identical(env$file_ingestion_submit_batch(controller,
    list(.ingestionTask(env, second)), "42")$status, "queued")
  task <- env$.file_ingestion_state()$pending[[1]]$tasks[[1]]
  expect_identical(env$file_ingestion_execute_task(task)$code, "source_unavailable")
  expect_identical(readLines(second$datapath), "iade")
  env$file_ingestion_cancel_controller(controller)
})

test_that("yavaş kopya kardeş hedefi engellemez ve devralma sahipliği çalamaz", {
  skip_if_not_installed("callr")
  skip_if_not_installed("filelock")
  root <- withr::local_tempdir()
  env <- .ingestionEnv()
  repo <- resolve_repo_root_for_tests()
  worker <- function(repo, root, name, slow) {
    env <- new.env(parent = globalenv())
    for (file in c("helpers_process_ownership.R", "utils_path_reservation.R",
                   "helpers_files_promote_probe.R", "helpers_files_promote_target.R"))
      source(file.path(repo, "R", file), encoding = "UTF-8", local = env)
    stage <- file.path(root, paste0(name, ".stage"))
    writeLines(name, stage)
    env$file.link <- env$file.rename <- function(...) FALSE
    copy_exclusive <- env$.mergen_promote_copy_exclusive
    env$.mergen_promote_copy_exclusive <- function(from, to) {
      if (slow) {
        marker <- file.path(paste0(to, ".mergen-rsv"), "owner")
        writeLines(c(readLines(marker, n = 1L), "host=uzak"), marker)
        Sys.setFileTime(marker, Sys.time() - 120)
        writeLines("kopya", file.path(root, "copying"))
        deadline <- Sys.time() + 30
        while (!file.exists(file.path(root, "release")) && Sys.time() < deadline) Sys.sleep(0.02)
        if (!file.exists(file.path(root, "release"))) stop("kopya kapısı açılmadı")
      }
      copy_exclusive(from, to)
    }
    env$mergen_promote_staged_file(stage, file.path(root, name), file.exists)
  }
  a <- callr::r_bg(worker, args = list(repo = repo, root = root, name = "a.txt", slow = TRUE))
  withr::defer(try(a$kill(), silent = TRUE))
  deadline <- Sys.time() + 15
  while (!file.exists(file.path(root, "copying")) && a$is_alive() && Sys.time() < deadline) a$poll_io(50)
  expect_true(file.exists(file.path(root, "copying")))
  b <- callr::r_bg(worker, args = list(repo = repo, root = root, name = "b.txt", slow = FALSE))
  withr::defer(try(b$kill(), silent = TRUE))
  b$wait(timeout = 10000)
  expect_true(b$get_result()$ok)
  expect_true(a$is_alive())
  reservation <- file.path(root, "a.txt.mergen-rsv")
  owner <- env$mergen_reservation_owner(reservation)
  expect_false(env$mergen_reservation_takeover(reservation, env$mergen_reservation_token(), stale_sec = 1))
  expect_identical(env$mergen_reservation_owner(reservation), owner)
  writeLines("devam", file.path(root, "release"))
  a$wait(timeout = 10000)
  expect_true(a$get_result()$ok)
  expect_identical(readLines(file.path(root, "a.txt")), "a.txt")
  expect_identical(readLines(file.path(root, "b.txt")), "b.txt")
})

test_that("eksik Windows kısa yolunda var olan üst dizin kaynak kapsamını belirler", {
  for (mode in c("missing", "resolved_elsewhere", "outside")) local({
    env <- .ingestionEnv()
    root <- withr::local_tempdir()
    upload <- list(name = "kisa_yol.txt", datapath = file.path(root, "upload"), size = 4,
      type = "text/plain")
    writeLines("veri", upload$datapath)
    if (mode != "resolved_elsewhere") unlink(upload$datapath)
    env$normalizePath <- function(path, ...) {
      if (identical(path, upload$datapath)) return("Z:/SHORT~1/Temp/upload")
      if (mode == "outside" && identical(path, dirname(upload$datapath))) return("Z:/stable")
      base::normalizePath(path, ...)
    }
    links <- 0L
    env$file.link <- function(...) { links <<- links + 1L; FALSE }
    env$file.rename <- function(...) FALSE
    logs <- character()
    controller <- env$file_ingestion_create_controller(debug_fn = function(tag, message)
      logs <<- c(logs, tag))
    lease <- new.env(parent = emptyenv())
    lease$slot_acquired <- FALSE
    job <- list(id = basename(tempfile("short-source-")), lease = lease, controller = controller,
      tasks = list(.ingestionTask(env, upload)))
    withr::defer(env$file_ingestion_release_job(job))
    job <- env$file_ingestion_bind_sources(job)
    if (mode == "missing") {
      expect_match(job$tasks[[1]]$source_error, "geçici kaynağı hazırlanamadı", fixed = TRUE)
      expect_identical(env$file_ingestion_execute_task(job$tasks[[1]])$code, "source_unavailable")
      expect_identical(logs, "ingest_source_link_error")
      expect_identical(links, 1L)
    } else {
      # Yükleme alanı dışına çözülen kaynak ASLA bağlanmaz/kopyalanmaz; görev
      # kaynak hatasıyla reddedilir (önceden olduğu gibi işlenmeye bırakılmaz).
      expect_match(job$tasks[[1]]$source_error, "geçici yükleme alanında değil", fixed = TRUE)
      expect_identical(env$file_ingestion_execute_task(job$tasks[[1]])$code, "source_unavailable")
      expect_identical(job$tasks[[1]]$datapath, upload$datapath)
      expect_identical(logs, "ingest_source_outside_upload_root")
      expect_identical(links, 0L)
    }
  })
})

test_that("taşınan kaynak hata ve süre aşımından sonra aynı girdiden yeniden gönderilir", {
  for (mode in c("timeout", "worker")) local({
    env <- .ingestionEnv()
    withr::local_envvar(c(MERGEN_FILE_INGESTION_QUEUE_TIMEOUT = ""))
    withr::local_options(list(mergen.file_ingestion.queue_timeout = 1800L))
    env$mergen_cancellable_worker_capacity <- function(...) 1L
    available <- FALSE
    env$file_ingestion_pool_has_capacity <- function() available
    env$file.link <- function(...) FALSE
    controller <- env$file_ingestion_create_controller()
    withr::defer(env$file_ingestion_cancel_controller(controller))
    upload <- .ingestionUpload(paste0("kaynak_tekrar_", mode, ".txt"), "yeniden denenecek baytlar")
    failures <- 0L
    task <- .ingestionTask(env, upload)
    env$file_ingestion_submit_batch(controller, list(task), "42",
      on_failure = function(...) failures <<- failures + 1L)
    state <- env$.file_ingestion_state()
    job <- state$pending[[1]]
    sources <- job$lease$sources
    expect_false(file.exists(upload$datapath))
    if (mode == "timeout") {
      state$pending[[1]]$queued_at <- Sys.time() - 1801
      env$file_ingestion_pump()
    } else {
      env$file_ingestion_take_next_job()
      job$lease$slot_acquired <- TRUE
      state$active <- 1L
      env$file_ingestion_fail_job(job, simpleError("işçi hatası"))
    }
    expect_identical(failures, 1L)
    expect_identical(state$active, 0L)
    expect_identical(readLines(upload$datapath), "yeniden denenecek baytlar")
    expect_false(dir.exists(sources))
    expect_false(env$file_ingestion_release_job(job))
    available <- TRUE
    received <- NULL
    status <- env$file_ingestion_submit_batch(controller, list(task), "42",
      on_complete = function(results, ...) received <<- results)
    expect_identical(status$status, "started")
    for (i in 1:30) later::run_now(0)
    expect_true(received[[1]]$ok)
    expect_identical(readLines(received[[1]]$dest), "yeniden denenecek baytlar")
    expect_false(file.exists(upload$datapath))
    expect_false(dir.exists(dirname(received[[1]]$source_path)))
    expect_identical(state$active, 0L)
  })
})

test_that("oturum yükleme dizini silindiyse taşınan özel kaynak tutulmaz", {
  env <- .ingestionEnv()
  env$file.link <- function(...) FALSE
  upload_dir <- withr::local_tempdir()
  upload <- .ingestionUpload("kapanan_kaynak.txt", "özel baytlar")
  file.rename(upload$datapath, file.path(upload_dir, "upload"))
  upload$datapath <- file.path(upload_dir, "upload")
  job <- .ingestionJob(env, env$file_ingestion_create_controller())
  job$id <- basename(tempfile("closed-source-"))
  job$lease <- new.env(parent = emptyenv())
  job$lease$slot_acquired <- FALSE
  job$tasks <- list(.ingestionTask(env, upload))
  job <- env$file_ingestion_bind_sources(job)
  withr::defer(unlink(job$lease$sources, recursive = TRUE))
  expect_true(file.exists(job$tasks[[1]]$datapath))
  unlink(upload_dir, recursive = TRUE)
  expect_true(env$file_ingestion_release_job(job))
  expect_false(file.exists(job$tasks[[1]]$datapath))
  expect_false(dir.exists(job$lease$sources))
  expect_length(job$lease$retained_sources, 0L)
  expect_false(env$file_ingestion_release_job(job))
})

test_that("alım karantina bildirimi kopya ve indeks işçisinin sahipliğini bırakmaz", {
  for (stage in c("copy", "index")) {
    env <- .ingestionEnv()
    job <- .ingestionJob(env, env$file_ingestion_create_controller())
    job$lease <- new.env()
    job$lease$slot_acquired <- TRUE
    job$lease$sources <- withr::local_tempdir()
    source_path <- file.path(job$lease$sources, "bytes")
    writeLines("korunacak", source_path)
    state <- env$.file_ingestion_state()
    state$active <- 1L
    notified <- rolled_back <- uncertain_count <- 0L
    job$on_failure <- function(...) notified <<- notified + 1L
    job$controller$clear_notification <- function(id, uncertain = FALSE) {
      if (uncertain) uncertain_count <<- uncertain_count + 1L
    }
    uncertain <- reject_worker <- NULL
    env$tracked_future_promise <- function(..., on_uncertain) {
      uncertain <<- on_uncertain
      promises::promise(function(resolve, reject) reject_worker <<- reject)
    }
    env$file_ingestion_rollback_job <- function(job, results, error, journals) {
      rolled_back <<- rolled_back + 1L
      env$file_ingestion_fail_job(job, error)
    }
    if (stage == "copy") env$file_ingestion_run_job(job) else env$file_ingestion_finish_job(job, list())
    expect_true(is.function(uncertain))
    uncertain(simpleError("karantinada"))
    uncertain(simpleError("karantinada"))
    expect_identical(notified, 0L)
    expect_identical(uncertain_count, 1L)
    expect_identical(rolled_back, 0L)
    expect_true(file.exists(source_path))
    expect_identical(env$.file_ingestion_state()$active, 1L)
    reject_worker(simpleError("ölüm doğrulandı"))
    for (i in 1:30) later::run_now(0)
    expect_identical(rolled_back, 1L)
    expect_identical(notified, 1L)
    expect_false(file.exists(source_path))
    expect_identical(env$.file_ingestion_state()$active, 0L)
  }
})

test_that("başarısız terfi görünür yabancı hedefe silme yetkisi vermez", {
  env <- .ingestionEnv()
  root <- withr::local_tempdir()
  stage <- file.path(root, "stage")
  dest <- file.path(root, "target")
  writeLines("yükleme", stage)
  env$file.link <- function(...) FALSE
  env$file.rename <- function(from, to) {
    writeLines("yabancı", to)
    FALSE
  }
  env$file.copy <- function(...) FALSE
  result <- env$mergen_promote_staged_file(stage, dest, file.exists)
  expect_false(result$promoted)
  expect_true(result$yabanci)
  expect_false(isTRUE(result$partial_owned))
  # Görsel çağırıcısının temizlik sözleşmesi yabancı hedefi korumalıdır.
  if (isTRUE(result$partial_owned)) unlink(dest)
  expect_identical(readLines(dest), "yabancı")
  expect_identical(readLines(stage), "yükleme")
})

test_that("taşınan kaynak kısmi commit'te yalnız reddedilen dosyayı iade eder", {
  env <- .ingestionEnv()
  env$file.link <- function(...) FALSE
  controller <- env$file_ingestion_create_controller()
  uploads <- list(.ingestionUpload("kaynak_kabul.txt", "kabul"), .ingestionUpload("kaynak_red.txt", "red"))
  job <- .ingestionJob(env, controller)
  job$id <- basename(tempfile("partial-source-"))
  job$lease <- new.env(parent = emptyenv())
  job$lease$slot_acquired <- FALSE
  job$tasks <- lapply(uploads, function(upload) .ingestionTask(env, upload))
  withr::defer(env$file_ingestion_release_job(job))
  job <- env$file_ingestion_bind_sources(job)
  sources <- job$lease$sources
  results <- lapply(job$tasks, function(task) env$file_ingestion_task_result(task, TRUE))
  env$file_ingestion_apply_commit(job, results,
    list(indexed = "kaynak_kabul.txt", accepted = c(TRUE, FALSE), ms = 0))
  expect_false(file.exists(uploads[[1]]$datapath))
  expect_identical(readLines(uploads[[2]]$datapath), "red")
  expect_false(dir.exists(sources))
  expect_identical(env$.file_ingestion_state()$active, 0L)
})

test_that("başarısız kaynak iadesi yalnız kurtarılamayan kopyayı saklar", {
  for (mode in c("busy", "collision")) local({
    env <- .ingestionEnv()
    env$file.link <- function(...) FALSE
    controller <- env$file_ingestion_create_controller()
    uploads <- list(.ingestionUpload("kabul.txt", "kabul"),
      .ingestionUpload("iade.txt", "iade"), .ingestionUpload("koru.txt", "koru"))
    job <- .ingestionJob(env, controller)
    job$id <- basename(tempfile("mixed-retained-source-"))
    job$lease <- new.env(parent = emptyenv())
    job$lease$slot_acquired <- FALSE
    job$tasks <- lapply(uploads, function(upload) .ingestionTask(env, upload))
    job <- env$file_ingestion_bind_sources(job)
    sources <- job$lease$sources
    withr::defer(unlink(sources, recursive = TRUE))
    if (mode == "busy") env$file.rename <- function(from, to) {
      if (identical(from, job$tasks[[3]]$datapath)) FALSE else base::file.rename(from, to)
    } else writeLines("yabancı", uploads[[3]]$datapath)
    results <- lapply(job$tasks, function(task) env$file_ingestion_task_result(task, TRUE))
    env$file_ingestion_apply_commit(job, results,
      list(indexed = "kabul.txt", accepted = c(TRUE, FALSE, FALSE), ms = 0))
    expect_false(file.exists(uploads[[1]]$datapath))
    expect_false(file.exists(job$tasks[[1]]$datapath))
    expect_identical(readLines(uploads[[2]]$datapath), "iade")
    expect_false(file.exists(job$tasks[[2]]$datapath))
    expect_identical(readLines(job$tasks[[3]]$datapath), "koru")
    expect_identical(list.files(sources), basename(job$tasks[[3]]$datapath))
    if (mode == "collision") expect_identical(readLines(uploads[[3]]$datapath), "yabancı") else
      expect_false(file.exists(uploads[[3]]$datapath))
    expect_false(env$file_ingestion_release_job(job))
    expect_identical(env$.file_ingestion_state()$active, 0L)
  })
})

test_that("taşınan kaynak iade edilemezse baytlar korunur ve yabancı hedef ezilmez", {
  for (mode in c("busy", "collision")) local({
    env <- .ingestionEnv()
    env$file.link <- function(...) FALSE
    logs <- character()
    controller <- env$file_ingestion_create_controller(debug_fn = function(tag, message)
      logs <<- c(logs, tag))
    upload <- .ingestionUpload(paste0("kaynak_iade_", mode, ".txt"), "korunacak")
    job <- .ingestionJob(env, controller)
    job$id <- basename(tempfile("retained-source-"))
    job$lease <- new.env(parent = emptyenv())
    job$lease$slot_acquired <- FALSE
    job$tasks <- list(.ingestionTask(env, upload))
    job <- env$file_ingestion_bind_sources(job)
    sources <- job$lease$sources
    withr::defer(unlink(sources, recursive = TRUE))
    if (mode == "busy") env$file.rename <- function(...) FALSE else writeLines("yabancı", upload$datapath)
    expect_true(env$file_ingestion_release_job(job))
    expect_identical(readLines(job$tasks[[1]]$datapath), "korunacak")
    expect_true(dir.exists(sources))
    expect_identical(logs, "ingest_source_restore_error")
    if (mode == "collision") expect_identical(readLines(upload$datapath), "yabancı") else
      expect_false(file.exists(upload$datapath))
    expect_false(env$file_ingestion_release_job(job))
    expect_identical(env$.file_ingestion_state()$active, 0L)
  })
})

test_that("kodlama eşleri tek staging ve sahip rezervasyonunda buluşur; eski marker tanınır", {
  env <- .ingestionEnv()
  env$.Platform <- list(OS.type = "windows")
  # Gerçek Unicode ebeveyn, göreli yollarla kodlama benzetiminin dışında kalır.
  withr::local_dir(withr::local_tempdir(pattern = paste0(intToUtf8(c(0x11f, 0x131)), "-")))
  root <- "."
  name <- paste0(strrep("Ö", 100), ".txt")
  native <- iconv(name, "UTF-8", "latin1")
  native_text <- function(x) iconv(enc2utf8(x), "UTF-8", "latin1")
  env$enc2native <- native_text
  env$basename <- function(x) {
    result <- base::basename(x)
    if (any(Encoding(x) == "latin1")) native_text(result) else result
  }
  env$tolower <- function(x) {
    result <- base::tolower(x)
    if (any(Encoding(x) == "latin1")) native_text(result) else result
  }
  env$file.path <- function(...) {
    result <- base::file.path(...)
    if (any(vapply(list(...), function(x) any(Encoding(x) == "latin1"), logical(1)))) native_text(result) else result
  }
  utf8 <- file.path(root, name)
  alias <- env$file.path(root, native)
  expect_false(anyNA(alias))
  expect_identical(charToRaw(env$basename(alias)), charToRaw(native))
  marker <- env$file_ingestion_owner_path(utf8)
  stage <- env$mergen_upload_staging_path(utf8)
  expect_identical(env$file_ingestion_owner_path(alias), marker)
  expect_identical(env$mergen_upload_staging_path(alias), stage)
  legacy <- env$file_ingestion_owner_path(alias, legacy = TRUE)
  expect_false(identical(legacy, marker))
  env$file_ingestion_write_owner(list(id = "legacy", state = "copying"), legacy)
  expect_identical(env$file_ingestion_owner_path(utf8), legacy)
  expect_identical(env$file_ingestion_owner_path(alias), legacy)
  env$file_ingestion_owner_reclaimable <- function(...) FALSE
  expect_error(env$file_ingestion_begin_copy(utf8, stage, "source",
    list(id = "blocked", journal = withr::local_tempfile())), "başka bir işlem")
  unlink(legacy)
  env$file_ingestion_owner_reclaimable <- function(...) TRUE
  first <- list(id = "first", journal = withr::local_tempfile())
  env$file_ingestion_begin_copy(alias, stage, "source", first)
  env$file_ingestion_begin_copy(file.path(root, tolower(name)), stage, "source", first)
  expect_identical(env$file_ingestion_read_owner(utf8)$id, first$id)
  env$file_ingestion_owner_reclaimable <- function(...) FALSE
  expect_error(env$file_ingestion_begin_copy(utf8, stage, "source",
    list(id = "second", journal = withr::local_tempfile())), "başka bir işlem")
  expect_false(file.exists(stage))
  expect_identical(env$file_ingestion_read_owner(utf8)$id, first$id)
})

test_that("kanıtlı eski staging temizlenir; aynı addaki yabancı dosya korunur", {
  env <- .ingestionEnv()
  root <- withr::local_tempdir()
  target <- file.path(root, paste0(strrep("n", 185), ".txt"))
  legacy <- paste0(target, env$MERGEN_UPLOAD_STAGING_SUFFIX)
  stage <- env$mergen_upload_staging_path(target)
  expect_false(identical(stage, legacy))
  usable <- isTRUE(suppressWarnings(file.create(legacy)))
  skip_if(!usable && .Platform$OS.type == "windows" && env$mergen_artifact_path_units(legacy) > 259L,
    "Host cannot represent the legacy staging fixture under this temporary root")
  expect_true(usable)
  marker <- env$file_ingestion_owner_path(target)
  old <- list(id = "abandoned", state = "copying", staging = legacy)
  env$file_ingestion_write_owner(old, marker)
  writeLines("abandoned", legacy)
  env$file_ingestion_prepare_promotion(legacy, target, list(id = old$id))
  env$file_ingestion_owner_reclaimable <- function(...) TRUE
  env$file_ingestion_begin_copy(target, stage, "source", list(id = "new", journal = withr::local_tempfile()))
  expect_false(file.exists(legacy))
  expect_identical(env$file_ingestion_read_owner(target)$id, "new")
  # Aynı yol daha sonra tamamlanmış başka bir yüklemenin dosyası olabilir.
  writeLines("completed", legacy)
  other <- env$file_ingestion_claim_artifact(legacy)
  env$file_ingestion_write_owner(old, marker)
  env$file_ingestion_prepare_promotion(legacy, target, list(id = old$id))
  env$file_ingestion_begin_copy(target, stage, "source", list(id = "next", journal = withr::local_tempfile()))
  expect_identical(readLines(legacy), "completed")
  expect_true(env$file_ingestion_artifact_owned(list(dest = legacy, artifact_id = other)))
  unlink(env$file_ingestion_owner_path(legacy))
  env$.load_index <- function() list(`42` = list(document = list(path = legacy)))
  env$file_ingestion_write_owner(old, marker)
  env$file_ingestion_prepare_promotion(legacy, target, list(id = old$id))
  env$file_ingestion_begin_copy(target, stage, "source", list(id = "indexed", journal = withr::local_tempfile()))
  expect_identical(readLines(legacy), "completed")
})

test_that("rezervasyonun karantina ve owner yolları Windows tam yol bütçesine sığar", {
  env <- .ingestionEnv()
  env$.Platform <- list(OS.type = "windows")
  parent <- paste0("C:/", strrep("p", 180))
  target <- file.path(parent, strrep("n", 59))
  reservation <- env$mergen_upload_artifact_path(target, ".mergen-rsv", component_only = TRUE)
  expect_lt(env$mergen_artifact_path_units(reservation), env$mergen_artifact_path_units(paste0(target, ".mergen-rsv")))
  longest <- file.path(env$mergen_reservation_quarantine_path(reservation, unique = FALSE), "owner")
  expect_lte(env$mergen_artifact_path_units(longest), 259L)
  expect_error(env$mergen_upload_artifact_path(file.path(paste0(parent, strrep("p", 60)), "a"),
    ".mergen-rsv", component_only = TRUE), "Rezervasyon yolu")
})

for (name in c("kisa.bin", paste0(strrep("ö", 100L), ".bin"))) test_that(paste("staging baytları korur:", name), {
  env <- .ingestionEnv()
  root <- withr::local_tempdir()
  source <- withr::local_tempfile()
  bytes <- as.raw(c(0, 255, 195, 40, 10))
  writeBin(bytes, source)
  target <- file.path(root, name)
  stage <- env$mergen_upload_staging_path(target)
  if (nchar(name, type = "bytes") > 180L) expect_false(identical(stage, paste0(target, env$MERGEN_UPLOAD_STAGING_SUFFIX)))
  usable <- isTRUE(suppressWarnings(file.create(target)))
  skip_if(!usable && .Platform$OS.type == "windows" && env$mergen_artifact_path_units(target) > 259L,
    "Host cannot represent this final-path fixture without Windows long-path support")
  expect_true(usable)
  unlink(target)
  expect_identical(env$mergen_copy_upload_staged(source, target, root), target)
  expect_identical(readBin(target, "raw", 100L), bytes)
  expect_false(file.exists(stage))
})

test_that("işlemsiz kopya yabancı staging'i korur ve aynı rezervasyonu paylaşır", {
  env <- .ingestionEnv()
  root <- withr::local_tempdir()
  source <- withr::local_tempfile()
  writeLines("first", source)
  # 181 bayt sıkıştırma eşiğini (180) aşar; derin Windows geçici kökünde de temsil edilir.
  target <- file.path(root, paste0(strrep("a", 177L), ".txt"))
  stage <- env$mergen_upload_staging_path(target)
  expect_false(identical(stage, paste0(target, env$MERGEN_UPLOAD_STAGING_SUFFIX)))
  usable <- isTRUE(suppressWarnings(file.create(target)))
  skip_if(!usable && .Platform$OS.type == "windows" && env$mergen_artifact_path_units(target) > 259L,
    "Host cannot represent this final-path fixture without Windows long-path support")
  expect_true(usable)
  unlink(target)
  writeLines("foreign", stage)
  expect_error(env$mergen_copy_upload_staged(source, target, root), "zaten var")
  expect_identical(readLines(stage), "foreign")
  expect_false(file.exists(target))
  expect_false(file.exists(env$file_ingestion_owner_path(target)))
  unlink(stage)
  real_copy <- fs::file_copy
  entered <- FALSE
  env$file_ingestion_owner_reclaimable <- function(...) FALSE
  testthat::local_mocked_bindings(file_copy = function(path, new_path, overwrite = FALSE, ...) {
    if (!entered) {
      entered <<- TRUE
      expect_error(env$mergen_copy_upload_staged(source, target, root), "başka bir işlem")
      expect_error(env$mergen_copy_upload_staged(source, target, root,
        transaction = list(id = "other", journal = withr::local_tempfile())), "başka bir işlem")
    }
    real_copy(path, new_path, overwrite = overwrite, ...)
  }, .package = "fs")
  expect_identical(env$mergen_copy_upload_staged(source, target, root), target)
  expect_true(entered)
  expect_identical(readLines(target), "first")
  expect_false(file.exists(stage))
  expect_false(file.exists(env$file_ingestion_owner_path(target)))
})

test_that("yerel kodlamaya yeniden bağlanan eski staging fiziksel kanıtla kurtarılır", {
  env <- .ingestionEnv()
  root <- file.path(withr::local_tempdir(), "Ö")
  expect_true(dir.create(root))
  target <- file.path(root, paste0(strrep("a", 190L), ".txt"))
  stage <- env$mergen_upload_staging_path(target)
  native <- iconv(sub(".mergen-", ".MERGEN-", enc2utf8(stage), fixed = TRUE), "UTF-8", "latin1")
  Encoding(native) <- "unknown"
  expect_false(identical(native, stage))
  marker <- env$file_ingestion_owner_path(target)
  env$file_ingestion_owner_reclaimable <- function(...) TRUE
  real_key <- env$file_ingestion_physical_identity
  env$file_ingestion_physical_identity <- function(path) {
    if (identical(charToRaw(path), charToRaw(native))) real_key(stage) else real_key(path)
  }
  for (proven in c(FALSE, TRUE)) {
    writeLines("abandoned", stage)
    env$file_ingestion_write_owner(list(id = "old-native", state = "copying", staging = native), marker)
    if (proven) env$file_ingestion_prepare_promotion(stage, target, list(id = "old-native"))
    tx <- list(id = "retry", journal = withr::local_tempfile())
    if (!proven) {
      expect_error(env$file_ingestion_begin_copy(target, stage, "source", tx), "kimliği doğrulanamadı")
      expect_identical(readLines(stage), "abandoned")
    } else {
      env$file_ingestion_begin_copy(target, stage, "source", tx)
      expect_false(file.exists(stage))
      expect_identical(env$file_ingestion_read_owner(target)$id, tx$id)
    }
  }
})

test_that("inode'suz boyut+mtime eşliği staging silmeye yetki vermez", {
  env <- .ingestionEnv()
  root <- withr::local_tempdir()
  target <- file.path(root, "zayif.txt")
  stage <- env$mergen_upload_staging_path(target)
  marker <- env$file_ingestion_owner_path(target)
  env$file_ingestion_owner_reclaimable <- function(...) TRUE
  # Ağ paylaşımı inode vermez: farklı dosyalar aynı zayıf anahtarı üretir.
  env$file_ingestion_physical_identity <- function(path)
    if (file.exists(path)) list(size = "9", modification_time = "2026-01-01 00:00:00") else NULL
  for (recorded in c("other", "same")) {
    old <- if (recorded == "same") stage else file.path(root, "eski.mergen-part")
    if (recorded == "other") writeLines("abandon!", old)
    writeLines("foreign!", stage)
    env$file_ingestion_write_owner(list(id = "old", state = "copying", staging = old), marker)
    env$file_ingestion_prepare_promotion(old, target, list(id = "old"))
    tx <- list(id = "retry", journal = withr::local_tempfile())
    expect_error(env$file_ingestion_begin_copy(target, stage, "source", tx),
      if (recorded == "same") "kimliği doğrulanamadı" else "zaten var")
    expect_identical(readLines(stage), "foreign!")
    if (recorded == "other") expect_identical(readLines(old), "abandon!")
    expect_identical(env$file_ingestion_read_owner(target)$id, "old")
  }
  expect_false(env$file_ingestion_same_physical_file(list(size = "1"), list(size = "1")))
  expect_true(env$file_ingestion_same_physical_file(list(inode = "7", size = "1"), list(inode = "7", size = "1")))
})

test_that("marker takma adı zayıf kimlikle değil nesil kanıtıyla ayırt edilir", {
  env <- .ingestionEnv()
  root <- withr::local_tempdir()
  env$file_ingestion_physical_identity <- function(path)
    if (file.exists(path)) list(size = "1", modification_time = "t") else NULL
  first <- file.path(root, "ilk.txt")
  second <- file.path(root, "ikinci.txt")
  tx <- list(id = "tx", journal = withr::local_tempfile())
  env$file_ingestion_begin_copy(first, env$mergen_upload_staging_path(first), "source", tx)
  expect_true(file.exists(env$file_ingestion_owner_path(first)))
  # Ayrı marker'lar zayıf anahtarla eşleşse de eski rezervasyon bırakılır.
  env$file_ingestion_begin_copy(second, env$mergen_upload_staging_path(second), "source", tx)
  expect_false(file.exists(env$file_ingestion_owner_path(first)))
  # Aynı fiziksel marker'a çözülen takma ad yeni rezervasyonu silmez.
  real_path <- env$file_ingestion_owner_path
  alias <- file.path(root, "takma.txt")
  env$file_ingestion_owner_path <- function(path, ...) real_path(if (identical(path, alias)) second else path, ...)
  env$file_ingestion_begin_copy(alias, env$mergen_upload_staging_path(second), "source", tx)
  expect_true(file.exists(real_path(second)))
  expect_identical(env$file_ingestion_read_owner(alias)$id, "tx")
})

test_that("indeks talebi POSIX'te harf duyarlı, Windows'ta harf duyarsız karşılaştırılır", {
  env <- .ingestionEnv()
  root <- withr::local_tempdir()
  target <- file.path(root, "rapor.txt")
  stage <- env$mergen_upload_staging_path(target)
  marker <- env$file_ingestion_owner_path(target)
  env$file_ingestion_owner_reclaimable <- function(...) TRUE
  if (.Platform$OS.type != "windows") {
    for (index_path in c(toupper(stage), stage)) {
      writeLines("abandoned", stage)
      env$file_ingestion_write_owner(list(id = "old", state = "copying", staging = stage), marker)
      env$file_ingestion_prepare_promotion(stage, target, list(id = "old"))
      env$.load_index <- function() list("42" = list(x = list(path = index_path)))
      tx <- list(id = paste0("retry-", nchar(index_path)), journal = withr::local_tempfile())
      if (identical(index_path, stage)) {
        expect_error(env$file_ingestion_begin_copy(target, stage, "source", tx), "kimliği doğrulanamadı")
        expect_true(file.exists(stage))
      } else {
        env$file_ingestion_begin_copy(target, stage, "source", tx)
        expect_false(file.exists(stage))
      }
    }
  }
  env$.Platform <- list(OS.type = "unix")
  expect_false(identical(env$.mergen_index_path_key("/srv/A.txt"), env$.mergen_index_path_key("/srv/a.txt")))
  env$.Platform <- list(OS.type = "windows")
  expect_identical(env$.mergen_index_path_key("C:\\Srv\\A.txt"), env$.mergen_index_path_key("c:/srv/a.txt"))
})

test_that("şerit bekleme bütçesi geçersiz seçenekte güvenli varsayılana döner", {
  env <- new.env(parent = baseenv())
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_files_promote_probe.R"),
    local = env, encoding = "UTF-8")
  root <- withr::local_tempdir()
  env$mergen_upload_mutex_path <- function(path) file.path(root, "lane.lock")
  clock <- as.POSIXct("2026-01-01", tz = "UTC")
  env$Sys.time <- function() clock
  guard <- list(held = TRUE)
  timeout_seen <- NULL
  acquire <- TRUE
  env$mergen_reclaim_mutex <- function(path, timeout = 0) {
    expect_length(timeout, 1L)
    expect_true(is.finite(timeout))
    expect_gte(timeout, 0)
    timeout_seen <<- timeout
    if (acquire) return(guard)
    clock <<- clock + 120
    NULL
  }
  invalid <- list(NA_real_, NaN, Inf, -Inf, -1, NULL, numeric(), c(1, 2),
    "invalid", list(1), 1 + 1i, TRUE)
  shiny::withReactiveDomain(NULL, {
    for (budget in invalid) {
      withr::with_options(list(mergen.upload_lane_wait_sec = budget), {
        acquire <- TRUE
        expect_identical(env$mergen_upload_lane_lock("target"), guard)
        expect_equal(timeout_seen, 5000)
        acquire <- FALSE
        expect_null(env$mergen_upload_lane_lock("target"))
        expect_equal(timeout_seen, 5000)
      })
      # Açık NULL da seçenek yokluğundan ayrı doğrulanır.
      acquire <- TRUE
      expect_identical(env$mergen_upload_lane_lock("target", wait_sec = budget), guard)
      expect_equal(timeout_seen, 5000)
    }
    for (budget in list(0, 0.125, 2L, 120)) {
      expect_identical(env$mergen_upload_lane_lock("target", wait_sec = budget), guard)
      expect_equal(timeout_seen, min(5000, budget * 1000))
    }
  })
  session <- shiny::MockShinySession$new()
  withr::defer(session$close())
  shiny::withReactiveDomain(session, {
    for (budget in c(invalid, list(120))) {
      acquire <- FALSE
      expect_null(env$mergen_upload_lane_lock("target", wait_sec = budget))
      expect_identical(timeout_seen, 0)
    }
  })
})

test_that("şerit çekişmesi tek zaman aşımında yüklemeyi düşürmez; kilit hatası beklemeden döner", {
  skip_if_not_installed("filelock")
  skip_if_not_installed("callr")
  env <- .ingestionEnv()
  root <- withr::local_tempdir()
  target <- file.path(root, "hedef.txt")
  lock <- env$mergen_upload_mutex_path(target)
  # Tutucu süreç kilit dizinini oluşturmaz; test önceki testlere bağlı kalmaz.
  dir.create(dirname(lock), recursive = TRUE, showWarnings = FALSE)
  real <- get("mergen_reclaim_mutex", envir = env, inherits = TRUE)
  calls <- 0L
  env$mergen_reclaim_mutex <- function(path, timeout = 0, exclusive = TRUE) {
    calls <<- calls + 1L
    real(path, min(timeout, 200), exclusive)
  }
  # Başka süreç şeridi zaman aşımı diliminden uzun tutar; edinim beklenir.
  holder <- callr::r_bg(function(lock, ready) {
    guard <- filelock::lock(lock, timeout = 5000)
    writeLines("held", ready)
    Sys.sleep(1.5)
    filelock::unlock(guard)
  }, args = list(lock = lock, ready = file.path(root, "ready")))
  withr::defer(try(holder$kill(), silent = TRUE))
  deadline <- Sys.time() + 20
  while (!file.exists(file.path(root, "ready")) && holder$is_alive() && Sys.time() < deadline) holder$poll_io(50)
  expect_true(file.exists(file.path(root, "ready")))
  # Oturum içindeki çekişme sıfır zaman aşımıyla kapalı başarısız olur.
  session_timeout <- NULL
  env$mergen_reclaim_mutex <- function(path, timeout = 0, exclusive = TRUE) {
    session_timeout <<- timeout
    NULL
  }
  shiny::withReactiveDomain(shiny::MockShinySession$new(), {
    expect_null(env$mergen_upload_lane_lock(target))
  })
  expect_identical(session_timeout, 0)
  env$mergen_reclaim_mutex <- function(path, timeout = 0, exclusive = TRUE) {
    calls <<- calls + 1L
    real(path, min(timeout, 200), exclusive)
  }
  guard <- env$mergen_upload_lane_lock(target)
  expect_false(is.null(guard))
  expect_gt(calls, 1L)
  filelock::unlock(guard)
  holder$wait(5000)
  # Boş şeritte sürekli edinme hatası bütçe boyunca beklenmez.
  env$mergen_reclaim_mutex <- function(...) NULL
  started <- Sys.time()
  expect_null(env$mergen_upload_lane_lock(target))
  expect_lt(as.numeric(difftime(Sys.time(), started, units = "secs")), 5)
})

test_that("yalıtılmış terfi rezervasyon modülü olmadan türlenmiş sonucu korur", {
  env <- new.env(parent = baseenv())
  for (name in c("helpers_files_promote_probe.R", "helpers_files_promote_target.R"))
    source(file.path(resolve_repo_root_for_tests(), "R", name), local = env, encoding = "UTF-8")
  expect_false(exists("mergen_reservation_quarantine_path", envir = env, inherits = TRUE))
  root <- withr::local_tempdir()
  stage <- file.path(root, "stage")
  target <- file.path(root, "target")
  writeLines("preserve", stage)
  env$file.link <- function(...) FALSE
  result <- env$mergen_promote_staged_file(stage, target, file.exists)
  expect_identical(result, list(ok = FALSE, yabanci = FALSE, promoted = FALSE))
  expect_identical(readLines(stage), "preserve")
  expect_false(file.exists(target))
  # Sahte rezervasyon sözleşmesi de global test sırasından bağımsız çalışır.
  env$mergen_reservation_token <- function(...) "fixture"
  env$mergen_reservation_acquire <- function(...) TRUE
  released <- FALSE
  env$mergen_reservation_release <- function(...) { released <<- TRUE; TRUE }
  result <- env$mergen_promote_staged_file(stage, target, file.exists)
  expect_true(result$promoted)
  expect_true(released)
  expect_identical(readLines(target), "preserve")
})

test_that("rezervasyon bütçesi reddedilince staging ve terfi kanıtı temizlenir", {
  for (direct in c(FALSE, TRUE)) {
    env <- .ingestionEnv()
    root <- withr::local_tempdir()
    source <- withr::local_tempfile()
    writeLines("source", source)
    target <- file.path(root, "target.txt")
    stage <- env$mergen_upload_staging_path(target)
    marker <- env$file_ingestion_owner_path(target)
    real_path <- env$mergen_upload_artifact_path
    env$mergen_upload_artifact_path <- function(final_dest, suffix, component_only = FALSE) {
      if (component_only) stop("Rezervasyon yolu dosya sistemi sınırını aşıyor.")
      real_path(final_dest, suffix, component_only)
    }
    env$file.link <- function(...) FALSE
    tx <- if (direct) NULL else list(id = "failed-budget", journal = withr::local_tempfile())
    expect_error(env$mergen_copy_upload_staged(source, target, root, transaction = tx), "kalıcı ada taşınamadı")
    expect_false(file.exists(stage))
    expect_false(file.exists(paste0(marker, ".identity")))
    expect_false(file.exists(target))
    if (!direct) env$file_ingestion_discard_results(list(readRDS(tx$journal)), "42")
    expect_false(file.exists(marker))
    expect_identical(readLines(source), "source")
  }
})

test_that("doğrudan kopyanın başarısız temizliği kalıcı sahiplik kanıtını korur, oturum günlüğünü bırakmaz", {
  for (cleanup_fails in c(FALSE, TRUE)) {
    env <- .ingestionEnv()
    root <- withr::local_tempdir()
    source <- withr::local_tempfile()
    writeLines("source", source)
    target <- file.path(root, "target.txt")
    stage <- env$mergen_upload_staging_path(target)
    journal <- NULL
    env$tempfile <- function(pattern, ...) {
      result <- base::tempfile(pattern, ...)
      if (identical(pattern, "ingest_direct_")) journal <<- result
      result
    }
    warned <- character()
    env$log_warn <- function(msg, ...) warned <<- c(warned, msg)
    env$file_ingestion_prepare_promotion <- function(...) stop("prepare failed")
    if (cleanup_fails) env$file_ingestion_discard_dest <- function(...) FALSE
    # Özgün hata temizlik hatasıyla örtülmez.
    expect_error(env$mergen_copy_upload_staged(source, target, root), "prepare failed")
    expect_false(file.exists(target))
    expect_false(is.null(journal))
    expect_false(file.exists(journal))
    expect_identical(file.exists(stage), cleanup_fails)
    expect_identical(file.exists(env$file_ingestion_owner_path(target)), cleanup_fails)
    expect_identical(length(warned) > 0L, cleanup_fails)
    expect_identical(readLines(source), "source")
    if (cleanup_fails) {
      # Süreç sonu: oturum günlüğü yok; yeni süreç klasördeki marker'dan kurtarır.
      fresh <- .ingestionEnv()
      owner <- fresh$file_ingestion_read_owner(target)
      expect_identical(owner$state, "copying")
      expect_identical(owner$staging, stage)
      fresh$file_ingestion_discard_results(list(list(dest = target, staging = owner$staging,
        artifact_id = owner$id, transaction_pending = TRUE, source_path = source)), "42")
      expect_false(file.exists(stage))
      expect_false(file.exists(fresh$file_ingestion_owner_path(target)))
      expect_identical(readLines(source), "source")
    }
  }
})

test_that("doğrudan kopya bağlantıdan sonra staging silinemese de yayınlanan dosyayı sahiplenmeye açık bırakır", {
  env <- .ingestionEnv()
  root <- withr::local_tempdir()
  source <- withr::local_tempfile()
  writeLines("published", source)
  target <- file.path(root, "linked.txt")
  stage <- env$mergen_upload_staging_path(target)
  linked <- FALSE
  env$file.link <- function(from, to) linked <<- isTRUE(base::file.link(from, to))
  env$.mergen_promote_drop_staging <- function(...) invisible(FALSE)
  expect_identical(env$mergen_copy_upload_staged(source, target, root), target)
  expect_true(linked)
  expect_true(file.exists(stage))
  expect_false(file.exists(env$file_ingestion_owner_path(target)))
  expect_false(file.exists(paste0(env$file_ingestion_owner_path(target), ".identity")))
  # İşçinin işlemsiz talebi sentetik doğrudan kopya sahibine takılmaz.
  id <- env$file_ingestion_claim_artifact(target, env$file_ingestion_file_identity(target))
  expect_identical(env$file_ingestion_read_owner(target)$id, id)
  expect_identical(readLines(target), "published")
})

for (width in c(5L, 235L)) test_that(paste("başarısız karantina iadesi yabancı rezervasyonu korur:", width), {
  env <- .ingestionEnv()
  root <- withr::local_tempdir()
  reservation <- file.path(root, paste0(strrep("r", width), ".mergen-rsv"))
  shape <- env$mergen_reservation_quarantine_path(reservation, unique = FALSE)
  expect_lte(env$mergen_artifact_path_units(basename(shape)), 255L)
  created <- dir.create(reservation, showWarnings = FALSE)
  skip_if(!created && .Platform$OS.type == "windows" && env$mergen_artifact_path_units(reservation) > 259L,
    "Host cannot represent the retained legacy reservation fixture")
  expect_true(created)
  writeLines("foreign", file.path(reservation, "owner"))
  quarantine <- NULL
  env$file.rename <- function(from, to) {
    if (!identical(from, reservation)) return(FALSE)
    moved <- base::file.rename(from, to)
    if (moved) {
      quarantine <<- to
      dir.create(reservation)
      writeLines("newer", file.path(reservation, "owner"))
    }
    moved
  }
  expect_warning(expect_false(env$.mergen_reservation_remove_owned(reservation, "observed-old")), "yabancı rezervasyon")
  expect_identical(env$mergen_reservation_owner(reservation), "newer")
  expect_identical(env$mergen_reservation_owner(quarantine), "foreign")
  expect_true(startsWith(basename(quarantine), substr(basename(shape), 1L, nchar(basename(shape)) - 16L)))
})

test_that("eksik yaprak mevcut üst dizinden bağlanır; kök ve bağlantı kaçışı reddedilir", {
  env <- .ingestionEnv()
  root <- withr::local_tempdir()
  outside <- withr::local_tempdir()
  alias <- file.path(dirname(root), "SHORT~1")
  missing <- file.path(alias, "missing.txt")
  real_normalize <- base::normalizePath
  env$normalizePath <- function(path, winslash = "/", mustWork = NA) {
    if (identical(path, alias)) return(real_normalize(root, winslash, TRUE))
    real_normalize(path, winslash, mustWork)
  }
  expect_true(env$mergen_path_inside_root(missing, root))
  expect_false(env$mergen_path_inside_root(file.path(alias, "..", "escape"), root))
  expect_false(env$mergen_path_inside_root(file.path(outside, "missing"), root))
  expect_false(env$mergen_path_inside_root(missing, file.path(root, "absent-root")))
  # Var olan yaprak çözülemiyorsa yalnız üst dizin üzerinden onaylanamaz.
  leaf <- file.path(root, "unresolved")
  writeLines("preserve", leaf)
  env$normalizePath <- function(path, winslash = "/", mustWork = NA) {
    if (identical(path, leaf)) stop("unresolved")
    real_normalize(path, winslash, mustWork)
  }
  expect_false(env$mergen_path_inside_root(leaf, root))
  link <- file.path(root, "link")
  # Windows `unlink()` dizin sembolik bağlantısında etiket uyuşmazlığı uyarısı
  # verir; libuv bağlantı nesnesini hedefi izlemeden siler ve sonuç doğrulanır.
  drop_link <- function() {
    fs::link_delete(link)
    expect_false(fs::is_link(link))
    expect_false(file.exists(link))
  }
  if (isTRUE(suppressWarnings(file.symlink(outside, link)))) {
    expect_false(env$mergen_path_inside_root(file.path(link, "missing"), root))
    drop_link()
  }
  if (isTRUE(suppressWarnings(file.symlink(file.path(outside, "absent"), link)))) {
    expect_false(env$mergen_path_inside_root(link, root))
    # Windows normalizePath() sarkan bağlantıyı sözcüksel döndürebilir; kapsama yine reddedilir.
    env$normalizePath <- function(path, winslash = "/", mustWork = NA)
      if (identical(path, link)) gsub("\\", "/", path, fixed = TRUE) else real_normalize(path, winslash, mustWork)
    expect_false(env$mergen_path_inside_root(link, root))
    drop_link()
  }
  expect_true(dir.exists(outside))
})

test_that("Windows kısa kökte eksik hedefin doğrudan kopya temizliği kanıtı bırakmaz", {
  env <- .ingestionEnv()
  root <- file.path(withr::local_tempdir(), "long parent directory")
  expect_true(dir.create(root))
  alias <- if (.Platform$OS.type == "windows") shortPathName(root) else root
  source <- withr::local_tempfile()
  writeLines("source", source)
  target <- file.path(alias, "missing.txt")
  expect_true(env$mergen_path_inside_root(target, root))
  stage <- env$mergen_upload_staging_path(target)
  journal <- NULL
  env$tempfile <- function(pattern, ...) {
    result <- base::tempfile(pattern, ...)
    if (identical(pattern, "ingest_direct_")) journal <<- result
    result
  }
  env$file_ingestion_prepare_promotion <- function(...) stop("prepare failed")
  expect_error(env$mergen_copy_upload_staged(source, target, root), "prepare failed")
  expect_false(file.exists(stage))
  expect_false(file.exists(journal))
  expect_false(file.exists(env$file_ingestion_owner_path(target)))
  expect_identical(readLines(source), "source")
})

test_that("doğrudan kopya ve staging temizliği meşgul indeksten bağımsızdır", {
  env <- .ingestionEnv()
  root <- withr::local_tempdir()
  source <- withr::local_tempfile()
  writeLines("source", source)
  # Gerçek indeks kilidi tutulur; yeniden giriş olsa işlem hemen reddedilir.
  real_lock <- .file_store_with_index_lock
  env$.file_store_with_index_lock <- function(expr, ...) real_lock(expr, timeout_sec = 0, require_lock = TRUE)
  real_lock({
    target <- file.path(root, "success.txt")
    expect_identical(env$mergen_copy_upload_staged(source, target, root), target)
    expect_identical(readLines(target), "source")
    expect_false(file.exists(env$file_ingestion_owner_path(target)))
    env$file_ingestion_prepare_promotion <- function(...) stop("prepare failed")
    target <- file.path(root, "failed.txt")
    expect_error(env$mergen_copy_upload_staged(source, target, root), "prepare failed")
    expect_false(file.exists(env$mergen_upload_staging_path(target)))
    expect_false(file.exists(env$file_ingestion_owner_path(target)))
    # İndeks talebi olan eski staging kurtarması kilidi atlayamaz.
    target <- file.path(root, "stale.txt")
    env$file_ingestion_write_owner(list(id = "old", state = "copying"), env$file_ingestion_owner_path(target))
    env$file_ingestion_owner_reclaimable <- function(...) TRUE
    expect_error(env$file_ingestion_begin_copy(target, env$mergen_upload_staging_path(target), source,
      list(id = "new", journal = withr::local_tempfile())), "İndeks kilidi")
    expect_identical(env$file_ingestion_read_owner(target)$id, "old")
  }, require_lock = TRUE)
  expect_identical(readLines(source), "source")
})

test_that("harf takma adlarının hash rezervasyonları fiziksel üst dizinde dışlanır", {
  for (mixed_link in c(FALSE, TRUE)) local({
  root <- withr::local_tempdir()
  # Dosya sistemi takma adları iki mantıksal hedefi tek fiziksel hedefe bağlar.
  worker <- function(repo, root, label, mixed_link) {
    env <- new.env(parent = globalenv())
    for (name in c("helpers_process_ownership.R", "utils_path_reservation.R",
                   "helpers_files_promote_probe.R", "helpers_files_promote_target.R"))
      source(file.path(repo, "R", name), local = env, encoding = "UTF-8")
    logical_dest <- file.path(root, paste0(strrep(if (label == "A") "N" else "n", 240L), ".txt"))
    physical_dest <- file.path(root, "physical.txt")
    stage <- file.path(root, paste0("stage-", label))
    writeLines(label, stage)
    env$file.link <- function(from, to) {
      if (mixed_link && label == "B") base::file.link(from, physical_dest) else FALSE
    }
    real_mutex <- env$mergen_reclaim_mutex
    env$mergen_reclaim_mutex <- function(path, timeout = 0, exclusive = TRUE) {
      guard <- real_mutex(path, 0, exclusive)
      if (identical(path, env$mergen_upload_mutex_path(logical_dest)))
        writeLines(if (is.null(guard)) "blocked" else "acquired", file.path(root, paste0("waiting-", label)))
      if (is.null(guard)) real_mutex(path, timeout, exclusive) else guard
    }
    env$file.rename <- function(from, to) {
      if (identical(from, stage)) {
        if (label == "A") {
          writeLines("ready", file.path(root, "ready"))
          deadline <- Sys.time() + 20
          while (!file.exists(file.path(root, "go")) && Sys.time() < deadline) Sys.sleep(0.01)
          if (!file.exists(file.path(root, "go"))) stop("barrier timeout")
        }
        to <- physical_dest
      }
      base::file.rename(from, to)
    }
    visible <- function(path) file.exists(if (identical(path, logical_dest)) physical_dest else path)
    env$mergen_promote_staged_file(stage, logical_dest, visible)
  }
  first <- callr::r_bg(worker, args = list(repo = resolve_repo_root_for_tests(), root = root, label = "A", mixed_link = mixed_link))
  withr::defer(try(first$kill(), silent = TRUE))
  deadline <- Sys.time() + 20
  while (!file.exists(file.path(root, "ready")) && first$is_alive() && Sys.time() < deadline) first$poll_io(50)
  expect_true(file.exists(file.path(root, "ready")))
  second <- callr::r_bg(worker, args = list(repo = resolve_repo_root_for_tests(), root = root, label = "B", mixed_link = mixed_link))
  withr::defer(try(second$kill(), silent = TRUE))
  while (!file.exists(file.path(root, "waiting-B")) && !file.exists(file.path(root, "physical.txt")) &&
      second$is_alive() && Sys.time() < deadline) second$poll_io(50)
  blocked <- file.exists(file.path(root, "waiting-B"))
  expect_true(blocked)
  if (blocked) expect_identical(readLines(file.path(root, "waiting-B")), "blocked")
  writeLines("go", file.path(root, "go"))
  first$wait(timeout = 10000)
  second$wait(timeout = 10000)
  expect_true(first$get_result()$promoted)
  expect_false(second$get_result()$promoted)
  expect_true(second$get_result()$yabanci)
  expect_identical(readLines(file.path(root, "physical.txt")), "A")
  expect_identical(readLines(file.path(root, "stage-B")), "B")
  })
})

test_that("sahip marker ve atomik geçici yazım Windows yol bütçesini paylaşır", {
  env <- .ingestionEnv()
  env$.Platform <- list(OS.type = "windows")
  parent <- paste0("C:/", strrep("p", 212L))
  target <- file.path(parent, strrep("n", 24L))
  legacy <- env$file_ingestion_owner_path(target, legacy = TRUE)
  expect_gt(env$mergen_artifact_path_units(paste0(legacy, ".identity")), 259L)
  marker <- env$file_ingestion_owner_path(target)
  expect_false(identical(marker, legacy))
  expect_lte(env$mergen_artifact_path_units(paste0(marker, ".identity")), 259L)
  expect_lte(env$mergen_artifact_path_units(env$mergen_upload_mutex_path(target)), 259L)
  expect_true(legacy %in% env$file_ingestion_owner_paths(target))
  env$path_exists_relaxed <- function(p) identical(p, legacy)
  expect_identical(env$file_ingestion_owner_path(target), legacy)
  # Geçici ad hedefin uzun adına eklenmez; aynı dizinde atomik taşınır.
  root <- withr::local_tempdir()
  dest <- file.path(root, strrep("n", 24L))
  real_save <- base::saveRDS
  tmp <- NULL
  env$saveRDS <- function(object, file, ...) {
    tmp <<- file
    # Ayraç yazımı değil, aynı dizin olup olmadığı karşılaştırılır (Windows ters/düz eğik çizgi).
    expect_identical(normalizePath(dirname(file), winslash = "/", mustWork = TRUE),
      normalizePath(root, winslash = "/", mustWork = TRUE))
    expect_false(startsWith(basename(file), basename(dest)))
    expect_lte(env$mergen_artifact_path_units(file.path(parent, basename(file))), 259L)
    real_save(object, file, ...)
  }
  env$file_ingestion_write_owner(list(id = "bounded"), dest)
  expect_identical(readRDS(dest)$id, "bounded")
  expect_false(file.exists(tmp))
})

test_that("bayat terfi rezervasyonu kilit yeniden girişi olmadan devralınır", {
  env <- .ingestionEnv()
  root <- withr::local_tempdir()
  target <- file.path(root, "dest")
  stage <- file.path(root, "stage")
  writeLines("preserve", stage)
  reservation <- paste0(target, env$MERGEN_PROMOTE_RESERVATION_SUFFIX)
  expect_true(env$mergen_reservation_acquire(reservation, "2147483646-dead"))
  env$mergen_lock_owner_reclaimable <- function(...) TRUE
  env$file.link <- function(...) FALSE
  active <- list()
  real_mutex <- get("mergen_reclaim_mutex", envir = env, inherits = TRUE)
  env$mergen_reclaim_mutex <- function(path, timeout = 0, exclusive = TRUE) {
    expect_false(path %in% names(active))
    guard <- real_mutex(path, timeout, exclusive)
    if (!is.null(guard)) active[[path]] <<- guard
    guard
  }
  real_unlock <- filelock::unlock
  testthat::local_mocked_bindings(unlock = function(lock, ...) {
    # Gerçek dosya kilidi testte yeniden girişsiz bir primitif gibi izlenir.
    active <<- active[!vapply(active, identical, logical(1), y = lock)]
    real_unlock(lock, ...)
  }, .package = "filelock")
  expect_true(env$mergen_promote_staged_file(stage, target, file.exists)$ok)
  expect_identical(readLines(target), "preserve")
  expect_false(dir.exists(reservation))
})

test_that("215 birim üst dizinde doğrudan kopya marker bütçesini aşmaz", {
  env <- .ingestionEnv()
  root <- withr::local_tempdir()
  if (.Platform$OS.type == "windows") root <- shortPathName(root)
  padding <- 215L - env$mergen_artifact_path_units(root) - 1L
  skip_if(padding < 1L || padding > 255L, "Geçici kökte 215 birimlik üst dizin oluşturulamıyor")
  parent <- file.path(root, strrep("p", padding))
  expect_true(dir.create(parent))
  target <- file.path(parent, strrep("n", 24L))
  source <- withr::local_tempfile()
  bytes <- as.raw(c(0, 255, 10, 42))
  writeBin(bytes, source)
  expect_equal(env$mergen_artifact_path_units(parent), 215L)
  expect_identical(env$mergen_copy_upload_staged(source, target, root), target)
  expect_identical(readBin(target, "raw", 100L), bytes)
  expect_identical(readBin(source, "raw", 100L), bytes)
  expect_false(file.exists(env$file_ingestion_owner_path(target)))
  expect_false(file.exists(env$mergen_upload_staging_path(target)))
})

test_that("benzersiz yüklemelerin kalıcı yayın kilitleri sınırlı kalır", {
  env <- .ingestionEnv()
  root <- withr::local_tempdir()
  targets <- file.path(root, paste0("unique-", seq_len(5000L), ".txt"))
  locks <- vapply(targets, env$mergen_upload_mutex_path, character(1))
  expect_lte(length(unique(locks)), 4096L)
  expect_gt(length(unique(locks)), 1L)
  expect_identical(env$normalize_for_path_compare(unique(dirname(locks))),
    env$normalize_for_path_compare(env$mergen_upload_lock_dir()))
  expect_identical(env$mergen_upload_mutex_path(file.path(root, "NAME.TXT")),
    env$mergen_upload_mutex_path(file.path(root, "name.txt")))
  # Aynı fiziksel dizinin farklı yazımı aynı şeride girer.
  expect_identical(env$mergen_upload_mutex_path(file.path(root, ".", "name.txt")),
    env$mergen_upload_mutex_path(file.path(root, "name.txt")))
  # Dosya sistemi harf eşleri süreç yerelinden bağımsız aynı şeride girer.
  env$tolower <- function(...) stop("locale-dependent")
  for (pair in list(c("I", "i"), c("I", "\u0131"), c("\u1e9e", "\u00df"), c("\u00d6", "O\u0308")))
    expect_identical(env$mergen_upload_mutex_path(file.path(root, pair[1])),
      env$mergen_upload_mutex_path(file.path(root, pair[2])))
})

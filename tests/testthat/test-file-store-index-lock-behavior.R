# ==============================================================================
# Dosya Yolu: tests/testthat/test-file-store-index-lock-behavior.R
# Açıklama: Dosya deposu indeks kilidi davranış sözleşmesi.
#           - Normal yol: kilit alınır, ifade çalışır, kilit temizlenir.
#           - Eski (stale) kilit: çökmüş süreçten kalan kilit dizini yaşına
#             bakılarak kırılır; mutasyonlar kalıcı 5 sn gecikme + kalıcı
#             kilitsiz moda düşmez.
#           - Taze kilit: belgelenmiş erişilebilirlik-öncelikli davranış
#             korunur; timeout sonrası ifade yine de çalışır ve taze kilit
#             dizinine dokunulmaz.
#           Gerçek DB, ağ, tarayıcı veya LLM gerektirmez; tüm yollar
#           helper_load_file_store.R tarafından tempdir altına alınmıştır.
# ==============================================================================

.lock_test_prepare_runtime <- function() {
  if (exists("reset_file_store_runtime_for_tests", mode = "function", inherits = TRUE)) {
    reset_file_store_runtime_for_tests()
  } else if (exists(".file_store_force_test_paths", mode = "function", inherits = TRUE)) {
    .file_store_force_test_paths()
  }

  .lock_test_cleanup()
  invisible(TRUE)
}

.lock_test_lock_dir <- function() {
  paste0(MERGEN_INDEX_PATH, ".lock")
}

.lock_test_lock_marker <- function(lock_dir = .lock_test_lock_dir()) {
  file.path(lock_dir, "owner")
}

.lock_test_cleanup <- function() {
  unlink(.lock_test_lock_dir(), recursive = TRUE, force = TRUE)
}

.lock_test_make_lock <- function(age_sec = NULL) {
  lock_dir <- .lock_test_lock_dir()
  dir.create(lock_dir, recursive = TRUE, showWarnings = FALSE)

  marker <- .lock_test_lock_marker(lock_dir)
  pid <- if (is.null(age_sec)) Sys.getpid() else 2147483647L
  writeLines(c(paste0("pid=", pid), paste0("host=", Sys.info()[["nodename"]]), "token=test-lock"), marker, useBytes = TRUE)

  if (!is.null(age_sec)) {
    eski_zaman <- Sys.time() - age_sec
    marker_time_ok <- suppressWarnings(Sys.setFileTime(marker, eski_zaman))

    if (!isTRUE(marker_time_ok)) {
      skip("Test ortamında kilit marker dosyası mtime ayarlanamıyor.")
    }
  }

  invisible(lock_dir)
}

test_that("kilit serbestken ifade kilit altinda calisir ve kilit temizlenir", {
  .lock_test_prepare_runtime()
  withr::defer(.lock_test_cleanup())

  lock_dir <- .lock_test_lock_dir()
  lock_seen_during_expr <- FALSE

  result <- .file_store_with_index_lock({
    lock_seen_during_expr <- dir.exists(lock_dir)
    "calisti"
  })

  expect_identical(result, "calisti")
  expect_true(lock_seen_during_expr, info = "İfade çalışırken kilit dizini mevcut olmalıdır.")
  expect_false(dir.exists(lock_dir), info = "İfade bittikten sonra kilit dizini temizlenmelidir.")
})

test_that("eski (stale) kilit kirilir ve mutasyon kilidi devralir", {
  .lock_test_prepare_runtime()
  withr::defer(.lock_test_cleanup())

  lock_dir <- .lock_test_lock_dir()

  # Çökmüş bir sürecin bıraktığı eski kilidi simüle et: Windows/UNC üzerinde
  # dizin mtime yerine marker dosyası mtime değeri kullanılır.
  .lock_test_make_lock(age_sec = 3600)

  start_time <- Sys.time()
  result <- .file_store_with_index_lock(
    {
      "stale-kirildi"
    },
    timeout_sec = 5,
    poll_sec = 0.01,
    stale_lock_sec = 1
  )
  gecen_sure <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))

  expect_identical(result, "stale-kirildi")
  expect_false(
    dir.exists(lock_dir),
    info = "Eski kilit kırıldıktan ve ifade bittikten sonra kilit dizini kalmamalıdır."
  )
  expect_lt(
    gecen_sure,
    4,
    label = "Eski kilit kırma süresi (timeout'a kadar beklememeli)"
  )
})

test_that("taze kilit belgelenmis erisebilirlik-oncelikli davranisi korur", {
  .lock_test_prepare_runtime()
  withr::defer(.lock_test_cleanup())

  lock_dir <- .lock_test_lock_dir()

  # Başka bir sürecin AKTİF (taze) kilidini simüle et: marker mtime şu an.
  .lock_test_make_lock()

  result <- .file_store_with_index_lock(
    {
      "kilitsiz-devam"
    },
    timeout_sec = 0.2,
    poll_sec = 0.05,
    stale_lock_sec = 3600
  )

  expect_identical(
    result,
    "kilitsiz-devam",
    info = "Taze kilit timeout'unda ifade yine de çalışmalıdır (mevcut davranış korunur)."
  )
  expect_true(
    dir.exists(lock_dir),
    info = "Taze (aktif) kilit dizini kırılmamalı; sahibinin temizlemesi beklenir."
  )
})

test_that("kilit yalnizca marker hala bizim jetonumuzu tasiyorsa birakilir", {
  .lock_test_prepare_runtime()
  withr::defer(.lock_test_cleanup())

  lock_dir <- .lock_test_lock_dir()

  # Gecikmiş eski sahip senaryosu: kilit biz tutarken bayat sayılıp kırılır ve
  # YENİ bir sahip kendi jetonuyla yeniden alır. İfade içinde marker'ı yabancı
  # bir jetonla değiştirerek bu durumu birebir üretiyoruz.
  sonuc <- .file_store_with_index_lock({
    writeLines(
      c("pid=999999", "token=baska-sahip"),
      .lock_test_lock_marker(lock_dir),
      useBytes = TRUE
    )
    "calisti"
  })

  expect_identical(sonuc, "calisti")
  expect_true(
    dir.exists(lock_dir),
    info = "Yeni sahibin kilidi silinmemelidir (lost update koruması)."
  )
  # DİZİN yeterli değildir: bırakma yolu marker'ı silerse yeni sahip bayatlık
  # denetimi için gereken mtime bilgisini kaybeder ve kilit erken kırılabilir.
  marker <- .lock_test_lock_marker(lock_dir)
  expect_true(file.exists(marker))
  expect_true(any(grepl(
    "token=baska-sahip", readLines(marker, warn = FALSE), fixed = TRUE
  )))
})

# Regresyon: kilit alınamadığında mutasyon KİLİTSİZ çalışıyordu (lost update).
test_that("kilit dogrulanamazsa require_lock ile hata verilir", {
  .lock_test_prepare_runtime()
  withr::defer(.lock_test_cleanup())

  # Taze (aktif) kilit: bayat sayılmaz, timeout icinde alinamaz.
  .lock_test_make_lock()

  expect_error(
    .file_store_with_index_lock(
      "asla-calismamali",
      timeout_sec = 0.2,
      poll_sec = 0.05,
      stale_lock_sec = 3600,
      require_lock = TRUE
    ),
    # ASCII çapa: gerçek mesaj "İndeks kilidi alınamadı" biçimindedir.
    "kilidi al"
  )
})

test_that("kilitli bolum icindeki heartbeat marker mtime degerini tazeler", {
  .lock_test_prepare_runtime()
  withr::defer(.lock_test_cleanup())

  lock_dir <- .lock_test_lock_dir()
  marker <- .lock_test_lock_marker(lock_dir)

  .file_store_with_index_lock({
    # Marker'i yapay olarak ESKIT, sonra heartbeat ile tazele.
    Sys.setFileTime(marker, Sys.time() - 3600)
    eski <- file.info(marker)$mtime[1]
    file_store_index_lock_heartbeat()
    yeni <- file.info(marker)$mtime[1]
    expect_true(as.numeric(difftime(yeni, eski, units = "secs")) > 1000)
    invisible(NULL)
  })
})

test_that("mutasyon yardimcisi stale kilit sonrasi indeks kaydini kaybetmez", {
  .lock_test_prepare_runtime()
  withr::defer(.lock_test_cleanup())

  lock_dir <- .lock_test_lock_dir()

  # Eski kilit mevcutken gerçek bir indeks mutasyonu çalıştır.
  .lock_test_make_lock(age_sec = 3600)

  marker_key <- paste0("stale_lock_probe_", as.integer(Sys.time()))

  sonuc <- .file_store_mutate_index(function(idx) {
    idx[[marker_key]] <- list(probe = TRUE)
    idx
  })

  expect_true(
    is.list(sonuc) && !is.null(sonuc[[marker_key]]),
    info = "Stale kilit senaryosunda mutasyon sonucu kaybolmamalıdır."
  )

  yeniden_yuklenen <- .load_index()
  expect_true(
    !is.null(yeniden_yuklenen[[marker_key]]),
    info = "Mutasyon, indeks dosyasına kalıcı olarak yazılmış olmalıdır."
  )

  # Temizlik: probe kaydını indeksten kaldır.
  .file_store_mutate_index(function(idx) {
    idx[[marker_key]] <- NULL
    idx
  })
})
test_that("ölü kilit hemen devralınır; aynı sürecin bırakamadığı kilit yalnız yaşla", {
  .lock_test_prepare_runtime()
  withr::defer(.lock_test_cleanup())
  .lock_test_make_lock(age_sec = 0)
  expect_identical(.file_store_with_index_lock(TRUE, timeout_sec = 0, require_lock = TRUE), TRUE)
  lock_dir <- .lock_test_lock_dir()
  # Bu süreç senkron kritik bölümde değilken kendi PID'li marker terk edilmiştir:
  # taze iken korunur, bayatlık eşiğinden sonra geri kazanılır.
  .lock_test_make_lock()
  expect_error(.file_store_with_index_lock(stop("kritik bölüm çalıştı"), timeout_sec = 0,
    stale_lock_sec = 60, require_lock = TRUE), "kilidi al")
  expect_true(dir.exists(lock_dir))
  Sys.sleep(1.2)
  expect_identical(.file_store_with_index_lock(TRUE, timeout_sec = 0, stale_lock_sec = 1,
    require_lock = TRUE), TRUE)
})

test_that("markersız, eski biçimli ya da uzak host kilidi yalnız bayatlıktan sonra kırılır", {
  .lock_test_prepare_runtime()
  withr::defer(.lock_test_cleanup())
  lock_dir <- .lock_test_lock_dir()
  marker <- .lock_test_lock_marker(lock_dir)
  for (durum in c("markersiz", "eski", "uzak", "bozuk")) {
    dir.create(lock_dir, recursive = TRUE, showWarnings = FALSE)
    if (durum == "eski") writeLines(c("pid=2147483647", "token=eski"), marker)
    if (durum == "uzak") writeLines(c("pid=1", "host=baska-dugum", "token=uzak"), marker)
    if (durum == "bozuk") writeBin(as.raw(c(0xff, 0x00, 0x13)), marker)
    expect_error(.file_store_with_index_lock(TRUE, timeout_sec = 0, stale_lock_sec = 3600,
      require_lock = TRUE), "kilidi al", info = durum)
    if (file.exists(marker)) Sys.setFileTime(marker, Sys.time() - 7200)
    Sys.setFileTime(lock_dir, Sys.time() - 7200)
    expect_identical(.file_store_with_index_lock(TRUE, timeout_sec = 0, stale_lock_sec = 3600,
      require_lock = TRUE), TRUE, info = durum)
  }
})

test_that("kilit içinde sert öldürülen işçinin kilidi ölüm doğrulandıktan sonra devralınır", {
  skip_if_not_installed("callr")
  .lock_test_prepare_runtime()
  withr::defer(.lock_test_cleanup())
  ready <- withr::local_tempfile()
  root <- resolve_repo_root_for_tests()
  process <- callr::r_bg(function(root, index, ready) {
    source(file.path(root, "R/utils_common.R"), encoding = "UTF-8")
    source(file.path(root, "R/helpers_process_ownership.R"), encoding = "UTF-8")
    source(file.path(root, "R/config_file_store_index_lock.R"), encoding = "UTF-8")
    assign("MERGEN_INDEX_PATH", index, envir = globalenv())
    .file_store_with_index_lock({ file.create(ready); Sys.sleep(60) }, require_lock = TRUE)
  }, args = list(root = root, index = MERGEN_INDEX_PATH, ready = ready), stdout = NULL, stderr = NULL)
  withr::defer(try(process$kill(), silent = TRUE))
  deadline <- Sys.time() + 10
  while (!file.exists(ready) && process$is_alive() && Sys.time() < deadline) Sys.sleep(0.01)
  expect_true(file.exists(ready))
  expect_error(.file_store_with_index_lock(TRUE, timeout_sec = 0, require_lock = TRUE), "kilidi al")
  # Yaşlanmış ama canlı yabancı sahip çalınmaz.
  Sys.sleep(1.5)
  expect_error(.file_store_with_index_lock(TRUE, timeout_sec = 0, stale_lock_sec = 1,
    require_lock = TRUE), "kilidi al")
  process$kill()
  process$wait(timeout = 5000)
  expect_false(process$is_alive())
  expect_identical(.file_store_with_index_lock(TRUE, timeout_sec = 0, require_lock = TRUE), TRUE)
})

test_that("eski sahibin heartbeat çağrısı yeni boş kilit dizinine marker yazmaz", {
  .lock_test_prepare_runtime()
  withr::defer(.lock_test_cleanup())
  marker <- .lock_test_lock_marker()
  .file_store_with_index_lock({
    unlink(.lock_test_lock_dir(), recursive = TRUE)
    dir.create(.lock_test_lock_dir())
    expect_false(file_store_index_lock_heartbeat())
    expect_false(file.exists(marker))
    writeLines("token=yeni-sahip", marker)
  }, require_lock = TRUE)
  expect_identical(readLines(marker), "token=yeni-sahip")
})

test_that("okunamayan marker süren geri kazanım sırasında eski sahibin jetonuyla yeniden yazılmaz", {
  skip_if_not_installed("callr")
  skip_if_not_installed("filelock")
  .lock_test_prepare_runtime()
  withr::defer(.lock_test_cleanup())
  lock_dir <- .lock_test_lock_dir()
  marker <- .lock_test_lock_marker(lock_dir)
  ready <- withr::local_tempfile()
  release <- withr::local_tempfile()
  .file_store_with_index_lock({
    # Marker geçici olarak okunamaz; muteks serbestken sahip marker'ı tazeler.
    writeLines(character(), marker)
    expect_true(file_store_index_lock_heartbeat())
    expect_true(file.exists(marker))
    # Başka bir süreç geri kazanım muteksini tutarken marker yeniden yazılmaz.
    process <- callr::r_bg(function(path, ready, release) {
      lock <- filelock::lock(path)
      file.create(ready)
      while (!file.exists(release)) Sys.sleep(0.02)
      filelock::unlock(lock)
    }, args = list(path = paste0(lock_dir, ".reclaim"), ready = ready, release = release))
    withr::defer(try(process$kill(), silent = TRUE))
    deadline <- Sys.time() + 10
    while (!file.exists(ready) && process$is_alive() && Sys.time() < deadline) Sys.sleep(0.01)
    expect_true(file.exists(ready))
    unlink(marker)
    expect_false(file_store_index_lock_heartbeat())
    expect_false(file.exists(marker))
    file.create(release)
    process$wait(timeout = 5000)
    invisible(NULL)
  })
})


test_that("kilit bırakma geçici okunamazlığı muteks altında doğrular ve yabancı sahibi korur", {
  for (mode in c("transient", "unreadable", "foreign", "known", "mutex_unavailable")) {
    .lock_test_prepare_runtime()
    withr::defer(.lock_test_cleanup())
    releasing <- FALSE
    reads <- 0L
    env <- new.env(parent = environment(.file_store_with_index_lock))
    source(file.path(resolve_repo_root_for_tests(), "R/config_file_store_index_lock.R"), encoding = "UTF-8", local = env)
    env$readLines <- function(con, ...) {
      if (releasing) {
        reads <<- reads + 1L
        if (mode == "unreadable" || (mode != "known" && reads == 1L)) stop("UNC okuma")
        if (mode == "foreign") return("token=baska-sahip")
      }
      base::readLines(con, ...)
    }
    env$.file_store_with_index_lock({
      releasing <- TRUE
      if (mode == "mutex_unavailable") env$mergen_reclaim_mutex <- function(...) NULL
      TRUE
    }, require_lock = TRUE)
    expect_identical(dir.exists(.lock_test_lock_dir()), mode %in% c("unreadable", "foreign", "mutex_unavailable"), info = mode)
    releasing <- FALSE
    unlink(.lock_test_lock_dir(), recursive = TRUE)
  }
})

test_that("geri kazanım muteksi tutulurken yeni indeks sahibi yayımlanmaz", {
  skip_if_not_installed("callr")
  skip_if_not_installed("filelock")
  .lock_test_prepare_runtime()
  withr::defer(.lock_test_cleanup())
  ready <- withr::local_tempfile()
  release <- withr::local_tempfile()
  process <- callr::r_bg(function(path, ready, release) {
    lock <- filelock::lock(path)
    on.exit(filelock::unlock(lock))
    file.create(ready)
    while (!file.exists(release)) Sys.sleep(0.01)
  }, args = list(path = paste0(.lock_test_lock_dir(), ".reclaim"), ready = ready, release = release))
  withr::defer(try(process$kill(), silent = TRUE))
  deadline <- Sys.time() + 10
  while (!file.exists(ready) && process$is_alive() && Sys.time() < deadline) Sys.sleep(0.01)
  expect_true(file.exists(ready))
  expect_error(.file_store_with_index_lock(stop("mutasyon"), timeout_sec = 0,
    require_lock = TRUE), "kilidi al")
  expect_false(dir.exists(.lock_test_lock_dir()))
  file.create(release)
  process$wait(timeout = 5000)
  expect_identical(.file_store_with_index_lock("geçerli", require_lock = TRUE), "geçerli")
  expect_false(dir.exists(.lock_test_lock_dir()))
})

test_that("kullanılamayan geri kazanım muteksi indeks mutasyonuna izin vermez", {
  .lock_test_prepare_runtime()
  withr::defer(.lock_test_cleanup())
  env <- new.env(parent = environment(.file_store_with_index_lock))
  source(file.path(resolve_repo_root_for_tests(), "R/config_file_store_index_lock.R"),
    encoding = "UTF-8", local = env)
  env$mergen_reclaim_mutex <- function(...) NULL
  mutated <- FALSE
  expect_error(env$.file_store_with_index_lock({ mutated <- TRUE },
    timeout_sec = 0, require_lock = TRUE), "kilidi alınamadı")
  expect_false(mutated)
  expect_false(dir.exists(.lock_test_lock_dir()))
})

test_that("geri kazanım son silme öncesi değişen jetonu korur", {
  .lock_test_prepare_runtime()
  withr::defer(.lock_test_cleanup())
  .lock_test_make_lock(age_sec = 3600)
  env <- new.env(parent = environment(.file_store_with_index_lock))
  source(file.path(resolve_repo_root_for_tests(), "R/config_file_store_index_lock.R"),
    encoding = "UTF-8", local = env)
  env$log_warn <- function(...) writeLines("token=yeni-sahip", .lock_test_lock_marker())
  expect_error(env$.file_store_with_index_lock(stop("mutasyon"), timeout_sec = 0,
    require_lock = TRUE), "kilidi al")
  expect_identical(readLines(.lock_test_lock_marker()), "token=yeni-sahip")
})

test_that("kısa muteks çekişmesi heartbeat veya kilit bırakmayı düşürmez", {
  skip_if_not_installed("callr")
  skip_if_not_installed("filelock")
  for (operation in c("heartbeat", "release")) {
    .lock_test_prepare_runtime()
    withr::defer(.lock_test_cleanup())
    ready <- withr::local_tempfile()
    process <- NULL
    .file_store_with_index_lock({
      process <- callr::r_bg(function(path, ready) {
        lock <- filelock::lock(path)
        on.exit(filelock::unlock(lock))
        file.create(ready)
        Sys.sleep(0.2)
      }, args = list(path = paste0(.lock_test_lock_dir(), ".reclaim"), ready = ready))
      withr::defer(try(process$kill(), silent = TRUE))
      deadline <- Sys.time() + 10
      while (!file.exists(ready) && process$is_alive() && Sys.time() < deadline) Sys.sleep(0.01)
      expect_true(file.exists(ready))
      if (operation == "heartbeat") expect_true(file_store_index_lock_heartbeat())
      TRUE
    }, require_lock = TRUE)
    process$wait(timeout = 5000)
    expect_false(dir.exists(.lock_test_lock_dir()), info = operation)
    expect_identical(.file_store_with_index_lock("yeniden", require_lock = TRUE), "yeniden")
  }
})

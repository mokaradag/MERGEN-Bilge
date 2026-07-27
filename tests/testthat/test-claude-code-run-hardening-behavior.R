# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-run-hardening-behavior.R
# Açıklama: Bilge Yolaç bloklamayan çalıştırma hattının inceleme sonrası
#           sertleştirmelerinin davranış sözleşmesi:
#             - tek dizin listelemesinin gerçekten sınırlı olması,
#             - kesilmiş taramada adı geçen dosyanın diskten çözülmesi,
#             - boyut sınırı nedeniyle aktarılamayan onaylı çıktıların
#               sessizce kaybolmaması,
#             - doküman destek temizliğinin yapılandırılmış saklama süresine
#               uyması,
#             - dahili runtime bölgelerinin indirme adayı olmaması,
#             - çalıştırma sonrası tarama kesintisinin raporlanabilmesi,
#             - yeniden kullanılan runtime'da sahiplik devri,
#             - eşzamansız olmayan future planının reddedilmesi,
#             - görünürlük bekleme bütçesinin paylaşılması.
#
#           Çevrimdışı ve deterministiktir; gerçek DB/LLM/CLI/tarayıcı yoktur.
# ==============================================================================

.cc_hardening_env <- function(extra_files = character(0)) {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())

  env$`%||%` <- function(x, y) if (is.null(x)) y else x
  env$log_info <- function(...) invisible(NULL)
  env$log_warn <- function(...) invisible(NULL)
  env$log_error <- function(...) invisible(NULL)
  env$cc_log_info <- function(...) invisible(NULL)
  env$cc_log_warn <- function(...) invisible(NULL)
  env$CLAUDE_CODE_LOG_PREFIX <- "[TEST]"
  env$normalize_mcp_path <- function(path, must_exist = FALSE) {
    normalizePath(path, winslash = "/", mustWork = must_exist)
  }

  dosyalar <- c(
    "config_claude_code.R",
    "helpers_claude_code_bounded_scan.R",
    "helpers_claude_code_runtime_prepare.R",
    "helpers_claude_code_output_sync.R",
    extra_files
  )

  for (dosya in dosyalar) {
    source(file.path(repo_root, "R", dosya), encoding = "UTF-8", local = env)
  }

  env
}

# ------------------------------------------------------------------------------
# 1) TEK DİZİN LİSTELEMESİ GERÇEKTEN SINIRLI
# ------------------------------------------------------------------------------

test_that("cc_scan_list_dir_bounded düz dizinde öge sayısını gerçekten sınırlar", {
  skip_if_not_installed("processx")

  env <- .cc_hardening_env()
  kok <- withr::local_tempdir()

  for (i in seq_len(40L)) {
    writeLines("x", file.path(kok, sprintf("dosya%03d.txt", i)), useBytes = TRUE)
  }

  sonuc <- env$cc_scan_list_dir_bounded(kok, max_entries = 5L, timeout_ms = 5000L)

  expect_true(is.list(sonuc))
  expect_lte(length(sonuc$entries), 5L)
  expect_true(isTRUE(sonuc$truncated))
  expect_identical(sonuc$reason, "max_entries")
})

test_that("cc_scan_list_dir_bounded var olmayan dizinde güvenle boş döner", {
  env <- .cc_hardening_env()

  sonuc <- env$cc_scan_list_dir_bounded(
    file.path(tempdir(), "yok-boyle-bir-dizin-mergen"),
    max_entries = 10L
  )

  expect_length(sonuc$entries, 0L)
  expect_false(isTRUE(sonuc$truncated))
})

test_that("cc_list_dir_relaxed sınırlı deneme boş veya hatalıysa sınırsız yola düşmez", {
  env <- .cc_hardening_env("helpers_claude_code_directory_listing.R")
  env$list.files <- function(...) stop("sınırsız listeleme çağrılmamalı")

  env$cc_scan_list_dir_bounded <- function(...) {
    list(entries = character(0), truncated = TRUE)
  }
  bos <- env$cc_list_dir_relaxed(tempdir())
  expect_length(bos, 0L)
  expect_true(isTRUE(attr(bos, "truncated", exact = TRUE)))

  env$cc_scan_list_dir_bounded <- function(...) stop("zaman aşımı")
  hatali <- env$cc_list_dir_relaxed(tempdir())
  expect_length(hatali, 0L)
  expect_true(isTRUE(attr(hatali, "truncated", exact = TRUE)))
})

# ------------------------------------------------------------------------------
# 2) KESİLMİŞ TARAMADA ADI GEÇEN DOSYA DİSKTEN ÇÖZÜLÜR
# ------------------------------------------------------------------------------

test_that("cc_resolve_mentioned_files_on_disk yalnızca kök altındaki gerçek dosyaları döndürür", {
  env <- .cc_hardening_env()
  kok <- withr::local_tempdir()

  dir.create(file.path(kok, "z"))
  writeLines("{}", file.path(kok, "z", "config.json"), useBytes = TRUE)

  bulunan <- env$cc_resolve_mentioned_files_on_disk(
    mentions = c("z/config.json", "yok.json"),
    root = kok
  )

  expect_length(bulunan, 1L)
  expect_true(grepl("z/config\\.json$", bulunan[1]))
})

test_that("cc_resolve_mentioned_files_on_disk kaçış denemelerini reddeder", {
  env <- .cc_hardening_env()
  kok <- withr::local_tempdir()
  disari <- withr::local_tempdir()

  writeLines("gizli", file.path(disari, "gizli.txt"), useBytes = TRUE)

  bulunan <- env$cc_resolve_mentioned_files_on_disk(
    mentions = c(
      "../gizli.txt",
      file.path(disari, "gizli.txt"),
      "/etc/passwd",
      "C:/Windows/win.ini"
    ),
    root = kok
  )

  expect_length(bulunan, 0L)
})

test_that("cc_select_input_files kesilmiş taramada istenen dosyayı otomatik alt kümeye tercih eder", {
  env <- .cc_hardening_env()
  kok <- withr::local_tempdir()

  # Taramaya giren (kesilmiş) alt küme: istenen dosya BURADA YOK.
  taranan <- character(0)
  for (i in seq_len(3L)) {
    yol <- file.path(kok, sprintf("gurultu%02d.txt", i))
    writeLines("gurultu", yol, useBytes = TRUE)
    taranan <- c(taranan, yol)
  }

  dir.create(file.path(kok, "z"))
  istenen <- file.path(kok, "z", "config.json")
  writeLines("{}", istenen, useBytes = TRUE)

  secim <- env$cc_select_input_files(
    prompt = "Lütfen z/config.json dosyasını güncelle",
    files = taranan,
    file_sizes = rep(10, length(taranan)),
    root = kok
  )

  expect_identical(secim$selection_mode, "prompt")
  expect_true(any(grepl("config\\.json$", secim$files)))
})

test_that("cc_select_input_files adı geçen dosya yoksa otomatik alt kümeye düşer", {
  env <- .cc_hardening_env()
  kok <- withr::local_tempdir()

  taranan <- character(0)
  for (i in seq_len(3L)) {
    yol <- file.path(kok, sprintf("gurultu%02d.txt", i))
    writeLines("gurultu", yol, useBytes = TRUE)
    taranan <- c(taranan, yol)
  }

  secim <- env$cc_select_input_files(
    prompt = "Bu klasoru ozetle",
    files = taranan,
    file_sizes = rep(10, length(taranan)),
    root = kok
  )

  expect_identical(secim$selection_mode, "auto")
  expect_gt(length(secim$files), 0L)
})

# ------------------------------------------------------------------------------
# 3) BOYUT SINIRINI AŞAN ONAYLI ÇIKTI SESSİZCE KAYBOLMAZ
# ------------------------------------------------------------------------------

test_that("cc_plan_output_sync boyut sınırını aşan onaylı çıktıyı ayrı raporlar", {
  env <- .cc_hardening_env()
  runtime <- withr::local_tempdir()
  kaynak <- withr::local_tempdir()

  duzen <- list(
    root = runtime,
    input = file.path(runtime, "input"),
    output = file.path(runtime, "output"),
    metadata = file.path(runtime, "metadata"),
    document_support = file.path(runtime, "document_support")
  )
  dir.create(duzen$output, recursive = TRUE)

  buyuk <- file.path(duzen$output, "buyuk.bin")
  writeBin(as.raw(rep(1L, 4096L)), buyuk)

  plan <- env$cc_plan_output_sync(
    changed_files = buyuk,
    layout = duzen,
    source_workdir = kaynak,
    limits = list(max_output_file_bytes = 10, max_output_total_bytes = 10)
  )

  expect_length(plan$items, 0L)
  expect_length(plan$skipped_approved, 1L)

  sonuclar <- env$cc_output_sync_skipped_results(plan)

  expect_length(sonuclar, 1L)
  expect_false(isTRUE(sonuclar[[1]]$success))
  expect_true(nzchar(sonuclar[[1]]$error))
})

test_that("cc_output_sync_skipped_results atlanan onaylı çıktı yoksa boş döner", {
  env <- .cc_hardening_env()

  expect_length(env$cc_output_sync_skipped_results(list()), 0L)
  expect_length(
    env$cc_output_sync_skipped_results(list(skipped_approved = list())),
    0L
  )
})

test_that("cc_plan_output_sync input ve runtime kökü değişikliklerini reddeder", {
  env <- .cc_hardening_env()
  runtime <- withr::local_tempdir()
  kaynak <- withr::local_tempdir()
  duzen <- list(
    root = runtime,
    input = file.path(runtime, "input"),
    output = file.path(runtime, "output"),
    metadata = file.path(runtime, "metadata"),
    document_support = file.path(runtime, "document_support")
  )
  dir.create(duzen$input)
  dir.create(duzen$output)
  input <- file.path(duzen$input, "girdi.txt")
  root_file <- file.path(runtime, "cli.log")
  writeLines("değişti", input, useBytes = TRUE)
  writeLines("artifact", root_file, useBytes = TRUE)

  plan <- env$cc_plan_output_sync(c(input, root_file), duzen, kaynak)

  expect_length(plan$items, 0L)
  expect_setequal(plan$skipped, c(input, root_file))
})

test_that("cc_apply_output_sync_plan var olan symlink hedefini izlemez", {
  skip_on_os("windows")
  env <- .cc_hardening_env()
  kaynak <- withr::local_tempdir()
  disari <- withr::local_tempdir()
  runtime <- withr::local_tempdir()
  cikti <- file.path(runtime, "rapor.txt")
  dis_hedef <- file.path(disari, "onemli.txt")
  hedef <- file.path(kaynak, "rapor.txt")
  writeLines("yeni", cikti, useBytes = TRUE)
  writeLines("koru", dis_hedef, useBytes = TRUE)
  expect_true(file.symlink(dis_hedef, hedef))

  plan <- list(
    items = list(list(source_path = cikti, dest_path = hedef, size = 4)),
    source_workdir = kaynak
  )
  sonuc <- env$cc_apply_output_sync_plan(plan)

  expect_false(isTRUE(sonuc[[1]]$success))
  expect_identical(readLines(dis_hedef, warn = FALSE), "koru")
})

# ------------------------------------------------------------------------------
# 4) DOKÜMAN DESTEK TEMİZLİĞİ YAPILANDIRILMIŞ SAKLAMA SÜRESİNE UYAR
# ------------------------------------------------------------------------------

test_that("cc_cleanup_stale_document_support_dirs yapılandırılmış saklama süresini kullanır", {
  env <- .cc_hardening_env()

  kok <- file.path(
    tempdir(), "claude_code_runtime", "user_test_retention", "document_support"
  )
  dir.create(kok, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(dirname(kok), recursive = TRUE, force = TRUE), add = TRUE)

  eski <- file.path(kok, "eski_destek")
  dir.create(eski, showWarnings = FALSE)
  Sys.setFileTime(eski, Sys.time() - 3600)

  # Varsayılan 6 saatlik süre ile silinmez.
  env$cc_cleanup_stale_document_support_dirs(user_id = "test_retention")
  expect_true(dir.exists(eski))

  # Operatör saklama süresini düşürdüğünde silinmelidir.
  onceki <- if (exists("claude_code_runtime_limits", envir = env, inherits = FALSE)) {
    get("claude_code_runtime_limits", envir = env)
  } else {
    list()
  }
  onceki$runtime_retention_sec <- 60
  assign("claude_code_runtime_limits", onceki, envir = env)

  env$cc_cleanup_stale_document_support_dirs(user_id = "test_retention")
  expect_false(dir.exists(eski))
})

# ------------------------------------------------------------------------------
# 5) DAHİLİ RUNTIME BÖLGELERİ İNDİRME ADAYI DEĞİLDİR
# ------------------------------------------------------------------------------

test_that("cc_filter_download_candidates metadata ve doküman destek dosyalarını eler", {
  env <- .cc_hardening_env(extra_files = "helpers_claude_code_run_completion.R")
  runtime <- withr::local_tempdir()

  duzen <- list(
    root = runtime,
    input = file.path(runtime, "input"),
    output = file.path(runtime, "output"),
    metadata = file.path(runtime, "metadata"),
    document_support = file.path(runtime, "document_support")
  )
  for (yol in duzen) dir.create(yol, recursive = TRUE, showWarnings = FALSE)

  cikti <- file.path(duzen$output, "rapor.txt")
  lease <- file.path(duzen$metadata, "active-run-x.lease")
  destek <- file.path(duzen$document_support, "ozet.txt")

  for (yol in c(cikti, lease, destek)) writeLines("veri", yol, useBytes = TRUE)

  suzme <- env$cc_filter_download_candidates(
    paths = c(cikti, lease, destek),
    layout = duzen,
    limits = list()
  )

  expect_true(cikti %in% suzme$paths)
  expect_false(lease %in% suzme$paths)
  expect_false(destek %in% suzme$paths)
  expect_length(suzme$rejected_zone, 2L)
})

test_that("cc_filter_download_candidates boyut sınırlarını staging öncesinde uygular", {
  env <- .cc_hardening_env(extra_files = "helpers_claude_code_run_completion.R")
  runtime <- withr::local_tempdir()

  duzen <- list(
    root = runtime,
    input = file.path(runtime, "input"),
    output = file.path(runtime, "output"),
    metadata = file.path(runtime, "metadata"),
    document_support = file.path(runtime, "document_support")
  )
  dir.create(duzen$output, recursive = TRUE, showWarnings = FALSE)

  kucuk <- file.path(duzen$output, "kucuk.txt")
  buyuk <- file.path(duzen$output, "buyuk.bin")
  writeLines("a", kucuk, useBytes = TRUE)
  writeBin(as.raw(rep(1L, 8192L)), buyuk)

  suzme <- env$cc_filter_download_candidates(
    paths = c(kucuk, buyuk),
    layout = duzen,
    limits = list(max_output_file_bytes = 1024, max_output_total_bytes = 1024)
  )

  expect_true(kucuk %in% suzme$paths)
  expect_false(buyuk %in% suzme$paths)
  expect_true(buyuk %in% suzme$rejected_size)
})

test_that("cc_filter_download_candidates düzen verilmezse bölge süzgeci uygulamaz", {
  env <- .cc_hardening_env(extra_files = "helpers_claude_code_run_completion.R")
  kok <- withr::local_tempdir()

  yol <- file.path(kok, "serbest.txt")
  writeLines("veri", yol, useBytes = TRUE)

  suzme <- env$cc_filter_download_candidates(paths = yol, layout = NULL, limits = list())

  expect_identical(suzme$paths, yol)
  expect_length(suzme$rejected_zone, 0L)
})

# ------------------------------------------------------------------------------
# 6) ÇALIŞTIRMA SONRASI TARAMA KESİNTİSİ RAPORLANABİLİR
# ------------------------------------------------------------------------------

test_that("diff_claude_code_workdir_snapshot tarama meta verisini sonuca iliştirir", {
  skip_if_not_installed("processx")

  repo_root <- resolve_repo_root_for_tests()
  env <- .cc_hardening_env()
  env$canonicalize_claude_code_file_path <- function(path) {
    normalizePath(path, winslash = "/", mustWork = FALSE)
  }
  env$deduplicate_claude_code_file_paths <- function(paths) unique(paths)

  source(
    file.path(repo_root, "R", "helpers_claude_code_workdir_scan.R"),
    encoding = "UTF-8", local = env
  )

  kok <- withr::local_tempdir()
  for (i in seq_len(12L)) {
    writeLines("veri", file.path(kok, sprintf("cikti%02d.txt", i)), useBytes = TRUE)
  }

  degisenler <- env$diff_claude_code_workdir_snapshot(
    before_snapshot = list(),
    workdir = kok,
    limits = list(output_scan_max_files = 3)
  )

  tarama <- attr(degisenler, "scan", exact = TRUE)

  expect_true(is.list(tarama))
  expect_true(isTRUE(tarama$truncated))
  expect_true(nzchar(as.character(tarama$truncated_reason)[1]))
})

test_that("cc_report_output_scan_truncation kesilmemiş taramayı başarısız saymaz", {
  env <- .cc_hardening_env(extra_files = "helpers_claude_code_run_completion.R")

  expect_false(
    env$cc_report_output_scan_truncation(
      ctx = list(),
      outputs = list(output_scan_truncated = FALSE)
    )
  )
})

# ------------------------------------------------------------------------------
# 7) YENİDEN KULLANILAN RUNTIME'DA SAHİPLİK DEVRİ
# ------------------------------------------------------------------------------

.cc_ownership_env <- function() {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(x, y) if (is.null(x)) y else x

  # Dosya, tepe seviyede yalnızca yardımcı tanımları içerir.
  source(
    file.path(repo_root, "R", "helpers_claude_code_run_prepare_task.R"),
    encoding = "UTF-8", local = env
  )

  env
}

test_that("sahiplik işareti yokken yeniden kullanım engellenmez", {
  env <- .cc_ownership_env()
  runtime <- withr::local_tempdir()

  expect_true(env$cc_runtime_ownership_is(runtime, "istek-1"))
})

test_that("yeni çalıştırma sahipliği devraldığında eski hazırlık sahibi değildir", {
  env <- .cc_ownership_env()
  runtime <- withr::local_tempdir()

  isaret <- env$cc_claim_runtime_ownership(runtime, "istek-1")
  expect_true(nzchar(isaret))
  expect_true(env$cc_runtime_ownership_is(runtime, "istek-1"))

  env$cc_claim_runtime_ownership(runtime, "istek-2")

  expect_false(env$cc_runtime_ownership_is(runtime, "istek-1"))
  expect_true(env$cc_runtime_ownership_is(runtime, "istek-2"))
})

test_that("girdi kopyası sahipliği her dosya arasında yeniden doğrular", {
  env <- .cc_hardening_env()
  kaynak <- withr::local_tempdir()
  hedef <- withr::local_tempdir()
  dosyalar <- file.path(kaynak, c("bir.txt", "iki.txt"))
  writeLines("eski-bir", dosyalar[1], useBytes = TRUE)
  writeLines("eski-iki", dosyalar[2], useBytes = TRUE)
  writeLines("yeni-iki", file.path(hedef, "iki.txt"), useBytes = TRUE)

  kontrol_sayisi <- 0L
  sahiplik_dogrula <- function() {
    kontrol_sayisi <<- kontrol_sayisi + 1L
    if (kontrol_sayisi >= 3L) stop("sahiplik kaybedildi", call. = FALSE)
  }

  expect_error(
    env$cc_copy_files_to_runtime_input(
      files = dosyalar,
      relatives = basename(dosyalar),
      input_dir = hedef,
      ownership_guard = sahiplik_dogrula
    ),
    "sahiplik kaybedildi"
  )

  expect_identical(readLines(file.path(hedef, "iki.txt"), warn = FALSE), "yeni-iki")
  expect_identical(kontrol_sayisi, 3L)
})

test_that("çalıştırma sonrası diff hatası çıktı işlemeyi başarısız kılar", {
  env <- .cc_hardening_env(extra_files = "helpers_claude_code_run_completion.R")
  runtime <- withr::local_tempdir()
  toplama_cagrildi <- FALSE

  env$diff_claude_code_workdir_snapshot <- function(...) stop("diff okunamadı")
  env$cc_collect_streaming_run_downloads <- function(...) {
    toplama_cagrildi <<- TRUE
    list()
  }

  expect_error(
    env$cc_process_run_outputs(list(
      before_snapshot = list(), runtime_workdir = runtime,
      source_workdir = runtime, mirrored = FALSE, limits = list()
    )),
    "diff okunamadı"
  )
  expect_false(toplama_cagrildi)
})

# ------------------------------------------------------------------------------
# 8) EŞZAMANSIZ OLMAYAN FUTURE PLANI REDDEDİLİR
# ------------------------------------------------------------------------------

test_that("cc_future_plan_is_async sequential planı eşzamansız saymaz", {
  skip_if_not_installed("future")

  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(x, y) if (is.null(x)) y else x
  env$cc_log_info <- function(...) invisible(NULL)
  env$cc_log_warn <- function(...) invisible(NULL)
  env$log_error <- function(...) invisible(NULL)
  env$CLAUDE_CODE_LOG_PREFIX <- "[TEST]"
  env$CLAUDE_CODE_LIMIT_MESSAGE <- "sinir"
  env$cc_runtime_limit <- function(name, default_value = Inf, limits = NULL) default_value

  source(
    file.path(repo_root, "R", "helpers_claude_code_run_dispatch.R"),
    encoding = "UTF-8", local = env
  )

  onceki <- future::plan()
  on.exit(future::plan(onceki), add = TRUE)

  future::plan(future::sequential)
  expect_false(env$cc_future_plan_is_async())
})

test_that("cc_dispatch_run_preparation eşzamansız plan yoksa çalıştırmayı reddeder", {
  skip_if_not_installed("future")

  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(x, y) if (is.null(x)) y else x
  env$cc_log_info <- function(...) invisible(NULL)
  env$cc_log_warn <- function(...) invisible(NULL)
  env$log_error <- function(...) invisible(NULL)
  env$CLAUDE_CODE_LOG_PREFIX <- "[TEST]"
  env$CLAUDE_CODE_LIMIT_MESSAGE <- "sinir"
  env$cc_runtime_limit <- function(name, default_value = Inf, limits = NULL) default_value

  source(
    file.path(repo_root, "R", "helpers_claude_code_run_dispatch.R"),
    encoding = "UTF-8", local = env
  )

  bloke_mesajlari <- new.env(parent = emptyenv())
  bloke_mesajlari$mesajlar <- character(0)

  env$cc_is_active_run <- function(rv, request_id) TRUE
  env$cc_send_run_blocked_message <- function(session, ns, message) {
    bloke_mesajlari$mesajlar <- c(bloke_mesajlari$mesajlar, message)
    invisible(TRUE)
  }
  env$cc_finalize_if_active <- function(...) invisible(TRUE)
  env$tracked_future_promise <- function(...) {
    stop("Eşzamansız plan yokken worker gönderilmemelidir.")
  }

  onceki <- future::plan()
  on.exit(future::plan(onceki), add = TRUE)
  future::plan(future::sequential)

  ctx <- list(
    session = list(token = "t", sendCustomMessage = function(...) invisible(NULL)),
    ns = function(x) x,
    rv = new.env(parent = emptyenv()),
    run_request_id = "istek-1",
    finalize_streaming = function(...) invisible(TRUE),
    prompt = "merhaba",
    workdir = tempdir(),
    user_id = 1L
  )

  sonuc <- env$cc_dispatch_run_preparation(ctx)

  expect_false(isTRUE(sonuc))
  expect_length(bloke_mesajlari$mesajlar, 1L)
  expect_true(grepl("havuz", bloke_mesajlari$mesajlar[1], fixed = TRUE))
})

# ------------------------------------------------------------------------------
# 9) GÖRÜNÜRLÜK BEKLEME BÜTÇESİ PAYLAŞILIR
# ------------------------------------------------------------------------------

test_that("cc_with_path_visibility_budget toplam bekleme bütçesini paylaştırır", {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(x, y) if (is.null(x)) y else x
  env$log_warn <- function(...) invisible(NULL)
  env$log_info <- function(...) invisible(NULL)
  env$CLAUDE_CODE_LOG_PREFIX <- "[TEST]"
  env$cc_runtime_limit <- function(name, default_value = Inf, limits = NULL) default_value

  source(
    file.path(repo_root, "R", "helpers_claude_code_downloads.R"),
    encoding = "UTF-8", local = env
  )

  yok <- file.path(tempdir(), "kesinlikle-yok-mergen-bilge.txt")

  baslangic <- Sys.time()
  env$cc_with_path_visibility_budget(
    {
      for (i in seq_len(6L)) env$cc_wait_for_path_visible(yok)
    },
    budget_ms = 300
  )
  gecen_ms <- as.numeric(difftime(Sys.time(), baslangic, units = "secs")) * 1000

  # Altı ayrı çağrı ayrı ayrı 300 ms harcasaydı ~1800 ms sürerdi.
  expect_lt(gecen_ms, 1200)
})

test_that("cc_path_visibility_budget_remaining pencere dışında NULL döner", {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(x, y) if (is.null(x)) y else x
  env$log_warn <- function(...) invisible(NULL)
  env$log_info <- function(...) invisible(NULL)
  env$CLAUDE_CODE_LOG_PREFIX <- "[TEST]"
  env$cc_runtime_limit <- function(name, default_value = Inf, limits = NULL) default_value

  source(
    file.path(repo_root, "R", "helpers_claude_code_downloads.R"),
    encoding = "UTF-8", local = env
  )

  expect_null(env$cc_path_visibility_budget_remaining())
})

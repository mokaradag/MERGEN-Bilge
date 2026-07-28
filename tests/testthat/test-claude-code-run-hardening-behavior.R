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
    "helpers_claude_code_input_matching.R",
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
  # Plan yollari normalize edilmis (ileri bolu, Windows'ta 8.3 kisa ad uzun
  # forma acilmis) halde dondurur. Beklenti de ayni normalizasyondan gecmelidir;
  # aksi halde Windows'ta ham tempdir() kisa adi ile karsilastirilir ve test
  # gercek bir hata olmadigi halde basarisiz olur.
  beklenen <- vapply(c(input, root_file), env$.cc_scan_norm, character(1), USE.NAMES = FALSE)
  expect_setequal(plan$skipped, beklenen)
})

test_that("cc_apply_output_sync_plan var olan symlink hedefini izlemez", {
  env <- .cc_hardening_env()
  kaynak <- withr::local_tempdir()
  disari <- withr::local_tempdir()
  runtime <- withr::local_tempdir()
  cikti <- file.path(runtime, "rapor.txt")
  dis_hedef <- file.path(disari, "onemli.txt")
  writeLines("yeni", cikti, useBytes = TRUE)
  writeLines("koru", dis_hedef, useBytes = TRUE)

  # Windows'ta DOSYA symlink'i yönetici hakkı ister; aynı güvenlik sözleşmesi
  # (var olan bağlantı hedefi izlenerek onaylı kök dışındaki dosya EZİLEMEZ)
  # yönetici hakkı gerektirmeyen dizin junction'ı ile doğrulanır.
  if (.Platform$OS.type == "windows") {
    baglanti_dizin <- file.path(kaynak, "dis")
    expect_true(isTRUE(suppressWarnings(tryCatch(
      Sys.junction(disari, baglanti_dizin),
      error = function(e) FALSE
    ))))
    hedef <- file.path(baglanti_dizin, "onemli.txt")
  } else {
    hedef <- file.path(kaynak, "rapor.txt")
    expect_true(file.symlink(dis_hedef, hedef))
  }

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

# ------------------------------------------------------------------------------
# 10) KESİLMİŞ/BOŞ TARAMADA BİLE İSTENEN DOSYA DİSKTEN ÇÖZÜLÜR
# ------------------------------------------------------------------------------

test_that("cc_select_input_files bos taramada bile istenen dosyayi diskten cozer", {
  env <- .cc_hardening_env()
  kok <- withr::local_tempdir()

  dir.create(file.path(kok, "z"))
  istenen <- file.path(kok, "z", "config.json")
  writeLines("{}", istenen, useBytes = TRUE)

  # Tarama kökte HİÇ dosya bulamamış gibi davranır (files = character(0));
  # önceki davranışta bu durum erken bir bos sonuçla çıkardı ve prompt'ta
  # açıkça istenen dosya hiç diskten çözülmezdi.
  secim <- env$cc_select_input_files(
    prompt = "Lütfen z/config.json dosyasını güncelle",
    files = character(0),
    file_sizes = numeric(0),
    root = kok
  )

  expect_identical(secim$selection_mode, "prompt")
  expect_true(any(grepl("config\\.json$", secim$files)))
})

test_that("cc_select_input_files kok verilmezse ve tarama bosşsa güvenle boş döner", {
  env <- .cc_hardening_env()

  secim <- env$cc_select_input_files(
    prompt = "herhangi bir şey",
    files = character(0),
    root = ""
  )

  expect_length(secim$files, 0L)
  expect_identical(secim$selection_mode, "none")
})

# ------------------------------------------------------------------------------
# 11) İSTENEN DOSYA BOYUT SINIRINI AŞARSA SESSİZCE YUTULMAZ
# ------------------------------------------------------------------------------

test_that("cc_select_input_files boyutu asan ACIKÇA istenen dosyayi required_skipped isaretler", {
  env <- .cc_hardening_env()
  kok <- withr::local_tempdir()

  buyuk <- file.path(kok, "buyuk.csv")
  writeBin(as.raw(rep(1L, 4096L)), buyuk)

  secim <- env$cc_select_input_files(
    prompt = "buyuk.csv dosyasini incele",
    files = buyuk,
    file_sizes = 4096,
    root = kok,
    limits = list(max_input_file_bytes = 100)
  )

  expect_length(secim$files, 0L)
  expect_true("buyuk.csv" %in% secim$required_skipped)
})

test_that("cc_select_input_files auto modda boyutu asan dosyayi required_skipped saymaz", {
  env <- .cc_hardening_env()
  kok <- withr::local_tempdir()

  buyuk <- file.path(kok, "otomatik.csv")
  writeBin(as.raw(rep(1L, 4096L)), buyuk)

  secim <- env$cc_select_input_files(
    prompt = "bu klasoru ozetle",
    files = buyuk,
    file_sizes = 4096,
    root = kok,
    limits = list(max_input_file_bytes = 100)
  )

  expect_identical(secim$selection_mode, "auto")
  expect_length(secim$required_skipped, 0L)
})

test_that("mirror_directory_to_local_workspace boyutu asan gerekli girdide basarisiz doner", {
  env <- .cc_hardening_env(extra_files = "helpers_claude_code_runtime_workdir.R")
  kaynak <- withr::local_tempdir()
  hedef <- withr::local_tempdir()

  buyuk <- file.path(kaynak, "buyuk.csv")
  writeBin(as.raw(rep(1L, 4096L)), buyuk)

  sonuc <- env$mirror_directory_to_local_workspace(
    source_dir = kaynak,
    target_dir = hedef,
    prompt = "buyuk.csv dosyasini incele",
    limits = list(max_input_file_bytes = 100)
  )

  expect_false(isTRUE(sonuc$ok))
  expect_true(grepl("boyut sınırını aştığı", sonuc$message, fixed = TRUE))
})

# ------------------------------------------------------------------------------
# 12) MENTION ÇIKARIMI: BOŞLUKLU/TIRNAKLI DOSYA ADLARI VE HARF BÜYÜKLÜĞÜ
# ------------------------------------------------------------------------------

test_that("cc_extract_prompt_file_mentions tirnakli bosluklu dosya adini butun yakalar", {
  env <- .cc_hardening_env()

  mentions <- env$cc_extract_prompt_file_mentions(
    'Lutfen "reports/Q1 budget.csv" dosyasini guncelle'
  )

  expect_true("reports/Q1 budget.csv" %in% mentions)
})

test_that("cc_extract_prompt_file_mentions harf buyuklugunu korur", {
  env <- .cc_hardening_env()

  mentions <- env$cc_extract_prompt_file_mentions("Data/Report.CSV dosyasini incele")

  expect_true("Data/Report.CSV" %in% mentions)
  expect_false("data/report.csv" %in% mentions)
})

test_that("cc_select_input_files tirnakli bosluklu dosya adini diskten cozer", {
  env <- .cc_hardening_env()
  kok <- withr::local_tempdir()

  dir.create(file.path(kok, "reports"))
  istenen <- file.path(kok, "reports", "Q1 budget.csv")
  writeLines("veri", istenen, useBytes = TRUE)

  secim <- env$cc_select_input_files(
    prompt = 'Lutfen "reports/Q1 budget.csv" dosyasini guncelle',
    files = character(0),
    root = kok
  )

  expect_true(any(grepl("Q1 budget\\.csv$", secim$files)))
})

test_that("cc_select_input_files case-sensitive dosya sisteminde harf buyuklugunu korur", {
  # NTFS de dahil olmak uzere hedef dosya sistemlerinin tumu harf buyuklugunu
  # KORUR (arama case-insensitive olsa bile). Bu yuzden secim sonucu diskteki
  # ozgun adi dondurmelidir; test artik Windows'ta da calisir.
  env <- .cc_hardening_env()
  kok <- withr::local_tempdir()

  dir.create(file.path(kok, "Data"))
  istenen <- file.path(kok, "Data", "Report.CSV")
  writeLines("veri", istenen, useBytes = TRUE)

  secim <- env$cc_select_input_files(
    prompt = "Data/Report.CSV dosyasini incele",
    files = character(0),
    root = kok
  )

  expect_true(any(grepl("Report\\.CSV$", secim$files)))
})

# ------------------------------------------------------------------------------
# 13) DAHİLİ RUNTIME BÖLGELERİ YALNIZCA KÖK DÜZEYİNDE HARİÇ TUTULUR
# ------------------------------------------------------------------------------

test_that("cc_snapshot_run_output_area output altindaki gercek 'metadata' dizinini hariç tutmaz", {
  skip_if_not_installed("digest")
  env <- .cc_hardening_env(extra_files = "helpers_claude_code_workdir_scan.R")
  runtime <- withr::local_tempdir()

  # output/metadata GERÇEK bir üretilen alt dizindir; runtime kökündeki
  # dahili "metadata" bölmesiyle karıştırılıp basename ile hariç tutulmamalı.
  ic_ice <- file.path(runtime, "output", "metadata")
  dir.create(ic_ice, recursive = TRUE)
  writeLines("veri", file.path(ic_ice, "rapor.json"), useBytes = TRUE)

  snapshot <- env$cc_snapshot_run_output_area(runtime, mirrored = TRUE)
  yollar <- if (length(snapshot)) vapply(snapshot, function(x) x$path, character(1)) else character(0)

  expect_true(any(grepl("output/metadata/rapor\\.json$", yollar)))
})

test_that("cc_snapshot_run_output_area kok duzeyindeki dahili metadata bolmesini haric tutar", {
  skip_if_not_installed("digest")
  env <- .cc_hardening_env(extra_files = "helpers_claude_code_workdir_scan.R")
  runtime <- withr::local_tempdir()

  kok_metadata <- file.path(runtime, "metadata")
  dir.create(kok_metadata, recursive = TRUE)
  writeLines("lease", file.path(kok_metadata, "runtime-owner"), useBytes = TRUE)
  dir.create(file.path(runtime, "output"), recursive = TRUE)

  snapshot <- env$cc_snapshot_run_output_area(runtime, mirrored = TRUE)
  yollar <- if (length(snapshot)) vapply(snapshot, function(x) x$path, character(1)) else character(0)

  expect_false(any(grepl("/metadata/runtime-owner$", yollar)))
})

# ------------------------------------------------------------------------------
# 14) İÇERİK İMZASI: AYNI MTIME/BOYUTTA GİZLİ İÇERİK DEĞİŞİKLİĞİ YAKALANIR
# ------------------------------------------------------------------------------

test_that("diff_claude_code_workdir_snapshot ayni mtime/boyutta icerik degisikligini yakalar", {
  skip_if_not_installed("digest")
  env <- .cc_hardening_env(extra_files = "helpers_claude_code_workdir_scan.R")

  kok <- withr::local_tempdir()
  dosya <- file.path(kok, "rapor.txt")
  writeLines("ESKI-ICERIK", dosya, useBytes = TRUE)

  once <- env$snapshot_claude_code_workdir_files(kok)

  # Ayni boyutta farklı içerik yaz, sonra mtime'i eski değere geri al
  # (cp -p / arşiv çıkarma gibi zaman damgasını koruyan araçları taklit eder).
  eski_mtime <- file.info(dosya)$mtime[1]
  writeLines("YENI-ICERIK", dosya, useBytes = TRUE)
  Sys.setFileTime(dosya, eski_mtime)

  degisenler <- env$diff_claude_code_workdir_snapshot(before_snapshot = once, workdir = kok)

  expect_true(any(grepl("rapor\\.txt$", degisenler)))
})

test_that("diff_claude_code_workdir_snapshot degismeyen dosyayi degisen saymaz", {
  skip_if_not_installed("digest")
  env <- .cc_hardening_env(extra_files = "helpers_claude_code_workdir_scan.R")

  kok <- withr::local_tempdir()
  dosya <- file.path(kok, "sabit.txt")
  writeLines("ayni-icerik", dosya, useBytes = TRUE)

  once <- env$snapshot_claude_code_workdir_files(kok)
  degisenler <- env$diff_claude_code_workdir_snapshot(before_snapshot = once, workdir = kok)

  expect_length(degisenler, 0L)
})

# ------------------------------------------------------------------------------
# 15) İÇ İÇE (NESTED) KOPYALANMIŞ DOKÜMANLAR KEŞFEDİLİR
# ------------------------------------------------------------------------------

test_that("list_claude_code_binary_documents ic ice kopyalanan dokumani bulur", {
  env <- .cc_hardening_env(extra_files = "helpers_claude_code_document_extractors.R")
  kok <- withr::local_tempdir()

  dir.create(file.path(kok, "reports"))
  belge <- file.path(kok, "reports", "quarterly.pdf")
  writeLines("sahte-pdf-icerigi", belge, useBytes = TRUE)

  bulunan <- env$list_claude_code_binary_documents(kok, extensions = c("pdf"))

  expect_true(any(grepl("quarterly\\.pdf$", bulunan)))
})

test_that("workdir_has_binary_documents ic ice kopyalanan dokumani algilar", {
  env <- .cc_hardening_env(extra_files = c(
    "helpers_claude_code_document_extractors.R",
    "helpers_claude_code_model_config.R"
  ))
  kok <- withr::local_tempdir()

  dir.create(file.path(kok, "input", "reports"), recursive = TRUE)
  belge <- file.path(kok, "input", "reports", "quarterly.pdf")
  writeLines("sahte-pdf-icerigi", belge, useBytes = TRUE)

  expect_true(env$workdir_has_binary_documents(file.path(kok, "input"), extensions = c("pdf")))
})

# ------------------------------------------------------------------------------
# 16) ÇIKTI SENKRONİZASYON İSTİSNALARI YUTULMAZ
# ------------------------------------------------------------------------------

test_that("sync hatasi cikti islemeyi basarisiz kilar (yutulmaz)", {
  env <- .cc_hardening_env(extra_files = "helpers_claude_code_run_completion.R")
  runtime <- withr::local_tempdir()

  env$diff_claude_code_workdir_snapshot <- function(...) character(0)
  env$cc_collect_streaming_run_downloads <- function(...) list()
  env$sync_claude_runtime_workdir_back <- function(...) stop("sistemik yol hatasi")

  expect_error(
    env$cc_process_run_outputs(list(
      before_snapshot = list(), runtime_workdir = runtime,
      source_workdir = runtime, mirrored = TRUE, limits = list()
    )),
    "sistemik yol hatasi"
  )
})

# ------------------------------------------------------------------------------
# 17) ÇIKTI AKTARIM KORUMA DOSYASI OLUŞTURULAMAZSA WORKER GÖNDERİLMEZ
# ------------------------------------------------------------------------------

test_that("guard dosyasi olusturulamazsa worker gonderilmeden acikca basarisiz olunur", {
  env <- .cc_hardening_env(extra_files = "helpers_claude_code_run_completion.R")

  worker_cagrildi <- FALSE
  rapor_edildi <- new.env(parent = emptyenv())
  rapor_edildi$hata <- NULL

  env$tracked_future_promise <- function(...) {
    worker_cagrildi <<- TRUE
    stop("worker hiç çağrılmamalı")
  }
  env$cc_report_output_processing_failure <- function(ctx, error) {
    rapor_edildi$hata <- error
    invisible(TRUE)
  }
  env$file.create <- function(...) FALSE

  ctx <- list(
    session = list(token = "t"),
    ns = function(x) x,
    rv = new.env(parent = emptyenv()),
    env = list(runtime_layout = list(metadata = tempdir()), request_id = "rid-guard"),
    ayristirma = list(tool_uses = list())
  )

  env$cc_dispatch_run_output_processing(ctx)

  expect_false(worker_cagrildi)
  expect_false(is.null(rapor_edildi$hata))
})

# ------------------------------------------------------------------------------
# 18) SINIRLI DİZİN LİSTELEME BAŞARISIZLIĞI SESSİZ "BOŞ DİZİN" GİBİ GÖSTERİLMEZ
# ------------------------------------------------------------------------------

test_that("list_directory_contents sinirli listeleyici basarisiz olunca sessiz bos dizin gostermez", {
  env <- .cc_hardening_env(extra_files = "helpers_claude_code_directory_listing.R")
  kok <- withr::local_tempdir()

  env$cc_scan_list_dir_bounded <- function(...) {
    list(
      entries = character(0), truncated = FALSE, reason = "",
      ok = FALSE, error = "listeleyici kod 1 ile sonlandi"
    )
  }

  sonuc <- env$list_directory_contents(kok, max_items = 50L)

  # Gerçek bir listeleme başarısızlığı (sinirli$ok == FALSE) artık success =
  # FALSE ile açıkça raporlanır; UI bunu sessiz "boş dizin" yerine gerçek bir
  # hata mesajı olarak gösterir (bkz. cc_build_dir_contents_ui()).
  expect_false(isTRUE(sonuc$success))
  expect_true(nzchar(sonuc$error))
  expect_true(isTRUE(sonuc$truncated))
  expect_true(!is.null(sonuc$truncated_reason) && nzchar(sonuc$truncated_reason))
})

test_that("list_directory_contents gercekten bos dizinde truncated=FALSE doner", {
  env <- .cc_hardening_env(extra_files = "helpers_claude_code_directory_listing.R")
  kok <- withr::local_tempdir()

  sonuc <- env$list_directory_contents(kok, max_items = 50L)

  expect_true(isTRUE(sonuc$success))
  expect_false(isTRUE(sonuc$truncated))
})

# ------------------------------------------------------------------------------
# 19) EŞZAMANSIZ PLANDA BİLE GÖNDERİM ANINDA SENKRON HATA AÇIKÇA SONLANDIRILIR
# ------------------------------------------------------------------------------

test_that("cc_dispatch_run_preparation gonderim aninda senkron hata verirse hazirlik acikca sonlandirilir", {
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
  env$cc_release_runtime_lease <- function(...) invisible(TRUE)
  env$cc_claim_runtime_ownership <- function(...) ""
  env$cc_build_run_prepare_request <- function(...) list()
  env$cc_run_prepare_worker_globals <- function(...) list()

  # Plan ASENKRON gibi görünsün (cc_future_plan_is_async() TRUE dönsün) ama
  # tracked_future_promise() GÖNDERİM ANINDA senkron hata versin (ör. küme
  # çökmüş veya globals serileştirilemiyor).
  env$cc_future_plan_is_async <- function() TRUE
  env$tracked_future_promise <- function(...) stop("worker kumesi coktu")

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

  expect_error(env$cc_dispatch_run_preparation(ctx), NA)
  expect_length(bloke_mesajlari$mesajlar, 1L)
  expect_true(grepl("worker kumesi coktu", bloke_mesajlari$mesajlar[1], fixed = TRUE))
})

# ------------------------------------------------------------------------------
# 20) TOPLAM BAYT SINIRINDA KESİLEN TÜM AÇIKÇA İSTENEN DOSYALAR RAPORLANIR
# ------------------------------------------------------------------------------

test_that("cc_select_input_files toplam bayt siniri kesince siradaki tum istenen dosyalar required_skipped'e girer", {
  env <- .cc_hardening_env()
  kok <- withr::local_tempdir()

  # Üç açıkça istenen dosya; toplam bayt sınırı yalnızca ilkine yeter.
  a <- file.path(kok, "a.csv")
  b <- file.path(kok, "b.csv")
  c_ <- file.path(kok, "c.csv")
  writeBin(as.raw(rep(1L, 100L)), a)
  writeBin(as.raw(rep(1L, 100L)), b)
  writeBin(as.raw(rep(1L, 100L)), c_)

  secim <- env$cc_select_input_files(
    prompt = "a.csv b.csv c.csv dosyalarini incele",
    files = c(a, b, c_),
    file_sizes = c(100, 100, 100),
    root = kok,
    explicit_files = c(a, b, c_),
    limits = list(max_input_total_bytes = 150)
  )

  # a.csv aktarılır; toplam sınır b.csv'de aşılır ve HEM b.csv HEM sıradaki
  # c.csv da (önceden yalnızca kesmeye neden olan dosya raporlanırdı, kalan
  # sıradaki istenenler sessizce yutulurdu) required_skipped'e girmelidir.
  expect_true("b.csv" %in% secim$required_skipped)
  expect_true("c.csv" %in% secim$required_skipped)
})

# ------------------------------------------------------------------------------
# 21) TIRNAKLI DOSYA ADI GENEL REGEX'E İKİNCİ KEZ DÜŞMEZ
# ------------------------------------------------------------------------------

test_that("cc_extract_prompt_file_mentions tirnak icindeki alt dizeyi ikinci kez ayri aday yapmaz", {
  env <- .cc_hardening_env()

  mentions <- env$cc_extract_prompt_file_mentions(
    'Lutfen "reports/Q1 budget.csv" dosyasini guncelle'
  )

  # "reports/Q1 budget.csv" tek bir aday olmalı; tırnak içindeki
  # "budget.csv" alt dizesi genel (tırnaksız) regex'e tekrar düşüp ayrı ve
  # yanlış bir ikinci dosya adayı üretmemeli.
  expect_true("reports/Q1 budget.csv" %in% mentions)
  expect_false("budget.csv" %in% mentions)
})

# ------------------------------------------------------------------------------
# 22) SIKI SENKRONİZASYON GEÇİŞİ ÖNCESİ İPTAL YENİDEN KONTROL EDİLİR
# ------------------------------------------------------------------------------

test_that("cc_apply_output_sync_plan kopyalama sirasinda guard silinirse dosyayi hedefe tasimaz", {
  env <- .cc_hardening_env(extra_files = "helpers_claude_code_output_sync.R")
  kaynak_kok <- withr::local_tempdir()
  hedef_kok <- withr::local_tempdir()

  kaynak_dosya <- file.path(kaynak_kok, "cikti.txt")
  writeLines("icerik", kaynak_dosya, useBytes = TRUE)
  hedef_dosya <- file.path(hedef_kok, "cikti.txt")

  guard <- withr::local_tempfile()
  file.create(guard)

  # Staging kopyası TAMAMLANDIKTAN hemen sonra (ama hedefe taşımadan/promote
  # ÖNCE) guard dosyası kaldırılır; bu, kopyalama sürerken çalıştırmanın
  # durdurulduğu senaryoyu simüle eder. cc_apply_output_sync_plan bu ikinci
  # kontrolü YAKALAYIP tamamlanmış staging dosyasını hedefe taşımamalıdır.
  gercek_file_copy <- file.copy
  env$file.copy <- function(from, to, ...) {
    sonuc <- gercek_file_copy(from, to, ...)
    if (isTRUE(sonuc) && identical(basename(as.character(from)), "cikti.txt")) {
      unlink(guard, force = TRUE)
    }
    sonuc
  }

  plan <- list(items = list(list(
    source_path = kaynak_dosya, dest_path = hedef_dosya, size = file.info(kaynak_dosya)$size
  )))

  sonuclar <- env$cc_apply_output_sync_plan(plan, active_guard = guard)

  expect_false(file.exists(hedef_dosya))
  expect_length(sonuclar, 1L)
  expect_false(isTRUE(sonuclar[[1]]$success))
  expect_true(nzchar(sonuclar[[1]]$error %||% ""))
})

# ------------------------------------------------------------------------------
# 23) KAYNAK/RUNTIME KÖKÜ KAYBOLURSA SENKRON SESSİZCE BAŞARILI SAYILMAZ
# ------------------------------------------------------------------------------

test_that("sync_claude_runtime_workdir_back kaynak dizini kaybolmusken degisiklik varsa acikca basarisiz olur", {
  env <- .cc_hardening_env(extra_files = "helpers_claude_code_runtime_workdir.R")
  runtime <- withr::local_tempdir()
  kaynak <- file.path(tempdir(), "yok-artik-boyle-bir-kaynak-mergen")

  sonuclar <- env$sync_claude_runtime_workdir_back(
    runtime_workdir = runtime,
    source_workdir = kaynak,
    changed_files = "cikti.txt"
  )

  expect_length(sonuclar, 1L)
  expect_false(isTRUE(sonuclar[[1]]$success))
  expect_true(nzchar(sonuclar[[1]]$error %||% ""))
})

test_that("sync_claude_runtime_workdir_back degisiklik yoksa kok kaybolsa bile zararsiz erken cikar", {
  env <- .cc_hardening_env(extra_files = "helpers_claude_code_runtime_workdir.R")
  runtime <- withr::local_tempdir()
  kaynak <- file.path(tempdir(), "yok-artik-boyle-bir-kaynak-mergen-2")

  sonuclar <- env$sync_claude_runtime_workdir_back(
    runtime_workdir = runtime,
    source_workdir = kaynak,
    changed_files = character(0)
  )

  expect_length(sonuclar, 0L)
})

# ------------------------------------------------------------------------------
# 24) ÇIKTI TARAMASI KESİLİRSE STAGING/SYNC TAMAMEN ATLANIR
# ------------------------------------------------------------------------------

test_that("cikti taramasi kesilirse indirme sahnelemesi ve senkron hic cagrilmaz", {
  env <- .cc_hardening_env(extra_files = "helpers_claude_code_run_completion.R")
  runtime <- withr::local_tempdir()

  env$diff_claude_code_workdir_snapshot <- function(...) {
    structure(character(0), scan = list(truncated = TRUE, truncated_reason = "max_entries"))
  }

  staging_cagrildi <- FALSE
  sync_cagrildi <- FALSE
  env$cc_collect_streaming_run_downloads <- function(...) {
    staging_cagrildi <<- TRUE
    list()
  }
  env$sync_claude_runtime_workdir_back <- function(...) {
    sync_cagrildi <<- TRUE
    list()
  }

  sonuc <- env$cc_process_run_outputs(list(
    before_snapshot = list(), runtime_workdir = runtime,
    source_workdir = runtime, mirrored = TRUE, limits = list()
  ))

  expect_false(staging_cagrildi)
  expect_false(sync_cagrildi)
  expect_true(isTRUE(sonuc$output_scan_truncated))
  expect_identical(sonuc$output_scan_truncated_reason, "max_entries")
})

# ------------------------------------------------------------------------------
# 25) ÇIKTI İŞLEME İÇİN BAĞIMSIZ ZAMAN AŞIMI TAKILAN WORKER'I SONLANDIRIR
# ------------------------------------------------------------------------------

test_that("cc_dispatch_run_output_processing takilan worker'i bagimsiz deadline ile sonlandirir", {
  env <- .cc_hardening_env(extra_files = c(
    "helpers_claude_code_run_lifecycle.R",
    "helpers_claude_code_run_dispatch.R",
    "helpers_claude_code_run_completion.R"
  ))
  env$cc_runtime_limit <- function(name, default_value = Inf, limits = NULL) {
    if (identical(name, "output_process_timeout_sec")) 0.05 else default_value
  }

  metadata_dir <- withr::local_tempdir()

  # Worker HİÇ çözülmeyen bir promise döndürsün; deadline'ın devreye
  # girmesi gerekir.
  env$tracked_future_promise <- function(...) {
    promises::promise(function(resolve, reject) invisible(NULL))
  }

  rv <- new.env(parent = emptyenv())
  rv$active_request_id <- "rid-timeout"

  rapor_edildi <- new.env(parent = emptyenv())
  rapor_edildi$hata <- NULL
  env$cc_report_output_processing_failure <- function(ctx, error) {
    rapor_edildi$hata <- error
    invisible(TRUE)
  }

  ctx <- list(
    session = list(token = "t", sendCustomMessage = function(...) invisible(NULL)),
    ns = function(x) x,
    rv = rv,
    env = list(
      runtime_layout = list(metadata = metadata_dir),
      request_id = "rid-timeout"
    ),
    ayristirma = list(tool_uses = list())
  )

  env$cc_dispatch_run_output_processing(ctx)

  son <- Sys.time() + 3
  while (is.null(rapor_edildi$hata) && Sys.time() < son) {
    later::run_now(0.05)
  }

  expect_false(is.null(rapor_edildi$hata))
  expect_true(grepl("zaman aşımı", conditionMessage(rapor_edildi$hata), fixed = TRUE))
})

# ------------------------------------------------------------------------------
# 26) DOKÜMAN VARLIK PROBUNDA max_files, max_entries'TEN ÖNCE KESMEZ
# ------------------------------------------------------------------------------

test_that("workdir_has_binary_documents ilk 400 sıradan dosyadan sonra gelen belgeyi kaçırmaz", {
  env <- .cc_hardening_env(extra_files = "helpers_claude_code_model_config.R")
  kok <- withr::local_tempdir()

  for (i in seq_len(410L)) {
    writeLines("x", file.path(kok, sprintf("not%03d.txt", i)), useBytes = TRUE)
  }
  # Alfabetik olarak "not*.txt" dosyalarından SONRA gelecek gerçek bir belge.
  writeLines("veri", file.path(kok, "zzz_rapor.pdf"), useBytes = TRUE)

  sonuc <- env$workdir_has_binary_documents(kok, extensions = c("pdf", "docx", "xlsx"))

  expect_true(isTRUE(sonuc))
})

# ------------------------------------------------------------------------------
# 27) SINIRLI DİZİN LİSTELEMESİ GERÇEK HATADA success = FALSE DÖNER
# ------------------------------------------------------------------------------

test_that("list_directory_contents gercek listeleme hatasinda success FALSE doner ve UI hatasi gorunur", {
  env <- .cc_hardening_env(extra_files = "helpers_claude_code_directory_listing.R")
  kok <- withr::local_tempdir()

  env$cc_scan_list_dir_bounded <- function(...) {
    list(entries = character(0), truncated = FALSE, reason = "", ok = FALSE, error = "erisim reddedildi")
  }

  sonuc <- env$list_directory_contents(kok, max_items = 20L)

  expect_false(isTRUE(sonuc$success))
  expect_identical(sonuc$error, "erisim reddedildi")
})

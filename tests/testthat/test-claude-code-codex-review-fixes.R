# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-codex-review-fixes.R
# Açıklama: PR #672 üzerinde Codex tarafından bildirilen son runtime/output
#           yarış ve fail-closed bulgularının gerileme testleri.
# ==============================================================================

# Sertleştirme dosyaları manifeste OPSİYONEL olarak kayıtlıdır: güncellenmemiş
# bir on-prem çalışma kopyasında fiziksel olarak bulunmayabilirler. Bu durumda
# testler "cannot open file" hatasıyla patlamak yerine ATLANMALIDIR; aksi halde
# eksik dosya, uygulamayı ilgilendiren gerçek bir hata gibi raporlanır.
.cc_codex_review_files <- function() {
  file.path(
    resolve_repo_root_for_tests(), "R",
    c("helpers_claude_code_codex_runtime_lock.R",
      "helpers_claude_code_codex_runtime_fixes.R",
      "helpers_claude_code_codex_output_fixes.R")
  )
}

# Eksik dosyanın ADINI ve aynı dizindeki benzer adlı dosyaları raporlar.
# Kısmi/elle kopyalamada ad tek karakter eksik kalabilir; o zaman dosya hem
# "eksik" hem de "sahipsiz" görünür ve gerçek neden gizli kalır.
.cc_codex_missing_report <- function() {
  eksikler <- .cc_codex_review_files()
  eksikler <- eksikler[!file.exists(eksikler)]
  if (!length(eksikler)) return("")

  satirlar <- vapply(eksikler, function(yol) {
    adaylar <- tryCatch(
      list.files(dirname(yol), pattern = "\\.[rR]$"),
      error = function(e) character(0)
    )
    benzer <- tryCatch(
      setdiff(
        agrep(basename(yol), adaylar, max.distance = 0.1,
              ignore.case = TRUE, value = TRUE),
        basename(yol)
      ),
      error = function(e) character(0)
    )

    paste0(
      "  - EKSIK: ", yol,
      if (length(benzer)) {
        paste0("\n    Ayni dizinde benzer adli dosya: ", paste(benzer, collapse = ", "))
      } else {
        ""
      }
    )
  }, character(1), USE.NAMES = FALSE)

  paste(satirlar, collapse = "\n")
}

# Onaylı kökün İÇİNDE görünen ama dışarı çözülen bir kaynak yolu üretir.
# POSIX'te dosya symlink'i, Windows'ta yönetici hakkı gerektirmeyen dizin
# junction'ı kullanılır; iki platformda da aynı sözleşme doğrulanır.
.cc_codex_disari_kaynak <- function(kok, disari_dizin, ad) {
  if (.Platform$OS.type == "windows") {
    baglanti_dizin <- file.path(kok, "dis")
    testthat::expect_true(isTRUE(suppressWarnings(tryCatch(
      Sys.junction(disari_dizin, baglanti_dizin),
      error = function(e) FALSE
    ))))
    return(file.path(baglanti_dizin, ad))
  }

  baglanti <- file.path(kok, ad)
  testthat::expect_true(isTRUE(suppressWarnings(
    file.symlink(file.path(disari_dizin, ad), baglanti)
  )))
  baglanti
}

.cc_codex_skip_if_absent <- function() {
  testthat::skip_if_not(
    all(file.exists(.cc_codex_review_files())),
    paste0(
      "Codex sertlestirme dosyalari bu calisma kopyasinda yok:\n",
      .cc_codex_missing_report()
    )
  )
}

.cc_codex_review_env <- function() {
  .cc_codex_skip_if_absent()
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(x, y) if (is.null(x)) y else x
  env$get_claude_code_binary_doc_extensions <- function() {
    c("pdf", "xlsx", "xls", "docx", "doc", "pptx", "ppt")
  }
  env$cc_runtime_limit <- function(name, default, limits = NULL) {
    value <- if (is.list(limits)) limits[[name]] else NULL
    if (is.null(value)) default else value
  }

  captured <- c(
    "mirror_directory_to_local_workspace",
    "cc_select_input_files",
    "cc_scan_directory_bounded",
    "cc_plan_output_sync",
    "cc_apply_output_sync_plan",
    "cc_process_run_outputs",
    "cc_prepare_run_workspace",
    "cc_dispatch_run_preparation",
    "cc_run_prepare_worker_globals",
    "cc_run_output_worker_globals",
    "prepare_claude_code_document_context"
  )
  for (name in captured) env[[name]] <- function(...) list()

  env$.cc_prepare_worker_cache <- new.env(parent = emptyenv())
  env$.cc_completion_worker_cache <- new.env(parent = emptyenv())

  # Sertlestirme dosyalari uretimde temel yardimcilardan SONRA yuklenir ve
  # onlarin paylasilan fonksiyonlarini (ornegin cc_output_sync_canonical_root)
  # cagirir. Izole test ortami da ayni yukleme sirasini yansitmalidir.
  for (temel in c(
    "utils_path_reservation.R",
    "helpers_claude_code_run_lifecycle.R",
    "helpers_claude_code_bounded_scan.R",
    "helpers_claude_code_input_matching.R",
    "helpers_claude_code_runtime_prepare.R",
    "helpers_claude_code_runtime_lease.R",
    "helpers_claude_code_output_sync.R"
  )) {
    source(file.path(repo_root, "R", temel), encoding = "UTF-8", local = env)
  }

  source(
    file.path(repo_root, "R", "helpers_claude_code_codex_runtime_lock.R"),
    encoding = "UTF-8",
    local = env
  )
  source(
    file.path(repo_root, "R", "helpers_claude_code_codex_runtime_fixes.R"),
    encoding = "UTF-8",
    local = env
  )
  source(
    file.path(repo_root, "R", "helpers_claude_code_codex_output_fixes.R"),
    encoding = "UTF-8",
    local = env
  )
  env
}

test_that("Codex sertleştirme dosyaları çalışma kopyasında mevcuttur", {
  # Bu dosyalar git'te İZLENİR. Manifestteki "opsiyonel" işareti yalnızca
  # kısmi bir on-prem kopyada uygulamanın hiç açılmamasını engellemek içindir;
  # dosyaların GERÇEKTEN eksik olması normal bir durum DEĞİLDİR: o çalışma
  # kopyasında Codex sertleştirmelerinin tamamı sessizce devre dışıdır.
  #
  # Bu yüzden eksiklik 16 sessiz "skip" yerine TEK ve açık bir hata verir;
  # mesaj eksik dosyanın adını ve aynı dizindeki benzer adlı dosyaları
  # (ör. tek karakter eksik kopyalanmış bir ad) içerir.
  eksik_raporu <- .cc_codex_missing_report()

  expect_identical(
    eksik_raporu,
    "",
    info = paste0(
      "Codex sertlestirme dosyalari calisma kopyasinda bulunamadi. Bu dosyalar ",
      "git'te izlenir; calisma kopyasi dal ile senkron degil.\n",
      eksik_raporu,
      "\nCozum: bu dalı yeniden cekin (git fetch + git reset --hard) ve ",
      "R/ altindaki artik/yanlis adli kopyalari temizleyin."
    )
  )
})

test_that("Codex hardening files parse and loader references both layers", {
  repo_root <- resolve_repo_root_for_tests()

  # Parse doğrulaması yalnızca dosyalar bu kopyada varken anlamlıdır; manifest
  # ve sıra sözleşmesi ise dosyalar olmasa da doğrulanmalıdır.
  if (all(file.exists(.cc_codex_review_files()))) {
    expect_silent(lapply(.cc_codex_review_files(), parse))
  }

  # Sertleştirme dosyaları kaynak manifestinden yüklenir. Manifest dışı
  # geç-yükleme, dosyaları seam sahipliği olmayan ölü koda çevirmişti.
  expect_source_manifest_contains_for_tests(c(
    "R/helpers_claude_code_codex_runtime_lock.R",
    "R/helpers_claude_code_codex_runtime_fixes.R",
    "R/helpers_claude_code_codex_output_fixes.R"
  ))

  # Sertleştirmeler mevcut tanımların üzerine yazdığı için sıra kritiktir:
  # önce değiştirilen özgün yardımcılar, sonra runtime, en son output.
  expect_source_manifest_order_for_tests(c(
    "R/helpers_claude_code_bounded_scan.R",
    "R/helpers_claude_code_runtime_prepare.R",
    "R/helpers_claude_code_output_sync.R",
    "R/helpers_claude_code_run_completion.R",
    "R/helpers_claude_code_codex_runtime_lock.R",
    "R/helpers_claude_code_codex_runtime_fixes.R",
    "R/helpers_claude_code_codex_output_fixes.R"
  ))

  # Manifest dışı geç-yükleyici geri gelmemelidir.
  loader <- paste(readLines(
    file.path(repo_root, "R", "server_observers_misc.R"), warn = FALSE
  ), collapse = "\n")
  expect_false(grepl("load_claude_code_codex_review_fixes", loader, fixed = TRUE))
})

test_that("ordinary local workdirs are always isolated and unresolved paths fail", {
  env <- .cc_codex_review_env()
  source_dir <- withr::local_tempdir()
  runtime_base <- withr::local_tempdir()

  env$resolve_claude_runtime_source_dir <- function(path) normalizePath(path, winslash = "/")
  env$cc_scan_source_workdir <- function(source_dir, limits = NULL) {
    list(ok = TRUE, root = source_dir, files = character(0), file_sizes = numeric(0))
  }
  env$cc_evaluate_workdir_preflight <- function(...) list(blocked = FALSE, limited = FALSE)
  env$.cc_runtime_workdir_reusable <- function(...) FALSE
  env$cc_runtime_user_dir <- function(user_id = NULL) runtime_base
  env$.cc_runtime_workdir_token <- function(runtime_token = NULL) "run-test"
  env$cc_runtime_ensure_layout <- function(layout) {
    invisible(lapply(layout, dir.create, recursive = TRUE, showWarnings = FALSE))
    layout
  }
  env$mirror_directory_to_local_workspace <- function(...) {
    list(ok = TRUE, selection = list(files = character(0)), copy = list())
  }
  env$.cc_runtime_prepare_result <- function(workdir, source_dir = NULL,
                                             mirrored = FALSE, reused = FALSE,
                                             layout = NULL, selection = NULL,
                                             preflight = NULL, scan = NULL) {
    list(runtime_workdir = workdir, source_workdir = source_dir,
         mirrored = mirrored, reused = reused, layout = layout,
         selection = selection, preflight = preflight, scan = scan)
  }

  result <- env$prepare_claude_runtime_workdir(source_dir, user_id = 7L)
  expect_true(isTRUE(result$mirrored))
  expect_true(dir.exists(result$layout$output))
  expect_false(identical(result$layout$output, source_dir))
  expect_false(identical(
    normalizePath(result$runtime_workdir, winslash = "/", mustWork = FALSE),
    normalizePath(source_dir, winslash = "/", mustWork = FALSE)
  ))

  env$resolve_claude_runtime_source_dir <- function(path) ""
  expect_error(
    env$prepare_claude_runtime_workdir(source_dir, user_id = 7L),
    "çözülemedi|erişilemiyor"
  )
})

test_that("reused input promotion removes stale files as one tree swap", {
  env <- .cc_codex_review_env()
  source_dir <- withr::local_tempdir()
  runtime <- withr::local_tempdir()
  target <- file.path(runtime, "input")
  dir.create(target)
  writeLines("stale", file.path(target, "stale.txt"), useBytes = TRUE)

  env$.cc_codex_original_mirror_directory_to_local_workspace <- function(
      source_dir, target_dir, ...) {
    dir.create(target_dir, recursive = TRUE, showWarnings = FALSE)
    fresh <- file.path(target_dir, "fresh.txt")
    writeLines("fresh", fresh, useBytes = TRUE)
    list(
      ok = TRUE,
      selection = list(files = "fresh.txt"),
      copy = list(
        copied = fresh,
        results = list(list(dest_path = fresh, success = TRUE))
      )
    )
  }

  result <- env$mirror_directory_to_local_workspace(
    source_dir, target, ownership_guard = function() invisible(TRUE)
  )
  expect_true(isTRUE(result$ok))
  expect_true(file.exists(file.path(target, "fresh.txt")))
  expect_false(file.exists(file.path(target, "stale.txt")))
  expect_true(all(startsWith(result$copy$copied, normalizePath(target, winslash = "/"))))
})

test_that("runtime ownership marker is atomic and missing markers fail closed", {
  env <- .cc_codex_review_env()
  runtime <- withr::local_tempdir()
  env$cc_runtime_owner_file <- function(runtime_workdir) {
    file.path(runtime_workdir, "metadata", "runtime-owner")
  }

  marker <- env$cc_claim_runtime_ownership(runtime, "request-a")
  expect_true(nzchar(marker))
  expect_true(env$cc_runtime_ownership_is(runtime, "request-a"))
  expect_false(env$cc_runtime_ownership_is(runtime, "request-b"))

  unlink(marker, force = TRUE)
  expect_false(env$cc_runtime_ownership_is(runtime, "request-a"))
})

test_that("dizin kilidi dayanikli sahiplik marker'i olmadan alinamaz", {
  env <- .cc_codex_review_env()
  taban <- withr::local_tempdir()
  lock_dir <- file.path(taban, "kilit")

  # Normal yol: marker yazılır, geri okunur ve jeton döner.
  jeton <- env$.cc_codex_acquire_dir_lock(lock_dir, attempts = 1L)
  expect_true(nzchar(jeton))
  expect_identical(env$.cc_codex_lock_owner_token(lock_dir), jeton)
  unlink(lock_dir, recursive = TRUE, force = TRUE)

  # Marker yazılamayan dosya sistemi: sahiplik KANITLANAMAZ. Kilit alınmış
  # sayılmamalı ve yeni oluşturulan kilit dizini geride bırakılmamalıdır
  # (işaretsiz kilit 60 sn sonra ikinci bir worker tarafından devralınırdı).
  env$writeLines <- function(...) invisible(NULL)
  bos_jeton <- env$.cc_codex_acquire_dir_lock(lock_dir, attempts = 1L)
  expect_identical(bos_jeton, "")
  expect_false(dir.exists(lock_dir))
})

test_that("dispatch refuses reused runtime when ownership cannot be claimed", {
  env <- .cc_codex_review_env()
  called <- FALSE
  failed <- FALSE
  env$.cc_codex_original_cc_dispatch_run_preparation <- function(ctx) {
    called <<- TRUE
    TRUE
  }
  env$cc_claim_runtime_ownership <- function(...) ""
  env$cc_fail_run_preparation <- function(...) {
    failed <<- TRUE
    TRUE
  }
  rv <- new.env(parent = emptyenv())
  rv$active_runtime_source <- "source"
  rv$active_runtime_workdir <- "runtime"

  result <- env$cc_dispatch_run_preparation(list(
    rv = rv, workdir = "source", run_request_id = "request-a"
  ))
  expect_false(isTRUE(result))
  expect_true(failed)
  expect_false(called)
})

test_that("unknown input sizes fail closed for scans and requested files", {
  env <- .cc_codex_review_env()
  env$.cc_codex_original_cc_scan_directory_bounded <- function(...) {
    list(ok = TRUE, files = "unknown.bin", errors = character(0), skipped = character(0))
  }
  env$file.info <- function(...) data.frame(size = NA_real_)

  scan <- env$cc_scan_directory_bounded("unused")
  expect_false(isTRUE(scan$ok))
  expect_match(paste(scan$errors, collapse = " "), "boyutu belirlenemedi")

  env$cc_scan_relative_paths <- function(files, root) basename(files)
  env$cc_extract_prompt_file_mentions <- function(prompt) "unknown.bin"
  env$.cc_prepare_mention_matches <- function(files, relatives, mentions) {
    basename(files) %in% basename(mentions)
  }
  env$.cc_codex_original_cc_select_input_files <- function(...) {
    list(
      files = "unknown.bin", relatives = "unknown.bin", total_bytes = 0,
      selection_mode = "prompt", skipped = character(0),
      required_skipped = character(0), truncated = FALSE
    )
  }
  selected <- env$cc_select_input_files(
    prompt = "unknown.bin dosyasını kullan",
    files = "unknown.bin",
    file_sizes = NA_real_,
    root = "."
  )
  expect_length(selected$files, 0L)
  expect_true("unknown.bin" %in% selected$required_skipped)
})

test_that("case-sensitive snapshots and document relative paths are preserved", {
  env <- .cc_codex_review_env()
  paths <- c("/tmp/Report.txt", "/tmp/report.txt")
  env$canonicalize_claude_code_file_path <- identity
  deduped <- env$deduplicate_claude_code_file_paths(paths)
  expect_length(deduped, if (.Platform$OS.type == "windows") 1L else 2L)

  root <- withr::local_tempdir()
  dir.create(file.path(root, "reports"))
  a <- file.path(root, "reports", "Q1.pdf")
  b <- file.path(root, "reports", "Q2.pdf")
  writeLines("a", a, useBytes = TRUE)
  writeLines("b", b, useBytes = TRUE)
  env$cc_runtime_limit <- function(name, default, limits = NULL) {
    value <- if (is.list(limits)) limits[[name]] else NULL
    if (is.null(value)) default else value
  }
  env$cc_extract_prompt_file_mentions <- function(prompt) c("reports/Q1.pdf", "reports/Q2.pdf")

  selection <- env$cc_select_documents_for_request(
    prompt = "iki raporu oku",
    documents = c(a, b),
    limits = list(max_documents = 2L)
  )
  expect_identical(selection$selection_mode, "prompt")
  expect_setequal(selection$files, c(a, b))

  expect_error(
    env$cc_select_documents_for_request(
      prompt = "iki raporu oku",
      documents = c(a, b),
      limits = list(max_documents = 1L)
    ),
    "Açıkça istenen dokümanların tümü"
  )
})

test_that("snapshot failures propagate and mirrored scans exclude input", {
  env <- .cc_codex_review_env()
  root <- withr::local_tempdir()
  seen_excludes <- NULL
  env$cc_runtime_limit <- function(name, default, limits = NULL) default
  env$cc_scan_default_excluded_dirs <- function() character(0)
  env$cc_scan_default_excluded_rel_paths <- function() character(0)
  env$cc_scan_directory_bounded <- function(..., exclude_rel_paths = character(0)) {
    seen_excludes <<- exclude_rel_paths
    list(ok = FALSE, files = character(0), errors = "scanner failed")
  }
  expect_error(
    env$cc_snapshot_run_output_area(root, mirrored = TRUE),
    "scanner failed|anlık görüntüsü"
  )
  expect_true("input" %in% seen_excludes)
})

test_that("unknown outputs are rejected and missing runtime roots abort processing", {
  env <- .cc_codex_review_env()
  env$cc_runtime_limit <- function(name, default, limits = NULL) default
  filtered <- env$cc_filter_download_candidates(file.path(tempdir(), "missing-output.bin"))
  expect_length(filtered$paths, 0L)
  expect_length(filtered$rejected_size, 1L)

  expect_error(
    env$cc_process_run_outputs(list(runtime_workdir = file.path(tempdir(), "missing-runtime"))),
    "runtime dizini"
  )
})

test_that("output promotion rolls back when cancellation arrives during staging", {
  env <- .cc_codex_review_env()
  source_root <- withr::local_tempdir()
  runtime <- withr::local_tempdir()
  src <- file.path(runtime, "new.txt")
  dest <- file.path(source_root, "new.txt")
  guard <- file.path(runtime, "active.guard")
  writeLines("new", src, useBytes = TRUE)
  writeLines("old", dest, useBytes = TRUE)
  file.create(guard)

  env$cc_output_sync_skipped_results <- function(plan) list()
  env$.cc_scan_norm <- function(path) normalizePath(path, winslash = "/", mustWork = FALSE)
  env$.cc_scan_key <- function(path) if (.Platform$OS.type == "windows") tolower(path) else path
  env$file.copy <- function(from, to, ...) {
    ok <- base::file.copy(from, to, ...)
    unlink(guard, force = TRUE)
    ok
  }

  result <- env$cc_apply_output_sync_plan(list(
    source_workdir = source_root,
    output_root = runtime,
    skipped_approved = list(),
    items = list(list(source_path = src, dest_path = dest, size = file.info(src)$size))
  ), active_guard = guard)

  expect_false(isTRUE(result[[1]]$success))
  expect_identical(readLines(dest, warn = FALSE), "old")
})

test_that("partial sync failures remain warnings and output deadline has cleanup", {
  env <- .cc_codex_review_env()
  env$cc_output_sync_failures <- function(outputs) outputs$sync_results
  messages <- list()
  session <- new.env(parent = emptyenv())
  session$sendCustomMessage <- function(type, message) {
    messages[[length(messages) + 1L]] <<- list(type = type, message = message)
  }
  finished <- NULL
  env$cc_finish_streaming_run <- function(ctx, outputs) finished <<- ctx
  ctx <- list(session = session, ns = identity, env = list(request_id = "A"), cikis_kodu = 0L,
              ayristirma = list(text_output = "model yanıtı"))
  result <- env$cc_report_output_sync_failure(ctx, list(sync_results = list(list(
    success = FALSE, dest_path = "missing.txt"
  ))))
  # Kısmi aktarım başarı değildir: çalıştırma hata dalında sonlanır, metin korunur.
  expect_true(isTRUE(result))
  expect_false(identical(finished$cikis_kodu, 0L))
  expect_match(finished$hata_mesaji, "missing.txt", fixed = TRUE)
  expect_match(finished$hata_mesaji, "model yanıtı", fixed = TRUE)

  dispatch_body <- paste(deparse(body(env$cc_dispatch_run_output_processing)), collapse = "\n")
  expect_match(dispatch_body, "cancel_deadline")
  expect_match(dispatch_body, "dispatch_error <- tryCatch", fixed = TRUE)
  expect_match(dispatch_body, "runtime_lease", fixed = TRUE)
})

# ------------------------------------------------------------------------------
# PR #672 ikinci tur Codex bulguları
# ------------------------------------------------------------------------------

test_that("adı verilen ama bulunamayan doküman ilgisiz dokümanla değiştirilmez", {
  env <- .cc_codex_review_env()
  klasor <- withr::local_tempdir()

  baska <- file.path(klasor, "other.pdf")
  writeLines("icerik", baska, useBytes = TRUE)

  env$cc_runtime_limit <- function(name, default, limits = NULL) default
  env$cc_extract_prompt_file_mentions <- function(prompt) {
    unlist(regmatches(prompt, gregexpr("[A-Za-z0-9_.-]+\\.[A-Za-z0-9]{1,8}", prompt)))
  }
  env$get_claude_code_binary_doc_extensions <- function() {
    c("pdf", "xlsx", "xls", "docx", "doc")
  }

  # REGRESYON: istenen "missing.pdf" yok; hazırlık sessizce "other.pdf"
  # dosyasını seçip kullanıcının hiç sormadığı içerik için başarı bildiriyordu.
  expect_error(
    env$cc_select_documents_for_request(
      prompt = "missing.pdf dosyasını özetle",
      documents = baska
    ),
    "Açıkça istenen dokümanlar seçilen klasörde bulunamadı",
    fixed = TRUE
  )

  # Eşleşen ad verildiğinde normal seçim korunur.
  eslesen <- env$cc_select_documents_for_request(
    prompt = "other.pdf dosyasını özetle",
    documents = baska
  )
  expect_identical(eslesen$selection_mode, "prompt")
  expect_identical(basename(eslesen$files), "other.pdf")
})

test_that("adı verilen doküman aday kümesi boşken de reddedilir", {
  env <- .cc_codex_review_env()
  env$cc_extract_prompt_file_mentions <- function(prompt) "missing.pdf"

  expect_error(
    env$cc_select_documents_for_request("missing.pdf dosyasını oku", character(0)),
    "missing.pdf",
    fixed = TRUE
  )
})

test_that("taramadan sonra büyüyen girdiler taze boyut sınırlarına takılır", {
  env <- .cc_codex_review_env()
  root <- withr::local_tempdir()
  input <- file.path(root, "active.log")
  writeBin(as.raw(rep(1L, 32L)), input)
  env$cc_extract_prompt_file_mentions <- function(prompt) "active.log"
  env$cc_scan_relative_paths <- function(files, root) basename(files)
  env$.cc_prepare_mention_matches <- function(files, relatives, mentions) {
    basename(files) %in% basename(mentions)
  }
  env$.cc_codex_original_cc_select_input_files <- function(...) list(
    files = input, relatives = "active.log", selection_mode = "prompt",
    skipped = character(0), required_skipped = character(0), truncated = FALSE
  )

  result <- env$cc_select_input_files(
    "active.log dosyasını kullan", input, file_sizes = 1, root = root,
    limits = list(max_input_file_bytes = 16, max_input_total_bytes = 16)
  )

  expect_length(result$files, 0L)
  expect_true("active.log" %in% result$required_skipped)
})

test_that("eşleşen ve eksik doküman birlikte istendiğinde eksik olan reddedilir", {
  env <- .cc_codex_review_env()
  klasor <- withr::local_tempdir()

  bulunan <- file.path(klasor, "found.pdf")
  writeLines("icerik", bulunan, useBytes = TRUE)

  env$cc_runtime_limit <- function(name, default, limits = NULL) default
  env$cc_extract_prompt_file_mentions <- function(prompt) {
    unlist(regmatches(prompt, gregexpr("[A-Za-z0-9_.-]+\\.[A-Za-z0-9]{1,8}", prompt)))
  }
  env$get_claude_code_binary_doc_extensions <- function() {
    c("pdf", "xlsx", "xls", "docx", "doc")
  }

  expect_error(
    env$cc_select_documents_for_request(
      prompt = "found.pdf ve missing.pdf dosyalarını özetle",
      documents = bulunan
    ),
    "missing.pdf",
    fixed = TRUE
  )
})

test_that("düzyazıdaki noktalı belirteçler doküman seçimini bloke etmez", {
  env <- .cc_codex_review_env()
  klasor <- withr::local_tempdir()

  baska <- file.path(klasor, "other.pdf")
  writeLines("icerik", baska, useBytes = TRUE)

  env$cc_runtime_limit <- function(name, default, limits = NULL) default
  env$cc_extract_prompt_file_mentions <- function(prompt) {
    unlist(regmatches(prompt, gregexpr("[A-Za-z0-9_.-]+\\.[A-Za-z0-9]{1,8}", prompt)))
  }
  env$get_claude_code_binary_doc_extensions <- function() {
    c("pdf", "xlsx", "xls", "docx", "doc")
  }

  # "3.5" ve "v1.2" gerçek doküman uzantısı taşımaz; aşırı engelleme olmamalı.
  sonuc <- env$cc_select_documents_for_request(
    prompt = "Surum 1.2 ve 3.5 oranlarini iceren dokumanlari ozetle",
    documents = baska
  )

  expect_identical(sonuc$selection_mode, "auto")
  expect_identical(basename(sonuc$files), "other.pdf")
})

test_that("bulunamayan doküman hazırlığı bloklu sonuca dönüşür", {
  env <- .cc_codex_review_env()

  env$.cc_codex_original_cc_prepare_run_workspace <- function(request) {
    list(
      ok = TRUE,
      document_context = list(
        extraction_errors = "Açıkça istenen dokümanlar seçilen klasörde bulunamadı: missing.pdf"
      )
    )
  }

  sonuc <- env$cc_prepare_run_workspace(list())

  expect_false(isTRUE(sonuc$ok))
  expect_true(isTRUE(sonuc$blocked))
  expect_true(grepl("missing.pdf", sonuc$message, fixed = TRUE))
})

test_that("worker global paketi her gönderimde yeniden taranmaz", {
  env <- .cc_codex_review_env()

  cagri <- 0L
  env$.cc_codex_original_cc_run_prepare_worker_globals <- function(refresh = FALSE, envir = globalenv()) {
    cagri <<- cagri + 1L
    list(temel = TRUE)
  }
  env$.cc_codex_add_named_worker_globals <- function(bundle, names, envir = globalenv()) bundle
  env$.cc_prepare_worker_cache$globals <- NULL

  ilk <- env$cc_run_prepare_worker_globals()
  ikinci <- env$cc_run_prepare_worker_globals()
  ucuncu <- env$cc_run_prepare_worker_globals()

  # REGRESYON: sarmalayıcı koşulsuz refresh = TRUE çağırıyordu; her Bilge Yolaç
  # çalıştırması future gönderilmeden önce ana olay döngüsünde özyinelemeli
  # global taramasını baştan çalıştırıyordu.
  expect_identical(cagri, 1L)
  expect_identical(ilk, ikinci)
  expect_identical(ikinci, ucuncu)

  # Açık refresh isteği önbelleği yeniler.
  env$cc_run_prepare_worker_globals(refresh = TRUE)
  expect_identical(cagri, 2L)
})

test_that("çıktı worker global paketi de önbelleği kullanır", {
  env <- .cc_codex_review_env()

  cagri <- 0L
  env$.cc_codex_original_cc_run_output_worker_globals <- function(refresh = FALSE, envir = globalenv()) {
    cagri <<- cagri + 1L
    list(temel = TRUE)
  }
  env$.cc_codex_add_named_worker_globals <- function(bundle, names, envir = globalenv()) bundle
  env$.cc_completion_worker_cache$globals <- NULL

  env$cc_run_output_worker_globals()
  env$cc_run_output_worker_globals()

  expect_identical(cagri, 1L)
})

test_that("var olan normal hedef Windows'ta da bağlantı sayılmaz", {
  # Sys.readlink() Windows'ta NA döner ve nzchar(NA) TRUE'dur; sertleştirilmiş
  # aktarım yolu buna dayandığında var olan HER hedefi reddediyordu.
  env <- .cc_codex_review_env()
  kaynak <- withr::local_tempdir()
  runtime <- withr::local_tempdir()

  hedef <- file.path(kaynak, "rapor.txt")
  writeLines("eski", hedef, useBytes = TRUE)

  cikti <- file.path(runtime, "rapor.txt")
  writeLines("yeni", cikti, useBytes = TRUE)

  sonuc <- env$cc_apply_output_sync_plan(list(
    source_workdir = kaynak,
    output_root = runtime,
    skipped_approved = list(),
    items = list(list(
      source_path = cikti,
      dest_path = hedef,
      size = file.info(cikti)$size
    ))
  ))

  expect_true(isTRUE(sonuc[[1]]$success))
  expect_identical(readLines(hedef, warn = FALSE), "yeni")
})

test_that("planlamadan sonra bağlantıya dönüşen çıktı kaynağı reddedilir", {
  env <- .cc_codex_review_env()
  kaynak <- withr::local_tempdir()
  runtime <- withr::local_tempdir()
  disari_dizin <- withr::local_tempdir()
  disari <- file.path(disari_dizin, "rapor.txt")
  writeLines("gizli", disari, useBytes = TRUE)

  # Windows'ta DOSYA symlink'i yönetici hakkı ister; aynı sözleşme (onaylı
  # output kökü dışına çözülen kaynak reddedilir) junction ile doğrulanır.
  cikti <- .cc_codex_disari_kaynak(runtime, disari_dizin, "rapor.txt")

  sonuc <- env$cc_apply_output_sync_plan(list(
    source_workdir = kaynak,
    output_root = runtime,
    skipped_approved = list(),
    items = list(list(
      source_path = cikti,
      dest_path = file.path(kaynak, "rapor.txt"),
      size = file.info(cikti)$size
    ))
  ))

  expect_false(isTRUE(sonuc[[1]]$success))
  expect_false(file.exists(file.path(kaynak, "rapor.txt")))
})

test_that("bulunamayan istenen girdi otomatik dosya seçimine düşmez", {
  env <- .cc_codex_review_env()
  kok <- withr::local_tempdir()
  ilgisiz <- file.path(kok, "ilgisiz.csv")
  writeLines("yanlis", ilgisiz, useBytes = TRUE)

  sonuc <- env$cc_select_input_files(
    prompt = "missing.csv dosyasını incele",
    files = ilgisiz,
    file_sizes = file.info(ilgisiz)$size,
    root = kok
  )

  expect_length(sonuc$files, 0L)
  expect_true("missing.csv" %in% sonuc$required_skipped)
})

test_that("çıktı terfisi güncel tekil ve toplam boyut sınırlarını uygular", {
  env <- .cc_codex_review_env()
  kaynak <- withr::local_tempdir()
  runtime <- withr::local_tempdir()
  cikti <- file.path(runtime, "buyuyen.txt")
  writeChar(strrep("x", 20), cikti, eos = NULL, useBytes = TRUE)

  sonuc <- env$cc_apply_output_sync_plan(list(
    source_workdir = kaynak, output_root = runtime, skipped_approved = list(),
    limits = list(max_output_file_bytes = 10, max_output_total_bytes = 10),
    items = list(list(source_path = cikti, dest_path = file.path(kaynak, "buyuyen.txt"), size = 1))
  ))

  expect_false(isTRUE(sonuc[[1]]$success))
  expect_false(file.exists(file.path(kaynak, "buyuyen.txt")))
})

test_that("runtime girdi kopyası son anda bağlantıya dönüşen kaynağı reddeder", {
  env <- .cc_codex_review_env()
  kok <- withr::local_tempdir()
  hedef <- withr::local_tempdir()
  disari_dizin <- withr::local_tempdir()
  writeLines("gizli", file.path(disari_dizin, "girdi.txt"), useBytes = TRUE)

  baglanti <- .cc_codex_disari_kaynak(kok, disari_dizin, "girdi.txt")

  sonuc <- env$cc_copy_files_to_runtime_input(
    baglanti, "girdi.txt", hedef, source_root = kok
  )

  expect_identical(sonuc$failed, "girdi.txt")
  expect_false(file.exists(file.path(hedef, "girdi.txt")))
})

test_that("Türkçe adlı normal girdi runtime alanına kopyalanır", {
  # REGRESYON: kaynak güvenlik denetimi tam yolu "üst dizin + taban ad" ile
  # karşılaştırıyordu. Windows'ta Türkçe taban adlar harf katlaması nedeniyle
  # eşitsiz görünüyor ve GEÇERLİ her dosya "bağlantı" sayılarak
  # kopyalanmıyordu ("Çalışma alanı hazırlanamadı: Gerekli girdi dosyaları
  # kopyalanamadı: ...").
  env <- .cc_codex_review_env()
  kok <- withr::local_tempdir()
  hedef <- withr::local_tempdir()

  ad <- paste0(
    "20260727230224821_40022c68f89c4117_EK-U S", intToUtf8(0x00FC), "re",
    intToUtf8(0x00E7), " ", intToUtf8(0x0130), intToUtf8(0x015F), " Ak",
    intToUtf8(0x0131), intToUtf8(0x015F), "lar", intToUtf8(0x0131), ".pdf"
  )
  writeLines("veri", file.path(kok, ad), useBytes = TRUE)

  sonuc <- env$cc_copy_files_to_runtime_input(
    file.path(kok, ad), ad, hedef, source_root = kok
  )

  expect_length(sonuc$failed, 0L)
  expect_true(file.exists(file.path(hedef, ad)))
})

test_that("yükleme klasöründeki depolama önekli doküman görünen adla eşleşir", {
  # REGRESYON: "Yükleme Klasörüne git" ile açılan klasörde dosyalar diskte
  # <zaman>_<hash>_<hash>_<görünen ad> biçiminde durur. Kullanıcı arayüzde
  # gördüğü adla sorduğunda eşleşme tutmuyor ve çalıştırma "Açıkça istenen
  # dokümanlar seçilen klasörde bulunamadı" ile bloke oluyordu.
  env <- .cc_codex_review_env()
  kok <- withr::local_tempdir()

  gorunen <- "EK-U Sureci.pdf"
  depo <- paste0("20260727230224821_40022c68f89c4117_2f0c175c515f_", gorunen)
  yol <- file.path(kok, depo)
  writeLines("pdf", yol, useBytes = TRUE)

  sonuc <- env$cc_select_documents_for_request(
    prompt = paste(gorunen, "dosyasini ozetle"),
    documents = yol
  )

  expect_identical(sonuc$selection_mode, "prompt")
  expect_identical(basename(sonuc$files), depo)
})

test_that("depolama önekli girdi görünen adla seçilir", {
  env <- .cc_codex_review_env()
  kok <- withr::local_tempdir()

  gorunen <- "EK-U Sureci.pdf"
  depo <- paste0("20260727230224821_40022c68f89c4117_2f0c175c515f_", gorunen)
  yol <- file.path(kok, depo)
  writeLines("veri", yol, useBytes = TRUE)

  sonuc <- env$cc_select_input_files(
    prompt = paste(gorunen, "dosyasini incele"),
    files = yol,
    file_sizes = file.info(yol)$size,
    root = kok
  )

  expect_identical(sonuc$selection_mode, "prompt")
  expect_identical(basename(sonuc$files), depo)
})

test_that("depolama öneki olmayan gerçekten eksik doküman hâlâ reddedilir", {
  env <- .cc_codex_review_env()
  kok <- withr::local_tempdir()
  yol <- file.path(kok, "other.pdf")
  writeLines("pdf", yol, useBytes = TRUE)

  expect_error(
    env$cc_select_documents_for_request(
      prompt = "missing.pdf dosyasini ozetle",
      documents = yol
    ),
    "bulunamadi|bulunamad",
    fixed = FALSE
  )
})

test_that("özet terfisi gerçek callr ve üretim aktarım denetimleriyle tamamlanır", {
  skip_if_not_installed("callr")
  env <- .cc_codex_review_env()
  for (file in c("helpers_worker_monitor.R", "helpers_worker_cancellation.R",
    "helpers_claude_code_run_lifecycle.R", "helpers_document_output_publication.R"))
    source(file.path(resolve_repo_root_for_tests(), "R", file), encoding = "UTF-8", local = env)
  env$cc_run_output_worker_globals <- function() {
    bundle <- list(cc_apply_output_sync_plan = env$cc_apply_output_sync_plan)
    c(bundle, env$worker_monitor_expand_function_globals(bundle))
  }
  output_dir <- withr::local_tempdir(); target_dir <- withr::local_tempdir()
  source_path <- file.path(output_dir, "dosya_aciklamalari.txt")
  dest <- file.path(target_dir, "dosya_aciklamalari.txt")
  writeLines("gerçek özet", source_path); writeLines("önceki özet", dest)
  shiny::testServer(function(input, output, session) NULL, {
    session$userData$user_id <- 7L
    rv <- shiny::reactiveValues(is_running = TRUE, active_request_id = "A",
      run_owner_guard = mergen_session_owner_guard(session))
    result <- NULL; failure <- NULL
    promise <- env$cc_publish_document_summary_async(list(success = TRUE,
      generated_summary_path = source_path), target_dir, output_dir, session, rv, "A")
    promises::then(promise, function(value) result <<- value, function(e) failure <<- e)
    expect_identical(readLines(dest), "önceki özet")
    deadline <- Sys.time() + 15
    while (is.null(result) && is.null(failure) && Sys.time() < deadline) later::run_now(0.01)
    expect_false(is.null(result) && is.null(failure), info = "Özet işçisi 15 sn içinde yerleşmedi.")
    expect_null(failure)
    expect_true(is.list(result))
    expect_identical(readLines(dest), "gerçek özet")
    expect_length(env$.MERGEN_CANCELLABLE_WORKERS$jobs, 0L)
  })
})

test_that("belirsiz özet işçisi bir kez bildirir; guard ve sahip kancası ölüm kanıtını bekler", {
  env <- .cc_codex_review_env()
  for (file in c("helpers_worker_monitor.R", "helpers_worker_cancellation.R",
    "helpers_claude_code_run_lifecycle.R", "helpers_document_output_publication.R"))
    source(file.path(resolve_repo_root_for_tests(), "R", file), encoding = "UTF-8", local = env)
  env$cc_run_output_worker_globals <- function() list()
  env$mergen_cancellable_worker_schedule <- function(...) NULL
  process_state <- new.env()
  process_state$alive <- NA
  env$mergen_cancellable_worker_launch <- function(...) list(
    is_alive = function() if (is.na(process_state$alive)) stop("bilinmiyor") else process_state$alive,
    kill_tree = function() FALSE, kill = function(...) FALSE)
  notifications <- failures <- 0L
  testthat::local_mocked_bindings(showNotification = function(...) {
    notifications <<- notifications + 1L
  }, .package = "shiny")
  output_dir <- withr::local_tempdir()
  shiny::testServer(function(input, output, session) NULL, {
    session$userData$user_id <- 7L
    rv <- shiny::reactiveValues(is_running = TRUE, active_request_id = "A",
      run_owner_guard = mergen_session_owner_guard(session))
    promise <- env$cc_publish_document_summary_async(list(success = TRUE,
      generated_summary_path = file.path(output_dir, "summary.txt")), output_dir,
      output_dir, session, rv, "A")
    promises::catch(promise, function(e) failures <<- failures + 1L)
    guard <- rv$summary_sync_guard
    for (i in 1:4) env$mergen_cancellable_worker_tick()
    expect_identical(notifications, 1L)
    expect_identical(failures, 0L)
    expect_true(file.exists(guard))
    expect_length(ls(session$userData$kimlik_kancalari), 1L)
    job <- env$.MERGEN_CANCELLABLE_WORKERS$jobs[[1]]
    job$next_probe <- Sys.time() - 1
    env$mergen_cancellable_worker_tick()
    expect_identical(notifications, 1L)
    process_state$alive <- FALSE
    job$next_probe <- Sys.time() - 1
    env$mergen_cancellable_worker_tick()
    for (i in 1:30) later::run_now(0)
    expect_identical(failures, 1L)
    expect_false(file.exists(guard))
    expect_null(rv$summary_sync_guard)
    expect_length(ls(session$userData$kimlik_kancalari), 0L)
    expect_length(env$.MERGEN_CANCELLABLE_WORKERS$jobs, 0L)
  })
})


test_that("canlı veya belirsiz runtime lease sahipliği devredilemez", {
  env <- .cc_codex_review_env()
  runtime <- withr::local_tempdir()
  prepare <- new.env(parent = env)
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_claude_code_run_prepare_task.R"),
         encoding = "UTF-8", local = prepare)
  env$cc_runtime_owner_file <- prepare$cc_runtime_owner_file
  prepare$.cc_runtime_workdir_reusable <- function(...) TRUE
  expect_true(nzchar(env$cc_claim_runtime_ownership(runtime, "old")))
  lease <- file.path(runtime, "metadata", "active-run-old.lease")
  child <- callr::r_bg(function() Sys.sleep(60))
  withr::defer(try(child$kill(), silent = TRUE))
  env$cc_bind_runtime_lease(lease, child)
  expect_false(any(grepl("^pid=NA$", readLines(lease))))
  # Canlı çalıştırma çocuğu yeniden kullanımı engeller (yaşı kendi başlangıcından
  # eski gösterilemez; o durum PID yeniden kullanımıdır).
  expect_false(env$cc_runtime_lease_reclaimable(lease, stale_sec = -1, orphan_sec = 1))
  expect_identical(env$cc_claim_runtime_ownership(runtime, "new"), "")
  expect_true(env$cc_runtime_ownership_is(runtime, "old"))
  expect_error(prepare$cc_acquire_reused_runtime_lease(runtime, 7L, "new"), "lease devralınamaz")
  expect_false(file.exists(file.path(runtime, "metadata", "active-run-new.lease")))
  writeLines(c("host=unknown-host", "pid=2147483647"), lease)
  expect_identical(env$cc_claim_runtime_ownership(runtime, "new"), "")
  writeLines(c(paste0("host=", Sys.info()[["nodename"]]), "pid=2147483647"), lease)
  # Ölü sahip kısa devir penceresinden sonra geri kazanılır.
  expect_false(env$cc_runtime_lease_reclaimable(lease))
  Sys.setFileTime(lease, Sys.time() - 120)
  expect_true(env$cc_runtime_lease_reclaimable(lease))
  # Yalnız uzun ömürlü sunucu süreci kayıtlıysa terk edilmiş kira yetim
  # eşiğinden sonra geri kazanılır; taze iken korunur.
  writeLines(c(paste0("host=", Sys.info()[["nodename"]]), paste0("pid=", Sys.getpid())), lease)
  expect_false(env$cc_runtime_lease_reclaimable(lease))
  Sys.setFileTime(lease, Sys.time() - 100000)
  expect_true(env$cc_runtime_lease_reclaimable(lease))
  writeLines(c(paste0("host=", Sys.info()[["nodename"]]), "pid=2147483647"), lease)
  Sys.setFileTime(lease, Sys.time() - 120)
  expect_true(nzchar(env$cc_claim_runtime_ownership(runtime, "new")))
  expect_true(env$cc_runtime_ownership_is(runtime, "new"))
  acquired <- prepare$cc_acquire_reused_runtime_lease(runtime, 7L, "new")
  expect_true(file.exists(acquired))
})

test_that("çıktı geri yüklemesi başarısızsa yedeğin rezervasyon kimliği korunur", {
  env <- .cc_codex_review_env()
  root <- withr::local_tempdir()
  output <- withr::local_tempdir()
  src <- file.path(output, "rapor.txt")
  dest <- file.path(root, "rapor.txt")
  writeLines("yeni", src); writeLines("özgün", dest)
  env$.cc_scan_norm <- function(path) normalizePath(path, winslash = "/", mustWork = FALSE)
  env$.cc_scan_key <- identity
  env$cc_output_sync_skipped_results <- function(...) list()
  env$file.rename <- function(from, to) {
    if (identical(to, dest)) FALSE else base::file.rename(from, to)
  }
  result <- env$cc_apply_output_sync_plan(list(source_workdir = root, output_root = output,
    items = list(list(source_path = src, dest_path = dest, size = file.info(src)$size))))
  expect_false(result[[1]]$success)
  token <- env$mergen_reservation_owner(env$.cc_output_txn_paths(dest)$lock)
  expect_false(is.na(token))
  env$file.rename <- base::file.rename
  expect_true(env$.cc_output_recover_dest(dest, token))
  expect_identical(readLines(dest), "özgün")
})

test_that("uzun çıktı adı işlem yapıtlarının dosya adı sınırını aşmaz ve kurtarılır", {
  env <- .cc_codex_review_env()
  base_root <- withr::local_tempdir()
  root <- file.path(base_root, strrep("p", max(1L, 215L - nchar(base_root) - 1L)))
  expect_true(dir.create(root))
  long_dest <- file.path(root, paste0(strrep("x", 246), ".txt"))
  token <- "2147483646-ccoutabcdef"
  txn <- env$.cc_output_txn_paths(long_dest, token)
  expect_true(all(nchar(basename(unlist(txn)), type = "bytes") <= 255))
  expect_false(identical(txn, env$.cc_output_txn_paths(sub("x.txt$", "y.txt", long_dest), token)))
  dest <- long_dest
  owner <- env$.cc_output_dest_lock(dest, wait_sec = 0)
  expect_true(nzchar(owner))
  txn <- env$.cc_output_txn_paths(dest, owner)
  # Kurulum da üretimle aynı I/O sınırını kullanır; uzun yedek mantıksal yolda açılamaz.
  expect_gt(nchar(txn$backup), 259L)
  writeLines("özgün", env$mergen_io_path(txn$backup))
  writeLines(c(token, paste0("host=", Sys.info()[["nodename"]])), env$.mergen_reservation_marker(txn$lock))
  expect_true(file.rename(env$mergen_io_path(txn$backup),
                          env$mergen_io_path(env$.cc_output_txn_paths(dest, token)$backup)))
  env$.cc_output_recover_parent(dirname(dest))
  expect_identical(readLines(env$mergen_io_path(dest)), "özgün")
  expect_false(dir.exists(env$mergen_io_path(txn$lock)))
  expect_false(path_exists_relaxed(txn$backup))
  expect_false(path_exists_relaxed(txn$staging))
})

test_that("çıktı karşılaştırması Windows I/O önekini mantıksal köke geri bağlar", {
  env <- .cc_codex_review_env()
  env$normalizePath <- function(path, ...) path
  env$.Platform <- list(OS.type = "windows")
  expect_identical(env$.cc_scan_key(env$.cc_scan_norm("\\\\?\\C:\\root\\result.txt")), "c:/root/result.txt")
  expect_identical(env$.cc_scan_key(env$.cc_scan_norm("\\\\?\\UNC\\server\\share\\result.txt")), "//server/share/result.txt")
  expect_identical(env$.cc_scan_norm("//?/C:/root/result.txt"), "//?/C:/root/result.txt")
  env$.Platform <- list(OS.type = "unix")
  expect_identical(env$.cc_scan_key("//?/C:/root/result.txt"), "//?/C:/root/result.txt")
})

test_that("uzun eski çıktı yedeği atlanmaz; staging temizlenir ve yeni hedef korunur", {
  env <- .cc_codex_review_env()
  root <- withr::local_tempdir()
  parent <- file.path(root, strrep("p", max(1L, 180L - nchar(root) - 1L)))
  expect_true(dir.create(parent))
  dest <- file.path(parent, paste0(strrep("n", 185L), ".txt"))
  token <- "2147483646-ccoutabcdef"
  paths <- env$.cc_output_txn_paths(dest, token, legacy = TRUE)
  expect_lte(nchar(basename(paths$backup), type = "bytes"), 255L)
  expect_gt(nchar(paths$backup), 259L)
  bytes <- as.raw(c(0, 255, 10, 42))
  for (occupied in c(FALSE, TRUE)) {
    writeBin(bytes, env$mergen_io_path(paths$backup))
    writeLines("partial", env$mergen_io_path(paths$staging))
    if (occupied) writeLines("newer", env$mergen_io_path(dest))
    expect_true(env$.cc_output_recover_dest(dest, token))
    recovered <- if (occupied) file.path(parent, paste0(".cc-output-recovered-", token, "-",
      digest::digest(basename(dest), algo = "xxhash64", serialize = FALSE))) else dest
    expect_identical(readBin(env$mergen_io_path(recovered), "raw", 100L), bytes)
    if (occupied) expect_identical(readLines(env$mergen_io_path(dest)), "newer")
    expect_false(path_exists_relaxed(paths$backup))
    expect_false(path_exists_relaxed(paths$staging))
  }
})

test_that("uzun çıktı hedefinin bağlantı kanıtı görünürlük belirsizliğinde de korunur", {
  env <- .cc_codex_review_env()
  root <- withr::local_tempdir()
  output <- withr::local_tempdir()
  src <- file.path(output, "new.txt")
  dest <- file.path(root, paste0(strrep("n", 220L), ".txt"))
  writeLines("new", src)
  writeLines("preserve", env$mergen_io_path(dest))
  # Bağlantı meta verisi var; base R uzun/sarkan hedefi yok sanıyor.
  real_exists <- base::file.exists
  env$file.exists <- function(path) if (path %in% c(dest, env$mergen_io_path(dest))) FALSE else real_exists(path)
  env$cc_path_is_reparse_link <- function(...) FALSE
  real_link <- fs::is_link
  testthat::local_mocked_bindings(is_link = function(path) {
    if (identical(path, dest)) TRUE else real_link(path)
  }, .package = "fs")
  result <- env$cc_apply_output_sync_plan(list(source_workdir = root, output_root = output,
    items = list(list(source_path = src, dest_path = dest, size = file.info(src)$size))))
  expect_false(result[[1]]$success)
  expect_match(result[[1]]$error, "bağlantı/reparse-point", fixed = TRUE)
  expect_identical(readLines(env$mergen_io_path(dest)), "preserve")
  expect_identical(readLines(src), "new")
})

test_that("uzun çıktı kaynağı fiziksel kökten doğrulanır; bağlantı kaçışı reddedilir", {
  env <- .cc_codex_review_env()
  root <- withr::local_tempdir()
  output <- withr::local_tempdir()
  outside <- withr::local_tempdir()
  name <- paste0(strrep("s", 240L), ".txt")
  src <- file.path(output, name)
  writeLines("published", env$mergen_io_path(src))
  # Uzun-yol kayıt defteri açık olsa da olağan I/O sınırı benzetilir.
  env$file.exists <- function(path) {
    if (.Platform$OS.type == "windows" && nchar(path) > 247L &&
        !startsWith(chartr("\\", "/", path), "//?/")) return(FALSE)
    base::file.exists(path)
  }
  dest <- file.path(root, "published.txt")
  result <- env$cc_apply_output_sync_plan(list(source_workdir = root, output_root = output,
    items = list(list(source_path = src, dest_path = dest, size = file.info(env$mergen_io_path(src))$size))))
  expect_true(result[[1]]$success)
  expect_identical(readLines(dest), "published")
  expect_identical(readLines(env$mergen_io_path(src)), "published")
  unlink(env$mergen_io_path(src), expand = FALSE)
  expect_false(path_exists_relaxed(src))
  writeLines("outside", env$mergen_io_path(file.path(outside, name)))
  escape <- .cc_codex_disari_kaynak(output, outside, name)
  link <- if (.Platform$OS.type == "windows") dirname(escape) else escape
  withr::defer(fs::link_delete(link))
  rejected <- file.path(root, "rejected.txt")
  result <- env$cc_apply_output_sync_plan(list(source_workdir = root, output_root = output,
    items = list(list(source_path = escape, dest_path = rejected, size = 8))))
  expect_false(result[[1]]$success)
  expect_false(path_exists_relaxed(rejected))
  expect_identical(readLines(env$mergen_io_path(file.path(outside, name))), "outside")
})

test_that("uzun çıktı ebeveyni taranır; kilit kimliği I/O önekiyle değişmez", {
  env <- .cc_codex_review_env()
  root <- withr::local_tempdir()
  parent <- file.path(root, strrep("p", 95L), strrep("q", 95L), strrep("r", 95L))
  expect_true(dir.create(env$mergen_io_path(parent), recursive = TRUE))
  dest <- file.path(parent, paste0(strrep("n", 220L), ".txt"))
  owner <- env$.cc_output_dest_lock(dest, wait_sec = 0)
  expect_true(nzchar(owner))
  old <- "2147483646-ccoutabcdef"
  paths <- env$.cc_output_txn_paths(dest, old)
  writeLines("recover", env$mergen_io_path(paths$backup))
  writeLines("partial", env$mergen_io_path(paths$staging))
  writeLines(c(old, paste0("host=", Sys.info()[["nodename"]])), env$.mergen_reservation_marker(paths$lock))
  env$mergen_lock_owner_reclaimable <- function(...) TRUE
  env$.cc_output_recover_parent(parent)
  expect_identical(readLines(env$mergen_io_path(dest)), "recover")
  expect_false(path_exists_relaxed(paths$backup))
  expect_false(path_exists_relaxed(paths$staging))
  expect_false(path_exists_relaxed(paths$lock))
})

test_that("uzun çıktı planlanır ve yayımlanır; her dosya sistemi sondası I/O yolunu kullanır", {
  env <- .cc_codex_review_env()
  # Uzun-yol desteksiz Windows benzetimi: mantıksal bileşen diskte yoktur ve
  # yalnız I/O dönüşümü onu gerçek kısa dizine bağlar. Dönüştürülmemiş her
  # sonda (varlık, boyut, ebeveyn, kilit metadata'sı, terfi) böylece düşer.
  virtual <- strrep("u", 120L)
  real_io <- env$mergen_io_path
  env$mergen_io_path <- function(path) {
    if (!length(path)) return(path)
    out <- as.character(path)
    hit <- !is.na(out)
    out[hit] <- gsub(paste0("/", virtual, "(?=/|$)"), "/k", out[hit], perl = TRUE)
    real_io(out)
  }
  runtime <- normalizePath(withr::local_tempdir(), winslash = "/")
  source_root <- normalizePath(withr::local_tempdir(), winslash = "/")
  layout <- list(root = runtime, input = file.path(runtime, "input"), output = file.path(runtime, "output"),
                 metadata = file.path(runtime, "metadata"), document_support = file.path(runtime, "document_support"))
  name <- paste0(strrep("ç", 105L), ".txt")
  src <- file.path(layout$output, virtual, "alt", name)
  expect_true(dir.create(env$mergen_io_path(dirname(src)), recursive = TRUE))
  expect_false(file.exists(src))
  for (content in c("ilk yayın", "ikinci yayın")) {
    writeLines(content, env$mergen_io_path(src))
    plan <- env$cc_plan_output_sync(src, layout, source_root)
    expect_length(plan$skipped_approved, 0L)
    expect_length(plan$items, 1L)
    dest <- plan$items[[1]]$dest_path
    # Plan ve sonuç mantıksal yolları taşır.
    expect_identical(plan$items[[1]]$source_path, src)
    expect_identical(dest, file.path(source_root, virtual, "alt", name))
    expect_true(startsWith(basename(env$.cc_output_txn_paths(dest)$lock), ".cc-output-lockhash-"))
    result <- env$cc_apply_output_sync_plan(plan)
    expect_true(result[[1]]$success, info = result[[1]]$error)
    expect_identical(result[[1]]$dest_path, dest)
    expect_identical(readLines(env$mergen_io_path(dest)), content)
    expect_length(list.files(env$mergen_io_path(dirname(dest)), pattern = "^\\.cc-output-", all.files = TRUE), 0L)
  }
})

test_that("hash kilidinin Türkçe hedef adı UTF-8 olarak simetrik saklanır", {
  withr::local_options(encoding = "UTF-8")
  env <- .cc_codex_review_env()
  dest <- file.path(withr::local_tempdir(), paste0(strrep("ö", 110), ".txt"))
  token <- env$.cc_output_dest_lock(dest, wait_sec = 0)
  lock <- env$.cc_output_txn_paths(dest)$lock
  withr::defer(env$mergen_reservation_release(lock, token))
  expect_true(nzchar(token))
  con <- file(file.path(lock, "destination"), "rb")
  withr::defer(close(con))
  expect_identical(readLines(con, encoding = "UTF-8"), basename(dest))
  env$.Platform <- list(OS.type = "windows")
  expect_identical(env$.cc_output_txn_paths(toupper(dest))$lock,
    file.path(dirname(toupper(dest)), basename(env$.cc_output_txn_paths(dest)$lock)))
})

test_that("çıktı kurtarma UTF-8 ve eski yerel adı yalnız kilit hash'i eşleşirse kabul eder", {
  withr::local_options(encoding = "UTF-8")
  for (legacy_metadata in c(FALSE, TRUE)) {
    env <- .cc_codex_review_env()
    env$.Platform <- list(OS.type = "windows")
    # Gerçek Unicode ebeveyn, göreli yollarla kodlama benzetiminin dışında kalır.
    withr::with_dir(withr::local_tempdir(pattern = paste0(intToUtf8(c(0x11f, 0x131)), "-")), {
      root <- "."
      name <- paste0("Ö", strrep("x", 210), ".txt")
      native <- iconv(name, "UTF-8", "latin1")
      # Eski Windows yol işlemlerinin tek baytlı gösterimi yalnız bu ortamda korunur.
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
        marked <- vapply(list(...), function(x) any(Encoding(x) == "latin1"), logical(1))
        if (any(marked)) native_text(result) else result
      }
      dest <- env$file.path(root, native)
      expect_false(anyNA(dest))
      expect_identical(charToRaw(env$basename(dest)), charToRaw(native))
      token <- "2147483646-ccoutabcdef"
      txn <- env$.cc_output_txn_paths(dest, token)
      expect_false(identical(txn$backup, env$.cc_output_txn_paths(enc2utf8(dest), token)$backup))
      dir.create(txn$lock)
      writeLines(c(token, paste0("host=", Sys.info()[["nodename"]])), file.path(txn$lock, "owner"))
      metadata <- if (legacy_metadata) native else enc2utf8(name)
      writeBin(charToRaw(paste0(metadata, if (legacy_metadata) "\r\n" else "\n")), file.path(txn$lock, "destination"))
      writeBin(charToRaw(enc2utf8("özgün\n")), txn$backup)
      writeBin(charToRaw("partial"), txn$staging)
      # Eski Windows yerel gösterimi, oturumun yerel ayarı değiştirilmeden kurulur.
      env$rawToChar <- function(bytes) {
        result <- base::rawToChar(bytes)
        if (legacy_metadata) Encoding(result) <- "latin1"
        result
      }
      restored <- file.path(root, "restored.txt")
      env$file.rename <- function(from, to) {
        if (identical(from, txn$backup)) {
          # Uzun mutlak hedefte terfi I/O yazımını alır; mantıksal kimlik aynıdır.
          expect_identical(enc2utf8(to), enc2utf8(env$mergen_io_path(dest)))
          base::file.rename(from, restored)
        } else base::file.rename(from, to)
      }
      expect_false(is.null(env$.cc_output_recovery_dest(root, txn$lock)))
      expect_warning(env$.cc_output_recover_parent(root), NA)
      expect_identical(readBin(restored, "raw", 100L), charToRaw(enc2utf8("özgün\n")))
      expect_false(dir.exists(txn$lock))
      expect_false(file.exists(txn$backup))
      expect_false(file.exists(txn$staging))
    })
  }
})

test_that("uyuşmayan veya bozuk hedef metadata'sı yabancı kilidi ve yedeği değiştirmez", {
  env <- .cc_codex_review_env()
  root <- withr::local_tempdir()
  dest <- file.path(root, paste0(strrep("x", 246), ".txt"))
  token <- "2147483646-ccoutabcdef"
  txn <- env$.cc_output_txn_paths(dest, token)
  dir.create(txn$lock)
  writeLines(c(token, paste0("host=", Sys.info()[["nodename"]])), file.path(txn$lock, "owner"))
  writeLines("koru", txn$backup)
  writeLines("yarım", txn$staging)
  env$file.rename <- function(...) stop("Yabancı yedeğe erişilmemeliydi.")
  for (metadata in list(charToRaw("different.txt\n"), as.raw(c(255, 10)))) {
    writeBin(metadata, file.path(txn$lock, "destination"))
    expect_warning(env$.cc_output_recover_parent(root), NA)
    expect_true(dir.exists(txn$lock))
    expect_identical(readLines(txn$backup), "koru")
    expect_true(file.exists(txn$staging))
    expect_identical(env$mergen_reservation_owner(txn$lock), token)
  }
})

test_that("çıktı kopyası kilidi tazeleyemezse kendi rezervasyonunu bırakır", {
  env <- .cc_codex_review_env()
  root <- withr::local_tempdir()
  output <- withr::local_tempdir()
  src <- file.path(output, "rapor.txt")
  dest <- file.path(root, "rapor.txt")
  writeLines("içerik", src)
  env$.cc_scan_norm <- function(path) normalizePath(path, winslash = "/", mustWork = FALSE)
  env$.cc_scan_key <- identity
  env$cc_output_sync_skipped_results <- function(...) list()
  env$mergen_reservation_touch <- function(...) FALSE
  result <- env$cc_apply_output_sync_plan(list(source_workdir = root, output_root = output,
    items = list(list(source_path = src, dest_path = dest, size = file.info(src)$size))))
  expect_false(result[[1]]$success)
  expect_false(dir.exists(env$.cc_output_txn_paths(dest)$lock))
  expect_false(file.exists(dest))
})

test_that("yarım oluşturulmuş çıktı rezervasyonu sahiplik kanıtı olmadan devralınmaz", {
  env <- .cc_codex_review_env()
  dest <- file.path(withr::local_tempdir(), "rapor.txt")
  lock <- env$.cc_output_txn_paths(dest)$lock
  dir.create(lock)
  expect_identical(env$.cc_output_dest_lock(dest, wait_sec = 0), "")
  Sys.setFileTime(lock, Sys.time() - 120)
  token <- env$.cc_output_dest_lock(dest, wait_sec = 0)
  expect_identical(token, "")
  expect_true(dir.exists(lock))
  expect_true(is.na(env$mergen_reservation_owner(lock)))
})

test_that("çıktı kurtarma eski rezervasyon kaldırılmadan yapılır ve başarısızlıkta yeniden denenir", {
  env <- .cc_codex_review_env()
  dest <- file.path(withr::local_tempdir(), "rapor.txt")
  old <- "2147483646-ccoutabcdef"
  txn <- env$.cc_output_txn_paths(dest, old)
  dir.create(txn$lock)
  writeLines(c(old, paste0("host=", Sys.info()[["nodename"]])), file.path(txn$lock, "owner"))
  writeLines("özgün", txn$backup)
  recover <- env$.cc_output_recover_dest
  env$.cc_output_recover_dest <- function(path, token) {
    expect_identical(token, old)
    expect_identical(env$mergen_reservation_owner(txn$lock), old)
    FALSE
  }
  blocked <- env$.cc_output_dest_lock(dest, wait_sec = 0)
  expect_true(isTRUE(attr(blocked, "recovery_failed")))
  expect_identical(env$mergen_reservation_owner(txn$lock), old)
  expect_true(file.exists(txn$backup))
  env$.cc_output_recover_dest <- recover
  token <- env$.cc_output_dest_lock(dest, wait_sec = 0)
  expect_true(nzchar(token))
  expect_identical(readLines(dest), "özgün")
  expect_false(file.exists(txn$backup))
  env$mergen_reservation_release(txn$lock, token)
})

test_that("çıktı yayını hedef başına tek yazarlıdır ve yarım kalan yedek kurtarılır", {
  env <- .cc_codex_review_env()
  source_root <- withr::local_tempdir()
  runtime <- withr::local_tempdir()
  env$cc_output_sync_skipped_results <- function(plan) list()
  env$.cc_scan_norm <- function(path) normalizePath(path, winslash = "/", mustWork = FALSE)
  env$.cc_scan_key <- function(path) if (.Platform$OS.type == "windows") tolower(path) else path
  plan_for <- function(name, content) {
    src <- file.path(runtime, name)
    writeLines(enc2utf8(content), src, useBytes = TRUE)
    list(source_workdir = source_root, output_root = runtime, skipped_approved = list(),
         items = list(list(source_path = src, dest_path = file.path(source_root, name),
                           size = file.info(src)$size)))
  }
  dest <- file.path(source_root, "rapor.txt")
  txn <- env$.cc_output_txn_paths(dest)
  # Sert ölüm: ölü sürecin bayat rezervasyonu ve onun jetonuyla adlandırılmış
  # yapıtlar kalır. Önek taşıyan sıradan kullanıcı dosyaları işlem yapıtı değildir.
  bayat_islem <- function(hedef, ozgun, legacy = FALSE) {
    jeton <- paste0("2147483646-ccout", substr(basename(tempfile()), 5, 12))
    kilit <- env$.cc_output_txn_paths(hedef)$lock
    dir.create(kilit)
    writeLines(c(jeton, paste0("host=", Sys.info()[["nodename"]])), file.path(kilit, "owner"))
    yollar <- env$.cc_output_txn_paths(hedef, jeton, legacy = legacy)
    writeLines(enc2utf8(ozgun), yollar$backup, useBytes = TRUE)
    writeLines(enc2utf8("yarım"), yollar$staging, useBytes = TRUE)
    yollar
  }
  kullanici <- file.path(source_root, c(".cc-output-backup-rapor.txt", ".cc-output-stage-rapor.txt",
                                        ".cc-output-backup-diger2.txt"))
  for (yol in kullanici) writeLines(enc2utf8("kullanıcı verisi"), yol, useBytes = TRUE)
  yarim <- bayat_islem(dest, "özgün", legacy = TRUE)
  ok <- env$cc_apply_output_sync_plan(plan_for("rapor.txt", "yeni"))
  expect_true(isTRUE(ok[[1]]$success))
  expect_identical(readLines(dest, warn = FALSE, encoding = "UTF-8"), "yeni")
  expect_false(file.exists(yarim$backup))
  expect_false(file.exists(yarim$staging))
  # Plan dışı hedefin bayat işlemi de kanıtlı jetonla geri konur.
  diger <- file.path(source_root, "diger.txt")
  bayat_islem(diger, "diğer özgün")
  env$cc_apply_output_sync_plan(plan_for("rapor.txt", "yeniden"))
  expect_identical(readLines(diger, warn = FALSE, encoding = "UTF-8"), "diğer özgün")
  # Sıradan dosyalar ad önekinden ötürü taşınmaz, silinmez ya da geri yüklenmez.
  for (yol in kullanici) expect_identical(readLines(yol, warn = FALSE, encoding = "UTF-8"), "kullanıcı verisi")
  expect_false(file.exists(file.path(source_root, "diger2.txt")))
  expect_length(list.files(source_root, pattern = "^\\.cc-output-(stage|backup|recovered)-[0-9]+-ccout",
                           all.files = TRUE), 0L)
  # Canlı başka bir yazar hedefi tutarken bu işlem hedefi silemez ya da ezemez.
  jeton <- env$mergen_reservation_token("baska")
  expect_true(env$mergen_reservation_acquire(txn$lock, jeton))
  gercek_kilit <- env$.cc_output_dest_lock
  env$.cc_output_dest_lock <- function(dest, wait_sec = 0) gercek_kilit(dest, wait_sec = 0)
  blocked <- env$cc_apply_output_sync_plan(plan_for("rapor.txt", "çakışan"))
  expect_false(isTRUE(blocked[[1]]$success))
  expect_match(blocked[[1]]$error, "kullanılıyor")
  expect_identical(readLines(dest, warn = FALSE, encoding = "UTF-8"), "yeniden")
  env$mergen_reservation_release(txn$lock, jeton)
})

test_that("başka sunucunun terk edilmiş kirası kayıtlı sunucu rolüyle geri kazanılır", {
  env <- .cc_codex_review_env()
  lease <- withr::local_tempfile()
  writeLines(c(paste0("host=", Sys.info()[["nodename"]]), "server=111", "pid=111", "pid=222"), lease)
  Sys.setFileTime(lease, Sys.time() - 7200)
  env$mergen_pid_status <- function(pid, ...) identical(pid, 111L)
  expect_true(env$cc_runtime_lease_reclaimable(lease, orphan_sec = 3600))
  env$mergen_pid_status <- function(...) TRUE
  expect_false(env$cc_runtime_lease_reclaimable(lease, orphan_sec = 3600))
  expect_true(env$cc_bind_runtime_lease(lease))
  expect_true(paste0("server=", Sys.getpid()) %in% readLines(lease))
})

test_that("okunamayan kira yalnız yetim eşiğinden sonra geri kazanılır", {
  env <- .cc_codex_review_env()
  lease <- withr::local_tempfile()
  writeLines("kira", lease)
  env$.cc_read_runtime_lease <- function(...) NULL
  expect_false(env$cc_runtime_lease_reclaimable(lease, orphan_sec = 3600))
  Sys.setFileTime(lease, Sys.time() - 7200)
  expect_true(env$cc_runtime_lease_reclaimable(lease, orphan_sec = 3600))
})

test_that("okunamayan kira dizini yabancı kira yok sayılmaz", {
  env <- .cc_codex_review_env()
  runtime <- withr::local_tempdir()
  dir.create(file.path(runtime, "metadata"))
  expect_false(env$cc_runtime_has_foreign_lease(runtime, "yeni"))
  env$list.files <- function(...) character()
  expect_true(env$cc_runtime_has_foreign_lease(runtime, "yeni"))
})

test_that("tarayıcı kapanışında bekleyen hazırlık yeniden denemesi ayrılmış durumla sürer", {
  env <- .cc_codex_review_env()
  callbacks <- list()
  attempts <- 0L
  failed <- NULL
  env$.cc_codex_original_cc_dispatch_run_preparation <- function(ctx) stop("beklenmeyen gönderim")
  env$cc_claim_runtime_ownership <- function(...) { attempts <<- attempts + 1L; "" }
  env$cc_fail_run_preparation <- function(ctx, message, ...) failed <<- ctx$rv
  ud <- new.env()
  ud$user_id <- 7L
  closed <- FALSE
  session <- list(userData = ud, isClosed = function() closed)
  rv <- shiny::reactiveValues(active_request_id = "A", is_running = TRUE,
    active_runtime_source = "source", active_runtime_workdir = "runtime",
    run_owner_guard = mergen_session_owner_guard(session))
  testthat::local_mocked_bindings(later = function(func, delay = 0) {
    callbacks[[length(callbacks) + 1L]] <<- func
    function() NULL
  }, .package = "later")
  shiny::isolate(env$cc_dispatch_run_preparation(list(rv = rv, workdir = "source", run_request_id = "A")))
  expect_length(callbacks, 1L)
  closed <- TRUE
  shiny::isolate(cc_detach_run_state(cc_run_state_reference(rv), session))
  while (length(callbacks)) {
    fn <- callbacks[[1]]
    callbacks <- callbacks[-1]
    fn()
  }
  # Oturuma bağlı durum kapalıdır; denemeler ayrılmış durumla sürer ve terminal hataya ulaşır.
  expect_identical(attempts, 40L)
  expect_true(is.environment(failed))
  expect_true(env$cc_is_active_run(failed, "A"))
})

test_that("açık oturumda hazırlık yeniden denemesi reaktif bağlam dışında tamamlanır", {
  env <- .cc_codex_review_env()
  callbacks <- list()
  dispatched <- 0L
  attempts <- 0L
  env$cc_claim_runtime_ownership <- function(...) {
    attempts <<- attempts + 1L
    if (attempts <= 12L) "" else "owner"
  }
  env$.cc_codex_original_cc_dispatch_run_preparation <- function(ctx) {
    expect_identical(ctx$rv$active_runtime_workdir, "runtime")
    dispatched <<- dispatched + 1L
  }
  rv <- shiny::reactiveValues(active_request_id = "A", is_running = TRUE,
    active_runtime_source = "source", active_runtime_workdir = "runtime")
  testthat::local_mocked_bindings(later = function(func, delay = 0) {
    callbacks[[length(callbacks) + 1L]] <<- func
    function() NULL
  }, .package = "later")
  shiny::isolate(env$cc_dispatch_run_preparation(list(rv = rv, workdir = "source", run_request_id = "A")))
  while (length(callbacks)) {
    fn <- callbacks[[1L]]
    callbacks <- callbacks[-1L]
    expect_no_error(fn())
  }
  expect_identical(attempts, 13L)
  expect_identical(dispatched, 1L)
})

test_that("hazırlık kilidi bekleyen eski istek yeniden denenmez", {
  env <- .cc_codex_review_env()
  callback <- NULL
  claims <- 0L
  env$cc_claim_runtime_ownership <- function(...) { claims <<- claims + 1L; "" }
  env$.cc_codex_original_cc_dispatch_run_preparation <- function(...) stop("eski gönderim")
  env$cc_fail_run_preparation <- function(...) stop("yeni isteğe hata")
  rv <- shiny::reactiveValues(active_request_id = "A", is_running = TRUE,
    active_runtime_source = "source", active_runtime_workdir = "runtime")
  testthat::local_mocked_bindings(later = function(func, delay = 0) {
    expect_identical(delay, 0.25)
    callback <<- func
  }, .package = "later")
  shiny::isolate(env$cc_dispatch_run_preparation(list(rv = rv, workdir = "source", run_request_id = "A")))
  rv$active_request_id <- "B"
  expect_no_error(callback())
  expect_identical(claims, 1L)
  expect_identical(shiny::isolate(rv$active_request_id), "B")
})

test_that("kira değiştirmesi geçici hatada yeniden denenir, okunamayan kira yeniden yazılmaz", {
  env <- .cc_codex_review_env()
  env$Sys.sleep <- function(...) invisible(NULL)
  lease <- file.path(withr::local_tempdir(), "active-run-a.lease")
  sahip <- c(paste0("host=", Sys.info()[["nodename"]]), paste0("pid=", Sys.getpid()))
  writeLines(sahip, lease)
  # Windows paylaşım ihlali: ilk iki değiştirme denemesi başarısız olur.
  denemeler <- 0L
  original_move <- fs::file_move
  fail_move <- FALSE
  testthat::local_mocked_bindings(file_move = function(from, to) {
    denemeler <<- denemeler + 1L
    if (fail_move || denemeler < 3L) stop("paylaşım ihlali")
    original_move(from, to)
  }, .package = "fs")
  expect_true(env$cc_bind_runtime_lease(lease, list(get_pid = function() 4242L)))
  expect_identical(denemeler, 3L)
  expect_true("pid=4242" %in% readLines(lease))
  # Kalıcı değiştirme hatası eski kirayı olduğu gibi bırakır.
  onceki <- readLines(lease)
  fail_move <- TRUE
  expect_false(env$cc_bind_runtime_lease(lease, list(get_pid = function() 5151L)))
  expect_identical(readLines(lease), onceki)
  expect_length(list.files(dirname(lease), pattern = "\\.tmp$"), 0L)
  # Okuma hatası boş kira sayılmaz: sahiplik satırları silinerek yeniden yazılmaz.
  fail_move <- FALSE
  env$readLines <- function(...) stop("geçici okuma hatası")
  env$Sys.setFileTime <- function(...) FALSE
  expect_false(env$cc_touch_runtime_lease(lease))
  expect_false(env$cc_bind_runtime_lease(lease))
  env$readLines <- base::readLines
  expect_identical(readLines(lease), onceki)
})

test_that("başarısız kira heartbeat ana döngüde beklemez ve sonraki turda toparlanır", {
  env <- .cc_codex_review_env()
  beklemeler <- numeric()
  env$Sys.sleep <- function(seconds) beklemeler <<- c(beklemeler, seconds)
  env$Sys.setFileTime <- function(...) FALSE
  env$cc_log_warn <- function(...) invisible(NULL)
  lease <- file.path(withr::local_tempdir(), "active-run-a.lease")
  sahip <- c(paste0("host=", Sys.info()[["nodename"]]), paste0("pid=", Sys.getpid()))
  writeLines(sahip, lease)
  denemeler <- 0L
  hata <- TRUE
  original_move <- fs::file_move
  testthat::local_mocked_bindings(file_move = function(from, to) {
    denemeler <<- denemeler + 1L
    if (hata) stop("paylaşım ihlali")
    original_move(from, to)
  }, .package = "fs")
  for (tur in 1:3) {
    expect_false(env$cc_touch_runtime_lease(lease))
    expect_identical(denemeler, 5L * tur)
    expect_identical(readLines(lease), sahip)
    expect_length(list.files(dirname(lease), pattern = "\\.tmp$"), 0L)
  }
  expect_length(beklemeler, 0L)
  hata <- FALSE
  expect_true(env$cc_touch_runtime_lease(lease))
  expect_identical(denemeler, 16L)
  expect_identical(readLines(lease), sahip)
  expect_length(list.files(dirname(lease), pattern = "\\.tmp$"), 0L)
})

test_that("Windows uzun hedefin harf varyantları aynı yayın işlemini kilitler", {
  env <- .cc_codex_review_env()
  env$.Platform <- list(OS.type = "windows")
  root <- withr::local_tempdir()
  lower <- file.path(root, paste0(strrep("a", 205), ".txt"))
  upper <- file.path(root, paste0(strrep("A", 205), ".TXT"))
  a <- env$.cc_output_txn_paths(lower, "run")
  b <- env$.cc_output_txn_paths(upper, "run")
  expect_identical(a, b)
  env$.Platform <- list(OS.type = "unix")
  expect_false(identical(env$.cc_output_txn_paths(lower)$lock, env$.cc_output_txn_paths(upper)$lock))
})

test_that("runtime lease yeniden bağlanır, heartbeat değiştirir, yazım hatası eskiyi korur", {
  env <- .cc_codex_review_env()
  lease <- withr::local_tempfile()
  expect_true(env$.cc_write_runtime_lease(lease, "pid=2147483647"))
  expect_true(env$cc_bind_runtime_lease(lease, list(get_pid = function() 12345L)))
  expect_true(all(c(paste0("server=", Sys.getpid()), "pid=12345") %in% readLines(lease)))
  env$Sys.setFileTime <- function(...) FALSE
  before <- readLines(lease)
  expect_true(env$cc_touch_runtime_lease(lease))
  expect_identical(readLines(lease), before)
  testthat::local_mocked_bindings(file_move = function(...) stop("paylaşım ihlali"), .package = "fs")
  expect_false(env$.cc_write_runtime_lease(lease, "pid=54321"))
  expect_identical(readLines(lease), before)
  expect_false(file.exists(paste0(lease, ".", Sys.getpid(), ".tmp")))
})

test_that("açık çıktı paketi rezervasyon işlemini temiz ortamda çalıştırır", {
  env <- .cc_codex_review_env()
  env$.cc_codex_original_cc_run_output_worker_globals <- function(...) list()
  bundle <- env$cc_run_output_worker_globals(refresh = TRUE, envir = env)
  expect_true("%||%" %in% names(bundle))
  worker <- list2env(bundle, parent = baseenv())
  for (nm in names(bundle)) if (is.function(worker[[nm]])) environment(worker[[nm]]) <- worker
  dest <- file.path(withr::local_tempdir(), "rapor.txt")
  token <- worker$.cc_output_dest_lock(dest)
  expect_true(is.character(token) && nzchar(token))
  expect_identical(worker$.cc_output_recovery_dest(dirname(dest), worker$.cc_output_txn_paths(dest)$lock),
    file.path(dirname(dest), basename(dest)))
  expect_true(worker$.cc_output_recover_dest(dest, token))
  expect_true(worker$mergen_reservation_release(worker$.cc_output_txn_paths(dest)$lock, token))
})

test_that("hazırlık yeniden denemesi senkron hatayı sonlandırır ve yeni isteği korur", {
  for (successor in c(FALSE, TRUE)) {
    env <- .cc_codex_review_env()
    callbacks <- list()
    claims <- 0L
    failed <- character()
    rv <- shiny::reactiveValues(active_request_id = "A", is_running = TRUE,
      active_runtime_source = "source", active_runtime_workdir = "runtime")
    env$cc_claim_runtime_ownership <- function(...) {
      claims <<- claims + 1L
      if (claims == 1L) "" else "owner"
    }
    env$.cc_codex_original_cc_dispatch_run_preparation <- function(ctx) {
      if (successor) rv$active_request_id <- "B"
      stop("istek oluşturulamadı")
    }
    env$cc_fail_run_preparation <- function(ctx, message, ...) {
      expect_identical(ctx$rv$active_request_id, "A")
      failed <<- c(failed, message)
      ctx$rv$is_running <- FALSE
    }
    testthat::local_mocked_bindings(later = function(func, delay = 0) {
      callbacks[[length(callbacks) + 1L]] <<- func
      function() NULL
    }, .package = "later")
    shiny::isolate(env$cc_dispatch_run_preparation(list(rv = rv, workdir = "source", run_request_id = "A")))
    expect_no_error(callbacks[[1L]]())
    expect_identical(failed, if (successor) character() else "istek oluşturulamadı")
    expect_identical(shiny::isolate(rv$is_running), successor)
    expect_identical(shiny::isolate(rv$active_request_id), if (successor) "B" else "A")
  }
})

test_that("satır sonlu uzun POSIX hedefi bayt sınırından eksiksiz kurtarılır", {
  skip_on_os("windows")
  env <- .cc_codex_review_env()
  root <- withr::local_tempdir()
  for (ending in c(".txt", "\r")) {
    dest <- file.path(root, paste0(strrep("n", 205), "\n", ending))
    token <- "2147483646-ccoutabcdef"
    txn <- env$.cc_output_txn_paths(dest, token)
    acquired <- env$.cc_output_dest_lock(dest, wait_sec = 0)
    expect_true(nzchar(acquired))
    writeLines(c(token, paste0("host=", Sys.info()[["nodename"]])), file.path(txn$lock, "owner"))
    writeBin(charToRaw("original"), txn$backup)
    writeBin(charToRaw("partial"), txn$staging)
    expect_identical(env$.cc_output_recovery_dest(root, txn$lock), dest)
    env$.cc_output_recover_parent(root)
    expect_identical(readBin(dest, "raw", 100L), charToRaw("original"))
    expect_false(dir.exists(txn$lock))
    expect_false(file.exists(txn$staging))
  }
})

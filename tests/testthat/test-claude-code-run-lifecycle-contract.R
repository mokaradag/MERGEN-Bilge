# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-run-lifecycle-contract.R
# Açıklama: Bilge Yolaç çalışma yaşam döngüsü ve stale async callback koruması.
# ==============================================================================

.read_repo_text_cc_run_lifecycle_contract <- function(path) {
  repo_root <- resolve_repo_root_for_tests()
  full_path <- file.path(repo_root, path)

  size <- suppressWarnings(file.info(full_path)$size[1])
  if (is.na(size) || size <= 0) {
    return("")
  }

  con <- file(full_path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_data <- readBin(con, what = "raw", n = size)

  txt <- suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
  )

  if (is.na(txt)) {
    txt <- ""
  }

  txt <- gsub("\\r\\n?|\\r", "\n", txt, perl = TRUE)
  enc2utf8(txt)
}

.source_cc_run_lifecycle_for_test <- function() {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())

  source(file.path(repo_root, "R", "utils_common.R"), encoding = "UTF-8", local = env)
  source(
    file.path(repo_root, "R", "helpers_claude_code_run_lifecycle.R"),
    encoding = "UTF-8",
    local = env
  )

  env
}

test_that("Claude Code run lifecycle helper aktif ve stale request ayrımı yapar", {
  env <- .source_cc_run_lifecycle_for_test()

  rv <- new.env(parent = emptyenv())
  request_id <- env$cc_next_run_request_id()
  stale_id <- paste0(request_id, "_stale")

  expect_match(request_id, "^ccrun_")

  env$cc_mark_active_run(rv, request_id)

  expect_true(env$cc_is_active_run(rv, request_id))
  expect_false(env$cc_is_active_run(rv, stale_id))

  # Geriye dönük uyumluluk: eski finalize çağrıları request_id vermez.
  expect_true(env$cc_is_active_run(rv, NULL))
})

test_that("cc_finalize_if_active stale finalize çağrısını yoksayar", {
  env <- .source_cc_run_lifecycle_for_test()

  rv <- new.env(parent = emptyenv())
  calls <- 0L

  finalize_fn <- function(durum_metin,
                          durum_ikon,
                          durum_renk,
                          sure = NULL,
                          request_id = NULL) {
    calls <<- calls + 1L
    rv$last_finalize_request_id <- request_id
    invisible(TRUE)
  }

  env$cc_mark_active_run(rv, "newer-request")

  expect_false(env$cc_finalize_if_active(
    rv = rv,
    request_id = "older-request",
    finalize_streaming = finalize_fn,
    durum_metin = "Hata",
    durum_ikon = "exclamation-triangle",
    durum_renk = "#E57373",
    sure = NULL
  ))

  expect_equal(calls, 0L)

  expect_true(env$cc_finalize_if_active(
    rv = rv,
    request_id = "newer-request",
    finalize_streaming = finalize_fn,
    durum_metin = "Tamamlandı",
    durum_ikon = "check-circle",
    durum_renk = "#81C784",
    sure = 1
  ))

  expect_equal(calls, 1L)
  expect_identical(rv$last_finalize_request_id, "newer-request")
})

test_that("cc_observe_dir_if_active stale dizin yenilemesini yoksayar", {
  env <- .source_cc_run_lifecycle_for_test()

  rv <- new.env(parent = emptyenv())
  env$cc_mark_active_run(rv, "active-run")

  observed_dirs <- character(0)
  observe_dir_contents <- function(dizin) {
    observed_dirs <<- c(observed_dirs, dizin)
    invisible(TRUE)
  }

  expect_false(env$cc_observe_dir_if_active(
    rv = rv,
    request_id = "stale-run",
    observe_dir_contents = observe_dir_contents,
    dizin = "eski"
  ))

  expect_identical(observed_dirs, character(0))

  expect_true(env$cc_observe_dir_if_active(
    rv = rv,
    request_id = "active-run",
    observe_dir_contents = observe_dir_contents,
    dizin = "guncel"
  ))

  expect_identical(observed_dirs, "guncel")
})

test_that("doküman özetleme yolu CLI oturum bağlamını temizler", {
  env <- .source_cc_run_lifecycle_for_test()

  rv <- new.env(parent = emptyenv())
  rv$cli_session_id <- "resume-edilmemesi-gereken-eski-session"
  rv$conversation_context <- list(
    list(role = "assistant", content = "Eski CLI bağlamı")
  )
  rv$current_runtime_model <- "old-model"

  expect_true(env$cc_reset_document_summary_session_context(rv, "summary-model"))

  expect_null(rv$cli_session_id)
  expect_identical(rv$conversation_context, list())
  expect_identical(rv$current_runtime_model, "summary-model")
})

test_that("cc_abort_run_before_streaming yalnızca aktif request state'ini temizler", {
  env <- .source_cc_run_lifecycle_for_test()

  rv <- new.env(parent = emptyenv())
  env$cc_mark_active_run(rv, "active-run")
  rv$is_running <- TRUE

  expect_true(env$cc_abort_run_before_streaming(rv, "active-run"))
  expect_false(isTRUE(rv$is_running))
  expect_null(rv$active_request_id)

  env$cc_mark_active_run(rv, "newer-run")
  rv$is_running <- TRUE

  expect_false(env$cc_abort_run_before_streaming(rv, "older-run"))
  expect_true(isTRUE(rv$is_running))
  expect_identical(rv$active_request_id, "newer-run")
})

test_that("cc_send_run_blocked_message ortak hata payload'ını güvenli üretir", {
  env <- .source_cc_run_lifecycle_for_test()

  sent <- list()
  fake_session <- new.env(parent = emptyenv())
  fake_session$sendCustomMessage <- function(type, message) {
    sent[[length(sent) + 1L]] <<- list(type = type, message = message)
    invisible(TRUE)
  }

  ns <- function(x) paste0("cc-", x)

  expect_true(env$cc_send_run_blocked_message(
    session = fake_session,
    ns = ns,
    message = "<deneme>"
  ))

  expect_equal(length(sent), 1L)
  expect_equal(sent[[1]]$type, "cc-add-message")
  expect_equal(sent[[1]]$message$target, "cc-output_area")
  expect_equal(sent[[1]]$message$type, "error")
  expect_equal(sent[[1]]$message$welcomeId, "cc-welcome_screen")
  expect_true(grepl("&lt;deneme&gt;", sent[[1]]$message$content, fixed = TRUE))
})

test_that("çalışma dizini ve prompt yol güvenliği lifecycle helper içinde birlikte tutulur", {
  txt <- .read_repo_text_cc_run_lifecycle_contract(
    "R/helpers_claude_code_run_lifecycle.R"
  )

  expect_true(
    grepl("cc_prepare_safe_workdir_for_run\\s*<-\\s*function\\s*\\(", txt, perl = TRUE),
    info = "Workdir ve prompt yol güvenliği run lifecycle helper içinde birlikte tutulmalıdır."
  )

  expect_true(
    grepl("cc_validate_selected_workdir_for_run(", txt, fixed = TRUE),
    info = "Lifecycle helper mevcut çalışma dizini doğrulama helper'ını kullanmalıdır."
  )

  expect_true(
    grepl("cc_policy_validate_prompt_file_intent(", txt, fixed = TRUE),
    info = "Lifecycle helper merkezi prompt güvenlik politikasını çağırmalıdır."
  )

  expect_true(
    grepl("cc_send_run_blocked_message(", txt, fixed = TRUE),
    info = "Engellenen prompt kullanıcıya ortak blocked-message helper ile gösterilmelidir."
  )

  expect_true(
    grepl("cc_abort_run_before_streaming(", txt, fixed = TRUE),
    info = "Engellenen prompt aktif run state'ini temizlemelidir."
  )
})

test_that("module_claude_code.R çalışma dizini ve prompt yol güvenliğini lifecycle helper'a delege eder", {
  txt <- .read_repo_text_cc_run_lifecycle_contract("R/module_claude_code.R")

  expect_true(
    grepl("cc_prepare_safe_workdir_for_run(", txt, fixed = TRUE),
    info = "Module, çalışma dizini ve prompt yol güvenliğini tek lifecycle helper'a delege etmelidir."
  )

  expect_false(
    grepl("cc_validate_prompt_file_intent_for_run(", txt, fixed = TRUE),
    info = "Eski ara helper module içinde kullanılmamalıdır."
  )

  expect_false(
    grepl("prompt_path_policy <- cc_policy_validate_prompt_file_intent(", txt, fixed = TRUE),
    info = "Module içinde merkezi prompt path policy doğrudan çağrılmamalıdır."
  )
})

test_that("module_claude_code.R erken abortları lifecycle helper ile temizler", {
  txt <- .read_repo_text_cc_run_lifecycle_contract("R/module_claude_code.R")

  expect_true(
    grepl("cc_send_run_blocked_message\\(", txt, perl = TRUE),
    info = "Bilge Yolaç erken hata mesajları ortak helper üzerinden gönderilmelidir."
  )

  hits <- gregexpr(
    "cc_abort_run_before_streaming\\(rv, run_request_id\\)",
    txt,
    perl = TRUE
  )[[1]]

  hit_count <- if (length(hits) == 1L && hits[1] == -1L) 0L else length(hits)

  expect_true(
    hit_count >= 5L,
    info = sprintf(
      "Erken abort aktif request state'ini temizlemelidir. Bulunan çağrı sayısı: %d",
      hit_count
    )
  )

  # Hazırlık ve süreç başlatma hataları artık dispatch helper'ında aynı
  # request-id korumalı temizleme yolundan geçer.
  dispatch_txt <- .read_repo_text_cc_run_lifecycle_contract(
    "R/helpers_claude_code_run_dispatch.R"
  )

  expect_true(
    grepl("cc_fail_run_preparation\\s*<-\\s*function\\(", dispatch_txt, perl = TRUE),
    info = "Hazırlık hatası temizliği cc_fail_run_preparation() içinde merkezileşmelidir."
  )

  expect_true(
    grepl("cc_is_active_run\\(ctx\\$rv, ctx\\$run_request_id\\)", dispatch_txt, perl = TRUE),
    info = "Hazırlık geri çağrıları stale request'e karşı cc_is_active_run() ile korunmalıdır."
  )

  expect_false(
    grepl(
      "content\\s*=\\s*htmltools::htmlEscape\\(model_cozumu\\$reason\\)",
      txt,
      perl = TRUE
    ),
    info = "Model engelleme mesajı modül içinde tekrar eden özel payload ile gönderilmemelidir."
  )
})

test_that("module_claude_code.R doküman özetleme akışını lifecycle helper'a delege eder", {
  txt <- .read_repo_text_cc_run_lifecycle_contract("R/module_claude_code.R")

  expect_true(
    grepl("cc_next_run_request_id\\(\\)", txt, perl = TRUE),
    info = "Bilge Yolaç komut çalıştırma akışı request id üretmelidir."
  )

  expect_true(
    grepl("cc_mark_active_run\\(rv, run_request_id\\)", txt, perl = TRUE),
    info = "Bilge Yolaç aktif request kimliğini rv içinde işaretlemelidir."
  )

  # Doküman özetleme ve akış başlatma, hazırlık tamamlandıktan sonra
  # dispatch helper'ı üzerinden yürütülür.
  dispatch_txt <- .read_repo_text_cc_run_lifecycle_contract(
    "R/helpers_claude_code_run_dispatch.R"
  )

  expect_true(
    grepl("cc_dispatch_run_preparation\\(", txt, perl = TRUE),
    info = "Pahalı hazırlık ana Shiny sürecinden dispatch helper'a delege edilmelidir."
  )

  expect_true(
    grepl("cc_handle_document_summary_run\\(", dispatch_txt, perl = TRUE),
    info = "Doküman özetleme promise callback'leri helper'a taşınmış olmalıdır."
  )

  expect_true(
    grepl("stream_env\\$request_id\\s*<-\\s*ctx\\$run_request_id", dispatch_txt, perl = TRUE),
    info = "Streaming env aktif request kimliğini taşımalıdır."
  )
})

test_that("normal streaming finalization request id ile korunur", {
  # Çalıştırma sonrası sonlandırma completion helper'ına taşındı; her iki
  # dal da request-id korumalı cc_finalize_if_active() kullanır.
  txt <- .read_repo_text_cc_run_lifecycle_contract(
    "R/helpers_claude_code_run_completion.R"
  )

  expect_true(
    grepl(
      'durum_metin\\s*=\\s*"Tamamlandı"[\\s\\S]{0,200}?sure\\s*=\\s*sure',
      txt,
      perl = TRUE
    ),
    info = "Başarılı sonlandırma cc_finalize_if_active() üzerinden yapılmalıdır."
  )

  expect_true(
    grepl(
      'durum_metin\\s*=\\s*"Hata"[\\s\\S]{0,200}?sure\\s*=\\s*sure',
      txt,
      perl = TRUE
    ),
    info = "Hata sonlandırması cc_finalize_if_active() üzerinden yapılmalıdır."
  )

  hits <- gregexpr(
    "request_id\\s*=\\s*env\\$request_id",
    txt,
    perl = TRUE
  )[[1]]

  hit_count <- if (length(hits) == 1L && hits[1] == -1L) 0L else length(hits)

  expect_true(
    hit_count >= 2L,
    info = sprintf(
      "Sonlandırma çağrıları env$request_id ile korunmalıdır. Bulunan: %d",
      hit_count
    )
  )

  expect_true(
    grepl("cc_is_active_run\\(ctx\\$rv, ctx\\$env\\$request_id\\)", txt, perl = TRUE),
    info = "Çıktı işleme geri çağrıları stale request'e karşı korunmalıdır."
  )
})

test_that("çıktı toplama ve indirme staging çalıştırma başına bir kez yapılır", {
  poll_txt <- .read_repo_text_cc_run_lifecycle_contract(
    "R/module_claude_code_stream_poll.R"
  )

  expect_true(
    grepl("env\\$cikti_islendi\\s*<-\\s*TRUE", poll_txt, perl = TRUE),
    info = "Poll gözlemcisi çıktı işlemesini tek seferlik bayrakla korumalıdır."
  )

  expect_false(
    grepl("collect_claude_code_workdir_changes_downloads\\(", poll_txt, perl = TRUE),
    info = "Poll gözlemcisi indirme toplamayı doğrudan çağırmamalıdır."
  )

  expect_false(
    grepl("cc_collect_streaming_run_downloads\\(", poll_txt, perl = TRUE),
    info = "Poll gözlemcisi ikinci bir toplama çağrısı yapmamalıdır."
  )

  completion_txt <- .read_repo_text_cc_run_lifecycle_contract(
    "R/helpers_claude_code_run_completion.R"
  )

  hits <- gregexpr(
    "cc_collect_streaming_run_downloads\\(",
    completion_txt,
    perl = TRUE
  )[[1]]

  hit_count <- if (length(hits) == 1L && hits[1] == -1L) 0L else length(hits)

  expect_equal(
    hit_count,
    1L,
    info = "Çıktı worker'ı indirme toplamayı yalnızca bir kez çağırmalıdır."
  )
})

test_that("Bilge Yolaç stop observer UI finalization'ı poll observer'a bırakmaz", {
  tam_txt <- .read_repo_text_cc_run_lifecycle_contract("R/module_claude_code_stream_poll.R")

  # Yalnızca stop observer bloğu incelenir; poll bloğundaki süreç referansı
  # temizliği (yoklamayı durdurmak için) bu sözleşmenin kapsamı dışındadır.
  stop_baslangic <- regexpr(
    "shiny::observeEvent\\(input\\$stop_command",
    tam_txt,
    perl = TRUE
  )

  expect_true(stop_baslangic > 0L)

  txt <- substring(tam_txt, stop_baslangic)

  expect_true(
    grepl("shiny::observeEvent\\(input\\$stop_command", txt, perl = TRUE),
    info = "input$stop_command observer bloğu stream poll helper içinde bulunmalıdır."
  )

  expect_true(
    grepl("finalize_streaming\\(", txt, perl = TRUE),
    info = "Stop observer, poll observer'a güvenmeden finalize_streaming() çağırmalıdır."
  )

  expect_true(
    grepl("\"Durduruldu\"", txt, fixed = TRUE),
    info = "Stop observer kullanıcıya Durduruldu durumunu göndermelidir."
  )

  expect_true(
    grepl("cc-stream-end", txt, fixed = TRUE),
    info = "Stop observer istemcide açık stream mesajını kapatmalıdır."
  )

  expect_false(
    grepl("rv\\$active_process\\s*<-\\s*NULL", txt, perl = TRUE),
    info = "Stop observer active_process'i elle NULL yapmamalı; state temizliği finalize_streaming() içinde kalmalıdır."
  )

  expect_true(
    grepl(
      'finalize_streaming\\(\\s*"Durduruldu"\\s*,\\s*"stop-circle"\\s*,\\s*"#FFB74D"\\s*,\\s*request_id\\s*=\\s*request_id',
      txt,
      perl = TRUE
    ),
    info = "Stop observer stale finalize koruması için request_id ile finalize etmelidir."
  )
})

test_that("runtime lease bırakma idempotenttir", {
  env <- .source_cc_run_lifecycle_for_test()
  lease <- tempfile(fileext = ".lease")
  expect_true(file.create(lease))

  expect_true(env$cc_release_runtime_lease(lease))
  expect_false(file.exists(lease))
  expect_true(env$cc_release_runtime_lease(lease))
  expect_false(env$cc_release_runtime_lease(""))
})

test_that("terminal çalışma yolları runtime lease temizliğini taşır", {
  dispatch <- .read_repo_text_cc_run_lifecycle_contract(
    "R/helpers_claude_code_run_dispatch.R"
  )
  lifecycle <- .read_repo_text_cc_run_lifecycle_contract(
    "R/helpers_claude_code_run_lifecycle.R"
  )
  akis <- .read_repo_text_cc_run_lifecycle_contract("R/module_claude_code_akis.R")
  poll <- .read_repo_text_cc_run_lifecycle_contract(
    "R/module_claude_code_stream_poll.R"
  )

  expect_match(dispatch, "cc_release_runtime_lease\\(prep\\$runtime_lease", perl = TRUE)
  expect_match(dispatch, "runtime_lease = prep\\$runtime_lease", perl = TRUE)
  expect_match(lifecycle, "on.exit\\(cc_release_runtime_lease\\(runtime_lease\\)", perl = TRUE)
  expect_match(akis, "cc_release_runtime_lease\\(rv\\$stream_env\\$runtime_lease", perl = TRUE)
  expect_match(poll, "cc_release_runtime_lease\\(env\\$runtime_lease", perl = TRUE)
})

# ------------------------------------------------------------------------------
# DOKÜMAN ÖZETİ İZOLE ÇIKTI ALANINDA ÜRETİLİR
# ------------------------------------------------------------------------------

test_that("doküman özeti worker'ı kaynak klasöre yazmaz", {
  lifecycle_txt <- .read_repo_text_cc_run_lifecycle_contract(
    "R/helpers_claude_code_run_lifecycle.R"
  )
  dispatch_txt <- .read_repo_text_cc_run_lifecycle_contract(
    "R/helpers_claude_code_run_dispatch.R"
  )

  # REGRESYON: özet worker'ı output_dir = kaynak klasör ile çağrılıyordu ve
  # dosyayı promise geri çağrısındaki iptal kontrolünden ÖNCE yazıyordu.
  # Kullanıcı Durdur'a bastıktan sonra biten bir worker, iptal edilmiş bir
  # çalıştırmanın çıktısını kaynak klasördeki dosyanın üzerine yazabiliyordu.
  expect_true(
    grepl("cikti_dizini = NULL", lifecycle_txt, fixed = TRUE),
    info = "Özet handler'ı izole çıktı dizinini parametre olarak almalıdır."
  )

  expect_true(
    grepl("output_dir = worker_cikti_dizini", lifecycle_txt, fixed = TRUE),
    info = "Worker izole çıktı alanına yazmalıdır."
  )

  expect_false(
    grepl("output_dir = target_dir", lifecycle_txt, fixed = TRUE),
    info = "Worker doğrudan kaynak klasöre yazmaya geri dönmemelidir."
  )

  expect_true(
    grepl("cikti_dizini = prep$layout$output", dispatch_txt, fixed = TRUE),
    info = "Dispatch, hazırlıktan gelen izole çıktı alanını iletmelidir."
  )

  # Kaynak klasöre terfi yalnızca iptal korumasından SONRA yapılır.
  guard_pos <- regexpr("if \\(!cc_is_active_run\\(rv, run_request_id\\)\\)", lifecycle_txt, perl = TRUE)[[1]]
  write_pos <- regexpr("hedef_yol <- file\\.path\\(target_dir", lifecycle_txt, perl = TRUE)[[1]]

  expect_true(guard_pos > 0)
  expect_true(write_pos > guard_pos)
})

test_that("izole çıktı dizini yoksa mevcut davranışa güvenle düşülür", {
  env <- .source_cc_run_lifecycle_for_test()

  govde <- paste(deparse(body(env$cc_handle_document_summary_run)), collapse = "\n")

  expect_true(grepl("worker_cikti_dizini <- target_dir", govde, fixed = TRUE))
  expect_true(grepl("dir.exists(worker_cikti_dizini)", govde, fixed = TRUE))
})

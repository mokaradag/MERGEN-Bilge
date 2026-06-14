# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-run-streaming-behavior.R
# Açıklama: helpers_claude_code_streaming.R içindeki run_claude_code_streaming
#           davranışını doğrular. Bu fonksiyon Claude Code CLI'yi processx ile
#           canlı akış modunda çalıştırır; çıktıyı satır satır okuyup on_chunk'a
#           iletir, çıkış kodu/zaman aşımı/hata durumlarını yapılandırılmış
#           sonuç listesine çevirir.
#
#           processx::process$new SAHTE bir R6 benzeri nesneyle mock'lanır;
#           GERÇEK CLI ASLA başlatılmaz. Güvenlik politikası/CLI yol çözümü/JSON
#           ayrıştırma env içine stub'lanır. Çevrimdışı ve deterministik.
#           Kapsanan dallar: boş komut, CLI yok, workdir reddi, prompt yol reddi,
#           normal akış başarısı, sıfırdan farklı çıkış, zaman aşımı, süreç
#           başlatma hatası, on_chunk geri çağırma.
# ==============================================================================

# Türkçe yorum: helpers_claude_code_streaming.R'yi yalıtılmış ortama yükler ve
# tüm servis-bağlı bağımlılıkları güvenli stub'larla değiştirir.
.ccStreamEnv <- function() {
  env <- new.env(parent = globalenv())
  kok <- resolve_repo_root_for_tests()
  source(file.path(kok, "R", "helpers_claude_code_streaming.R"), encoding = "UTF-8", local = env)

  env$CLAUDE_CODE_LOG_PREFIX <- "[CC]"
  env$claude_code_config <- list(cli_path = "/sahte/claude")
  env$log_info <- function(...) invisible(NULL)
  env$log_warn <- function(...) invisible(NULL)
  env$log_error <- function(...) invisible(NULL)
  env$ensure_utf8 <- function(x) x
  env$resolve_claude_cli_path <- function(p) "/sahte/claude"
  env$cc_policy_validate_workdir <- function(workdir, allow_system_temp = TRUE) {
    list(ok = TRUE, path = workdir)
  }
  env$cc_policy_validate_prompt_file_intent <- function(prompt, workdir = NULL) list(ok = TRUE)
  env$cc_policy_build_cli_args <- function(...) c("--print", "merhaba")
  env$build_processx_command <- function(cli_path, args, workdir = NULL) {
    list(command = cli_path, args = args, env = NULL, wd = workdir, windows_verbatim_args = FALSE)
  }
  # Türkçe yorum: akış parçası ayrıştırma stub'ı -> on_chunk her satır için tetiklensin
  env$parse_streaming_chunk <- function(satir) list(raw = satir)
  env$parse_claude_code_json_output <- function(tum_cikti) {
    list(text_output = "Birleşik cevap", tool_uses = list(list(name = "Write")), session_id = "sess-1")
  }
  env
}

# Türkçe yorum: gerçek CLI başlatmadan processx::process$new yerine geçen sahte
# süreç nesnesi. is_alive sayacı 'alive_times' kez TRUE döner, sonra FALSE.
.makeFakeProc <- function(lines = character(0), exit = 0L, stderr = "",
                          alive_times = 1L, remaining = "") {
  fp <- new.env(parent = emptyenv())
  fp$alive_n <- 0L
  fp$read_n <- 0L
  fp$killed <- FALSE
  fp$is_alive <- function() { fp$alive_n <- fp$alive_n + 1L; fp$alive_n <= alive_times }
  fp$poll_io <- function(ms) invisible(NULL)
  fp$read_output_lines <- function() {
    fp$read_n <- fp$read_n + 1L
    if (fp$read_n == 1L) lines else character(0)
  }
  fp$read_all_output <- function() remaining
  fp$read_all_error <- function() stderr
  fp$get_exit_status <- function() exit
  fp$kill <- function() { fp$killed <- TRUE; invisible(NULL) }
  fp
}

test_that("run_claude_code_streaming boş komut için hata döner", {
  env <- .ccStreamEnv()
  res <- env$run_claude_code_streaming("   ", workdir = tempdir())
  expect_false(res$success)
  expect_true(grepl("boş olamaz", res$error))
  expect_identical(res$tool_uses, list())
})

test_that("run_claude_code_streaming CLI bulunamazsa hata döner", {
  env <- .ccStreamEnv()
  env$resolve_claude_cli_path <- function(p) NULL
  res <- env$run_claude_code_streaming("merhaba", workdir = tempdir(), cli_path = NULL)
  expect_false(res$success)
  expect_true(grepl("CLI bulunamadı", res$error, fixed = TRUE))
})

test_that("run_claude_code_streaming workdir politikası reddederse hata döner", {
  env <- .ccStreamEnv()
  env$cc_policy_validate_workdir <- function(workdir, allow_system_temp = TRUE) {
    list(ok = FALSE, error = "Çalışma dizini geçersiz.")
  }
  res <- env$run_claude_code_streaming("merhaba", workdir = "/kotu/yol", cli_path = "/sahte/claude")
  expect_false(res$success)
  expect_identical(res$error, "Çalışma dizini geçersiz.")
})

test_that("run_claude_code_streaming prompt yol politikası reddederse hata döner", {
  env <- .ccStreamEnv()
  env$cc_policy_validate_prompt_file_intent <- function(prompt, workdir = NULL) {
    list(ok = FALSE, error = "Yol dışı yazma reddedildi.")
  }
  res <- env$run_claude_code_streaming("../disari.txt yaz", workdir = tempdir(), cli_path = "/sahte/claude")
  expect_false(res$success)
  expect_identical(res$error, "Yol dışı yazma reddedildi.")
})

test_that("run_claude_code_streaming normal akışta başarılı sonuç ve ayrıştırma döner", {
  env <- .ccStreamEnv()
  fake <- .makeFakeProc(
    lines = c('{"type":"stream_event"}', '{"type":"result"}'),
    exit = 0L, alive_times = 1L
  )
  testthat::local_mocked_bindings(
    process = list(new = function(...) fake), .package = "processx"
  )
  res <- env$run_claude_code_streaming("merhaba", workdir = tempdir(), cli_path = "/sahte/claude")
  expect_true(res$success)
  expect_identical(res$output, "Birleşik cevap")
  expect_identical(res$session_id, "sess-1")
  expect_length(res$tool_uses, 1L)
  expect_identical(res$error, "")
})

test_that("run_claude_code_streaming her satır için on_chunk geri çağırmasını tetikler", {
  env <- .ccStreamEnv()
  fake <- .makeFakeProc(
    lines = c('{"a":1}', '{"b":2}'), exit = 0L, alive_times = 1L
  )
  testthat::local_mocked_bindings(
    process = list(new = function(...) fake), .package = "processx"
  )
  alinan <- new.env(parent = emptyenv()); alinan$chunks <- list()
  on_chunk <- function(parca) alinan$chunks[[length(alinan$chunks) + 1L]] <- parca
  env$run_claude_code_streaming("merhaba", workdir = tempdir(), cli_path = "/sahte/claude",
                                on_chunk = on_chunk)
  expect_length(alinan$chunks, 2L)
  expect_identical(alinan$chunks[[1]]$raw, '{"a":1}')
})

test_that("run_claude_code_streaming sıfırdan farklı çıkış kodunda hata döner", {
  env <- .ccStreamEnv()
  fake <- .makeFakeProc(
    lines = c('{"type":"stream_event"}'), exit = 1L,
    stderr = "CLI hata detayı", alive_times = 1L
  )
  testthat::local_mocked_bindings(
    process = list(new = function(...) fake), .package = "processx"
  )
  res <- env$run_claude_code_streaming("merhaba", workdir = tempdir(), cli_path = "/sahte/claude")
  expect_false(res$success)
  expect_true(grepl("CLI hata detayı", res$error, fixed = TRUE))
})

test_that("run_claude_code_streaming zaman aşımında süreci öldürüp hata döner", {
  env <- .ccStreamEnv()
  # Türkçe yorum: is_alive TRUE döner; timeout_sec=-1 ile ilk iterasyonda zaman aşımı
  fake <- .makeFakeProc(lines = character(0), exit = 0L, alive_times = 5L)
  testthat::local_mocked_bindings(
    process = list(new = function(...) fake), .package = "processx"
  )
  res <- env$run_claude_code_streaming("merhaba", workdir = tempdir(),
                                       cli_path = "/sahte/claude", timeout_sec = -1L)
  expect_false(res$success)
  expect_true(grepl("zaman aşımına uğradı", res$error, fixed = TRUE))
  # Türkçe yorum: zaman aşımında süreç öldürülmeli
  expect_true(fake$killed)
})

test_that("run_claude_code_streaming süreç başlatma hatasını yakalar", {
  env <- .ccStreamEnv()
  testthat::local_mocked_bindings(
    process = list(new = function(...) stop("süreç başlatılamadı")), .package = "processx"
  )
  res <- env$run_claude_code_streaming("merhaba", workdir = tempdir(), cli_path = "/sahte/claude")
  expect_false(res$success)
  expect_true(grepl("Claude Code çalıştırılırken hata oluştu", res$error, fixed = TRUE))
  expect_true(grepl("süreç başlatılamadı", res$error, fixed = TRUE))
})

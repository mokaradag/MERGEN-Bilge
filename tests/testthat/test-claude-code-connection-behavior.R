# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-connection-behavior.R
# Açıklama: helpers_claude_code.R check_claude_code_status() ve
#           test_claude_code_connection() için davranış testleri. CLI bulunamadı,
#           başarılı sürüm okuma, sıfırdan farklı çıkış kodu, zaman aşımı ve
#           süreç başlatma hatası dalları processx::process R6 üreticisi
#           mock'lanarak; bağlantı testi ise check_claude_code_status/run_claude_code
#           stub'lanarak doğrulanır. Çevrimdışı, deterministik; gerçek CLI/alt
#           süreç başlatılmaz.
# ==============================================================================

# helpers_claude_code.R'yi izole env'e source eder ve alt süreç bağımlılıklarını
# stub'lar. resolve_claude_cli_path varsayılan olarak geçerli bir yol döndürür.
.claudeStatusEnv <- function(cli_path = "/sahte/claude.cmd") {
  env <- new.env(parent = globalenv())
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_claude_code.R"),
         encoding = "UTF-8", local = env)

  env$claude_code_config <- list(cli_path = cli_path)
  env$resolve_claude_cli_path <- function(p = NULL) cli_path
  env$build_processx_command <- function(command, args, workdir = NULL) {
    list(command = command, args = args, env = character(0), wd = NULL,
         windows_verbatim_args = FALSE)
  }
  env$get_safe_processx_launch_workdir <- function() tempdir()
  env$ensure_utf8 <- function(x) x
  env$CLAUDE_CODE_LOG_PREFIX <- "[TEST]"
  env$log_warn <- function(...) invisible(NULL)
  env$log_error <- function(...) invisible(NULL)
  env
}

# Yapılandırılabilir sahte processx süreç nesnesi üreticisi.
.fakeProcessGenerator <- function(exit = 0L, out = "", err = "", alive = FALSE) {
  list(new = function(...) list(
    wait            = function(timeout = NULL) invisible(NULL),
    is_alive        = function() alive,
    read_all_output = function() out,
    read_all_error  = function() err,
    get_exit_status = function() exit,
    kill            = function() invisible(NULL)
  ))
}

testthat::test_that("check_claude_code_status CLI bulunamadığında installed=FALSE döner", {
  env <- .claudeStatusEnv()
  env$resolve_claude_cli_path <- function(p = NULL) NULL  # CLI yok

  r <- env$check_claude_code_status()
  testthat::expect_false(r$installed)
  testthat::expect_identical(r$version, "")
  testthat::expect_true(grepl("bulunamadı", r$error, fixed = TRUE))
})

testthat::test_that("check_claude_code_status başarılı sürüm okumada installed=TRUE döner", {
  env <- .claudeStatusEnv()

  testthat::local_mocked_bindings(
    process = .fakeProcessGenerator(exit = 0L, out = "  1.2.3\n"),
    .package = "processx"
  )

  r <- env$check_claude_code_status(cli_path = "/sahte/claude.cmd")
  testthat::expect_true(r$installed)
  testthat::expect_identical(r$version, "1.2.3")  # trimws uygulanır
  testthat::expect_identical(r$path, "/sahte/claude.cmd")
  testthat::expect_identical(r$error, "")
})

testthat::test_that("check_claude_code_status sıfırdan farklı çıkış kodunda hata detayı döndürür", {
  env <- .claudeStatusEnv()

  testthat::local_mocked_bindings(
    process = .fakeProcessGenerator(exit = 1L, out = "kismi", err = "patladi"),
    .package = "processx"
  )

  r <- env$check_claude_code_status(cli_path = "/sahte/claude.cmd")
  testthat::expect_false(r$installed)
  testthat::expect_true(grepl("Çıkış kodu: 1", r$error, fixed = TRUE))
  testthat::expect_true(grepl("patladi", r$error, fixed = TRUE))
})

testthat::test_that("check_claude_code_status süreç canlı kalırsa zaman aşımı raporlar", {
  env <- .claudeStatusEnv()

  testthat::local_mocked_bindings(
    process = .fakeProcessGenerator(alive = TRUE),
    .package = "processx"
  )

  r <- env$check_claude_code_status(cli_path = "/sahte/claude.cmd")
  testthat::expect_false(r$installed)
  testthat::expect_true(grepl("zaman aşımına uğradı", r$error, fixed = TRUE))
})

testthat::test_that("check_claude_code_status süreç başlatma hatasını yakalar", {
  env <- .claudeStatusEnv()

  patlayan_gen <- list(new = function(...) stop("başlatılamadı"))
  testthat::local_mocked_bindings(process = patlayan_gen, .package = "processx")

  r <- env$check_claude_code_status(cli_path = "/sahte/claude.cmd")
  testthat::expect_false(r$installed)
  testthat::expect_true(grepl("çalıştırılamadı", r$error, fixed = TRUE))
})

testthat::test_that("test_claude_code_connection CLI yoksa başarısız döner", {
  env <- .claudeStatusEnv()
  env$check_claude_code_status <- function(cli_path = NULL, workdir = NULL) {
    list(installed = FALSE, version = "", path = "", error = "yok")
  }

  r <- env$test_claude_code_connection(workdir = tempdir())
  testthat::expect_false(r$success)
  testthat::expect_true(grepl("bulunamadı veya erişilemez", r$message, fixed = TRUE))
  testthat::expect_identical(r$details, "yok")
})

testthat::test_that("test_claude_code_connection başarılı çalıştırmada başarı mesajı döndürür", {
  env <- .claudeStatusEnv()
  env$check_claude_code_status <- function(cli_path = NULL, workdir = NULL) {
    list(installed = TRUE, version = "1.2.3", path = "/sahte/claude.cmd", error = "")
  }
  env$run_claude_code <- function(prompt, workdir, model = NULL, timeout_sec = NULL, cli_path = NULL) {
    list(success = TRUE, output = "OK", error = "", duration = 2)
  }

  r <- env$test_claude_code_connection(workdir = tempdir())
  testthat::expect_true(r$success)
  testthat::expect_true(grepl("Bağlantı başarılı", r$message, fixed = TRUE))
  testthat::expect_true(grepl("1.2.3", r$message, fixed = TRUE))
})

testthat::test_that("test_claude_code_connection CLI çalışır ama API başarısızsa başarısız döner", {
  env <- .claudeStatusEnv()
  env$check_claude_code_status <- function(cli_path = NULL, workdir = NULL) {
    list(installed = TRUE, version = "1.2.3", path = "/sahte/claude.cmd", error = "")
  }
  env$run_claude_code <- function(prompt, workdir, model = NULL, timeout_sec = NULL, cli_path = NULL) {
    list(success = FALSE, output = "", error = "API hatası", duration = 1)
  }

  r <- env$test_claude_code_connection(workdir = tempdir())
  testthat::expect_false(r$success)
  testthat::expect_true(grepl("API bağlantısı başarısız", r$message, fixed = TRUE))
  testthat::expect_identical(r$details, "API hatası")
})

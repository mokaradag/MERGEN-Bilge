# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-downloads-security-behavior.R
# Açıklama: Bilge Yolaç üretilen-dosya indirme GÜVENLİK sınırını test eder
#           (Faz 5 adversarial). Mevcut downloads helper testi yalnızca
#           format/sanitize/download-root'u kapsıyordu; üretilen dosya yolu
#           çözümleme + staging'in "yalnızca izin verilen kökler içindeki
#           dosyalar indirilebilir kart olur" sözleşmesi davranışsal olarak
#           sınanmamıştı. Bu test gerçek yol politikasını yükleyerek şunları kilitler:
#             * resolve_claude_code_generated_path: izinli kök içi -> normalize
#               edilmiş yol; izinli kök DIŞINDAKİ var olan dosya -> ""; boş -> "".
#             * list_claude_code_generated_file_paths: yalnızca write/edit/file_write
#               araçları hedeflenir (read/bash yok sayılır); tekrarlar elenir;
#               kök-dışı yol düşürülür.
#             * stage_claude_code_downloads: kök-içi dosya geçici indirme köküne
#               kopyalanır (bilge_yolac_downloads URL'si); kök-dışı dosya düşürülür.
#           İndirme kökü options ile geçici dizine yönlendirilir (repo kirliliği
#           yok). Var olan dosyalar kullanıldığından 1.5sn bekleme döngülerine
#           girilmez. Gerçek CLI/süreç/DB/ağ GEREKMEZ.
# ==============================================================================

testthat::local_edition(3)

# Gerçek yol politikasıyla downloads yardımcılarını izole ortama yükler.
.ccdl_env <- function() {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  env$CLAUDE_CODE_LOG_PREFIX <- "[CC_TEST]"
  env$log_warn <- function(...) invisible(NULL)
  env$log_info <- function(...) invisible(NULL)
  # normalize_mcp_path kimlik benzeri: gerçek normalizePath (deterministik).
  env$normalize_mcp_path <- function(path, must_exist = FALSE) {
    normalizePath(path, winslash = "/", mustWork = FALSE)
  }
  source(file.path(repo_root, "R", "utils_common.R"), encoding = "UTF-8", local = env)
  source(file.path(repo_root, "R", "helpers_claude_code_path_policy.R"), encoding = "UTF-8", local = env)
  source(file.path(repo_root, "R", "helpers_claude_code_downloads.R"), encoding = "UTF-8", local = env)
  env
}

# ---------------------------------------------------------------------------
# resolve_claude_code_generated_path
# ---------------------------------------------------------------------------
testthat::test_that("resolve_claude_code_generated_path izinli kök içindeki mutlak dosyayı çözer", {
  env <- .ccdl_env()
  wd <- tempfile("ccdl_in_"); dir.create(wd)
  f <- file.path(wd, "rapor.txt"); writeLines("x", f)

  res <- env$resolve_claude_code_generated_path(f, allowed_roots = wd)

  testthat::expect_true(nzchar(res))
  testthat::expect_identical(res, normalizePath(f, winslash = "/", mustWork = FALSE))
})

testthat::test_that("resolve_claude_code_generated_path göreli yolu çalışma dizini altında çözer", {
  env <- .ccdl_env()
  wd <- tempfile("ccdl_rel_"); dir.create(wd)
  f <- file.path(wd, "cikti.txt"); writeLines("x", f)
  # cwd'yi wd yaparak ilk aday (ham göreli "cikti.txt") anında var olur -> bekleme yok.
  withr::local_dir(wd)

  res <- env$resolve_claude_code_generated_path("cikti.txt", runtime_workdir = wd, allowed_roots = wd)

  testthat::expect_true(endsWith(res, "cikti.txt"))
})

testthat::test_that("resolve_claude_code_generated_path izinli kök DIŞINDAKİ var olan dosyayı reddeder", {
  env <- .ccdl_env()
  allowed <- tempfile("ccdl_allow_"); dir.create(allowed)
  other <- tempfile("ccdl_other_"); dir.create(other)
  leak <- file.path(other, "sizinti.txt"); writeLines("x", leak)

  res <- env$resolve_claude_code_generated_path(leak, allowed_roots = allowed)

  testthat::expect_identical(res, "")
})

testthat::test_that("resolve_claude_code_generated_path boş yol için boş döner", {
  env <- .ccdl_env()
  testthat::expect_identical(env$resolve_claude_code_generated_path(""), "")
  testthat::expect_identical(env$resolve_claude_code_generated_path(NULL), "")
})

# ---------------------------------------------------------------------------
# list_claude_code_generated_file_paths
# ---------------------------------------------------------------------------
testthat::test_that("list_claude_code_generated_file_paths yalnızca write/edit araçlarını toplar ve tekrarı eler", {
  env <- .ccdl_env()
  wd <- tempfile("ccdl_list_"); dir.create(wd)
  writeLines("x", file.path(wd, "a.txt"))
  writeLines("x", file.path(wd, "b.txt"))
  withr::local_dir(wd)

  tool_uses <- list(
    list(name = "Write", input = list(file_path = "a.txt")),
    list(name = "Read",  input = list(file_path = "a.txt")),   # okuma yok sayılır
    list(name = "Edit",  input = list(path = "b.txt")),
    list(name = "Bash",  input = list(command = "ls")),         # bash yok sayılır
    list(name = "Write", input = list(file_path = "a.txt"))     # tekrar
  )

  res <- env$list_claude_code_generated_file_paths(tool_uses, runtime_workdir = wd, allowed_roots = wd)

  testthat::expect_length(res, 2L)
  testthat::expect_true(any(endsWith(res, "a.txt")))
  testthat::expect_true(any(endsWith(res, "b.txt")))
})

testthat::test_that("list_claude_code_generated_file_paths kök-dışı yazma yolunu düşürür", {
  env <- .ccdl_env()
  wd <- tempfile("ccdl_listin_"); dir.create(wd)
  other <- tempfile("ccdl_listout_"); dir.create(other)
  leak <- file.path(other, "sizinti.txt"); writeLines("x", leak)

  tool_uses <- list(list(name = "Write", input = list(file_path = leak)))
  res <- env$list_claude_code_generated_file_paths(tool_uses, runtime_workdir = wd, allowed_roots = wd)

  testthat::expect_length(res, 0L)
})

testthat::test_that("list_claude_code_generated_file_paths boş araç listesinde character(0) döner", {
  env <- .ccdl_env()
  testthat::expect_identical(env$list_claude_code_generated_file_paths(list()), character(0))
})

# ---------------------------------------------------------------------------
# stage_claude_code_downloads
# ---------------------------------------------------------------------------
testthat::test_that("stage_claude_code_downloads kök-içi dosyayı geçici indirme köküne kopyalar", {
  env <- .ccdl_env()
  dl_root <- tempfile("ccdl_root_"); dir.create(dl_root)
  withr::local_options(mergen.claude_code_download_root = dl_root)

  wd <- tempfile("ccdl_stagein_"); dir.create(wd)
  f <- file.path(wd, "özet.txt"); writeLines("içerik", f)

  res <- env$stage_claude_code_downloads(
    file_paths = f, user_id = 7L, session_token = "tok1", allowed_roots = wd
  )

  testthat::expect_length(res, 1L)
  testthat::expect_identical(res[[1]]$display_name, "özet.txt")
  testthat::expect_true(grepl("^bilge_yolac_downloads/", res[[1]]$url))
  # Dosya gerçekten geçici indirme kökü altına kopyalanmış olmalı.
  testthat::expect_true(startsWith(
    normalizePath(res[[1]]$download_path, winslash = "/", mustWork = FALSE),
    normalizePath(dl_root, winslash = "/", mustWork = FALSE)
  ))
})

testthat::test_that("stage_claude_code_downloads kök-dışı dosyayı kopyalamadan düşürür", {
  env <- .ccdl_env()
  dl_root <- tempfile("ccdl_root2_"); dir.create(dl_root)
  withr::local_options(mergen.claude_code_download_root = dl_root)

  allowed <- tempfile("ccdl_stageallow_"); dir.create(allowed)
  other <- tempfile("ccdl_stageother_"); dir.create(other)
  leak <- file.path(other, "sizinti.txt"); writeLines("x", leak)

  res <- env$stage_claude_code_downloads(
    file_paths = leak, user_id = 7L, session_token = "tok2", allowed_roots = allowed
  )

  testthat::expect_length(res, 0L)
  # İndirme kökü altında hiçbir dosya oluşmamalı.
  staged <- list.files(dl_root, recursive = TRUE)
  testthat::expect_length(staged, 0L)
})

testthat::test_that("stage_claude_code_downloads boş girdide boş liste döner", {
  env <- .ccdl_env()
  dl_root <- tempfile("ccdl_root3_"); dir.create(dl_root)
  withr::local_options(mergen.claude_code_download_root = dl_root)
  testthat::expect_identical(env$stage_claude_code_downloads(character(0)), list())
})

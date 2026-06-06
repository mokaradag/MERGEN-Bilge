# ==============================================================================
# Dosya Yolu: tests/testthat/test-normalize-claude-code-text-files-behavior.R
# Açıklama: normalize_claude_code_text_files (helpers_claude_code_workdir_snapshot.R)
#           orkestratörünün davranışsal testleri. Yalnızca izin verilen
#           uzantıları (txt/log/csv/md) normalize eder, başarıyla normalize
#           edilen yolları döndürür, boş/var olmayan/uzantısı eşleşmeyen
#           girdileri güvenle eler. Gerçek LLM/DB/ağ GEREKMEZ.
# ==============================================================================

.norm_text_files_env <- function() {
  env <- new.env(parent = globalenv())
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_claude_code_workdir_snapshot.R"),
         encoding = "UTF-8", local = env)
  env
}

testthat::test_that("normalize_claude_code_text_files boş girdide character(0) döner", {
  env <- .norm_text_files_env()
  testthat::expect_identical(env$normalize_claude_code_text_files(character(0)), character(0))
  testthat::expect_identical(env$normalize_claude_code_text_files(NULL), character(0))
})

testthat::test_that("normalize_claude_code_text_files yalnızca izin verilen uzantıları normalize eder", {
  env <- .norm_text_files_env()
  d <- file.path(tempdir(), paste0("nctf_", as.integer(runif(1, 1, 1e6))))
  dir.create(d, showWarnings = FALSE)
  on.exit(unlink(d, recursive = TRUE), add = TRUE)

  txt <- file.path(d, "a.txt"); writeLines("Türkçe: çğış", txt, useBytes = TRUE)
  md  <- file.path(d, "c.md");  writeLines("# Başlık", md, useBytes = TRUE)
  png <- file.path(d, "b.png"); writeBin(as.raw(c(1, 2, 3)), png)

  out <- env$normalize_claude_code_text_files(c(txt, png, md))

  # .txt ve .md normalize edilir; .png uzantısı elenir.
  testthat::expect_true(txt %in% out)
  testthat::expect_true(md %in% out)
  testthat::expect_false(png %in% out)
})

testthat::test_that("normalize_claude_code_text_files var olmayan dosyaları eler", {
  env <- .norm_text_files_env()
  d <- file.path(tempdir(), paste0("nctf2_", as.integer(runif(1, 1, 1e6))))
  dir.create(d, showWarnings = FALSE)
  on.exit(unlink(d, recursive = TRUE), add = TRUE)

  # Var olmayan .txt -> normalize başarısız -> sonuçta yok.
  testthat::expect_length(env$normalize_claude_code_text_files(file.path(d, "yok.txt")), 0L)
})

testthat::test_that("normalize_claude_code_text_files özel extensions argümanına uyar", {
  env <- .norm_text_files_env()
  d <- file.path(tempdir(), paste0("nctf3_", as.integer(runif(1, 1, 1e6))))
  dir.create(d, showWarnings = FALSE)
  on.exit(unlink(d, recursive = TRUE), add = TRUE)

  json_file <- file.path(d, "veri.json"); writeLines("{\"a\":1}", json_file, useBytes = TRUE)
  txt_file  <- file.path(d, "not.txt");   writeLines("metin", txt_file, useBytes = TRUE)

  # Yalnızca 'json' izinliyken .txt elenir, .json normalize edilir.
  out <- env$normalize_claude_code_text_files(c(json_file, txt_file), extensions = c("json"))
  testthat::expect_true(json_file %in% out)
  testthat::expect_false(txt_file %in% out)
})

# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-runtime-path-pure-behavior.R
# Açıklama: Bilge Yolaç runtime yol yardımcılarının saf davranışını doğrular:
#           is_windows_single_slash_network_path, .cc_runtime_workdir_token,
#           .cc_runtime_workdir_reusable. Çevrimdışı/deterministik.
# ==============================================================================

repo_root_cc_path <- resolve_repo_root_for_tests()

.cc_path_env <- new.env(parent = globalenv())
source(file.path(repo_root_cc_path, "R/utils_common.R"), encoding = "UTF-8", local = .cc_path_env)
source(file.path(repo_root_cc_path, "R/helpers_claude_code_process.R"), encoding = "UTF-8", local = .cc_path_env)
source(file.path(repo_root_cc_path, "R/helpers_claude_code_runtime_workdir.R"), encoding = "UTF-8", local = .cc_path_env)

test_that("is_windows_single_slash_network_path Windows dışında her zaman FALSE döner", {
  # Bu sözleşme, Linux/cloud çalışmalarında platform koruması olduğunu doğrular.
  skip_if(.Platform$OS.type == "windows", "Windows-dışı sözleşme testi")
  expect_false(.cc_path_env$is_windows_single_slash_network_path("/rehisds/uygulamalar"))
  expect_false(.cc_path_env$is_windows_single_slash_network_path("//server/share"))
  expect_false(.cc_path_env$is_windows_single_slash_network_path(""))
  expect_false(.cc_path_env$is_windows_single_slash_network_path(NULL))
})

test_that(".cc_runtime_workdir_token verilen token'ı temizleyip run_ önekiyle döner", {
  expect_identical(.cc_path_env$.cc_runtime_workdir_token("abc def!"), "run_abc_def")
  expect_identical(.cc_path_env$.cc_runtime_workdir_token("a/b\\c"), "run_a_b_c")
  expect_identical(.cc_path_env$.cc_runtime_workdir_token("__kenar__"), "run_kenar")
  expect_identical(.cc_path_env$.cc_runtime_workdir_token("Sade-123.txt"), "run_Sade-123.txt")
})

test_that(".cc_runtime_workdir_token boş token için benzersiz run_ değeri üretir", {
  t1 <- .cc_path_env$.cc_runtime_workdir_token("")
  t2 <- .cc_path_env$.cc_runtime_workdir_token(NULL)
  expect_true(startsWith(t1, "run_"))
  expect_true(startsWith(t2, "run_"))
  expect_true(nchar(t1) > nchar("run_"))
})

test_that(".cc_runtime_workdir_reusable yalnızca runtime alanı altındaki var olan klasörü kabul eder", {
  base <- tempfile("cc_runtime_test_")
  good <- file.path(base, "claude_code_runtime", "user_5", "run_x")
  dir.create(good, recursive = TRUE)
  on.exit(unlink(base, recursive = TRUE), add = TRUE)

  # Doğru kullanıcı + var olan klasör -> TRUE
  expect_true(.cc_path_env$.cc_runtime_workdir_reusable(good, user_id = 5))
  # Yanlış kullanıcı segmenti -> FALSE
  expect_false(.cc_path_env$.cc_runtime_workdir_reusable(good, user_id = 9))
  # Runtime alanı dışında -> FALSE
  expect_false(.cc_path_env$.cc_runtime_workdir_reusable(file.path(base, "baska", "yer"), user_id = 5))
  # Var olmayan klasör -> FALSE
  expect_false(.cc_path_env$.cc_runtime_workdir_reusable(
    file.path(base, "claude_code_runtime", "user_5", "yok"), user_id = 5))
  # Boş/NA -> FALSE
  expect_false(.cc_path_env$.cc_runtime_workdir_reusable("", user_id = 5))
  expect_false(.cc_path_env$.cc_runtime_workdir_reusable(NA_character_, user_id = 5))
})

test_that(".cc_runtime_workdir_reusable default kullanıcı segmentini de destekler", {
  base <- tempfile("cc_runtime_def_")
  good <- file.path(base, "claude_code_runtime", "user_default", "run_y")
  dir.create(good, recursive = TRUE)
  on.exit(unlink(base, recursive = TRUE), add = TRUE)

  expect_true(.cc_path_env$.cc_runtime_workdir_reusable(good, user_id = NULL))
})

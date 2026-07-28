# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-runtime-workdir-contract.R
# Açıklama: Bilge Yolaç runtime çalışma dizini helper extraction ve eşzamanlı
#           çalıştırma güvenliği sözleşmesini doğrular.
# ==============================================================================

.read_repo_text_cc_runtime_workdir_contract <- function(path) {
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

.extract_safe_source_paths_cc_runtime_workdir <- function(text) {
  m <- gregexpr(
    'safe_source\\("([^"]+)"\\s*,\\s*encoding\\s*=\\s*"UTF-8"',
    text,
    perl = TRUE,
    useBytes = TRUE
  )

  hits <- regmatches(text, m)[[1]]
  if (length(hits) == 0 || identical(hits, character(0))) {
    return(character(0))
  }

  sub(
    '.*safe_source\\("([^"]+)".*',
    "\\1",
    hits,
    perl = TRUE,
    useBytes = TRUE
  )
}

.source_cc_runtime_workdir_for_test <- function() {
  repo_root <- resolve_repo_root_for_tests()
  test_env <- new.env(parent = globalenv())

  test_env$`%||%` <- function(x, y) {
    if (is.null(x)) y else x
  }

  test_env$log_info <- function(...) invisible(NULL)
  test_env$log_warn <- function(...) invisible(NULL)
  test_env$log_error <- function(...) invisible(NULL)
  test_env$CLAUDE_CODE_LOG_PREFIX <- "[TEST]"
  test_env$normalize_mcp_path <- function(path, must_exist = FALSE) {
    normalizePath(path, winslash = "/", mustWork = must_exist)
  }

  # Runtime hazırlık zinciri: sınırlar -> sınırlı tarayıcı -> hazırlık
  # yardımcıları -> runtime workdir. İzole test bu sırayı korumalıdır.
  for (dosya in c(
    "config_claude_code.R",
    "helpers_claude_code_bounded_scan.R",
    "helpers_claude_code_input_matching.R",
    "helpers_claude_code_runtime_prepare.R",
    "helpers_claude_code_output_sync.R",
    "helpers_claude_code_runtime_resolver.R",
    "helpers_claude_code_runtime_workdir.R"
  )) {
    source(
      file.path(repo_root, "R", dosya),
      encoding = "UTF-8",
      local = test_env
    )
  }

  test_env
}
test_that("Claude Code runtime workdir yardımcıları ayrı dosyaya taşınmıştır", {
  repo_root <- resolve_repo_root_for_tests()

  expect_true(file.exists(file.path(
    repo_root,
    "R",
    "helpers_claude_code_runtime_workdir.R"
  )))

  runtime_text <- .read_repo_text_cc_runtime_workdir_contract(
    "R/helpers_claude_code_runtime_workdir.R"
  )
  old_text <- .read_repo_text_cc_runtime_workdir_contract(
    "R/helpers_claude_code.R"
  )

  moved_functions <- c(
    "get_user_workspace",
    "is_problematic_windows_workdir",
    "mirror_directory_to_local_workspace",
    "prepare_claude_runtime_workdir",
    "sync_claude_runtime_workdir_back"
  )

  for (fn in moved_functions) {
    pattern <- paste0(fn, "\\s*<-\\s*function\\s*\\(")

    expect_true(
      grepl(pattern, runtime_text, perl = TRUE),
      info = sprintf(
        "%s R/helpers_claude_code_runtime_workdir.R içinde tanımlı olmalıdır.",
        fn
      )
    )

    expect_false(
      grepl(pattern, old_text, perl = TRUE),
      info = sprintf(
        "%s R/helpers_claude_code.R içine geri taşınmamalıdır.",
        fn
      )
    )
  }
})

test_that("Claude Code runtime workdir helper source sırası korunur", {
  expect_source_manifest_order_for_tests(
    c(
      "R/helpers_claude_code_process.R",
      "R/helpers_claude_code_runtime_resolver.R",
      "R/helpers_claude_code_runtime_workdir.R",
      "R/helpers_claude_code.R",
      "R/helpers_claude_code_server_setup.R"
    ),
    label = "Claude Code runtime workdir source sırası bozulmuş:"
  )
})

test_that("Claude Code runtime workdir helper dosyası parse ve source edilebilir kalır", {
  repo_root <- resolve_repo_root_for_tests()

  expect_silent(parse(
    file.path(repo_root, "R", "helpers_claude_code_runtime_workdir.R"),
    encoding = "UTF-8"
  ))

  expect_silent(.source_cc_runtime_workdir_for_test())
})

test_that("runtime workdir aynalama çalışma başına benzersiz dizin kullanır", {
  test_env <- .source_cc_runtime_workdir_for_test()

  source_dir <- withr::local_tempdir()
  writeLines("merhaba", file.path(source_dir, "girdi.txt"), useBytes = TRUE)

  # Test platformu Windows olmasa bile problemli path dalını sözleşme olarak
  # doğrulamak için bu helper test ortamında zorlanır.
  test_env$is_problematic_windows_workdir <- function(path) TRUE

  first <- test_env$prepare_claude_runtime_workdir(
    source_dir,
    user_id = 42L,
    runtime_token = "request-a"
  )

  second <- test_env$prepare_claude_runtime_workdir(
    source_dir,
    user_id = 42L,
    runtime_token = "request-b"
  )

  expect_true(isTRUE(first$mirrored))
  expect_true(isTRUE(second$mirrored))

  expect_true(dir.exists(first$runtime_workdir))
  expect_true(dir.exists(second$runtime_workdir))

  expect_false(
    identical(first$runtime_workdir, second$runtime_workdir),
    info = "Aynı kullanıcı için farklı çalışma istekleri aynı runtime klasörünü paylaşmamalıdır."
  )

  expect_false(
    grepl("/active_dir$", first$runtime_workdir),
    info = "Eski paylaşılan active_dir runtime klasörü yeniden kullanılmamalıdır."
  )

  expect_false(
    grepl("/active_dir$", second$runtime_workdir),
    info = "Eski paylaşılan active_dir runtime klasörü yeniden kullanılmamalıdır."
  )

  # Kaynak klasörün TAMAMI kopyalanmaz; gerekli girdiler izole `input`
  # bölmesine aktarılır ve runtime düzeni input/output/metadata içerir.
  expect_true(file.exists(file.path(first$runtime_workdir, "input", "girdi.txt")))
  expect_true(file.exists(file.path(second$runtime_workdir, "input", "girdi.txt")))

  expect_true(dir.exists(file.path(first$runtime_workdir, "output")))
  expect_true(dir.exists(file.path(first$runtime_workdir, "metadata")))
  expect_true(dir.exists(file.path(first$runtime_workdir, "document_support")))
})

test_that("çalışma request kimliği runtime workdir token olarak geçirilir", {
  # Hazırlık ana Shiny sürecinden arka plan worker'ına taşındığı için bu
  # çağrı artık hazırlık görevi dosyasında yaşar.
  module_text <- .read_repo_text_cc_runtime_workdir_contract(
    "R/helpers_claude_code_run_prepare_task.R"
  )

  expect_true(
    grepl(
      "prepare_claude_runtime_workdir\\s*\\([\\s\\S]*runtime_token\\s*=\\s*request\\$request_id",
      module_text,
      perl = TRUE
    ),
    info = paste(
      "R/helpers_claude_code_run_prepare_task.R prepare_claude_runtime_workdir()",
      "çağrısında runtime_token = request$request_id geçmelidir."
    )
  )
})

test_that("prepare_claude_runtime_workdir mevcut runtime workdir verildiğinde yeniden kullanır", {
  test_env <- .source_cc_runtime_workdir_for_test()

  # Kaynak dizin: takip eden çağrılar arasında değişen bir dosya simüle et
  source_dir <- withr::local_tempdir()
  writeLines("ilk", file.path(source_dir, "girdi.txt"), useBytes = TRUE)

  test_env$is_problematic_windows_workdir <- function(path) TRUE

  ilk <- test_env$prepare_claude_runtime_workdir(
    source_dir,
    user_id = 42L,
    runtime_token = "first-request"
  )

  expect_true(isTRUE(ilk$mirrored))
  expect_false(isTRUE(ilk$reused %||% FALSE))
  expect_true(dir.exists(ilk$runtime_workdir))

  # Aynı sohbette gelen takip çağrısında runtime workdir'i yeniden kullan:
  # Claude CLI --resume oturum metadatası buraya bağlı olduğundan yeni
  # runtime klasörü "No conversation found with session ID" hatasına yol açar.
  writeLines("yeni", file.path(source_dir, "ek.txt"), useBytes = TRUE)

  ikinci <- test_env$prepare_claude_runtime_workdir(
    source_dir,
    user_id = 42L,
    runtime_token = "second-request",
    existing_runtime_workdir = ilk$runtime_workdir
  )

  expect_true(isTRUE(ikinci$mirrored))
  expect_true(isTRUE(ikinci$reused))
  expect_identical(ikinci$runtime_workdir, ilk$runtime_workdir)

  # Takip çağrısında kaynak klasör yeniden aynalanmaz; yalnızca gerekli
  # girdi dosyaları input bölmesinde tazelenir.
  expect_true(file.exists(file.path(ikinci$runtime_workdir, "input", "girdi.txt")))
  expect_true(file.exists(file.path(ikinci$runtime_workdir, "input", "ek.txt")))
})

test_that("prepare_claude_runtime_workdir farklı kullanıcı kovasındaki runtime'ı yeniden kullanmaz", {
  test_env <- .source_cc_runtime_workdir_for_test()

  source_dir <- withr::local_tempdir()
  writeLines("merhaba", file.path(source_dir, "girdi.txt"), useBytes = TRUE)

  test_env$is_problematic_windows_workdir <- function(path) TRUE

  # Başka kullanıcının runtime klasörünü taklit eden geçici bir yol oluştur.
  baska_user_runtime <- file.path(
    tempdir(),
    "claude_code_runtime",
    "user_999",
    "run_other"
  )
  dir.create(baska_user_runtime, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(baska_user_runtime, recursive = TRUE, force = TRUE), add = TRUE)

  sonuc <- test_env$prepare_claude_runtime_workdir(
    source_dir,
    user_id = 42L,
    runtime_token = "fresh-request",
    existing_runtime_workdir = baska_user_runtime
  )

  # Başka kullanıcının runtime klasörü güvenlik nedeniyle kullanılmamalı;
  # taze bir klasör oluşturulmalı.
  expect_true(isTRUE(sonuc$mirrored))
  expect_false(isTRUE(sonuc$reused %||% FALSE))
  expect_false(identical(sonuc$runtime_workdir, baska_user_runtime))
})

test_that("Claude CLI runtime workdir'i takip çağrıları için yeniden kullanılır", {
  dispatch_text <- .read_repo_text_cc_runtime_workdir_contract(
    "R/helpers_claude_code_run_dispatch.R"
  )

  expect_true(
    grepl(
      "existing_runtime_workdir\\s*=\\s*mevcut_runtime",
      dispatch_text,
      perl = TRUE
    ),
    info = paste(
      "R/helpers_claude_code_run_dispatch.R hazırlık isteğinde mevcut runtime",
      "klasörünü existing_runtime_workdir ile geçmelidir."
    )
  )

  expect_true(
    grepl(
      "rv\\$active_runtime_workdir\\s*<-",
      dispatch_text,
      perl = TRUE
    ),
    info = paste(
      "R/helpers_claude_code_run_dispatch.R aynalama yapıldığında runtime",
      "klasörünü rv$active_runtime_workdir alanında saklamalıdır."
    )
  )

  expect_true(
    grepl(
      "rv\\$active_runtime_source\\s*<-",
      dispatch_text,
      perl = TRUE
    ),
    info = paste(
      "R/helpers_claude_code_run_dispatch.R aynalama yapıldığında kaynak",
      "workdir'i rv$active_runtime_source alanında saklamalıdır."
    )
  )
})

test_that("runtime workdir tek slash ağ yolunu relaxed resolver ile aynalar", {
  test_env <- .source_cc_runtime_workdir_for_test()

  source_dir <- withr::local_tempdir()
  writeLines("merhaba", file.path(source_dir, "girdi.txt"), useBytes = TRUE)

  test_env$is_problematic_windows_workdir <- function(path) {
    grepl("^/rehisds|^//rehisds", gsub("\\\\", "/", path), perl = TRUE)
  }

  test_env$cc_resolve_existing_dir_relaxed <- function(dir_path) {
    if (identical(gsub("\\\\", "/", dir_path), "/rehisds/uygulamalar/Primavera/PY")) {
      return(source_dir)
    }

    ""
  }

  sonuc <- test_env$prepare_claude_runtime_workdir(
    "/rehisds/uygulamalar/Primavera/PY",
    user_id = 42L,
    runtime_token = "single-slash-network-path"
  )

  expect_true(isTRUE(sonuc$mirrored))
  expect_true(dir.exists(sonuc$runtime_workdir))
  expect_true(file.exists(file.path(sonuc$runtime_workdir, "input", "girdi.txt")))
  expect_equal(sonuc$source_workdir, source_dir)
})
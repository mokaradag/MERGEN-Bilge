# ==============================================================================
# Dosya Yolu: tests/testthat/test-claude-code-directory-listing-contract.R
# Açıklama: Bilge Yolaç dizin listeleme helper refactor sözleşmesini korur.
# ==============================================================================

.read_repo_text_cc_dir_listing_contract <- function(path) {
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

.extract_safe_source_paths_cc_dir_listing <- function(text) {
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

.source_claude_code_directory_listing_for_test <- function() {
  repo_root <- resolve_repo_root_for_tests()
  test_env <- new.env(parent = globalenv())

  test_env$`%||%` <- function(x, y) {
    if (is.null(x)) y else x
  }

  test_env$path_exists_relaxed <- function(path) {
    isTRUE(file.exists(path)) || isTRUE(dir.exists(path))
  }

  test_env$normalize_mcp_path <- function(path, must_exist = FALSE) {
    normalizePath(path, winslash = "/", mustWork = FALSE)
  }

  test_env$.load_index <- function() {
    list()
  }

  test_env$mergen_resolve_display_name <- function(path, user_id = NULL, idx = list()) {
    uid <- suppressWarnings(as.integer(user_id %||% NA_integer_))
    if (!is.na(uid) && identical(uid, 42L) && identical(basename(path), "internal.txt")) {
      return("yüklenen_özet.txt")
    }

    basename(path)
  }

  source(
    file.path(repo_root, "R", "helpers_claude_code_directory_listing.R"),
    encoding = "UTF-8",
    local = test_env
  )

  test_env
}

test_that("Claude Code dizin listeleme yardımcıları ayrı dosyada tutulur", {
  repo_root <- resolve_repo_root_for_tests()

  expect_true(file.exists(file.path(repo_root, "R", "helpers_claude_code_directory_listing.R")))

  helper_text <- .read_repo_text_cc_dir_listing_contract(
    "R/helpers_claude_code_directory_listing.R"
  )
  old_text <- .read_repo_text_cc_dir_listing_contract(
    "R/helpers_claude_code.R"
  )

  moved_functions <- c(
    "cc_build_dir_variants",
    "cc_list_dir_relaxed",
    "cc_resolve_dir_display_name",
    "cc_normalize_dir_entry",
    "list_directory_contents"
  )

  for (fn in moved_functions) {
    pattern <- paste0(fn, "\\s*<-\\s*function\\s*\\(")

    expect_true(
      grepl(pattern, helper_text, perl = TRUE),
      info = sprintf("%s R/helpers_claude_code_directory_listing.R içinde tanımlı olmalıdır.", fn)
    )
  }

  expect_false(
    grepl("list_directory_contents\\s*<-\\s*function\\s*\\(", old_text, perl = TRUE),
    info = "list_directory_contents() geniş helpers_claude_code.R dosyasına geri taşınmamalıdır."
  )
})

test_that("Claude Code dizin listeleme helper source sırası korunur", {
  expect_source_manifest_order_for_tests(
    c(
      "R/helpers_claude_code_runtime_workdir.R",
      "R/helpers_claude_code_directory_listing.R",
      "R/helpers_claude_code.R",
      "R/helpers_claude_code_server_setup.R",
      "R/module_claude_code.R"
    ),
    label = "Claude Code dizin listeleme source sırası bozulmuş:"
  )
})

test_that("Claude Code dizin listeleme helper parse ve source edilebilir kalır", {
  repo_root <- resolve_repo_root_for_tests()

  expect_silent(parse(
    file.path(repo_root, "R", "helpers_claude_code_directory_listing.R"),
    encoding = "UTF-8"
  ))

  expect_silent(.source_claude_code_directory_listing_for_test())
})

test_that("Claude Code dizin listeleme davranışı ve Türkçe görünen ad korunur", {
  skip_if_not_installed("fs")

  test_env <- .source_claude_code_directory_listing_for_test()
  tmp <- withr::local_tempdir()

  dir.create(file.path(tmp, "src"), recursive = TRUE, showWarnings = FALSE)
  file.create(file.path(tmp, "internal.txt"))

  sonuc <- test_env$list_directory_contents(
    tmp,
    max_items = 10L,
    user_id = 42L
  )

  expect_true(isTRUE(sonuc$success))
  expect_equal(sonuc$error, "")
  expect_equal(sonuc$toplam, 2L)
  expect_equal(
    normalizePath(sonuc$resolved_path, winslash = "/", mustWork = TRUE),
    normalizePath(tmp, winslash = "/", mustWork = TRUE)
  )

  expect_equal(length(sonuc$items), 2L)
  expect_equal(sonuc$items[[1]]$tip, "klasor")
  expect_equal(sonuc$items[[1]]$gorunen_ad, "src")

  file_item <- sonuc$items[[2]]
  expect_equal(file_item$tip, "dosya")
  expect_equal(file_item$ad, "internal.txt")
  expect_equal(file_item$gorunen_ad, "yüklenen_özet.txt")
})

test_that("Claude Code dizin listeleme SSO ve stale refresh guard sözleşmesi korunur", {
  setup_text <- .read_repo_text_cc_dir_listing_contract(
    "R/helpers_claude_code_server_setup.R"
  )

  guard_pos <- regexpr(
    'ensure_ready_user_id\\("proje dizini listeleme"\\)',
    setup_text,
    perl = TRUE
  )[[1]]

  call_pos <- regexpr(
    "list_directory_contents\\(",
    setup_text,
    perl = TRUE
  )[[1]]

  expect_true(
    guard_pos > 0,
    info = "Dizin listeleme öncesinde kullanıcı kimliği hazır olma kontrolü kalmalıdır."
  )

  expect_true(
    call_pos > guard_pos,
    info = "list_directory_contents() kullanıcı kimliği hazır olmadan çağrılmamalıdır."
  )

  # Listeleme artık arka plan worker'ında da çalışabildiği için stale koruması
  # tek bir uygulama fonksiyonunda toplanmıştır: senkron ve eşzamansız yolun
  # ikisi de sonucu bu fonksiyondan geçirir.
  uygula_pos <- regexpr("uygula_icerik <- function\\(icerik\\)", setup_text, perl = TRUE)[[1]]

  expect_true(
    uygula_pos > 0,
    info = "Dizin listeleme sonucu tek bir stale korumalı uygulama fonksiyonundan geçmelidir."
  )

  uygula_govde <- substring(setup_text, uygula_pos, uygula_pos + 900L)

  expect_true(
    regexpr("dir_refresh_guard\\$is_latest\\(refresh_id\\)", uygula_govde, perl = TRUE)[[1]] <
      regexpr("sendCustomMessage", uygula_govde, perl = TRUE)[[1]],
    info = "UI güncellenmeden ÖNCE stale refresh guard kontrolü yapılmalıdır."
  )

  expect_true(
    grepl("uygula_icerik(list_directory_contents(", setup_text, fixed = TRUE),
    info = "Senkron yedek yol da sonucu stale korumalı uygulama fonksiyonuna vermelidir."
  )
})

test_that("dizin gezgini numaralandırması ana olay döngüsünden çıkarılabilir", {
  setup_text <- .read_repo_text_cc_dir_listing_contract(
    "R/helpers_claude_code_server_setup.R"
  )

  # REGRESYON: yüz binlerce girdili düz/UNC bir klasörde list.files() +
  # öge başına file.info() ana Shiny olay döngüsünde çalıştığında aynı R
  # sürecini paylaşan TÜM oturumlar donuyordu.
  expect_true(
    grepl("cc_dir_listing_async_available()", setup_text, fixed = TRUE),
    info = "Eşzamansız plan varlığı kontrol edilmelidir."
  )

  expect_true(
    grepl("claude_code_dir_listing", setup_text, fixed = TRUE),
    info = "Dizin listeleme izlenen bir worker görevi olarak gönderilmelidir."
  )

  expect_true(
    grepl("dependency_mode = \"explicit\"", setup_text, fixed = TRUE),
    info = "Gönderim anında bağımlılık taraması yapılmamalıdır (explicit mod)."
  )

  async_text <- .read_repo_text_cc_dir_listing_contract(
    "R/helpers_claude_code_dir_listing_async.R"
  )

  expect_true(
    grepl(".cc_dir_listing_worker_cache$globals", async_text, fixed = TRUE),
    info = "Worker global paketi süreç başına bir kez önbelleklenmelidir."
  )

  expect_true(
    grepl("if (!isTRUE(refresh) && !is.null(.cc_dir_listing_worker_cache$globals))",
          async_text, fixed = TRUE),
    info = "Önbellek refresh = FALSE çağrılarında yeniden kurulmamalıdır."
  )
})
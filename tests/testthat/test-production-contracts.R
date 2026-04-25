# ==============================================================================
# Dosya Yolu: tests/testthat/test-production-contracts.R
# Açıklama: Üretim sertleştirme sözleşmelerini statik olarak doğrular.
# Bu testler uygulamayı başlatmaz; dosya yapısı, parse edilebilirlik,
# source manifesti ve async sarmalayıcı disiplinini kontrol eder.
# ==============================================================================

.find_repo_root <- function() {
  adaylar <- unique(normalizePath(
    c(
      getwd(),
      file.path(getwd(), ".."),
      file.path(getwd(), "..", "..")
    ),
    winslash = "/",
    mustWork = FALSE
  ))

  for (aday in adaylar) {
    if (file.exists(file.path(aday, "app.R")) &&
        dir.exists(file.path(aday, "R"))) {
      return(aday)
    }
  }

  stop("Repo kökü bulunamadı.", call. = FALSE)
}

.repo_root <- .find_repo_root()

# Uyarı üretmeyen dosya okuyucu.
# readLines(encoding=...) bazı suite koşullarında encoding warning üretebildiği
# için production-contract testlerinde raw okuma kullanıyoruz.
.read_text_quiet <- function(path) {
  size <- suppressWarnings(file.info(path)$size[1])
  if (is.na(size) || size <= 0) {
    return("")
  }

  con <- file(path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_data <- readBin(con, what = "raw", n = size)

  txt <- suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
  )

  if (is.na(txt)) {
    txt <- ""
  }

  txt <- gsub("\r\n?|\r", "\n", txt, perl = TRUE)
  enc2utf8(txt)
}

.has_text <- function(haystack, needle) {
  isTRUE(suppressWarnings(grepl(
    needle,
    haystack,
    fixed = TRUE,
    useBytes = TRUE
  )))
}

test_that("kritik üretim giriş dosyaları UTF-8 ile parse edilebilir", {
  r_files <- file.path(
    .repo_root,
    c(
      "app.R",
      "global.R",
      "ui.R",
      "server.R",
      "welcome_screen.R",

      # Temel altyapı
      "R/utils_safe_source.R",
      "R/utils_common.R",
      "R/utils_safe_path.R",
      "R/utils_atomic_write.R",
      "R/utils_upload_validator.R",
      "R/utils_log_redact.R",
      "R/utils_session_cleanup.R",
      "R/utils_safe_worker_run.R",
      "R/utils_file_index.R",
      "R/utils_excel_reader.R",

      # Yapılandırma ve DB
      "R/config_file_store.R",
      "R/config_logging.R",
      "R/config_sso.R",
      "R/config_api.R",
      "R/helpers_database.R",
      "R/library_queries.R",
      "R/config_sql_loader.R",

      # LLM / SSE / worker hattı
      "R/helpers_worker_monitor.R",
      "R/helpers_llm_response_postprocess.R",
      "R/helpers_llm_api.R",
      "R/helpers_llm_sse.R",
      "R/helpers_llm_worker.R",
      "R/server_handler_true_streaming.R",
      "R/server_send_message.R",

      # Dosya, MCP, özetleme, proje analizi
      "R/helpers_mcp_tools.R",
      "R/helpers_files.R",
      "R/helpers_send_message_core.R",
      "R/module_file_manager.R",
      "R/module_summarization.R",
      "R/module_proje_kaynak_analizi.R",

      # Bilge Yolaç / health
      "R/module_claude_code.R",
      "R/helpers_claude_code.R",
      "R/module_health.R",
      "R/helpers_health_checks.R"
    )
  )

  r_files <- unique(r_files[file.exists(r_files)])

  expect_gt(length(r_files), 10L)

  parse_errors <- character(0)

  for (f in r_files) {
    file_label <- normalizePath(f, winslash = "/", mustWork = FALSE)

    err <- tryCatch(
      {
        suppressWarnings(
          parse(file = f, encoding = "UTF-8", keep.source = FALSE)
        )
        NULL
      },
      error = function(e) e
    )

    if (!is.null(err)) {
      parse_errors <- c(
        parse_errors,
        sprintf("%s\n  -> %s", file_label, conditionMessage(err))
      )
    }
  }

  expect_equal(
    parse_errors,
    character(0),
    label = paste(parse_errors, collapse = "\n\n")
  )
})

test_that("global.R üretim sertleştirme helper'larını manifestte yüklüyor", {
  global_text <- .read_text_quiet(file.path(.repo_root, "global.R"))

  beklenenler <- c(
    'safe_source("R/utils_safe_path.R"',
    'safe_source("R/utils_atomic_write.R"',
    'safe_source("R/utils_upload_validator.R"',
    'safe_source("R/utils_log_redact.R"',
    'safe_source("R/utils_session_cleanup.R"',
    'safe_source("R/utils_safe_worker_run.R"',
    'safe_source("R/helpers_worker_monitor.R"'
  )

  bulunanlar <- vapply(
    beklenenler,
    function(beklenen) .has_text(global_text, beklenen),
    logical(1)
  )

  expect_true(
    all(bulunanlar),
    label = paste("Eksik source kayıtları:", paste(beklenenler[!bulunanlar], collapse = ", "))
  )
})

test_that("app.R doğrudan source edildiğinde otomatik çalışma kapısı korunuyor", {
  app_text <- .read_text_quiet(file.path(.repo_root, "app.R"))

  beklenenler <- c(
    "validate_boot_state <- function",
    "create_mergen_app <- function",
    "run_mergen_app <- function",
    "MERGEN_RUN_APP",
    "auto_run <- .env_flag_is_true",
    "if (isTRUE(auto_run))"
  )

  bulunanlar <- vapply(
    beklenenler,
    function(beklenen) .has_text(app_text, beklenen),
    logical(1)
  )

  expect_true(
    all(bulunanlar),
    label = paste("Eksik app.R boot kayıtları:", paste(beklenenler[!bulunanlar], collapse = ", "))
  )
})

test_that("kritik async altyapısında future_promise merkezi sarmalayıcı arkasında kalıyor", {
  # Önceki sürüm tüm R/ klasörünü recursive tarıyordu. Full test_dir koşumunda
  # bu geniş tarama warning fırtınası oluşturabiliyor. Burada yalnızca async
  # disiplininin kritik dosyaları denetlenir.
  kontrol_dosyalari <- file.path(
    .repo_root,
    c(
      "R/helpers_worker_monitor.R",
      "R/helpers_llm_worker.R",
      "R/server_handler_true_streaming.R",
      "R/server_send_message.R",
      "R/module_file_manager.R",
      "R/module_summarization.R",
      "R/module_image_generation.R",
      "R/module_proje_kaynak_analizi.R"
    )
  )

  kontrol_dosyalari <- unique(kontrol_dosyalari[file.exists(kontrol_dosyalari)])

  expect_gt(length(kontrol_dosyalari), 3L)

  izinli_dosya <- normalizePath(
    file.path(.repo_root, "R", "helpers_worker_monitor.R"),
    winslash = "/",
    mustWork = FALSE
  )

  ihlaller <- character(0)

  for (f in kontrol_dosyalari) {
    f_norm <- normalizePath(f, winslash = "/", mustWork = FALSE)
    txt <- .read_text_quiet(f)

    ham_future_var <- isTRUE(suppressWarnings(grepl(
      "(^|[^A-Za-z0-9_.])future_promise\\s*\\(",
      txt,
      perl = TRUE,
      useBytes = TRUE
    ))) || isTRUE(suppressWarnings(grepl(
      "promises::future_promise\\s*\\(",
      txt,
      perl = TRUE,
      useBytes = TRUE
    )))

    if (ham_future_var && !identical(f_norm, izinli_dosya)) {
      ihlaller <- c(ihlaller, f_norm)
    }
  }

  ihlaller <- unique(ihlaller)

  expect_equal(
    ihlaller,
    character(0),
    label = paste("Doğrudan future_promise kullanan kritik dosyalar:", paste(ihlaller, collapse = ", "))
  )
})

test_that("test runner Shiny/future başlatmayı kapatan env bayraklarını içeriyor", {
  runner_path <- file.path(.repo_root, "tests", "testthat.R")

  expect_true(file.exists(runner_path))

  runner_text <- .read_text_quiet(runner_path)

  beklenenler <- c(
    'MERGEN_RUN_APP = "false"',
    'MERGEN_DISABLE_FUTURES = "true"',
    "stop_on_failure = TRUE",
    "stop_on_warning = TRUE"
  )

  bulunanlar <- vapply(
    beklenenler,
    function(beklenen) .has_text(runner_text, beklenen),
    logical(1)
  )

  expect_true(
    all(bulunanlar),
    label = paste("Eksik test runner güvenlik kayıtları:", paste(beklenenler[!bulunanlar], collapse = ", "))
  )
})
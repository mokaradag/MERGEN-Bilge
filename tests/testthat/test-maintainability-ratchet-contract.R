# ==============================================================================
# Dosya Yolu: tests/testthat/test-maintainability-ratchet-contract.R
# Açıklama: Büyük dosyaların daha da büyümesini engelleyen bakım borcu ratchet
#           sözleşmesini doğrular. library_queries.R bilinçli olarak hariçtir.
# ==============================================================================

.read_repo_text_maintainability <- function(path) {
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

.count_functions_maintainability <- function(txt) {
  hits <- gregexpr(
    "(<-|=)\\s*function\\s*\\(",
    txt,
    perl = TRUE
  )[[1]]

  if (identical(hits[1], -1L)) {
    return(0L)
  }

  length(hits)
}

.collect_runtime_report_maintainability <- function(repo_root) {
  runtime_files <- c(
    file.path(repo_root, "app.R"),
    file.path(repo_root, "global.R"),
    file.path(repo_root, "ui.R"),
    file.path(repo_root, "server.R"),
    file.path(repo_root, "welcome_screen.R"),
    list.files(
      file.path(repo_root, "R"),
      pattern = "\\.R$",
      recursive = TRUE,
      full.names = TRUE
    )
  )

  runtime_files <- unique(runtime_files[file.exists(runtime_files)])

  rows <- lapply(runtime_files, function(path) {
    rel_path <- sub(
      paste0(
        "^",
        gsub("([\\^$.|?*+(){}\\[\\]\\\\])", "\\\\\\1", repo_root),
        "/?"
      ),
      "",
      normalizePath(path, winslash = "/", mustWork = TRUE),
      perl = TRUE
    )

    txt <- .read_repo_text_maintainability(path)
    lines <- strsplit(txt, "\n", fixed = TRUE)[[1]]

    data.frame(
      file = rel_path,
      lines = length(lines),
      functions = .count_functions_maintainability(txt),
      stringsAsFactors = FALSE
    )
  })

  report <- do.call(rbind, rows)

  # library_queries.R bilgi tabanı olduğu için ratchet kapsamına alınmaz.
  report <- subset(report, !grepl("(^|/)library_queries\\.R$", file, perl = TRUE))

  report[order(report$lines, decreasing = TRUE), ]
}

.maintainability_baseline <- data.frame(
  file = c(
    "R/helpers_mcp_tools.R",
    "R/module_claude_code.R",
    "R/helpers_claude_code.R",
    "R/module_proje_kaynak_analizi.R",
    "R/module_file_manager.R",
    "R/module_admin_yanit_analizi.R",
    "R/module_admin_geri_bildirim.R",
    "R/module_admin_hata_analizi.R",
    "R/helpers_database.R",
    "R/module_settings_yapilandirma.R",
    "R/helpers_llm_worker.R",
    "R/helpers_claude_code_documents.R",
    "R/server_send_message.R",
    "R/config_api.R",
    "R/helpers_llm_sse.R",
    "R/config_file_store.R",
    "R/module_image_generation.R",
    "R/server_ai_expert_handlers.R",
    "R/module_startup_screen.R",
    "R/module_ai_expert.R",
    "R/helpers_claude_code_workdir_snapshot.R",
    "R/server_handler_true_streaming.R",
    "R/helpers_deep_analysis.R",
    "R/helpers_ai_expert.R",
    "R/helpers_chartlab.R",
    "R/helpers_language.R",
    "ui.R",
    "R/module_chartlab.R",
    "R/helpers_chat_runtime.R"
  ),
  baseline_lines = c(
    2378L,
    1749L,
    1672L,
    1580L,
    1496L,
    1273L,
    1247L,
    1225L,
    1099L,
    1065L,
    1027L,
    941L,
    878L,
    866L,
    858L,
    788L,
    765L,
    726L,
    695L,
    686L,
    662L,
    662L,
    627L,
    619L,
    577L,
    572L,
    539L,
    532L,
    523L
  ),
  baseline_functions = c(
    99L,
    30L,
    66L,
    28L,
    50L,
    8L,
    10L,
    13L,
    38L,
    5L,
    13L,
    31L,
    17L,
    26L,
    27L,
    45L,
    22L,
    23L,
    5L,
    22L,
    31L,
    17L,
    12L,
    19L,
    44L,
    3L,
    0L,
    20L,
    14L
  ),
  stringsAsFactors = FALSE
)

test_that("mevcut büyük dosyalar kontrolsüz şekilde büyümüyor", {
  repo_root <- resolve_repo_root_for_tests()
  current <- .collect_runtime_report_maintainability(repo_root)

  merged <- merge(
    .maintainability_baseline,
    current,
    by = "file",
    all.x = TRUE
  )

  # Bir dosya refactor edilip küçültülmüş/taşınmış olabilir; bu iyi bir şeydir.
  merged <- merged[!is.na(merged$lines), , drop = FALSE]

  line_limit <- merged$baseline_lines + pmax(25L, ceiling(merged$baseline_lines * 0.05))
  function_limit <- merged$baseline_functions + pmax(3L, ceiling(merged$baseline_functions * 0.10))

  line_violations <- merged$file[merged$lines > line_limit]
  function_violations <- merged$file[merged$functions > function_limit]

  expect_equal(
    line_violations,
    character(0),
    info = paste(
      "Satır sayısı ratchet limitini aşan dosyalar:",
      paste(line_violations, collapse = ", ")
    )
  )

  expect_equal(
    function_violations,
    character(0),
    info = paste(
      "Fonksiyon sayısı ratchet limitini aşan dosyalar:",
      paste(function_violations, collapse = ", ")
    )
  )
})

test_that("yeni büyük monolit dosya eklenmiyor", {
  repo_root <- resolve_repo_root_for_tests()
  current <- .collect_runtime_report_maintainability(repo_root)

  known_files <- .maintainability_baseline$file
  new_files <- subset(current, !(file %in% known_files))

  new_large_files <- subset(new_files, lines >= 800L | functions >= 25L)

  expect_equal(
    new_large_files$file,
    character(0),
    info = paste(
      "Yeni büyük/monolit aday dosyalar:",
      paste(new_large_files$file, collapse = ", ")
    )
  )
})
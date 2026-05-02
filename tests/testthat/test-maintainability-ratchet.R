# ==============================================================================
# Dosya Yolu: tests/testthat/test-maintainability-ratchet.R
# Açıklama: Maintainability skorunun ve büyük dosya sayaçlarının mevcut
#           üretim taban çizgisinin altına düşmesini engeller.
# ==============================================================================

.find_repo_root_maint_ratchet <- function() {
  candidates <- unique(normalizePath(
    c(
      getwd(),
      file.path(getwd(), ".."),
      file.path(getwd(), "..", "..")
    ),
    winslash = "/",
    mustWork = FALSE
  ))

  for (candidate in candidates) {
    if (file.exists(file.path(candidate, "app.R")) &&
        dir.exists(file.path(candidate, "tests", "scripts"))) {
      return(candidate)
    }
  }

  stop("Repo kökü bulunamadı.", call. = FALSE)
}

.as_int_env <- function(name, default) {
  raw <- Sys.getenv(name, as.character(default))
  value <- suppressWarnings(as.integer(raw))

  if (is.na(value)) {
    stop(sprintf("%s geçersiz: %s", name, raw), call. = FALSE)
  }

  value
}

test_that("maintainability skoru mevcut taban çizgisinin altına düşmez", {
  repo_root <- .find_repo_root_maint_ratchet()
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(repo_root)

  maint_env <- new.env(parent = globalenv())
  report <- source(
    "tests/scripts/maintainability_report.R",
    encoding = "UTF-8",
    local = maint_env
  )$value

  score <- attr(report, "maintainability_score", exact = TRUE)

  expect_true(
    is.numeric(score) || is.integer(score),
    info = "maintainability_report.R attr(..., 'maintainability_score') üretmelidir."
  )

  min_score <- .as_int_env("MERGEN_TEST_MIN_MAINTAINABILITY_SCORE", 67L)

  expect_true(
    score >= min_score,
    info = sprintf(
      "Maintainability skoru geriledi: %s/100 < minimum %s/100.",
      score,
      min_score
    )
  )
})

test_that("büyük dosya ve fonksiyon sayaçları mevcut taban çizgisinden kötüye gitmez", {
  repo_root <- .find_repo_root_maint_ratchet()
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(repo_root)

  maint_env <- new.env(parent = globalenv())
  report <- source(
    "tests/scripts/maintainability_report.R",
    encoding = "UTF-8",
    local = maint_env
  )$value

  score_report <- attr(report, "score_report", exact = TRUE)

  expect_true(
    is.data.frame(score_report),
    info = "maintainability_report.R attr(..., 'score_report') üretmelidir."
  )

  max_large_files <- .as_int_env("MERGEN_TEST_MAX_800_LINE_FILES", 7L)
  max_function_heavy_files <- .as_int_env("MERGEN_TEST_MAX_25_FUNCTION_FILES", 6L)
  max_very_large_files <- .as_int_env("MERGEN_TEST_MAX_1500_LINE_FILES", 0L)
  max_file_lines <- .as_int_env("MERGEN_TEST_MAX_FILE_LINES", 1024L)
  max_file_functions <- .as_int_env("MERGEN_TEST_MAX_FILE_FUNCTIONS", 44L)

  actual_large_files <- sum(score_report$lines >= 800)
  actual_function_heavy_files <- sum(score_report$functions >= 25)
  actual_very_large_files <- sum(score_report$lines >= 1500)
  actual_max_lines <- max(score_report$lines, na.rm = TRUE)
  actual_max_functions <- max(score_report$functions, na.rm = TRUE)

  expect_true(
    actual_large_files <= max_large_files,
    info = sprintf(
      "800+ satır dosya sayısı arttı: %d > %d.",
      actual_large_files,
      max_large_files
    )
  )

  expect_true(
    actual_function_heavy_files <= max_function_heavy_files,
    info = sprintf(
      "25+ fonksiyon dosya sayısı arttı: %d > %d.",
      actual_function_heavy_files,
      max_function_heavy_files
    )
  )

  expect_true(
    actual_very_large_files <= max_very_large_files,
    info = sprintf(
      "1500+ satır dosya sayısı arttı: %d > %d.",
      actual_very_large_files,
      max_very_large_files
    )
  )

  expect_true(
    actual_max_lines <= max_file_lines,
    info = sprintf(
      "En büyük dosya satırı arttı: %d > %d.",
      actual_max_lines,
      max_file_lines
    )
  )

  expect_true(
    actual_max_functions <= max_file_functions,
    info = sprintf(
      "En yüksek fonksiyon sayısı arttı: %d > %d.",
      actual_max_functions,
      max_file_functions
    )
  )
})

test_that("module_claude_code.R setup extraction kazanımı geri alınmaz", {
  repo_root <- .find_repo_root_maint_ratchet()
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(repo_root)

  maint_env <- new.env(parent = globalenv())
  report <- source(
    "tests/scripts/maintainability_report.R",
    encoding = "UTF-8",
    local = maint_env
  )$value

  cc_row <- report[
    grepl("(^|/)R/module_claude_code\\.R$", report$file, perl = TRUE),
    ,
    drop = FALSE
  ]

  expect_equal(
    nrow(cc_row),
    1L,
    info = "R/module_claude_code.R maintainability raporunda tek satır olarak görünmelidir."
  )

  max_cc_lines <- .as_int_env("MERGEN_TEST_MAX_CLAUDE_CODE_LINES", 960L)

  expect_true(
    cc_row$lines[1] <= max_cc_lines,
    info = sprintf(
      "module_claude_code.R setup extraction sonrası küçülmüş kalmalıdır: %d > %d.",
      cc_row$lines[1],
      max_cc_lines
    )
  )
})

test_that("helpers_llm_sse.R akış I/O ayrımı sonrası ince kalır", {
  repo_root <- .find_repo_root_maint_ratchet()
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(repo_root)

  maint_env <- new.env(parent = globalenv())
  report <- source(
    "tests/scripts/maintainability_report.R",
    encoding = "UTF-8",
    local = maint_env
  )$value

  sse_row <- report[
    grepl("(^|/)R/helpers_llm_sse\\.R$", report$file, perl = TRUE),
    ,
    drop = FALSE
  ]

  expect_equal(
    nrow(sse_row),
    1L,
    info = "R/helpers_llm_sse.R maintainability raporunda tek satır olarak görünmelidir."
  )

  max_sse_lines <- .as_int_env("MERGEN_TEST_MAX_LLM_SSE_LINES", 799L)
  max_sse_functions <- .as_int_env("MERGEN_TEST_MAX_LLM_SSE_FUNCTIONS", 24L)

  expect_true(
    sse_row$lines[1] <= max_sse_lines,
    info = sprintf(
      "helpers_llm_sse.R stream I/O ayrımı sonrası 800 satır altı kalmalıdır: %d > %d.",
      sse_row$lines[1],
      max_sse_lines
    )
  )

  expect_true(
    sse_row$functions[1] <= max_sse_functions,
    info = sprintf(
      "helpers_llm_sse.R fonksiyon sayısı stream I/O ayrımı sonrası 25 altı kalmalıdır: %d > %d.",
      sse_row$functions[1],
      max_sse_functions
    )
  )
})

test_that("helpers_llm_worker.R payload extraction kazanımı geri alınmaz", {
  repo_root <- .find_repo_root_maint_ratchet()
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(repo_root)

  maint_env <- new.env(parent = globalenv())
  report <- source(
    "tests/scripts/maintainability_report.R",
    encoding = "UTF-8",
    local = maint_env
  )$value

  worker_row <- report[
    grepl("(^|/)R/helpers_llm_worker\\.R$", report$file, perl = TRUE),
    ,
    drop = FALSE
  ]

  payload_row <- report[
    grepl("(^|/)R/helpers_llm_worker_payload\\.R$", report$file, perl = TRUE),
    ,
    drop = FALSE
  ]

  expect_equal(
    nrow(worker_row),
    1L,
    info = "R/helpers_llm_worker.R maintainability raporunda tek satır olarak görünmelidir."
  )

  expect_equal(
    nrow(payload_row),
    1L,
    info = "R/helpers_llm_worker_payload.R maintainability raporunda tek satır olarak görünmelidir."
  )

  max_worker_lines <- .as_int_env("MERGEN_TEST_MAX_LLM_WORKER_LINES", 860L)
  max_payload_lines <- .as_int_env("MERGEN_TEST_MAX_LLM_WORKER_PAYLOAD_LINES", 320L)
  max_payload_functions <- .as_int_env("MERGEN_TEST_MAX_LLM_WORKER_PAYLOAD_FUNCTIONS", 12L)

  expect_true(
    worker_row$lines[1] <= max_worker_lines,
    info = sprintf(
      "helpers_llm_worker.R payload extraction sonrası küçülmüş kalmalıdır: %d > %d.",
      worker_row$lines[1],
      max_worker_lines
    )
  )

  expect_true(
    payload_row$lines[1] <= max_payload_lines,
    info = sprintf(
      "helpers_llm_worker_payload.R küçük saf helper dosyası olarak kalmalıdır: %d > %d.",
      payload_row$lines[1],
      max_payload_lines
    )
  )

  expect_true(
    payload_row$functions[1] <= max_payload_functions,
    info = sprintf(
      "helpers_llm_worker_payload.R fonksiyon sayısı kontrollü kalmalıdır: %d > %d.",
      payload_row$functions[1],
      max_payload_functions
    )
  )
})

test_that("helpers_mcp_tools.R refactor kazanımı geri alınmaz", {
  repo_root <- .find_repo_root_maint_ratchet()
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(repo_root)

  maint_env <- new.env(parent = globalenv())
  report <- source(
    "tests/scripts/maintainability_report.R",
    encoding = "UTF-8",
    local = maint_env
  )$value

  mcp_row <- report[grepl("(^|/)R/helpers_mcp_tools\\.R$", report$file, perl = TRUE), , drop = FALSE]

  expect_equal(
    nrow(mcp_row),
    1L,
    info = "R/helpers_mcp_tools.R maintainability raporunda tek satır olarak görünmelidir."
  )

  max_mcp_lines <- .as_int_env("MERGEN_TEST_MAX_MCP_TOOLS_LINES", 700L)
  max_mcp_functions <- .as_int_env("MERGEN_TEST_MAX_MCP_TOOLS_FUNCTIONS", 24L)

  expect_true(
    mcp_row$lines[1] <= max_mcp_lines,
    info = sprintf(
      "helpers_mcp_tools.R satır sayısı refactor sonrası taban çizgisini aştı: %d > %d.",
      mcp_row$lines[1],
      max_mcp_lines
    )
  )

  expect_true(
    mcp_row$functions[1] <= max_mcp_functions,
    info = sprintf(
      "helpers_mcp_tools.R fonksiyon sayısı refactor sonrası taban çizgisini aştı: %d > %d.",
      mcp_row$functions[1],
      max_mcp_functions
    )
  )
})

test_that("module_admin_geri_bildirim.R refactor kazanımı geri alınmaz", {
  repo_root <- .find_repo_root_maint_ratchet()
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(repo_root)

  maint_env <- new.env(parent = globalenv())
  report <- source(
    "tests/scripts/maintainability_report.R",
    encoding = "UTF-8",
    local = maint_env
  )$value

  gb_row <- report[grepl("(^|/)R/module_admin_geri_bildirim\\.R$", report$file, perl = TRUE), , drop = FALSE]

  expect_equal(
    nrow(gb_row),
    1L,
    info = "R/module_admin_geri_bildirim.R maintainability raporunda tek satır olarak görünmelidir."
  )

  max_gb_lines <- .as_int_env("MERGEN_TEST_MAX_ADMIN_GERI_BILDIRIM_LINES", 951L)
  max_gb_functions <- .as_int_env("MERGEN_TEST_MAX_ADMIN_GERI_BILDIRIM_FUNCTIONS", 8L)

  expect_true(
    gb_row$lines[1] <= max_gb_lines,
    info = sprintf(
      "module_admin_geri_bildirim.R satır sayısı refactor sonrası taban çizgisini aştı: %d > %d.",
      gb_row$lines[1],
      max_gb_lines
    )
  )

  expect_true(
    gb_row$functions[1] <= max_gb_functions,
    info = sprintf(
      "module_admin_geri_bildirim.R fonksiyon sayısı refactor sonrası taban çizgisini aştı: %d > %d.",
      gb_row$functions[1],
      max_gb_functions
    )
  )
})

test_that("module_admin_hata_analizi.R helper extraction kazanımı geri alınmaz", {
  repo_root <- .find_repo_root_maint_ratchet()
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(repo_root)

  maint_env <- new.env(parent = globalenv())
  report <- source(
    "tests/scripts/maintainability_report.R",
    encoding = "UTF-8",
    local = maint_env
  )$value

  hata_row <- report[
    grepl("(^|/)R/module_admin_hata_analizi\\.R$", report$file, perl = TRUE),
    ,
    drop = FALSE
  ]

  expect_equal(
    nrow(hata_row),
    1L,
    info = "R/module_admin_hata_analizi.R maintainability raporunda tek satır olarak görünmelidir."
  )

  max_hata_lines <- .as_int_env("MERGEN_TEST_MAX_ADMIN_HATA_ANALIZI_LINES", 799L)

  expect_true(
    hata_row$lines[1] <= max_hata_lines,
    info = sprintf(
      "module_admin_hata_analizi.R helper extraction sonrası 800 satır altı kalmalıdır: %d > %d.",
      hata_row$lines[1],
      max_hata_lines
    )
  )

  helper_row <- report[
    grepl("(^|/)R/helpers_admin_hata_analizi\\.R$", report$file, perl = TRUE),
    ,
    drop = FALSE
  ]

  expect_equal(
    nrow(helper_row),
    1L,
    info = "R/helpers_admin_hata_analizi.R maintainability raporunda tek satır olarak görünmelidir."
  )

  max_helper_lines <- .as_int_env("MERGEN_TEST_MAX_ADMIN_HATA_HELPER_LINES", 799L)
  max_helper_functions <- .as_int_env("MERGEN_TEST_MAX_ADMIN_HATA_HELPER_FUNCTIONS", 20L)

  expect_true(
    helper_row$lines[1] <= max_helper_lines,
    info = sprintf(
      "helpers_admin_hata_analizi.R 800 satır altı kalmalıdır: %d > %d.",
      helper_row$lines[1],
      max_helper_lines
    )
  )

  expect_true(
    helper_row$functions[1] <= max_helper_functions,
    info = sprintf(
      "helpers_admin_hata_analizi.R fonksiyon sayısı kontrollü kalmalıdır: %d > %d.",
      helper_row$functions[1],
      max_helper_functions
    )
  )
})

test_that("module_admin_yanit_analizi.R refactor kazanımı geri alınmaz", {
  repo_root <- .find_repo_root_maint_ratchet()
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(repo_root)

  maint_env <- new.env(parent = globalenv())
  report <- source(
    "tests/scripts/maintainability_report.R",
    encoding = "UTF-8",
    local = maint_env
  )$value

  yanit_row <- report[
    grepl("(^|/)R/module_admin_yanit_analizi\\.R$", report$file, perl = TRUE),
    ,
    drop = FALSE
  ]

  expect_equal(
    nrow(yanit_row),
    1L,
    info = "R/module_admin_yanit_analizi.R maintainability raporunda tek satır olarak görünmelidir."
  )

  max_yanit_lines <- .as_int_env("MERGEN_TEST_MAX_ADMIN_YANIT_ANALIZI_LINES", 799L)

  expect_true(
    yanit_row$lines[1] <= max_yanit_lines,
    info = sprintf(
      "module_admin_yanit_analizi.R refactor sonrası 800 satır altı kalmalıdır: %d > %d.",
      yanit_row$lines[1],
      max_yanit_lines
    )
  )
})
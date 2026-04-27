# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-analysis-maintainability-contract.R
# Açıklama: İlk güvenli refactor hedefinin bakım skorunu gerçekten iyileştirdiğini
#           doğrular: module_proje_kaynak_analizi.R 1500 satır ve 25 fonksiyon
#           eşiklerinin altına düşmelidir.
# ==============================================================================

.read_repo_text_pk_metric <- function(rel_path) {
  abs_path <- file.path(repo_root_for_tests, rel_path)

  if (!file.exists(abs_path)) {
    stop(sprintf("Dosya bulunamadı: %s", rel_path), call. = FALSE)
  }

  size <- suppressWarnings(file.info(abs_path)$size[1])
  if (is.na(size) || size <= 0) {
    return("")
  }

  con <- file(abs_path, open = "rb")
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

.count_functions_pk_metric <- function(txt) {
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

.file_metrics_pk <- function(rel_path) {
  txt <- .read_repo_text_pk_metric(rel_path)
  lines <- strsplit(txt, "\n", fixed = TRUE)[[1]]

  data.frame(
    path = rel_path,
    lines = length(lines),
    functions = .count_functions_pk_metric(txt),
    stringsAsFactors = FALSE
  )
}

test_that("module_proje_kaynak_analizi.R crosses below the next maintainability thresholds", {
  metrics <- .file_metrics_pk("R/module_proje_kaynak_analizi.R")

	expect_true(
	  metrics$lines < 1500L,
	  info = paste(
		"R/module_proje_kaynak_analizi.R 1500+ satır eşiğinin altına düşmeli.",
		"Bu, maintainability_score için gerçek +5 puan etkisi yaratır.",
		sprintf("Mevcut satır: %d", metrics$lines)
	  )
	)

	expect_true(
	  metrics$functions < 25L,
	  info = paste(
		"R/module_proje_kaynak_analizi.R 25+ fonksiyon eşiğinin altına düşmeli.",
		"Bu, maintainability_score için gerçek +2 puan etkisi yaratır.",
		sprintf("Mevcut fonksiyon: %d", metrics$functions)
	  )
	)
})

test_that("helpers_pk_analysis_core.R remains intentionally small and side-effect-light", {
  metrics <- .file_metrics_pk("R/helpers_pk_analysis_core.R")
  txt <- .read_repo_text_pk_metric("R/helpers_pk_analysis_core.R")

	expect_true(
	  metrics$lines < 300L,
	  info = sprintf(
		"R/helpers_pk_analysis_core.R küçük kalmalıdır. Mevcut satır: %d",
		metrics$lines
	  )
	)

	expect_true(
	  metrics$functions <= 10L,
	  info = sprintf(
		paste(
		  "R/helpers_pk_analysis_core.R küçük kalmalıdır.",
		  "Bu metrik anonim/nested function ifadelerini de sayar.",
		  "Beklenen üst sınır 10'dur. Mevcut fonksiyon ifadesi: %d"
		),
		metrics$functions
	  )
	)

  expect_false(
    grepl("call_local_llm\\s*\\(", txt, perl = TRUE),
    info = "PK core helper dosyası LLM çağrısı başlatmamalıdır."
  )

  expect_false(
    grepl("observeEvent\\s*\\(|renderUI\\s*\\(|shiny::runApp", txt, perl = TRUE),
    info = "PK core helper dosyası Shiny observer/render/runtime davranışı içermemelidir."
  )

  expect_false(
    grepl("dbConnect\\s*\\(|odbc::", txt, perl = TRUE),
    info = "PK core helper dosyası canlı DB bağlantısı açmamalıdır."
  )
})
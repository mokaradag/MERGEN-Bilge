# ==============================================================================
# Dosya Yolu: tests/testthat/test-llm-worker-tool-results-refactor-contract.R
# Açıklama: helpers_llm_worker.R içinden ayrılan MCP araç sonucu biçimlendirme
#           yardımcılarının davranış ve snapshot sözleşmesini korur.
# ==============================================================================

.find_repo_root_llm_worker_tool_results <- function() {
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
        dir.exists(file.path(candidate, "R"))) {
      return(candidate)
    }
  }

  stop("Repo kökü bulunamadı.", call. = FALSE)
}

.read_repo_text_llm_worker_tool_results <- function(path) {
  repo_root <- .find_repo_root_llm_worker_tool_results()
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

repo_root_llm_worker_tool_results <- .find_repo_root_llm_worker_tool_results()

if (!exists("%||%", mode = "function", inherits = TRUE)) {
  `%||%` <- function(x, y) if (is.null(x)) y else x
}

mergen_debug_cat <- function(...) invisible(NULL)

source(
  file.path(repo_root_llm_worker_tool_results, "R", "helpers_llm_worker_payload.R"),
  encoding = "UTF-8",
  local = environment()
)

source(
  file.path(repo_root_llm_worker_tool_results, "R", "helpers_llm_worker_tool_results_preview.R"),
  encoding = "UTF-8",
  local = environment()
)

source(
  file.path(repo_root_llm_worker_tool_results, "R", "helpers_llm_worker_tool_results.R"),
  encoding = "UTF-8",
  local = environment()
)

test_that("araç sonucu data frame olarak LLM prompt metnine davranış korunarak çevrilir", {
  raw_results <- list(
    list(
      preview = data.frame(
        kaynak = c("P6", "SAP"),
        tutar = c(10, 20),
        source_table = c("P6", "SAP"),
        stringsAsFactors = FALSE
      ),
      sql_effective = "SELECT * FROM t",
      dropped_all_na_columns = c("bos_kolon")
    )
  )

  out <- llm_worker_format_tool_results_for_prompt(
    tool_calls = list(list(function_name = "sql_query_uploaded_file")),
    tool_results_raw = raw_results
  )

  expect_type(out, "list")
  expect_equal(length(out$tool_results), 1L)
  expect_equal(out$tool_results[[1]]$tool, "sql_query_uploaded_file")

  result_text <- out$tool_results[[1]]$result

  expect_true(grepl("VERİTABANINDAN GELEN GERÇEK VERİ", result_text, fixed = TRUE))
  expect_true(grepl("SQL Sorgusu: SELECT * FROM t", result_text, fixed = TRUE))
  expect_true(grepl("Dönen Toplam Satır: 2", result_text, fixed = TRUE))
  expect_true(grepl("Dönen Toplam Sütun: 3", result_text, fixed = TRUE))
  expect_true(grepl("source_table değerleri: P6, SAP", result_text, fixed = TRUE))
  expect_true(grepl("Tamamen NA olduğu için gizlenen sütunlar: bos_kolon", result_text, fixed = TRUE))
  expect_true(grepl("| kaynak | tutar | source_table |", result_text, fixed = TRUE))
  expect_equal(out$results_text, trimws(result_text))
})

test_that("karakter vektörü döndüren araçlar atomik $ erişimiyle kırılmaz", {
  out <- llm_worker_format_tool_results_for_prompt(
    tool_calls = list(list(function_name = "plain_text_tool")),
    tool_results_raw = list(c("birinci satır", "ikinci satır"))
  )

  expect_equal(out$tool_results[[1]]$tool, "plain_text_tool")
  expect_equal(out$tool_results[[1]]$result, "birinci satır\n\nikinci satır")
  expect_equal(out$results_text, "birinci satır\n\nikinci satır")
})

test_that("grafik araç sonuçları JSON yerine grafik özetiyle biçimlendirilir", {
  out <- llm_worker_format_tool_results_for_prompt(
    tool_calls = list(list(function_name = "create_chart")),
    tool_results_raw = list(
      list(
        chart = list(
          type = "bar",
          mapping = list(x = "Kategori", y = "Tutar"),
          n = 3
        )
      )
    )
  )

  result_text <- out$tool_results[[1]]$result

  expect_true(grepl("Grafik hazırlandı:", result_text, fixed = TRUE))
  expect_true(grepl("Tür: bar", result_text, fixed = TRUE))
  expect_true(grepl("X=Kategori", result_text, fixed = TRUE))
  expect_true(grepl("Y=Tutar", result_text, fixed = TRUE))
})

test_that("helpers_llm_worker.R araç yürütmede mcp registry snapshot session_obj değerini kullanır", {
  worker_text <- .read_repo_text_llm_worker_tool_results("R/helpers_llm_worker.R")

  stale_pattern <- "current_session <- if (!is.null(settings$shiny_session)) settings$shiny_session else NULL"

  expect_false(
    grepl(stale_pattern, worker_text, fixed = TRUE),
    info = "MCP araç yürütme canlı settings$shiny_session'a geri dönmemelidir; session_obj snapshot koruması kullanılmalıdır."
  )

  expect_true(
    grepl("current_session <- session_obj", worker_text, fixed = TRUE),
    info = "MCP araç yürütme için current_session session_obj üzerinden çözülmelidir."
  )
})

test_that("helpers_llm_worker.R araç sonucu biçimlendirme helper'ını çağırır", {
  worker_text <- .read_repo_text_llm_worker_tool_results("R/helpers_llm_worker.R")
  helper_text <- .read_repo_text_llm_worker_tool_results("R/helpers_llm_worker_tool_results.R")

  expect_true(
    grepl("llm_worker_format_tool_results_for_prompt(", worker_text, fixed = TRUE),
    info = "helpers_llm_worker.R araç sonucu biçimlendirmeyi helper'a devretmelidir."
  )

  expect_false(
    grepl("|  [GLOBAL] ARAÇ SONUÇLARINI FORMATLAMAYA BAŞLIYOR  |", worker_text, fixed = TRUE),
    info = "Büyük araç sonucu biçimlendirme bloğu helpers_llm_worker.R içine geri taşınmamalıdır."
  )

  expect_true(
    grepl("|  [GLOBAL] ARAÇ SONUÇLARINI FORMATLAMAYA BAŞLIYOR  |", helper_text, fixed = TRUE),
    info = "Araç sonucu biçimlendirme log sözleşmesi yeni helper dosyasında korunmalıdır."
  )
})
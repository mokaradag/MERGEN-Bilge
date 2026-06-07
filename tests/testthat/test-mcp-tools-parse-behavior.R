# ==============================================================================
# Dosya Yolu: tests/testthat/test-mcp-tools-parse-behavior.R
# Açıklama: helpers_mcp_tools$parse_tool_calls_from_text ve get_mcp_tools_prompt
#           public sarmalayıcılarının davranışını doğrular. parse_tool_calls saf
#           bir ayrıştırıcıdır: <tool_call> blokları, satır içi JSON, tüm-mesaj
#           JSON ve düz SQL fallback. Çevrimdışı/deterministik; DB/LLM/ağ yok.
#           MCP zinciri test-mcp-excel-resolve.R ile aynı sırayla yüklenir.
# ==============================================================================

.mcp_parse_source_once <- function() {
  if (exists("parse_tool_calls_from_text", envir = globalenv(), inherits = FALSE) &&
      exists("helpers_mcp_tools", envir = globalenv(), inherits = FALSE)) {
    return(invisible(TRUE))
  }
  rr <- resolve_repo_root_for_tests()
  files <- c(
    "R/helpers_mcp_context.R",
    "R/helpers_mcp_bootstrap.R",
    "R/helpers_mcp_table_readers.R",
    "R/helpers_mcp_file_resolver.R",
    "R/helpers_mcp_schema_helpers.R",
    "R/helpers_mcp_basic_tools.R",
    "R/helpers_mcp_chart_tools.R",
    "R/helpers_mcp_analyze_visualize.R",
    "R/helpers_mcp_tools.R"
  )
  for (f in files) {
    source(file.path(rr, f), encoding = "UTF-8", local = globalenv())
  }
  invisible(TRUE)
}
.mcp_parse_source_once()

test_that("parse_tool_calls_from_text boş/NULL girdi için boş liste döner", {
  expect_identical(parse_tool_calls_from_text(NULL), list())
  expect_identical(parse_tool_calls_from_text(""), list())
})

test_that("parse_tool_calls_from_text <tool_call> bloğunu ayrıştırır", {
  txt <- '<tool_call>{"name":"analyze_uploaded_file","arguments":{"file":"a.xlsx"}}</tool_call>'
  res <- parse_tool_calls_from_text(txt)
  # <tool_call> içindeki JSON hem blok hem satır içi yola eşleşebilir; en az
  # bir doğru çözümleme yeterlidir (gerçek ayrıştırıcı davranışı).
  expect_gte(length(res), 1L)
  fns <- vapply(res, function(x) x$function_name %||% "", character(1))
  expect_true("analyze_uploaded_file" %in% fns)
  hit <- Find(function(x) identical(x$function_name, "analyze_uploaded_file"), res)
  expect_identical(hit$arguments$file, "a.xlsx")
})

test_that("parse_tool_calls_from_text satır içi JSON aracını ayrıştırır", {
  txt <- 'Şunu yap: {"tool":"get_column_statistics","parameters":{"column":"tutar"}} teşekkürler'
  res <- parse_tool_calls_from_text(txt)
  expect_gte(length(res), 1L)
  fns <- vapply(res, function(x) x$function_name %||% "", character(1))
  expect_true("get_column_statistics" %in% fns)
})

test_that("parse_tool_calls_from_text düz SQL'i fallback olarak sql_query_uploaded_file'e çevirir", {
  res <- parse_tool_calls_from_text("SELECT ad, tutar FROM dosya WHERE tutar > 100")
  expect_length(res, 1L)
  expect_identical(res[[1]]$function_name, "sql_query_uploaded_file")
  expect_true(grepl("SELECT", res[[1]]$arguments$sql, fixed = TRUE))
})

test_that("parse_tool_calls_from_text araç işareti olmayan düz metinde boş döner", {
  res <- parse_tool_calls_from_text("Merhaba, bugün hava nasıl?")
  expect_identical(res, list())
})

test_that("get_mcp_tools_prompt araç tanımlarını içeren metin döndürür", {
  prompt <- get_mcp_tools_prompt()
  expect_true(is.character(prompt) && length(prompt) == 1L && nzchar(prompt))
  # En az bir bilinen araç adından bahsetmeli
  expect_true(grepl("sql_query_uploaded_file", prompt, fixed = TRUE) ||
                grepl("analyze_uploaded_file", prompt, fixed = TRUE))
})

test_that("get_openai_tools OpenAI fonksiyon şeması listesi üretir", {
  out <- get_openai_tools()
  expect_true(is.list(out$tools) && length(out$tools) > 0)
  # OpenAI tool şeması: her öğede type = "function" ve function$name olmalı
  first <- out$tools[[1]]
  expect_identical(first$type, "function")
  expect_true(!is.null(first[["function"]]$name) && nzchar(first[["function"]]$name))
})

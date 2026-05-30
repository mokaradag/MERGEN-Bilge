# ==============================================================================
# Dosya Yolu: tests/testthat/test-detect-tool-type-behavior.R
# Açıklama: R/helpers_claude_code_streaming.R detect_tool_type DAVRANIŞSAL
#           testleri. Bilge Yolaç araç adını (bash/file_read/file_write/search/
#           other) sınıflandırır; sıralı grepl olduğundan eşleşme önceliği
#           önemlidir (read, write'tan önce gelir). tolower ile büyük/küçük harf
#           duyarsız. Saf base R; ağ/CLI/Shiny GEREKMEZ.
# ==============================================================================

.detecttool_source_once <- function() {
  if (exists("detect_tool_type", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_claude_code_streaming.R"),
    encoding = "UTF-8", local = globalenv()
  )
  invisible(TRUE)
}

testthat::test_that("detect_tool_type bash/shell/komut adlarını 'bash' yapar", {
  .detecttool_source_once()
  testthat::expect_identical(detect_tool_type("Bash"), "bash")
  testthat::expect_identical(detect_tool_type("execute_command"), "bash")
  testthat::expect_identical(detect_tool_type("Shell"), "bash")
})

testthat::test_that("detect_tool_type okuma/yazma adlarını doğru sınıflandırır", {
  .detecttool_source_once()
  testthat::expect_identical(detect_tool_type("Read"), "file_read")
  testthat::expect_identical(detect_tool_type("file_read"), "file_read")
  testthat::expect_identical(detect_tool_type("Write"), "file_write")
  testthat::expect_identical(detect_tool_type("Edit"), "file_write")
  testthat::expect_identical(detect_tool_type("MultiEdit"), "file_write")
  testthat::expect_identical(detect_tool_type("create_file"), "file_write")
})

testthat::test_that("detect_tool_type arama adlarını 'search' yapar", {
  .detecttool_source_once()
  testthat::expect_identical(detect_tool_type("Grep"), "search")
  testthat::expect_identical(detect_tool_type("Glob"), "search")
  testthat::expect_identical(detect_tool_type("search_files"), "search")
  testthat::expect_identical(detect_tool_type("find"), "search")
})

testthat::test_that("detect_tool_type eşleşmeyenleri 'other' yapar (LS ve boş dahil)", {
  .detecttool_source_once()
  testthat::expect_identical(detect_tool_type("LS"), "other")
  testthat::expect_identical(detect_tool_type("UnknownTool"), "other")
  testthat::expect_identical(detect_tool_type(""), "other")
})

testthat::test_that("detect_tool_type sıralı eşleşmede önceliği korur (read, write'tan önce)", {
  .detecttool_source_once()
  # Hem 'read' hem 'write' içeren ad: read önce kontrol edildiği için file_read.
  testthat::expect_identical(detect_tool_type("read_then_write"), "file_read")
  # tolower ile büyük harf duyarsız.
  testthat::expect_identical(detect_tool_type("BASH"), "bash")
})

# ==============================================================================
# Dosya Yolu: tests/testthat/test-mcp-excel-summary-behavior.R
# Açıklama: R/helpers_llm_tool_formatters.R içindeki, mevcut testlerde
#           çağrılmayan saf yardımcıların DAVRANIŞSAL testleri:
#             - get_mcp_excel_candidates (oturum dosya kayıt adlarını çıkarır)
#             - build_mcp_excel_summary  (analiz sonucundan TR/EN anahtarlarla
#               okunabilir özet metni üretir)
#           Parse edilmiş R listeleri / sentetik oturum alınır; readxl/jsonlite/
#           MCP araç ortamı / DB / ağ GEREKMEZ.
# ==============================================================================

.mcpxls_source_once <- function() {
  if (!exists("%||%", inherits = TRUE)) {
    assign("%||%", function(a, b) if (is.null(a)) b else a, envir = globalenv())
  }
  if (!exists("get_mcp_excel_candidates",
              envir = globalenv(), mode = "function", inherits = TRUE)) {
    source(
      file.path(resolve_repo_root_for_tests(), "R", "helpers_llm_tool_formatters.R"),
      encoding = "UTF-8", local = globalenv()
    )
  }
  invisible(TRUE)
}

# ------------------------------------------------------------------------------
# get_mcp_excel_candidates
# ------------------------------------------------------------------------------
testthat::test_that("get_mcp_excel_candidates boş/NULL oturumda character() döner", {
  .mcpxls_source_once()
  testthat::expect_identical(get_mcp_excel_candidates(NULL), character())
  testthat::expect_identical(
    get_mcp_excel_candidates(list(userData = list(current_session_files = NULL))),
    character()
  )
  testthat::expect_identical(
    get_mcp_excel_candidates(list(userData = list(current_session_files = list()))),
    character()
  )
})

testthat::test_that("get_mcp_excel_candidates dosya görünür adlarını çıkarır (name/display + dedup)", {
  .mcpxls_source_once()
  sess <- list(userData = list(current_session_files = list(
    list(name = "a.xlsx"),
    list(name = "b.txt"),
    list(name = "a.xlsx")            # tekrar -> tekille
  )))
  testthat::expect_identical(get_mcp_excel_candidates(sess), c("a.xlsx", "b.txt"))

  # name yoksa display kullanılır.
  sess_disp <- list(userData = list(current_session_files = list(
    list(display = "rapor.xlsx")
  )))
  testthat::expect_identical(get_mcp_excel_candidates(sess_disp), "rapor.xlsx")
})

testthat::test_that("get_mcp_excel_candidates name/display yoksa liste isimlerine düşer", {
  .mcpxls_source_once()
  sess <- list(userData = list(current_session_files = list(
    dosya1 = list(), dosya2 = list()
  )))
  testthat::expect_identical(get_mcp_excel_candidates(sess), c("dosya1", "dosya2"))
})

# ------------------------------------------------------------------------------
# build_mcp_excel_summary
# ------------------------------------------------------------------------------
testthat::test_that("build_mcp_excel_summary NULL/liste-olmayan girdide NULL döner", {
  .mcpxls_source_once()
  testthat::expect_null(build_mcp_excel_summary(NULL, "x.xlsx"))
  testthat::expect_null(build_mcp_excel_summary("liste degil", "x.xlsx"))
})

testthat::test_that("build_mcp_excel_summary EN anahtarlardan özet üretir", {
  .mcpxls_source_once()
  ozet <- build_mcp_excel_summary(
    list(row_count = 10, column_count = 3, columns = c("A", "B", "C")),
    "data.xlsx"
  )
  testthat::expect_length(ozet, 1L)
  testthat::expect_true(is.character(ozet))
  testthat::expect_match(ozet, "Dosya: data.xlsx", fixed = TRUE)
  testthat::expect_match(ozet, "Toplam satir: 10", fixed = TRUE)
  testthat::expect_match(ozet, "Toplam sutun: 3", fixed = TRUE)
  testthat::expect_match(ozet, "Sutunlar (3): A, B, C", fixed = TRUE)
})

testthat::test_that("build_mcp_excel_summary TR anahtarları ve sayısal sütunları işler", {
  .mcpxls_source_once()
  ozet <- build_mcp_excel_summary(
    list(
      satir_sayisi = 5,
      sutun_sayisi = 2,
      sutun_isimleri = c("Ad", "Tutar"),
      sayisal_sutunlar = c("Tutar")
    ),
    "rapor.xlsx"
  )
  testthat::expect_match(ozet, "Toplam satir: 5", fixed = TRUE)
  testthat::expect_match(ozet, "Toplam sutun: 2", fixed = TRUE)
  testthat::expect_match(ozet, "Sayisal sutunlar: Tutar", fixed = TRUE)
})

testthat::test_that("build_mcp_excel_summary eksik alanlarda '(bilinmiyor)' ve dosya adı fallback'i kullanır", {
  .mcpxls_source_once()
  # Boş sonuç + display_name verilmiş.
  ozet <- build_mcp_excel_summary(list(), "verilen.xlsx")
  testthat::expect_match(ozet, "Dosya: verilen.xlsx", fixed = TRUE)
  testthat::expect_match(ozet, "Toplam satir: (bilinmiyor)", fixed = TRUE)
  testthat::expect_match(ozet, "Toplam sutun: (bilinmiyor)", fixed = TRUE)

  # display_name NULL -> sonuçtaki dosya_adi kullanılır.
  ozet2 <- build_mcp_excel_summary(list(dosya_adi = "icerikten.xlsx"), NULL)
  testthat::expect_match(ozet2, "Dosya: icerikten.xlsx", fixed = TRUE)
})

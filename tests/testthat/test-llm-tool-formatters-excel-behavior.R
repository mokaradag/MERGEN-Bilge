# ==============================================================================
# Dosya Yolu: tests/testthat/test-llm-tool-formatters-excel-behavior.R
# Açıklama: R/helpers_llm_tool_formatters.R Excel/MCP araç biçimlendiricilerinin
#           davranışsal testleri. build_excel_digest_json (gerçek xlsx profili),
#           get_mcp_excel_candidates, build_mcp_excel_summary, mcp_excel_tool_fallback
#           ve convert_docx_to_pdf hata koruması doğrulanır. DB/LLM/tarayıcı yok.
# ==============================================================================

testthat::local_edition(3)

.tf_env <- new.env(parent = globalenv())
local({
  kok <- resolve_repo_root_for_tests()
  source(file.path(kok, "R", "utils_excel_reader.R"), encoding = "UTF-8", local = .tf_env)
  source(file.path(kok, "R", "helpers_llm_tool_formatters.R"), encoding = "UTF-8", local = .tf_env)
})

# -----------------------------------------------------------------------------
# build_excel_digest_json
# -----------------------------------------------------------------------------

test_that("build_excel_digest_json gerçek xlsx'ten satır/sütun şekli ve profil JSON'u üretir", {
  skip_if_not_installed("writexl")
  skip_if_not_installed("data.table")

  xf <- tempfile(fileext = ".xlsx")
  writexl::write_xlsx(
    data.frame(Sehir = c("Ankara", "Izmir", "Ankara"), Nufus = c(5, 4, 5), stringsAsFactors = FALSE),
    xf
  )

  js <- .tf_env$build_excel_digest_json(xf)
  expect_s3_class(js, "json")

  parsed <- jsonlite::fromJSON(as.character(js), simplifyVector = FALSE)
  expect_equal(parsed$shape$rows, 3L)
  expect_equal(parsed$shape$cols, 2L)
  # Sayısal sütun (Nufus) ve kategorik sütun (Sehir) profili bulunmalı.
  expect_false(is.null(parsed$numeric))
  expect_false(is.null(parsed$categories))
})

# -----------------------------------------------------------------------------
# get_mcp_excel_candidates
# -----------------------------------------------------------------------------

test_that("get_mcp_excel_candidates oturum dosyalarından görünen adları çıkarır", {
  sess <- list(userData = list(current_session_files = list(
    list(name = "Rapor.xlsx"),
    list(display = "Veri.xlsx")
  )))
  expect_identical(.tf_env$get_mcp_excel_candidates(sess), c("Rapor.xlsx", "Veri.xlsx"))
})

test_that("get_mcp_excel_candidates NULL oturum veya dosyasız oturumda boş döner", {
  expect_equal(length(.tf_env$get_mcp_excel_candidates(NULL)), 0L)
  expect_equal(
    length(.tf_env$get_mcp_excel_candidates(list(userData = list(current_session_files = list())))),
    0L
  )
})

# -----------------------------------------------------------------------------
# build_mcp_excel_summary
# -----------------------------------------------------------------------------

test_that("build_mcp_excel_summary Türkçe/İngilizce anahtarlardan özet metin üretir", {
  res <- list(satir_sayisi = 10, sutun_sayisi = 3,
              sutun_isimleri = c("A", "B", "C"), sayisal_sutunlar = c("B"))
  txt <- .tf_env$build_mcp_excel_summary(res, "MyFile.xlsx")
  expect_true(grepl("Dosya: MyFile.xlsx", txt, fixed = TRUE))
  expect_true(grepl("Toplam satir: 10", txt, fixed = TRUE))
  expect_true(grepl("Toplam sutun: 3", txt, fixed = TRUE))
  expect_true(grepl("Sutunlar (3)", txt, fixed = TRUE))
})

test_that("build_mcp_excel_summary NULL veya liste olmayan girdide NULL döner", {
  expect_null(.tf_env$build_mcp_excel_summary(NULL, "x"))
  expect_null(.tf_env$build_mcp_excel_summary("metin", "x"))
})

# -----------------------------------------------------------------------------
# mcp_excel_tool_fallback
# -----------------------------------------------------------------------------

test_that("mcp_excel_tool_fallback NULL oturumda ve dosyasız oturumda NULL döner", {
  expect_null(.tf_env$mcp_excel_tool_fallback(NULL))
  expect_null(.tf_env$mcp_excel_tool_fallback(list(userData = list(current_session_files = list()))))
})

test_that("mcp_excel_tool_fallback başarılı analizde özet metin ve atıf döner", {
  # MCP araç ortamını stub'la: analyze_uploaded_file geçerli bir analiz döndürür.
  .tf_env$helpers_mcp_tools <- list(
    analyze_uploaded_file = function(disp, session_obj) {
      list(satir_sayisi = 5, sutun_sayisi = 2, sutun_isimleri = c("X", "Y"))
    }
  )
  withr::defer(rm("helpers_mcp_tools", envir = .tf_env))

  sess <- list(userData = list(current_session_files = list(list(name = "Analiz.xlsx"))))
  out <- .tf_env$mcp_excel_tool_fallback(sess)

  expect_true(is.list(out))
  expect_identical(out$citation, "Analiz.xlsx")
  expect_true(grepl("Toplam satir: 5", out$text, fixed = TRUE))
})

# -----------------------------------------------------------------------------
# convert_docx_to_pdf hata koruması
# -----------------------------------------------------------------------------

test_that("convert_docx_to_pdf var olmayan dosyada açık hata verir", {
  expect_error(
    .tf_env$convert_docx_to_pdf(file.path(tempdir(), "yok_olan.docx")),
    "bulunamadi"
  )
})


# -----------------------------------------------------------------------------
# safe_read_excel_table satır sınırı
# -----------------------------------------------------------------------------
# Regresyon: readxl, `range` verildiğinde `n_max` değerini YOK SAYAR. Sınır
# aralığın alt satırına taşınmadan önce n_max sessizce etkisizdi ve önizleme
# uzun sayfalarda tüm satırları okuyordu.

test_that("safe_read_excel_table n_max satir sinirini gercekten uygular", {
  skip_if_not_installed("writexl")
  skip_if_not_installed("readxl")

  yol <- withr::local_tempfile(fileext = ".xlsx")
  writexl::write_xlsx(
    data.frame(ad = paste0("s", 1:50), deger = 1:50, stringsAsFactors = FALSE),
    yol
  )

  dar <- .tf_env$safe_read_excel_table(yol, n_max = 5)
  expect_identical(nrow(dar), 5L)
  expect_identical(as.character(dar[[1]][1]), "s1")

  tum <- .tf_env$safe_read_excel_table(yol)
  expect_identical(nrow(tum), 50L)
})

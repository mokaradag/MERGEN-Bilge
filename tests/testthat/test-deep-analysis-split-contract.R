# ==============================================================================
# Dosya Yolu: tests/testthat/test-deep-analysis-split-contract.R
# Açıklama: R/helpers_deep_analysis.R bölünmesini dondurur.
#
#           helpers_deep_analysis.R bakım borcu ratchet bütçesini (627 taban ->
#           659 satır / 15 fonksiyon izni) aşmıştı: 780 satır / 16 fonksiyon.
#           Bütçeyi yükseltmek CLAUDE.md tarafından yasak olduğu için dosya iki
#           SAF yardımcıya bölündü:
#             * R/helpers_deep_analysis_detail.R  -> detay seviyesi kataloğu
#             * R/helpers_deep_analysis_context.R -> bağlam/prompt kurucu
#           Orkestratör (çoklu sorgu seçimi, tek sorgu çalıştırma,
#           pk_deep_analysis_process) helpers_deep_analysis.R içinde kaldı.
#
#           Bu YAPISAL bir sözleşmedir; davranış kapsamı
#           test-deep-analysis-detail-behavior.R ve
#           test-deep-analysis-context-builder-behavior.R içindedir.
#           Uygulamayı başlatmaz; DB, LLM, tarayıcı veya ağ GEREKMEZ.
# ==============================================================================

.read_repo_text_deep_split <- function(rel_path) {
  abs_path <- file.path(resolve_repo_root_for_tests(), rel_path)

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

test_that("ayrılan saf yardımcı dosyalar mevcut ve kendi sorumluluklarını taşır", {
  detay <- .read_repo_text_deep_split("R/helpers_deep_analysis_detail.R")
  baglam <- .read_repo_text_deep_split("R/helpers_deep_analysis_context.R")

  expect_true(grepl("ANALYSIS_DETAIL_LEVELS <- list(", detay, fixed = TRUE))
  expect_true(grepl("get_analysis_detail_config <- function(", detay, fixed = TRUE))
  expect_true(grepl("get_analysis_detail_instruction <- function(", detay, fixed = TRUE))
  expect_true(grepl("build_deep_analysis_context <- function(", baglam, fixed = TRUE))
})

test_that("orkestratör dosyası taşınan sorumlulukları geri almaz", {
  orkestratör <- .read_repo_text_deep_split("R/helpers_deep_analysis.R")

  # Taşınan tanımlar geri gelirse ratchet bütçesi yeniden aşılır.
  expect_false(grepl("ANALYSIS_DETAIL_LEVELS <- list(", orkestratör, fixed = TRUE))
  expect_false(grepl("get_analysis_detail_config <- function(", orkestratör, fixed = TRUE))
  expect_false(grepl("get_analysis_detail_instruction <- function(", orkestratör, fixed = TRUE))
  expect_false(grepl("build_deep_analysis_context <- function(", orkestratör, fixed = TRUE))

  # v1 ÇOKLU seçici de ratchet bütçesi nedeniyle taşındı; v1 TEKİL seçicisinin
  # (helpers_pk_analysis_ai_selector.R) tam karşılığı olarak
  # helpers_deep_analysis_selector.R içindedir. Orkestratöre geri alınmamalıdır.
  expect_false(grepl("find_multiple_queries_with_ai <- function(", orkestratör, fixed = TRUE))
  secici <- .read_repo_text_deep_split("R/helpers_deep_analysis_selector.R")
  expect_true(grepl("find_multiple_queries_with_ai <- function(", secici, fixed = TRUE))

  # Orkestrasyon sorumluluğu burada KALMALIDIR.
  expect_true(grepl("execute_single_deep_query <- function(", orkestratör, fixed = TRUE))
  expect_true(grepl("pk_deep_analysis_process <- function(", orkestratör, fixed = TRUE))
})

test_that("ayrılan yardımcılar saftır: Shiny/reactive/DB/ağ bağımlılığı yoktur", {
  for (yol in c(
    "R/helpers_deep_analysis_detail.R",
    "R/helpers_deep_analysis_context.R",
    # Faz 6 kurulum/karar katmanı da SAFTIR (DB/ağ yok).
    "R/helpers_deep_analysis_phase6.R"
  )) {
    metin <- .read_repo_text_deep_split(yol)

    for (yasak in c(
      "moduleServer(", "reactiveVal(", "reactiveValues(", "observeEvent(",
      "get_connection(", "call_local_llm(", "httr::"
    )) {
      expect_false(
        grepl(yasak, metin, fixed = TRUE),
        info = sprintf("%s içinde yasak bağımlılık: %s", yol, yasak)
      )
    }
  }
})

test_that("manifest ayrılan yardımcıları orkestratörden ÖNCE yükler", {
  yollar <- source_manifest_paths_for_tests()

  expect_source_manifest_contains_for_tests(
    c(
      "R/helpers_deep_analysis_phase6.R",
      "R/helpers_deep_analysis_selector.R",
      "R/helpers_deep_analysis_detail.R",
      "R/helpers_deep_analysis_context.R",
      "R/helpers_deep_analysis.R"
    ),
    yollar
  )

  expect_source_manifest_order_for_tests(
    c(
      "R/helpers_deep_analysis_phase6.R",
      "R/helpers_deep_analysis_selector.R",
      "R/helpers_deep_analysis_detail.R",
      "R/helpers_deep_analysis_context.R",
      "R/helpers_deep_analysis.R"
    ),
    yollar
  )
})

test_that("bölünme sonrası orkestratör ratchet bütçesinin altındadır", {
  metin <- .read_repo_text_deep_split("R/helpers_deep_analysis.R")

  satir_sayisi <- length(strsplit(metin, "\n", fixed = TRUE)[[1]])
  eslesme <- gregexpr("(<-|=)\\s*function\\s*\\(", metin, perl = TRUE)[[1]]
  fonksiyon_sayisi <- if (identical(eslesme[1], -1L)) 0L else length(eslesme)

  # inceleme düzeltmeleri: Faz 6 kurulumu (son tarih/iptal jetonu/
  # option yayını), kısmi-durma notu ve bozulmuş-filtre kararı
  # helpers_deep_analysis_phase6.R'ye; v1 çoklu seçici
  # helpers_deep_analysis_selector.R'ye taşındı. Ölçülen taban 598/10;
  # izin 640 ve 14 (bütçe YÜKSELTİLMEDİ, dosya KÜÇÜLDÜ).
  expect_lte(satir_sayisi, 640L)
  expect_lte(fonksiyon_sayisi, 14L)
})

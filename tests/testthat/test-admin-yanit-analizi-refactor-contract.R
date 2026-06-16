# ==============================================================================
# Dosya Yolu: tests/testthat/test-admin-yanit-analizi-refactor-contract.R
# Açıklama: Yanıt Geri Bildirimi Analizi refactor sözleşmesini korur.
# ==============================================================================

.read_admin_yanit_refactor_text <- function(path) {
  repo_root <- resolve_repo_root_for_tests()
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

.extract_admin_yanit_safe_source_paths <- function(text) {
  m <- gregexpr(
    'safe_source\\("([^"]+)"\\s*,\\s*encoding\\s*=\\s*"UTF-8"',
    text,
    perl = TRUE,
    useBytes = TRUE
  )

  hits <- regmatches(text, m)[[1]]
  if (length(hits) == 0 || identical(hits, character(0))) {
    return(character(0))
  }

  sub(
    '.*safe_source\\("([^"]+)".*',
    "\\1",
    hits,
    perl = TRUE,
    useBytes = TRUE
  )
}

test_that("Yanıt analizi helper dosyası modülden önce source ediliyor", {
  repo_root <- resolve_repo_root_for_tests()

  expect_true(file.exists(file.path(repo_root, "R/helpers_admin_yanit_analizi.R")))
  expect_true(file.exists(file.path(repo_root, "R/module_admin_yanit_analizi.R")))

  expect_source_manifest_order_for_tests(
    c(
      "R/helpers_admin_yanit_analizi.R",
      "R/module_admin_yanit_analizi.R"
    ),
    label = "Yanıt analizi helper/module source sırası bozulmuş:"
  )
})

test_that("Yanıt analizi veri ve UI yardımcıları modül dosyasına geri taşınmaz", {
  helper_text <- .read_admin_yanit_refactor_text("R/helpers_admin_yanit_analizi.R")
  module_text <- .read_admin_yanit_refactor_text("R/module_admin_yanit_analizi.R")

  expected_helper_defs <- c(
    "admin_yanit_collect_data <- function",
    "admin_yanit_tag_counts <- function",
    "admin_yanit_overview_ui <- function",
    "admin_yanit_model_ui <- function",
    "admin_yanit_etiket_ui <- function",
    "admin_yanit_zaman_ui <- function"
  )

  missing_defs <- expected_helper_defs[
    !vapply(expected_helper_defs, function(pattern) {
      grepl(pattern, helper_text, fixed = TRUE)
    }, logical(1))
  ]

  expect_equal(
    missing_defs,
    character(0),
    info = paste("Eksik Yanıt Analizi helper tanımları:", paste(missing_defs, collapse = ", "))
  )

  forbidden_module_defs <- c(
    "ya_overview_ui <- function",
    "ya_model_ui <- function",
    "ya_etiket_ui <- function",
    "ya_zaman_ui <- function"
  )

  returned_defs <- forbidden_module_defs[
    vapply(forbidden_module_defs, function(pattern) {
      grepl(pattern, module_text, fixed = TRUE)
    }, logical(1))
  ]

  expect_equal(
    returned_defs,
    character(0),
    info = paste("UI helper fonksiyonları modül dosyasına geri taşınmış:", paste(returned_defs, collapse = ", "))
  )

  expect_true(
    grepl("admin_yanit_collect_data(admin_safe_query)", module_text, fixed = TRUE),
    info = "module_admin_yanit_analizi.R veri sorgusunu admin_yanit_collect_data(...) üzerinden çağırmalıdır."
  )

  expect_true(
    grepl("admin_yanit_tag_counts(ya_data()$etiketler_ham)", module_text, fixed = TRUE),
    info = "module_admin_yanit_analizi.R etiket çözümlemeyi admin_yanit_tag_counts(...) üzerinden çağırmalıdır."
  )
})

test_that("Yanıt analizi UI sözleşmesi Türkçe metinleri ve output ID'lerini korur", {
  helper_text <- .read_admin_yanit_refactor_text("R/helpers_admin_yanit_analizi.R")
  module_text <- .read_admin_yanit_refactor_text("R/module_admin_yanit_analizi.R")

  expected_helper_texts <- c(
    "Toplam Geri Bildirim",
    "Beğeni Oranı",
    "Beğenmeme",
    "Etiket Dağılımı (Ağaç Haritası)",
    "Saat × Gün Isı Haritası",
    "Kullanıcı Bazlı Geri Bildirim"
  )

  missing_helper_texts <- expected_helper_texts[
    !vapply(expected_helper_texts, function(pattern) {
      grepl(pattern, helper_text, fixed = TRUE)
    }, logical(1))
  ]

  expect_equal(
    missing_helper_texts,
    character(0),
    info = paste("Yanıt Analizi helper dosyasında beklenen Türkçe UI metinleri eksik:", paste(missing_helper_texts, collapse = ", "))
  )

  expected_public_ui_texts <- c(
    "Yanıt Geri Bildirimi Analizi",
    "Genel Bakış",
    "Model Performansı",
    "Etiket & Yorum Analizi",
    "Zaman & Kullanıcı Analizi"
  )

  missing_public_ui_texts <- expected_public_ui_texts[
    !vapply(expected_public_ui_texts, function(pattern) {
      grepl(pattern, module_text, fixed = TRUE)
    }, logical(1))
  ]

  expect_equal(
    missing_public_ui_texts,
    character(0),
    info = paste("Yanıt Analizi public modül UI metinleri eksik:", paste(missing_public_ui_texts, collapse = ", "))
  )

  expected_output_ids <- c(
    "ya_gunluk_trend_chart",
    "ya_tip_pie_chart",
    "ya_uzunluk_chart",
    "ya_sure_chart",
    "ya_model_bar_chart",
    "ya_haftalik_oran_chart",
    "ya_model_tablo",
    "ya_etiket_treemap_chart",
    "ya_etiket_diverging_chart",
    "ya_yorum_tablo",
    "ya_saat_gun_heatmap",
    "ya_saatlik_chart",
    "ya_kullanici_tablo"
  )

  missing_ids <- expected_output_ids[
    !vapply(expected_output_ids, function(pattern) {
      grepl(pattern, helper_text, fixed = TRUE)
    }, logical(1))
  ]

  expect_equal(
    missing_ids,
    character(0),
    info = paste("Yanıt Analizi helper dosyasında beklenen output ID'leri eksik:", paste(missing_ids, collapse = ", "))
  )
})

.ya_expected_output_ids <- c(
  "ya_gunluk_trend_chart", "ya_tip_pie_chart", "ya_uzunluk_chart", "ya_sure_chart",
  "ya_model_bar_chart", "ya_haftalik_oran_chart", "ya_model_tablo",
  "ya_etiket_treemap_chart", "ya_etiket_diverging_chart", "ya_yorum_tablo",
  "ya_saat_gun_heatmap", "ya_saatlik_chart", "ya_kullanici_tablo"
)

test_that("yanıt analizi grafik/tablo renderer'ları admin_yanit_outputs dosyasına çıkarıldı", {
  repo_root <- resolve_repo_root_for_tests()
  outputs_path <- file.path(repo_root, "R/module_admin_yanit_analizi_outputs.R")

  expect_true(
    file.exists(outputs_path),
    info = "R/module_admin_yanit_analizi_outputs.R dosyası eklenmelidir."
  )

  outputs_text <- .read_admin_yanit_refactor_text("R/module_admin_yanit_analizi_outputs.R")
  module_text <- .read_admin_yanit_refactor_text("R/module_admin_yanit_analizi.R")

  expect_true(
    grepl("admin_yanit_outputs <- function", outputs_text, fixed = TRUE),
    info = "admin_yanit_outputs() outputs dosyasında tanımlı olmalıdır."
  )
  expect_true(grepl("renderHighchart", outputs_text, fixed = TRUE))
  expect_true(grepl("renderDT", outputs_text, fixed = TRUE))

  # Modül outputs fonksiyonunu çağırır ve artık inline renderer içermez.
  expect_true(
    grepl("admin_yanit_outputs(", module_text, fixed = TRUE),
    info = "module_admin_yanit_analizi.R admin_yanit_outputs() çağırmalıdır."
  )
  expect_false(
    grepl("renderHighchart", module_text, fixed = TRUE),
    info = "Grafik renderer'ları modülde kalmamalıdır (outputs dosyasına taşındı)."
  )
  expect_false(
    grepl("renderDT", module_text, fixed = TRUE),
    info = "Tablo renderer'ları modülde kalmamalıdır (outputs dosyasına taşındı)."
  )

  # Yenile tetikleyicisi (saat/saatlik grafikler) outputs dosyasında korunur.
  expect_true(
    grepl("refresh$trigger()", outputs_text, fixed = TRUE),
    info = "ya_saat_gun_heatmap/ya_saatlik_chart refresh$trigger() bağımlılığı korunmalıdır."
  )

  for (id in .ya_expected_output_ids) {
    expect_true(
      grepl(paste0("output$", id), outputs_text, fixed = TRUE),
      info = paste("Outputs dosyasında eksik output ID'si:", id)
    )
  }
})

test_that("yanıt analizi outputs dosyası modülden önce source ediliyor", {
  expect_source_manifest_order_for_tests(
    c(
      "R/module_admin_yanit_analizi_outputs.R",
      "R/module_admin_yanit_analizi.R"
    ),
    label = "Yanıt analizi outputs/module source sırası bozulmuş:"
  )
})
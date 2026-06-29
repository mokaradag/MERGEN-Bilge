# ==============================================================================
# Dosya Yolu: tests/testthat/test-health-formatters-render-behavior.R
# Açıklama: R/helpers_health_formatters.R içindeki render yardımcılarının
#           davranışsal testleri: health_escape (HTML kaçışı), health_status_pill
#           (durum rozeti) ve health_render_value (durum->rozet / düz metin->kaçış).
#           Mevcut health testleri farklı fonksiyonları kapsar; bunlar kapsam dışıydı.
# ==============================================================================

testthat::local_edition(3)

if (requireNamespace("shiny", quietly = TRUE)) {
  suppressMessages(library(shiny))
}

.hfmt_env <- new.env(parent = globalenv())
# %||% ve normalize_text_utf8 izole çalıştırmada da hazır olsun (depolama yolu
# mojibake onarımı bu yardımcıya bağlıdır).
source(
  file.path(resolve_repo_root_for_tests(), "R", "utils_common.R"),
  encoding = "UTF-8",
  local = .hfmt_env
)
source(
  file.path(resolve_repo_root_for_tests(), "R", "utils_text_encoding.R"),
  encoding = "UTF-8",
  local = .hfmt_env
)
source(
  file.path(resolve_repo_root_for_tests(), "R", "helpers_health_formatters.R"),
  encoding = "UTF-8",
  local = .hfmt_env
)

test_that("health_escape HTML özel karakterlerini kaçırır ve NULL'u boş stringe çevirir", {
  expect_equal(.hfmt_env$health_escape("<b>&x"), "&lt;b&gt;&amp;x")
  expect_equal(.hfmt_env$health_escape(NULL), "")
  # Türkçe karakter korunmalı.
  expect_equal(.hfmt_env$health_escape("Türkçe"), "Türkçe")
})

test_that("health_status_pill durum rozetini health-pill sınıfı ve tooltip ile üretir", {
  skip_if_not_installed("shiny")

  html <- paste(as.character(.hfmt_env$health_status_pill("ok")), collapse = "")
  expect_true(grepl("health-pill", html, fixed = TRUE))
  expect_true(grepl("data-health-tooltip", html, fixed = TRUE))
  expect_true(grepl("Durum:", html, fixed = TRUE))
})

test_that("health_render_value durum seviyesini rozet, düz metni kaçışlı string olarak döndürür", {
  skip_if_not_installed("shiny")

  # Durum seviyesi -> rozet (shiny tag).
  rozet <- .hfmt_env$health_render_value("ok")
  expect_true(grepl("health-pill", paste(as.character(rozet), collapse = ""), fixed = TRUE))

  # Düz metin -> HTML kaçışlı karakter dizisi.
  metin <- .hfmt_env$health_render_value("sıradan <b>metin")
  expect_true(is.character(metin))
  expect_equal(metin, "sıradan &lt;b&gt;metin")
})

test_that("health_render_value depolama yolundaki Türkçe mojibake'i görüntüleme sınırında onarır", {
  skip_if_not_installed("shiny")

  # Fixture'ları deterministik Unicode ile kur (Windows/VM parse güvenliği).
  s_char <- intToUtf8(0x015F)        # ş (doğru)
  moji_A <- intToUtf8(0x00C5)        # Å (çift kodlanmış baytın görünür hali)

  # Üretim yolu (UTF-8): "...04 - Geliştirme\..."
  proper <- paste0("//rehisds/uygulamalar/04 - Geli", s_char, "tirme/data")
  Encoding(proper) <- "UTF-8"

  # Windows/.Renviron sınırını taklit et: BAYTLAR geçerli UTF-8 ama dize yanlış
  # (latin1) işaretli; Shiny serileştirirken çift kodlama ile mojibake oluşur.
  mismarked <- proper
  Encoding(mismarked) <- "latin1"

  out <- .hfmt_env$health_render_value(mismarked, "storage.files_root")
  serialized <- enc2utf8(paste(as.character(out), collapse = ""))

  # Onarım sonrası düzgün "ş" baytları görünmeli, "Å" mojibake'i görünmemeli.
  expect_true(grepl(s_char, serialized, useBytes = TRUE))
  expect_false(grepl(moji_A, serialized, useBytes = TRUE))

  # Regresyon: zaten doğru UTF-8 yol bozulmadan kalmalı.
  clean <- enc2utf8(paste(
    as.character(.hfmt_env$health_render_value(proper, "storage.files_root")),
    collapse = ""
  ))
  expect_true(grepl(s_char, clean, useBytes = TRUE))
  expect_false(grepl(moji_A, clean, useBytes = TRUE))

  # Depolama dışı id mojibake onarımına tabi olmamalı (sınır yalnızca yollar).
  passthrough <- .hfmt_env$health_render_value(mismarked, "db.connection")
  expect_true(is.character(passthrough))
})

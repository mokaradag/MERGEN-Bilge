# ==============================================================================
# Dosya Yolu: tests/testthat/test-api-key-choice-modal-contract.R
# Açıklama:   API Anahtarı Seçim (onboarding) modalı sözleşmesi. Statik ve
#             hafif kontroller: kaynak manifest sırası, güvenlik sınırları
#             (Sys.info fallback yok, istemciye ham anahtar sızmaz), yerel
#             varlık kuralı (CDN/uzak kaynak yok), "bir daha gösterme"
#             bastırma bayrağı ve UI varlık manifesti kaydı. Uygulama boot
#             etmez, ağır bağımlılık derlemez.
# ==============================================================================

.akc_repo_root <- function() {
  if (exists("repo_root_for_tests", inherits = TRUE)) {
    return(get("repo_root_for_tests", inherits = TRUE))
  }

  candidates <- c(
    getwd(),
    file.path(getwd(), ".."),
    file.path(getwd(), "..", "..")
  )

  for (candidate in candidates) {
    if (file.exists(file.path(candidate, "app.R")) &&
        dir.exists(file.path(candidate, "R"))) {
      return(normalizePath(candidate, winslash = "/", mustWork = FALSE))
    }
  }

  stop("Repo kökü bulunamadı.", call. = FALSE)
}

.akc_read <- function(rel_path) {
  readLines(
    file.path(.akc_repo_root(), rel_path),
    warn = FALSE,
    encoding = "UTF-8"
  )
}

.akc_text <- function(rel_path) {
  paste(.akc_read(rel_path), collapse = "\n")
}

test_that("seçim modalı yardımcısı manifestte module_api_key.R'den önce yüklenir", {
  manifest_lines <- .akc_read("R/config_source_manifest.R")

  helper_pos <- grep("\"R/module_api_key_choice_modal\\.R\"", manifest_lines)
  module_pos <- grep("\"R/module_api_key\\.R\"", manifest_lines)

  expect_length(helper_pos, 1)
  expect_length(module_pos, 1)
  expect_lt(helper_pos, module_pos)
})

test_that("seçim modalı yardımcısı yeni R/CSS/JS/varlık dosyaları repoda mevcut", {
  root <- .akc_repo_root()

  # Not: backdrop.mp4 BİLİNÇLİ olarak repoda yoktur (opsiyonel, internetsiz
  # ortamda yerel kopyalanır). Eksikliği bir hata değildir; poster + gradyan
  # geri düşüşü çalışır.
  expected <- c(
    "R/module_api_key_choice_modal.R",
    "www/css/api_key_choice_modal.css",
    "www/js/api_key_choice_modal.js",
    "www/assets/api-key-choice/mesh-background.svg",
    "www/assets/api-key-choice/security-orbit.svg",
    "www/assets/api-key-choice/personal-key.svg",
    "www/assets/api-key-choice/corporate-key.svg",
    "www/assets/api-key-choice/backdrop-poster.svg",
    "www/assets/api-key-choice/README.md"
  )

  missing <- expected[!file.exists(file.path(root, expected))]
  expect_equal(missing, character(0))
})

test_that("seçim modalı yardımcısı Sys.info kullanıcısına fallback yapmaz", {
  helper_lines <- .akc_read("R/module_api_key_choice_modal.R")
  forbidden_pattern <- "Sys\\.info\\(\\)\\[\\[\"user\"\\]\\]"
  expect_false(any(grepl(forbidden_pattern, helper_lines)))
})

test_that("seçim modalı varsayılan kurum anahtarı değerini gömmez / sızdırmaz", {
  helper_lines <- .akc_read("R/module_api_key_choice_modal.R")
  js_lines <- .akc_read("www/js/api_key_choice_modal.js")
  css_lines <- .akc_read("www/css/api_key_choice_modal.css")

  # Ham anahtar/varsayılan anahtar değeri hiçbir istemci/üretici dosyada olmamalı.
  expect_false(any(grepl("MERGEN_DEFAULT_API_KEY", helper_lines, fixed = TRUE)))
  expect_false(any(grepl("MERGEN_DEFAULT_API_KEY", js_lines, fixed = TRUE)))
  expect_false(any(grepl("MERGEN_DEFAULT_API_KEY", css_lines, fixed = TRUE)))

  # İstemci tarafı oturum anahtarını okumaz; yalnızca hassas olmayan bastırma
  # bayrağını mergen_settings içinde tutar.
  expect_false(any(grepl("ai_api_key", js_lines, fixed = TRUE)))
  expect_true(any(grepl("mergen_settings", js_lines, fixed = TRUE)))
  expect_true(any(grepl("api_key_onboarding_suppressed", js_lines, fixed = TRUE)))
})

test_that("seçim modalı iki yollu/tek yollu mantığı, input id'leri ve dontshow kutusunu korur", {
  helper_text <- .akc_text("R/module_api_key_choice_modal.R")

  # Mevcut kaydet/temizle observer'larının bağlanabilmesi için aynı input id'leri.
  expect_true(grepl("api_key_plain_input", helper_text, fixed = TRUE))
  expect_true(grepl("tags$form", helper_text, fixed = TRUE))
  expect_true(grepl("data-akc-password-form", helper_text, fixed = TRUE))
  expect_true(grepl("onsubmit = \"return false;\"", helper_text, fixed = TRUE))
  expect_true(grepl("api_key_save_btn", helper_text, fixed = TRUE))
  expect_true(grepl("api_key_clear_btn", helper_text, fixed = TRUE))
  # Varsayılan kurum anahtarı yolu için ayrı eylem.
  expect_true(grepl("api_key_use_default_btn", helper_text, fixed = TRUE))
  # default_available bayrağına göre dallanma korunur.
  expect_true(grepl("default_available", helper_text, fixed = TRUE))
  # "Bu ekranı bir daha gösterme" kutusu (yalnızca varsayılan anahtar varken).
  expect_true(grepl("akc-dontshow", helper_text, fixed = TRUE))
  # Anahtar giriş alanı her zaman görünür olmalı (JS'e bağlı aç/kapa yok);
  # kullanıcı anahtarını doğrudan girip kaydedebilmeli.
  expect_false(grepl("akc-reveal", helper_text, fixed = TRUE))
})

test_that("onboarding kararı istemci bastırma bayrağı için tolerans penceresi kullanır", {
  module_text <- .akc_text("R/module_api_key.R")
  # Modal, istemci tercihi gelmeden açılıp "bir daha gösterme" seçeneğini
  # işlevsiz bırakmamalı: bayrak gelene kadar veya tolerans dolana kadar bekle.
  expect_true(grepl("flag_arrived", module_text, fixed = TRUE))
  expect_true(grepl("api_key_decision_start", module_text, fixed = TRUE))
})

test_that("modal merkezleme, sayfa bulanıklığı ve animasyonlar CSS ile çalışır", {
  css_text <- .akc_text("www/css/api_key_choice_modal.css")
  # Dikey + yatay ortalama (Bootstrap 3 uyumlu, JS'siz).
  expect_true(grepl("vertical-align: middle", css_text, fixed = TRUE))
  expect_true(grepl("margin: 0 auto", css_text, fixed = TRUE))
  # Global 60vh modal-body kaydırma kısıtı bu modalda kaldırılır.
  expect_true(grepl("max-height: none !important", css_text, fixed = TRUE))
  expect_true(grepl(".akc-key-form", css_text, fixed = TRUE))
  expect_true(grepl("margin: 0", css_text, fixed = TRUE))
  # Sayfa (modal arkası) bulanıklığı CSS ile.
  expect_true(grepl("backdrop-filter: blur", css_text, fixed = TRUE))
  # Giriş animasyonları mevcut.
  expect_true(grepl("@keyframes akcCardIn", css_text, fixed = TRUE))
})

test_that("seçim modalı yerel arka plan videosu/posteri kullanır (uzak değil)", {
  helper_text <- .akc_text("R/module_api_key_choice_modal.R")

  expect_true(grepl("assets/api-key-choice/backdrop.mp4", helper_text, fixed = TRUE))
  expect_true(grepl("assets/api-key-choice/backdrop-poster.svg", helper_text, fixed = TRUE))
})

test_that("module_api_key.R seçim modalını çağırır ve bastırma bayrağını okur", {
  module_text <- .akc_text("R/module_api_key.R")

  expect_true(grepl("show_api_key_choice_modal", module_text, fixed = TRUE))
  expect_true(grepl("api_key_use_default_btn", module_text, fixed = TRUE))
  expect_true(grepl("api_key_onboarding_suppressed", module_text, fixed = TRUE))

  # Eski sabit genişlik/inline tooltip modal markup'ı geri gelmemeli.
  expect_false(grepl("secure_tooltip", module_text, fixed = TRUE))
})

test_that("Yapılandırma sayfası onboarding'i tekrar açma anahtarını içerir", {
  ui_text <- .akc_text("R/module_settings_yapilandirma_ui.R")
  expect_true(grepl("show_api_key_onboarding", ui_text, fixed = TRUE))
})

test_that("seçim modalı varlıkları yereldir (CDN/uzak kaynak yok)", {
  # CSS/JS/R üretici içinde uzak URL olmamalı (yalnızca yerel yollar).
  for (rel in c(
    "www/css/api_key_choice_modal.css",
    "www/js/api_key_choice_modal.js",
    "R/module_api_key_choice_modal.R"
  )) {
    text <- .akc_text(rel)
    expect_false(
      grepl("https?://", text, perl = TRUE),
      info = paste("Uzak URL bulundu:", rel)
    )
    expect_false(
      grepl("//cdn", text, fixed = TRUE),
      info = paste("CDN referansı bulundu:", rel)
    )
  }

  # SVG'lerde yalnızca SVG namespace URL'sine izin verilir.
  svg_files <- c(
    "www/assets/api-key-choice/mesh-background.svg",
    "www/assets/api-key-choice/security-orbit.svg",
    "www/assets/api-key-choice/personal-key.svg",
    "www/assets/api-key-choice/corporate-key.svg",
    "www/assets/api-key-choice/backdrop-poster.svg"
  )

  for (rel in svg_files) {
    stripped <- gsub("http://www\\.w3\\.org/2000/svg", "", .akc_text(rel), perl = TRUE)
    expect_false(
      grepl("https?://", stripped, perl = TRUE),
      info = paste("SVG içinde beklenmedik uzak URL:", rel)
    )
  }
})

test_that("seçim modalı CSS/JS dosyaları UI varlık manifestinde kayıtlı", {
  manifest_text <- .akc_text("R/config_ui_assets.R")
  expect_true(grepl("css/api_key_choice_modal.css", manifest_text, fixed = TRUE))
  expect_true(grepl("js/api_key_choice_modal.js", manifest_text, fixed = TRUE))
})

test_that("seçim modalı Shiny custom message handler imzalarını korur", {
  js_lines <- .akc_read("www/js/api_key_choice_modal.js")
  js_text <- paste(js_lines, collapse = "\n")

  # Shiny >= 1.11 custom message handler imzasını denetler:
  # handler tek argüman almalıdır. Sıfır argümanlı handler kayıt hatası üretir.
  zero_arg_handler_lines <- grep(
    "addCustomMessageHandler\\s*\\([^\\n]*function\\s*\\(\\s*\\)",
    js_lines,
    value = TRUE,
    perl = TRUE
  )

  expect_equal(zero_arg_handler_lines, character(0))
  expect_true(grepl(
    "mergenApiKeyChoiceInit[^\\n]*function\\s*\\(\\s*message\\s*\\)",
    js_text,
    perl = TRUE
  ))
  expect_true(grepl("void message;", js_text, fixed = TRUE))
})

test_that("seçim modalı kontrol yüzeyini handler'lardan önce hazırlar", {
  js_lines <- .akc_read("www/js/api_key_choice_modal.js")
  js_text <- paste(js_lines, collapse = "\n")

  init_pos <- grep(
    "window\\.MergenApiKeyChoice = window\\.MergenApiKeyChoice \\|\\| \\{\\};",
    js_lines
  )
  handler_pos <- grep("Shiny\\.addCustomMessageHandler", js_lines)

  expect_true(length(init_pos) >= 1L)
  expect_true(length(handler_pos) >= 1L)
  expect_lt(min(init_pos), min(handler_pos))

  # reportToServer erken/bozuk durumlarda tanımsız nesneye erişmemeli.
  expect_true(grepl(
    "var choice = window.MergenApiKeyChoice || {};",
    js_text,
    fixed = TRUE
  ))

  # Dosya sonunda nesne yeniden atanmamalı; erken gelen _inputId korunmalı.
  expect_false(grepl("window.MergenApiKeyChoice = {", js_text, fixed = TRUE))
  expect_true(grepl(
    "window.MergenApiKeyChoice._inputId = window.MergenApiKeyChoice._inputId || null;",
    js_text,
    fixed = TRUE
  ))
})
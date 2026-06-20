# ==============================================================================
# Dosya Yolu: tests/testthat/test-ui-asset-config-split-contract.R
# Açıklama: Frontend CSS/JS varlık manifestinin VERİ + DOĞRULAYICI + RENDER
#           ayrımını dondurur. Çözümleyici/doğrulayıcı API'si (ui_asset_all_css,
#           sıra/render planı doğrulaması) R/config_ui_assets.R'den ayrılıp
#           R/config_ui_asset_validators.R dosyasına; htmltools etiket render
#           katmanı (ui_asset_tags vb.) R/config_ui_asset_tags.R dosyasına
#           taşındı. Varlık VERİSİ (gruplar, ertelenmiş grup listesi, render
#           planı, JS/CSS sıra kuralları) ve düzleştirme yardımcısı
#           (ui_asset_flatten_groups) veri dosyasında kaldı. Bu, en büyük runtime
#           dosyasını (690 satır) odaklı dosyalara indirir; config_ui_asset_zones.R
#           VERİ/DOĞRULAYICI ayrımının aynı desenidir.
#
#           Bu yapısal bir sözleşmedir; sıra/etiket davranışı
#           test-config-ui-assets-helpers-behavior.R ve
#           test-ui-asset-tag-builders-behavior.R içinde, manifest sözleşmesi
#           test-ui-asset-manifest-contract.R içinde kapsanır. Uygulamayı
#           başlatmaz; DB, LLM, tarayıcı veya ağ GEREKMEZ.
# ==============================================================================

testthat::local_edition(3)
if (requireNamespace("shiny", quietly = TRUE)) {
  suppressMessages(library(shiny))
}

.read_repo_text_ui_asset_split <- function(rel_path) {
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

# Veriden ayrılıp çözümleyici/doğrulayıcı dosyasına taşınan saf fonksiyonlar.
.ui_asset_validator_fns <- c(
  "ui_asset_render_plan_groups",
  "ui_asset_render_plan_deferred",
  "ui_asset_validate_js_render_plan",
  "ui_asset_all_css",
  "ui_asset_all_js",
  "ui_asset_deferred_js_paths",
  "ui_asset_validate_css_order",
  "ui_asset_validate_js_order",
  "ui_asset_duplicate_paths",
  "ui_asset_public_root",
  "ui_asset_validate"
)

# htmltools etiket render katmanına taşınan fonksiyonlar.
.ui_asset_tag_fns <- c(
  "ui_asset_css_tag",
  "ui_asset_script_tag",
  "ui_asset_css_tags",
  "ui_asset_js_tags",
  "ui_asset_tags"
)

# Veri dosyasında kalması gereken veri nesneleri.
.ui_asset_data_objects <- c(
  "ui_asset_css_groups",
  "ui_asset_js_groups",
  "ui_asset_deferred_js_groups",
  "ui_asset_js_render_plan",
  "ui_asset_js_order_rules",
  "ui_asset_css_order_rules"
)

.source_ui_asset_split_env <- function() {
  env <- new.env(parent = globalenv())
  for (asset_file in c(
    "R/config_ui_assets.R",
    "R/config_ui_asset_validators.R",
    "R/config_ui_asset_tags.R"
  )) {
    suppressWarnings(source(
      file.path(repo_root_for_tests, asset_file),
      encoding = "UTF-8", local = env
    ))
  }
  env
}

test_that("validator ve tag dosyaları mevcuttur ve API'yi gösterir", {
  validators_path <- file.path(
    repo_root_for_tests, "R", "config_ui_asset_validators.R"
  )
  tags_path <- file.path(
    repo_root_for_tests, "R", "config_ui_asset_tags.R"
  )

  expect_true(
    file.exists(validators_path),
    info = "R/config_ui_asset_validators.R dosyası eklenmelidir."
  )
  expect_true(
    file.exists(tags_path),
    info = "R/config_ui_asset_tags.R dosyası eklenmelidir."
  )

  env <- .source_ui_asset_split_env()

  for (fn in c(.ui_asset_validator_fns, .ui_asset_tag_fns)) {
    expect_true(
      exists(fn, envir = env, mode = "function", inherits = FALSE),
      info = sprintf("Eksik fonksiyon: %s", fn)
    )
  }

  # Düzleştirme yardımcısı ve veri nesneleri veri dosyasından gelir.
  expect_true(
    exists("ui_asset_flatten_groups", envir = env, mode = "function", inherits = FALSE),
    info = "ui_asset_flatten_groups veri dosyasında kalmalıdır."
  )
  for (obj in .ui_asset_data_objects) {
    expect_true(
      exists(obj, envir = env, inherits = FALSE),
      info = sprintf("Veri nesnesi eksik: %s", obj)
    )
  }
})

test_that("runtime manifest VERİ -> DOĞRULAYICI -> RENDER sırasını korur", {
  expect_source_manifest_order_for_tests(
    c(
      "R/config_ui_assets.R",
      "R/config_ui_asset_validators.R",
      "R/config_ui_asset_tags.R"
    ),
    label = "Kaynak sırası varlık VERİSİ -> DOĞRULAYICI -> RENDER olmalıdır:"
  )
})

test_that("config_ui_assets.R VERİ-odaklıdır: taşınan fonksiyonlar kalmaz", {
  data_txt <- .read_repo_text_ui_asset_split("R/config_ui_assets.R")

  # Taşınan doğrulayıcı/etiket fonksiyonları artık veri dosyasında inline
  # tanımlı OLMAMALIDIR (runtime mantık sızması).
  for (fn in c(.ui_asset_validator_fns, .ui_asset_tag_fns)) {
    expect_false(
      grepl(sprintf("%s <- function", fn), data_txt, fixed = TRUE),
      info = sprintf(
        "Bu fonksiyon artık ayrı dosyada olmalıdır (validators/tags): %s",
        fn
      )
    )
  }

  # Veri nesneleri ve düzleştirme yardımcısı veri dosyasında korunmalıdır.
  expect_true(
    grepl("ui_asset_flatten_groups <- function", data_txt, fixed = TRUE),
    info = "ui_asset_flatten_groups veri dosyasında korunmalıdır."
  )
  expect_true(
    grepl("ui_asset_css_groups <- list(", data_txt, fixed = TRUE),
    info = "ui_asset_css_groups veri dosyasında korunmalıdır."
  )
  expect_true(
    grepl("ui_asset_js_groups <- list(", data_txt, fixed = TRUE),
    info = "ui_asset_js_groups veri dosyasında korunmalıdır."
  )
  expect_true(
    grepl("ui_asset_js_render_plan <- list(", data_txt, fixed = TRUE),
    info = "ui_asset_js_render_plan veri dosyasında korunmalıdır."
  )
  expect_true(
    grepl("ui_asset_js_order_rules <- list(", data_txt, fixed = TRUE),
    info = "ui_asset_js_order_rules veri dosyasında korunmalıdır."
  )
  expect_true(
    grepl("ui_asset_css_order_rules <- list(", data_txt, fixed = TRUE),
    info = "ui_asset_css_order_rules veri dosyasında korunmalıdır."
  )
})

test_that("doğrulayıcı dosyası API'ye sahiptir ama veriyi yeniden tanımlamaz", {
  validators_txt <- .read_repo_text_ui_asset_split(
    "R/config_ui_asset_validators.R"
  )

  for (fn in .ui_asset_validator_fns) {
    expect_true(
      grepl(sprintf("%s <- function", fn), validators_txt, fixed = TRUE),
      info = sprintf("Doğrulayıcı dosyası şu fonksiyonu içermelidir: %s", fn)
    )
  }

  # Veri nesneleri tek kaynak olarak veri dosyasında kalmalıdır.
  for (obj in .ui_asset_data_objects) {
    expect_false(
      grepl(sprintf("%s <- list(", obj), validators_txt, fixed = TRUE),
      info = sprintf("Veri tek kaynak olarak veri dosyasında kalmalıdır: %s", obj)
    )
  }
  # Etiket fonksiyonları doğrulayıcı dosyasında olmamalıdır.
  for (fn in .ui_asset_tag_fns) {
    expect_false(
      grepl(sprintf("%s <- function", fn), validators_txt, fixed = TRUE),
      info = sprintf("Etiket fonksiyonu render dosyasında olmalıdır: %s", fn)
    )
  }
})

test_that("etiket dosyası render katmanına sahiptir ama doğrulayıcı/veri tutmaz", {
  tags_txt <- .read_repo_text_ui_asset_split("R/config_ui_asset_tags.R")

  for (fn in .ui_asset_tag_fns) {
    expect_true(
      grepl(sprintf("%s <- function", fn), tags_txt, fixed = TRUE),
      info = sprintf("Etiket dosyası şu fonksiyonu içermelidir: %s", fn)
    )
  }

  # Doğrulayıcılar ve veri etiket dosyasında yeniden tanımlanmamalıdır.
  for (fn in .ui_asset_validator_fns) {
    expect_false(
      grepl(sprintf("%s <- function", fn), tags_txt, fixed = TRUE),
      info = sprintf("Doğrulayıcı doğrulayıcı dosyasında olmalıdır: %s", fn)
    )
  }
  for (obj in .ui_asset_data_objects) {
    expect_false(
      grepl(sprintf("%s <- list(", obj), tags_txt, fixed = TRUE),
      info = sprintf("Veri tek kaynak olarak veri dosyasında kalmalıdır: %s", obj)
    )
  }
})

test_that("bölme sonrası manifest doğrulaması ve çözümleyiciler bozulmaz", {
  env <- .source_ui_asset_split_env()

  # Sıra/render planı doğrulaması bölme sonrası hatasız geçmelidir.
  expect_error(env$ui_asset_validate(check_files = FALSE), NA)

  css_paths <- env$ui_asset_all_css()
  js_paths <- env$ui_asset_all_js()

  expect_true(length(css_paths) > 0L && is.character(css_paths))
  expect_true(length(js_paths) > 0L && is.character(js_paths))

  # Ertelenmiş JS çözümü veri ile tutarlı kalmalıdır.
  deferred <- env$ui_asset_deferred_js_paths()
  expect_true(all(deferred %in% js_paths))

  # Render planı grupları manifest gruplarıyla eşleşmeli (eksik/fazla yok).
  expect_silent(env$ui_asset_validate_js_render_plan())
})

test_that("etiket render katmanı link ve script üretir", {
  skip_if_not_installed("shiny")
  env <- .source_ui_asset_split_env()

  html <- paste(as.character(env$ui_asset_tags(check_files = FALSE)), collapse = "\n")
  expect_true(grepl("<link", html, fixed = TRUE))
  expect_true(grepl("<script", html, fixed = TRUE))
})

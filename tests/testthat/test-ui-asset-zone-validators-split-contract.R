# ==============================================================================
# Dosya Yolu: tests/testthat/test-ui-asset-zone-validators-split-contract.R
# Açıklama: Frontend bölge (zone) sahiplik haritasının VERİ + DOĞRULAYICI
#           ayrımını dondurur. Bölge çözümleme ve bölümleme (partition)
#           doğrulama API'si (saf fonksiyonlar) R/config_ui_asset_zones.R'den
#           ayrılıp R/config_ui_asset_zone_validators.R dosyasına taşındı;
#           bölge VERİSİ (ui_asset_ownership_zones +
#           ui_asset_unmanifested_ownership) veri dosyasında kaldı. Bu, en
#           büyük runtime dosyasını (777 satır) iki odaklı dosyaya indirir.
#
#           Bu yapısal bir sözleşmedir; bölge bölümleme davranışı
#           test-ui-asset-zones-contract.R içinde, ui_asset_zone_get
#           davranışı test-misc-runtime-predicates-behavior.R içinde kapsanır.
#           Uygulamayı başlatmaz; DB, LLM, tarayıcı veya ağ GEREKMEZ.
# ==============================================================================

.read_repo_text_zone_validators_split <- function(rel_path) {
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

# Bölge çözümleme + bölümleme doğrulama API'si (taşınan saf fonksiyonlar).
.zone_validator_fns <- c(
  "ui_asset_zone_ids",
  "ui_asset_zone_get",
  "ui_asset_zone_css_paths",
  "ui_asset_zone_js_paths",
  "ui_asset_zone_owner_seams",
  "ui_asset_zones_for_seam",
  "ui_asset_zones_validate",
  "ui_asset_frontend_ownership_gaps"
)

test_that("config_ui_asset_zone_validators.R exists and exposes the zone API", {
  validators_path <- file.path(
    repo_root_for_tests, "R", "config_ui_asset_zone_validators.R"
  )

  expect_true(
    file.exists(validators_path),
    info = "R/config_ui_asset_zone_validators.R dosyası eklenmelidir."
  )

  # Veri dosyası + doğrulayıcı dosyası aynı ortama yüklenir (varsayılan
  # argümanlar tembel değerlendirilir; çağrı anında veri görünür olmalıdır).
  env <- new.env(parent = globalenv())
  suppressWarnings(source(
    file.path(repo_root_for_tests, "R", "config_ui_assets.R"),
    encoding = "UTF-8", local = env
  ))
  suppressWarnings(source(
    file.path(repo_root_for_tests, "R", "config_ui_asset_zones.R"),
    encoding = "UTF-8", local = env
  ))
  suppressWarnings(source(
    file.path(repo_root_for_tests, "R", "config_ui_asset_zone_validators.R"),
    encoding = "UTF-8", local = env
  ))

  for (fn in .zone_validator_fns) {
    expect_true(
      exists(fn, envir = env, mode = "function", inherits = FALSE),
      info = sprintf("Eksik bölge doğrulayıcı/erişimci: %s", fn)
    )
  }

  # Veri nesneleri veri dosyasından gelir.
  expect_true(
    is.list(env$ui_asset_ownership_zones) && length(env$ui_asset_ownership_zones) > 0L,
    info = "ui_asset_ownership_zones veri dosyasında tanımlı olmalıdır."
  )
  expect_true(
    is.list(env$ui_asset_unmanifested_ownership),
    info = "ui_asset_unmanifested_ownership veri dosyasında tanımlı olmalıdır."
  )
})

test_that("runtime manifest sources zone data before zone validators", {
  expect_source_manifest_order_for_tests(
    c(
      "R/config_ui_asset_zones.R",
      "R/config_ui_asset_zone_validators.R"
    ),
    label = "Kaynak sırası bölge VERİSİ -> bölge DOĞRULAYICI olmalıdır:"
  )
})

test_that("config_ui_asset_zones.R is pure data: no validator functions remain", {
  data_txt <- .read_repo_text_zone_validators_split("R/config_ui_asset_zones.R")

  # Hiçbir fonksiyon tanımı veri dosyasında kalmamalıdır (runtime mantık sızması).
  expect_false(
    grepl("<- function(", data_txt, fixed = TRUE),
    info = "config_ui_asset_zones.R artık SADECE veri olmalıdır (fonksiyon tanımı yok)."
  )

  # Taşınan doğrulayıcılar artık veri dosyasında inline tanımlı OLMAMALIDIR.
  for (fn in .zone_validator_fns) {
    expect_false(
      grepl(sprintf("%s <- function", fn), data_txt, fixed = TRUE),
      info = sprintf(
        "Bu doğrulayıcı artık R/config_ui_asset_zone_validators.R içinde olmalıdır: %s",
        fn
      )
    )
  }

  # Veri nesneleri veri dosyasında korunmalıdır.
  expect_true(
    grepl("ui_asset_ownership_zones <- list(", data_txt, fixed = TRUE),
    info = "ui_asset_ownership_zones veri dosyasında korunmalıdır."
  )
  expect_true(
    grepl("ui_asset_unmanifested_ownership <- list(", data_txt, fixed = TRUE),
    info = "ui_asset_unmanifested_ownership veri dosyasında korunmalıdır."
  )
})

test_that("config_ui_asset_zone_validators.R owns the API and not the data", {
  validators_txt <- .read_repo_text_zone_validators_split(
    "R/config_ui_asset_zone_validators.R"
  )

  # Doğrulayıcı API fonksiyonları bu dosyada tanımlı olmalıdır.
  for (fn in .zone_validator_fns) {
    expect_true(
      grepl(sprintf("%s <- function", fn), validators_txt, fixed = TRUE),
      info = sprintf("Doğrulayıcı dosyası şu fonksiyonu içermelidir: %s", fn)
    )
  }

  # Veri nesneleri doğrulayıcı dosyasında yeniden tanımlanmamalıdır
  # (tek kaynak veri dosyasıdır; varsayılan argüman olarak referans serbesttir).
  expect_false(
    grepl("ui_asset_ownership_zones <- list(", validators_txt, fixed = TRUE),
    info = "Bölge verisi tek kaynak olarak config_ui_asset_zones.R'de kalmalıdır."
  )
  expect_false(
    grepl("ui_asset_unmanifested_ownership <- list(", validators_txt, fixed = TRUE),
    info = "Manifest dışı sahiplik verisi tek kaynak olarak veri dosyasında kalmalıdır."
  )
})

test_that("split preserves the manifest partition: ui_asset_zones_validate finds no problems", {
  # Veri + doğrulayıcı + gerçek manifest birlikte yüklendiğinde bölümleme
  # (partition) sağlam kalmalıdır: ayırma davranışı bozmadı.
  env <- new.env(parent = globalenv())
  suppressWarnings(source(
    file.path(repo_root_for_tests, "R", "config_ui_assets.R"),
    encoding = "UTF-8", local = env
  ))
  suppressWarnings(source(
    file.path(repo_root_for_tests, "R", "config_ui_asset_zones.R"),
    encoding = "UTF-8", local = env
  ))
  suppressWarnings(source(
    file.path(repo_root_for_tests, "R", "config_ui_asset_zone_validators.R"),
    encoding = "UTF-8", local = env
  ))

  problems <- env$ui_asset_zones_validate(
    zones = env$ui_asset_ownership_zones,
    css_paths = env$ui_asset_all_css(),
    js_paths = env$ui_asset_all_js(),
    css_groups = env$ui_asset_css_groups,
    js_groups = env$ui_asset_js_groups,
    unmanifested = env$ui_asset_unmanifested_ownership
  )

  expect_identical(
    problems,
    character(0),
    info = paste(
      "Bölme sonrası manifest bölümlemesi sağlam olmalıdır. Sorunlar:",
      paste(problems, collapse = " | ")
    )
  )

  # ui_asset_zone_ids harita adlarıyla aynı olmalıdır (erişimci doğru bağlanır).
  expect_identical(
    env$ui_asset_zone_ids(env$ui_asset_ownership_zones),
    names(env$ui_asset_ownership_zones),
    info = "ui_asset_zone_ids() bölge haritası adlarıyla aynı olmalıdır."
  )
})

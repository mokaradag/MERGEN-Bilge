# ==============================================================================
# Dosya Yolu: tests/testthat/test-ui-asset-zones-contract.R
# Açıklama: R/config_ui_asset_zones.R frontend bölge sahiplik haritasını
#           dondurur ve R/config_ui_assets.R manifestine karşı tam bölümleme
#           (partition) olarak doğrular. Uygulamayı başlatmaz; DB, LLM,
#           tarayıcı veya ağ gerektirmez.
#
#           Korunan sözleşmeler:
#             - Bölge id listesi bilinçli güncelleme gerektirir.
#             - Manifestteki HER CSS/JS varlığı tam olarak BİR bölgeye aittir.
#             - www/css ve www/js altındaki fiziksel dosyalarda sahiplik
#               boşluğu yoktur (manifest bölgesi ya da manifest dışı kayıt).
#             - Bölge sahipleri gerçek seam id'leridir ve guard testleri
#               repoda vardır.
#             - Smoke-only dosyalar üretim manifestine sızamaz.
# ==============================================================================

.load_ui_asset_zones_env <- function() {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())

  source(file.path(repo_root, "R", "config_ui_assets.R"), encoding = "UTF-8", local = env)
  source(file.path(repo_root, "R", "config_ui_asset_validators.R"), encoding = "UTF-8", local = env)
  source(file.path(repo_root, "R", "config_ui_asset_tags.R"), encoding = "UTF-8", local = env)
  source(file.path(repo_root, "R", "config_ui_asset_zones.R"), encoding = "UTF-8", local = env)
  source(file.path(repo_root, "R", "config_ui_asset_zone_validators.R"), encoding = "UTF-8", local = env)
  source(file.path(repo_root, "R", "config_seam_registry.R"), encoding = "UTF-8", local = env)

  env
}

# Dondurulmuş bölge id listesi. Bölge eklenir/çıkarılır/yeniden adlandırılırsa
# bu liste ve docs/architecture-map.md bilinçli olarak birlikte güncellenmelidir.
.expected_zone_ids <- c(
  "vendor_codemirror",
  "vendor_threejs",
  "vendor_ikon_fontlari",
  "tanilama",
  "kimlik_oturum",
  "cekirdek_kabuk",
  "tema",
  "kodlama_metin",
  "shiny_mesaj_koprusu",
  "akis_markdown_guvenligi",
  "sohbet_girisi_mesajlar",
  "karsilama_intro",
  "arac_arka_plan",
  "ses_yasam_dongusu",
  "dosya_yonetimi",
  "gorsel_uretim_galeri",
  "ozetleme_analiz",
  "gecmis_kayit_arama",
  "ayarlar_api_anahtar",
  "geri_bildirim_destek",
  "yonetici_saglik",
  "bilge_yolac_calisma",
  "bilge_yolac_oyun"
)

test_that("frontend bölge haritası beklenen bölge id listesini içerir", {
  env <- .load_ui_asset_zones_env()

  zones <- env$ui_asset_ownership_zones

  expect_true(is.list(zones), info = "ui_asset_ownership_zones bir liste olmalıdır.")

  expect_equal(
    names(zones),
    .expected_zone_ids,
    info = "Frontend bölge id listesi veya sırası değişti; bilinçli güncelleme gerekir."
  )

  expect_equal(
    env$ui_asset_zone_ids(zones),
    .expected_zone_ids,
    info = "ui_asset_zone_ids() bölge haritası adlarıyla aynı olmalıdır."
  )
})

test_that("bölge haritası manifest CSS/JS varlıklarını tam bölümler", {
  repo_root <- resolve_repo_root_for_tests()
  env <- .load_ui_asset_zones_env()

  problems <- env$ui_asset_zones_validate(
    zones = env$ui_asset_ownership_zones,
    css_paths = env$ui_asset_all_css(),
    js_paths = env$ui_asset_all_js(),
    css_groups = env$ui_asset_css_groups,
    js_groups = env$ui_asset_js_groups,
    unmanifested = env$ui_asset_unmanifested_ownership,
    repo_root = repo_root
  )

  expect_equal(
    problems,
    character(0),
    info = paste("Frontend bölge doğrulaması sorun bildirdi:", paste(problems, collapse = " | "))
  )
})

test_that("www/css ve www/js fiziksel dosyalarında sahiplik boşluğu yoktur", {
  repo_root <- resolve_repo_root_for_tests()
  env <- .load_ui_asset_zones_env()

  gaps <- env$ui_asset_frontend_ownership_gaps(
    repo_root = repo_root,
    zones = env$ui_asset_ownership_zones,
    css_paths = env$ui_asset_all_css(),
    js_paths = env$ui_asset_all_js(),
    unmanifested = env$ui_asset_unmanifested_ownership
  )

  expect_equal(
    gaps,
    character(0),
    info = paste(
      "Sahipsiz frontend dosyası bulundu. Dosyayı manifest + bir bölgeye ekleyin",
      "ya da ui_asset_unmanifested_ownership içinde gerekçesiyle sahiplenin:",
      paste(gaps, collapse = ", ")
    )
  )
})

test_that("bölge sahipleri gerçek seam id'leridir", {
  env <- .load_ui_asset_zones_env()

  zone_owners <- env$ui_asset_zone_owner_seams(env$ui_asset_ownership_zones)
  seam_ids <- env$mergen_seam_ids(env$mergen_seam_registry())

  unknown_owners <- setdiff(unique(zone_owners), seam_ids)

  expect_equal(
    unknown_owners,
    character(0),
    info = paste("Bölge sahibi olarak bilinmeyen seam kullanılmış:", paste(unknown_owners, collapse = ", "))
  )

  # Manifest dışı sahiplik kayıtları da gerçek seam'lere işaret etmelidir.
  unmanifested <- env$ui_asset_unmanifested_ownership
  unmanifested_owners <- character(0)

  for (path in names(unmanifested)) {
    unmanifested_owners <- c(unmanifested_owners, unmanifested[[path]]$owner_seam)
  }

  unknown_unmanifested <- setdiff(unique(unmanifested_owners), seam_ids)

  expect_equal(
    unknown_unmanifested,
    character(0),
    info = paste(
      "Manifest dışı sahiplik kaydı bilinmeyen seam'e işaret ediyor:",
      paste(unknown_unmanifested, collapse = ", ")
    )
  )
})

test_that("seam frontend bölgeleri tek kaynaktan türetilir", {
  env <- .load_ui_asset_zones_env()

  zones <- env$ui_asset_ownership_zones

  bilge_zones <- env$ui_asset_zones_for_seam("bilge_yolac", zones)

  expect_setequal(bilge_zones, c("bilge_yolac_calisma", "bilge_yolac_oyun"))

  frontend_zones <- env$ui_asset_zones_for_seam("frontend_varlik", zones)

  expect_true(
    all(c("vendor_codemirror", "vendor_threejs", "tema", "tanilama") %in% frontend_zones),
    info = "frontend_varlik seam'i vendor/tema/tanılama bölgelerini sahiplenmelidir."
  )
})

test_that("smoke-only dosyalar üretim manifestine sızmaz ve sahiplidir", {
  env <- .load_ui_asset_zones_env()

  manifest_assets <- c(env$ui_asset_all_css(), env$ui_asset_all_js())

  smoke_paths <- c("smoke/ux-smoke.html", "smoke/ux-smoke-probes.js")

  expect_equal(
    intersect(smoke_paths, manifest_assets),
    character(0),
    info = "Smoke-only dosyalar üretim varlık manifestine eklenemez."
  )

  unmanifested <- env$ui_asset_unmanifested_ownership

  expect_true(
    all(smoke_paths %in% names(unmanifested)),
    info = "Smoke-only dosyalar manifest dışı sahiplik kaydında listelenmelidir."
  )
})

test_that("optional_in_checkout girdileri checkout'ta dosya yokken sorun bildirmez, zorunlu girdiler bildirir", {
  repo_root <- resolve_repo_root_for_tests()
  env <- .load_ui_asset_zones_env()

  # On-prem-only vendored girdiler optional_in_checkout = TRUE taşımalıdır;
  # bu girdiler cloud checkout'unda fiziksel dosya olmadan da geçerlidir.
  unmanifested <- env$ui_asset_unmanifested_ownership
  on_prem_only_paths <- c("js/fontfaceobserver.js", "js/highlight.min.js")

  for (path in on_prem_only_paths) {
    expect_true(
      isTRUE(unmanifested[[path]]$optional_in_checkout),
      info = paste("On-prem-only vendored girdi optional_in_checkout = TRUE olmalıdır:", path)
    )
  }

  # Zorunlu (optional olmayan) bir girdi için dosya yokluğu hâlâ yapısal
  # sorun üretmelidir; doğrulayıcı yanlışlıkla tüm yokluk kontrolünü
  # gevşetmemelidir.
  fake_unmanifested <- unmanifested
  fake_unmanifested[["js/olmayan_zorunlu_dosya_kontrati.js"]] <- list(
    owner_seam = "frontend_varlik",
    reason = "Test: zorunlu girdi yokluk kontrolü korunmalıdır."
  )

  problems <- env$ui_asset_zones_validate(
    zones = env$ui_asset_ownership_zones,
    css_paths = env$ui_asset_all_css(),
    js_paths = env$ui_asset_all_js(),
    css_groups = env$ui_asset_css_groups,
    js_groups = env$ui_asset_js_groups,
    unmanifested = fake_unmanifested,
    repo_root = repo_root
  )

  expect_true(
    any(grepl("js/olmayan_zorunlu_dosya_kontrati.js", problems, fixed = TRUE)),
    info = "Zorunlu manifest dışı girdinin yokluğu yapısal sorun olarak bildirilmelidir."
  )

  # Optional girdiler aynı koşuda sorun listesinde görünmemelidir.
  expect_false(
    any(grepl("fontfaceobserver", problems, fixed = TRUE)) ||
      any(grepl("highlight.min", problems, fixed = TRUE)),
    info = "optional_in_checkout girdileri dosya yokken sorun olarak bildirilmemelidir."
  )
})

test_that("bölge çözümleme yardımcıları bilinmeyen grup referansında açık hata verir", {
  env <- .load_ui_asset_zones_env()

  bad_zone <- list(
    title = "test",
    owner_seam = "frontend_varlik",
    css_groups = c("olmayan_css_grubu"),
    js_groups = character(0),
    css = character(0),
    js = character(0),
    guard_tests = c("tests/testthat/test-ui-asset-zones-contract.R")
  )

  expect_error(
    env$ui_asset_zone_css_paths(bad_zone, css_groups = env$ui_asset_css_groups),
    regexp = "bilinmeyen CSS grubuna",
    info = "Bilinmeyen CSS grup referansı açık hata vermelidir."
  )

  bad_zone$css_groups <- character(0)
  bad_zone$js_groups <- c("olmayan_js_grubu")

  expect_error(
    env$ui_asset_zone_js_paths(bad_zone, js_groups = env$ui_asset_js_groups),
    regexp = "bilinmeyen JS grubuna",
    info = "Bilinmeyen JS grup referansı açık hata vermelidir."
  )
})

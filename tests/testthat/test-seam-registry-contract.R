# ==============================================================================
# Dosya Yolu: tests/testthat/test-seam-registry-contract.R
# Açıklama: R/config_seam_registry.R üretim-kritik dikiş (seam) kayıt defterini
#           dondurur ve manifest/bölge/dosya gerçekliğine karşı doğrular.
#           Uygulamayı başlatmaz; DB, LLM, tarayıcı veya ağ gerektirmez.
#
#           Korunan sözleşmeler:
#             - Seam id listesi bilinçli güncelleme gerektirir.
#             - Her source-manifest bölümü tam olarak BİR seam'e aittir.
#             - Seam guard testleri ve manifest dışı runtime dosyaları
#               gerçekten repoda vardır.
#             - R/ altında manifest + seam allowlist dışında sahipsiz runtime
#               R dosyası kalamaz.
# ==============================================================================

.load_seam_registry_env <- function() {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())

  source(file.path(repo_root, "R", "config_source_manifest.R"), encoding = "UTF-8", local = env)
  source(file.path(repo_root, "R", "config_ui_assets.R"), encoding = "UTF-8", local = env)
  source(file.path(repo_root, "R", "config_ui_asset_validators.R"), encoding = "UTF-8", local = env)
  source(file.path(repo_root, "R", "config_ui_asset_tags.R"), encoding = "UTF-8", local = env)
  source(file.path(repo_root, "R", "config_ui_asset_zones.R"), encoding = "UTF-8", local = env)
  source(file.path(repo_root, "R", "config_ui_asset_zone_validators.R"), encoding = "UTF-8", local = env)
  source(file.path(repo_root, "R", "config_seam_registry.R"), encoding = "UTF-8", local = env)

  env
}

# Dondurulmuş seam id listesi. Seam eklenir/çıkarılır/yeniden adlandırılırsa
# bu liste ve ilgili dokümantasyon (CLAUDE.md, docs/architecture-map.md)
# bilinçli olarak birlikte güncellenmelidir.
.expected_seam_ids <- c(
  "temel_altyapi",
  "veritabani_kodlama",
  "kimlik_sso",
  "api_anahtar_model",
  "sohbet_llm_akis",
  "mcp_analiz",
  "dosya_yasam_dongusu",
  "medya_ses",
  "bilge_yolac",
  "destek_yonetici_saglik",
  "shiny_calisma_zamani",
  "frontend_varlik"
)

test_that("seam kayıt defteri beklenen seam id listesini içerir", {
  env <- .load_seam_registry_env()

  registry <- env$mergen_seam_registry()

  expect_true(is.list(registry), info = "mergen_seam_registry() bir liste döndürmelidir.")

  expect_equal(
    names(registry),
    .expected_seam_ids,
    info = "Seam id listesi veya sırası değişti; bilinçli güncelleme gerekir."
  )

  expect_equal(
    env$mergen_seam_ids(registry),
    .expected_seam_ids,
    info = "mergen_seam_ids() kayıt defteri adlarıyla aynı olmalıdır."
  )
})

test_that("seam kayıt defteri manifest, bölge ve dosya gerçekliğine karşı temizdir", {
  repo_root <- resolve_repo_root_for_tests()
  env <- .load_seam_registry_env()

  registry <- env$mergen_seam_registry()
  sections <- env$source_manifest_sections
  zone_owners <- env$ui_asset_zone_owner_seams(env$ui_asset_ownership_zones)

  problems <- env$mergen_seam_registry_validate(
    registry = registry,
    manifest_section_names = names(sections),
    zone_owner_seam_ids = zone_owners,
    repo_root = repo_root
  )

  expect_equal(
    problems,
    character(0),
    info = paste("Seam kayıt defteri doğrulaması sorun bildirdi:", paste(problems, collapse = " | "))
  )
})

test_that("her manifest bölümü tam olarak bir seam tarafından sahiplenilir", {
  env <- .load_seam_registry_env()

  registry <- env$mergen_seam_registry()
  sections <- names(env$source_manifest_sections)
  owner_map <- env$mergen_seam_section_owner_map(registry)

  expect_equal(
    sort(names(owner_map)),
    sort(sections),
    info = "Bölüm -> seam sahiplik haritası manifest bölümleriyle birebir örtüşmelidir."
  )

  expect_equal(
    anyDuplicated(names(owner_map)),
    0L,
    info = "Bir manifest bölümü birden fazla seam tarafından sahiplenilemez."
  )
})

test_that("R/ altında manifest ve seam allowlist dışında sahipsiz runtime dosyası yoktur", {
  repo_root <- resolve_repo_root_for_tests()
  env <- .load_seam_registry_env()

  registry <- env$mergen_seam_registry()
  manifest_paths <- env$source_manifest_runtime_paths
  allowlist <- env$mergen_seam_runtime_allowlist(registry)

  r_files <- file.path("R", list.files(file.path(repo_root, "R"), pattern = "\\.R$", recursive = FALSE))

  orphans <- setdiff(r_files, c(manifest_paths, allowlist))

  # Sahipsiz dosyalar HER BİRİ AYRI SATIRDA raporlanır: tek satırlık uzun bir
  # mesaj Windows konsolunda kırpılabilir ve dosya adının son karakterleri
  # kaybolarak yanlış teşhise yol açar. Ayrıca manifestte BEKLENEN ama diskte
  # olmayan benzer adlı bir dosya varsa (kısmi kopyalamada tek karakter eksik
  # kalmış bir ad gibi) bu ilişki açıkça belirtilir.
  orphan_report <- ""
  if (length(orphans)) {
    orphan_report <- paste0(
      "\n",
      paste(vapply(orphans, function(yol) {
        benzer <- tryCatch(
          setdiff(
            agrep(basename(yol), basename(manifest_paths), max.distance = 0.1,
                  ignore.case = TRUE, value = TRUE),
            basename(yol)
          ),
          error = function(e) character(0)
        )

        paste0(
          "  - ", yol,
          if (length(benzer)) {
            paste0(
              "\n    Manifestte benzer adli kayit var: ",
              paste(benzer, collapse = ", "),
              " -> calisma kopyasi git ile senkron degil olabilir."
            )
          } else {
            ""
          }
        )
      }, character(1), USE.NAMES = FALSE), collapse = "\n")
    )
  }

  expect_equal(
    orphans,
    character(0),
    info = paste0(
      "Sahipsiz R/ dosyasi bulundu. Dosyayi R/config_source_manifest.R bolumune ",
      "ekleyin, ilgili seam'in extra_runtime_files listesine alin ya da artik ",
      "bir kopyaysa silin:",
      orphan_report
    )
  )
})

test_that("kök runtime giriş dosyaları seam allowlist'inde sahiplenilmiştir", {
  env <- .load_seam_registry_env()

  registry <- env$mergen_seam_registry()
  allowlist <- env$mergen_seam_runtime_allowlist(registry)
  manifest_paths <- env$source_manifest_runtime_paths

  root_entry_files <- c("app.R", "global.R", "ui.R", "server.R", "welcome_screen.R")

  covered <- root_entry_files %in% c(allowlist, manifest_paths)

  expect_true(
    all(covered),
    info = paste(
      "Kök runtime giriş dosyaları sahiplenilmemiş:",
      paste(root_entry_files[!covered], collapse = ", ")
    )
  )
})

test_that("seam erişim yardımcıları beklenen davranışı korur", {
  env <- .load_seam_registry_env()

  registry <- env$mergen_seam_registry()

  seam <- env$mergen_seam_get("bilge_yolac", registry)
  expect_equal(seam$title, "Bilge Yolaç (Claude Code)")
  expect_true("config_claude_code" %in% seam$manifest_sections)

  expect_error(
    env$mergen_seam_get("olmayan_seam", registry),
    regexp = "bulunamad",
    info = "Bilinmeyen seam id açık hata vermelidir."
  )

  expect_error(
    env$mergen_seam_get(c("a", "b"), registry),
    regexp = "tek bir",
    info = "Seam id tek karakter değeri olmalıdır."
  )
})

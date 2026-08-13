# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-entity-apply-behavior.R
# Açıklama: Faz 4 — varlık çözümlemesinin FİLTRE HATTINA bağlanması (§5.4).
#           Tamamen çevrimdışı ve belirlenimcidir: DB, LLM, tarayıcı, SSO, ağ
#           veya gizli değer GEREKMEZ.
#
# NEDEN BU DOSYA VAR: bağlama olmadan Faz 4 ÖLÜ KODDUR. Normalleştirme,
# alias/kanonik çözümleme, belirsizlik kapıları, netleştirme çipleri ve D11
# devralması yalnızca birim testlerinde çalışır; gerçek istekler LLM'in ham
# yaprak değerleriyle filtrelenmeye devam eder ve TÜM birim testler yeşil
# kalır. Bu dosya, çözümleyicinin GERÇEKTEN derleme öncesinde çalıştığını
# kanıtlar.
#
# Kapsanan sözleşmeler:
#   - Kanonik olmayan yazım, derlemeye GİDEN yaprakta kanonik değere döner.
#   - Çözümlenemeyen ÖZNE analizi DURDURUR (yanlış sayı üretilmez).
#   - Çözümlenemeyen İKİNCİL DARALTMA analizi durdurmaz; değer düşürülür ve
#     AÇIKÇA bildirilir.
#   - Kapalı sözlük GERÇEK veriden gelir; uydurma değer üretilmez.
#   - Anahtar kapalıyken hat hiçbir şey değiştirmez.
# ==============================================================================

pk_entity_source_chain_for_tests(extra = "helpers_pk_entity_apply.R")

local({
  # `%||%` çalışma zamanı yardımcısıdır; izole test zincirinde tanımlı olmayabilir.
  if (!exists("%||%", mode = "function")) {
    assign("%||%", function(x, y) if (is.null(x)) y else x, envir = globalenv())
  }
})

.PK_APPLY_VERI <- data.frame(
  Proje = c("ANKA Projesi", "AKINCI Projesi", "ANKA Projesi"),
  Departman = c("Yazılım", "Donanım", "Yazılım"),
  Tutar = c(10, 20, 30),
  stringsAsFactors = FALSE
)

.pk_apply_query <- function(match = "resolve", primary = "Proje", aliases = NULL) {
  list(meta = list(
    primary_entity = primary,
    column_meta = list(
      Proje = list(role = "dimension", match = match, filterable = TRUE,
                   aliases = aliases),
      Departman = list(role = "dimension", match = "resolve", filterable = TRUE)
    )
  ))
}

.pk_apply_leaf <- function(column, value, operation = "exact_match") {
  list(list(column = column, operation = operation, value = value))
}

test_that("kanonik olmayan yazım DERLEMEYE giden yaprakta kanonikleşir", {
  testthat::skip_if_not_installed("stringi")

  # Kullanıcı Türkçe karakter yazmadan arıyor; kapalı sözlükteki kanonik
  # değer ise Türkçe. Katman 3 (ASCII ikincil anahtar) bunu 90 puanla çözer.
  veri <- data.frame(
    Proje = c("KALIP", "ZZZZ"), Tutar = c(1, 2), stringsAsFactors = FALSE
  )

  plan <- pk_entity_resolve_filter_plan(
    data = veri,
    filters = .pk_apply_leaf("Proje", "kalip"),
    query = .pk_apply_query(primary = "Proje")
  )

  expect_equal(plan$action, "proceed")
  expect_equal(plan$filters[[1]]$value, "KALIP")
  expect_equal(plan$decisions[[1]]$decision, "auto")
})

test_that("çözümlenemeyen ÖZNE analizi DURDURUR", {
  testthat::skip_if_not_installed("stringi")

  plan <- pk_entity_resolve_filter_plan(
    data = .PK_APPLY_VERI,
    filters = .pk_apply_leaf("Proje", "zzzzzzzz"),
    query = .pk_apply_query(primary = "Proje")
  )

  expect_equal(plan$action, "halt")
  expect_true(nzchar(plan$message_tr))
  expect_equal(plan$decisions[[1]]$decision, "unresolved")
})

test_that("çözümlenemeyen İKİNCİL DARALTMA analizi durdurmaz, AÇIKÇA bildirilir", {
  testthat::skip_if_not_installed("stringi")

  # `Departman` birincil varlık DEĞİLDİR; kural 7 uygulanır.
  plan <- pk_entity_resolve_filter_plan(
    data = .PK_APPLY_VERI,
    filters = .pk_apply_leaf("Departman", "zzzzzzzz"),
    query = .pk_apply_query(primary = "Proje")
  )

  expect_equal(plan$action, "proceed")
  expect_length(plan$filters[[1]]$value, 0L)
  expect_true(length(plan$disclosures) >= 1L)
  expect_true(any(grepl("UYGULANMADI", plan$disclosures, fixed = TRUE)))
})

test_that("belirsiz aday analizi DURDURUR; sessizce ilki seçilmez", {
  testthat::skip_if_not_installed("stringi")

  veri <- data.frame(
    Proje = c("alfa beta gama", "alfa beta delta"),
    Tutar = c(1, 2), stringsAsFactors = FALSE
  )

  plan <- pk_entity_resolve_filter_plan(
    data = veri,
    filters = .pk_apply_leaf("Proje", "alfa beta"),
    query = .pk_apply_query(primary = "Proje")
  )

  expect_equal(plan$action, "halt")
  expect_equal(plan$decisions[[1]]$decision, "clarify")
})

test_that("kod/kimlik sütununda noktalama SİLİNMEZ", {
  testthat::skip_if_not_installed("stringi")

  veri <- data.frame(
    Kod = c("PRJ-001", "PRJ-002"), Tutar = c(1, 2), stringsAsFactors = FALSE
  )
  sorgu <- list(meta = list(
    primary_entity = "Kod",
    column_meta = list(Kod = list(role = "id", match = "exact", filterable = TRUE))
  ))

  # `PRJ 001` kanonik `PRJ-001` DEĞİLDİR; kesin sütunda bulanıklaştırma yoktur.
  plan <- pk_entity_resolve_filter_plan(
    data = veri, filters = .pk_apply_leaf("Kod", "PRJ 001"), query = sorgu
  )
  expect_equal(plan$action, "halt")

  # Tam kod yazıldığında sorunsuz geçer.
  plan_ok <- pk_entity_resolve_filter_plan(
    data = veri, filters = .pk_apply_leaf("Kod", "PRJ-001"), query = sorgu
  )
  expect_equal(plan_ok$action, "proceed")
  expect_equal(plan_ok$filters[[1]]$value, "PRJ-001")
})

test_that("match = 'contains' ve 'none' sütunlarına DOKUNULMAZ", {
  testthat::skip_if_not_installed("stringi")

  for (kip in c("contains", "none")) {
    sorgu <- list(meta = list(
      primary_entity = "Proje",
      column_meta = list(Proje = list(role = "dimension", match = kip))
    ))

    plan <- pk_entity_resolve_filter_plan(
      data = .PK_APPLY_VERI,
      filters = .pk_apply_leaf("Proje", "anka"),
      query = sorgu
    )

    expect_equal(plan$action, "proceed", info = kip)
    expect_equal(plan$filters[[1]]$value, "anka", info = kip)
  }
})

test_that("anahtar KAPALIYKEN hat hiçbir şeyi değiştirmez", {
  testthat::skip_if_not_installed("stringi")

  pk_entity_with_resolve_env(c(MERGEN_PK_RESOLVE_ENABLED = "false"), {
    plan <- pk_entity_resolve_filter_plan(
      data = .PK_APPLY_VERI,
      filters = .pk_apply_leaf("Proje", "zzzzzzzz"),
      query = .pk_apply_query(primary = "Proje")
    )

    expect_equal(plan$action, "proceed")
    expect_equal(plan$filters[[1]]$value, "zzzzzzzz")
    expect_length(plan$decisions, 0L)
  })
})

test_that("kapalı sözlük GERÇEK veriden gelir; uydurma değer üretilmez", {
  testthat::skip_if_not_installed("stringi")

  plan <- pk_entity_resolve_filter_plan(
    data = .PK_APPLY_VERI,
    filters = .pk_apply_leaf("Proje", "ANKA Projesi"),
    query = .pk_apply_query(primary = "Proje")
  )

  expect_equal(plan$action, "proceed")
  expect_true(all(plan$filters[[1]]$value %in% .PK_APPLY_VERI$Proje))
})

test_that("v2 yürütücüsü çözümlemeyi derlemeden ÖNCE çağırır", {
  repo_root <- resolve_repo_root_for_tests()
  yol <- file.path(repo_root, "R", "helpers_pk_analysis_filters_v2.R")

  ham <- readBin(yol, "raw", file.info(yol)$size)
  metin <- iconv(rawToChar(ham), from = "UTF-8", to = "UTF-8", sub = "byte")

  cozumleme <- regexpr("pk_entity_resolve_filter_plan", metin, fixed = TRUE)
  derleme <- regexpr("pk_filter_compile(data, filters, query = query)", metin, fixed = TRUE)

  expect_true(cozumleme > 0L, info = "Cozumleyici v2 yolunda cagrilmiyor.")
  expect_true(derleme > 0L)
  expect_true(
    cozumleme < derleme,
    info = "Cozumleme derlemeden SONRA calisiyor; kanonik olmayan deger derleyiciye gidiyor."
  )
})

test_that("bağlama katmanı manifestte ve doğru sıradadır", {
  expect_source_manifest_contains_for_tests("R/helpers_pk_entity_apply.R")

  expect_source_manifest_order_for_tests(c(
    "R/helpers_pk_entity_history.R",
    "R/helpers_pk_entity_apply.R",
    "R/helpers_pk_filter_compile.R"
  ))
})

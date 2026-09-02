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

pk_entity_source_chain_for_tests(extra = c("helpers_pk_entity_tree.R",
                                           "helpers_pk_entity_apply_leaf.R",
                                           "helpers_pk_entity_apply.R"))

# TABAN YALITIMI: bu dosyadaki SARILMAMIŞ (varsayılan eşikli) çözümleyici
# çağrıları da dağıtım `MERGEN_PK_RESOLVE_*` ortam değişkenlerinden ve
# eşleşen `mergen.pk.*` seçeneklerinden ETKİLENMEMELİDİR;
# `pk_entity_with_resolve_env()` yalnızca SARDIĞI çağrıyı korur.
pk_entity_isolate_resolve_config()

# `%||%` KAYNAK ZİNCİRİNİN ORTAMINA BAĞLANIR.
#
# `pk_entity_source_chain_for_tests()` varsayılan olarak `globalenv()` içine
# source eder, dolayısıyla üretilen fonksiyonların ENCLOSING ortamı
# `globalenv()`tir. Bu dosyanın gövdesinde tanımlanan bir `%||%` ise TEST DOSYASI
# ortamında kalır ve `pk_entity_resolve_filter_plan()` içindeki çağrılar onu
# GÖREMEZ: başka bir test dosyası operatörü küresel ortama sızdırmadıysa çağrı
# "could not find function" ile düşerdi (yani test SIRA BAĞIMLIYDI).
#
# Tanım bu yüzden `globalenv()` içine YALNIZCA YOKSA konur ve dosya sonunda
# GERİ ALINIR; kalıcı sızıntı olmaz. Üretim semantiği (`R/utils_common.R`)
# korunur: yalnızca `NULL` yedeğe düşer.
if (!exists("%||%", envir = globalenv(), inherits = FALSE)) {
  assign("%||%", function(x, y) if (is.null(x)) y else x, envir = globalenv())
  if (requireNamespace("withr", quietly = TRUE)) {
    withr::defer(
      suppressWarnings(try(rm("%||%", envir = globalenv()), silent = TRUE)),
      envir = testthat::teardown_env()
    )
  }
}
`%||%` <- get("%||%", envir = globalenv(), inherits = FALSE)

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

  # YORUM SATIRLARI TARAMA DIŞIDIR. `regexpr()` dosyadaki İLK geçişi bulur ve
  # bu dosyanın uzun Türkçe başlık bloğu iş birlikçilerini ADIYLA anar; gerçek
  # çağrı derlemeden SONRAYA taşınsa bile `cozumleme < derleme` başlıktaki
  # anıştan ötürü DOĞRU kalıyor ve test bu dosyanın yakalamak için var olduğu
  # regresyonu KAÇIRIYORDU.
  satirlar <- strsplit(enc2utf8(metin), "\n", fixed = TRUE)[[1]]
  satirlar <- satirlar[!grepl("^\\s*#", satirlar, perl = TRUE, useBytes = TRUE)]
  kod <- paste(satirlar, collapse = "\n")

  cozumleme <- regexpr("pk_entity_resolve_filter_plan", kod, fixed = TRUE)
  # BOŞLUKLARA TOLERANSLI: çağrı satır sonuna sarılır ya da aralıkları
  # değişirse SABİT dize eşleşmesi -1 döner, iddia düşer ve
  # `stop_on_failure = TRUE` altında TÜM süit üretim doğruyken kırılır.
  # Sözleşme argüman SIRASIdır, biçimlendirme değil.
  derleme <- regexpr(
    "pk_filter_compile\\(\\s*data\\s*,\\s*filters\\s*,\\s*query\\s*=\\s*query\\s*\\)",
    kod, perl = TRUE
  )

  expect_true(cozumleme > 0L, info = "Cozumleyici v2 yolunda cagrilmiyor.")
  expect_true(derleme > 0L)
  expect_true(
    cozumleme < derleme,
    info = "Cozumleme derlemeden SONRA calisiyor; kanonik olmayan deger derleyiciye gidiyor."
  )
})

test_that("bağlama katmanı manifestte ve doğru sıradadır", {
  expect_source_manifest_contains_for_tests("R/helpers_pk_entity_apply.R")
  # Yaprak karar katmanı plan gezintisinden ÖNCE yüklenmelidir.
  expect_source_manifest_contains_for_tests("R/helpers_pk_entity_apply_leaf.R")

  expect_source_manifest_order_for_tests(c(
    "R/helpers_pk_entity_history.R",
    "R/helpers_pk_entity_apply_leaf.R",
    "R/helpers_pk_entity_apply.R",
    "R/helpers_pk_filter_compile.R"
  ))
})

# ---------------------------------------------------------------------------
# KAPALI BAŞARISIZLIK: çözümleyici yapılandırması bozuk (`config_error`)
# ---------------------------------------------------------------------------

# Üretim çözümleyicisini GEÇİCİ olarak `config_error` döndürecek şekilde
# değiştirir ve blok bitince ESKİ tanımı geri koyar. `local_mocked_bindings()`
# kullanılamaz: bu depoda yardımcılar bir pakete değil, doğrudan ortama
# kaynaklanır. Geri yükleme yapılmazsa sonraki test dosyaları bozuk bir
# çözümleyici görürdü.
.pk_apply_with_config_error <- function(body_fn) {
  hedef <- environment(pk_entity_resolve_filter_plan)
  eski <- get("pk_entity_resolve_with_history", envir = hedef)
  assign("pk_entity_resolve_with_history", function(...) {
    list(decision = "config_error", values = character(0),
         message_tr = "Çözümleyici yapılandırması geçersiz.")
  }, envir = hedef)
  on.exit(assign("pk_entity_resolve_with_history", eski, envir = hedef), add = TRUE)
  body_fn()
}

test_that("ÖZNE yaprağında `config_error` analizi REDDEDER (ham değer filtreye derlenmez)", {
  # `config_error` bir veri belirsizliği değildir: eşikler/alias kaydı bozuktur.
  # GERİLEME: karar yalnızca bildiriliyor, `durdur` kurulmuyordu; plan
  # "proceed" dönüyor ve DOĞRULANMAMIŞ model değeri SQL filtresine giriyordu.
  .pk_apply_with_config_error(function() {

    plan <- pk_entity_resolve_filter_plan(
      data = .PK_APPLY_VERI,
      filters = .pk_apply_leaf("Proje", "ANKA"),
      query = .pk_apply_query(primary = "Proje")
    )

    expect_identical(plan$action, "halt")
    expect_true(nzchar(plan$message_tr))
  })
})

test_that("`config_error` İKİNCİL daraltmada da analizi REDDEDER", {
  # PR #705 inceleme bulgusu: rol koşulu (`subject`) tek başına yeterli
  # DEĞİLDİR. Sorgu metadata'sı `primary_entity` beyan etmediğinde ve planda
  # birden fazla filtre sütunu olduğunda HİÇBİR yaprak "subject" olmaz; o
  # durumda `config_error` hiçbir yerde `durdur` kurmuyor, plan "proceed"
  # dönüyor ve DOĞRULANMAMIŞ ham model değerleri SQL filtresine derleniyordu.
  # `config_error` bozuk çözümleyici YAPILANDIRMASIDIR; her rolde kapalı
  # başarısız olunur.
  .pk_apply_with_config_error(function() {
    plan <- pk_entity_resolve_filter_plan(
      data = .PK_APPLY_VERI,
      filters = .pk_apply_leaf("Departman", "Yazılım"),
      query = .pk_apply_query(primary = "Proje")
    )

    expect_identical(plan$action, "halt")
    expect_true(nzchar(plan$message_tr))
    expect_true(length(plan$disclosures) > 0L)
  })
})

# ---------------------------------------------------------------------------
# Birincil varlık BİLİNMİYORSA rol tespiti
# ---------------------------------------------------------------------------

test_that("birincil varlık bilinmiyorken çok sütunlu plan ÖZNE üretmez", {
  # GERİLEME: `pk_meta_primary_entity()` küratörlü `primary_entity` yokken ve
  # birden fazla filtre sütunu varken `NULL` döner. Her yaprak "subject"
  # sayılınca çözümlenemeyen bir İKİNCİL daraltma kural 6 (`unresolved`,
  # DURDUR) üretiyor ve TÜM analizi iptal ediyordu.
  expect_identical(
    .pk_entity_apply_role(list(meta = list()), "Departman", c("Proje", "Departman")),
    "refinement"
  )

  # Tek filtre sütunu varsa o sütun gerçekten ÖZNEDİR.
  expect_identical(
    .pk_entity_apply_role(list(meta = list()), "Proje", c("Proje")),
    "subject"
  )
})

test_that("birincil varlık bilinmiyorken çözümlenemeyen ikincil daraltma analizi durdurmaz", {
  # Bu blok `pk_entity_normalize()` üzerinden `stringi`ye ulaşır; dosyadaki
  # diğer çözümleyici testleri gibi paket yoksa ATLANIR (aksi hâlde
  # `stop_on_failure = TRUE` ile TÜM paket düşerdi).
  skip_if_not_installed("stringi")
  plan <- pk_entity_resolve_filter_plan(
    data = .PK_APPLY_VERI,
    filters = c(
      .pk_apply_leaf("Proje", "ANKA Projesi"),
      .pk_apply_leaf("Departman", "BULUNMAYAN-DEĞER")
    ),
    query = list(meta = list(
      column_meta = list(
        Proje = list(role = "dimension", match = "resolve", filterable = TRUE),
        Departman = list(role = "dimension", match = "resolve", filterable = TRUE)
      )
    ))
  )

  expect_identical(plan$action, "proceed")

  # ÇÖZÜMLENEMEYEN DARALTMA GERÇEKTEN DÜŞÜRÜLÜR ve BİLDİRİLİR.
  #
  # Yalnızca "proceed" iddiası, çözümlenemeyen `Departman` değeri filtrede
  # KALSA ya da hiçbir bildirim üretilmese de geçerdi; sorgu o zaman sessizce
  # BOŞ sonuç döndürürdü.
  expect_true(length(plan$disclosures) > 0L)
  kalan <- unlist(lapply(plan$filters %||% list(), function(y) as.character(y$value)),
                  use.names = FALSE)
  expect_false("BULUNMAYAN-DEĞER" %in% kalan)
})

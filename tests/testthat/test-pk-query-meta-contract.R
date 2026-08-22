# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-query-meta-contract.R
# Açıklama: Faz 3a — sorgu metadata sözleşmesi. Tamamen çevrimdışı ve
#           belirlenimcidir: DB, LLM, tarayıcı, SSO, ağ veya gizli değer
#           GEREKMEZ. Uygulamayı başlatmaz.
#
# Kapsanan kabul kriterleri (master plan §8 "Phase 3a", §7):
#   - Şemadan BAĞIMSIZ her geçersiz sözleşme başlangıcı DÜŞÜRÜR.
#   - Alias anahtarları NFC normalize + katlanır; çakışmalar reddedilir.
#   - Üretim alias hedefleri opsiyonel/gitignore'lu dosyada kalır; izlenen
#     dosyadaki alias'lar sentetik/onaylı olmak ZORUNDADIR.
#   - Yetenek kimlikleri allowlist'tedir; rol/birim tutarlıdır.
#   - Şema VARKEN şemaya bağlı uyumsuzluklar da başlangıcı düşürür.
#   - Şema YOKKEN bekleyen kontrol kaydedilir ve sorgu Tier-0 yapısal yoldan
#     boot eder.
#   - Anlamsal yetenek gerektiren istek SQL'den ÖNCE
#     `unknown_no_semantic_metadata` döner.
#   - SQL döndükten SONRAKİ gerçek sütun doğrulaması KOŞULSUZ fail-closed'dır.
#   - Her tüketicinin Tier-0 geri düşüşü ADIYLA doğrulanır.
# ==============================================================================

local({
  repo_root <- resolve_repo_root_for_tests()

  if (!exists("%||%", mode = "function", inherits = TRUE)) {
    `%||%` <<- function(a, b) if (is.null(a)) b else a
  }

  # Çalışma zamanı yükleme sırasının AYNISI (manifest §6 sırası).
  for (dosya in c(
    "helpers_pk_config.R",
    "helpers_pk_text_turkish.R",
    "helpers_pk_query_meta_schema.R",
    "helpers_pk_query_meta_access.R",
    "helpers_pk_query_meta_layers.R",
    "helpers_pk_query_meta.R"
  )) {
    source(file.path(repo_root, "R", dosya), encoding = "UTF-8", local = globalenv())
  }
})

# --- ORTAK FİKSTÜRLER ---------------------------------------------------------

.pk_meta_test_registry <- function() {
  list(
    "labor.remaining_hours"   = list(role = "measure",   unit = "saat"),
    "labor.planned_hours"     = list(role = "measure",   unit = "saat"),
    "progress.completion_pct" = list(role = "measure",   unit = "%"),
    "dimension.resource"      = list(role = "dimension", unit = NULL),
    "date.project_start"      = list(role = "date",      unit = NULL)
  )
}

# Tamamen SENTETİK sorgu metadata'sı. Üretim adı, gerçek proje/program adı ya
# da gerçek kanonik değer İÇERMEZ (master plan §5.1 gizlilik sınırı).
.pk_meta_test_query <- function(...) {
  temel <- list(
    grain = "activity_assignment",
    grain_columns = c("ProjeKodu"),
    primary_entity = "ProjeAdi",
    default_group_by = c("ProjeKodu"),
    default_measures = c("KalanIscilik_sa"),
    row_cap = 1000L,
    column_meta = list(
      ProjeKodu = list(label = "Proje Kodu", role = "id", match = "exact"),
      ProjeAdi = list(label = "Proje Adi", role = "dimension", match = "resolve",
                      filterable = TRUE),
      BaslangicTarihi = list(label = "Baslangic", role = "date",
                             capability = "date.project_start"),
      KalanIscilik_sa = list(label = "Kalan Iscilik", role = "measure",
                             capability = "labor.remaining_hours",
                             unit = "saat", decimals = 1, additive = TRUE)
    )
  )

  ek <- list(...)
  for (alan in names(ek)) temel[[alan]] <- ek[[alan]]
  temel
}

.pk_meta_test_library <- function(ids = "q001") {
  lapply(ids, function(id) {
    list(
      id = id,
      name = paste("Sentetik sorgu", id),
      sql = "SELECT 1",
      rls_columns = list(proje_kodu_col = "ProjeKodu", masraf_yeri_col = NULL)
    )
  })
}

# --- 1) YETENEK KAYDI ---------------------------------------------------------

test_that("yetenek kimlikleri allowlist'tedir ve rol/birim tutarlıdır", {
  registry <- .pk_meta_test_registry()

  expect_equal(pk_meta_validate_capability_registry(registry), character(0))

  # Bilinmeyen yetenek kimliği: sütun kayıtta olmayan bir kimliğe işaret ediyor.
  meta <- .pk_meta_test_query()
  meta$column_meta$KalanIscilik_sa$capability <- "labor.unknown_thing"
  hatalar <- pk_meta_validate_query("q001", meta, registry)
  expect_true(any(grepl("bilinmeyen capability", hatalar)))

  # Rol uyumsuzluğu: date yeteneği bir ölçü sütununa verilmiş.
  meta2 <- .pk_meta_test_query()
  meta2$column_meta$KalanIscilik_sa$capability <- "date.project_start"
  hatalar2 <- pk_meta_validate_query("q001", meta2, registry)
  expect_true(any(grepl("role='date' bekler", hatalar2)))

  # Birim uyumsuzluğu: kayıt "saat" der, sütun "adet" der.
  meta3 <- .pk_meta_test_query()
  meta3$column_meta$KalanIscilik_sa$unit <- "adet"
  hatalar3 <- pk_meta_validate_query("q001", meta3, registry)
  expect_true(any(grepl("unit='saat' bekler", hatalar3)))
})

test_that("kararsız yetenek kimliği ve geçersiz kayıt rolü reddedilir", {
  expect_true(any(grepl(
    "kararli olmayan",
    pk_meta_validate_capability_registry(list("Isçilik Kalan" = list(role = "measure")))
  )))

  expect_true(any(grepl(
    "gecersiz role",
    pk_meta_validate_capability_registry(list("labor.x" = list(role = "id")))
  )))

  # Boyut/tarih yeteneğinin birimi olmaz.
  expect_true(any(grepl(
    "unit tanimlanamaz",
    pk_meta_validate_capability_registry(list("dimension.x" = list(role = "dimension", unit = "saat")))
  )))
})

test_that("aynı yetenek iki sütunda ise deterministik varyant kuralı zorunludur", {
  registry <- .pk_meta_test_registry()

  meta <- .pk_meta_test_query()
  meta$column_meta$PlanlananIscilik_sa <- list(
    label = "Planlanan", role = "measure", capability = "labor.remaining_hours",
    unit = "saat", additive = TRUE
  )

  hatalar <- pk_meta_validate_query("q001", meta, registry)
  expect_true(any(grepl("birden fazla sutunda", hatalar)))

  # Açık varyant kuralı bildirilince kabul edilir ve kapı o sütunu seçer.
  meta$capability_variants <- list("labor.remaining_hours" = list(prefer = "KalanIscilik_sa"))
  expect_equal(pk_meta_validate_query("q001", meta, registry), character(0))

  beyan <- pk_meta_declared_capabilities(list(meta = meta))
  expect_equal(beyan[["labor.remaining_hours"]], "KalanIscilik_sa")
})

# --- 2) ŞEMADAN BAĞIMSIZ SÖZLEŞME ---------------------------------------------

test_that("geçersiz role/aggregate/match/percent_scale değerleri reddedilir", {
  registry <- .pk_meta_test_registry()

  gecersiz_rol <- .pk_meta_test_query()
  gecersiz_rol$column_meta$ProjeAdi$role <- "olcut"
  expect_true(any(grepl("gecersiz role", pk_meta_validate_query("q001", gecersiz_rol, registry))))

  gecersiz_agg <- .pk_meta_test_query()
  gecersiz_agg$column_meta$KalanIscilik_sa$aggregate <- "median"
  expect_true(any(grepl("gecersiz aggregate", pk_meta_validate_query("q001", gecersiz_agg, registry))))

  gecersiz_match <- .pk_meta_test_query()
  gecersiz_match$column_meta$ProjeAdi$match <- "fuzzy"
  expect_true(any(grepl("gecersiz match", pk_meta_validate_query("q001", gecersiz_match, registry))))

  # unit = "%" iken percent_scale ZORUNLU (Excel 61.3 -> %6130 tuzağı, §5.9).
  yuzde <- .pk_meta_test_query()
  yuzde$column_meta$TamamlanmaYuzde <- list(
    label = "Tamamlanma", role = "measure", capability = "progress.completion_pct",
    unit = "%", additive = FALSE
  )
  expect_true(any(grepl("percent_scale zorunludur", pk_meta_validate_query("q001", yuzde, registry))))

  yuzde$column_meta$TamamlanmaYuzde$percent_scale <- "points"
  expect_equal(pk_meta_validate_query("q001", yuzde, registry), character(0))
})

test_that("kod/kimlik sütunu bulanık eşleşme alamaz", {
  registry <- .pk_meta_test_registry()

  meta <- .pk_meta_test_query()
  meta$column_meta$ProjeKodu$match <- "resolve"

  expect_true(any(grepl(
    "bulanik match kullanilamaz",
    pk_meta_validate_query("q001", meta, registry)
  )))
})

test_that("weighted_mean ağırlığı ve latest sıralaması beyan edilmiş olmalıdır", {
  registry <- .pk_meta_test_registry()

  agirlikli <- .pk_meta_test_query()
  agirlikli$column_meta$KalanIscilik_sa$aggregate <- "weighted_mean"
  agirlikli$column_meta$KalanIscilik_sa$weight_by <- "OlmayanSutun"
  expect_true(any(grepl("weight_by", pk_meta_validate_query("q001", agirlikli, registry))))

  # latest, hem latest_by hem latest_tie_by olmadan çalıştırılamaz.
  son <- .pk_meta_test_query()
  son$column_meta$KalanIscilik_sa$aggregate <- "latest"
  hatalar <- pk_meta_validate_query("q001", son, registry)
  expect_true(any(grepl("latest_by ve latest_tie_by zorunludur", hatalar)))

  son$column_meta$KalanIscilik_sa$latest_by <- "BaslangicTarihi"
  son$column_meta$KalanIscilik_sa$latest_tie_by <- c("ProjeKodu")
  expect_equal(pk_meta_validate_query("q001", son, registry), character(0))
})

test_that("primary_entity / default_measures beyan edilmemiş sütuna işaret edemez", {
  registry <- .pk_meta_test_registry()

  meta <- .pk_meta_test_query(primary_entity = "OlmayanSutun")
  expect_true(any(grepl("primary_entity", pk_meta_validate_query("q001", meta, registry))))

  # default_measures ÖLÇÜ sütunu olmalıdır; boyut sütunu kabul edilmez.
  meta2 <- .pk_meta_test_query(default_measures = c("ProjeAdi"))
  expect_true(any(grepl("default_measures", pk_meta_validate_query("q001", meta2, registry))))

  meta3 <- .pk_meta_test_query(row_cap = 0L)
  expect_true(any(grepl("row_cap", pk_meta_validate_query("q001", meta3, registry))))
})

test_that("geçersiz sözleşme BAŞLANGICI düşürür (pk_query_meta_attach stop eder)", {
  registry <- .pk_meta_test_registry()
  bozuk <- .pk_meta_test_query()
  bozuk$column_meta$ProjeAdi$role <- "olcut"

  expect_error(
    pk_query_meta_attach(
      .pk_meta_test_library("q001"),
      auto = list(), local = list(), curated = list(q001 = bozuk),
      aliases = list(), registry = registry
    ),
    "PK_META"
  )

  # Geçerli sözleşme sorunsuz iliştirilir.
  sonuc <- pk_query_meta_attach(
    .pk_meta_test_library("q001"),
    auto = list(), local = list(), curated = list(q001 = .pk_meta_test_query()),
    aliases = list(), registry = registry
  )
  expect_equal(sonuc[[1]]$meta$primary_entity, "ProjeAdi")
})

# --- 3) ALIAS SÖZLEŞMESİ ------------------------------------------------------

test_that("alias anahtarları NFC normalize edilir ve Türkçe katlanır", {
  testthat::skip_if_not_installed("stringi")

  # Ayrışık `I` + U+0307 ile yazılmış anahtar; ayrıca sondaki noktasız `I`
  # Türkçe kuralla `ı`ya katlanmalıdır (İngilizce katlama `i` verirdi).
  ayrisik <- paste0("I", intToUtf8(0x0307L), "STANBUL PROJESI")
  harita <- c("SENTETIK PROJE A")
  names(harita) <- ayrisik

  katlama <- pk_meta_fold_alias_map("q001", "ProjeAdi", harita)

  # Beklenen anahtar kod noktalarından kurulur: "istanbul projes" + U+0131.
  beklenen <- paste0("istanbul projes", intToUtf8(0x0131L))

  expect_equal(katlama$errors, character(0))
  expect_equal(names(katlama$aliases), beklenen)
  expect_equal(unname(katlama$aliases), "SENTETIK PROJE A")

  # Birleşik biçimle yazılmış AYNI alias aynı anahtarı üretmelidir.
  birlesik <- c("SENTETIK PROJE A")
  names(birlesik) <- "İSTANBUL PROJESI"
  expect_equal(
    names(pk_meta_fold_alias_map("q001", "ProjeAdi", birlesik)$aliases),
    beklenen
  )
})

test_that("alias çakışması SERT hatadır; 'son yazan kazanır' yoktur", {
  testthat::skip_if_not_installed("stringi")

  # Aynı normalleştirilmiş anahtar iki FARKLI kanonik değere işaret ediyor.
  cakisan <- c("SENTETIK A", "SENTETIK B")
  names(cakisan) <- c("İSTANBUL", "istanbul")

  katlama <- pk_meta_fold_alias_map("q001", "ProjeAdi", cakisan)
  expect_true(any(grepl("birden fazla kanonik degere", katlama$errors)))

  # Aynı anahtar AYNI değere iki kez işaret ederse zararsızdır, tekilleştirilir.
  ayni <- c("SENTETIK A", "SENTETIK A")
  names(ayni) <- c("İSTANBUL", "istanbul")
  tekil <- pk_meta_fold_alias_map("q001", "ProjeAdi", ayni)
  expect_equal(tekil$errors, character(0))
  expect_equal(length(tekil$aliases), 1L)
})

test_that("boş alias anahtarı/hedefi ve yanlış tip reddedilir", {
  expect_true(any(grepl(
    "adlandirilmis karakter vektoru",
    pk_meta_fold_alias_map("q001", "ProjeAdi", list(a = "b"))$errors
  )))

  bos_hedef <- c("  ")
  names(bos_hedef) <- "alias"
  expect_true(any(grepl("bos kanonik hedef", pk_meta_fold_alias_map("q001", "ProjeAdi", bos_hedef)$errors)))
})

test_that("yerel alias bindirmesi YALNIZCA aliases alanını değiştirebilir", {
  registry <- .pk_meta_test_registry()
  birlesik <- list(q001 = .pk_meta_test_query())

  overlay <- list(q001 = list(
    ProjeAdi = c("sentetik kisaltma" = "SENTETIK PROJE A")
  ))

  sonuc <- pk_meta_apply_alias_overlay(birlesik, overlay)

  expect_equal(sonuc$errors, character(0))
  expect_equal(unname(sonuc$meta$q001$column_meta$ProjeAdi$aliases), "SENTETIK PROJE A")

  # Sözleşme alanları DEĞİŞMEDEN kalmalıdır.
  expect_equal(sonuc$meta$q001$grain, "activity_assignment")
  expect_equal(sonuc$meta$q001$primary_entity, "ProjeAdi")
  expect_equal(sonuc$meta$q001$column_meta$KalanIscilik_sa$capability, "labor.remaining_hours")
  expect_equal(sonuc$meta$q001$column_meta$ProjeAdi$role, "dimension")
  expect_equal(sonuc$meta$q001$column_meta$ProjeAdi$match, "resolve")
})

test_that("alias bindirmesi tanımsız sorgu/sütuna ve kod sütununa yazamaz", {
  birlesik <- list(q001 = .pk_meta_test_query())

  bilinmeyen_sorgu <- pk_meta_apply_alias_overlay(
    birlesik, list(q999 = list(ProjeAdi = c("a" = "B")))
  )
  expect_true(any(grepl("tanimsiz sorgu kimligine", bilinmeyen_sorgu$errors)))

  bilinmeyen_sutun <- pk_meta_apply_alias_overlay(
    birlesik, list(q001 = list(OlmayanSutun = c("a" = "B")))
  )
  expect_true(any(grepl("beyan edilmemis", bilinmeyen_sutun$errors)))

  # Kod/kimlik sütunu varsayılan olarak alias ALMAZ.
  kod_sutunu <- pk_meta_apply_alias_overlay(
    birlesik, list(q001 = list(ProjeKodu = c("a" = "B")))
  )
  expect_true(any(grepl("kod/kimlik sutunu alias alamaz", kod_sutunu$errors)))

  # Ayrıca gözden geçirilmiş allow_aliases = TRUE beyanı bunu açar.
  izinli <- birlesik
  izinli$q001$column_meta$ProjeKodu$allow_aliases <- TRUE
  expect_equal(
    pk_meta_apply_alias_overlay(izinli, list(q001 = list(ProjeKodu = c("a" = "B"))))$errors,
    character(0)
  )
})

test_that("izlenen dosyadaki alias'lar sentetik/onaylı olmak ZORUNDADIR", {
  onaysiz <- list(q001 = list(column_meta = list(
    ProjeAdi = list(role = "dimension", aliases = c("a" = "GERCEK PROGRAM ADI"))
  )))
  expect_equal(pk_meta_tracked_alias_audit(onaysiz), "q001/ProjeAdi")

  onayli <- onaysiz
  onayli$q001$column_meta$ProjeAdi$alias_provenance <- "synthetic"
  expect_equal(pk_meta_tracked_alias_audit(onayli), character(0))

  # Onaysız izlenen alias BAŞLANGICI düşürür.
  expect_error(
    pk_query_meta_attach(
      .pk_meta_test_library("q001"),
      auto = list(), local = list(), curated = onaysiz,
      aliases = list(), registry = .pk_meta_test_registry()
    ),
    "onay etiketi olmayan alias"
  )
})

test_that("YERELDEN gelen alias, izlenen dosya denetimini tetiklemez", {
  registry <- .pk_meta_test_registry()

  sonuc <- pk_query_meta_attach(
    .pk_meta_test_library("q001"),
    auto = list(), local = list(), curated = list(q001 = .pk_meta_test_query()),
    aliases = list(q001 = list(ProjeAdi = c("kisaltma" = "SENTETIK PROJE A"))),
    registry = registry
  )

  expect_equal(sonuc[[1]]$meta$column_meta$ProjeAdi$alias_provenance, "local_overlay")
  expect_equal(unname(sonuc[[1]]$meta$column_meta$ProjeAdi$aliases), "SENTETIK PROJE A")
})

# --- 4) KATMAN BİRLEŞTİRME ----------------------------------------------------

test_that("katman birleştirmede KÜRE EDİLMİŞ katman kazanır", {
  auto <- list(q001 = list(column_meta = list(
    ProjeAdi = list(label = "auto", role = "dimension", high_cardinality = NA)
  )))
  local <- list(q001 = list(
    result_schema = c(ProjeAdi = "character"),
    column_meta = list(
      ProjeAdi = list(label = "uretilen", role = "dimension", high_cardinality = TRUE)
    )
  ))
  curated <- list(q001 = list(
    grain = "activity",
    column_meta = list(ProjeAdi = list(label = "Kure Edilmis", match = "resolve"))
  ))

  birlesik <- pk_meta_merge_layers(auto = auto, local = local, curated = curated)$q001

  # Küre edilmiş alan kazanır.
  expect_equal(birlesik$column_meta$ProjeAdi$label, "Kure Edilmis")
  expect_equal(birlesik$column_meta$ProjeAdi$match, "resolve")
  # Küre edilmiş katmanın DOKUNMADIĞI alanlar alt katmandan korunur.
  expect_true(birlesik$column_meta$ProjeAdi$high_cardinality)
  expect_equal(birlesik$column_meta$ProjeAdi$role, "dimension")
  expect_equal(birlesik$result_schema[["ProjeAdi"]], "character")
  expect_equal(birlesik$grain, "activity")
})

test_that("üstün katmanda BİLEREK boşaltılan liste alanı alttakini korumaz", {
  # Bu, utils::modifyList() tuzağıdır (Faz 0 / D9): özyinelemeli birleştirme
  # `list()` ile boşaltmayı sessizce yok sayar. Bizim birleştirmemiz üstün
  # katmanın açık kararına uymalıdır.
  alt <- list(q001 = list(default_measures = c("A", "B")))
  ust <- list(q001 = list(default_measures = character(0)))

  birlesik <- pk_meta_merge_layers(auto = alt, curated = ust)$q001
  expect_equal(birlesik$default_measures, character(0))
})

# --- 5) ŞEMA VARKEN / YOKKEN --------------------------------------------------

test_that("şema YOKKEN bekleyen kontrol kaydedilir ve sorgu Tier-0'dan boot eder", {
  registry <- .pk_meta_test_registry()

  sonuc <- pk_query_meta_attach(
    .pk_meta_test_library("q001"),
    auto = list(), local = list(), curated = list(),
    aliases = list(), registry = registry
  )

  expect_equal(sonuc[[1]]$meta$schema_validation, PK_META_SCHEMA_PENDING)
  expect_equal(sonuc[[1]]$meta$tier, 0L)
  # Boot DÜŞMEZ: metadata'sı hiç olmayan sorgu da kütüphanede kalır.
  expect_equal(sonuc[[1]]$id, "q001")
})

test_that("şema VARKEN şemaya bağlı uyumsuzluk başlangıcı düşürür", {
  registry <- .pk_meta_test_registry()

  meta <- .pk_meta_test_query()
  meta$result_schema <- c(
    ProjeKodu = "character", ProjeAdi = "character",
    BaslangicTarihi = "Date", KalanIscilik_sa = "numeric"
  )

  # Şema uyumluyken sorun yok ve doğrulama "validated" olarak işaretlenir.
  sonuc <- pk_query_meta_attach(
    .pk_meta_test_library("q001"),
    auto = list(), local = list(), curated = list(q001 = meta),
    aliases = list(), registry = registry
  )
  expect_equal(sonuc[[1]]$meta$schema_validation, PK_META_SCHEMA_VALIDATED)

  # Beyan edilen RLS sütunu şemada yoksa: D6 fail-open deliği, başlangıç düşer.
  kutuphane <- .pk_meta_test_library("q001")
  kutuphane[[1]]$rls_columns <- list(proje_kodu_col = "OlmayanRlsSutunu")
  expect_error(
    pk_query_meta_attach(kutuphane, auto = list(), local = list(),
                         curated = list(q001 = meta), aliases = list(), registry = registry),
    "fail-open"
  )

  # Beyan edilen rol ile şemadaki yapısal tip uyuşmuyorsa da düşer.
  tip_bozuk <- meta
  tip_bozuk$result_schema[["KalanIscilik_sa"]] <- "character"
  expect_error(
    pk_query_meta_attach(.pk_meta_test_library("q001"), auto = list(), local = list(),
                         curated = list(q001 = tip_bozuk), aliases = list(), registry = registry),
    "sayisal degil"
  )
})

test_that("başlangıç şema doğrulaması, getirme-sonrası doğrulamadan AYRIDIR", {
  registry <- .pk_meta_test_registry()

  # Şema yok -> başlangıç ertelenir (hata YOK).
  kutuphane <- pk_query_meta_attach(
    .pk_meta_test_library("q001"),
    auto = list(), local = list(), curated = list(q001 = .pk_meta_test_query()),
    aliases = list(), registry = registry
  )
  expect_equal(kutuphane[[1]]$meta$schema_validation, PK_META_SCHEMA_PENDING)

  # Ama SQL döndükten sonra aynı sözleşme KOŞULSUZ zorlanır.
  gercek <- c("ProjeKodu", "ProjeAdi", "BaslangicTarihi", "KalanIscilik_sa")
  expect_true(pk_meta_validate_actual_columns(kutuphane[[1]], gercek)$ok)

  eksik_rls <- pk_meta_validate_actual_columns(
    kutuphane[[1]], setdiff(gercek, "ProjeKodu")
  )
  expect_false(eksik_rls$ok)
  expect_true(eksik_rls$fail_closed)
  expect_equal(eksik_rls$missing_rls, "ProjeKodu")
})

test_that("getirme-sonrası doğrulama eksik metadata sütununu da yakalar", {
  kutuphane <- .pk_meta_test_library("q001")
  kutuphane[[1]]$meta <- .pk_meta_test_query()

  sonuc <- pk_meta_validate_actual_columns(
    kutuphane[[1]], c("ProjeKodu", "ProjeAdi", "BaslangicTarihi")
  )

  expect_false(sonuc$ok)
  expect_true("KalanIscilik_sa" %in% sonuc$missing_declared)
  # RLS sütunu yerinde olduğu için fail_closed işareti RLS'e özgü kalır.
  expect_false(sonuc$fail_closed)
})

# --- 6) TIER-0 ÇIKARIMI VE ANLAMSAL KAPI --------------------------------------

test_that("Tier-0 yapısal rol çıkarır ama ANLAMSAL yetenek UYDURMAZ", {
  cerceve <- data.frame(
    ProjeKodu = c("P1", "P2"),
    BaslangicTarihi = as.Date(c("2026-01-01", "2026-02-01")),
    KalanIscilik_sa = c(10.5, 20.0),
    stringsAsFactors = FALSE
  )

  cikarim <- pk_meta_tier0_column_meta(cerceve)

  expect_equal(cikarim$ProjeKodu$role, "dimension")
  expect_equal(cikarim$BaslangicTarihi$role, "date")
  expect_equal(cikarim$KalanIscilik_sa$role, "measure")

  for (sutun in names(cikarim)) {
    # Anlam ASLA uydurulmaz.
    expect_null(cikarim[[sutun]]$capability)
    # Fail-closed: bulanık eşleşme ve filtre yetkisi verilmez.
    expect_equal(cikarim[[sutun]]$match, "none")
    expect_false(cikarim[[sutun]]$filterable)
    # Bir örneklem kardinalite/tanımlayıcı iddiasını KANITLAYAMAZ.
    expect_true(is.na(cikarim[[sutun]]$high_cardinality))
    expect_equal(cikarim[[sutun]]$tier, 0L)
  }

  # Tier-0 asla `id` rolü ATAMAZ: bir sütunun tanımlayıcı olduğu yapıdan
  # kanıtlanamaz (rastgele önek örneklemi tekilliği ispatlamaz, §5.1 Tier 0).
  expect_false(any(vapply(cikarim, function(x) identical(x$role, "id"), logical(1))))
})

test_that("anlamsal gereksinimli istek SQL'den ÖNCE unknown_no_semantic_metadata döner", {
  # Metadata'sı olmayan (Tier-0) aday.
  tier0 <- list(meta = list(column_meta = pk_meta_tier0_column_meta(
    c(ProjeKodu = "character", KalanIscilik_sa = "numeric")
  )))

  kapi <- pk_meta_capability_check(tier0, list(measures = "labor.remaining_hours"))
  expect_equal(kapi$status, PK_META_STATUS_NO_SEMANTICS)
  expect_equal(kapi$missing, "labor.remaining_hours")

  # Gereksinim YOKSA kapı açıktır: yapısal inceleme/render engellenmez.
  expect_equal(pk_meta_capability_check(tier0, list())$status, PK_META_STATUS_OK)

  # Küre edilmiş yetenek beyan edilmişse kapı açılır ve SÜTUNU adlandırır.
  kure <- list(meta = .pk_meta_test_query())
  acik <- pk_meta_capability_check(kure, list(
    measures = "labor.remaining_hours", dates = "date.project_start"
  ))
  expect_equal(acik$status, PK_META_STATUS_OK)
  expect_equal(acik$columns[["labor.remaining_hours"]], "KalanIscilik_sa")
  expect_equal(acik$columns[["date.project_start"]], "BaslangicTarihi")

  # Etiket ya da ham sütun adı yetenek YERİNE geçmez.
  expect_equal(
    pk_meta_capability_check(kure, list(measures = "KalanIscilik_sa"))$status,
    PK_META_STATUS_NO_SEMANTICS
  )
  expect_equal(
    pk_meta_capability_check(kure, list(measures = "iscilik"))$status,
    PK_META_STATUS_NO_SEMANTICS
  )
})

# --- 7) HER TÜKETİCİ İÇİN BELGELENMİŞ TIER-0 GERİ DÜŞÜŞÜ ----------------------

test_that("her tüketicinin Tier-0 geri düşüşü ADIYLA kayıtlıdır", {
  geri_dusus <- pk_meta_tier0_fallbacks()

  beklenen <- c(
    "primary_entity", "additive", "aggregate", "grain", "grain_columns",
    "default_measures", "default_group_by", "row_cap", "unit", "decimals",
    "match", "filterable", "domain", "high_cardinality", "capability"
  )

  expect_equal(sort(names(geri_dusus)), sort(beklenen))
  for (ad in beklenen) {
    expect_true(nzchar(geri_dusus[[ad]]), info = sprintf("'%s' geri dususu bos.", ad))
  }
})

test_that("primary_entity yoksa TEK filtre yaprağı birincildir, birden fazlaysa seçilmez", {
  bos <- list(meta = list())

  expect_equal(pk_meta_primary_entity(bos, filter_columns = "ProjeAdi"), "ProjeAdi")
  expect_null(pk_meta_primary_entity(bos, filter_columns = c("ProjeAdi", "Durum")))
  expect_null(pk_meta_primary_entity(bos, filter_columns = character(0)))

  # Beyan varsa beyan kazanır.
  expect_equal(
    pk_meta_primary_entity(list(meta = .pk_meta_test_query()), filter_columns = "Durum"),
    "ProjeAdi"
  )
})

test_that("additive bilinmiyorsa TOPLAMA YAPILMAZ (satır bazında raporlanır)", {
  bilinmeyen <- list(meta = list(column_meta = list(
    Tutar = list(role = "measure")   # additive BEYAN EDİLMEMİŞ
  )))
  expect_equal(pk_meta_aggregate_for(bilinmeyen, "Tutar"), "none")

  # Tier-0 çıkarımı da toplama yetkisi vermez.
  tier0 <- list(meta = list(column_meta = pk_meta_tier0_column_meta(c(Tutar = "numeric"))))
  expect_equal(pk_meta_aggregate_for(tier0, "Tutar"), "none")

  # additive = TRUE beyanı toplamayı açar.
  toplanabilir <- list(meta = list(column_meta = list(
    Tutar = list(role = "measure", additive = TRUE)
  )))
  expect_equal(pk_meta_aggregate_for(toplanabilir, "Tutar"), "sum")

  # Açık aggregate beyanı her şeyin üstündedir.
  agirlikli <- list(meta = list(column_meta = list(
    Oran = list(role = "measure", additive = TRUE, aggregate = "weighted_mean")
  )))
  expect_equal(pk_meta_aggregate_for(agirlikli, "Oran"), "weighted_mean")

  # Hiç tanınmayan sütun da güvenli tarafta kalır.
  expect_equal(pk_meta_aggregate_for(bilinmeyen, "HicYok"), "none")
})

test_that("match ve filterable geri düşüşleri FAIL-CLOSED yöndedir", {
  bos <- list(meta = list(column_meta = list(Serbest = list(role = "dimension"))))

  # Bulanık eşleşme metadata olmadan ASLA açılmaz.
  expect_equal(pk_meta_match_mode(bos, "Serbest"), "none")
  expect_equal(pk_meta_match_mode(bos, "HicYok"), "none")
  expect_false(pk_meta_is_filterable(bos, "Serbest"))

  # Kod/kimlik sütunu beyan edilmiş match olmadan da TAM eşleşir.
  kod <- list(meta = list(column_meta = list(Kod = list(role = "id"))))
  expect_equal(pk_meta_match_mode(kod, "Kod"), "exact")
})

test_that("row_cap geri düşüşü yapılandırma öncelik zincirini kullanır", {
  eski <- Sys.getenv("MERGEN_PK_ROW_CAP", unset = NA_character_)
  on.exit({
    if (is.na(eski)) Sys.unsetenv("MERGEN_PK_ROW_CAP") else Sys.setenv(MERGEN_PK_ROW_CAP = eski)
  }, add = TRUE)

  Sys.unsetenv("MERGEN_PK_ROW_CAP")

  # Sorgu metadata'sı global değeri EZER.
  expect_equal(pk_meta_row_cap(list(meta = list(row_cap = 200000L))), 200000L)

  # Metadata yoksa yerleşik varsayılan (sabit sayı kodda DEĞİL, spec'te).
  expect_equal(pk_meta_row_cap(list(meta = list())), pk_config_spec$MERGEN_PK_ROW_CAP$default)

  # Ortam değişkeni metadata'sız sorgu için geçerlidir.
  Sys.setenv(MERGEN_PK_ROW_CAP = "1234")
  expect_equal(pk_meta_row_cap(list(meta = list())), 1234L)
  # ...ama sorgu bazlı değer yine de kazanır.
  expect_equal(pk_meta_row_cap(list(meta = list(row_cap = 999L))), 999L)
})

# --- 8) DEPO SÖZLEŞMESİ: DOSYA AYRIMI VE GİZLİLİK SINIRI ----------------------

test_that("izlenen metadata üretim-only semantiği yalnız açık opsiyonel sözleşmeyle taşır", {
  repo_root <- resolve_repo_root_for_tests()

  auto_env <- new.env(parent = globalenv())
  source(file.path(repo_root, "R", "library_query_meta_auto.R"),
         encoding = "UTF-8", local = auto_env)
  expect_equal(length(get("pk_query_meta_auto", envir = auto_env)), 0L,
               info = "R/library_query_meta_auto.R Git'te BOS iskelet kalmalidir.")

  kure_env <- new.env(parent = globalenv())
  source(file.path(repo_root, "R", "library_query_meta.R"),
         encoding = "UTF-8", local = kure_env)

  # Yetenek kaydı doludur ve geçerlidir.
  registry <- get("pk_capability_registry", envir = kure_env)
  expect_true(length(registry) > 0L)
  expect_equal(pk_meta_validate_capability_registry(registry), character(0))

  tracked <- get("pk_query_meta", envir = kure_env)

  # Checkout'taki dört YER TUTUCU id'ye izlenen semantik bağlanamaz; üretim VM'i
  # aynı id'leri farklı gerçek sorgular için kullanabileceğinden bu sınır korunur.
  expect_equal(
    intersect(names(tracked), PK_META_CHECKOUT_PLACEHOLDER_IDS),
    character(0),
    info = paste(
      "Checkout'taki yer tutucu id'lere izlenen metadata baglanmamalidir;",
      "aksi halde VM'deki farkli gercek sorguya yanlis anlam tasinabilir."
    )
  )

  # BOŞ KÜME ÜZERİNDE `all()` VACUOUS TRUE'DUR. Küre edilmiş girdiler
  # `R/library_query_meta.R` içinden kazara silinirse hem aşağıdaki denetim hem
  # de yukarıdaki kesişim denetimi GEÇERDİ; yani bu sözleşmenin koruduğu
  # regresyon CI'ı kırmadan geri gelebilirdi.
  expect_true(
    length(tracked) > 0L,
    info = "Izlenen production-only semantik BOS olmamalidir; bos kume denetimi vacuous gecer."
  )

  # Git'te izlenen production-only semantik ancak yokluğu AÇIKÇA opsiyonel
  # işaretlenmişse taşınabilir. Gerçek üretim envanterinde eksik id yine
  # fail-closed'dur; bu istisna yalnız checkout yer tutucu envanterine özgüdür.
  expect_true(
    all(vapply(
      tracked,
      function(meta) is.list(meta) && isTRUE(meta$optional_when_absent),
      logical(1)
    )),
    info = paste(
      "Izlenen production-only semantik yalnizca",
      "optional_when_absent=TRUE ile acikca beyan edilmelidir."
    )
  )

  expect_equal(pk_meta_tracked_alias_audit(tracked), character(0))
})

test_that("yerel katmanlar gitignore'ludur ve manifestte OPSİYONEL işaretlidir", {
  repo_root <- resolve_repo_root_for_tests()

  yerel_dosyalar <- c("R/library_query_meta_local.R", "R/library_query_aliases_local.R")

  ignore_yolu <- file.path(repo_root, ".gitignore")
  ham <- readBin(ignore_yolu, what = "raw", n = file.info(ignore_yolu)$size)
  ignore_metni <- iconv(rawToChar(ham), from = "UTF-8", to = "UTF-8", sub = "byte")

  for (dosya in yerel_dosyalar) {
    expect_true(
      grepl(dosya, ignore_metni, fixed = TRUE, useBytes = TRUE),
      info = sprintf("%s .gitignore icinde degil; uretim verisi Git'e sizabilir.", dosya)
    )
  }

  # Manifestte bulunmalı ve OPSİYONEL olmalı (bulut checkout'unda yoklar).
  # Opsiyonel yol tanımları ayrı VERİ dosyasındadır (Faz 4, E5).
  manifest_env <- new.env(parent = globalenv())
  for (manifest_dosyasi in c("bootstrap_source_manifest.R", "config_source_manifest.R")) {
    source(file.path(repo_root, "R", manifest_dosyasi),
           encoding = "UTF-8", local = manifest_env)
  }

  runtime <- get("source_manifest_runtime_paths", envir = manifest_env)
  opsiyonel <- get("source_manifest_optional_source_paths", envir = manifest_env)

  for (dosya in yerel_dosyalar) {
    expect_true(dosya %in% runtime, info = sprintf("%s manifestte yok.", dosya))
    expect_true(dosya %in% opsiyonel, info = sprintf("%s opsiyonel isaretli degil.", dosya))
  }

  # Yoklukları GÜRÜLTÜ üretmemelidir: bu iki grup "yokluğu beklenen" listesinde.
  beklenen_eksik <- get("source_manifest_expected_absent_source_groups", envir = manifest_env)
  expect_true(all(c("pk_query_meta_local", "pk_query_aliases_local") %in% beklenen_eksik))
})

test_that("SQL loader metadata sözleşmesini çağırır ve strict bayrağından bağımsızdır", {
  repo_root <- resolve_repo_root_for_tests()
  yol <- file.path(repo_root, "R", "config_sql_loader.R")

  ham <- readBin(yol, what = "raw", n = file.info(yol)$size)
  metin <- iconv(rawToChar(ham), from = "UTF-8", to = "UTF-8", sub = "byte")

  expect_true(grepl("pk_query_meta_attach(query_library)", metin, fixed = TRUE, useBytes = TRUE))

  # Doğrulama, .SQL_LOADER_STRICT içine gömülmemelidir: gecersiz metadata ile
  # acilan bir uygulama sessizce yanlis cevap uretir.
  satirlar <- strsplit(metin, "\n", fixed = TRUE)[[1]]
  cagri_index <- grep("pk_query_meta_attach(query_library)", satirlar, fixed = TRUE)
  expect_length(cagri_index, 1L)

  onceki <- satirlar[max(1L, cagri_index - 3L):cagri_index]
  expect_false(
    any(grepl(".SQL_LOADER_STRICT", onceki, fixed = TRUE, useBytes = TRUE)),
    info = "Metadata dogrulamasi strict bayragina baglanmis."
  )
})

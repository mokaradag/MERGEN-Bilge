# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-query-selection-existential-behavior.R
# Açıklama: Faz 5 (§5.2) — VARLIK ("var mı?") biçimindeki anlamsal isteğin,
#           SEÇİLEN ADAYIN ZATEN SUNDUĞU SAYIM ölçüsüne DETERMİNİSTİK olarak
#           kanonikleştirilmesi.
#
# ÜRETİM TEKRAR ÜRETİMİ (Windows VM): anlamsal olarak AYNI üç soru farklı
# sonuçlanıyordu — sayım biçimleri `yetenek=ok` verirken varlık biçimi
# `unknown_capability` ile REDDEDİLİYORDU. Fark tamamen Geçiş B'nin ONTOLOJİ
# SÖZCÜĞÜ seçimindeydi; varlık ise `count > 0` ile zaten türetilebilir.
#
# BU DOSYA GENEL SÖZLEŞMEYİ KANITLAR, ÜÇ CÜMLEYİ EZBERLEMEZ: kimlikler
# sentetiktir, üretim sorgu kimliği/proje adı/veri kümesi KULLANILMAZ.
#
# Tamamen çevrimdışıdır: DB, LLM, tarayıcı, SSO, ağ ya da gizli değer GEREKMEZ.
# ==============================================================================

pk_select_source_chain_for_tests()

# Sentetik kavram: "geciken aktivite sayısı". Kayıt defterinde YALNIZCA sayım
# ölçüsü vardır; varlık kipi için AYRI bir kimlik TANIMLI DEĞİLDİR (inceleme
# şartı: uydurma takma adlar kayıt defterine eklenmez).
.pk_exist_registry <- function() {
  list(
    "activity.delayed_count"  = list(role = "measure",   unit = "adet"),
    "labor.remaining_hours"   = list(role = "measure",   unit = "saat"),
    "dimension.resource"      = list(role = "dimension", unit = NULL),
    "date.project_finish"     = list(role = "date",      unit = NULL)
  )
}

.pk_exist_query <- function() {
  list(
    id = "qsyn_01",
    name = "Sentetik Aktivite Gecikme Ozeti",
    meta = list(
      column_meta = list(
        GecikenAktiviteSayisi = list(
          label = "Geciken Aktivite Sayisi", role = "measure",
          capability = "activity.delayed_count", unit = "adet",
          decimals = 0, additive = TRUE, aggregate = "sum", filterable = TRUE
        ),
        KaynakAdi = list(
          label = "Kaynak Adi", role = "dimension", capability = "dimension.resource"
        )
      )
    )
  )
}

.pk_exist_ids <- function() names(.pk_exist_registry())

.pk_exist_validate <- function(requirements, query = .pk_exist_query(),
                               registry = .pk_exist_registry()) {
  pk_select_validate_requirements(query, requirements, names(registry),
                                  registry = registry)
}

test_that("VARLIK ve SAYIM biçimleri AYNI doğrulanmış gereksinime indirgenir", {
  # "Kac geciken aktivite var?" / "Toplam geciken aktivite sayisi nedir?"
  sayim <- .pk_exist_validate(list(measures = "activity.delayed_count"))

  # "Geciken aktiviteler var mi?" — model varlık kipini AYRI bir kimlik gibi
  # yazar; kayıt defterinde böyle bir kimlik YOKTUR.
  varlik <- .pk_exist_validate(list(measures = "activity.delayed_exists"))

  expect_equal(sayim$status, "ok")
  expect_equal(varlik$status, "ok")

  # Anlamsal SONUÇ aynıdır: ikisi de aynı SAYIM sütununu çözer.
  expect_equal(varlik$columns, sayim$columns)
  expect_equal(unname(varlik$columns[["activity.delayed_count"]]), "GecikenAktiviteSayisi")

  # Kanonikleştirme TANILAMADA görünür (operatör hangi kimliğin nereye
  # eşlendiğini görebilmelidir).
  expect_equal(unname(varlik$canonicalized[["activity.delayed_exists"]]),
               "activity.delayed_count")
  expect_length(sayim$canonicalized, 0L)
})

test_that("varlık kipi jetonunun YERİ ve DİLİ kararı değiştirmez", {
  # Sözcük TABLOSU değil, KİP jetonu tanınır: sonek, önek ve Türkçe biçim.
  for (kimlik in c("activity.delayed_exists", "activity.has_delayed",
                   "activity.delayed_presence", "activity.delayed_mevcut",
                   "activity.any_delayed")) {
    sonuc <- .pk_exist_validate(list(measures = kimlik))
    expect_equal(sonuc$status, "ok",
                 info = sprintf("varlık kipi tanınmadı: %s", kimlik))
    expect_equal(unname(sonuc$canonicalized[[kimlik]]), "activity.delayed_count")
  }
})

test_that("varlık kipi HANGİ ALANDA yazılırsa yazılsın SAYIM alanına taşınır", {
  # Model varlık isteğini `dimensions` altına da koyabilir; kanonik sayım
  # ölçüsü KENDİ rolüne ait alana yazılmazsa rol uyuşmazlığı üretilirdi.
  sonuc <- .pk_exist_validate(list(dimensions = "activity.delayed_exists"))
  expect_equal(sonuc$status, "ok")
  expect_equal(unname(sonuc$columns[["activity.delayed_count"]]), "GecikenAktiviteSayisi")
})

# --- FAIL-CLOSED SÖZLEŞMESİ KORUNUR ------------------------------------------

test_that("GERÇEKTEN bilinmeyen kavram hâlâ unknown_capability", {
  sonuc <- .pk_exist_validate(list(measures = "budget.total_cost"))
  expect_equal(sonuc$status, "unknown_capability")
  expect_true("budget.total_cost" %in% sonuc$unknown)
  expect_length(sonuc$canonicalized, 0L)
})

test_that("varlık kipi TAŞIMAYAN bilinmeyen kimlik kanonikleştirilmez", {
  # `_ratio` bir varlık kipi DEĞİLDİR; sayımdan türetilemez.
  sonuc <- .pk_exist_validate(list(measures = "activity.delayed_ratio"))
  expect_equal(sonuc$status, "unknown_capability")
})

test_that("kayıt defterinde OLAN ama sorgunun SUNMADIĞI kimlik capability_missing kalır", {
  sonuc <- .pk_exist_validate(list(measures = "labor.remaining_hours"))
  expect_equal(sonuc$status, "capability_missing")
  expect_true("labor.remaining_hours" %in% sonuc$missing)
})

test_that("varlık kipi de sorguda SAYIM yoksa capability_missing/unknown kalır", {
  # Aynı varlık isteği, sayım ölçüsü SUNMAYAN bir adayda kanonikleştirilemez.
  aday <- list(id = "qsyn_02", meta = list(column_meta = list(
    KalanIscilik_sa = list(label = "Kalan", role = "measure",
                           capability = "labor.remaining_hours", unit = "saat")
  )))
  sonuc <- .pk_exist_validate(list(measures = "activity.delayed_exists"), query = aday)
  expect_equal(sonuc$status, "unknown_capability")
  expect_length(sonuc$canonicalized, 0L)
})

test_that("BELİRSİZ eşleşme AUTO'ya dönüşmez", {
  # Aynı kavram anahtarına düşen İKİ sayım ölçüsü varsa hangisinin istendiği
  # BİLİNEMEZ; kapı kapalı kalır.
  belirsiz_registry <- c(.pk_exist_registry(), list(
    "activity.delayed_num" = list(role = "measure", unit = "adet")
  ))
  aday <- .pk_exist_query()
  aday$meta$column_meta$GecikenAktiviteAdedi <- list(
    label = "Geciken Aktivite Adedi", role = "measure",
    capability = "activity.delayed_num", unit = "adet", decimals = 0
  )

  sonuc <- pk_select_validate_requirements(
    aday, list(measures = "activity.delayed_exists"), names(belirsiz_registry),
    registry = belirsiz_registry
  )
  expect_equal(sonuc$status, "unknown_capability")
})

test_that("group_by içinde de geçen varlık kimliği kanonikleştirilmez", {
  # Bir SAYIM ölçüsü kırılım anahtarı olamaz; niyet belirsizdir.
  sonuc <- .pk_exist_validate(list(measures = "activity.delayed_exists",
                                   group_by = "activity.delayed_exists"))
  expect_equal(sonuc$status, "unknown_capability")

  # KAPININ KENDİSİ DOĞRULANIR.
  #
  # Yukarıdaki durum tek başına kapıyı SINAMAZ: `group_by` belirsizlik kuralı
  # tamamen kaldırılıp yalnızca `measures` kanonikleştirilse bile `group_by`
  # girdisi hâlâ BİLİNMEYEN bir yetenek olurdu ve durum yine
  # `unknown_capability` çıkardı. Bu yüzden dönüşümün HİÇ olmadığı doğrudan
  # iddia edilir.
  donusum <- pk_select_canonicalize_requirements(
    .pk_exist_query(),
    list(measures = "activity.delayed_exists",
         group_by = "activity.delayed_exists"),
    capability_ids = .pk_exist_ids(), registry = .pk_exist_registry()
  )
  expect_false(isTRUE(donusum$changed))
  expect_setequal(donusum$requirements$measures, "activity.delayed_exists")
  expect_setequal(donusum$requirements$group_by, "activity.delayed_exists")
})

test_that("SAYIM OLMAYAN bir ölçü varlık kipine hedef olamaz", {
  # `labor.remaining_hours` sorguda SUNULSA bile sayım DEĞİLDİR: "kalan işçilik
  # var mı?" sorusu saat toplamından deterministik olarak türetilemez.
  aday <- list(id = "qsyn_03", meta = list(column_meta = list(
    KalanIscilik_sa = list(label = "Kalan", role = "measure",
                           capability = "labor.remaining_hours", unit = "saat")
  )))
  sonuc <- pk_select_validate_requirements(
    aday, list(measures = "labor.remaining_exists"), .pk_exist_ids(),
    registry = .pk_exist_registry()
  )
  expect_equal(sonuc$status, "unknown_capability")
})

test_that("`unsupported` SERBEST METİNDİR ve kanonikleştirilmez", {
  # İfade edilemeyen ihtiyaç bir yetenek iddiası değildir; kanonikleştirme
  # ona DOKUNMAZ ve karar politikasının 4. kuralı devrede kalır.
  donusum <- pk_select_canonicalize_requirements(
    .pk_exist_query(),
    list(measures = character(0), unsupported = "gecikme nedeni kirilimi"),
    capability_ids = .pk_exist_ids(), registry = .pk_exist_registry()
  )
  expect_false(isTRUE(donusum$changed))
})

test_that("kanonikleştirme SAF ve enjekte edilebilirdir", {
  donusum <- pk_select_canonicalize_requirements(
    .pk_exist_query(), list(measures = "activity.delayed_exists"),
    capability_ids = .pk_exist_ids(), registry = .pk_exist_registry()
  )
  expect_true(isTRUE(donusum$changed))
  expect_setequal(donusum$requirements$measures, "activity.delayed_count")
  expect_false("activity.delayed_exists" %in% donusum$requirements$measures)
})

test_that("kanonikleştirme dosyası SAF kalır (Shiny/DB/LLM/ağ yok)", {
  yol <- file.path(resolve_repo_root_for_tests(), "R",
                   "helpers_pk_query_selection_canonical.R")
  ham <- readBin(yol, "raw", file.info(yol)$size)
  metin <- iconv(rawToChar(ham), from = "UTF-8", to = "UTF-8", sub = "byte")
  # Açıklama satırları taranmaz: "Shiny/reactive/DB/LLM/ağ bağımlılığı yoktur"
  # gibi bir SÖZLEŞME NOTU saflık ihlali değildir.
  satirlar <- strsplit(gsub("\r\n?", "\n", metin), "\n", fixed = TRUE)[[1]]
  metin <- paste(satirlar[!grepl("^\\s*#", satirlar, perl = TRUE)], collapse = "\n")

  for (yasak in c("shiny::", "session$", "reactive", "observeEvent",
                  "DBI::", "dbGetQuery", "httr", "curl")) {
    expect_false(grepl(yasak, metin, fixed = TRUE),
                 info = sprintf("saflık ihlali: %s", yasak))
  }
})

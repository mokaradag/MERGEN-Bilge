# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-fact-reference-scan-behavior.R
# Açıklama: BEKLENMEYEN MODEL SAYISI tarayıcısının DAR sözleşmesi (§5.11).
#
#           Tarayıcı bir EŞLEŞTİRİCİ DEĞİLDİR: bulduğu sayının hangi olguya ait
#           olabileceğini aramaz. Bu dosya hem kapsamı (veri görünümlü sayı
#           yakalanır) hem de dar kalmasını (yıl/tarih/madde numarası/güvenilir
#           istek değeri muaf) kilitler.
#
#           Tümü ÇEVRİMDIŞI ve DETERMİNİSTİKTİR.
# ==============================================================================

.pk_scan_env <- function() {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(x, y) if (is.null(x)) y else x

  for (dosya in c("helpers_pk_fact_reference.R", "helpers_pk_fact_reference_scan.R")) {
    source(file.path(repo_root, "R", dosya), encoding = "UTF-8", local = env)
  }
  env
}

# ---------------------------------------------------------------------------
# 1) VERİ GÖRÜNÜMLÜ SAYI yakalanır
# ---------------------------------------------------------------------------

test_that("ayrac / yuzde / dort hane / olcek birimi tasiyan sayilar yakalanir", {
  env <- .pk_scan_env()

  for (metin in c("Toplam 15.448 kayit bulundu.",
                  "Tamamlanma %61,3 seviyesinde.",
                  "Sure 47 saat olarak olculdu.",
                  "Deger 123456 olarak raporlandi.",
                  "Buyukluk 1e6 mertebesinde.")) {
    tarama <- env$pk_fact_literal_scan(metin, character(0))
    expect_equal(length(tarama$tokens), 1L, info = metin)
  }
})

test_that("negatif ve ondalikli sayilar da yakalanir", {
  env <- .pk_scan_env()
  expect_length(env$pk_fact_literal_scan("Sapma -2.450 saat.", character(0))$tokens, 1L)
  expect_length(env$pk_fact_literal_scan("Oran 0,87 civarinda.", character(0))$tokens, 1L)
})

# ---------------------------------------------------------------------------
# 2) MUAFİYETLER — tarayıcı DAR kalır, yanlış pozitif üretmez
# ---------------------------------------------------------------------------

test_that("yil, tarih, madde numarasi ve kucuk tam sayilar MUAFTIR", {
  env <- .pk_scan_env()

  for (metin in c("2024 yilinda program yeniden planlandi.",
                  "Son guncelleme 31.12.2024 tarihinde yapildi.",
                  "Guncelleme 2024.12.31 tarihinde yapildi.",
                  "1. Kaynak plani gozden gecirilsin.",
                  "2) Oncelikler yeniden siralansin.",
                  "Konu 3 kez ele alindi.")) {
    tarama <- env$pk_fact_literal_scan(metin, character(0))
    expect_equal(length(tarama$tokens), 0L, info = metin)
  }
})

test_that("negatif dort haneli sayi YIL muafiyetine DUSMEZ", {
  env <- .pk_scan_env()
  expect_length(env$pk_fact_literal_scan("Fark -2024 olarak olculdu.", character(0))$tokens, 1L)
})

test_that("yil bicimindeki sayi OLCEK BIRIMI tasiyorsa muaf DEGILDIR", {
  env <- .pk_scan_env()
  expect_length(env$pk_fact_literal_scan("Toplam 2024 saat harcandi.", character(0))$tokens, 1L)
})

# ---------------------------------------------------------------------------
# 3) GÜVENİLİR İSTEK DEĞERLERİ — tahminle değil, TAM eşleşmeyle tanınır
# ---------------------------------------------------------------------------

test_that("guvenilir istek degeri taranan metinde ihlal SAYILMAZ", {
  env <- .pk_scan_env()

  # Veri gorunumlu esik: guven OLMADAN yakalanir, guvenle muaf tutulur.
  expect_length(
    env$pk_fact_literal_scan("Kalan isciligi 1.500 uzerindeki isler.", "1500")$tokens, 0L
  )
  expect_length(
    env$pk_fact_literal_scan("Kalan isciligi 1.500 uzerindeki isler.", character(0))$tokens, 1L
  )
  # Bicim farki (binlik ayraci) ayni anahtara duser.
  expect_length(
    env$pk_fact_literal_scan("Esik 1.000 olarak verildi.", "1000")$tokens, 0L
  )
  expect_length(
    env$pk_fact_literal_scan("Esik 1.000 olarak verildi.", character(0))$tokens, 1L
  )
  # BASKA bir sayi muafiyeti PAYLASMAZ.
  expect_length(
    env$pk_fact_literal_scan("Toplam 45 saat harcandi.", "30")$tokens, 1L
  )
})

test_that("birimsiz istek esigi BIRIMLI model iddiasini muaf KILMAZ", {
  env <- .pk_scan_env()
  # 1000 gunluk filtre, ilgisiz "1.000 saat" iddiasini ortmemelidir.
  expect_length(env$pk_fact_literal_scan("Toplam 1.000 saat harcandi.", "1000")$tokens, 1L)
  # Istek degeri birimi TASIYORSA ayni birimli yinelemesi muaftir.
  anahtar <- env$pk_fact_trusted_input_keys(list(
    list(kind = "request_input", request_values = "1.000 saat", display = "1.000 saat")
  ))
  expect_true("1000|saat" %in% anahtar)
  expect_length(env$pk_fact_literal_scan("Esik 1.000 saat olarak verildi.", anahtar)$tokens, 0L)
})

test_that("guvenilir anahtar sayisal ANLAMI korur", {
  env <- .pk_scan_env()
  expect_identical(env$pk_fact_number_key("1.000"), "1000")
  expect_identical(env$pk_fact_number_key("1,5"), "1.5")
  expect_identical(env$pk_fact_number_key("12.500"), "12500")
  expect_identical(env$pk_fact_number_key("P15"), "")

  # Kategorik "P15" hicbir anahtar uretmez; "1,5" ile "15" ayni kovaya dusmez.
  expect_length(env$pk_fact_trusted_input_keys(list(
    list(kind = "request_input", request_values = "P15", display = "P15")
  )), 0L)
  anahtar <- env$pk_fact_trusted_input_keys(list(
    list(kind = "request_input", request_values = "1,5", display = "1,5", value = 1.5)
  ))
  expect_length(env$pk_fact_literal_scan("Toplam 15 saat harcandi.", anahtar)$tokens, 1L)

  # Ayristirilmis `value` alani anahtar URETMEZ (12.500 -> 12,5 -> "125" olmaz).
  anahtar <- env$pk_fact_trusted_input_keys(list(
    list(kind = "request_input", request_values = "12.500", display = "12.500", value = 12.5)
  ))
  expect_false("125" %in% anahtar)
  expect_true("12500" %in% anahtar)
})

test_that("guvenilir anahtarlar YALNIZCA request_input turunden cikarilir", {
  env <- .pk_scan_env()

  istek <- list(kind = "request_input", display = "30", value = 30,
                request_values = c("30", "60"))
  olcu <- list(kind = "measure", display = "15.448", value = 15448)

  anahtarlar <- env$pk_fact_trusted_input_keys(list(istek, olcu))
  expect_true(all(c("30", "60") %in% anahtarlar))
  expect_false("15448" %in% anahtarlar)
})

# ---------------------------------------------------------------------------
# 4) REFERANS JETONLARI TARANMAZ — kimlikteki rakamlar sayi sanilmaz
# ---------------------------------------------------------------------------

test_that("yuva jetonunun ICI sayi olarak taranmaz", {
  env <- .pk_scan_env()

  tarama <- env$pk_fact_literal_scan(
    "Ozellikle {{fact:activity_late_count.sum.overall.3b150a}} aktivite gecikti.",
    character(0)
  )
  expect_length(tarama$tokens, 0L)
})

test_that("eski bicim alinti isaretinin ICI de taranmaz", {
  env <- .pk_scan_env()
  tarama <- env$pk_fact_literal_scan("Deger [fact:olcu.sum.overall.217683] kadardir.",
                                     character(0))
  expect_length(tarama$tokens, 0L)
})

test_that("jeton konumlari OZGUN metin koordinatlarinda kalir", {
  env <- .pk_scan_env()
  metin <- "Once {{fact:a.sum.overall.aaaaaa}} sonra 99.999 saat."
  tarama <- env$pk_fact_literal_scan(metin, character(0))

  expect_length(tarama$tokens, 1L)
  jeton <- tarama$tokens[[1]]
  expect_identical(substr(metin, jeton$start, jeton$end), jeton$raw)
  expect_true(grepl("99.999", jeton$raw, fixed = TRUE))
})

# ---------------------------------------------------------------------------
# 5) WINDOWS / KODLAMA GÜVENLİĞİ
# ---------------------------------------------------------------------------

test_that("TL simgesi kaynak parse asamasinda native encodinge bagli kacis kullanmaz", {
  kod <- pk_test_code_only_file("R/helpers_pk_fact_reference_scan.R")

  # `fixed = TRUE` ile `ignore.case` R tarafindan YOK SAYILIR ve uyari uretir
  # (Windows tam suite bulgusu). Buyuk/kucuk harf duyarsiz arama bu yuzden
  # DUZENLI IFADE ile yapilir; ters bolu regex icin ayrica kacirilir. Niyet
  # AYNIDIR: kaynak dosya TL simgesini native encodinge bagli bir ters-bolu-u
  # kacisiyla YAZMAMALIDIR; simge `intToUtf8()` ile uretilir.
  expect_false(grepl("\\\\u\\{?20ba\\}?", kod, ignore.case = TRUE, perl = TRUE))

  env <- .pk_scan_env()
  tl <- intToUtf8(0x20BA)
  expect_identical(env$.PK_SCAN_TL_SIGN, tl)
  expect_true(grepl(tl, env$.PK_SCAN_CURRENCY, fixed = TRUE))
})

test_that("onek para birimi tasiyan tutar veri iddiasi olarak yakalanir", {
  env <- .pk_scan_env()
  tl <- intToUtf8(0x20BA)

  tarama <- env$pk_fact_literal_scan(paste0("Butce ", tl, "1.250 olarak belirlendi."),
                                     character(0))
  expect_length(tarama$tokens, 1L)
})

test_that("Turkce harfli birim jetonlari yerelden bagimsiz katlanir", {
  env <- .pk_scan_env()
  # "gün" ve "gun" AYNI birime katlanir; ikisi de olcek tasir.
  expect_length(env$pk_fact_literal_scan("Sure 47 gün surdu.", character(0))$tokens, 1L)
  expect_length(env$pk_fact_literal_scan("Sure 47 gun surdu.", character(0))$tokens, 1L)
})

# ---------------------------------------------------------------------------
# 6) SINIFLANDIRMA BOŞLUKLARI — veri iddiası kaçmaz, yapısal metin düşmez
# ---------------------------------------------------------------------------

test_that("olcek tasiyan kucuk degerler muafiyete DUSMEZ", {
  env <- .pk_scan_env()
  kare <- intToUtf8(0x00B2)
  kup <- intToUtf8(0x00B3)
  for (metin in c(paste0("Alan 47 m", kare, " olarak olculdu."),
                  paste0("Hacim 47 m", kup, " hesaplandi."),
                  "Butce $47 olarak belirlendi.",
                  paste0("Butce ", intToUtf8(0x20AC), "47 olarak belirlendi."),
                  "Maliyet 47 milyon TL oldu.",
                  "Toplam 3 milyar TL harcandi.",
                  "Toplam 12 bin proje var.")) {
    expect_gte(length(env$pk_fact_literal_scan(metin, character(0))$tokens), 1L)
  }
})

test_that("oran bicimi veri iddiasidir; saat ve tarih degildir", {
  env <- .pk_scan_env()
  expect_gte(length(env$pk_fact_literal_scan("Projelerin 1/2si gecikti.", character(0))$tokens), 1L)
  expect_gte(length(env$pk_fact_literal_scan("Oran 3:2 seviyesinde.", character(0))$tokens), 1L)
  expect_length(env$pk_fact_literal_scan("Toplanti 14:30 icin planlandi.", character(0))$tokens, 0L)
  expect_length(env$pk_fact_literal_scan("Teslim 31/12/2024 tarihinde.", character(0))$tokens, 0L)
})

test_that("teknik kimlik ve aralik icindeki rakamlar olcu SAYILMAZ", {
  env <- .pk_scan_env()
  for (metin in c("P1234 projesi gecikti.", "Aktivite A1000 tamamlandi.",
                  "ISO9001 standardi uygulandi.", "PRJ-2045 projesi incelendi.",
                  "Blok A1234 teslim edildi.", "2024-2025 doneminde plan degisti.")) {
    expect_length(env$pk_fact_literal_scan(metin, character(0))$tokens, 0L)
  }
})

test_that("tireli gun-once tarih negatif olcu SAYILMAZ, negatif olcu yine yakalanir", {
  env <- .pk_scan_env()
  expect_length(env$pk_fact_literal_scan("Son guncelleme 31-12-2024 tarihinde yapildi.",
                                         character(0))$tokens, 0L)
  expect_length(env$pk_fact_literal_scan("Guncelleme 2024-12-31 tarihinde yapildi.",
                                         character(0))$tokens, 0L)
  expect_length(env$pk_fact_literal_scan("Fark -2024 olarak olculdu.", character(0))$tokens, 1L)
})

test_that("birim sozcuguyle baslayan madde numarasi satiri DUSURMEZ", {
  env <- .pk_scan_env()
  for (metin in c("1. saat planlamasi gozden gecirilsin.",
                  "- 3. ay degerlendirmesi yapilsin.",
                  "2) gun bazli izleme kurulsun.")) {
    expect_length(env$pk_fact_literal_scan(metin, character(0))$tokens, 0L)
  }
  # Satir BASINDAKI birimli olcu madde numarasi SAYILMAZ.
  expect_length(env$pk_fact_literal_scan("47 saat harcandi.", character(0))$tokens, 1L)
})

test_that("uzun kanonik ve kapanmamis jetonlarin ICI sayi olarak taranmaz", {
  env <- .pk_scan_env()
  uzun <- paste0("grp.", paste(rep("x1234567890", 20), collapse = ""), ".sum.overall.abc123")
  expect_gt(nchar(uzun), 160L)
  metin <- paste0("Toplam ", env$pk_fact_reference_token(uzun), " kayit var.")
  expect_length(env$pk_fact_literal_scan(metin, character(0))$tokens, 0L)
  expect_length(env$pk_fact_literal_scan("Toplam {{fact:olcu_2024.sum.overall.123456",
                                         character(0))$tokens, 0L)
})

test_that("yinelenen iddia silinirken jetona iliskin rakam araligi tasinir", {
  env <- .pk_scan_env()
  metin <- "Toplam 15.448 aktivite gecikti."
  jeton <- env$pk_fact_literal_scan(metin, character(0))$tokens[[1]]
  expect_identical(substr(metin, jeton$start, jeton$number_end), "15.448")
  expect_identical(jeton$scale_unit, "")
  saat <- env$pk_fact_literal_scan("Toplam 15.448 saat.", character(0))$tokens[[1]]
  expect_identical(saat$scale_unit, "saat")
})

test_that("bos / NA / sayisiz girdi bos jeton listesi dondurur", {
  env <- .pk_scan_env()
  for (girdi in list("", NA_character_, NULL, "Tamamen niteliksel bir degerlendirme.")) {
    expect_length(env$pk_fact_literal_scan(girdi, character(0))$tokens, 0L)
  }
})

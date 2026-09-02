# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-filter-policy-behavior.R
# Açıklama: D4 / D5 / D9 / D12 — sıfır eşleşme politikası (birincil reddeder,
#           ikincil ifşayla düşer), `eval(parse())` kaldırılması, bozulmuş
#           filtre durumunda sessiz tam-küme devamının engellenmesi ve ölü
#           "genel soru" muhafızının v2 yolunda bulunmaması. Tümü çevrimdışı
#           ve deterministiktir: gerçek DB, LLM, tarayıcı, SSO, ağ veya gerçek
#           sır KULLANILMAZ.
# ==============================================================================

.pk_policy_env <- function() {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  # ÜRETİM OPERATÖRÜYLE AYNI (`R/utils_common.R`): yalnız `NULL` yedeğe düşer.
  env$`%||%` <- function(x, y) if (is.null(x)) y else x
  for (f in c("helpers_pk_text_turkish.R", "helpers_pk_query_meta_schema.R",
              "helpers_pk_query_meta_access.R", "helpers_pk_provenance.R",
              "helpers_pk_filter_compile.R", "helpers_pk_filter_group.R", "helpers_pk_filter_policy.R",
              "helpers_pk_analysis_filters_v2.R")) {
    source(file.path(repo_root, "R", f), encoding = "UTF-8", local = env)
  }
  env
}

.pk_policy_read_bytes <- function(rel_path) {
  full <- file.path(resolve_repo_root_for_tests(), rel_path)
  # EKSİK DOSYA KAPALI BAŞARISIZ OLUR.
  #
  # Boş metin döndürmek, D12 taramasını VACUOUS geçiriyordu: iddialar yalnızca
  # `expect_false(grepl(...))` biçiminde olduğu için boş dize hepsini
  # karşılıyordu. Dosya yeniden adlandırıldığında/taşındığında sözleşme
  # "başarılı" raporlardı (bkz. test-pk-rls-failclosed-contract.R).
  if (!file.exists(full)) {
    stop(sprintf("Dosya bulunamadı: %s", rel_path), call. = FALSE)
  }
  size <- suppressWarnings(file.info(full)$size[1])
  if (is.na(size) || size <= 0) {
    # BOŞ DOSYA DA VACUOUS GEÇİRİR: bu dosyalardaki taramaların çoğu
    # `expect_false(grepl(...))` biçimindedir ve boş dize hepsini karşılar.
    stop(sprintf("Kaynak dosya BOŞ ya da okunamıyor: %s", full), call. = FALSE)
  }
  con <- file(full, open = "rb")
  on.exit(close(con), add = TRUE)
  raw_data <- readBin(con, what = "raw", n = size)
  txt <- suppressWarnings(iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]])
  if (is.na(txt)) "" else enc2utf8(txt)
}

# Aciklama satirlari taranmaz: v2 dosyasi KASITLI olarak "v1'de bu alan
# subset(dt, eval(parse(...))) ile calistiriliyordu" cumlesini icerir.
.pk_policy_code_only <- function(rel_path) {
  txt <- .pk_policy_read_bytes(rel_path)
  satirlar <- strsplit(txt, "\n", fixed = TRUE)[[1]]
  satirlar <- satirlar[!grepl("^\\s*#", satirlar, perl = TRUE, useBytes = TRUE)]
  paste(satirlar, collapse = "\n")
}

.pk_policy_data <- function() {
  data.frame(
    ProjeAdi = c("SENTETIK ALFA", "SENTETIK BETA", "SENTETIK GAMA"),
    Durum = c("Aktif", "Pasif", "Aktif"),
    Butce = c(10, 20, 30),
    stringsAsFactors = FALSE
  )
}

test_that("D4: BIRINCIL sutunda sifir eslesme analizi REDDEDER", {
  env <- .pk_policy_env()
  veri <- .pk_policy_data()

  filtreler <- list(
    list(column = "ProjeAdi", value = "HIC OLMAYAN PROJE", operation = "exact_match")
  )
  derleme <- env$pk_filter_compile(veri, filtreler)
  politika <- env$pk_filter_zero_match_policy(veri, filtreler, derleme, NULL)

  expect_identical(politika$action, "refuse")
  expect_true(nzchar(politika$refusal_message))
  # Ne bos ekran ne de tum kume analizi: mesaj degeri ve alani ADIYLA soyler.
  expect_true(grepl("HIC OLMAYAN PROJE", politika$refusal_message, fixed = TRUE))
  expect_true(grepl("ProjeAdi", politika$refusal_message, fixed = TRUE))

  # "En yakin aday" onerisi BILEREK yoktur; o Faz 4 cozumleyicisinindir.
  expect_false(grepl("en yakın aday", politika$refusal_message, fixed = TRUE))
})

test_that("D4: IKINCIL sutunda sifir eslesme ifsayla dusurulur, analiz surer", {
  env <- .pk_policy_env()
  veri <- .pk_policy_data()

  filtreler <- list(
    list(column = "ProjeAdi", value = "SENTETIK ALFA", operation = "exact_match"),
    list(column = "Durum", value = "HIC OLMAYAN DURUM", operation = "exact_match")
  )
  derleme <- env$pk_filter_compile(veri, filtreler)

  # Metadata birincil varligi ProjeAdi olarak beyan eder.
  sorgu <- list(id = "q_sentetik", meta = list(primary_entity = "ProjeAdi"))
  politika <- env$pk_filter_zero_match_policy(veri, filtreler, derleme, sorgu)

  expect_identical(politika$action, "dropped_secondary")
  expect_identical(politika$dropped_columns, "Durum")
  expect_true(length(politika$disclosures) > 0L)
  # Birincil filtre uygulanmaya devam eder: tam olarak 1 satir kalir.
  expect_equal(sum(politika$mask), 1L)
})

test_that("birincil sutun belirleme metadata -> tek yaprak geri dusus sirasini izler", {
  env <- .pk_policy_env()

  # 1) Metadata beyan ediyorsa o kullanilir.
  expect_identical(
    env$pk_filter_primary_column(list(meta = list(primary_entity = "ProjeKodu")),
                                 c("ProjeAdi", "Durum")),
    "ProjeKodu"
  )

  # 2) Metadata yoksa (uretimdeki tum sorgular Tier-0) TEK filtre yapragi
  #    birincildir. Bu BELGELI geri dusustur.
  expect_identical(env$pk_filter_primary_column(NULL, "ProjeAdi"), "ProjeAdi")

  # 3) Metadata yok ve birden fazla filtre sutunu varsa birincil BELIRLENEMEZ;
  #    bu durumda hicbir sutun "birincil" sayilmaz.
  expect_null(env$pk_filter_primary_column(NULL, c("ProjeAdi", "Durum")))
})

test_that("D9: bozulmus filtre durumu sessiz tam-kume devamini ENGELLER", {
  env <- .pk_policy_env()

  for (durum in c("timeout", "error", "malformed")) {
    kapi <- env$pk_filter_degraded_gate(durum)
    expect_true(isTRUE(kapi$refuse), info = durum)
    expect_true(nzchar(kapi$message), info = durum)
    # Kullaniciya tum kayitlar uzerinden analiz YAPILMADIGI acikca soylenir.
    expect_true(grepl("YAPILMADI", kapi$message, fixed = TRUE), info = durum)
  }

  # Mesru filtresiz sonuc ve gozlem-amacli durumlar REDDEDILMEZ.
  for (durum in c("ok_no_filter", "ok_filtered", "disabled", "not_reached", "stopped")) {
    kapi <- env$pk_filter_degraded_gate(durum)
    expect_false(isTRUE(kapi$refuse), info = durum)
  }
})

test_that("D5: v2 yolunda eval(parse()) yoktur ve filter_expression calistirilmaz", {
  env <- .pk_policy_env()
  veri <- .pk_policy_data()

  # v1'de bu ifade `subset(dt, eval(parse(text = ...)))` ile CALISTIRILIYORDU.
  # Yan etkiyi kanitlamak icin sayac artiran bir ifade kullanilir.
  env$.pk_test_sayac <- 0L
  talimat <- list(
    filters = list(),
    filter_expression = "{ .pk_test_sayac <<- .pk_test_sayac + 1L; Butce > 5 }",
    aggregation = NULL
  )

  sonuc <- env$pk_apply_smart_filters_v2(veri, talimat, NULL)

  # Ifade DEGERLENDIRILMEDI: sayac artmadi ve satirlar filtrelenmedi.
  expect_identical(env$.pk_test_sayac, 0L)
  expect_equal(nrow(sonuc), 3L)

  karar <- attr(sonuc, env$PK_FILTER_V2_ATTR, exact = TRUE)
  gerekceler <- vapply(karar$dropped, function(d) d$reason, character(1))
  expect_true(any(grepl("çalıştırılabilir ifade", gerekceler, fixed = TRUE)))

  # Kaynak duzeyinde de eval(parse( kalibi bulunmamalidir.
  v2_kaynak <- .pk_policy_code_only("R/helpers_pk_analysis_filters_v2.R")
  derleyici <- .pk_policy_code_only("R/helpers_pk_filter_compile.R")
  for (metin in list(v2_kaynak, derleyici)) {
    expect_false(grepl("eval(parse(", metin, fixed = TRUE, useBytes = TRUE))
    expect_false(grepl("subset(dt", metin, fixed = TRUE, useBytes = TRUE))
  }
})

test_that("D12: olu 'genel soru' muhafizi v2 yolunda YOKTUR", {
  v2_kaynak <- .pk_policy_code_only("R/helpers_pk_analysis_filters_v2.R")

  for (kalip in c("genel_soru_kaliplari", "spesifik_varlik_var", "genel_soru_mu")) {
    expect_false(
      grepl(kalip, v2_kaynak, fixed = TRUE, useBytes = TRUE),
      info = sprintf("Olu muhafiz v2 yoluna geri geldi: %s", kalip)
    )
  }
})

test_that("v2 yurutucusu v1 ile ayni donus seklini korur", {
  env <- .pk_policy_env()
  veri <- .pk_policy_data()

  # Filtresiz -> data.frame
  duz <- env$pk_apply_smart_filters_v2(veri, list(filters = list()), NULL)
  expect_true(is.data.frame(duz))
  expect_equal(nrow(duz), 3L)

  # count
  say <- env$pk_apply_smart_filters_v2(
    veri, list(filters = list(), aggregation = "count"), NULL
  )
  expect_true(all(c("Sonuc", "Adet") %in% names(say)))
  expect_equal(say$Adet, 3L)

  # group_by
  grup <- env$pk_apply_smart_filters_v2(
    veri, list(filters = list(), aggregation = "group_by", group_column = "Durum"), NULL
  )
  expect_true("Durum" %in% names(grup))

  # sum
  toplam <- env$pk_apply_smart_filters_v2(
    veri, list(filters = list(), aggregation = "sum"), NULL
  )
  expect_true("Butce" %in% names(toplam))
  expect_equal(toplam$Butce, 60)

  # Bos veri
  bos <- env$pk_apply_smart_filters_v2(veri[0, , drop = FALSE], list(filters = list()), NULL)
  expect_true(is.data.frame(bos))
  expect_equal(nrow(bos), 0L)
})

test_that("ifsa blogu dusurulen, sifir eslesen ve etkisiz filtreleri isimlendirir", {
  env <- .pk_policy_env()

  blok <- env$pk_filter_policy_disclosure_block(
    list(disclosures = "`Durum` alanindaki kriter eslesmedi."),
    dropped = list(list(leaf = list(column = "Butce"), reason = "sayisal degil")),
    noop_columns = "ProjeAdi"
  )

  expect_true(nzchar(blok))
  expect_true(grepl("Durum", blok, fixed = TRUE))
  expect_true(grepl("Butce", blok, fixed = TRUE))
  expect_true(grepl("ProjeAdi", blok, fixed = TRUE))
  expect_true(grepl("ETKİSİZ", blok, fixed = TRUE))

  expect_null(env$pk_filter_policy_disclosure_block(list(), list(), character(0)))
})

test_that("D4: birincil belirlenemez VE her filtre sifir eslesirse analiz REDDEDILIR", {
  env <- .pk_policy_env()
  veri <- .pk_policy_data()

  # Uretimdeki sorgular su an Tier-0'dir: metadata birincil varligi beyan
  # etmez ve birden fazla filtre sutunu varken birincil BELIRLENEMEZ. O halde
  # "ikincil daraltmayi dusur, analiz sursun" kurali geriye HICBIR daraltma
  # birakmaz ve tum yetkili kume uzerinden istatistik uretilir; bu tam olarak
  # D4'un engellemek icin var oldugu sonuctur.
  filtreler <- list(
    list(column = "ProjeAdi", value = "HIC OLMAYAN PROJE", operation = "exact_match"),
    list(column = "Durum", value = "HIC OLMAYAN DURUM", operation = "exact_match")
  )
  derleme <- env$pk_filter_compile(veri, filtreler)
  politika <- env$pk_filter_zero_match_policy(veri, filtreler, derleme, NULL)

  expect_null(politika$primary_column)
  expect_identical(politika$action, "refuse")
  expect_true(nzchar(politika$refusal_message))
  # Mesaj eslesmeyen degerleri ADIYLA soyler; bos ekran/tum-kume degil.
  expect_true(grepl("HIC OLMAYAN PROJE", politika$refusal_message, fixed = TRUE))
  # Tum kume uzerinden devam EDILMEZ.
  expect_equal(sum(politika$mask), 0L)
})

test_that("birincil BILINMIYORKEN tek bir sifir eslesme bile genisletmeye izin vermez", {
  env <- .pk_policy_env()
  veri <- .pk_policy_data()

  # "X projesinin 2024 harcamalari" bicimindeki istek: proje adi yanlis
  # yazilmis olabilir ve sifir eslesir, yil filtresi ise satir tutar. Birincil
  # varlik metadata'da beyan edilmediginden HANGI daraltmanin sorunun OZNESI
  # oldugu bilinemez; proje kriterini "ikincil" sayip dusurmek, kullaniciya
  # bulunamayan projenin yerine TUM 2024 kayitlarinin ozetini verir.
  filtreler <- list(
    list(column = "ProjeAdi", value = "HIC OLMAYAN PROJE", operation = "exact_match"),
    list(column = "Durum", value = "Aktif", operation = "exact_match")
  )
  derleme <- env$pk_filter_compile(veri, filtreler)
  politika <- env$pk_filter_zero_match_policy(veri, filtreler, derleme, NULL)

  expect_null(politika$primary_column)
  expect_identical(politika$action, "refuse")
  expect_equal(sum(politika$mask), 0L)
})

test_that("D4: birincil BILINIYORKEN ikincil dusurme davranisi korunur", {
  env <- .pk_policy_env()
  veri <- .pk_policy_data()

  # Mesru ikincil-dusurme yolu kaybolmamalidir: metadata birincil varligi
  # beyan ettiginde, birincil eslesiyorken sifir eslesen IKINCIL sutun
  # dusurulur, ifsa edilir ve analiz surer.
  # STUB YOK: ortam `R/helpers_pk_query_meta_access.R` dosyasini ZATEN source
  # eder ve uretim erisimcisi kullanilir; stub, gercek metadata cozumlemesindeki
  # bir gerilemeyi bu testten GIZLERDI.
  sorgu <- list(meta = list(primary_entity = "ProjeAdi"))

  filtreler <- list(
    list(column = "ProjeAdi", value = "SENTETIK ALFA", operation = "exact_match"),
    list(column = "Durum", value = "HIC OLMAYAN DURUM", operation = "exact_match")
  )
  derleme <- env$pk_filter_compile(veri, filtreler)
  politika <- env$pk_filter_zero_match_policy(veri, filtreler, derleme, sorgu)

  expect_identical(politika$primary_column, "ProjeAdi")
  expect_identical(politika$action, "dropped_secondary")
  expect_identical(politika$dropped_columns, "Durum")
  expect_equal(sum(politika$mask), 1L)
})

test_that("DUSURULEN birincil/tek filtre analizi durdurur", {
  env <- .pk_policy_env()
  veri <- .pk_policy_data()

  # Derleyici yapragi hic uygulayamadiginda (bilinmeyen islem, cevrilemeyen
  # deger, olmayan sutun) grup listesine HIC girmez. Eskiden bu durumda sifir
  # eslesen grup bulunmadigi icin politika "proceed" diyor ve tumu-TRUE maske
  # ile TUM yetkili kume analiz ediliyordu.
  filtreler <- list(
    list(column = "ProjeAdi", value = "SENTETIK ALFA", operation = "between")
  )
  derleme <- env$pk_filter_compile(veri, filtreler)
  politika <- env$pk_filter_zero_match_policy(veri, filtreler, derleme, NULL)

  expect_identical(politika$action, "refuse")
  expect_true(nzchar(politika$refusal_message))
  expect_true(grepl("uygulanamad", politika$refusal_message))
})

# AYNI MANTIK GRUBUNDAKI ESLESEN IKINCIL KRITER de grup cikarildiginda DUSER.
# Ifsa listesi yalnizca SIFIR eslesen sutunlari sayarken kullanici, yil
# kapsamli bir soruya TUM yillar uzerinden verilmis yaniti uyarisiz okuyordu.
test_that("grup cikarma yan hasari da ifsa edilir", {
  veri <- data.frame(
    ProjeAdi = c("ANKA", "ANKA", "AKINCI"),
    Yil = c(2024L, 2023L, 2024L),
    Durum = c("A", "B", "A"),
    stringsAsFactors = FALSE
  )

  # URETIM ALAN ADI `value`DIR (PR #705 incelemesi, P3):
  # `pk_filter_normalize_leaf()` `f$value` okur ve `values` yalnizca R'nin
  # `$` KISMI AD eslesmesiyle cozuluyordu. `value` onekli ikinci bir alan
  # eklenirse eslesme BELIRSIZ olur, `f$value` `NULL` doner ve yapraklar BOS
  # deger kumesine indirgenir; asagidaki iddialar ALAKASIZ bir nedenle duser.
  filtreler <- list(
    list(column = "ProjeAdi", operation = "equals", value = "ANKA"),
    list(operator = "and", children = list(
      list(column = "Yil", operation = "equals", value = 2024L),
      list(column = "Durum", operation = "equals", value = "YOK")
    ))
  )

  env <- .pk_policy_env()
  sorgu <- list(meta = list(primary_entity = "ProjeAdi"))
  derleme <- env$pk_filter_compile(veri, filtreler, query = sorgu)
  politika <- env$pk_filter_zero_match_policy(veri, filtreler, derleme, query = sorgu)

  expect_equal(politika$action, "dropped_secondary")
  # Sifir eslesen sutun ZATEN raporlaniyordu; asil kayip `Yil` idi.
  expect_true("Durum" %in% politika$dropped_columns)
  expect_true("Yil" %in% politika$dropped_columns)
  expect_true(any(grepl("Yil", politika$disclosures, fixed = TRUE)))
})

# ------------------------------------------------------------------------------
# DERİNLİK AŞIMI / DEĞERLENDİRİLEMEYEN MANTIK GRUBU (`__group__`)
# ------------------------------------------------------------------------------

test_that("dusurulen `__group__` gecerli bir filtre YANINDA da analizi REDDEDER", {
  env <- .pk_policy_env()
  veri <- .pk_policy_data()

  # Derinlik asimi / desteklenmeyen birlestirici / bos grup, sentetik
  # `__group__` adiyla dusurulur. Metadata BIRINCIL sutunu UYGULANAN yapraktan
  # cikarabildiginde 0b kapisi calismiyor; `__group__` gercek bir sutun adi
  # olmadigi icin 0c kapisi da calismiyordu. Sonuc: kullanicinin istedigi grup
  # SESSIZCE atiliyor ve analiz yalnizca ILGISIZ kalan filtreyle suruyordu.
  # FİKSTÜR GERÇEK DERLEYİCİ ŞEKLİNDEN ÜRETİLİR: elle yazılan `applied` /
  # `zero_match` alanları üretimin döndürdüğü şekil DEĞİLDİR (`pk_filter_compile()`
  # `mask`/`groups`/`dropped`/`noop_columns`/`ok`/`requested`/`all_dropped`
  # döndürür). Politika bu yüzden SIFIR uygulanan grup görüyor ve
  # `groups` güdümlü dallardaki bir gerileme SAPTANMADAN kalıyordu. Derleme
  # gerçek işlevle yapılır, `__group__` düşme kaydı SONRADAN enjekte edilir.
  filtreler <- list(list(column = "Durum", value = "Aktif",
                         operation = "exact_match"))
  derlenmis <- env$pk_filter_compile(veri, filtreler, query = NULL)
  derlenmis$dropped <- c(
    derlenmis$dropped,
    list(list(leaf = list(column = "__group__"), reason = "depth_overflow"))
  )

  karar <- env$pk_filter_zero_match_policy(
    veri, filtreler, derlenmis,
    query = list(id = "q-grup", meta = list(primary_entity = "Durum"))
  )

  expect_identical(karar$action, "refuse")
  expect_true(nzchar(as.character(karar$refusal_message)[1]))
  expect_true(all(karar$mask == FALSE))
  # Sentetik ad kullaniciya SIZMAZ.
  expect_false(grepl("__group__", as.character(karar$refusal_message)[1], fixed = TRUE))
})

test_that("`__group__` YOKSA gecerli filtre yolunda davranis DEGISMEZ", {
  env <- .pk_policy_env()
  veri <- .pk_policy_data()

  # GİRDİ GERÇEK DERLEYİCİYLE ÜRETİLİR.
  #
  # Elle yazılan `applied`/`zero_match` alanları ÜRETİM ŞEKLİ DEĞİLDİR ve
  # `groups` alanı hiç yoktu; `pk_filter_zero_match_policy()` o zaman
  # `groups`-siz bir girdi değerlendiriyor, `groups` güdümlü dallar
  # gerilese bile `proceed` sonucu ayakta kalıyordu. Komşu test (yukarıda)
  # gerçek sözleşmenin `mask`/`groups`/`dropped`/`noop_columns`/`ok`/
  # `requested`/`all_dropped` olduğunu belgeliyor.
  filtreler <- list(list(column = "Durum", value = "Aktif", operation = "exact_match"))
  derlenmis <- env$pk_filter_compile(veri, filtreler)
  expect_true(isTRUE(derlenmis$ok))
  expect_false(isTRUE(derlenmis$all_dropped))

  karar <- env$pk_filter_zero_match_policy(
    veri,
    filtreler,
    derlenmis,
    query = list(id = "q-grup", meta = list(primary_entity = "Durum"))
  )

  expect_identical(karar$action, "proceed")
  expect_identical(karar$mask, derlenmis$mask)
})

test_that("BEYAN EDILEN birincil sutun UYGULANMADIYSA sifir eslesme REDDEDER", {
  env <- .pk_policy_env()
  veri <- .pk_policy_data()

  # Metadata `ProjeAdi`yi birincil sayar; istek YALNIZCA `Durum` uzerinde
  # daraltir ve o daraltma sifir eslesir. Onceden hicbir kapi calismiyor,
  # kurtarma derlemesi TUMU-TRUE maske uretiyordu.
  filtreler <- list(
    list(column = "Durum", value = "HIC OLMAYAN DURUM", operation = "exact_match")
  )
  derlenmis <- env$pk_filter_compile(
    veri, filtreler,
    query = list(id = "q-birincil-yok", meta = list(primary_entity = "ProjeAdi"))
  )

  karar <- env$pk_filter_zero_match_policy(
    veri, filtreler, derlenmis,
    query = list(id = "q-birincil-yok", meta = list(primary_entity = "ProjeAdi"))
  )

  expect_identical(karar$action, "refuse")
  expect_identical(sum(karar$mask), 0L)
  expect_true(nzchar(as.character(karar$refusal_message)[1]))
})

test_that("KURTARMA geriye daraltma birakmiyorsa karar REDDIR", {
  env <- .pk_policy_env()
  veri <- .pk_policy_data()

  # Tek daraltma sifir eslesiyor ve birincil varlik ayni sutun DEGIL:
  # `kalan` bos kalir, `pk_filter_compile(data, list(), ...)` TUMU-TRUE maske
  # dondururdu. Kapali basarisiz karar REDdir.
  filtreler <- list(
    list(column = "Durum", value = "HIC OLMAYAN DURUM", operation = "exact_match")
  )
  derlenmis <- env$pk_filter_compile(veri, filtreler, query = NULL)

  karar <- env$pk_filter_zero_match_policy(veri, filtreler, derlenmis, query = NULL)

  expect_identical(karar$action, "refuse")
  expect_false(any(karar$mask))
})

test_that("COK DEGERLI grup operatoru sessizce ilk ogeye INDIRGENMEZ", {
  env <- .pk_policy_env()

  # Model `{"operator": ["or","and"], ...}` uretirse `[1]` kirpmasi eskiden
  # ifadeyi sessizce OR yapiyordu; belirsiz beyan artik `NA` doner.
  expect_true(is.na(env$.pk_filter_group_operator(list(operator = c("or", "and")))))
  expect_identical(env$.pk_filter_group_operator(list(operator = "or")), "or")
  expect_identical(env$.pk_filter_group_operator(list()), "and")
})

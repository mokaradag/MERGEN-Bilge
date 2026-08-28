# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-filter-compile-behavior.R
# Açıklama: D1 / D2 / D3 — sütun içinde VEYA, sütunlar arasında VE, tamamlayıcı
#           aralık sınırlarının VE kalması, çok değerli filtreler ve Türkçe
#           katlamalı karşılaştırma. Tümü çevrimdışı ve deterministiktir:
#           gerçek DB, LLM, tarayıcı, SSO, ağ veya gerçek sır KULLANILMAZ.
#           Fixture'lar sentetiktir; gerçek proje/program adı geçmez.
# ==============================================================================

.pk_compile_env <- function() {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  # ÜRETİM OPERATÖRÜYLE AYNI (`R/utils_common.R`): yalnız `NULL` yedeğe düşer.
  env$`%||%` <- function(x, y) if (is.null(x)) y else x
  source(file.path(repo_root, "R", "helpers_pk_text_turkish.R"),
         encoding = "UTF-8", local = env)
  source(file.path(repo_root, "R", "helpers_pk_filter_compile.R"),
         encoding = "UTF-8", local = env)
  source(file.path(repo_root, "R", "helpers_pk_filter_group.R"),
         encoding = "UTF-8", local = env)
  env
}

# Aciklama satirlari taranmaz; yalnizca kod taranir.
.pk_compile_code_only <- function(rel_path) {
  full <- file.path(resolve_repo_root_for_tests(), rel_path)
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
  if (is.na(txt)) return("")
  satirlar <- strsplit(enc2utf8(txt), "\n", fixed = TRUE)[[1]]
  satirlar <- satirlar[!grepl("^\\s*#", satirlar, perl = TRUE, useBytes = TRUE)]
  paste(satirlar, collapse = "\n")
}

# Sentetik veri: gerçek hiçbir proje/program adı içermez.
.pk_compile_data <- function() {
  data.frame(
    ProjeAdi = c(
      "SENTETIK RADAR MODERNIZASYON",
      "SENTETIK ELEKTRONIK HARP MODERNIZASYON",
      "SENTETIK LOJISTIK DESTEK",
      "İSTANBUL SENTETİK KALIP",
      "SENTETIK KALIP HATTI"
    ),
    Durum = c("Aktif", "Aktif", "Pasif", "Aktif", "Pasif"),
    Butce = c(100, 250, 50, 400, 700),
    Baslangic = as.Date(c("2024-03-01", "2024-07-15", "2023-05-10",
                          "2025-01-20", "2024-12-31")),
    stringsAsFactors = FALSE
  )
}

test_that("D1: AYNI sutundaki alternatifler VEYA'yi ACIK olarak ister", {
  env <- .pk_compile_env()
  veri <- .pk_compile_data()

  # VEYA anlami ARTIK CIKARSANMAZ: "ayni sutuna iki yuklem geldi" gozleminden
  # VEYA uretmek, kullanicinin "hem X hem Y iceren" istegini sessizce
  # genisletir. Beyansiz iki yaprak VE'lenir ve burada hicbir satir tutmaz.
  ortulu <- env$pk_filter_compile(veri, list(
    list(column = "ProjeAdi", value = "RADAR", operation = "contains"),
    list(column = "ProjeAdi", value = "ELEKTRONIK HARP", operation = "contains")
  ))
  expect_equal(sum(ortulu$mask), 0L)

  # 1) ACIK yol: tek yaprak, COK DEGERLI (D2). Bu, dogal ve tercih edilen
  #    VEYA ifadesidir; degerler zaten yaprak icinde birlesir.
  cok_degerli <- env$pk_filter_compile(veri, list(
    list(column = "ProjeAdi", value = c("RADAR", "ELEKTRONIK HARP"),
         operation = "contains")
  ))
  sonuc <- veri[cok_degerli$mask, , drop = FALSE]
  expect_equal(nrow(sonuc), 2L)
  expect_setequal(
    sonuc$ProjeAdi,
    c("SENTETIK RADAR MODERNIZASYON", "SENTETIK ELEKTRONIK HARP MODERNIZASYON")
  )

  # 2) ACIK yol: yapraklar `logic = "or"` beyan eder.
  beyanli <- env$pk_filter_compile(veri, list(
    list(column = "ProjeAdi", value = "RADAR", operation = "contains", logic = "or"),
    list(column = "ProjeAdi", value = "ELEKTRONIK HARP", operation = "contains", logic = "or")
  ))
  expect_equal(sum(beyanli$mask), 2L)
})

test_that("P0: model uretimi filtre metni R kodu olarak CALISTIRILAMAZ", {
  env <- .pk_compile_env()
  veri <- .pk_compile_data()

  # Filtre degerleri LLM uretimidir. Derleyici bunlari YALNIZCA veri olarak
  # karsilastirir; hicbir yolda parse()/eval() yoktur. Yan etkili bir ifade
  # yalnizca eslesmeyen bir METIN olarak ele alinir.
  isaret <- new.env(parent = emptyenv())
  isaret$calisti <- FALSE
  assign("pk_test_rce_kanit", function() isaret$calisti <<- TRUE, envir = globalenv())
  on.exit(rm("pk_test_rce_kanit", envir = globalenv()), add = TRUE)

  zararli <- env$pk_filter_compile(veri, list(
    list(column = "ProjeAdi", value = "pk_test_rce_kanit()", operation = "exact_match")
  ))

  expect_false(isaret$calisti)
  expect_equal(sum(zararli$mask), 0L)

  # Ayni sey acik mantik gruplarinin icinde de gecerlidir.
  grup <- env$pk_filter_compile(veri, list(
    list(operator = "or", children = list(
      list(column = "ProjeAdi", value = "pk_test_rce_kanit()", operation = "contains"),
      list(column = "Durum", value = "system('true')", operation = "exact_match")
    ))
  ))
  expect_false(isaret$calisti)
  expect_equal(sum(grup$mask), 0L)
})

test_that("acik mantik gruplari VE/VEYA'yi veri olarak temsil eder", {
  env <- .pk_compile_env()
  veri <- .pk_compile_data()

  # (Durum == 'Pasif') VEYA (Butce >= 400) -> 3 satir (Pasif x2, 400'luk kayit)
  grup <- env$pk_filter_compile(veri, list(
    list(operator = "or", children = list(
      list(column = "Durum", value = "Pasif", operation = "exact_match"),
      list(column = "Butce", value = "400", operation = "greater_or_equal")
    ))
  ))
  expect_equal(sum(grup$mask), 3L)

  # Grup + duz yaprak birlikte VE'lenir: yukaridaki VEYA ile Durum == 'Aktif'
  # kesisimi yalnizca 400 butceli aktif kaydi birakir.
  karma <- env$pk_filter_compile(veri, list(
    list(operator = "or", children = list(
      list(column = "Durum", value = "Pasif", operation = "exact_match"),
      list(column = "Butce", value = "400", operation = "greater_or_equal")
    )),
    list(column = "Durum", value = "Aktif", operation = "exact_match")
  ))
  expect_equal(sum(karma$mask), 1L)
})

test_that("bilinmeyen islem SESSIZCE esitlige dusurulmez", {
  env <- .pk_compile_env()
  veri <- .pk_compile_data()

  derleme <- env$pk_filter_compile(veri, list(
    list(column = "Butce", value = "100", operation = "between")
  ))

  # Eski davranista `between` -> "alternative" -> `%in%` idi ve 100'e ESIT
  # satiri dondururdu; kullanici aralik isterken esitlik uygulaniyordu.
  expect_equal(length(derleme$dropped), 1L)
  expect_true(grepl("desteklenmeyen", derleme$dropped[[1]]$reason))
  expect_true(isTRUE(derleme$all_dropped))
  expect_equal(sum(derleme$mask), 5L)
})

test_that("cevrilemeyen deger yapragi DUSURUR, kismi uygulanmaz", {
  env <- .pk_compile_env()
  veri <- .pk_compile_data()

  # Cok degerli sayisal filtrede tek bir gecersiz deger bile yapragi dusurur;
  # eskiden gecersiz deger sessizce atilip kalan alt kume uygulaniyordu.
  sayisal <- env$pk_filter_compile(veri, list(
    list(column = "Butce", value = c("100", "yuksek"), operation = "in")
  ))
  expect_equal(length(sayisal$dropped), 1L)
  expect_equal(sum(sayisal$mask), 5L)

  tarih <- env$pk_filter_compile(veri, list(
    list(column = "Baslangic", value = "gecen ay", operation = "greater_than")
  ))
  expect_equal(length(tarih$dropped), 1L)
})

test_that("mantiksal sutunda tanimsiz deger FALSE'a cevrilmez", {
  env <- .pk_compile_env()
  veri <- .pk_compile_data()
  veri$Onayli <- c(TRUE, TRUE, FALSE, TRUE, FALSE)

  gecerli <- env$pk_filter_compile(veri, list(
    list(column = "Onayli", value = "evet", operation = "exact_match")
  ))
  expect_equal(sum(gecerli$mask), 3L)

  # "belirsiz" sozlukte yok: eskiden FALSE olarak yorumlanip onaysiz kayitlar
  # donuyordu. Artik yaprak dusurulur.
  gecersiz <- env$pk_filter_compile(veri, list(
    list(column = "Onayli", value = "belirsiz", operation = "exact_match")
  ))
  expect_equal(length(gecersiz$dropped), 1L)
  expect_true(isTRUE(gecersiz$all_dropped))
})

test_that("POSIXct filtresinde gun ici saat KORUNUR", {
  env <- .pk_compile_env()
  veri <- data.frame(
    Kayit = c("a", "b", "c"),
    Zaman = as.POSIXct(c("2024-05-01 00:30:00", "2024-05-01 23:45:00",
                         "2024-05-02 08:00:00"), tz = "UTC"),
    stringsAsFactors = FALSE
  )

  # Yalniz-tarih ust sinir GUN SONU olarak yorumlanir: 1 Mayis'in tamami girer.
  ust <- env$pk_filter_compile(veri, list(
    list(column = "Zaman", value = "2024-05-01", operation = "less_or_equal")
  ))
  expect_equal(sum(ust$mask), 2L)

  # Saat iceren sinir tam olarak uygulanir; as.Date()'e yuvarlanmaz.
  saatli <- env$pk_filter_compile(veri, list(
    list(column = "Zaman", value = "2024-05-01 12:00:00", operation = "greater_than")
  ))
  expect_equal(sum(saatli$mask), 2L)
})

test_that("metadata filterable kapisi derleyicide uygulanir", {
  env <- .pk_compile_env()
  veri <- .pk_compile_data()

  env$pk_meta_is_filterable <- function(query, column) {
    isTRUE(query$meta$column_meta[[column]]$filterable)
  }

  sorgu <- list(meta = list(column_meta = list(
    Durum = list(role = "dimension", filterable = TRUE),
    Butce = list(role = "measure", filterable = FALSE)
  )))

  acik <- env$pk_filter_compile(veri, list(
    list(column = "Durum", value = "Aktif", operation = "exact_match")
  ), query = sorgu)
  expect_equal(sum(acik$mask), 3L)

  kapali <- env$pk_filter_compile(veri, list(
    list(column = "Butce", value = "100", operation = "greater_than")
  ), query = sorgu)
  expect_equal(length(kapali$dropped), 1L)
  expect_true(grepl("filtrelenebilir", kapali$dropped[[1]]$reason))
})

test_that("D1: FARKLI sutunlar arasinda VE korunur", {
  env <- .pk_compile_env()
  veri <- .pk_compile_data()

  filtreler <- list(
    list(column = "ProjeAdi", value = "MODERNIZASYON", operation = "contains"),
    list(column = "Durum", value = "Aktif", operation = "exact_match")
  )

  derleme <- env$pk_filter_compile(veri, filtreler)
  sonuc <- veri[derleme$mask, , drop = FALSE]

  expect_equal(nrow(sonuc), 2L)
  expect_true(all(sonuc$Durum == "Aktif"))
})

test_that("D1: tamamlayici aralik sinirlari ayni sutunda VE kalir", {
  env <- .pk_compile_env()
  veri <- .pk_compile_data()

  filtreler <- list(
    list(column = "Baslangic", value = "2024-01-01", operation = "greater_or_equal"),
    list(column = "Baslangic", value = "2024-12-31", operation = "less_or_equal")
  )

  derleme <- env$pk_filter_compile(veri, filtreler)
  sonuc <- veri[derleme$mask, , drop = FALSE]

  # VEYA'lansaydi neredeyse evrensel bir predikat olur ve 5 satir donerdi.
  expect_equal(nrow(sonuc), 3L)
  expect_true(all(sonuc$Baslangic >= as.Date("2024-01-01")))
  expect_true(all(sonuc$Baslangic <= as.Date("2024-12-31")))

  # Sayisal sinirlar icin de ayni sozlesme gecerlidir.
  sayisal <- env$pk_filter_compile(veri, list(
    list(column = "Butce", value = "100", operation = "greater_or_equal"),
    list(column = "Butce", value = "400", operation = "less_or_equal")
  ))
  expect_equal(sum(sayisal$mask), 3L)
})

test_that("D2: cok degerli filtreler kirpilmadan uygulanir", {
  env <- .pk_compile_env()
  veri <- .pk_compile_data()

  # Karakter vektoru
  vektor <- env$pk_filter_compile(veri, list(
    list(column = "Durum", value = c("Aktif", "Pasif"), operation = "exact_match")
  ))
  expect_equal(sum(vektor$mask), 5L)

  # Liste (LLM'in yaygin JSON dizisi bicimi)
  liste <- env$pk_filter_compile(veri, list(
    list(column = "ProjeAdi",
         value = list("SENTETIK LOJISTIK DESTEK", "SENTETIK KALIP HATTI"),
         operation = "exact_match")
  ))
  # v1'de as.character(val)[1] nedeniyle yalnizca ILK deger uygulanirdi.
  expect_equal(sum(liste$mask), 2L)

  yaprak <- env$pk_filter_normalize_leaf(
    list(column = "A", value = list("x", "y", "z"), operation = "in")
  )
  expect_identical(yaprak$values, c("x", "y", "z"))
})

test_that("D3: karsilastirma Turkce katlamayla yapilir, ignore.case ile degil", {
  env <- .pk_compile_env()
  veri <- .pk_compile_data()

  # grepl("^istanbul...", "İSTANBUL...", ignore.case = TRUE) FALSE dondurur;
  # Turkce katlama ile TRUE olmalidir.
  turkce <- env$pk_filter_compile(veri, list(
    list(column = "ProjeAdi", value = "istanbul sentetik kalıp",
         operation = "exact_match")
  ))
  expect_equal(sum(turkce$mask), 1L)

  # "KALIP" Turkce kurallarla "kalıp" olur; ASCII "kalip" ile ESLESMEZ.
  kalip <- env$pk_filter_compile(veri, list(
    list(column = "ProjeAdi", value = "kalıp", operation = "contains")
  ))
  expect_equal(sum(kalip$mask), 2L)
})

test_that("dislama ve gecersiz yapraklar dogru ele alinir", {
  env <- .pk_compile_env()
  veri <- .pk_compile_data()

  dislama <- env$pk_filter_compile(veri, list(
    list(column = "Durum", value = "Pasif", operation = "not_equals")
  ))
  expect_equal(sum(dislama$mask), 3L)

  gecersiz <- env$pk_filter_compile(veri, list(
    list(column = "OlmayanSutun", value = "x", operation = "exact_match"),
    list(column = "", value = "y", operation = "exact_match"),
    list(column = "Butce", value = "sayi-degil", operation = "greater_than")
  ))
  # Hicbiri uygulanmadi -> maske degismedi, hepsi DUSURULDU olarak raporlandi.
  expect_equal(sum(gecersiz$mask), 5L)
  expect_equal(length(gecersiz$dropped), 3L)
})

test_that("etkisiz (no-op) filtre raporlanir", {
  env <- .pk_compile_env()
  veri <- .pk_compile_data()

  # Bes satirin dordunu koruyan (0.8) filtre 0.5 esiginin uzerindedir.
  dort_bes <- list(list(column = "ProjeAdi", value = "SENTETIK LOJISTIK DESTEK",
                        operation = "not_equals"))

  derleme <- env$pk_filter_compile(veri, dort_bes, noop_ratio = 0.5)
  expect_true("ProjeAdi" %in% derleme$noop_columns)

  # Ayni filtre 0.95 esiginde etkisiz SAYILMAZ.
  sika <- env$pk_filter_compile(veri, dort_bes, noop_ratio = 0.95)
  expect_length(sika$noop_columns, 0L)
})

test_that("sifir eslesen sutun grubu isaretlenir ve koken kaydi uretilir", {
  env <- .pk_compile_env()
  veri <- .pk_compile_data()

  derleme <- env$pk_filter_compile(veri, list(
    list(column = "ProjeAdi", value = "HIC OLMAYAN DEGER", operation = "exact_match")
  ))

  expect_equal(length(derleme$groups), 1L)
  expect_true(isTRUE(derleme$groups[[1]]$zero_match))
  expect_equal(derleme$groups[[1]]$rows_before, 5L)
  expect_equal(derleme$groups[[1]]$rows_after, 0L)
})

test_that("bos filtre listesi ve bos veri guvenli davranir", {
  env <- .pk_compile_env()
  veri <- .pk_compile_data()

  bos <- env$pk_filter_compile(veri, list())
  expect_true(all(bos$mask))

  bos_veri <- env$pk_filter_compile(veri[0, , drop = FALSE], list(
    list(column = "Durum", value = "Aktif", operation = "exact_match")
  ))
  expect_length(bos_veri$mask, 0L)
})

test_that("Turkce katlama otoritesi yoksa derleyici KAPALI BASARISIZ olur", {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = baseenv())
  # ÜRETİM OPERATÖRÜYLE AYNI (`R/utils_common.R`): yalnız `NULL` yedeğe düşer.
  env$`%||%` <- function(x, y) if (is.null(x)) y else x
  env$exists <- function(...) FALSE
  source(file.path(repo_root, "R", "helpers_pk_filter_compile.R"),
         encoding = "UTF-8", local = env)
  source(file.path(repo_root, "R", "helpers_pk_filter_group.R"),
         encoding = "UTF-8", local = env)

  # pk_tr_fold yoksa SESSIZCE tolower()'a DUSULMEZ; hata yukselir (D3).
  expect_error(
    env$.pk_filter_fold("ABC"),
    "pk_tr_fold",
    fixed = TRUE
  )
})

test_that("ayristirilamayan tarih degeri HATA yukseltmez, yaprak dusurulur", {
  env <- .pk_compile_env()
  veri <- .pk_compile_data()

  # `as.Date("gecen ay")` UYARI degil HATA yukseltir; suppressWarnings() tek
  # basina yetmez. Filtre degerleri LLM uretimidir ve bu bicimde bir metin
  # kolayca gelir. Korumasiz halde hata apply_smart_filters() uzerinden disari
  # sizar ve analiz, yapragi gerekcesiyle dusurmek yerine ham R hatasiyla coker.
  yaprak <- env$pk_filter_normalize_leaf(
    list(column = "Baslangic", operation = "greater_than", value = "gecen ay")
  )

  sonuc <- env$pk_filter_leaf_mask(veri, yaprak)
  expect_false(
    isTRUE(sonuc$ok),
    info = "Cozulemeyen tarih degeri gecerli bir maske uretmemelidir."
  )
  expect_true(
    is.character(sonuc$reason) && nzchar(sonuc$reason),
    info = "Dusurulen yaprak gerekcesini tasimalidir."
  )

  derleme <- env$pk_filter_compile(
    veri,
    list(list(column = "Baslangic", operation = "greater_than", value = "gecen ay"))
  )
  expect_identical(
    sum(derleme$mask), nrow(veri),
    info = "Dusurulen tarih filtresi satirlari kesmemelidir."
  )
  expect_true(
    length(derleme$dropped) == 1L,
    info = "Cozulemeyen tarih filtresi tam olarak bir dusurme kaydi uretmelidir."
  )

  # Ayristirilabilir deger yolu DEGISMEZ.
  gecerli <- env$pk_filter_compile(
    veri,
    list(list(column = "Baslangic", operation = "greater_or_equal", value = "2024-07-01"))
  )
  expect_identical(sum(gecerli$mask), 3L)
})

test_that("D3: islem adi YERELDEN BAGIMSIZ kucuk harfe indirilir", {
  env <- .pk_compile_env()
  veri <- .pk_compile_data()

  # Turkce Windows yerel ayarinda `tolower("CONTAINS")` noktasiz `contaıns`
  # uretir; islem hicbir listeyle eslesmez ve ALT DIZGE aramasi fark edilmeden
  # TAM ESLESMEYE duser. Buyuk harfli islem adi LLM ciktisi icin siradan bir
  # varyasyondur, dolayisiyla bu sessizce yanlis (cogunlukla bos) sonuc demektir
  # ve bu dosyanin duzelttigi D3 kusurunun ta kendisidir.
  buyuk <- env$pk_filter_normalize_leaf(
    list(column = "ProjeAdi", value = "RADAR", operation = "CONTAINS")
  )
  expect_identical(buyuk$operation, "contains")

  derleme <- env$pk_filter_compile(
    veri, list(list(column = "ProjeAdi", value = "RADAR", operation = "CONTAINS"))
  )
  expect_equal(sum(derleme$mask), 1L)
  expect_length(derleme$dropped, 0L)

  # Diger I iceren islem adlari da ayni yolu izler.
  for (cift in list(c("STARTS_WITH", "starts_with"), c("NOT_IN", "not_in"),
                    c("IN", "in"), c("MIN", "min"))) {
    yaprak <- env$pk_filter_normalize_leaf(
      list(column = "Butce", value = "100", operation = cift[1])
    )
    expect_identical(yaprak$operation, cift[2], info = cift[1])
  }

  # Kaynak duzeyi muhafiz: yerel bagimli `tolower()` geri gelirse bu iddia
  # duser. Katlama yalnizca ASCII A-Z ile sinirli oldugundan chartr dogrudur.
  kaynak <- .pk_compile_code_only("R/helpers_pk_filter_compile.R")
  expect_false(
    grepl("tolower(", kaynak, fixed = TRUE, useBytes = TRUE),
    info = "Yerel bagimli tolower() derleyiciye geri getirilmemelidir."
  )
})

test_that("POSIXt sutununda YALNIZ-TARIH esitligi GUN duzeyinde eslesir", {
  env <- .pk_compile_env()
  # GERİLEME KORUMASI: gün genişletmesi yalnızca kapsayıcı ÜST SINIR için
  # çalışıyordu; eşitlik/üyelik sınırı yerel `00:00:00`da kalıyor ve SADECE
  # gece yarısı kayıtları eşleşiyordu. Yaprak düşmediği için kullanıcıya
  # hiçbir ifşa gitmiyordu.
  veri <- data.frame(
    Zaman = as.POSIXct(c("2026-05-01 00:00:00", "2026-05-01 13:45:00",
                         "2026-05-02 09:00:00"), tz = "UTC"),
    stringsAsFactors = FALSE
  )

  for (op in c("exact_match", "equals", "in")) {
    yaprak <- env$pk_filter_normalize_leaf(
      # ALAN ADI ÜRETİM SÖZLEŞMESİDİR: `pk_filter_normalize_leaf()` `f$value`
      # okur. `values` yalnızca `$` KISMİ EŞLEŞMESİ sayesinde çalışıyordu;
      # `value` ile başlayan ikinci bir alan eklendiğinde eşleşme belirsizleşir,
      # `$value` `NULL` döner ve yaprak sessizce BOŞ değer kümesine normalize
      # olurdu.
      list(column = "Zaman", value = "2026-05-01", operation = op)
    )
    sonuc <- env$pk_filter_leaf_mask(veri, yaprak)
    expect_true(isTRUE(sonuc$ok), info = op)
    expect_identical(sonuc$mask, c(TRUE, TRUE, FALSE), info = op)
  }

  # Dışlama aynı maskeyi kullanır (tersleme üst katmanda yapılır).
  yaprak_haric <- env$pk_filter_normalize_leaf(
    list(column = "Zaman", value = "2026-05-01", operation = "not_equals")
  )
  expect_identical(env$pk_filter_leaf_mask(veri, yaprak_haric)$mask,
                   c(TRUE, TRUE, FALSE))

  # SAAT TAŞIYAN değer AN düzeyinde karşılaştırılmaya devam eder.
  yaprak_an <- env$pk_filter_normalize_leaf(
    list(column = "Zaman", value = "2026-05-01 13:45:00", operation = "equals")
  )
  expect_identical(env$pk_filter_leaf_mask(veri, yaprak_an)$mask,
                   c(FALSE, TRUE, FALSE))
})

test_that("integer64 uyeligi BIT DESENI degil DEGER karsilastirir", {
  skip_if_not_installed("bit64")
  env <- .pk_compile_env()

  # GERİLEME KORUMASI: taban `%in%` integer64 altındaki DOUBLE bit desenini
  # eşleştirir; bit deseni `NaN` çözülen iki FARKLI BIGINT aynı sayılırdı.
  a <- bit64::as.integer64("9218868437227405313")
  b <- bit64::as.integer64("9218868437227405314")
  expect_false(identical(as.character(a), as.character(b)))

  veri <- data.frame(Kimlik = c(a, b))
  yaprak <- env$pk_filter_normalize_leaf(
    list(column = "Kimlik", value = as.character(a), operation = "equals")
  )
  sonuc <- env$pk_filter_leaf_mask(veri, yaprak)
  expect_true(isTRUE(sonuc$ok))
  expect_identical(sonuc$mask, c(TRUE, FALSE))
})

test_that("TANINMAYAN `logic` belirteci SESSIZCE `and` olmaz", {
  env <- .pk_compile_env()
  veri <- .pk_compile_data()

  # GERİLEME: `PK_FILTER_OR_TOKENS` dışındaki HER belirteç `and`e eşleniyordu.
  # `.pk_filter_group_operator()` ise aynı belirteci `NA` sayıp grubu AÇIK bir
  # bildirimle reddeder. Model `logic = "veyaa"` yazdığında aynı sütundaki iki
  # `contains` yaprağı KESİŞİM üretiyor (çoğu zaman sıfır satır) ve hiçbir
  # yaprak düşürülmediği için kullanıcıya HİÇBİR bildirim gitmiyordu.
  for (belirtec in c("veyaa", "xor", "nand")) {
    sonuc <- env$pk_filter_compile(veri, list(
      list(column = "ProjeAdi", value = "RADAR", operation = "contains",
           logic = belirtec)
    ))
    expect_true(length(sonuc$dropped) > 0L, info = belirtec)
    nedenler <- vapply(sonuc$dropped, function(d) as.character(d$reason)[1], character(1))
    expect_true(any(grepl("birlestirme", nedenler, fixed = TRUE)), info = belirtec)
  }

  # BİLİNEN belirteçler ve BEYANSIZ yapraklar davranışı DEĞİŞMEZ.
  for (belirtec in c("or", "veya", "and", "ve")) {
    sonuc <- env$pk_filter_compile(veri, list(
      list(column = "ProjeAdi", value = "RADAR", operation = "contains",
           logic = belirtec)
    ))
    expect_equal(length(sonuc$dropped), 0L, info = belirtec)
  }

  beyansiz <- env$pk_filter_compile(veri, list(
    list(column = "ProjeAdi", value = "RADAR", operation = "contains")
  ))
  expect_equal(length(beyansiz$dropped), 0L)
})

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
  env$`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L) y else x
  for (f in c("helpers_pk_text_turkish.R", "helpers_pk_query_meta_schema.R",
              "helpers_pk_query_meta_access.R", "helpers_pk_provenance.R",
              "helpers_pk_filter_compile.R", "helpers_pk_filter_policy.R",
              "helpers_pk_analysis_filters_v2.R")) {
    source(file.path(repo_root, "R", f), encoding = "UTF-8", local = env)
  }
  env
}

.pk_policy_read_bytes <- function(rel_path) {
  full <- file.path(resolve_repo_root_for_tests(), rel_path)
  size <- suppressWarnings(file.info(full)$size[1])
  if (is.na(size) || size <= 0) return("")
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

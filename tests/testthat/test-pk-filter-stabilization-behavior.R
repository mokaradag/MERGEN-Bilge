# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-filter-stabilization-behavior.R
# Açıklama: PR #705 kararlılık düzeltmeleri — filtre hattı.
#
#           Kapsanan dört kök neden:
#             1. Doğrulayıcı `{operator, children}` grup düğümlerini eliyordu;
#                model üretimi VEYA dalı derleyiciye HİÇ ulaşmıyordu.
#             2. Durum kısayolu çok değerli (`["Aktif","Beklemede"]`) yaprakta
#                skaler `if` üzerinde HATA yükseltiyor, geçerli yanıt `error`
#                durumuna düşüyordu.
#             3. Genel olarak tanınan ama sütun TÜRÜNDE uygulanamayan bir
#                işlem (metin sütununda `greater_than`) SESSİZCE eşitliğe
#                dönüyordu.
#             4. Sıfır eşleşme kurtarma derlemesi `query` metadata'sını
#                düşürüyor, ilk derlemenin reddettiği filtre kapıdan geçiyordu.
#
#           Tümü çevrimdışı ve deterministiktir: gerçek DB, LLM, tarayıcı,
#           SSO, ağ veya gerçek sır KULLANILMAZ. Fixture'lar sentetiktir.
# ==============================================================================

.pk_stab_compile_env <- function() {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  # ÜRETİM OPERATÖRÜYLE AYNI (`R/utils_common.R`): yalnız `NULL` yedeğe düşer.
  env$`%||%` <- function(x, y) if (is.null(x)) y else x
  for (f in c("helpers_pk_text_turkish.R", "helpers_pk_query_meta_schema.R",
              "helpers_pk_query_meta_access.R", "helpers_pk_provenance.R",
              "helpers_pk_filter_compile.R", "helpers_pk_filter_group.R",
              "helpers_pk_filter_policy.R")) {
    source(file.path(repo_root, "R", f), encoding = "UTF-8", local = env)
  }
  env
}

# Çıkarıcı (`extract_filter_criteria_from_prompt`) izole edilir: LLM çağrısı ve
# sütun özeti STUB'lanır, böylece doğrulama/normalleştirme mantığı ağ olmadan
# sınanır.
.pk_stab_extract_env <- function(model_json) {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  # ÜRETİM OPERATÖRÜYLE AYNI (`R/utils_common.R`): yalnız `NULL` yedeğe düşer.
  env$`%||%` <- function(x, y) if (is.null(x)) y else x
  source(file.path(repo_root, "R", "helpers_pk_filter_group.R"),
         encoding = "UTF-8", local = env)
  source(file.path(repo_root, "R", "helpers_pk_analysis_filters_base.R"),
         encoding = "UTF-8", local = env)
  env$summarize_columns_for_ai <- function(...) "SENTETIK SUTUN OZETI"
  env$call_local_llm <- function(...) list(content = model_json)
  # Gercek model adi/uc noktasi/anahtar KULLANILMAZ; yalnizca yapilandirma
  # sekli ve sahte bir yer tutucu.
  env$api_config <- list(local_models = c("sentetik-test-model"))
  env$resolve_local_llm_credentials <- function(...) {
    list(endpoint = "http://sentetik.local/v1", api_key = "SENTETIK-YER-TUTUCU")
  }
  env
}

.pk_stab_data <- function() {
  data.frame(
    ProjeAdi = c("SENTETIK ALFA", "SENTETIK BETA", "SENTETIK GAMA"),
    Durum    = c("Aktif", "Beklemede", "Kapali"),
    Butce    = c(100, 200, 300),
    Etkin    = c(TRUE, FALSE, TRUE),
    stringsAsFactors = FALSE
  )
}

test_that("tur/islem uyumsuzlugu sessizce esitlige donmez, yaprak dusurulur", {
  env <- .pk_stab_compile_env()
  veri <- .pk_stab_data()

  # KUSUR: metin sutununda `greater_than` son `%in%` dalina duser ve istek
  # sessizce "== SENTETIK BETA" olurdu. Yuklem anlami degistirilmez; yaprak
  # dusurulur ve gerekcesi ifsa edilir.
  for (islem in c("greater_than", "greater_or_equal", "from", "min",
                  "less_than", "less_or_equal", "to", "max")) {
    yaprak <- env$pk_filter_normalize_leaf(
      list(column = "ProjeAdi", value = "SENTETIK BETA", operation = islem)
    )
    sonuc <- env$pk_filter_leaf_mask(veri, yaprak)
    expect_false(isTRUE(sonuc$ok), info = islem)
    expect_true(is.null(sonuc$mask), info = islem)
    expect_true(grepl("uygulanamaz", sonuc$reason, fixed = TRUE), info = islem)
  }

  # Mantiksal sutunda metinsel islem de ayni sekilde dusurulur.
  for (islem in c("contains", "not_contains", "starts_with")) {
    yaprak <- env$pk_filter_normalize_leaf(
      list(column = "Etkin", value = "true", operation = islem)
    )
    sonuc <- env$pk_filter_leaf_mask(veri, yaprak)
    expect_false(isTRUE(sonuc$ok), info = islem)
  }
})

test_that("uyumlu tur/islem ciftleri DEGISMEDEN calisir", {
  env <- .pk_stab_compile_env()
  veri <- .pk_stab_data()

  # Sayisal sutunda aralik: korunur.
  sayisal <- env$pk_filter_leaf_mask(veri, env$pk_filter_normalize_leaf(
    list(column = "Butce", value = "150", operation = "greater_than")
  ))
  expect_true(sayisal$ok)
  expect_identical(sayisal$mask, c(FALSE, TRUE, TRUE))

  # Metin sutununda esitlik/icerme: korunur.
  esit <- env$pk_filter_leaf_mask(veri, env$pk_filter_normalize_leaf(
    list(column = "ProjeAdi", value = "SENTETIK BETA", operation = "exact_match")
  ))
  expect_true(esit$ok)
  expect_identical(esit$mask, c(FALSE, TRUE, FALSE))

  icerir <- env$pk_filter_leaf_mask(veri, env$pk_filter_normalize_leaf(
    list(column = "ProjeAdi", value = "GAMA", operation = "contains")
  ))
  expect_true(icerir$ok)
  expect_identical(icerir$mask, c(FALSE, FALSE, TRUE))

  # Mantiksal sutunda esitlik: korunur.
  mantik <- env$pk_filter_leaf_mask(veri, env$pk_filter_normalize_leaf(
    list(column = "Etkin", value = "true", operation = "exact_match")
  ))
  expect_true(mantik$ok)
  expect_identical(mantik$mask, c(TRUE, FALSE, TRUE))
})

test_that("dogrulayici yapisal grup dugumlerini korur", {
  # KUSUR: yalnizca yaprak kurali uygulaniyordu; her `{operator, children}`
  # dugumu derleyiciye ULASMADAN eleniyordu.
  json <- paste0(
    '{"filters":[{"operator":"or","children":[',
    '{"column":"ProjeAdi","value":"SENTETIK ALFA","operation":"exact_match"},',
    '{"column":"ProjeAdi","value":"SENTETIK GAMA","operation":"exact_match"}',
    ']}],"aggregation":"list","group_column":null}'
  )
  env <- .pk_stab_extract_env(json)

  sonuc <- env$extract_filter_criteria_from_prompt(
    user_prompt = "alfa veya gama",
    data_context = .pk_stab_data(),
    available_columns = names(.pk_stab_data()),
    conn = NULL
  )

  expect_identical(sonuc$status, "ok_filtered")
  expect_length(sonuc$filters, 1L)
  expect_false(is.null(sonuc$filters[[1]]$children))
  expect_length(sonuc$filters[[1]]$children, 2L)

  # Korunan dugum derleyicide GERCEKTEN degerlendirilir.
  cenv <- .pk_stab_compile_env()
  grup <- cenv$.pk_filter_eval_group(.pk_stab_data(), sonuc$filters[[1]])
  expect_identical(grup$mask, c(TRUE, FALSE, TRUE))
})

test_that("cocuksuz grup dugumu gecerli sayilmaz", {
  json <- '{"filters":[{"operator":"or","children":[]}],"aggregation":"list"}'
  env <- .pk_stab_extract_env(json)
  sonuc <- env$extract_filter_criteria_from_prompt(
    "bos grup", .pk_stab_data(), names(.pk_stab_data()), NULL
  )
  expect_identical(sonuc$status, "malformed")
})

test_that("cok degerli durum filtresi hata yerine derleyiciye ulasir", {
  # KUSUR: `as.character(list("Aktif","Beklemede"))` uzunlugu 2 olan bir vektor
  # uretir; skaler `if` bunun uzerinde HATA yukseltir ve dis tryCatch gecerli
  # yaniti `error` durumuna cevirirdi.
  json <- paste0(
    '{"filters":[{"column":"Durum","value":["Aktif","Beklemede"],',
    '"operation":"in"}],"aggregation":"list","group_column":null}'
  )
  env <- .pk_stab_extract_env(json)

  sonuc <- env$extract_filter_criteria_from_prompt(
    "aktif veya beklemede", .pk_stab_data(), names(.pk_stab_data()), NULL
  )

  expect_identical(sonuc$status, "ok_filtered")
  expect_length(sonuc$filters, 1L)
  # Degerler DEGISTIRILMEDEN korunur: tek "1"/"0" atamasi cok degerli VEYA
  # isteginin anlamini bozardi.
  expect_identical(
    as.character(unlist(sonuc$filters[[1]]$value, use.names = FALSE)),
    c("Aktif", "Beklemede")
  )

  cenv <- .pk_stab_compile_env()
  derleme <- cenv$pk_filter_compile(.pk_stab_data(), sonuc$filters)
  expect_identical(derleme$mask, c(TRUE, TRUE, FALSE))
})

test_that("durum kisayolu YALNIZCA ikili sutunda uygulanir", {
  # `Durum` bu VERI KUMESINDE 0/1 kodludur: `evet` -> `1` yeniden yazimi
  # yalnizca boyle bir sutunda anlamlidir.
  ikili_veri <- data.frame(
    ProjeAdi = c("SENTETIK ALFA", "SENTETIK BETA"),
    Durum    = c(1, 0),
    stringsAsFactors = FALSE
  )
  json <- paste0(
    '{"filters":[{"column":"Durum","value":"evet","operation":"exact_match"}],',
    '"aggregation":"list"}'
  )
  env <- .pk_stab_extract_env(json)
  sonuc <- env$extract_filter_criteria_from_prompt(
    "aktif olanlar", ikili_veri, names(ikili_veri), NULL
  )
  expect_identical(sonuc$status, "ok_filtered")
  expect_identical(as.character(sonuc$filters[[1]]$value), "1")
  expect_identical(sonuc$filters[[1]]$operation, "exact_match")
})

test_that("METIN durum sutununda etiket degeri YENIDEN YAZILMAZ", {
  # `Durum` metin sutunudur ve `Aktif`/`Beklemede`/`Kapali` etiketlerini saklar.
  # Kosulsuz `-> "1"` yeniden yazimi tam eslesmeyi SIFIR satira dusururdu:
  # model dogru etiketi yazmis olsa bile hicbir kayit tutulmazdi.
  json <- paste0(
    '{"filters":[{"column":"Durum","value":"Aktif","operation":"exact_match"}],',
    '"aggregation":"list"}'
  )
  env <- .pk_stab_extract_env(json)
  sonuc <- env$extract_filter_criteria_from_prompt(
    "aktif olanlar", .pk_stab_data(), names(.pk_stab_data()), NULL
  )
  expect_identical(sonuc$status, "ok_filtered")
  expect_identical(as.character(sonuc$filters[[1]]$value), "Aktif")

  cenv <- .pk_stab_compile_env()
  derleme <- cenv$pk_filter_compile(.pk_stab_data(), sonuc$filters)
  expect_identical(derleme$mask, c(TRUE, FALSE, FALSE))
})

test_that("kurtarma derlemesi metadata kapisini ZAYIFLATMAZ", {
  env <- .pk_stab_compile_env()
  veri <- .pk_stab_data()

  # `Durum` metadata tarafindan filtrelenebilir DEGIL; `ProjeAdi` birincil
  # varlik. `ProjeAdi` eslesir, ikincil `Butce` sifir eslesir ve dusurulur.
  sorgu <- list(meta = list(
    primary_entity = "ProjeAdi",
    column_meta = list(
      ProjeAdi = list(filterable = TRUE),
      Butce    = list(filterable = TRUE),
      Durum    = list(filterable = FALSE)
    )
  ))

  filtreler <- list(
    list(column = "ProjeAdi", value = "SENTETIK ALFA", operation = "exact_match"),
    list(column = "Butce",    value = "9999",          operation = "exact_match"),
    # AYIRT EDICI DEGER: `"Aktif"` satir 1'de birincil eslesmeyle BIRLIKTE
    # bulunur; kapi kaldirilsa bile maske ayni cikardi ve iddia HICBIR SEY
    # kanitlamazdi. `"Kapali"` yalnizca satir 3'tedir: kapi kaldirilirsa
    # birincil eslesmeyle KESISIM BOSALIR ve maske degisir.
    list(column = "Durum",    value = "Kapali",        operation = "exact_match")
  )

  derleme <- env$pk_filter_compile(veri, filtreler, query = sorgu)
  politika <- env$pk_filter_zero_match_policy(veri, filtreler, derleme, query = sorgu)

  # Ikincil sifir eslesme dusurulur ve analiz surer.
  expect_identical(politika$action, "dropped_secondary")

  # KUSUR: kurtarma derlemesi `query = NULL` ile yapiliyordu; metadata
  # tarafindan ENGELLENMIS `Durum` filtresi bu kez kapidan gecerdi. Metadata
  # kapisi korundugunda `Durum` UYGULANMAZ ve maske YALNIZCA birincil
  # filtreden gelir: satir 1. Kapi dusurulseydi `Durum == "Kapali"` satir 3'u
  # secer, birincil ile kesisim BOSALIR ve maske `c(FALSE, FALSE, FALSE)`
  # olurdu; yani bu iddia artik iki davranisi AYIRT EDER.
  expect_false(is.null(politika$mask))
  expect_identical(politika$mask, c(TRUE, FALSE, FALSE))

  # Kaynak duzeyi muhafiz: `query` yeniden dusurulurse bu iddia duser.
  kaynak <- readLines(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_pk_filter_policy.R"),
    warn = FALSE, encoding = "UTF-8"
  )
  expect_true(
    any(grepl("pk_filter_compile(data, kalan, query = query)", kaynak, fixed = TRUE)),
    info = "Kurtarma derlemesi ayni sorgu metadata'si ile yapilmalidir."
  )
})

# ---------------------------------------------------------------------------
# integer64 (bigint) filtre kesinliği
# ---------------------------------------------------------------------------

test_that("bigint filtre degeri 2^53'te YUVARLANMAZ", {
  skip_if_not_installed("bit64")

  kok <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  source(file.path(kok, "R", "helpers_pk_precision.R"), encoding = "UTF-8", local = env)

  # GERİLEME: `is.numeric()` `integer64` için TRUE döner; `as.numeric(val_str)`
  # 2^53 üstündeki iki KOMŞU tam sayıyı AYNI double'a yuvarlıyordu. Filtre o
  # zaman yanlış satırı tutuyor ya da hiç satır tutmuyordu.
  sutun <- bit64::as.integer64(c("9007199254740993", "9007199254740994"))

  operand <- env$pk_filter_numeric_operand(sutun, "9007199254740993")
  expect_true(isTRUE(operand$ok))
  expect_true(inherits(operand$value, "integer64"))
  expect_identical(sum(sutun == operand$value), 1L)

  # Komsu deger AYRI satiri secer (double yolunda ikisi de eslesirdi).
  operand2 <- env$pk_filter_numeric_operand(sutun, "9007199254740994")
  expect_identical(sum(sutun == operand2$value), 1L)
  expect_false(identical(operand$value, operand2$value))
})

test_that("bigint sutununda TAM SAYI OLMAYAN deger yapragi DUSURUR", {
  skip_if_not_installed("bit64")

  kok <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  source(file.path(kok, "R", "helpers_pk_precision.R"), encoding = "UTF-8", local = env)

  sutun <- bit64::as.integer64(c("1", "2"))
  for (ham in c("1.5", "abc", "")) {
    expect_false(isTRUE(env$pk_filter_numeric_operand(sutun, ham)$ok), info = ham)
  }
})

test_that("siradan sayisal sutun davranisi DEGISMEZ", {
  kok <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  source(file.path(kok, "R", "helpers_pk_precision.R"), encoding = "UTF-8", local = env)

  operand <- env$pk_filter_numeric_operand(c(1.5, 2.5), "1.5")
  expect_true(isTRUE(operand$ok))
  expect_identical(operand$value, 1.5)

  expect_false(isTRUE(env$pk_filter_numeric_operand(c(1, 2), "abc")$ok))
})

# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-export-xlsx-behavior.R
# Açıklama: Faz 2 — Excel/CSV dışa aktarımı (§5.9) ve yanıt kompozisyonu (§5.8).
#
#           Kanıtlanan sözleşmeler:
#             * yerel tipler korunur (sayısal sayısal, Türkçe metin bozulmadan),
#             * yazıcıya özgü yüzde sözleşmesi — `writexl` tabanı 61,3'ü
#               `Tamamlanma (%)` başlığı altında SAYISAL saklar; hiçbir yol
#               %6130,0 üretemez,
#             * `Bilgi` sayfasında RLS ÖNCESİ satır sayısı BULUNMAZ,
#               `bilge_yolac_downloads` KULLANILMAZ,
#             * parça tavanı aşılırsa AÇIK RET; sessiz kırpma YOK,
#             * doğrulama başarısızsa CSV yedeği; karakter formül benzeri
#               değerler etkisizleştirilir ama sayısal -125,50 SAYI kalır,
#             * meşru mükerrer satırlar korunur.
#
#           `readxl` yalnızca SAKLANAN DEĞERİ kanıtlar, render edilen stili
#           değil. Gerçek Excel görünümü VM kapısıdır.
#
#           Tümü ÇEVRİMDIŞI: gerçek DB, LLM, tarayıcı, SSO, ağ veya gerçek sır
#           KULLANILMAZ; fixture'lar sentetiktir.
# ==============================================================================

.pk_export_env <- function() {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(x, y) if (is.null(x)) y else x
  env$safe_unlink_if_exists <- function(path) {
    if (!is.null(path) && is.character(path) && length(path) == 1L &&
        !is.na(path) && nzchar(path) && file.exists(path)) {
      try(unlink(path, force = TRUE), silent = TRUE)
    }
    invisible(TRUE)
  }

  for (dosya in c("helpers_pk_config.R", "helpers_pk_text_turkish.R",
                  "helpers_pk_precision.R", "helpers_pk_packet_stats.R", "helpers_pk_packet_context_facts.R", "helpers_pk_packet_keys.R", "helpers_pk_analysis_packet.R",
                  "helpers_pk_packet_render.R", "helpers_pk_export_plan.R",
                  "helpers_pk_export_csv.R", "helpers_pk_export_xlsx.R",
                  "helpers_pk_export_serve.R",
                  "helpers_pk_answer_compose.R")) {
    source(file.path(repo_root, "R", dosya), encoding = "UTF-8", local = env)
  }
  env
}

.pk_export_code_only <- function(rel_path) {
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

.pk_export_query <- function() {
  list(id = "q_sentetik", name = "Sentetik Sorgu", meta = list(column_meta = list(
    TamamlanmaYuzde = list(label = "Tamamlanma", role = "measure", unit = "%",
                           decimals = 1L, percent_scale = "points", additive = FALSE),
    Tutar = list(label = "Tutar", role = "measure", unit = "TL", decimals = 2L,
                 additive = TRUE),
    ProjeAdi = list(label = "Proje Adı", role = "dimension")
  )))
}

.pk_export_data <- function(n = 20L) {
  data.frame(
    ProjeAdi = rep(c("SENTETIK ÇALIŞMA İSTANBUL", "SENTETIK ÖLÇÜM"), length.out = n),
    TamamlanmaYuzde = rep(c(61.3, 20.0), length.out = n),
    Tutar = rep(c(-125.50, 1000.25), length.out = n),
    Not = rep(c("-KAPALI-", "=1+1", "normal metin", "@kullanici", "duz"),
              length.out = n),
    stringsAsFactors = FALSE
  )
}

.pk_export_dir <- function() {
  yol <- file.path(tempdir(), paste0("pk_export_test_", as.integer(runif(1, 1, 1e9))))
  dir.create(yol, recursive = TRUE, showWarnings = FALSE)
  yol
}

# --- Parca plani ve ACIK RET --------------------------------------------------

test_that("Sinirin altindaki sonuc tek parcada aktarilir", {
  env <- .pk_export_env()
  plan <- env$pk_export_plan(data.frame(A = seq_len(500)), max_rows = 1000L)

  expect_identical(plan$status, "ok")
  expect_length(plan$parts, 1L)
  expect_identical(plan$parts[[1]]$sheet, "Veri")
  expect_equal(plan$total_rows, 500L)
})

test_that("Sinirin ustundeki sonuc DOGRULANABILIR numarali parcalara bolunur", {
  env <- .pk_export_env()
  plan <- env$pk_export_plan(data.frame(A = seq_len(2500)), max_rows = 1000L)

  expect_identical(plan$status, "ok")
  expect_length(plan$parts, 3L)
  expect_identical(vapply(plan$parts, function(p) p$sheet, character(1)),
                   c("Veri_001", "Veri_002", "Veri_003"))
  # Her satir TAM OLARAK bir kez gorunur.
  hepsi <- unlist(lapply(plan$parts, function(p) p$ordinals))
  expect_identical(sort(hepsi), seq_len(2500L))
  expect_equal(anyDuplicated(hepsi), 0L)
})

test_that("Parca tavani asilirsa dosya SESSIZCE KIRPILMAZ; ACIKCA reddedilir", {
  env <- .pk_export_env()
  plan <- env$pk_export_plan(data.frame(A = seq_len(10000)), max_rows = 1000L,
                             max_parts = 3L)

  expect_identical(plan$status, "refuse")
  expect_length(plan$parts, 0L)
  expect_true(grepl("daraltın", plan$message, fixed = TRUE))
  expect_true(grepl("SESSİZCE KIRPILMADI", plan$message, fixed = TRUE))
})

test_that("Sayfa adi Excel kurallarina indirgenir; Turkce karakter KORUNUR", {
  env <- .pk_export_env()
  expect_identical(env$pk_export_sheet_name("Proje/Kaynak: Özet*"), "Proje Kaynak Özet")
  expect_true(nchar(env$pk_export_sheet_name(strrep("a", 60), 2L)) <= 31L)
  expect_identical(env$pk_export_sheet_name("Veri", 7L), "Veri_007")
})

# --- Yuzde sozlesmesi (YAZICIYA OZGU) -----------------------------------------

test_that("writexl tabani: yuzde-puan SAYISAL saklanir, baslik '(%)' tasir", {
  env <- .pk_export_env()
  hazir <- env$pk_export_prepare_percent(.pk_export_data(4L),
                                         .pk_export_query()$meta, formatted = FALSE)

  expect_equal(hazir$data$TamamlanmaYuzde[1], 61.3)
  expect_true("Tamamlanma (%)" %in% hazir$headers)
  expect_true("TamamlanmaYuzde" %in% hazir$percent_columns)
})

test_that("openxlsx yolu: kesir saklanir ve baslikta '(%)' bulunmaz", {
  env <- .pk_export_env()
  hazir <- env$pk_export_prepare_percent(.pk_export_data(4L),
                                         .pk_export_query()$meta, formatted = TRUE)

  expect_equal(hazir$data$TamamlanmaYuzde[1], 0.613)
  expect_true("Tamamlanma" %in% hazir$headers)
  expect_false("Tamamlanma (%)" %in% hazir$headers)
})

test_that("percent_scale = fraction her iki yolda da dogru olceklenir", {
  env <- .pk_export_env()
  meta <- list(column_meta = list(
    Oran = list(label = "Oran", role = "measure", unit = "%", decimals = 1L,
                percent_scale = "fraction")
  ))
  veri <- data.frame(Oran = 0.613)

  taban <- env$pk_export_prepare_percent(veri, meta, formatted = FALSE)
  expect_equal(taban$data$Oran[1], 61.3)

  bicimli <- env$pk_export_prepare_percent(veri, meta, formatted = TRUE)
  expect_equal(bicimli$data$Oran[1], 0.613)
})

test_that("percent_scale beyan edilmemisse deger OLCEKLENMEZ ve durum ifsa edilir", {
  env <- .pk_export_env()
  meta <- list(column_meta = list(
    Oran = list(label = "Oran", role = "measure", unit = "%", decimals = 1L)
  ))

  hazir <- env$pk_export_prepare_percent(data.frame(Oran = 61.3), meta, formatted = TRUE)
  expect_equal(hazir$data$Oran[1], 61.3)
  expect_length(hazir$percent_columns, 0L)
  expect_true(any(grepl("percent_scale", hazir$notes, fixed = TRUE)))
})

test_that("Hicbir yol %6130 buyuklugunde bir deger URETEMEZ", {
  env <- .pk_export_env()
  meta <- .pk_export_query()$meta

  for (bicimli in c(FALSE, TRUE)) {
    hazir <- env$pk_export_prepare_percent(.pk_export_data(2L), meta, formatted = bicimli)
    goruntulenen <- if (bicimli) hazir$data$TamamlanmaYuzde * 100 else hazir$data$TamamlanmaYuzde
    expect_true(all(goruntulenen <= 100),
                info = sprintf("formatted=%s icin gosterilen yuzde 100'u asti.", bicimli))
  }
})

# --- Gercek dosya yazimi ve dogrulama -----------------------------------------

test_that("5.000 satirlik sonuc dogru bir XLSX uretir ve geri okunur", {
  skip_if_not_installed("writexl")
  skip_if_not_installed("readxl")

  env <- .pk_export_env()
  veri <- .pk_export_data(5000L)
  q <- .pk_export_query()
  paket <- env$pk_packet_build(veri, q, list(authorized_rows = 5000L, filtered_rows = 5000L))

  # SATIR TAVANI SABİTLENİR: `MERGEN_PK_EXPORT_MAX_ROWS` `.Renviron` ile
  # ayarlanabilir. Dağıtım kabuğu 5000'in ALTINDA bir değer verirse dışa
  # aktarım parçalanır, tek dosya/"Veri" sayfası iddiaları üretim doğru olduğu
  # hâlde kırılır.
  testthat::skip_if_not_installed("withr")
  artefakt <- withr::with_envvar(
    # BAYT VE PARÇA TAVANLARI DA SABİTLENİR: `pk_export_build()` yalnızca satır
    # tavanında değil, BAYT tavanı aşıldığında da CSV yoluna düşer. Yapılandırılmış
    # bir VM/CI kabuğu küçük bir `MERGEN_PK_EXPORT_MAX_BYTES_MB` dışa aktarırsa
    # 5000 satırlık fikstür `csv_fallback` döner ve ÜRETİM DOĞRU olduğu hâlde
    # aşağıdaki iddia kırılırdı (satır anahtarı için ZATEN belgelenen gerekçe).
    list(MERGEN_PK_EXPORT_MAX_ROWS = NA_character_,
         MERGEN_PK_EXPORT_MAX_BYTES_MB = NA_character_,
         MERGEN_PK_EXPORT_MAX_PARTS = NA_character_),
    env$pk_export_build(
      veri, paket,
      context = list(query_id = "q_sentetik", query_name = "Sentetik Sorgu",
                     authorized_rows = 5000L, filtered_rows = 5000L),
      base_name = "sentetik", dir = .pk_export_dir(), query = q
    )
  )

  expect_identical(artefakt$status, "ok")
  expect_length(artefakt$files, 1L)
  expect_equal(artefakt$total_rows, 5000L)

  yol <- artefakt$files[[1]]$path
  expect_true(file.exists(yol))

  sayfalar <- readxl::excel_sheets(yol)
  expect_true(all(c("Veri", "Ozet", "Bilgi") %in% sayfalar))

  okunan <- as.data.frame(readxl::read_excel(yol, sheet = "Veri"))
  expect_equal(nrow(okunan), 5000L)

  # inceleme bulgusu: BEYAN EDILEN BIRIM basliga tasinir; aksi halde veri
  # sayfasi "saat mi gun mu TL mi" sorusunu yanitlayamiyordu.
  expect_true("Tutar (TL)" %in% names(okunan))
  # Yerel tipler: sayisal sayisal kalir, as.character()'a cevrilmez.
  expect_true(is.numeric(okunan[["Tutar (TL)"]]))
  expect_equal(okunan[["Tutar (TL)"]][1], -125.50)
  bicimli <- env$.pk_export_openxlsx_available()
  yuzde_basligi <- if (bicimli) "Tamamlanma" else "Tamamlanma (%)"
  expect_true(is.numeric(okunan[[yuzde_basligi]]))
  expect_equal(okunan[[yuzde_basligi]][1], if (bicimli) 0.613 else 61.3)

  # Turkce metin bozulmadan gidip gelir.
  expect_true(any(grepl("SENTETIK ÇALIŞMA İSTANBUL", okunan[["Proje Adı"]], fixed = TRUE)))
})

test_that("Bilgi sayfasi RLS ONCESI satir sayisini ICERMEZ", {
  skip_if_not_installed("writexl")
  skip_if_not_installed("readxl")

  env <- .pk_export_env()
  veri <- .pk_export_data(10L)
  q <- .pk_export_query()

  artefakt <- env$pk_export_build(
    veri, env$pk_packet_build(veri, q, list(authorized_rows = 120L, filtered_rows = 10L)),
    context = list(query_id = "q_sentetik", query_name = "Sentetik Sorgu",
                   authorized_rows = 120L, filtered_rows = 10L,
                   # Cagiran kazara gecirse bile Bilgi sayfasina YAZILMAZ.
                   pre_rls_rows = 41930L),
    base_name = "sentetik", dir = .pk_export_dir(), query = q
  )

  bilgi <- as.data.frame(readxl::read_excel(artefakt$files[[1]]$path, sheet = "Bilgi"))
  metin <- paste(unlist(bilgi), collapse = " ")

  expect_true(grepl("120", metin, fixed = TRUE))
  expect_false(grepl("41930", metin, fixed = TRUE))
  expect_true(any(bilgi$Alan == "Yetkiniz Dahilindeki Satir"))
  expect_false(any(grepl("RLS oncesi", bilgi$Alan, fixed = TRUE)))
})

test_that("Cok parcali aktarimda her satir TAM OLARAK bir kez yazilir", {
  testthat::skip_if_not_installed("withr")
  skip_if_not_installed("writexl")
  skip_if_not_installed("readxl")

  env <- .pk_export_env()
  veri <- data.frame(Sira = seq_len(250), Ad = paste0("SENTETIK_", seq_len(250)),
                     stringsAsFactors = FALSE)

  # `MERGEN_PK_EXPORT_MAX_PARTS` DE SABITLENIR (PR #705 incelemesi, P3):
  # yapilandirilabilir bir anahtardir ve dagitim/CI kabugu `2` verirse
  # 250/100 plani 3 parca ister, plan `refused` doner ve uretim dogru oldugu
  # halde test kirilirdi.
  withr::with_envvar(list(MERGEN_PK_EXPORT_MAX_ROWS = "100",
                          MERGEN_PK_EXPORT_MAX_PARTS = NA_character_), {
    artefakt <- env$pk_export_build(
      veri, list(facts = list()),
      context = list(query_id = "q_sentetik", authorized_rows = 250L, filtered_rows = 250L),
      base_name = "sentetik", dir = .pk_export_dir()
    )

    expect_identical(artefakt$status, "ok")
    yol <- artefakt$files[[1]]$path
    sayfalar <- readxl::excel_sheets(yol)
    expect_true(all(c("Veri_001", "Veri_002", "Veri_003") %in% sayfalar))

    hepsi <- do.call(rbind, lapply(c("Veri_001", "Veri_002", "Veri_003"), function(s) {
      as.data.frame(readxl::read_excel(yol, sheet = s))
    }))
    expect_equal(nrow(hepsi), 250L)
    expect_equal(sort(hepsi$Sira), seq_len(250L))
  })
})

test_that("Parca tavani asilirsa dosya URETILMEZ ve ret mesaji doner", {
  testthat::skip_if_not_installed("withr")
  env <- .pk_export_env()
  withr::with_envvar(list(MERGEN_PK_EXPORT_MAX_ROWS = "10",
                          MERGEN_PK_EXPORT_MAX_PARTS = "2"), {
    artefakt <- env$pk_export_build(
      data.frame(A = seq_len(100)), list(facts = list()), list(),
      base_name = "sentetik", dir = .pk_export_dir()
    )

    expect_identical(artefakt$status, "refused")
    expect_length(artefakt$files, 0L)
    expect_true(grepl("daraltın", artefakt$message, fixed = TRUE))
  })
})

test_that("MESRU MUKERRER satirlar korunur; tekillestirme YAPILMAZ", {
  skip_if_not_installed("writexl")
  skip_if_not_installed("readxl")

  env <- .pk_export_env()
  veri <- data.frame(Ad = rep("AYNI SATIR", 8L), Deger = rep(5, 8L),
                     stringsAsFactors = FALSE)

  artefakt <- env$pk_export_build(veri, list(facts = list()), list(),
                                  base_name = "sentetik", dir = .pk_export_dir())

  expect_identical(artefakt$status, "ok")
  okunan <- as.data.frame(readxl::read_excel(artefakt$files[[1]]$path, sheet = "Veri"))
  expect_equal(nrow(okunan), 8L)
})

test_that("Coklu-kume dogrulamasi mukerrerleri korur ama eksik satiri YAKALAR", {
  env <- .pk_export_env()
  kaynak <- data.frame(A = c("x", "x", "y"), B = c(1, 1, 2), stringsAsFactors = FALSE)

  expect_true(env$pk_export_verify_multiset(kaynak, kaynak)$ok)

  eksik <- kaynak[1:2, , drop = FALSE]
  expect_false(env$pk_export_verify_multiset(kaynak, eksik)$ok)

  # Ayni satir sayisi ama farkli icerik: yakalanmalidir.
  bozuk <- kaynak
  bozuk$B[3] <- 999
  expect_false(env$pk_export_verify_multiset(kaynak, bozuk)$ok)

  # Mukerrer satirlarin BIRI kaybolup baskasi eklenirse de yakalanir.
  degistirilmis <- data.frame(A = c("x", "y", "y"), B = c(1, 2, 2),
                              stringsAsFactors = FALSE)
  expect_false(env$pk_export_verify_multiset(kaynak, degistirilmis)$ok)
})

# --- CSV yedegi ve formul etkisizlestirme -------------------------------------

test_that("CSV yedeginde KARAKTER formul benzeri degerler etkisizlestirilir", {
  env <- .pk_export_env()
  veri <- data.frame(
    Not = c("-KAPALI-", "=1+1", "+ek", "@kullanici", "normal metin", "Türkçe ölçüm"),
    Tutar = c(-125.50, 1000, -1, 2, 3, 4),
    stringsAsFactors = FALSE
  )

  temiz <- env$pk_export_neutralize_csv(veri)

  expect_identical(temiz$Not[1], "'-KAPALI-")
  expect_identical(temiz$Not[2], "'=1+1")
  expect_identical(temiz$Not[3], "'+ek")
  expect_identical(temiz$Not[4], "'@kullanici")
  # Sıradan Türkçe metne DOKUNULMAZ.
  expect_identical(temiz$Not[5], "normal metin")
  expect_identical(temiz$Not[6], "Türkçe ölçüm")

  # MESRU SAYISAL negatif tutar SAYI kalir.
  expect_true(is.numeric(temiz$Tutar))
  expect_equal(temiz$Tutar[1], -125.50)
})

test_that("Dogrulama basarisiz olursa XLSX SUNULMAZ; BOM'lu CSV yedegine dusulur", {
  skip_if_not_installed("writexl")

  env <- .pk_export_env()
  # Dogrulamayi bilerek basarisiz kilariz: gercek yazim yolu degismez.
  env$pk_export_verify_file <- function(path, plan, sheets) {
    list(ok = FALSE, reason = "sentetik dogrulama hatasi")
  }

  veri <- data.frame(Not = c("=1+1", "duz"), Tutar = c(-125.50, 5),
                     stringsAsFactors = FALSE)
  artefakt <- env$pk_export_build(veri, list(facts = list()), list(),
                                  base_name = "sentetik", dir = .pk_export_dir())

  expect_identical(artefakt$status, "csv_fallback")
  # inceleme bulgusu: yedek yalnizca ham veri parcasini degil, XLSX'teki
  # `Ozet`/`Bilgi` denetim baglamini da yan dosya olarak yazar; aksi halde
  # indirilen/paylasilan CSV hangi populasyonu ve filtreleri temsil ettigini
  # kaybediyordu.
  expect_length(artefakt$files, 3L)
  expect_true(any(grepl("_Ozet_", vapply(artefakt$files, function(f) f$name, character(1)),
                        fixed = TRUE)))
  expect_true(any(grepl("_Bilgi_", vapply(artefakt$files, function(f) f$name, character(1)),
                        fixed = TRUE)))
  expect_identical(artefakt$files[[1]]$format, "csv")
  expect_true(grepl("CSV", artefakt$message, fixed = TRUE))

  yol <- artefakt$files[[1]]$path
  expect_true(file.exists(yol))
  # Dogrulanmayan XLSX diskte BIRAKILMAZ.
  expect_length(list.files(dirname(yol), pattern = "\\.xlsx$"), 0L)

  bayt <- readBin(yol, "raw", 3L)
  expect_identical(bayt, as.raw(c(0xEF, 0xBB, 0xBF)))

  icerik <- paste(readLines(yol, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  expect_true(grepl("'=1+1", icerik, fixed = TRUE))
  expect_true(grepl("-125.5", icerik, fixed = TRUE))
})

# --- Guvenlik: global indirme dizini KULLANILMAZ ------------------------------

test_that("Disa aktarim bilge_yolac_downloads altina YAZMAZ", {
  for (dosya in c("R/helpers_pk_export_xlsx.R", "R/helpers_pk_export_serve.R",
                  "R/helpers_pk_export_plan.R",
                  "R/helpers_pk_analysis_result.R")) {
    kod <- .pk_export_code_only(dosya)
    expect_false(grepl("bilge_yolac_downloads", kod, fixed = TRUE, useBytes = TRUE),
                 info = sprintf("%s global indirme dizinini kullanmamalidir.", dosya))
    expect_false(grepl("addResourcePath", kod, fixed = TRUE, useBytes = TRUE),
                 info = sprintf("%s global kaynak yolu kaydetmemelidir.", dosya))
  }

  # Sunma/temizleme katmani AYRI dosyadadir (helpers_pk_export_serve.R); uretim
  # katmani Shiny oturumuna DOKUNMAZ.
  kod <- .pk_export_code_only("R/helpers_pk_export_serve.R")
  expect_true(grepl("registerDataObj", kod, fixed = TRUE, useBytes = TRUE))
  # inceleme bulgusu: `register_session_cleanup_on_end()` oturum basina
  # YALNIZCA BIR KEZ kayit kabul eder ve sonraki extra_cleanup listelerini
  # eklemez; disa aktarim temizligi bu yuzden hic calismayabiliyordu. Yollar
  # artik oturum defterine yazilir ve defteri bosaltan TEK bir geri cagri
  # kaydedilir.
  expect_true(grepl("onSessionEnded", kod, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("pk_export_cleanup_paths", kod, fixed = TRUE, useBytes = TRUE))
  # Indirme dosyayi BELLEGE ALMADAN akitir.
  expect_true(grepl("list(file = data$path", kod, fixed = TRUE, useBytes = TRUE))
})

test_that("Sunum oturum kapsamlidir ve oturum bitiminde temizlik kaydedilir", {
  skip_if_not_installed("writexl")

  env <- .pk_export_env()
  kayitli <- new.env(parent = emptyenv())
  kayitli$geri_cagrilar <- list()

  sahte_session <- list(
    registerDataObj = function(name, data, filterFunc) paste0("session/", name),
    onSessionEnded = function(fn) {
      kayitli$geri_cagrilar[[length(kayitli$geri_cagrilar) + 1L]] <- fn
      invisible(TRUE)
    },
    userData = new.env(parent = emptyenv())
  )

  artefakt <- env$pk_export_build(data.frame(A = 1:3), list(facts = list()), list(),
                                  base_name = "sentetik", dir = .pk_export_dir())
  sunulan <- env$pk_export_serve(sahte_session, artefakt)
  yol <- sunulan$files[[1]]$path

  expect_true(grepl("^session/pk_export_", sunulan$files[[1]]$url))
  expect_length(kayitli$geri_cagrilar, 1L)
  expect_true(yol %in% sahte_session$userData$pk_export_cleanup_paths)
  expect_true(file.exists(yol))

  # Ikinci bir disa aktarim, geri cagriyi TEKRAR kaydetmez ama defteri buyutur.
  ikinci <- env$pk_export_serve(
    sahte_session,
    env$pk_export_build(data.frame(A = 4:6), list(facts = list()), list(),
                        base_name = "sentetik2", dir = .pk_export_dir())
  )
  expect_length(kayitli$geri_cagrilar, 1L)
  expect_true(ikinci$files[[1]]$path %in% sahte_session$userData$pk_export_cleanup_paths)

  # Oturum bitince HER IKI dosya da silinir.
  kayitli$geri_cagrilar[[1]]()
  expect_false(file.exists(yol))
  expect_false(file.exists(ikinci$files[[1]]$path))
})

test_that("Her disa aktarim TEKIL bir calisma dizinine yazar (cakisma yok)", {
  skip_if_not_installed("writexl")

  env <- .pk_export_env()
  kok <- .pk_export_dir()
  veri <- data.frame(A = 1:3)

  a <- env$pk_export_build(veri, list(facts = list()), list(),
                           base_name = "ayni_ad", dir = kok)
  b <- env$pk_export_build(veri, list(facts = list()), list(),
                           base_name = "ayni_ad", dir = kok)

  expect_false(identical(a$files[[1]]$path, b$files[[1]]$path))
  expect_true(file.exists(a$files[[1]]$path))
  expect_true(file.exists(b$files[[1]]$path))
})

.pk_export_pin_thresholds <- function(code) {
  # EŞİK VARSAYILANLARI SABİTLENİR: bu anahtarlar `.Renviron` ile
  # yapılandırılabilir; dağıtım kabuğunda tanımlıysa üretim çözümleyicisi doğru
  # olduğu hâlde varsayılan iddiaları kırılırdı (satır 278/301'deki
  # `MERGEN_PK_EXPORT_MAX_ROWS` sabitlemesiyle aynı gerekçe).
  withr::with_envvar(
    list(
      MERGEN_PK_PREVIEW_ROWS       = NA_character_,
      MERGEN_PK_DT_MAX_ROWS        = NA_character_,
      MERGEN_PK_INLINE_MAX_ROWS    = NA_character_,
      MERGEN_PK_INLINE_MAX_COLS    = NA_character_,
      MERGEN_PK_INLINE_MAX_COLS_DT = NA_character_
    ),
    code
  )
}

# --- Yanit kompozisyonu (§5.8) ------------------------------------------------

test_that("Esik kurallari SIRALIDIR ve ilk eslesen kazanir", {
  skip_if_not_installed("withr")
  env <- .pk_export_env()

  .pk_export_pin_thresholds({
    # Kural 1: kullanici acikca liste/excel istiyor.
    expect_identical(env$pk_compose_decide(3L, 3L, "listeyi ver")$mode, "attachment")
    expect_identical(env$pk_compose_decide(3L, 3L, "excel olarak ver")$rule, 1L)

    # Kural 2: 100 satir x 20 sutun HEM "<= 200 satir" HEM "> 12 sutun" saglar;
    # sira olmadan iki uygulama farkli davranirdi.
    karar <- env$pk_compose_decide(100L, 20L, "durum nedir")
    expect_identical(karar$mode, "attachment")
    expect_identical(karar$rule, 2L)

    # Kural 3: kucuk sonuc satir ici tablo.
    expect_identical(env$pk_compose_decide(10L, 5L, "durum nedir")$mode, "inline_table")

    # Kural 4: aradaki her sey.
    expect_identical(env$pk_compose_decide(100L, 10L, "durum nedir")$mode, "dt")
  })
})

test_that("Turkce liste/dokum ifadeleri yerelden bagimsiz yakalanir", {
  env <- .pk_export_env()
  for (soru in c("LİSTEYİ VER", "döküm çıkar", "Excel olarak indir",
                 "dışa aktar lütfen", "rapor hazırla")) {
    expect_true(env$pk_compose_wants_export(soru),
                info = sprintf("'%s' disa aktarim istegi sayilmali.", soru))
  }
  expect_false(env$pk_compose_wants_export("hangi projeler gecikti"))
})

test_that("Baloncuk TABLO DUVARI degildir: buyuk sonuc onizleme + ek olur", {
  skip_if_not_installed("withr")
  env <- .pk_export_env()
  veri <- .pk_export_data(400L)

  .pk_export_pin_thresholds({
    karar <- env$pk_compose_decide(400L, 4L, "durum nedir")
    blok <- env$pk_compose_block(karar, veri, artifact = NULL,
                                 meta = .pk_export_query()$meta)

    expect_identical(karar$mode, "attachment")
    satir_sayisi <- length(strsplit(blok, "\n", fixed = TRUE)[[1]])
    expect_true(satir_sayisi < 30L)
    expect_true(grepl("Önizleme", blok, fixed = TRUE))
    expect_true(grepl("400 satırın ilk 10 satırı", blok, fixed = TRUE))
  })
})

test_that("Markdown tablo R tarafindan uretilir ve yapiyi bozan hucreler kacisir", {
  env <- .pk_export_env()
  veri <- data.frame(
    Ad = c("a | b", "satir\nsonu"),
    Deger = c(1234.5, 2),
    stringsAsFactors = FALSE
  )

  tablo <- env$pk_compose_markdown_table(veri, max_rows = 10L, max_cols = 8L)
  expect_true(grepl("| Ad | Deger |", tablo, fixed = TRUE))
  expect_true(grepl("a \\| b", tablo, fixed = TRUE))
  expect_false(grepl("satir\nsonu", tablo, fixed = TRUE))
  expect_true(grepl("1.234,5", tablo, fixed = TRUE))
})

test_that("Ek karti dosya adi, satir x sutun ve oturum kapsamli baglanti gosterir", {
  env <- .pk_export_env()
  kart <- env$pk_compose_attachment_card(list(
    status = "ok",
    files = list(list(path = tempfile(), name = "sentetik.xlsx", rows = 312L,
                      cols = 14L, url = "session/pk_export_sentetik"))
  ))

  expect_true(grepl("sentetik.xlsx", kart, fixed = TRUE))
  expect_true(grepl("312 satır × 14 sütun", kart, fixed = TRUE))
  expect_true(grepl("session/pk_export_sentetik", kart, fixed = TRUE))
})

test_that("Reddedilen disa aktarim kullaniciya ACIKCA soylenir", {
  env <- .pk_export_env()
  kart <- env$pk_compose_attachment_card(list(
    status = "refused", files = list(),
    message = "Sonuç kümesi çok büyük; lütfen sorunuzu daraltın."
  ))

  expect_true(grepl("Dışa aktarım yapılmadı", kart, fixed = TRUE))
  expect_true(grepl("daraltın", kart, fixed = TRUE))
})

test_that("Olgu ozeti block kipi icin deterministik metin uretir", {
  env <- .pk_export_env()
  olgular <- env$pk_measure_facts(c(1, 2, 3), "Saat",
                                  list(label = "Saat", unit = "saat", decimals = 1L),
                                  additive = TRUE)
  ozet <- env$pk_compose_facts_summary(olgular)

  expect_true(grepl("Hesaplanan değerler", ozet, fixed = TRUE))
  expect_true(grepl("6,0 saat", ozet, fixed = TRUE))
  expect_false(grepl("KULLANILAMAZ", ozet, fixed = TRUE))
})

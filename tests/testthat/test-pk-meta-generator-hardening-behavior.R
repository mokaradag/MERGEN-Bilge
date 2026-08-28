# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-meta-generator-hardening-behavior.R
# Açıklama: Faz 3b metadata üreticisi -- İNCELEME BULGULARI için REGRESYON
#           sözleşmesi.
#
# Bu dosya, kod incelemesinde saptanan ve düzeltilen davranışların GERİ
# GELMEMESİNİ güvence altına alır. Tamamen ÇEVRİMDIŞI ve BELİRLENİMCİDİR:
# SQL Server, LLM, tarayıcı, SSO, ağ ya da gizli değer GEREKMEZ. Örnekleme
# testleri gerçek ama YEREL bir SQLite bağlantısı kullanır.
#
# DÜRÜSTLÜK SINIRI: burada kanıtlanan hiçbir şey Windows VM davranışını, gerçek
# ODBC sürücü metinlerini ya da üretim SQL'ini KANITLAMAZ.
# ==============================================================================

local({
  repo_root <- resolve_repo_root_for_tests()

  if (!exists("%||%", mode = "function", inherits = TRUE)) {
    `%||%` <<- function(a, b) if (is.null(a)) b else a
  }

  for (dosya in c(
    "helpers_pk_ascii_tokens.R",
    "helpers_pk_text_turkish.R",
    "helpers_pk_config.R",
    "helpers_pk_query_meta_schema.R",
    "helpers_pk_query_meta_access.R",
    "helpers_pk_query_meta_layers.R",
    "helpers_pk_query_meta.R",
    "helpers_pk_sql_statements.R", "helpers_pk_sql_readonly.R",
    "helpers_pk_sql_local_temp_batch.R"
  )) {
    source(file.path(repo_root, "R", dosya), encoding = "UTF-8", local = globalenv())
  }

  # Giriş noktasıyla AYNI sıra (bkz. tools/pk/generate_query_meta.R).
  for (dosya in c(
    "helpers_meta_generator_config.R",
    "helpers_meta_generator_schema.R",
    "helpers_meta_generator_render.R",
    "helpers_meta_generator_redact.R",
    "helpers_meta_generator_findings.R",
    "helpers_meta_generator_health.R",
    "helpers_meta_generator_state.R",
    "helpers_meta_generator_db.R",
    "helpers_meta_generator_fetch.R",
    "helpers_meta_generator_run.R",
    "helpers_meta_generator_lock.R",
    "helpers_meta_generator_commit.R"
  )) {
    source(file.path(repo_root, "tools", "pk", dosya), encoding = "UTF-8", local = globalenv())
  }
})

.pkh_cfg <- function(mode = "describe", ...) {
  anahtarlar <- c(
    "MERGEN_PK_META_MODE", "MERGEN_PK_META_SAMPLE_ROWS",
    "MERGEN_PK_META_HIGH_CARD_MIN", "MERGEN_PK_META_SQL_TIMEOUT_SEC",
    "MERGEN_PK_META_MAX_RESULT_MB", "MERGEN_PK_META_RESUME",
    "MERGEN_PK_META_SAMPLE_UNICODE"
  )
  temiz <- stats::setNames(rep(NA_character_, length(anahtarlar)), anahtarlar)
  temiz[["MERGEN_PK_META_MODE"]] <- mode

  withr::with_envvar(temiz, {
    cfg <- pkg_meta_resolve_config(repo_root = tempdir())
    ekler <- list(...)
    for (ad in names(ekler)) cfg[[ad]] <- ekler[[ad]]
    cfg
  })
}

.pkh_desc <- function(...) {
  sutunlar <- list(...)
  lapply(names(sutunlar), function(ad) {
    list(name = ad, system_type_name = sutunlar[[ad]], max_length = 50)
  })
}

.pkh_kayit <- function(id, status, codes = character(0)) {
  list(
    query_id = id, status = status,
    findings = lapply(codes, function(k) list(code = k, severity = "blocking"))
  )
}

# ------------------------------------------------------------------------------
# 1) Devam önbelleği parmak izi ve yedek karma
# ------------------------------------------------------------------------------

test_that("saf R yedek karmasi 32 bit tasmasi yuzunden NA URETMEZ", {
  # `bitwXor()` sayisal islenenleri `integer` turune ZORLAR; FNV baslangic
  # degeri (2166136261) isaretli tam sayi ust sinirinin USTUNDEDIR ve dogrudan
  # verildiginde NA uretirdi.
  karma <- expect_no_warning(.pkgh_fallback_hash("MERGEN"))

  expect_type(karma, "character")
  expect_false(grepl("NA", karma, fixed = TRUE))
  expect_true(grepl("^[0-9a-f]{16}-[0-9]+$", karma))
  expect_identical(karma, .pkgh_fallback_hash("MERGEN"))
  expect_false(identical(karma, .pkgh_fallback_hash("MERGEN2")))
})

test_that("SAMPLE kipinde kanit ureten ayarlar parmak izini DEGISTIRIR", {
  q <- list(id = "q1", sql = "SELECT 1", db_target = "primary")

  a <- pkgh_state_fingerprint(q, .pkh_cfg("sample", high_cardinality_threshold = 10L))
  b <- pkgh_state_fingerprint(q, .pkh_cfg("sample", high_cardinality_threshold = 50L))
  # Esik degistiginde eski `high_cardinality_proved` KANITLANMIS degildir.
  expect_false(identical(a, b))

  c1 <- pkgh_state_fingerprint(q, .pkh_cfg("sample", sample_rows = 100L))
  c2 <- pkgh_state_fingerprint(q, .pkh_cfg("sample", sample_rows = 500L))
  expect_false(identical(c1, c2))
})

test_that("DESCRIBE kipinde ornekleme ayarlari parmak izini ETKILEMEZ", {
  q <- list(id = "q1", sql = "SELECT 1", db_target = "primary")
  a <- pkgh_state_fingerprint(q, .pkh_cfg("describe", high_cardinality_threshold = 10L))
  b <- pkgh_state_fingerprint(q, .pkh_cfg("describe", high_cardinality_threshold = 50L))
  expect_identical(a, b)
})

test_that("KAYNAK parmak izi kanit ayarlarindan BAGIMSIZDIR", {
  # Yayimlanmis bir `result_schema`, ornekleme esigi degisti diye GECERSIZ
  # OLMAZ; yalnizca SQL/hedef degistiginde gecersiz olur. Devam onbellegi ise
  # TURETILMIS gozlem tasidigi icin esige BAGLIDIR.
  q <- list(id = "q1", sql = "SELECT 1", db_target = "primary")

  kaynak <- pkgh_source_fingerprint(q)
  expect_identical(kaynak, pkgh_source_fingerprint(q))
  expect_false(identical(
    kaynak,
    pkgh_source_fingerprint(list(id = "q1", sql = "SELECT 2", db_target = "primary"))
  ))

  a <- pkgh_state_fingerprint(q, .pkh_cfg("sample", high_cardinality_threshold = 10L))
  b <- pkgh_state_fingerprint(q, .pkh_cfg("sample", high_cardinality_threshold = 50L))
  expect_false(identical(a, b))
  # Kaynak damgasi ikisinden de FARKLI ve ikisi arasinda DEGISMEZ.
  expect_false(identical(kaynak, a))
})

test_that("URETILEN girdi KAYNAK parmak izini DAMGALAR", {
  cfg <- .pkh_cfg("describe")
  sorgu <- list(id = "q1", name = "A", sql = "SELECT 1", db_target = "primary")

  sonuc <- pkgn_inventory_one(
    query = sorgu, config = cfg, conn = structure(list(), class = "fake_conn"),
    describe_fn = function(conn, sql) .pkh_desc(Tutar = "int"),
    sample_fn = function(conn, sql, n) stop("ornekleme beklenmiyordu")
  )

  expect_identical(sonuc$record$status, "ok")
  # DAMGA OLMADAN bir sonraki kosunun birlestirme kapisi girdiyi
  # DOGRULAYAMAZ ve gecici bir hatada onu (dogru bicimde) DUSURURDU.
  expect_identical(sonuc$local_entry$source_fingerprint, pkgh_source_fingerprint(sorgu))

  # Damgali girdi, SQL degismedigi surece gecici hatada KORUNUR.
  parmak <- pkgh_source_fingerprints(list(sorgu))
  birlesme <- pkgc_merge_local_layers(
    list(q1 = sonuc$local_entry), list(),
    list(.pkh_kayit("q1", "failed", "describe_failed")),
    fingerprints = parmak
  )
  expect_identical(birlesme$kept, "q1")
})

test_that("DAMGASIZ eski girdi gecici hatada KORUNMAZ", {
  # Bu surumden ONCE uretilmis girdilerde damga yoktur; dogrulanamayan bir
  # sozlesmeyi canli birakmak yerine DUSURMEK guvenli yondur.
  onceki <- list(q1 = list(result_schema = c(A = "numeric")))
  birlesme <- pkgc_merge_local_layers(
    onceki, list(), list(.pkh_kayit("q1", "failed", "describe_failed")),
    fingerprints = list(q1 = "fp1")
  )
  expect_identical(birlesme$stale_removed, "q1")
  expect_null(birlesme$meta$q1)
})

test_that("SQL degisimi parmak izini DEGISTIRIR (alan ayirici korunur)", {
  cfg <- .pkh_cfg("describe")
  a <- pkgh_state_fingerprint(list(id = "q", sql = "SELECT A", db_target = "primary"), cfg)
  b <- pkgh_state_fingerprint(list(id = "q", sql = "SELECT B", db_target = "primary"), cfg)
  expect_false(identical(a, b))

  # Ayirici olmadan `hedef + sql` sinirlari kayabilir ve iki farkli girdi ayni
  # metne cozulebilirdi.
  x <- pkgh_state_fingerprint(list(id = "q", sql = "b", db_target = "primary"), cfg)
  y <- pkgh_state_fingerprint(list(id = "q", sql = "", db_target = "primaryb"), cfg)
  expect_false(identical(x, y))
})

test_that("devam durumu yazilamazsa ONCEKI anlik goruntu KARANTINAYA alinir", {
  gecici <- withr::local_tempdir()
  yol <- file.path(gecici, "generator-state.json")
  writeLines("{}", yol)

  sonuc <- pkgh_quarantine_state(yol)

  expect_true(isTRUE(sonuc$ok))
  # Dosya SILINMEZ, yeniden adlandirilir: operator inceleyebilmelidir.
  expect_false(file.exists(yol))
  expect_true(file.exists(sonuc$path))
})

# ------------------------------------------------------------------------------
# 2) Koşu kilidi: sahiplik, kalp atışı, atomik devralma
# ------------------------------------------------------------------------------

test_that("kilit sahiplik JETONU tasir ve YALNIZCA sahibi birakir", {
  gecici <- withr::local_tempdir()
  yol <- file.path(gecici, "kilit")

  a <- pkgc_acquire_run_lock(yol)
  expect_true(a$ok)
  expect_identical(a$reason, "acquired")
  expect_true(nzchar(a$token))

  # Ikinci kosu CEKISME goruyor.
  b <- pkgc_acquire_run_lock(yol)
  expect_false(b$ok)
  expect_identical(b$reason, "contention")

  # Kilit BASKASI tarafindan devralinmissa eski kosu onu SILMEZ.
  sahte <- a
  sahte$token <- "baska-kosu"
  expect_false(isTRUE(pkgc_release_run_lock(sahte)))
  expect_true(dir.exists(yol))

  expect_true(isTRUE(pkgc_release_run_lock(a)))
  expect_false(dir.exists(yol))
})

test_that("kalp atisi CANLI kosuyu bayat sayilmaktan korur", {
  gecici <- withr::local_tempdir()
  yol <- file.path(gecici, "kilit")

  a <- pkgc_acquire_run_lock(yol)
  expect_true(a$ok)

  # Kalp atisi tazelenmeden bayatlama esigi asilirsa ikinci kosu devralir.
  Sys.setFileTime(file.path(yol, PKG_META_LOCK_HEARTBEAT_FILE), Sys.time() - 7200)
  Sys.setFileTime(file.path(yol, PKG_META_LOCK_OWNER_FILE), Sys.time() - 7200)
  Sys.setFileTime(yol, Sys.time() - 7200)

  expect_gt(.pkgc_lock_age_sec(yol), 3600)

  # Kalp atisi tazelenince kilit YENIDEN canli sayilir.
  expect_true(isTRUE(pkgc_refresh_run_lock(a)))
  expect_lt(.pkgc_lock_age_sec(yol), 60)
})

test_that("BAYAT kilit devralinir ve devralma ATOMIK rename ile yapilir", {
  gecici <- withr::local_tempdir()
  yol <- file.path(gecici, "kilit")

  a <- pkgc_acquire_run_lock(yol)
  expect_true(a$ok)
  for (dosya in list.files(yol, full.names = TRUE)) {
    Sys.setFileTime(dosya, Sys.time() - 7200)
  }
  Sys.setFileTime(yol, Sys.time() - 7200)

  b <- pkgc_acquire_run_lock(yol, stale_sec = 60)
  expect_true(b$ok)
  expect_identical(b$reason, "takeover")
  # Devralan yeni bir jeton yazar; eski kosu artik sahibi DEGILDIR.
  expect_false(identical(a$token, b$token))
  expect_identical(.pkgc_lock_read_token(yol), b$token)
  expect_false(isTRUE(pkgc_release_run_lock(a)))
})

test_that("G/C hatasi CEKISME ile KARISTIRILMAZ", {
  # Ust klasor bir DOSYA oldugunda kilit dizini olusturulamaz; bu bir
  # eszamanlilik sorunu DEGILDIR ve operatore "kilidi silin" denmemelidir.
  gecici <- withr::local_tempdir()
  engel <- file.path(gecici, "engel")
  writeLines("x", engel)

  sonuc <- pkgc_acquire_run_lock(file.path(engel, "kilit"))
  expect_false(sonuc$ok)
  expect_identical(sonuc$reason, "io_error")
  expect_false(grepl("kilit dizinini silin", sonuc$detail, fixed = TRUE))
})

# ------------------------------------------------------------------------------
# 3) Katman birleştirme: parmak izi ve kesin/geçici ayrımı
# ------------------------------------------------------------------------------

test_that("GECICI hatada onceki girdi KORUNUR (parmak izi uyuyorsa)", {
  onceki <- list(q1 = list(result_schema = c(A = "numeric"), source_fingerprint = "fp1"))
  kayitlar <- list(.pkh_kayit("q1", "failed", "describe_failed"))

  birlesme <- pkgc_merge_local_layers(onceki, list(), kayitlar,
                                      fingerprints = list(q1 = "fp1"))

  expect_identical(birlesme$kept, "q1")
  expect_identical(birlesme$meta$q1$result_schema, c(A = "numeric"))
})

test_that("SQL DEGISTIGINDE onceki girdi KORUNMAZ (bayat sozlesme birakilmaz)", {
  # Bu tam olarak butun-kutuphane kapisinin YAKALAYAMADIGI durumdur: kapi
  # SQL'i CALISTIRMAZ, dolayisiyla eski `numeric` sema gecerli gorunur.
  onceki <- list(q1 = list(result_schema = c(A = "numeric"), source_fingerprint = "eski"))
  kayitlar <- list(.pkh_kayit("q1", "failed", "describe_failed"))

  birlesme <- pkgc_merge_local_layers(onceki, list(), kayitlar,
                                      fingerprints = list(q1 = "yeni"))

  expect_identical(birlesme$stale_removed, "q1")
  expect_null(birlesme$meta$q1)
  expect_length(birlesme$kept, 0L)
})

test_that("KESIN kusurlarda onceki girdi KALDIRILIR", {
  for (kod in c("invalid_db_target", "missing_sql", "sql_not_readonly",
                "missing_query_id", "malformed_library_entry")) {
    onceki <- list(q1 = list(result_schema = c(A = "numeric"), source_fingerprint = "fp1"))
    durum <- if (identical(kod, "sql_not_readonly")) "skipped" else "failed"
    kayitlar <- list(.pkh_kayit("q1", durum, kod))

    birlesme <- pkgc_merge_local_layers(onceki, list(), kayitlar,
                                        fingerprints = list(q1 = "fp1"))

    expect_null(birlesme$meta$q1, info = kod)
    expect_true("q1" %in% birlesme$withheld_removed, info = kod)
  }
})

test_that("ok durumunda uretilen girdi ONCEKININ YERINE gecer", {
  onceki <- list(q1 = list(result_schema = c(A = "numeric"), source_fingerprint = "fp1"))
  uretilen <- list(q1 = list(result_schema = c(A = "character")))
  kayitlar <- list(.pkh_kayit("q1", "ok"))

  birlesme <- pkgc_merge_local_layers(onceki, uretilen, kayitlar,
                                      fingerprints = list(q1 = "fp1"))
  expect_identical(birlesme$replaced, "q1")
  expect_identical(birlesme$meta$q1$result_schema, c(A = "character"))
})

# ------------------------------------------------------------------------------
# 4) Katalog teşhisi: bozuk `sql_file` beyanı
# ------------------------------------------------------------------------------

test_that("cozulemeyen/bos sql_file beyani KATALOG bulgusu uretir", {
  gecici <- withr::local_tempdir()
  bos <- file.path(gecici, "bos.sql")
  file.create(bos)
  dolu <- file.path(gecici, "dolu.sql")
  writeLines("SELECT 1", dolu)

  kayitlar <- pkgc_catalog_findings(list(
    list(id = "yok", name = "A", sql_file = file.path(gecici, "olmayan.sql")),
    list(id = "bos", name = "B", sql_file = bos),
    list(id = "iyi", name = "C", sql_file = dolu)
  ))

  kodlar <- unlist(lapply(kayitlar, function(r) {
    vapply(r$findings, function(f) f$code, character(1))
  }))

  expect_true("sql_file_unresolvable" %in% kodlar)
  expect_true("sql_file_empty" %in% kodlar)
  # Saglikli beyan bulgu URETMEZ.
  expect_false("iyi" %in% vapply(kayitlar, function(r) r$query_id, character(1)))
})

# ------------------------------------------------------------------------------
# 5) Hata sınıflandırma ve maskeleme
# ------------------------------------------------------------------------------

test_that("SQLSTATE ACILIS PARANTEZINDEN cikarilir (Microsoft oneki yanilmaz)", {
  ozet <- pkgh_db_error_summary(
    "[Microsoft][ODBC Driver 18 for SQL Server][22018] Conversion failed"
  )
  expect_true(grepl("sqlstate=22018", ozet, fixed = TRUE))
  expect_false(grepl("osoft", ozet, fixed = TRUE))
})

# TURKCE YEREL KUR (kurulamazsa ATLA).
#
# `LC_CTYPE` adlari platforma gore degisir; POSIX ve Windows yazimlarinin
# TAMAMI denenir. Windows-motivasyonlu bir sozlesmenin tam Windows'ta atlanmasi
# anlamsiz olurdu.
.pkh_turkce_yerel_kur <- function() {
  for (yerel in c("tr_TR.UTF-8", "tr_TR.utf8", "tr_TR", "Turkish_Turkey.1254",
                  "Turkish_Turkey.65001", "Turkish")) {
    kuruldu <- suppressWarnings(try(Sys.setlocale("LC_CTYPE", yerel), silent = TRUE))
    if (!inherits(kuruldu, "try-error") && is.character(kuruldu) && nzchar(kuruldu)) {
      return(TRUE)
    }
  }
  FALSE
}

test_that("hata sinifi YERELDEN BAGIMSIZ eslesir", {
  # Turkce yerelde buyuk `I` noktasiz `i` olur; ASCII katlama bunu kapar.
  eski <- Sys.getlocale("LC_CTYPE")
  on.exit(try(suppressWarnings(Sys.setlocale("LC_CTYPE", eski)), silent = TRUE), add = TRUE)

  iddialar <- function() {
    expect_true(grepl("sinif=permission_denied",
                      pkgh_db_error_summary("LOGIN FAILED for user"), fixed = TRUE))
    expect_true(grepl("sinif=connection_lost",
                      pkgh_db_error_summary("COMMUNICATION LINK FAILURE"), fixed = TRUE))
    expect_true(grepl("sinif=object_missing",
                      pkgh_db_error_summary("INVALID OBJECT NAME 'dbo.X'"), fixed = TRUE))
  }

  # 1) Mevcut (genelde C/UTF-8) yerelde taban davranis.
  iddialar()

  # 2) YEREL GERCEKTEN DEGISTIRILIR.
  #
  # Yalnizca mevcut yereli kaydedip iddiada bulunmak sozlesmeyi SINAMAZ: tum
  # girdiler ASCII buyuk harftir ve `tolower()`e donen bir regresyon varsayilan
  # yerelde de eslesirdi. Turkce yerel kurulamiyorsa (CI konteyneri) yalnizca
  # bu ikinci tur atlanir; taban iddialar YINE calisir.
  # `skip()` KULLANILMAZ.
  #
  # `testthat` govdesi icinde `skip()` cagrilirsa TUM test "skipped" sayilir ve
  # o ana kadar kaydedilen iddialar ATILIR. Turkce yereli olmayan bir kosucuda
  # (normal Linux CI konteyneri) taban iddialar hicbir gecen sonuc uretmiyor,
  # asagidaki yerel-geri-yukleme dogrulamasi da HIC calismiyordu. Turkce yerel
  # yoksa yalnizca ikinci tur ATLANIR; sonuclar KORUNUR.
  if (.pkh_turkce_yerel_kur()) {
    iddialar()
    suppressWarnings(Sys.setlocale("LC_CTYPE", eski))
  } else {
    message("Turkce LC_CTYPE yok; yalnizca taban yerel sinandi.")
  }

  # Yerel geri yuklendigi DOGRULANIR: sizan bir LC_CTYPE sonraki dosyalari kirar.
  expect_identical(Sys.getlocale("LC_CTYPE"), eski)
})

test_that("serbest metindeki 'error NNN' hata numarasi olarak SIZDIRILMAZ", {
  # Ham surucu metni URETIM SATIR DEGERI tasiyabilir; degeri `error 12345` olan
  # bir donusum hatasi, satir degerinin bir parcasini rapora tasirdi.
  ozet <- pkgh_db_error_summary(
    "Conversion failed when converting the nvarchar value 'error 12345' to int"
  )
  expect_false(grepl("hata_no", ozet, fixed = TRUE))

  # YAPISAL OLARAK CAPALANMIS T-SQL basligi ise korunur.
  capali <- pkgh_db_error_summary("Msg 208, Level 16, State 1, Line 1")
  expect_true(grepl("hata_no=208", capali, fixed = TRUE))
})

test_that("42S02/42S22 NESNE EKSIK olarak siniflandirilir", {
  expect_true(grepl("sinif=object_missing",
                    pkgh_db_error_summary("[42S02] tablo yok"), fixed = TRUE))
  expect_true(grepl("sinif=object_missing",
                    pkgh_db_error_summary("[42S22] sutun yok"), fixed = TRUE))
})

test_that("standart ODBC oneki her hatayi SURUCU SORUNU yapmaz", {
  # `[ODBC Driver 18 for SQL Server]` oneki NORMAL sunucu hatalarinda da vardir;
  # yalin `driver` kelimesi operatoru DSN/surucu teshisine yonlendirirdi.
  ozet <- pkgh_db_error_summary(
    "[Microsoft][ODBC Driver 18 for SQL Server] Transaction was deadlocked"
  )
  expect_false(grepl("sinif=driver_unavailable", ozet, fixed = TRUE))

  expect_true(grepl("sinif=driver_unavailable",
                    pkgh_db_error_summary("[IM002] Data source name not found"),
                    fixed = TRUE))
})

test_that("bootstrap istisnasi KULLANICI ADI ve YOL sizdirmaz", {
  # FIKSTUR CALISMA ZAMANINDA KURULUR.
  #
  # Depo sozlesmesi (`test-secret-leak-contract.R`) kisisel mutlak Windows
  # kullanici yolunun kaynak dosyada LITERAL olarak bulunmasini yasaklar; bir
  # test fiksturu bu kurali "ornek" diye delemez.
  kullanici <- "alice"
  yol <- paste0("C:", "/Users/", kullanici, "/gizli.R")
  alan_kullanici <- paste0("DOMAIN", "\\", kullanici)
  ham <- sprintf("Login failed for user '%s' while reading %s", alan_kullanici, yol)

  guvenli <- pkgh_sanitize_bootstrap_error(ham)

  expect_false(grepl(kullanici, guvenli, ignore.case = TRUE))
  expect_false(grepl(paste0("C:", "/Users"), guvenli, fixed = TRUE))
  expect_true(grepl("<kullanici>", guvenli, fixed = TRUE) ||
                grepl("<yol>", guvenli, fixed = TRUE))
})

test_that("bootstrap maskesi COK UZUN metni kisaltir", {
  uzun <- paste(rep("A", 5000), collapse = "")
  expect_lt(nchar(pkgh_sanitize_bootstrap_error(uzun)), 700L)
})

# ------------------------------------------------------------------------------
# 6) Doğrulayıcı mesajları: ilgisiz bloklayıcı GİZLENMEZ
# ------------------------------------------------------------------------------

test_that("OZEL bulguyla temsil EDILMEYEN dogrulayici hatasi BLOKLAYICI kalir", {
  sorgu <- list(id = "q1", rls_columns = list(proje_kodu_col = "ProjeKodu"))
  sema <- c(Tutar = "numeric")

  bulgular <- pkgh_structural_findings(
    sorgu,
    merged = list(column_meta = list()),
    schema = sema,
    blocking = c(
      "[q1] rls_columns$proje_kodu_col = 'ProjeKodu' semada yok (D6 fail-open deligi).",
      "[q1] BASKA BIR DOGRULAYICI KUSURU"
    )
  )

  kodlar <- vapply(bulgular, function(f) f$code, character(1))
  siddet <- vapply(bulgular, function(f) f$severity, character(1))

  # RLS kusuru ozel bulguyla temsil edilir.
  expect_true("rls_column_missing" %in% kodlar)
  # Temsil EDILMEYEN mesaj bloklayici olarak KALIR.
  expect_true("startup_validation_would_fail" %in% kodlar)
  expect_identical(siddet[kodlar == "startup_validation_would_fail"], "blocking")

  ayrinti <- bulgular[[which(kodlar == "startup_validation_would_fail")]]$detail
  expect_true(grepl("BASKA BIR DOGRULAYICI KUSURU", ayrinti, fixed = TRUE))
  expect_false(grepl("D6 fail-open", ayrinti, fixed = TRUE))
})

test_that("TAMAMI temsil edilen dogrulayici yuku yalnizca AYRINTI olur", {
  sorgu <- list(id = "q1", rls_columns = list(proje_kodu_col = "ProjeKodu"))
  bulgular <- pkgh_structural_findings(
    sorgu, merged = list(column_meta = list()), schema = c(Tutar = "numeric"),
    blocking = "[q1] rls_columns$proje_kodu_col = 'ProjeKodu' semada yok (D6 fail-open deligi)."
  )
  kodlar <- vapply(bulgular, function(f) f$code, character(1))
  expect_true("startup_validation_detail" %in% kodlar)
  expect_false("startup_validation_would_fail" %in% kodlar)
})

test_that("ESKI sutun beyanlari AYNEN karsilastirilir (kirpilmaz)", {
  # `convert_date_columns()` beyani KIRPMAZ; `" Tarih "` calisma zamaninda
  # SESSIZCE atlanir. Rapor bunu "temiz" diye onaylayamaz.
  bulgular <- pkgh_structural_findings(
    list(id = "q1", date_columns = c(" Tarih ")),
    merged = list(column_meta = list()),
    schema = c(Tarih = "Date")
  )
  kodlar <- vapply(bulgular, function(f) f$code, character(1))
  expect_true("query_date_columns_missing_in_schema" %in% kodlar)
})

# ------------------------------------------------------------------------------
# 7) Sağlık kaydı ve artefakt dizini
# ------------------------------------------------------------------------------

test_that("saglik kaydi KANONIK db hedefini yazar", {
  kayit <- pkgh_query_record(list(id = "q1", db_target = "  Secondary  "), "ok", "describe",
                             schema = c(A = "integer"))
  expect_identical(kayit$db_target, "secondary")
})

test_that("bos ornek bilgisi JSON turunu DEGISTIRMEZ (null yazilir)", {
  bos <- pkgh_query_record(list(id = "q1"), "failed", "describe")
  dolu <- pkgh_query_record(list(id = "q2"), "ok", "sample", schema = c(A = "integer"),
                            sample_info = list(mode = "sample", rows_seen = 3L))
  expect_null(bos$sample)
  expect_true(is.list(dolu$sample))
})

test_that("rapor kararliligi NULL alanlari SILMEZ", {
  skip_if_not_installed("jsonlite")

  # `x[[i]] <- NULL` bir liste ogesini KALDIRIR ve kalanlari KAYDIRIR; dongu de
  # sonraki turda "subscript out of bounds" ile duserdi. Kayitlar bilincli
  # olarak NULL alan tasir (bos `sample`).
  girdi <- list(a = 1L, sample = NULL, columns = c("A", "B"), z = "son")
  kararli <- pkgh_stabilize_report(girdi)

  expect_identical(names(kararli), names(girdi))
  expect_null(kararli$sample)
  expect_identical(kararli$z, "son")

  # Tek ogeli koleksiyon alani JSON'da DIZI kalir.
  json <- as.character(jsonlite::toJSON(
    pkgh_stabilize_report(list(columns = "A", sample = NULL)),
    auto_unbox = TRUE, null = "null"
  ))
  expect_true(grepl('"columns":["A"]', json, fixed = TRUE))
  expect_true(grepl('"sample":null', json, fixed = TRUE))
})

test_that("BASARISIZ kayit iceren rapor artefakti YAZILABILIR", {
  skip_if_not_installed("jsonlite")

  gecici <- withr::local_tempdir()
  kayitlar <- list(pkgh_query_record(list(id = "q1", name = "A"), "failed", "describe"))
  ozet <- pkgh_summarize(kayitlar)

  yollar <- pkgh_write_artifacts(
    report = list(run_id = "t", summary = ozet, queries = kayitlar),
    artifact_dir = gecici, records = kayitlar, summary = ozet,
    config_summary = pkg_meta_config_summary(.pkh_cfg("describe"))
  )

  expect_true(file.exists(yollar$json))
  geri <- jsonlite::fromJSON(yollar$json, simplifyVector = FALSE)
  expect_null(geri$queries[[1]]$sample)
  expect_identical(geri$queries[[1]]$status, "failed")
})

test_that("KORUNAN onceki metadata Tier-0 olarak RAPORLANMAZ", {
  kayitlar <- list(pkgh_query_record(list(id = "q1"), "failed", "describe"))
  expect_true(kayitlar[[1]]$tier0)

  uzlasik <- pkgh_reconcile_records_with_layer(kayitlar, list(q1 = list(result_schema = c(A = "int"))))
  expect_false(uzlasik[[1]]$tier0)
  expect_identical(uzlasik[[1]]$schema_validation, "preserved_previous")
  expect_identical(pkgh_summarize(uzlasik)$preserved_previous, 1L)
})

test_that("artefakt dizini ADAYLARIN TAMAMI DOLUYSA HATA verir", {
  gecici <- withr::local_tempdir()
  taban <- file.path(gecici, "kosu")

  # Taban + SON aday dahil tum sonek adaylari dolu.
  for (sonek in c("", "-2", "-3", "-4")) {
    yol <- paste0(taban, sonek)
    dir.create(yol, recursive = TRUE, showWarnings = FALSE)
    writeLines("x", file.path(yol, "health.txt"))
  }

  expect_error(pkgh_allocate_artifact_dir(taban, max_suffix = 3L), "DOLU")
  # Onceki raporun uzerine YAZILMADIGI dogrulanir.
  expect_identical(readLines(file.path(taban, "health.txt"), warn = FALSE), "x")
})

# ------------------------------------------------------------------------------
# 8) Şema çıkarımı: natif tip, genişlik ve blob NULL
# ------------------------------------------------------------------------------

test_that("SAMPLE kipi NATIF tip eslemesini UYGULAR", {
  df <- data.frame(Sayi = c(1, 2), stringsAsFactors = FALSE)
  cikarim <- pkgs_schema_from_dataframe(df, column_types = c(Sayi = "bigint"))
  # `describe` kipi `bigint` icin `integer64` yazar; iki kip AYNI temsili
  # uretmelidir, aksi halde yalnizca kip degistirmek rolleri degistirirdi.
  expect_identical(unname(cikarim$schema[["Sayi"]]), "integer64")
})

test_that("ESLENMEYEN natif tip gercekten character/dimension'a DUSURULUR", {
  df <- data.frame(Ozel = c(1, 2))
  cikarim <- pkgs_schema_from_dataframe(df, column_types = c(Ozel = "geography"))

  expect_identical(unname(cikarim$schema[["Ozel"]]), "character")
  expect_length(cikarim$unmapped, 1L)
  # Rol de olcu DEGIL boyut olmalidir; aksi halde sessiz yanlis toplam uretilir.
  cmeta <- pkgs_build_column_meta(cikarim$schema, cikarim$source_types, "sample")
  expect_identical(cmeta$Ozel$role, "dimension")
})

test_that("tanimlayici GENISLIK kaniti SAMPLE kipine tasinir", {
  # `max_length = -1`, tip adinda `(max)` OLMADAN sinirsizligi bildirir.
  df <- data.frame(Veri = c("a", "b"), stringsAsFactors = FALSE)
  cikarim <- pkgs_schema_from_dataframe(
    df, column_types = c(Veri = "geometry"), column_widths = c(Veri = -1)
  )
  expect_true("Veri" %in% cikarim$unbounded)
})

test_that("tanimlayici cikarimi GENISLIK haritasini dondurur", {
  cikarim <- pkgs_schema_from_descriptor(list(
    list(name = "A", system_type_name = "varchar(max)", max_length = -1),
    list(name = "B", system_type_name = "int", max_length = 4)
  ))
  expect_identical(unname(cikarim$widths[["A"]]), -1)
  expect_identical(unname(cikarim$widths[["B"]]), 4)
})

test_that("SIFIR UZUNLUKLU ham deger SQL NULL sayilmaz", {
  df <- data.frame(x = 1:2)
  df$Ikili <- list(raw(0), as.raw(c(1, 2)))

  gozlem <- pkgs_sample_observations(df)
  # `raw(0)` mesru bir bos `varbinary` degeridir; NULL DEGILDIR.
  expect_null(gozlem$Ikili$null_observed)
  expect_identical(gozlem$Ikili$distinct_observed, 2L)

  df2 <- data.frame(x = 1:2)
  df2$Ikili <- list(NULL, as.raw(1))
  expect_true(pkgs_sample_observations(df2)$Ikili$null_observed)
})

test_that("OLUMSUZ onek kaniti KAYDEDILMEZ", {
  df <- data.frame(Benzersiz = c("a", "b", "c"), stringsAsFactors = FALSE)
  gozlem <- pkgs_sample_observations(df, high_cardinality_threshold = 100L)

  expect_null(gozlem$Benzersiz$null_observed)
  expect_null(gozlem$Benzersiz$unique_disproved)
  expect_null(gozlem$Benzersiz$high_cardinality_proved)

  # Gozlenen mukerrer BENZERSIZLIGI CURUTUR.
  tekrar <- data.frame(K = c("a", "a"), stringsAsFactors = FALSE)
  expect_true(pkgs_sample_observations(tekrar)$K$unique_disproved)
})

# ------------------------------------------------------------------------------
# 9) Envanter döngüsü: kapı sırası, bağlantı hataları, önbellek tohumlama
# ------------------------------------------------------------------------------

test_that("YEREL kapilar BAGLANTI ACILMADAN once calisir", {
  # Bozuk/reddedilmis bir sorgu icin gercek bir uretim oturumu ACILMAMALIDIR;
  # erisilemeyen bir DSN'de bu, hic gerekmeyen bir bloklamaya donusur.
  cagrildi <- FALSE
  cfg <- .pkh_cfg("describe")

  kosu <- pkg_meta_run_inventory(
    query_library = list(
      list(id = "yazma", name = "A", sql = "DELETE FROM T", db_target = "primary"),
      list(id = "sqlsiz", name = "B", db_target = "primary"),
      list(id = "hedef", name = "C", sql = "SELECT 1", db_target = "yokboyle")
    ),
    config = cfg,
    connect_fn = function(target) {
      cagrildi <<- TRUE
      stop("baglanti ACILMAMALIYDI")
    },
    release_fn = function(handle) invisible(NULL),
    describe_fn = function(conn, sql) NULL,
    sample_fn = function(conn, sql, n) stop("ornekleme beklenmiyordu")
  )

  expect_false(cagrildi)
  kodlar <- vapply(kosu$records, function(r) r$findings[[1]]$code, character(1))
  expect_setequal(kodlar, c("sql_not_readonly", "missing_sql", "invalid_db_target"))
})

test_that("BAGLANTI EDINIM hatasi saglik kaydinda KORUNUR", {
  cfg <- .pkh_cfg("describe")
  kosu <- pkg_meta_run_inventory(
    query_library = list(list(id = "q1", name = "A", sql = "SELECT 1", db_target = "primary")),
    config = cfg,
    connect_fn = function(target) stop("[Microsoft][ODBC Driver 18][28000] Login failed"),
    release_fn = function(handle) invisible(NULL),
    describe_fn = function(conn, sql) NULL,
    sample_fn = function(conn, sql, n) stop("ornekleme beklenmiyordu")
  )

  kayit <- kosu$records[[1]]
  expect_identical(kayit$status, "failed")
  expect_identical(kayit$findings[[1]]$code, "no_connection")
  # Genel `no_connection` yetmez: kimlik dogrulama hatasi ile eksik surucu
  # AYIRT EDILEBILMELIDIR.
  expect_true(grepl("sinif=permission_denied", kayit$error, fixed = TRUE))
  # HAM surucu metni RAPORA GIRMEZ.
  expect_false(grepl("Login failed", kayit$error, fixed = TRUE))
})

test_that("ARA KAYIT gezilmemis onbellek girdilerini SILMEZ (ve sekli DOGRUDUR)", {
  skip_if_not_installed("jsonlite")

  cfg <- .pkh_cfg("describe", resume = TRUE)
  # `pkgh_read_state()` girdi basina TAM sonuc nesnesi doner; `$cache` alt
  # nesnesi DURUM SEKLINI tasir.
  onbellek <- list(
    q1 = list(ok = TRUE, schema = c(A = "integer"), source_types = c(A = "int"),
              cache = list(mode = "describe", columns = c(A = "integer"),
                           source_types = c(A = "int"), fingerprint = "fp1")),
    q2 = list(ok = TRUE, schema = c(B = "integer"), source_types = c(B = "int"),
              cache = list(mode = "describe", columns = c(B = "integer"),
                           source_types = c(B = "int"), fingerprint = "fp2"))
  )

  ara_kayitlar <- list()
  pkg_meta_run_inventory(
    query_library = list(list(id = "q1", name = "A", sql = "SELECT 1", db_target = "primary")),
    config = cfg,
    connect_fn = function(target) list(conn = structure(list(), class = "fake_conn")),
    release_fn = function(handle) invisible(NULL),
    describe_fn = function(conn, sql) NULL,
    sample_fn = function(conn, sql, n) stop("ornekleme beklenmiyordu"),
    cache = onbellek,
    checkpoint_fn = function(cache) ara_kayitlar[[length(ara_kayitlar) + 1L]] <<- cache
  )

  expect_gt(length(ara_kayitlar), 0L)
  ilk <- ara_kayitlar[[1]]
  # `q2` bu kosuda HIC gezilmedi; ilk ara kayitta SILINMIS olmamalidir.
  expect_true("q2" %in% names(ilk))
  expect_true("q1" %in% names(ilk))

  # SEKIL SINANIR: ad tasimak YETMEZ. Tam sonuc nesnesi oldugu gibi tohumlansaydi
  # `columns = NULL` yazilir ve girdi sonraki OKUMADA sessizce dusherdi; yani
  # koruma hic islemezdi.
  gecici <- withr::local_tempdir()
  yol <- file.path(gecici, "generator-state.json")
  expect_true(pkgh_write_state(ilk, yol, "describe", "20260818-000000"))

  # Bu test GIRDI SEKLINI olcer, tazeligi degil: sabit damga TTL'e takilmasin.
  onceki_yas <- Sys.getenv("MERGEN_PK_META_RESUME_MAX_AGE_SEC", unset = NA_character_)
  on.exit({
    if (is.na(onceki_yas)) {
      Sys.unsetenv("MERGEN_PK_META_RESUME_MAX_AGE_SEC")
    } else {
      Sys.setenv(MERGEN_PK_META_RESUME_MAX_AGE_SEC = onceki_yas)
    }
  }, add = TRUE)
  Sys.setenv(MERGEN_PK_META_RESUME_MAX_AGE_SEC = "0")

  geri <- pkgh_read_state(yol, "describe",
                          fingerprints = list(q1 = "fp1", q2 = "fp2"))
  expect_true("q2" %in% names(geri))
  expect_identical(unname(geri$q2$schema[["B"]]), "integer")
})

test_that("alias bindirmesi KANONIK (kirpilmis) kimlikle aranir", {
  # Ham `" q1 "` ile bakmak, sorguya ozgu alias kusurunu KACIRIR ve kusur ancak
  # BUTUN KUTUPHANE kapisinda patlar; o zaman tek bozuk sorgu TUM katmani bloklar.
  cfg <- .pkh_cfg("describe")
  kosu <- pkg_meta_run_inventory(
    query_library = list(list(id = " q1 ", name = "A", sql = "SELECT 1", db_target = "primary")),
    config = cfg,
    connect_fn = function(target) list(conn = structure(list(), class = "fake_conn")),
    release_fn = function(handle) invisible(NULL),
    describe_fn = function(conn, sql) .pkh_desc(Tutar = "int"),
    sample_fn = function(conn, sql, n) stop("ornekleme beklenmiyordu"),
    alias_overlay = list(q1 = list(column_aliases = list(YokSutun = "Yok")))
  )

  kayit <- kosu$records[[1]]
  expect_identical(kayit$query_id, "q1")
  # Bozuk alias SORGU BAZINDA yakalanir; katmana girmez.
  expect_identical(kayit$status, "withheld")
})

test_that("HYT00 (sorgu zaman asimi) BAGLANTI hatasi SAYILMAZ", {
  # `HYT00` genel SORGU zaman asimidir; onu baglanti hatasi saymak, olagan her
  # ifade zaman asiminda HALA KULLANILABILIR bir tutamaci dusururdu.
  expect_false(.pkgn_is_connection_error("[HYT00] Query timeout expired"))
  expect_true(.pkgn_is_connection_error("[HYT01] Connection timeout expired"))
  expect_true(.pkgn_is_connection_error("[08S01] Communication link failure"))
})

test_that("baglanti hatasi tespiti YERELDEN BAGIMSIZDIR", {
  eski <- Sys.getlocale("LC_CTYPE")
  on.exit(try(suppressWarnings(Sys.setlocale("LC_CTYPE", eski)), silent = TRUE), add = TRUE)

  iddialar <- function() {
    expect_true(.pkgn_is_connection_error("COMMUNICATION LINK FAILURE"))
    expect_true(.pkgn_is_connection_error("LOGIN TIMEOUT expired"))
  }
  iddialar()

  # Yerel GERCEKTEN Turkce'ye alinir; aksi halde `tolower()` regresyonu
  # varsayilan yerelde de eslesir ve test yesil kalirdi.
  # `skip()` KULLANILMAZ.
  #
  # `testthat` govdesi icinde `skip()` cagrilirsa TUM test "skipped" sayilir ve
  # o ana kadar kaydedilen iddialar ATILIR. Turkce yereli olmayan bir kosucuda
  # (normal Linux CI konteyneri) taban iddialar hicbir gecen sonuc uretmiyor,
  # asagidaki yerel-geri-yukleme dogrulamasi da HIC calismiyordu. Turkce yerel
  # yoksa yalnizca ikinci tur ATLANIR; sonuclar KORUNUR.
  if (.pkh_turkce_yerel_kur()) {
    iddialar()
    suppressWarnings(Sys.setlocale("LC_CTYPE", eski))
  } else {
    message("Turkce LC_CTYPE yok; yalnizca taban yerel sinandi.")
  }

  # Yerel geri yuklendigi DOGRULANIR: sizan bir LC_CTYPE sonraki dosyalari kirar.
  expect_identical(Sys.getlocale("LC_CTYPE"), eski)
})

# ------------------------------------------------------------------------------
# 10) Şema getirme: geçersiz tanımlayıcı ve natif kanıt yokluğu
# ------------------------------------------------------------------------------

test_that("SAMPLE kipinde YAPISAL OLARAK GECERSIZ tanimlayici orneklemeye DUSMEZ", {
  # `describe` kipi adsiz bir sonuc sutununu bilerek REDDEDER. Sessizce
  # orneklemeye dusmek, DBI'in uydurdugu adlarla o yapisal reddi ATLAYAN bir
  # sema yayimlardi.
  cfg <- .pkh_cfg("sample")
  orneklendi <- FALSE

  sonuc <- pkgn_fetch_schema(
    query = list(id = "q1", sql = "SELECT 1", db_target = "primary"),
    config = cfg, conn = structure(list(), class = "fake_conn"),
    describe_fn = function(conn, sql) list(list(name = NULL, system_type_name = "int")),
    sample_fn = function(conn, sql, n) {
      orneklendi <<- TRUE
      data.frame(V1 = 1L)
    }
  )

  expect_false(isTRUE(sonuc$ok))
  expect_identical(sonuc$code, "describe_invalid_schema")
  expect_false(orneklendi)
})

test_that("NATIF tip kaniti YOKKEN acik bir DIKKAT bulgusu uretilir", {
  cfg <- .pkh_cfg("sample")
  sonuc <- pkgn_inventory_one(
    query = list(id = "q1", name = "A", sql = "SELECT 1", db_target = "primary"),
    config = cfg, conn = structure(list(), class = "fake_conn"),
    # Tanimlayici GERCEKTEN alinamiyor.
    describe_fn = function(conn, sql) stop("sonda yok"),
    sample_fn = function(conn, sql, n) data.frame(Tutar = c(1, 2))
  )

  kodlar <- vapply(sonuc$record$findings, function(f) f$code, character(1))
  # Yalnizca makine alani `native_types_available = FALSE` yetmez: `health.txt`
  # "eylem gerektiren bulgu yok" derdi.
  expect_true("native_types_unavailable" %in% kodlar)
  expect_false(isTRUE(sonuc$record$sample$native_types_available))
})

test_that("ONBELLEKTEN gelen SIFIR SATIR kaniti da BILDIRILIR", {
  cfg <- .pkh_cfg("sample")
  onbellek <- list(
    ok = TRUE, schema = c(A = "integer"), source_types = c(A = "int"),
    observations = list(),
    sample_info = list(mode = "sample", rows_seen = 0L, from_cache = TRUE),
    cache = list(mode = "sample", columns = c(A = "integer"))
  )

  sonuc <- pkgn_inventory_one(
    query = list(id = "q1", name = "A", sql = "SELECT 1", db_target = "primary"),
    config = cfg, cached = onbellek,
    describe_fn = function(conn, sql) NULL,
    sample_fn = function(conn, sql, n) stop("ornekleme beklenmiyordu")
  )

  kodlar <- vapply(sonuc$record$findings, function(f) f$code, character(1))
  expect_true("sample_zero_rows" %in% kodlar)

  ayrinti <- sonuc$record$findings[[which(kodlar == "sample_zero_rows")]]$detail
  expect_true(grepl("DEVAM ONBELLEGINDEN", ayrinti, fixed = TRUE))
})

# ------------------------------------------------------------------------------
# 11) DB katmanı: mutlak son tarih, sınırlı temizlik, Unicode anahtarı
# ------------------------------------------------------------------------------

test_that("ornek getirimi TEK bir mutlak son tarihi PAYLASIR", {
  skip_if_not_installed("RSQLite")

  butceler <- c()
  eski <- .pkgd_bounded
  withr::defer(assign(".pkgd_bounded", eski, envir = globalenv()))
  assign(".pkgd_bounded", function(fn, timeout_sec = NULL) {
    butceler <<- c(butceler, as.numeric(timeout_sec %||% NA_real_))
    fn()
  }, envir = globalenv())

  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  withr::defer(DBI::dbDisconnect(conn))
  DBI::dbWriteTable(conn, "t", data.frame(a = 1:5))

  cerceve <- pkg_default_sample_fn(conn, "SELECT a FROM t", sample_rows = 5L,
                                   timeout_sec = 30)
  expect_identical(nrow(cerceve), 5L)

  gecerli <- butceler[!is.na(butceler)]
  expect_gt(length(gecerli), 1L)
  # Her cagri TAM butceyi ALMAZ; kalan butce azalarak gider.
  expect_true(all(gecerli <= 30))
  expect_lt(gecerli[length(gecerli)], 30)
})

test_that("sonuc temizligi de SINIRLI calisir", {
  skip_if_not_installed("RSQLite")

  temizlik_sinirlari <- c()
  eski <- .pkgd_bounded
  withr::defer(assign(".pkgd_bounded", eski, envir = globalenv()))
  assign(".pkgd_bounded", function(fn, timeout_sec = NULL) {
    temizlik_sinirlari <<- c(temizlik_sinirlari, as.numeric(timeout_sec %||% NA_real_))
    fn()
  }, envir = globalenv())

  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  withr::defer(DBI::dbDisconnect(conn))
  DBI::dbWriteTable(conn, "t", data.frame(a = 1:2))

  pkg_default_sample_fn(conn, "SELECT a FROM t", sample_rows = 2L, timeout_sec = 30)

  # `dbClearResult()` bloklayabilir; sinirsiz birakilan bu cagri "her bloklayan
  # surucu cagrisi sinirlidir" sozunu curuturdu.
  expect_true(all(!is.na(temizlik_sinirlari)))
})

test_that("ornekleme UNICODE anahtari YAPILANDIRMADAN gelir", {
  # Dogrudan calistirma aninda okunsaydi deger kosu ozetine GIRMEZ ve `0`/`no`
  # gibi bicimler sessizce TRUE anlamina gelirdi.
  withr::with_envvar(c(MERGEN_PK_META_MODE = "sample",
                       MERGEN_PK_META_SAMPLE_UNICODE = "no"), {
    cfg <- pkg_meta_resolve_config(repo_root = tempdir())
    expect_false(cfg$sample_unicode)
    expect_false(pkg_meta_config_summary(cfg)$sample_unicode)
  })

  alinan <- NULL
  cfg <- .pkh_cfg("sample", sample_unicode = FALSE)
  pkgn_fetch_schema(
    query = list(id = "q1", sql = "SELECT 1", db_target = "primary"),
    config = cfg, conn = structure(list(), class = "fake_conn"),
    describe_fn = function(conn, sql) NULL,
    sample_fn = function(conn, sql, n, sample_unicode = TRUE) {
      alinan <<- sample_unicode
      data.frame(A = 1L)
    }
  )
  expect_false(alinan)
})

# ------------------------------------------------------------------------------
# 12) Salt-okunur kapı: opak PASS-THROUGH yapıları
# ------------------------------------------------------------------------------

test_that("opak PASS-THROUGH yapilari kapidan GECMEZ", {
  # Literal maskeleyici pass-through KOMUT METNINI gizler; kapinin bu sinifi
  # ANAHTAR KELIME olarak reddetmesi bu yuzden zorunludur.
  vakalar <- list(
    openrowset_bulk = "SELECT * FROM OPENROWSET(BULK 'c:/x.txt', SINGLE_CLOB) AS x",
    openrowset_exec = paste0(
      "SELECT a.* FROM OPENROWSET('SQLNCLI', 'Server=s;Trusted_Connection=yes;', ",
      "'SET NOCOUNT ON; EXEC dbo.proc') AS a"
    ),
    openquery       = "SELECT * FROM OPENQUERY(LNK, 'EXEC dbo.p')",
    opendatasource  = "SELECT * FROM OPENDATASOURCE('SQLNCLI', 'x').db.dbo.t",
    openxml         = "SELECT * FROM OPENXML(@h, '/x', 1)"
  )

  for (ad in names(vakalar)) {
    sonuc <- pk_sql_classify_readonly(vakalar[[ad]])
    expect_false(isTRUE(sonuc$allowed), info = ad)
    expect_identical(sonuc$reason, "forbidden_keyword", info = ad)
  }

  # Olagan SELECT etkilenmez.
  expect_true(pk_sql_classify_readonly("SELECT 1 AS x")$allowed)
})

# ------------------------------------------------------------------------------
# 13) UÇTAN UCA boru hattı (giriş betiğinin akışı, bootstrap OLMADAN)
# ------------------------------------------------------------------------------

test_that("envanter -> birlestirme -> uzlastirma -> rapor -> yayim zinciri CALISIR", {
  skip_if_not_installed("jsonlite")

  # Giriş betiği `app.R` bootstrap'i gerektirir; burada AYNI adım sırası
  # yardımcılar üzerinden yürütülür. Bu zincir, tek tek yeşil olan ama BİRLİKTE
  # kırılan (şekil uyuşmazlığı, NULL alan serileştirmesi gibi) kusurları yakalar.
  gecici <- withr::local_tempdir()
  dir.create(file.path(gecici, "R"), recursive = TRUE, showWarnings = FALSE)
  artefakt <- file.path(gecici, "artifacts")
  cikti <- file.path(gecici, "R", "library_query_meta_local.R")

  cfg <- .pkh_cfg("describe")
  cfg$repo_root <- gecici
  cfg$output_path <- cikti

  kutuphane <- list(
    list(id = "saglikli", name = "Saglikli", sql = "SELECT 1", db_target = "primary"),
    list(id = "yazma", name = "Yazma", sql = "DELETE FROM T", db_target = "primary"),
    list(id = "kopuk", name = "Kopuk", sql = "SELECT 2", db_target = "primary")
  )

  parmak <- pkgh_state_fingerprints(kutuphane, cfg)

  kosu <- pkg_meta_run_inventory(
    query_library = kutuphane, config = cfg,
    connect_fn = function(target) list(conn = structure(list(), class = "fake_conn")),
    release_fn = function(handle) invisible(NULL),
    describe_fn = function(conn, sql) {
      # `kopuk` icin tanimlayici DUSER (gecici hata sinifi).
      if (identical(sql, "SELECT 2")) stop("[08S01] Communication link failure")
      .pkh_desc(Tutar = "int")
    },
    sample_fn = function(conn, sql, n) stop("ornekleme beklenmiyordu"),
    fingerprints = parmak
  )

  expect_length(kosu$records, 3L)
  durumlar <- stats::setNames(
    vapply(kosu$records, function(r) r$status, character(1)),
    vapply(kosu$records, function(r) r$query_id, character(1))
  )
  expect_identical(unname(durumlar[["saglikli"]]), "ok")
  expect_identical(unname(durumlar[["yazma"]]), "skipped")
  expect_identical(unname(durumlar[["kopuk"]]), "failed")

  # ONCEKI katmanda `kopuk` icin GECERLI metadata vardi; parmak izi uyustugu
  # icin GECICI hatada KORUNUR.
  onceki <- list(kopuk = list(result_schema = c(Eski = "character"),
                              source_fingerprint = parmak[["kopuk"]]))

  birlesme <- pkgc_merge_local_layers(onceki, kosu$local_meta, kosu$records,
                                      fingerprints = parmak)
  expect_true("saglikli" %in% birlesme$replaced)
  expect_true("kopuk" %in% birlesme$kept)

  kayitlar <- pkgh_reconcile_records_with_layer(kosu$records, birlesme$meta)
  ozet <- pkgh_summarize(kayitlar)
  expect_identical(ozet$preserved_previous, 1L)
  expect_identical(ozet$included, 1L)

  # RAPOR ARTEFAKTLARI (BASARISIZ kayit NULL `sample` tasir).
  ozet_cfg <- pkg_meta_config_summary(cfg)
  yollar <- pkgh_write_artifacts(
    report = list(run_id = cfg$run_id, summary = ozet, queries = kayitlar,
                  local_layer_status = "staged"),
    artifact_dir = artefakt, records = kayitlar, summary = ozet,
    config_summary = ozet_cfg
  )
  expect_true(file.exists(yollar$json))
  expect_true(file.exists(yollar$text))

  geri <- jsonlite::fromJSON(yollar$json, simplifyVector = FALSE)
  expect_identical(geri$local_layer_status, "staged")
  expect_length(geri$queries, 3L)

  # ÜRETİLEN KATMAN: hazirla + yayimla.
  metin <- pkgr_render_local_meta_file(birlesme$meta, list(
    mode = cfg$mode, timestamp = cfg$timestamp, artifact_rel = cfg$artifact_rel
  ))
  hazirlanan <- pkgr_stage_local_meta_file(metin, cikti, repo_root = gecici)
  expect_true(file.exists(hazirlanan))
  expect_false(file.exists(cikti))

  pkgr_publish_staged_file(hazirlanan, cikti)
  expect_true(file.exists(cikti))

  ortam <- new.env(parent = globalenv())
  sys.source(cikti, envir = ortam, toplevel.env = globalenv())
  uretilen <- get("pk_query_meta_local", envir = ortam)
  expect_setequal(names(uretilen), c("saglikli", "kopuk"))
  # ANLAMSAL alan URETILMEZ.
  expect_null(uretilen$saglikli$capability)
  expect_null(uretilen$saglikli$grain)

  # DEVAM DURUMU yazilip geri okunabilir.
  durum_yolu <- file.path(gecici, "generator-state.json")
  expect_true(pkgh_write_state(kosu$cache, durum_yolu, cfg$mode, cfg$timestamp))
  onbellek <- pkgh_read_state(durum_yolu, cfg$mode, fingerprints = parmak)
  expect_true("saglikli" %in% names(onbellek))
})

# ------------------------------------------------------------------------------
# 14) Giriş betiğinin çağırdığı HER işlev gerçekten çözülür
# ------------------------------------------------------------------------------

test_that("giris betigindeki TUM islev cagrilari cozulur", {
  # Giriş betiği yalnızca operatörün VM'inde çalışır; oradaki bir yazım hatası
  # ("fonksiyon bulunamadi") ancak gerçek koşuda görülürdü. Bu test, betiğin
  # AYRIŞTIRILMIŞ ağacındaki her çağrı başını, yardımcılar yüklendikten sonra
  # çözülebilirlik açısından sınar -- betiği ÇALIŞTIRMADAN.
  kok <- resolve_repo_root_for_tests()
  ifadeler <- parse(file.path(kok, "tools", "pk", "generate_query_meta.R"),
                    encoding = "UTF-8")

  arg_at <- function(x, i) {
    if (isTRUE(tryCatch(identical(x[[i]], quote(expr = )), error = function(e) FALSE))) {
      return(NULL)
    }
    tryCatch(x[[i]], error = function(e) NULL)
  }

  cagrilar <- character(0)
  gez <- function(x) {
    if (is.call(x)) {
      bas <- x[[1]]
      if (is.name(bas)) cagrilar <<- c(cagrilar, as.character(bas))
      for (i in seq_along(x)) gez(arg_at(x, i))
    } else if (is.pairlist(x) || is.list(x)) {
      for (i in seq_along(x)) gez(arg_at(x, i))
    }
  }
  for (ifade in ifadeler) gez(ifade)
  cagrilar <- unique(cagrilar)

  # Betiğin KENDİ içinde tanımladığı yerel kapamalar.
  yereller <- c("geri_al", "ilerleme", "ara_kayit", "artefaktlari_yaz")

  eksik <- Filter(function(ad) {
    !(ad %in% yereller) && !exists(ad, mode = "function", inherits = TRUE)
  }, cagrilar)

  expect_gt(length(cagrilar), 40L)
  expect_identical(
    eksik, character(0),
    info = sprintf("Giris betiginde cozulemeyen islev(ler): %s",
                   paste(eksik, collapse = ", "))
  )

  # Betiğin kullandığı sözleşme sabitleri de tanımlı olmalıdır.
  for (sabit in c("PKG_META_ARTIFACT_DIR", "PKG_META_OUTPUT_FILE",
                  "PKG_META_STATE_VERSION")) {
    expect_true(exists(sabit, inherits = TRUE), info = sabit)
  }
})

# ============================================================================
# PR #705 incelemesi: üretici sertleştirmeleri
# ============================================================================

test_that("bulgu ayrıntısı mutlak yolları ve kullanıcı adlarını SIZDIRMAZ", {
  # Windows sürücü harfli yol, UNC payı ve POSIX ev dizini.
  # Yollar RUNTIME'DA kurulur: depo taramasi (test-secret-leak-contract.R)
  # kaynak dosyada LITERAL bir kisisel Windows yolu gormemeli.
  win_kok <- paste0("C:", "/", "Users", "/")
  # GERCEK UNC BICIMI: iki bastaki ters bolu + TEK ayirici. R kaynaginda
  # "\\\\" ZATEN iki ters bolu demektir; onceki fikstur bunu iki kez yazip
  # DORT bastaki ters bolu ve IKI ayirici uretiyordu, yani `\\host\share`
  # bicimine capalanmis bir redaksiyon deseni HIC sinanmiyordu.
  unc_kok <- paste0("\\", "\\", "SUNUCU01", "\\", "pay")
  ornekler <- c(
    sprintf("Beyan edilen sql_file COZULEMEDI: '%sAlice/gizli/sorgu.sql'.", win_kok),
    sprintf("Beyan edilen sql_file BOS: '%s\\pk\\sorgu.sql'.", unc_kok),
    "Beyan edilen sql_file OKUNAMIYOR: '/home/operator/pk/sorgu.sql'."
  )

  for (ornek in ornekler) {
    bulgu <- pkgh_finding("sql_file_unresolvable", "blocking", ornek)
    expect_false(grepl("Alice", bulgu$detail, fixed = TRUE))
    expect_false(grepl("SUNUCU01", bulgu$detail, fixed = TRUE))
    expect_false(grepl("operator", bulgu$detail, fixed = TRUE))
    expect_true(grepl("<yol>", bulgu$detail, fixed = TRUE))
    # Bulgunun ANLAMI korunur: kod ve siniflandirma degismez.
    expect_identical(bulgu$code, "sql_file_unresolvable")
    expect_identical(bulgu$severity, "blocking")
  }
})

test_that("bulgu ayrıntısındaki sıradan Türkçe metin bozulmadan kalır", {
  bulgu <- pkgh_finding("role_type_mismatch", "attention",
                        "Sutun 'KalanIscilik_sa' rolu 'measure' ama tipi metindir.")

  expect_true(grepl("KalanIscilik_sa", bulgu$detail, fixed = TRUE))
  expect_true(grepl("measure", bulgu$detail, fixed = TRUE))
})

test_that("başarısız ara kayıt SESSİZ geçmez", {
  cagri <- new.env(parent = emptyenv())
  cagri$n <- 0L
  # Ara kayit BASARISIZ raporlar; envanter devam etmeli ama UYARI basmali.
  checkpoint_fn <- function(cache) {
    cagri$n <- cagri$n + 1L
    FALSE
  }

  # IKI sorgu gerekir. Tek sorguyla, envanter ilk basarisiz ara kayittan HEMEN
  # SONRA dursaydi bile geri cagri calisir ve iki uyari da basilirdi; test
  # "devam ediliyor" iddiasini KANITLAMAZDI. Ikinci sorgunun KAYIT almasi
  # devam etmenin dogrudan kanitidir.
  kutuphane <- list(
    list(id = "qara1", name = "Sentetik-1", sql = "SELECT 1",
         rls_columns = list(masraf_yeri_col = NULL)),
    list(id = "qara2", name = "Sentetik-2", sql = "SELECT 2",
         rls_columns = list(masraf_yeri_col = NULL))
  )

  cikti <- utils::capture.output(
    sonuc <- pkg_meta_run_inventory(
      query_library = kutuphane,
      config = list(mode = "describe", sample_rows = 5L, sql_timeout_sec = 5L,
                    max_result_mb = 1, high_cardinality_threshold = 3L,
                    state_version = 1L, timestamp = "20260101-000000"),
      connect_fn = function(target) NULL,
      release_fn = function(x) invisible(NULL),
      describe_fn = function(conn, sql) NULL,
      sample_fn = function(conn, sql, n) NULL,
      checkpoint_fn = checkpoint_fn
    )
  )

  expect_true(cagri$n >= 1L)
  expect_true(any(grepl("ARA KAYIT BASARISIZ", cikti, fixed = TRUE)))
  expect_true(any(grepl("DEVAM ETTIRILEMEZ", cikti, fixed = TRUE)))

  # ILK ara kayit basarisiz olmasina RAGMEN envanter durmadi: ikinci sorgu da
  # islendi ve KENDI kaydini aldi.
  expect_equal(cagri$n, 2L)
  kimlikler <- vapply(sonuc$records, function(k) as.character(k$query_id)[1],
                      character(1))
  expect_true(all(c("qara1", "qara2") %in% kimlikler))
  expect_true(any(grepl("qara2", cikti, fixed = TRUE)))
})

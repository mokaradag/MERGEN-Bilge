# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-telemetry-privacy-contract.R
# Açıklama: Proje ve Kaynak Analizi telemetrisinin GİZLİLİK sözleşmesi.
#           GERÇEK bir DBI arka ucu (RSQLite, bellek içi) üzerinde çalışır;
#           gerçek SQL Server/ODBC, LLM, tarayıcı, ağ veya GERÇEK gizli değer
#           GEREKMEZ. Testteki anahtarlar çalışma anında üretilen sahte
#           değerlerdir.
#
# Kapsanan sözleşmeler:
#   - MERGEN_PK_LOG_QUESTION_TEXT=false iken ham soru metni tabloya ULAŞMAZ.
#   - Parmak izi ANAHTARLI (HMAC-SHA256) üretilir; düz özet DEĞİLDİR. Sorular
#     sonlu bir proje sözlüğünden geldiği için düşük entropilidir; anahtarsız
#     bir özet, tabloyu okuyabilen biri tarafından aday sorular özetlenerek
#     kırılabilirdi.
#   - Anahtar tanımlı değilse parmak izi HİÇ yazılmaz.
#   - Anahtar rotasyonu: farklı anahtar farklı parmak izi üretir ve anahtar
#     kimliği satırla birlikte saklanır.
#   - Gizli değer (anahtar/DSN/token) telemetri çıktısına sızmaz.
# ==============================================================================

testthat::skip_if_not_installed("DBI")
testthat::skip_if_not_installed("RSQLite")
testthat::skip_if_not_installed("openssl")

local({
  repo_root <- resolve_repo_root_for_tests()

  # `<<-` DEĞİL, AÇIK `assign()`.
  #
  # `<<-` en yakın kapsayan kapsamda ada bakar ve bulamazsa `globalenv()`e
  # yazar; niyet okunmaz ve dosya bitince kalan tanım bir SIZINTIYA dönüşür.
  # Bu dosya üretim PK yardımcılarını ZATEN `globalenv()`e sourceladığı için
  # yedek operatörün de orada olması TUTARLIDIR; kritik olan anlamın ÜRETİMLE
  # BİREBİR AYNI olmasıdır (yalnız `NULL` yedeğe düşer, `R/utils_common.R`).
  if (!exists("%||%", mode = "function", inherits = TRUE)) {
    assign("%||%", function(a, b) if (is.null(a)) b else a, envir = globalenv())
  }

  for (f in c("helpers_pk_config.R", "helpers_pk_provenance.R",
              "helpers_pk_telemetry_record.R",
              # Manifest sirasi: taban dosya once (dinamik source kesfi kaldirildi).
              "helpers_pk_telemetry_base.R", "helpers_pk_telemetry.R")) {
    source(file.path(repo_root, "R", f), encoding = "UTF-8", local = globalenv())
  }
})

# Gizli görünümlü sabit yazmamak için anahtarlar çalışma anında kurulur
# (CLAUDE.md gizli-fikstür kuralı).
.pk_priv_fake_key <- function(suffix = "a") {
  paste0("pk", "-sahte-", "hmac", "-", suffix, "-", strrep("0", 8))
}

.pk_priv_question <- "ELEKTRONIK HARP MODERNIZASYON projesinde kimler gorevli?"

.pk_priv_with_env <- function(envs, code) {
  old <- Sys.getenv(names(envs), unset = NA_character_, names = TRUE)

  set_env <- function(nm, val) {
    if (is.null(val) || is.na(val)) {
      Sys.unsetenv(nm)
    } else {
      do.call(Sys.setenv, stats::setNames(list(as.character(val)), nm))
    }
  }

  on.exit({
    for (nm in names(envs)) set_env(nm, old[[nm]])
  }, add = TRUE)

  for (nm in names(envs)) set_env(nm, envs[[nm]])
  force(code)
}

.pk_priv_conn <- function() {
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  DBI::dbExecute(conn, "
    CREATE TABLE MB_Analiz_Log (
      AnalizLogID        INTEGER PRIMARY KEY AUTOINCREMENT,
      IstekID            TEXT,
      KullaniciID        INTEGER,
      KullaniciAdi       TEXT,
      Motor              TEXT,
      DerinDusunme       INTEGER,
      SoruMetni          TEXT,
      SoruParmakIzi      TEXT,
      ParmakIziAnahtarID TEXT,
      SecilenSorguID     TEXT,
      SecilenSorguAdi    TEXT,
      FiltreDurumu       TEXT,
      FiltreSayisi       INTEGER,
      SatirRlsOncesi     INTEGER,
      SatirYetkiSonrasi  INTEGER,
      SatirFiltreSonrasi INTEGER,
      BozulmaKodlari     TEXT,
      Sonuc              TEXT,
      ToplamSureMs       INTEGER,
      OlusturmaZamani    TEXT NOT NULL
    )
  ")
  conn
}

.pk_priv_info <- function() {
  list(
    request_id = "req-gizlilik", question = .pk_priv_question,
    username = "test.kullanici", user_id = 7L, engine = "v1",
    query_id = "q042", query_name = "Aktivite Rol Atamaları",
    filter_status = "ok_filtered", filters = list(),
    pre_rls_rows = 100L, authorized_rows = 50L, filtered_rows = 5L,
    outcome = "Basarili", duration_ms = 10
  )
}

test_that("varsayılan gizlilik: ham soru metni tabloya hiçbir sütunda ulaşmaz", {
  pk_telemetry_reset_state()
  on.exit(pk_telemetry_reset_state(), add = TRUE)

  conn <- .pk_priv_conn()
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  .pk_priv_with_env(
    list(MERGEN_PK_LOG_QUESTION_TEXT = NULL,
         MERGEN_PK_TELEMETRY = "true",
         MERGEN_PK_TELEMETRY_HMAC_KEY = .pk_priv_fake_key()),
    {
      expect_true(pk_telemetry_log_analysis(.pk_priv_info(), conn))
    }
  )

  row <- DBI::dbGetQuery(conn, "SELECT * FROM MB_Analiz_Log")
  expect_equal(nrow(row), 1L)
  expect_true(is.na(row$SoruMetni[1]))

  # Soru metni HİÇBİR sütunda geçmemeli (yalnızca SoruMetni değil).
  butun_satir <- paste(unlist(lapply(row, as.character)), collapse = " | ")
  expect_false(grepl(.pk_priv_question, butun_satir, fixed = TRUE))
  expect_false(grepl("ELEKTRONIK HARP", butun_satir, fixed = TRUE))

  # Parmak izi yazılmış olmalı.
  expect_false(is.na(row$SoruParmakIzi[1]))
  expect_equal(nchar(row$SoruParmakIzi[1]), 64L)
})

test_that("parmak izi anahtarlı HMAC'tır, düz özet değildir", {
  key <- .pk_priv_fake_key("a")

  fp <- .pk_priv_with_env(
    list(MERGEN_PK_TELEMETRY_HMAC_KEY = key, MERGEN_PK_TELEMETRY_HMAC_KEY_ID = "k7"),
    pk_telemetry_question_fingerprint(.pk_priv_question)
  )

  normalized <- .pk_telemetry_normalize_question(.pk_priv_question)

  beklenen_hmac <- as.character(openssl::sha256(charToRaw(normalized), key = key))
  duz_ozet <- as.character(openssl::sha256(charToRaw(normalized)))

  expect_identical(fp$fingerprint, beklenen_hmac)
  expect_false(identical(fp$fingerprint, duz_ozet))
  expect_identical(fp$key_id, "k7")
})

test_that("anahtar rotasyonu: farklı anahtar farklı parmak izi üretir", {
  fp_a <- .pk_priv_with_env(
    list(MERGEN_PK_TELEMETRY_HMAC_KEY = .pk_priv_fake_key("a")),
    pk_telemetry_question_fingerprint(.pk_priv_question)
  )
  fp_b <- .pk_priv_with_env(
    list(MERGEN_PK_TELEMETRY_HMAC_KEY = .pk_priv_fake_key("b")),
    pk_telemetry_question_fingerprint(.pk_priv_question)
  )

  expect_false(identical(fp_a$fingerprint, fp_b$fingerprint))
})

test_that("anahtar yoksa parmak izi HİÇ yazılmaz", {
  pk_telemetry_reset_state()
  on.exit(pk_telemetry_reset_state(), add = TRUE)

  conn <- .pk_priv_conn()
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  .pk_priv_with_env(
    # `MERGEN_PK_TELEMETRY` SABİTLENİR: koşucu bunu `false` ayarlarsa
    # `pk_telemetry_log_analysis()` SATIR YAZMADAN döner ve `nrow(row) == 1L`
    # iddiası ORTAM yüzünden düşerdi.
    list(MERGEN_PK_TELEMETRY = "true",
         MERGEN_PK_TELEMETRY_HMAC_KEY = NULL, MERGEN_PK_LOG_QUESTION_TEXT = NULL),
    {
      fp <- pk_telemetry_question_fingerprint(.pk_priv_question)
      expect_true(is.na(fp$fingerprint))
      expect_true(is.na(fp$key_id))

      expect_true(pk_telemetry_log_analysis(.pk_priv_info(), conn))
    }
  )

  row <- DBI::dbGetQuery(conn, "SELECT * FROM MB_Analiz_Log")
  # SATIR SAYISI ÖNCE DOĞRULANIR: telemetri fail-soft'tur, hiç satır
  # yazılmazsa `row$SoruMetni[1]` NA olur ve aşağıdaki iddialar KENDİLİĞİNDEN
  # geçerdi; sözleşme YAZILAN bir satır için kanıtlanmalıdır.
  expect_equal(nrow(row), 1L)
  # Ne ham metin ne de parmak izi: anahtar yönetilemiyorsa hiçbir soru izi
  # bırakılmaz (plan §9 açık talimatı).
  expect_true(is.na(row$SoruMetni[1]))
  expect_true(is.na(row$SoruParmakIzi[1]))
})

test_that("açık onayla (=true) ham soru metni saklanabilir", {
  pk_telemetry_reset_state()
  on.exit(pk_telemetry_reset_state(), add = TRUE)

  conn <- .pk_priv_conn()
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  .pk_priv_with_env(
    list(MERGEN_PK_TELEMETRY = "true",
         MERGEN_PK_LOG_QUESTION_TEXT = "true",
         MERGEN_PK_TELEMETRY_HMAC_KEY = .pk_priv_fake_key()),
    expect_true(pk_telemetry_log_analysis(.pk_priv_info(), conn))
  )

  row <- DBI::dbGetQuery(conn, "SELECT * FROM MB_Analiz_Log")
  expect_equal(nrow(row), 1L)
  expect_identical(row$SoruMetni[1], .pk_priv_question)
})

test_that("HMAC anahtarının kendisi telemetri satırına sızmaz", {
  pk_telemetry_reset_state()
  on.exit(pk_telemetry_reset_state(), add = TRUE)

  conn <- .pk_priv_conn()
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  key <- .pk_priv_fake_key("gizli")

  .pk_priv_with_env(
    list(MERGEN_PK_TELEMETRY = "true",
         MERGEN_PK_TELEMETRY_HMAC_KEY = key, MERGEN_PK_LOG_QUESTION_TEXT = "true"),
    expect_true(pk_telemetry_log_analysis(.pk_priv_info(), conn))
  )

  row <- DBI::dbGetQuery(conn, "SELECT * FROM MB_Analiz_Log")
  # BOŞ SONUÇTA `grepl()` HİÇ EŞLEŞMEZ; sızıntı iddiası satır olmadan vacuous'tur.
  expect_equal(nrow(row), 1L)
  butun_satir <- paste(unlist(lapply(row, as.character)), collapse = " | ")
  expect_false(grepl(key, butun_satir, fixed = TRUE))
})

test_that("gizli görünümlü serbest alanlar telemetri kaydına taşınmaz", {
  # Girdiye kazara bir DSN/token benzeri değer gelse bile kayıt yalnızca
  # tanımlı alanları taşır; keyfi alanlar tabloya geçmez.
  sahte_dsn <- paste0("DSN=", "sahte_kaynak", ";UID=", "sahte_kullanici")

  record <- .pk_priv_with_env(
    list(MERGEN_PK_LOG_QUESTION_TEXT = NULL, MERGEN_PK_TELEMETRY_HMAC_KEY = NULL),
    pk_telemetry_build_record(utils::modifyList(
      .pk_priv_info(),
      list(connection_string = sahte_dsn, api_key = "sahte-anahtar")
    ))
  )

  duz <- paste(unlist(lapply(record, as.character)), collapse = " | ")
  expect_false(grepl(sahte_dsn, duz, fixed = TRUE))
  expect_false(grepl("sahte-anahtar", duz, fixed = TRUE))
  expect_false("connection_string" %in% names(record))
  expect_false("api_key" %in% names(record))
})

test_that("soru normalizasyonu yerel ayardan bağımsız aynı parmak izini üretir", {
  # Aynı sorunun boşluk/büyük-küçük harf farkları aynı parmak izini vermeli ki
  # kullanım sayımı anlamlı olsun.
  key <- .pk_priv_fake_key()

  fp1 <- .pk_priv_with_env(
    list(MERGEN_PK_TELEMETRY_HMAC_KEY = key),
    pk_telemetry_question_fingerprint("  Kac  PROJE   var? ")
  )
  fp2 <- .pk_priv_with_env(
    list(MERGEN_PK_TELEMETRY_HMAC_KEY = key),
    pk_telemetry_question_fingerprint("kac proje var?")
  )

  expect_identical(fp1$fingerprint, fp2$fingerprint)

  # Boş/geçersiz soru parmak izi üretmez.
  expect_true(is.na(.pk_priv_with_env(
    list(MERGEN_PK_TELEMETRY_HMAC_KEY = key),
    pk_telemetry_question_fingerprint("   ")
  )$fingerprint))
})

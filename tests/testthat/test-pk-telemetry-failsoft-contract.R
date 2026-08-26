# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-telemetry-failsoft-contract.R
# Açıklama: Proje ve Kaynak Analizi telemetrisinin FAIL-SOFT sözleşmesi.
#           GERÇEK bir DBI arka ucu (RSQLite, bellek içi) üzerinde çalışır;
#           gerçek SQL Server/ODBC, LLM, tarayıcı, ağ veya gizli değer
#           GEREKMEZ.
#
# Bu dosya Faz 0'ın EN KRİTİK testidir. MB_Analiz_Log DDL'i DBA tarafından elle
# uygulanır ama telemetri varsayılan olarak AÇIKTIR; yani uygulama güncellemesi
# DDL'den önce sahaya inebilir. O pencerede telemetri sessizce devre dışı
# kalmalı, ÇALIŞAN v1 analizlerini bozmamalıdır.
#
# Kapsanan sözleşmeler:
#   - Tablo YOKKEN araç TAM çalışır: yazım hata fırlatmaz, alt bilgi üretilir.
#   - INSERT hatası kullanıcı isteğine SIZMAZ.
#   - Tablo hazırlığı SÜREÇ BAŞINA BİR KEZ tespit edilir (tekrar sondalanmaz).
#   - Uyarı istek başına değil, BİR KEZ loglanır.
#   - Tablo varken satır gerçekten yazılır (gözlem işe yarar).
# ==============================================================================

testthat::skip_if_not_installed("DBI")
testthat::skip_if_not_installed("RSQLite")

local({
  repo_root <- resolve_repo_root_for_tests()

  if (!exists("%||%", mode = "function", inherits = TRUE)) {
    `%||%` <<- function(a, b) if (is.null(a)) b else a
  }

  for (f in c("helpers_pk_config.R", "helpers_pk_provenance.R",
              # Etkin yürütme bağlamı: hedef ANAHTARI açıkça verilmediğinde
              # `.pk_telemetry_target_key()` buradan çözülür; üretim çağrı
              # yolunu sınamak için gereklidir.
              "helpers_pk_exec_context.R",
              "helpers_pk_telemetry_record.R",
              # Manifest sırası: taban dosya önce (dinamik source keşfi kaldırıldı).
              "helpers_pk_telemetry_base.R", "helpers_pk_telemetry.R")) {
    source(file.path(repo_root, "R", f), encoding = "UTF-8", local = globalenv())
  }
})

# Test kapsamında log_warn çağrılarını sayan sayaç. Gerçek log_warn varsa
# geçici olarak değiştirilir ve sonunda geri yüklenir.
.pk_tel_with_log_counter <- function(code) {
  counter <- new.env(parent = emptyenv())
  counter$warns <- character(0)

  had_previous <- exists("log_warn", envir = globalenv(), inherits = FALSE)
  previous <- if (had_previous) get("log_warn", envir = globalenv()) else NULL

  assign("log_warn", function(msg, ...) {
    counter$warns <- c(counter$warns, as.character(msg)[1])
    invisible(NULL)
  }, envir = globalenv())

  on.exit({
    if (had_previous) {
      assign("log_warn", previous, envir = globalenv())
    } else {
      rm("log_warn", envir = globalenv())
    }
  }, add = TRUE)

  force(code)
  counter
}

# Faz 0'da tüketilen tam kolon listesiyle gerçek bir SQLite tablosu kurar.
.pk_tel_create_table <- function(conn) {
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
}

.pk_tel_sample_info <- function(...) {
  utils::modifyList(list(
    request_id = "req-1", question = "P1234 projesinin durumu nedir?",
    username = "test.kullanici", user_id = 42L, engine = "v1",
    query_id = "q042", query_name = "Aktivite Rol Atamaları",
    filter_status = "ok_filtered",
    filters = list(list(column = "ProjeKodu", value = "P1234", operation = "exact_match")),
    pre_rls_rows = 41930L, authorized_rows = 12405L, filtered_rows = 312L,
    outcome = "Basarili", duration_ms = 1234
  ), list(...))
}

test_that("MB_Analiz_Log yokken telemetri sessizce devre dışı kalır ve hata fırlatmaz", {
  pk_telemetry_reset_state()
  on.exit(pk_telemetry_reset_state(), add = TRUE)

  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  counter <- .pk_tel_with_log_counter({
    expect_no_error(sonuc <- pk_telemetry_log_analysis(.pk_tel_sample_info(), conn))
    expect_false(sonuc)
  })

  # Tablo yokluğu TAM OLARAK BİR uyarı üretir ve DDL yolunu işaret eder.
  expect_length(counter$warns, 1L)
  expect_true(grepl("MB_Analiz_Log", counter$warns[1], fixed = TRUE))
  expect_true(grepl("docs/sql/2026-08-pk-analiz-log.sql", counter$warns[1], fixed = TRUE))
})

test_that("tablo yokken tekrarlanan analizler tek uyarı üretir (süreç başına bir tespit)", {
  pk_telemetry_reset_state()
  on.exit(pk_telemetry_reset_state(), add = TRUE)

  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  counter <- .pk_tel_with_log_counter({
    for (i in seq_len(5)) {
      expect_false(pk_telemetry_log_analysis(.pk_tel_sample_info(), conn))
    }
  })

  # Uyarı istek başına değil, süreç başına bir kez.
  expect_length(counter$warns, 1L)
})

test_that("hazırlık tespiti önbelleklenir: tablo sonradan oluşsa bile yeniden sondalanmaz", {
  pk_telemetry_reset_state()
  on.exit(pk_telemetry_reset_state(), add = TRUE)

  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  .pk_tel_with_log_counter({
    expect_false(pk_telemetry_table_ready(conn))

    # Tablo sonradan yaratılsa bile önbellek nedeniyle hâlâ FALSE dönmeli;
    # bu, her istekte yeniden sondalanmadığının davranışsal kanıtıdır.
    .pk_tel_create_table(conn)
    expect_false(pk_telemetry_table_ready(conn))

    # Sıfırlamadan sonra yeniden tespit edilir.
    pk_telemetry_reset_state()
    expect_true(pk_telemetry_table_ready(conn))
  })
})

test_that("INSERT hatası kullanıcı isteğine sızmaz", {
  pk_telemetry_reset_state()
  on.exit(pk_telemetry_reset_state(), add = TRUE)

  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  # Sondalama başarılı olacak ama INSERT şema uyuşmazlığından patlayacak.
  DBI::dbExecute(conn, "CREATE TABLE MB_Analiz_Log (AnalizLogID INTEGER PRIMARY KEY)")

  counter <- .pk_tel_with_log_counter({
    expect_true(pk_telemetry_table_ready(conn))
    expect_no_error(sonuc <- pk_telemetry_log_analysis(.pk_tel_sample_info(), conn))
    expect_false(sonuc)

    # Kalıcı bir yazım sorunu logu boğmamalı: ilk hata loglanır, sonrası sessiz.
    for (i in seq_len(4)) {
      expect_false(pk_telemetry_log_analysis(.pk_tel_sample_info(), conn))
    }
  })

  expect_length(counter$warns, 1L)
  expect_true(grepl("yazimi basarisiz", counter$warns[1], fixed = TRUE))
})

test_that("NULL bağlantı ve kapalı telemetri güvenle atlanır", {
  pk_telemetry_reset_state()
  on.exit(pk_telemetry_reset_state(), add = TRUE)

  expect_no_error(sonuc <- pk_telemetry_log_analysis(.pk_tel_sample_info(), NULL))
  expect_false(sonuc)

  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  .pk_tel_create_table(conn)

  old <- Sys.getenv("MERGEN_PK_TELEMETRY", unset = NA_character_)
  on.exit({
    if (is.na(old)) Sys.unsetenv("MERGEN_PK_TELEMETRY") else Sys.setenv(MERGEN_PK_TELEMETRY = old)
  }, add = TRUE)

  Sys.setenv(MERGEN_PK_TELEMETRY = "false")
  expect_false(pk_telemetry_log_analysis(.pk_tel_sample_info(), conn))
  expect_identical(DBI::dbGetQuery(conn, "SELECT COUNT(*) AS n FROM MB_Analiz_Log")$n, 0L)
})

test_that("tablo varken satır gerçekten yazılır ve alanlar doğru yerleşir", {
  pk_telemetry_reset_state()
  on.exit(pk_telemetry_reset_state(), add = TRUE)

  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  .pk_tel_create_table(conn)

  expect_true(pk_telemetry_log_analysis(.pk_tel_sample_info(), conn))

  row <- DBI::dbGetQuery(conn, "SELECT * FROM MB_Analiz_Log")
  expect_equal(nrow(row), 1L)
  expect_identical(row$SecilenSorguID[1], "q042")
  expect_identical(row$FiltreDurumu[1], "ok_filtered")
  expect_identical(row$Sonuc[1], "Basarili")
  expect_identical(row$SatirYetkiSonrasi[1], 12405L)
  expect_identical(row$SatirFiltreSonrasi[1], 312L)

  # Türkçe sorgu adı gidiş-dönüşte bozulmamalı.
  expect_identical(row$SecilenSorguAdi[1], "Aktivite Rol Atamaları")

  # RLS öncesi sayım YALNIZCA burada yaşar (kısıtlı alan).
  expect_identical(row$SatirRlsOncesi[1], 41930L)
})

test_that("tablo yokken bile gözlem katmanı kullanıcıya görünen alt bilgiyi üretir", {
  # Faz 0'ın asıl vaadi: telemetri çalışmasa da araç ve köken alt bilgisi
  # tam çalışır.
  pk_telemetry_reset_state()
  on.exit(pk_telemetry_reset_state(), add = TRUE)

  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  session <- list(userData = new.env(parent = emptyenv()))

  .pk_tel_with_log_counter({
    footer <- pk_analysis_observe(session, conn, .pk_tel_sample_info())
    expect_true(nzchar(footer))
    expect_true(grepl("Analiz Kaynağı", footer, fixed = TRUE))
  })

  # Alt bilgi yuvaya konmuş olmalı ki nihai yanıta iliştirilebilsin.
  expect_true(nzchar(pk_provenance_take(session, request_id = "req-1") %||% ""))
})

test_that("gözlem katmanı hiçbir koşulda hata fırlatmaz", {
  pk_telemetry_reset_state()
  on.exit(pk_telemetry_reset_state(), add = TRUE)

  # Bozuk girdi, NULL oturum ve NULL bağlantı: hepsi sessizce yutulmalı.
  expect_no_error(pk_analysis_observe(NULL, NULL, NULL))
  expect_no_error(pk_analysis_observe(NULL, NULL, list(filter_status = "sacma-durum")))
  expect_no_error(pk_analysis_observe(list(userData = new.env()), NULL, .pk_tel_sample_info()))
})

# HAZIRLIK KARARI VERİTABANI HEDEFİNE GÖRE ANAHTARLANIR.
#
# Tek bir süreç-küresel bit, İLK yoklanan hedefin kararını bütün hedeflere
# dayatıyordu: tablosu OLAN bir hedefte denetim kaydı hiç yazılmıyor ya da
# tablosu OLMAYAN bir hedefte her analizde başarısız bir INSERT tekrarlanıyordu.
test_that("MB_Analiz_Log hazırlık kararı DB HEDEFİ başına tutulur", {
  pk_telemetry_reset_state()
  on.exit(pk_telemetry_reset_state(), add = TRUE)

  cagrilar <- character(0)
  yok_conn <- structure(list(kimlik = "yok"), class = "PKTelemetriYok")
  var_conn <- structure(list(kimlik = "var"), class = "PKTelemetriVar")

  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) {
      cagrilar <<- c(cagrilar, class(conn)[1])
      if (inherits(conn, "PKTelemetriYok")) stop("Invalid object name 'MB_Analiz_Log'.")
      data.frame(AnalizLogID = integer(0))
    },
    .package = "DBI"
  )

  expect_false(pk_telemetry_table_ready(yok_conn, target = "secondary"))
  # DİĞER hedef KENDİ kararını verir; önceki hedefin kararını devralmaz.
  expect_true(pk_telemetry_table_ready(var_conn, target = "primary"))
  # Her hedef için karar ÖNBELLEKLENİR: ikinci çağrı DB'ye gitmez.
  expect_false(pk_telemetry_table_ready(yok_conn, target = "secondary"))
  expect_true(pk_telemetry_table_ready(var_conn, target = "primary"))
  expect_equal(length(cagrilar), 2L)
})

# ÜRETİM ÇAĞRI YOLU: `target` AÇIKÇA VERİLMEZ.
#
# `pk_telemetry_log_analysis()` hedefi `db_target` argümanından ya da etkin
# yürütme bağlamından çözer; `pk_telemetry_table_ready()` çağrısına elle bir
# `target` GEÇİRMEZ. Yalnızca açık `target` ile sınamak, ortam bağlamından
# çözümü hiç çalıştırmıyor ve gerçek yolun `"primary"`ye sabitlenmesi
# fark edilmiyordu.
test_that("hedef VERİLMEDİĞİNDE etkin yürütme bağlamından çözülür", {
  pk_telemetry_reset_state()
  on.exit(pk_telemetry_reset_state(), add = TRUE)

  cagrilar <- character(0)
  yok_conn <- structure(list(kimlik = "yok"), class = "PKTelemetriYok")
  var_conn <- structure(list(kimlik = "var"), class = "PKTelemetriVar")

  testthat::local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) {
      cagrilar <<- c(cagrilar, class(conn)[1])
      if (inherits(conn, "PKTelemetriYok")) stop("Invalid object name 'MB_Analiz_Log'.")
      data.frame(AnalizLogID = integer(0))
    },
    .package = "DBI"
  )

  # 1) Bağlam `secondary` iken karar O hedefe yazılır.
  geri_al <- pk_set_exec_context(query = list(id = "q1", db_target = "secondary"))
  on.exit(geri_al(), add = TRUE)
  expect_false(pk_telemetry_table_ready(yok_conn))

  # 2) Bağlam `primary`ye geçtiğinde KENDİ kararı verilir (devralınmaz).
  geri_al2 <- pk_set_exec_context(query = list(id = "q2", db_target = "primary"))
  on.exit(geri_al2(), add = TRUE)
  expect_true(pk_telemetry_table_ready(var_conn))

  # 3) Kararlar hedef başına ÖNBELLEKLENİR; DB'ye yalnızca iki kez gidilir.
  geri_al3 <- pk_set_exec_context(query = list(id = "q3", db_target = "secondary"))
  on.exit(geri_al3(), add = TRUE)
  expect_false(pk_telemetry_table_ready(yok_conn))
  expect_equal(length(cagrilar), 2L)
})

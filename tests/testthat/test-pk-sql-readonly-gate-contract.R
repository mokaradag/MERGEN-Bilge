# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-sql-readonly-gate-contract.R
# Açıklama: D23 — ifade farkında, kapalı başarısız salt-okunur SQL
#           sınıflandırıcısı. Tümü çevrimdışı ve deterministiktir: gerçek DB,
#           LLM, tarayıcı, SSO, ağ veya gerçek sır KULLANILMAZ. Fixture'lar
#           sentetiktir; gerçek proje/program adı geçmez.
# ==============================================================================

.pk_sql_gate_env <- function() {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(x, y) if (is.null(x)) y else x
  for (.pk_kaynak_dosya in c("helpers_pk_sql_statements.R", "helpers_pk_sql_readonly.R", "helpers_pk_sql_local_temp_batch.R")) source(file.path(repo_root, "R", .pk_kaynak_dosya),
         encoding = "UTF-8", local = env)
  env
}

.pk_sql_read_bytes <- function(rel_path) {
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
  if (is.na(txt)) "" else enc2utf8(txt)
}

# YORUM SATIRLARI ÇIKARILMIŞ KOD METNİ: olumlu bir çağrı taraması, çağrı
# SİLİNSE bile aynı adı ALINTILAYAN bir yorum satırı kaldığında YEŞİL kalırdı;
# bu dosyalar zaten `pk_sql_readonly_guard()` adını anan açıklama taşıyor
# (kardeş çözüm: `.pk_rls_code_only()`, test-pk-rls-failclosed-contract.R).
.pk_sql_code_only <- function(rel_path) {
  satirlar <- strsplit(gsub("\r\n?", "\n", .pk_sql_read_bytes(rel_path)),
                       "\n", fixed = TRUE)[[1]]
  paste(satirlar[!grepl("^\\s*#", satirlar, perl = TRUE, useBytes = TRUE)],
        collapse = "\n")
}

test_that("tek bir salt-okunur SELECT ve CTE+SELECT kabul edilir", {
  env <- .pk_sql_gate_env()

  kabul <- c(
    "SELECT * FROM SentetikTablo",
    "   select a, b from t where x = 1   ",
    "WITH c AS (SELECT 1 AS a) SELECT * FROM c",
    "WITH a AS (SELECT 1 x), b AS (SELECT 2 y) SELECT * FROM a JOIN b ON 1 = 1",
    "(SELECT 1 AS a) UNION ALL (SELECT 2 AS a)",
    "SELECT TOP 10 a, SUM(b) OVER (PARTITION BY c) AS t FROM t WITH (NOLOCK) GROUP BY a, b, c ORDER BY a",
    "SELECT CASE WHEN a > 1 THEN 'x' ELSE 'y' END AS d FROM t CROSS APPLY dbo.f(a)",
    "SELECT * FROM t WHERE x = 1; "
  )

  for (sql in kabul) {
    sonuc <- env$pk_sql_classify_readonly(sql)
    expect_true(
      isTRUE(sonuc$allowed),
      info = sprintf("Gecerli salt-okunur SELECT reddedildi: %s (gerekce=%s)",
                     substr(sql, 1, 60), sonuc$reason %||% "-")
    )
  }
})

test_that("Turkce koseli/tirnakli sutun adlari yanlis pozitif uretmez", {
  env <- .pk_sql_gate_env()

  # Koseli tanimlayici icindeki "Silme"/"Guncelleme" gibi kelimeler ve
  # "]]" kacisi anahtar kelime taramasina GIRMEMELIDIR.
  sqls <- c(
    paste0("SELECT [Silme Tarihi], [Gu", "\u0308", "ncelleme Zamani] FROM [Proje Özeti]"),
    "SELECT \"Insert Tarihi\" FROM t",
    "SELECT [A]]B] FROM t"
  )

  for (sql in sqls) {
    sonuc <- env$pk_sql_classify_readonly(sql)
    expect_true(isTRUE(sonuc$allowed),
                info = sprintf("Tanimlayici icerigi yanlis pozitif uretti: %s", sql))
  }
})

test_that("literal ve yorum icindeki zararsiz anahtar kelimeler yanlis pozitif uretmez", {
  env <- .pk_sql_gate_env()

  sqls <- c(
    "SELECT * FROM t WHERE Aciklama = 'DROP TABLE X'",
    "SELECT * FROM t -- DELETE FROM Y\n",
    "SELECT * FROM t /* MERGE INTO Z */",
    "SELECT * FROM t /* dis /* ic */ hala yorum */",
    "SELECT 'it''s an INSERT' AS a FROM t"
  )

  for (sql in sqls) {
    sonuc <- env$pk_sql_classify_readonly(sql)
    expect_true(isTRUE(sonuc$allowed),
                info = sprintf("Literal/yorum icerigi yanlis pozitif uretti: %s", sql))
  }
})

test_that("tek ifadeli yan etkiler reddedilir (SELECT ... INTO dahil)", {
  env <- .pk_sql_gate_env()

  sonuc <- env$pk_sql_classify_readonly("SELECT * INTO #gecici FROM t")
  expect_false(isTRUE(sonuc$allowed))
  expect_identical(sonuc$reason, "forbidden_keyword")
  expect_identical(sonuc$statement_kind, "INTO")
})

test_that("veri degistiren CTE reddedilir", {
  env <- .pk_sql_gate_env()

  sonuc <- env$pk_sql_classify_readonly(
    "WITH c AS (DELETE FROM t OUTPUT deleted.* ) SELECT * FROM c"
  )
  expect_false(isTRUE(sonuc$allowed))
  expect_identical(sonuc$reason, "forbidden_keyword")
})

test_that("son ifadesi SELECT olmayan CTE reddedilir", {
  env <- .pk_sql_gate_env()

  sonuc <- env$pk_sql_classify_readonly("WITH c AS (SELECT 1 AS a) SEC * FROM c")
  expect_false(isTRUE(sonuc$allowed))
  expect_identical(sonuc$reason, "cte_not_select")
})

test_that("her write/DDL/DCL/backup/execute ailesi reddedilir", {
  env <- .pk_sql_gate_env()

  aile <- c(
    INSERT    = "INSERT INTO t VALUES (1)",
    UPDATE    = "UPDATE t SET a = 1",
    DELETE    = "DELETE FROM t",
    MERGE     = "MERGE t USING s ON 1 = 1 WHEN MATCHED THEN DELETE",
    CREATE    = "CREATE TABLE t (a INT)",
    DROP      = "DROP TABLE t",
    ALTER     = "ALTER TABLE t ADD b INT",
    TRUNCATE  = "TRUNCATE TABLE t",
    GRANT     = "GRANT SELECT ON t TO kullanici",
    DENY      = "DENY SELECT ON t TO kullanici",
    REVOKE    = "REVOKE SELECT ON t FROM kullanici",
    BACKUP    = "BACKUP DATABASE db TO DISK = 'x'",
    RESTORE   = "RESTORE DATABASE db FROM DISK = 'x'",
    EXEC      = "EXEC dbo.BirYordam"
  )

  for (ad in names(aile)) {
    sonuc <- env$pk_sql_classify_readonly(aile[[ad]])
    expect_false(isTRUE(sonuc$allowed), info = sprintf("%s ailesi kabul edildi!", ad))
  }

  # sp_ / xp_ onekleri ayrica engellenir.
  for (sql in c("SELECT * FROM sp_yardimci()", "SELECT * FROM xp_cmdshell")) {
    sonuc <- env$pk_sql_classify_readonly(sql)
    expect_false(isTRUE(sonuc$allowed), info = sql)
    expect_identical(sonuc$reason, "forbidden_prefix")
  }
})

test_that("yalniz SET NOCOUNT ON + tek salt-okunur ifade batch olarak kabul edilir", {
  env <- .pk_sql_gate_env()

  guvenli <- c(
    "SET NOCOUNT ON;\nSELECT * FROM t",
    paste0(
      "-- sentetik baslik\r\n",
      "SET NOCOUNT ON;\r\n",
      "WITH c AS (SELECT 1 AS a) SELECT * FROM c OPTION (RECOMPILE);"
    )
  )

  for (sql in guvenli) {
    sonuc <- env$pk_sql_classify_readonly(sql)
    expect_true(
      isTRUE(sonuc$allowed),
      info = sprintf("Guvenli NOCOUNT oneki reddedildi: gerekce=%s", sonuc$reason %||% "-")
    )
  }

  guvensiz <- c(
    "SET NOCOUNT OFF;\nSELECT * FROM t",
    "SET ANSI_NULLS ON;\nSELECT * FROM t",
    "SET NOCOUNT ON;\nDELETE FROM t",
    "SET NOCOUNT ON;\nSELECT 1; SELECT 2",
    "SET NOCOUNT ON;\nEXEC dbo.BirYordam"
  )

  for (sql in guvensiz) {
    sonuc <- env$pk_sql_classify_readonly(sql)
    expect_false(
      isTRUE(sonuc$allowed),
      info = sprintf("NOCOUNT istisnasi guvensiz batch'i acti: %s", sql)
    )
  }
})

test_that("cok ifadeli batch ve GO ayirici reddedilir", {
  env <- .pk_sql_gate_env()

  cok <- env$pk_sql_classify_readonly("SELECT 1; SELECT 2")
  expect_false(isTRUE(cok$allowed))
  expect_identical(cok$reason, "multiple_statements")
  expect_identical(cok$statement_count, 2L)

  go <- env$pk_sql_classify_readonly("SELECT * FROM t\nGO\nSELECT * FROM u")
  expect_false(isTRUE(go$allowed))
  expect_identical(go$reason, "multiple_statements")
})

test_that("ayristirma belirsizligi KAPALI BASARISIZ olur", {
  env <- .pk_sql_gate_env()

  belirsiz <- list(
    unterminated_literal    = "SELECT * FROM t WHERE x = 'kapanmamis",
    unterminated_comment    = "SELECT * FROM t /* kapanmamis",
    unterminated_identifier = "SELECT [kapanmamis FROM t",
    empty_sql               = "   ",
    not_select              = "TANIMSIZ BIR IFADE"
  )

  for (gerekce in names(belirsiz)) {
    sonuc <- env$pk_sql_classify_readonly(belirsiz[[gerekce]])
    expect_false(isTRUE(sonuc$allowed), info = gerekce)
    expect_identical(sonuc$reason, gerekce)
  }

  expect_false(isTRUE(env$pk_sql_classify_readonly(NULL)$allowed))
  expect_false(isTRUE(env$pk_sql_classify_readonly(NA_character_)$allowed))
})

test_that("guard reddettiginde ham SQL kullaniciya donmez", {
  env <- .pk_sql_gate_env()

  sql <- "DROP TABLE GizliTablo"
  # Gerekce sunucu loguna yazilir; test ciktisini kirletmemesi icin yutulur.
  utils::capture.output(kapi <- env$pk_sql_readonly_guard(sql), type = "output")

  expect_false(isTRUE(kapi$allowed))
  expect_true(nzchar(kapi$message))
  expect_false(grepl("GizliTablo", kapi$message, fixed = TRUE))
  expect_false(grepl("DROP", kapi$message, fixed = TRUE))
})

test_that("kapi TUM PK SQL yurutme yollarinda baglidir (v1 / v2 / derin mod)", {
  modul <- .pk_sql_code_only("R/module_proje_kaynak_analizi.R")
  derin <- .pk_sql_code_only("R/helpers_deep_analysis.R")

  expect_true(
    grepl("pk_sql_readonly_guard(", modul, fixed = TRUE, useBytes = TRUE),
    info = "Ana PK modulu salt-okunur kapisini cagirmalidir."
  )
  expect_true(
    grepl("pk_sql_readonly_guard(", derin, fixed = TRUE, useBytes = TRUE),
    info = "Derin analiz de AYNI kapiyi kullanmalidir."
  )

  # Eski kara liste ve izin veren dogrulayici GERI GELMEMELIDIR.
  #
  # KAYNAK METNI aranir: R dosyasinda regex CIFT ters bolu ile yazilir. Tek ters
  # boluyle yazilan literal desen dosyada HIC bulunamiyor, dolayisiyla eski kapi
  # geri gelse bile bu iddia BOSA gecerdi.
  for (metin in list(modul, derin)) {
    expect_false(
      grepl("\\\\b(DELETE|DROP|TRUNCATE|ALTER)\\\\b", metin, fixed = TRUE, useBytes = TRUE),
      info = "Eski kara liste SQL kapisi geri gelmemelidir."
    )
  }
  expect_false(
    grepl("SELECT|INSERT|UPDATE|DELETE|EXEC", modul, fixed = TRUE, useBytes = TRUE),
    info = "Write formlarini KABUL EDEN eski dogrulayici geri gelmemelidir."
  )

  # Yerel bagimli toupper() ile SQL taramasi geri gelmemelidir (D16).
  expect_false(
    grepl("toupper(sql_query_text)", derin, fixed = TRUE, useBytes = TRUE),
    info = "Yerel bagimli toupper() SQL taramasi geri gelmemelidir."
  )
})

test_that("kapi MERGEN_PK_ENGINE bayragindan BAGIMSIZDIR", {
  metin <- .pk_sql_read_bytes("R/helpers_pk_sql_readonly.R")

  # EKSİK DOSYA OLUMSUZ İDDİALARI KENDİLİĞİNDEN GEÇİRİR: `.pk_sql_read_bytes()`
  # okunamayan dosya için "" döner ve `grepl()` her zaman FALSE olur. Dosya
  # yeniden adlandırılırsa bu güvenlik sözleşmesi HİÇBİR ŞEY doğrulamadan
  # yeşil kalırdı.
  expect_true(nzchar(metin),
              info = "R/helpers_pk_sql_readonly.R okunamadi (sozlesme vacuous).")

  expect_false(
    grepl("MERGEN_PK_ENGINE", metin, fixed = TRUE, useBytes = TRUE),
    info = "Salt-okunur kapisi motor bayragina bagli olmamalidir (kosulsuz)."
  )
  expect_false(
    grepl("pk_engine_is_v2", metin, fixed = TRUE, useBytes = TRUE),
    info = "Salt-okunur kapisi motor bayragina bagli olmamalidir (kosulsuz)."
  )
})

test_that("GO batch ayiricisi CR / LF / CRLF icin AYNI kararı üretir", {
  env <- .pk_sql_gate_env()

  # Derin mod SQL dosyasini HAM okur; Windows/SSMS dosyalari CRLF'tir. Kapi
  # satir sonu ailesine gore FARKLI karar verirse ayni sorgu bir yolda
  # calisir, digerinde "yasakli anahtar kelime" ile reddedilirdi.
  for (eol in c("\n", "\r\n", "\r")) {
    sonuc <- env$pk_sql_classify_readonly(
      paste0("SELECT a FROM SentetikTablo", eol, "GO", eol)
    )
    expect_true(
      isTRUE(sonuc$allowed),
      info = sprintf(
        "Sondaki GO satiri ayiricidir; tek SELECT kabul edilmelidir (eol=%s, gerekce=%s).",
        gsub("\r", "CR", gsub("\n", "LF", eol)), sonuc$reason %||% "-"
      )
    )
  }

  # Gercek cok ifadeli batch her satir sonu ailesinde REDDEDILIR ve gerekce
  # "birden fazla ifade" olarak raporlanir.
  for (eol in c("\n", "\r\n", "\r")) {
    sonuc <- env$pk_sql_classify_readonly(
      paste0("SELECT 1", eol, "GO", eol, "SELECT 2", eol)
    )
    expect_false(
      isTRUE(sonuc$allowed),
      info = "Cok ifadeli batch her satir sonunda reddedilmelidir."
    )
    expect_identical(
      sonuc$reason, "multiple_statements",
      info = sprintf(
        "Gerekce ifade sayisi olmalidir (eol=%s).",
        gsub("\r", "CR", gsub("\n", "LF", eol))
      )
    )
  }
})

test_that("satir yorumu CR / LF / CRLF'in HEPSINDE biter (kapi ACILMAZ)", {
  env <- .pk_sql_gate_env()

  # T-SQL satir yorumunu CR, LF ve CRLF'in hepsi sonlandirir. Durum makinesi
  # yalnizca LF ariyorsa, CR ile biten bir dosyada yorumdan SONRAKI TUM batch
  # de yorum sayilir ve maskelenmis metin "tek salt-okunur SELECT"e benzer:
  # kapali basarisiz kapi SESSIZCE ACILIR. Ana modul metni kapidan once
  # normallestirir ama derin mod SQL dosyasini HAM okur; bu yuzden kapinin
  # kendisi satir sonu ailesinden bagimsiz olmalidir.
  for (eol in c("\n", "\r\n", "\r")) {
    etiket <- gsub("\r", "CR", gsub("\n", "LF", eol))

    sonuc <- env$pk_sql_classify_readonly(
      paste0("SELECT 1 -- zararsiz yorum", eol, "DROP TABLE SentetikTablo")
    )
    expect_false(
      isTRUE(sonuc$allowed),
      info = sprintf("Yorumdan sonraki DROP gizlenmemelidir (eol=%s).", etiket)
    )
    expect_identical(
      sonuc$reason, "forbidden_keyword",
      info = sprintf("Gerekce yasakli anahtar kelime olmalidir (eol=%s).", etiket)
    )

    batch <- env$pk_sql_classify_readonly(
      paste0("SELECT 1 -- zararsiz yorum", eol, "GO", eol, "DELETE FROM SentetikTablo")
    )
    expect_false(
      isTRUE(batch$allowed),
      info = sprintf("Yorumdan sonraki ikinci batch gizlenmemelidir (eol=%s).", etiket)
    )
  }

  # Yorumun MESRU davranisi korunur: yorum yalnizca kendi satirini yutar ve
  # geride kalan tek SELECT kabul edilmeye devam eder.
  for (eol in c("\n", "\r\n", "\r")) {
    sonuc <- env$pk_sql_classify_readonly(
      paste0("-- basliktaki aciklama", eol, "SELECT a FROM SentetikTablo")
    )
    expect_true(
      isTRUE(sonuc$allowed),
      info = sprintf(
        "Bastaki yorum satiri gecerli SELECT'i reddetmemelidir (eol=%s, gerekce=%s).",
        gsub("\r", "CR", gsub("\n", "LF", eol)), sonuc$reason %||% "-"
      )
    )
  }
})

# PR #705: NOKTALI VIRGULSUZ IKINCI IFADE + YERELDEN BAGIMSIZ ANAHTAR KELIME.
#
# T-SQL ifadeler arasinda `;` zorunlu kilmaz: `SELECT 1\nSELECT 2` tek dize
# olarak doner, hicbir yasak-kelime taramasi reddetmez ve boyle bir kutuphane
# sorgusu BIRDEN FAZLA sonuc kumesi uretebilir. Tespit parantez DERINLIGI
# farkindadir; kume islecleri (`UNION [ALL]` / `EXCEPT` / `INTERSECT`) MESRUdur.
test_that("noktali virgulsuz ikinci ust duzey SELECT reddedilir", {
  env <- .pk_sql_gate_env()

  red <- env$pk_sql_classify_readonly("SELECT 1 AS a\nSELECT 2 AS b")
  expect_false(isTRUE(red$allowed))
  expect_identical(red$reason, "multiple_statements")

  # Noktali virgulle ayrilmis ikinci ifade de reddedilmelidir.
  red2 <- env$pk_sql_classify_readonly("SELECT 1 AS a; SELECT 2 AS b")
  expect_false(isTRUE(red2$allowed))
})

test_that("kume islecleri ve alt sorgular YANLIS POZITIF uretmez", {
  env <- .pk_sql_gate_env()

  gecerli <- c(
    "SELECT a FROM t1 UNION SELECT b FROM t2",
    "SELECT a FROM t1 UNION ALL SELECT b FROM t2",
    "SELECT a FROM t1 EXCEPT SELECT b FROM t2",
    "SELECT a FROM t1 INTERSECT SELECT b FROM t2",
    "SELECT a FROM (SELECT b AS a FROM t) x",
    "WITH k AS (SELECT a FROM t) SELECT a FROM k",
    "SELECT a FROM t WHERE EXISTS (SELECT 1 FROM u)"
  )
  for (sql in gecerli) {
    sonuc <- env$pk_sql_classify_readonly(sql)
    expect_true(isTRUE(sonuc$allowed), info = sql)
  }
})

test_that("anahtar kelime esleşmesi yerelden BAGIMSIZDIR (Turkce noktasiz i)", {
  env <- .pk_sql_gate_env()

  # `toupper("intersect")` Turkce yerelde noktali `İ` uretir ve `INTERSECT`
  # islecine eslesmezdi; mesru sorgu "ikinci ifade" sanilip REDDEDILIRDI.
  # BEKLENTI `on.exit()` ICINDE CALISTIRILMAZ. Asagidaki `skip_if()` cereveyi
  # cozerken cikis isleyicisi yine calisir ve testthat, ZATEN atlanmis bir test
  # icin beklenti kaydeder. Ayrica geri yukleme yalnizca cozulme sirasinda
  # dogrulanirsa, basarisiz bir `Sys.setlocale()` cikis isleyicisine atfedilir
  # ve Turkce yerel SONRAKI test dosyalarina SIZAR. Isleyici yalnizca geri
  # yukler; dogrulama TEST GOVDESINDE yapilir.
  eski <- Sys.getlocale("LC_CTYPE")
  on.exit(suppressWarnings(Sys.setlocale("LC_CTYPE", eski)), add = TRUE)

  kuruldu <- ""
  for (loc in c("tr_TR.UTF-8", "tr_TR.utf8", "Turkish_Turkey.1254", "Turkish", "tr_TR")) {
    kuruldu <- suppressWarnings(Sys.setlocale("LC_CTYPE", loc))
    if (nzchar(kuruldu)) break
  }
  testthat::skip_if(!nzchar(kuruldu), "Turkce yerel bu makinede kurulu degil.")

  sonuc <- env$pk_sql_classify_readonly("select a from t1 intersect select b from t2")
  expect_true(isTRUE(sonuc$allowed))

  # GERI YUKLEME GOVDEDE DOGRULANIR: sizan bir `LC_CTYPE` ayni oturumdaki
  # sonraki dosyalarda Turkce karsilastirmalari bozar.
  geri <- suppressWarnings(Sys.setlocale("LC_CTYPE", eski))
  expect_true(nzchar(geri))
  expect_identical(Sys.getlocale("LC_CTYPE"), eski)
})

test_that("CTE SUTUN LISTESI govde taramasini bozmaz", {
  env <- .pk_sql_gate_env()

  # GERİLEME KORUMASI: `WITH c(a,b) AS (SELECT ...) SELECT ...` geçerli
  # T-SQL'dir; ilk üst düzey parantez SÜTUN LİSTESİDİR. Tarayıcı derinlik
  # sıfıra döndüğünde durduğu için `AS (SELECT ...) SELECT ...` döndürüyor ve
  # kapı ifadeyi `cte_not_select` diye reddediyordu — CTE sütun listesi
  # kullanan HER salt-okunur kütüphane sorgusu bloklanırdı.
  for (sql in c(
    "WITH c(a,b) AS (SELECT 1 AS a, 2 AS b) SELECT a, b FROM c",
    "WITH c(a) AS (SELECT 1), d(b) AS (SELECT 2) SELECT a, b FROM c, d",
    "WITH c AS (SELECT 1 AS a) SELECT a FROM c"
  )) {
    sonuc <- env$pk_sql_classify_readonly(sql)
    expect_true(isTRUE(sonuc$allowed), info = sql)
  }

  # KAPI HÂLÂ KAPALI BAŞARISIZDIR: sütun listesi mutasyonu meşrulaştırmaz.
  for (sql in c(
    "WITH c(a) AS (SELECT 1) DELETE FROM T",
    "WITH c(a) AS (SELECT 1) UPDATE T SET x = 1",
    "WITH c(a) AS (INSERT INTO T VALUES (1)) SELECT 1"
  )) {
    sonuc <- env$pk_sql_classify_readonly(sql)
    expect_false(isTRUE(sonuc$allowed), info = sql)
  }
})

# NOKTALI VIRGULSUZ IKINCI IFADE YALNIZCA "IKINCI BIR SELECT" DEGILDIR.
#
# `DISABLE TRIGGER ALL ON DATABASE` gecerli, tek basina calisan ve DURUM
# DEGISTIREN bir T-SQL ifadesidir; hicbir kelimesi denylist'te bulunmaz. Eski
# kapi yalnizca ikinci bir `SELECT` aradigi icin bu batch'i ONAYLIYORDU.
test_that("SELECT sonrasi SELECT DISI ust duzey ifade de reddedilir", {
  env <- .pk_sql_gate_env()

  red <- env$pk_sql_classify_readonly("SELECT 1 AS a\nDISABLE TRIGGER ALL ON DATABASE")
  expect_false(isTRUE(red$allowed))
  expect_identical(red$reason, "multiple_statements")
  expect_identical(red$statement_kind, "disable_trigger")

  acik <- env$pk_sql_classify_readonly("SELECT 1 AS a\nENABLE TRIGGER ALL ON DATABASE")
  expect_false(isTRUE(acik$allowed))
  expect_identical(acik$reason, "multiple_statements")

  # AYRILMIS ifade baslaticilari da (denylist'te olmayanlar) reddedilir.
  for (ifade in c("SELECT 1 AS a\nRETURN", "SELECT 1 AS a\nCHECKPOINT",
                  "SELECT 1 AS a\nWHILE 1=1 BREAK", "SELECT 1 AS a\nREVERT")) {
    sonuc <- env$pk_sql_classify_readonly(ifade)
    expect_false(isTRUE(sonuc$allowed), info = ifade)
  }
})

# YANLIS POZITIF KORUMASI: `OFFSET ... FETCH NEXT ... ROWS ONLY` mesru ve
# yaygin bir SELECT sayfalama bicimidir; `FETCH`/`NEXT` baslatici SAYILMAZ.
test_that("OFFSET/FETCH sayfalamasi ve ayrilmamis takma adlar reddedilmez", {
  env <- .pk_sql_gate_env()

  sayfali <- env$pk_sql_classify_readonly(
    "SELECT a FROM dbo.t ORDER BY a OFFSET 0 ROWS FETCH NEXT 10 ROWS ONLY"
  )
  expect_true(isTRUE(sayfali$allowed))

  # `Enable` AYRILMIS bir kelime degildir; tek basina ifade baslaticisi
  # sayilmamalidir (yalnizca `ENABLE TRIGGER` ikilisi reddedilir).
  takma <- env$pk_sql_classify_readonly("SELECT a AS Enable FROM dbo.t")
  expect_true(isTRUE(takma$allowed))
})

# YANLIS POZITIF KORUMASI: T-SQL duzenli (tirnaksiz) tanimlayicilari Unicode
# HARFLERI icerebilir. ASCII-only sinir + `useBytes` ile taranan metinde `\u015e`
# baytlari "harf degil" sayiliyor, sinir yasakli kelimenin HEMEN oncesinde
# eslesiyor ve GECERLI bir sorgu analizden ONCE reddediliyordu.
test_that("Turkce tanimlayici yasakli metne bitisikken kapi yanlis pozitif uretmez", {
  env <- .pk_sql_gate_env()

  # Yer tutucular parser-guvenli bicimde kurulur (CLAUDE.md 1G).
  s_buyuk <- intToUtf8(0x015EL)   # S with cedilla
  g_buyuk <- intToUtf8(0x011EL)   # G with breve

  gecerli <- c(
    sprintf("SELECT %sDROP FROM dbo.T", s_buyuk),
    sprintf("SELECT %ssp_name FROM dbo.T", s_buyuk),
    sprintf("SELECT %sDELETE, %sUPDATE FROM dbo.T", s_buyuk, g_buyuk),
    sprintf("SELECT T.%sALTER FROM dbo.T AS T", g_buyuk)
  )
  for (ifade in gecerli) {
    sonuc <- env$pk_sql_classify_readonly(ifade)
    expect_true(isTRUE(sonuc$allowed), info = ifade)
  }

  # GERCEK yasakli formlar HALA reddedilir (kapi gevsetilmedi).
  yasakli <- c("DROP TABLE dbo.T", "EXEC sp_who", "SELECT 1; DELETE FROM dbo.T",
               sprintf("SELECT %sDROP FROM dbo.T; DROP TABLE dbo.T", s_buyuk))
  for (ifade in yasakli) {
    sonuc <- env$pk_sql_classify_readonly(ifade)
    expect_false(isTRUE(sonuc$allowed), info = ifade)
  }
})

test_that("parantezli ilk ifade ikinci bir SELECT'i GIZLEMEZ (PR #705 P3)", {
  env <- .pk_sql_gate_env()

  # `(SELECT 1) SELECT 2` icinde ilk SELECT derinlik 1'dedir; tarayici yalnizca
  # TEK bir derinlik-0 SELECT gorup iki ifadeli batch'i tek salt-okunur SELECT
  # diye onayliyordu. DBI o zaman ustveri/RLS yolunun bekledigi sonuc kumesinden
  # BASKASINI tuketir.
  expect_false(isTRUE(env$pk_sql_classify_readonly("(SELECT 1) SELECT 2")$allowed))
  expect_false(isTRUE(env$pk_sql_classify_readonly("((SELECT 1)) SELECT 2")$allowed))

  # MESRU bicimler KABUL edilmeye devam eder.
  for (iyi in c(
    "(SELECT 1)",
    "(SELECT a FROM dbo.t)",
    "(SELECT 1) UNION (SELECT 2)",
    "(SELECT 1) UNION ALL SELECT 2",
    "(SELECT 1) UNION SELECT 2",
    "WITH c AS (SELECT 1 AS a) SELECT a FROM c",
    "WITH c(a) AS (SELECT 1) SELECT a FROM c",
    "SELECT a FROM (SELECT b AS a FROM dbo.t) x"
  )) {
    expect_true(isTRUE(env$pk_sql_classify_readonly(iyi)$allowed), info = iyi)
  }
})

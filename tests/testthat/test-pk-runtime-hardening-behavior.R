# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-runtime-hardening-behavior.R
# Açıklama: PR #714 (CodeRabbit) inceleme bulgularının regresyon sözleşmeleri.
#
#           Tamamen ÇEVRİMDIŞI ve DETERMİNİSTİKtir: gerçek DB, LLM, tarayıcı,
#           SSO sunucusu, ağ ya da gizli değer GEREKMEZ. Üretim SQL'i, proje
#           adı, kullanıcı adı, DSN ya da kimlik bilgisi KULLANILMAZ; tüm
#           fixture'lar sentetiktir.
# ==============================================================================

.pk_hardening_test_env <- function(dosyalar) {
  kok <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L) y else x
  for (dosya in dosyalar) {
    source(file.path(kok, "R", dosya), encoding = "UTF-8", local = env)
  }
  env
}

# --- Bağlantı sırrı redaksiyonu ------------------------------------------------

test_that("suslu parantezli baglanti SIFRESI de maskelenir", {
  env <- .pk_hardening_test_env("utils_log_redact.R")

  # Sentetik degerler; gercek bir DSN/sifre DEGILDIR.
  metin <- paste0("DSN=", "SentetikKaynak", ";Pwd={", "sahte-deger-42", "}")
  cikti <- env$redact_connection_identifiers(metin)

  expect_false(grepl("sahte-deger-42", cikti, fixed = TRUE))
  expect_false(grepl("SentetikKaynak", cikti, fixed = TRUE))
  # ALAN ADI korunur: tani icin "hangi alan" bilgisi yeterlidir.
  expect_true(grepl("Pwd=", cikti, fixed = TRUE))
  expect_true(grepl("DSN=", cikti, fixed = TRUE))

  surucu <- paste0("Driver={ODBC Driver 17};", "Pwd={", "bir;iki", "}")
  expect_false(grepl("bir;iki", env$redact_connection_identifiers(surucu), fixed = TRUE))

  # KACISLI AMA KAPANMAMIS DEGER: `}}` ODBC'de kacislanmis tek `}` demektir.
  # Kesilmis bir surucu tanisinda son kapanis `}` bulunmayabilir; eski desenler
  # bu bicimi HIC maskelemiyor, parola kuyrugu kalici loga yaziliyordu.
  kesik <- paste0("Pwd={", "sahte", "}}", "kuyruk")
  cikti_kesik <- env$redact_connection_identifiers(kesik)
  expect_false(grepl("sahte", cikti_kesik, fixed = TRUE))
  expect_false(grepl("kuyruk", cikti_kesik, fixed = TRUE))
  expect_true(grepl("Pwd=", cikti_kesik, fixed = TRUE))
})

# --- RLS kimlik sınırı ---------------------------------------------------------

.pk_rls_test_env <- function() .pk_hardening_test_env(c("utils_log_redact.R", "helpers_pk_rls_identity.R"))

test_that("noktali/noktasiz I ailesi yetkilendirmede BIRLESTIRILMEZ", {
  env <- .pk_rls_test_env()
  noktasiz <- "Ipek"
  noktali <- paste0(intToUtf8(0x0130), "pek")  # "İpek"

  expect_false(identical(env$.pk_rls_user_key(noktasiz),
                         env$.pk_rls_user_key(noktali)))

  satirlar <- data.frame(
    KullaniciAdi = c(noktasiz, noktali),
    ProjeKodu = c("P-1", "P-2"),
    stringsAsFactors = FALSE
  )
  secilen <- env$.pk_rls_rows_for_user(satirlar, noktasiz)
  expect_equal(nrow(secilen), 1L)
  expect_equal(secilen$ProjeKodu, "P-1")
})

test_that("ASCII buyuk/kucuk harf farki (I DAHIL) hala eslesir", {
  env <- .pk_rls_test_env()
  expect_identical(env$.pk_rls_user_key("AHMET"), env$.pk_rls_user_key("ahmet"))
  # Mevcut dagitim davranisi KORUNUR: ASCII `I` <-> `i` ayni harftir.
  expect_identical(env$.pk_rls_user_key("ALI"), env$.pk_rls_user_key("Ali"))
  # Turkce C/G/O/S/U ciftleri de katlanir.
  expect_identical(env$.pk_rls_user_key(paste0(intToUtf8(0xC7), "AGRI")),
                   env$.pk_rls_user_key(paste0(intToUtf8(0xE7), "agri")))
  # ANCAK `İ`/`ı` ASCII i-ailesine INDIRILMEZ.
  expect_false(identical(env$.pk_rls_user_key(paste0(intToUtf8(0x130), "pek")),
                         env$.pk_rls_user_key("ipek")))
  expect_false(identical(env$.pk_rls_user_key(paste0("K", intToUtf8(0x131), "z")),
                         env$.pk_rls_user_key("Kiz")))
})

test_that("baglanti redaktoru YOKKEN tani metni yayimlanmaz", {
  # `redact_sensitive_text()` sozlesmesi geregi DSN/UID/Server DEGERLERINI
  # KORUR; ona geri dusmek kalici log'a altyapi yazmak olurdu.
  #
  # ORTAM `baseenv()` uzerine kurulur, `globalenv()` uzerine DEGIL: tam paket
  # kosumunda onceki bir test dosyasi `utils_log_redact.R` dosyasini
  # `globalenv()` icine yuklemis olabilir ve `exists(..., inherits = TRUE)` o
  # gercek redaktoru bulup bu KAPALI BASARISIZ yolunu hic calistirmazdi
  # (dosya tek basina GECER, paket icinde DUSER).
  kok <- resolve_repo_root_for_tests()
  env <- new.env(parent = baseenv())
  env$`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L) y else x
  source(file.path(kok, "R", "helpers_pk_rls_identity.R"), encoding = "UTF-8", local = env)
  env$redact_sensitive_text <- function(x) x  # yalnizca genel redaktor var
  cikti <- env$.pk_rls_safe_detail("Server=SentetikSunucu;UID=sentetik")
  expect_equal(cikti, "(redaktor yuklenmedi)")
  expect_false(grepl("SentetikSunucu", cikti, fixed = TRUE))
})

test_that("izin sorgusu sarmalanirken SONDAKI noktali virgul kirpilir", {
  env <- .pk_rls_test_env()
  expect_equal(env$.pk_rls_strip_terminal_semicolon("SELECT a FROM t;"),
               "SELECT a FROM t")
  expect_equal(env$.pk_rls_strip_terminal_semicolon("SELECT a FROM t; \n"),
               "SELECT a FROM t")
  # Govde ICINDEKI noktali virgule DOKUNULMAZ.
  expect_equal(env$.pk_rls_strip_terminal_semicolon("SELECT 'a;b' FROM t"),
               "SELECT 'a;b' FROM t")
})

test_that("sarmalanmis izin sorgusu turetilmis tabloda GECERLI kalir", {
  env <- .pk_rls_test_env()
  gorulen <- new.env(parent = emptyenv())
  env$.pk_rls_bounded_query <- function(conn, statement, params = NULL) {
    gorulen$sql <- statement
    data.frame(KullaniciAdi = "u", ProjeKodu = "P-1", stringsAsFactors = FALSE)
  }
  env$.pk_rls_halt_error <- function(e) FALSE

  env$.pk_rls_permission_rows(NULL, "SELECT KullaniciAdi, ProjeKodu FROM izin;", "u")
  # `... FROM (SELECT ...;) AS t` SQL Server tarafindan REDDEDILIR.
  expect_false(grepl(";\n) AS mb_izin", gorulen$sql, fixed = TRUE))
  expect_true(grepl(") AS mb_izin WHERE mb_izin.KullaniciAdi = ?", gorulen$sql, fixed = TRUE))
})

test_that("gecici surucu hatasi TAM TABLO geri dusmesini TETIKLEMEZ", {
  env <- .pk_rls_test_env()
  sayac <- new.env(parent = emptyenv())
  sayac$n <- 0L
  env$.pk_rls_halt_error <- function(e) FALSE
  env$.pk_rls_bounded_query <- function(conn, statement, params = NULL) {
    sayac$n <- sayac$n + 1L
    if (!is.null(params)) stop("08S01 Communication link failure", call. = FALSE)
    data.frame(KullaniciAdi = "u", stringsAsFactors = FALSE)
  }

  # Gecici hata YUKARI YAYILIR: cagiran onu TIPLI `db_error` olarak raporlar.
  expect_error(env$.pk_rls_permission_rows(NULL, "SELECT 1", "u"),
               "Communication link failure")
  expect_equal(sayac$n, 1L)  # IKINCI tam tablo okumasi YOK
})

test_that("sozdizimi sinifi hata R tarafi geri dusmesine IZIN VERIR", {
  env <- .pk_rls_test_env()
  sayac <- new.env(parent = emptyenv())
  sayac$n <- 0L
  env$.pk_rls_halt_error <- function(e) FALSE
  env$.pk_rls_bounded_query <- function(conn, statement, params = NULL) {
    sayac$n <- sayac$n + 1L
    if (!is.null(params)) stop("[42000] Incorrect syntax near ')'", call. = FALSE)
    data.frame(KullaniciAdi = "u", stringsAsFactors = FALSE)
  }
  cikti <- utils::capture.output(
    satirlar <- env$.pk_rls_permission_rows(NULL, "SELECT 1", "u")
  )
  expect_equal(nrow(satirlar), 1L)
  expect_equal(sayac$n, 2L)
  expect_true(any(grepl("daraltilamadi", cikti, fixed = TRUE)))
})

test_that("yetki reddi mesaji IC KAYNAK ADI sizdirmaz", {
  env <- .pk_rls_test_env()
  mesaj <- env$pk_rls_denied_message(list(authorized = FALSE))
  expect_false(grepl("DC01", mesaj, fixed = TRUE))
  expect_true(grepl("Yetki Hatas", mesaj, fixed = TRUE))
  expect_true(grepl("yönetici", mesaj, fixed = TRUE))
})

# --- Toplama kesinliği ---------------------------------------------------------

test_that("integer64 olcusu 2^53 ustunde KESINLIK kaybetmeden toplanir", {
  skip_if_not_installed("bit64")
  degerler <- bit64::as.integer64(c("9007199254740993", "2", NA))

  # Uretimdeki ESKI yol: `as.numeric()` -> 2^53 ustunu yuvarlar.
  eski <- {
    ham <- suppressWarnings(as.numeric(degerler))
    sonlu <- ham[!is.na(ham) & is.finite(ham)]
    sum(sonlu)
  }
  # YENI yol: `integer64` yerlisi kalir.
  yeni <- {
    gecerli <- degerler[!is.na(degerler)]
    sum(gecerli)
  }

  expect_equal(format(yeni), "9007199254740995")
  expect_false(identical(format(eski, scientific = FALSE), format(yeni)))

  # Tamami NA olan sutun GOZLENMIS bir sifir uretmez.
  bos <- bit64::as.integer64(c(NA, NA))
  expect_true(is.na(if (!length(bos[!is.na(bos)])) NA_real_ else sum(bos[!is.na(bos)])))
})

# --- Ölçü sözleşmesi ve filtre uyarısı ----------------------------------------

.pk_stat_test_env <- function() .pk_hardening_test_env("helpers_pk_statistical_summary.R")

test_that("additive BILDIRILMEMIS bir olcu toplulastirilmaz", {
  env <- .pk_stat_test_env()
  degerler <- c(1.5, 2.5, 3.5)

  acik <- list(x = list(role = "measure", additive = TRUE))
  expect_true(env$.pk_stat_is_measure(degerler, acik, "x"))

  for (eksik in list(
    list(x = list(role = "measure")),
    list(x = list(role = "measure", additive = NA)),
    list(x = list(role = "measure", additive = "evet")),
    list(x = list(role = "measure", additive = c(TRUE, TRUE))),
    list(x = list(role = "measure", additive = FALSE))
  )) {
    expect_false(env$.pk_stat_is_measure(degerler, eksik, "x"))
  }

  # Metadata HIC yoksa davranis DEGISMEZ (yapisal kimlik dislamasi).
  expect_true(env$.pk_stat_is_measure(degerler, NULL, "x"))
})

test_that("v1 terminal geri dusmesi FILTRELEME UYARISINI korur", {
  kok <- resolve_repo_root_for_tests()
  yol <- file.path(kok, "R", "helpers_pk_statistical_summary.R")
  ham <- readBin(yol, "raw", file.info(yol)$size)
  metin <- iconv(rawToChar(ham), from = "UTF-8", to = "UTF-8", sub = "byte")
  metin <- gsub("\r\n", "\n", metin, fixed = TRUE)
  # Terminal geri dusmede uyari ARTIK motor bayragina bagli DEGILDIR.
  expect_false(grepl("if (pk_v2 && isTRUE(user_filter_applied)", metin, fixed = TRUE))
})

# --- Markdown çiti -------------------------------------------------------------

test_that("dort ters tirnakli blok UC tirnakla KAPANMIS sayilmaz", {
  env <- .pk_hardening_test_env("helpers_pk_answer_compose.R")
  metin <- paste("````", "kod ``` icinde siradan metin", sep = "\n")
  kapali <- env$pk_compose_close_markdown(metin)
  satirlar <- strsplit(kapali, "\n", fixed = TRUE)[[1]]
  expect_equal(trimws(satirlar[length(satirlar)]), "````")
})

test_that("bilgi dizeli satir KAPANIS citi sayilmaz", {
  env <- .pk_hardening_test_env("helpers_pk_answer_compose.R")
  metin <- paste("```", "x <- 1", "```r", sep = "\n")
  kapali <- env$pk_compose_close_markdown(metin)
  satirlar <- strsplit(kapali, "\n", fixed = TRUE)[[1]]
  expect_equal(trimws(satirlar[length(satirlar)]), "```")
})

test_that("duzgun kapanmis blok DEGISTIRILMEZ", {
  env <- .pk_hardening_test_env("helpers_pk_answer_compose.R")
  metin <- paste("```python", "x = 1", "```", sep = "\n")
  expect_equal(env$pk_compose_close_markdown(metin), metin)
})

# --- Birim katlaması -----------------------------------------------------------

test_that("kucuk harfli Turkce birim harfleri de katlanir", {
  env <- .pk_hardening_test_env("helpers_pk_numeric_provenance.R")
  gun_tr <- paste0("g", intToUtf8(0xFC), "n")  # "gün"
  expect_identical(env$.pk_prov_unit_fold(gun_tr), env$.pk_prov_unit_fold("gun"))
  kisi_tr <- paste0("ki", intToUtf8(0x15F), "i")  # "kişi"
  expect_identical(env$.pk_prov_unit_fold(kisi_tr), env$.pk_prov_unit_fold("kisi"))
})

# --- Olgu ad alanı -------------------------------------------------------------

.pk_deep_test_env <- function() {
  kok <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L) y else x
  source(file.path(kok, "R", "helpers_pk_packet_stats.R"), encoding = "UTF-8", local = env)
  # `helpers_pk_query_selection_deep.R` üst düzeyde geniş bir bağımlılık
  # zincirine dayanır; burada YALNIZCA saf ad alanı yardımcıları değerlendirilir.
  satirlar <- readLines(file.path(kok, "R", "helpers_pk_query_selection_deep.R"),
                        encoding = "UTF-8", warn = FALSE)
  # CRLF DAYANIKLILIĞI: `readLines()` CRLF çalışma kopyasında satır sonunda
  # `\r` bırakır; TAM EŞİTLİK karşılaştırması o durumda HİÇ eşleşmez ve
  # `satirlar[bas:...]` boş indeks üzerinde değerlendirilirdi.
  satirlar <- sub("\r$", "", satirlar)
  bas <- which(satirlar == ".pk_deep_id_checksum <- function(x) {")
  expect_length(bas, 1L)
  eval(parse(text = paste(satirlar[bas:length(satirlar)], collapse = "\n")), envir = env)
  env
}

test_that("ad alani KISALTILMAMIS sorgu kimligiyle carpismaya dayaniklidir", {
  env <- .pk_deep_test_env()
  # `pk_fact_slug()` ASCII disini `_` yapar ve 60 karakterde KESER.
  expect_identical(env$pk_fact_slug("A-B"), env$pk_fact_slug("A B"))
  expect_false(identical(env$.pk_deep_id_checksum("A-B"),
                         env$.pk_deep_id_checksum("A B")))

  uzun1 <- paste0(strrep("q", 60), "_alfa")
  uzun2 <- paste0(strrep("q", 60), "_beta")
  expect_identical(env$pk_fact_slug(uzun1), env$pk_fact_slug(uzun2))
  expect_false(identical(env$.pk_deep_id_checksum(uzun1), env$.pk_deep_id_checksum(uzun2)))

  # Deterministik ve ASCII.
  expect_identical(env$.pk_deep_id_checksum("q1"), env$.pk_deep_id_checksum("q1"))
  expect_match(env$.pk_deep_id_checksum("q1"), "^[0-9a-f]{8}$")
})

test_that("NA olgu kimligi ad alanlama sirasinda HATA firlatmaz", {
  env <- .pk_deep_test_env()
  sonuc <- env$.pk_deep_namespace_facts(
    "metin [fact:a] son",
    list(list(fact_id = NA_character_), list(fact_id = "a"), list(fact_id = character(0))),
    "q1"
  )
  expect_length(sonuc$facts, 3L)
  expect_true(is.na(sonuc$facts[[1]]$fact_id))
  expect_true(grepl("[fact:q1_", sonuc$text, fixed = TRUE))
})

# --- Eşzamansız istek sözleşmesi ----------------------------------------------

test_that("devralinan varlik baglami request$user_session'dan okunur", {
  kok <- resolve_repo_root_for_tests()
  yol <- file.path(kok, "R", "helpers_pk_async_bootstrap.R")
  ham <- readBin(yol, "raw", file.info(yol)$size)
  metin <- iconv(rawToChar(ham), from = "UTF-8", to = "UTF-8", sub = "byte")
  # `pk_async_build_request()` alani `user_session` adiyla tasir.
  expect_true(grepl(".pk_async_plain_user_data(request$user_session)", metin, fixed = TRUE))
  expect_false(grepl("request$user_session_snapshot", metin, fixed = TRUE))
})

test_that("bekci SOHBET DEGISTIGINDE gonderim durumunu temizler", {
  kok <- resolve_repo_root_for_tests()
  yol <- file.path(kok, "R", "server_handler_pk_async.R")
  ham <- readBin(yol, "raw", file.info(yol)$size)
  metin <- gsub("\r\n", "\n", iconv(rawToChar(ham), from = "UTF-8", to = "UTF-8",
                                    sub = "byte"), fixed = TRUE)
  expect_true(grepl(
    "} else if (isTRUE(karar_bekci$apply) && !isTRUE(ayni_chat_bekci)) {",
    metin, fixed = TRUE))
})

# --- Salt-okunur SQL kapısı ----------------------------------------------------

test_that("SELECT sonrasi UST DUZEY ikinci ifadeler REDDEDILIR", {
  env <- .pk_hardening_test_env(c("helpers_pk_sql_statements.R", "helpers_pk_sql_readonly.R"))
  for (sorgu in c("SELECT 1; SET NOCOUNT ON",
                  "SELECT 1 SET NOCOUNT ON",
                  "SELECT a FROM t SELECT b FROM u",
                  "SELECT a FROM t DECLARE @x INT",
                  "SELECT a FROM t EXEC dbo.p",
                  "SELECT a FROM t BEGIN TRAN",
                  "SELECT a FROM t USE master")) {
    expect_false(isTRUE(env$pk_sql_classify_readonly(sorgu)$allowed), info = sorgu)
  }
  # Mesru tek-ifade bicimleri KABUL edilmeye devam eder.
  for (sorgu in c("SELECT 1",
                  "SELECT a FROM t UNION ALL SELECT b FROM u",
                  "SELECT a FROM (SELECT b FROM u) z",
                  "SET NOCOUNT ON; SELECT a FROM t")) {
    expect_true(isTRUE(env$pk_sql_classify_readonly(sorgu)$allowed), info = sorgu)
  }
})

# NOT: tamamlanmis getirimde tepe projeksiyonunun UYGULANMAMASI DAVRANIS
# duzeyinde `tests/testthat/test-pk-sql-execute-bounded-behavior.R` icinde
# GERCEK bir RSQLite arka uctan kanitlanir (kaynak metni taramak yerine).
# Burada yalnizca surucu sorgusunun var oldugu dogrulanir.
test_that("tepe projeksiyonu surucunun TAMAMLANDI durumunu yoklar", {
  kok <- resolve_repo_root_for_tests()
  yol <- file.path(kok, "R", "helpers_pk_sql_execute.R")
  ham <- readBin(yol, "raw", file.info(yol)$size)
  metin <- gsub("\r\n", "\n", iconv(rawToChar(ham), from = "UTF-8", to = "UTF-8",
                                    sub = "byte"), fixed = TRUE)
  expect_true(grepl("DBI::dbHasCompleted(res)", metin, fixed = TRUE))
})

# --- Metadata üreticisi çitleme kaybı -----------------------------------------

test_that("kilit kaybi ara kayit UYARISINA indirgenmez", {
  env <- .pk_hardening_test_env(character(0))
  kok <- resolve_repo_root_for_tests()
  source(file.path(kok, "tools", "pk", "helpers_meta_generator_run.R"),
         encoding = "UTF-8", local = env)
  expect_equal(env$PKG_META_LOCK_LOST_CLASS, "pkg_meta_lock_lost")

  yol <- file.path(kok, "tools", "pk", "helpers_meta_generator_run.R")
  ham <- readBin(yol, "raw", file.info(yol)$size)
  metin <- iconv(rawToChar(ham), from = "UTF-8", to = "UTF-8", sub = "byte")
  expect_true(grepl("if (inherits(kayit_ok, PKG_META_LOCK_LOST_CLASS)) stop(kayit_ok)",
                    metin, fixed = TRUE))

  yol2 <- file.path(kok, "tools", "pk", "generate_query_meta.R")
  ham2 <- readBin(yol2, "raw", file.info(yol2)$size)
  metin2 <- iconv(rawToChar(ham2), from = "UTF-8", to = "UTF-8", sub = "byte")
  expect_true(grepl("class = c(PKG_META_LOCK_LOST_CLASS,", metin2, fixed = TRUE))
})

# --- Modül yükleyici tutarlılığı ----------------------------------------------

test_that("pk_required_helpers her BILDIRILEN fonksiyonu gercekten yukler", {
  kok <- resolve_repo_root_for_tests()
  satirlar <- readLines(file.path(kok, "R", "module_proje_kaynak_analizi.R"),
                        encoding = "UTF-8", warn = FALSE)
  # CRLF DAYANIKLILIĞI (yukarıdaki tarayıcıyla AYNI gerekçe).
  satirlar <- sub("\r$", "", satirlar)
  bas <- which(satirlar == "pk_required_helpers <- list(")
  expect_length(bas, 1L)
  son <- which(satirlar == ")")
  son <- min(son[son > bas])

  env <- new.env(parent = globalenv())
  eval(parse(text = paste(satirlar[bas:son], collapse = "\n")), envir = env)
  spec_listesi <- env$pk_required_helpers
  expect_true(length(spec_listesi) > 0L)

  for (spec in spec_listesi) {
    hedef <- new.env(parent = globalenv())
    for (yol in spec$path) {
      tam <- file.path(kok, yol)
      expect_true(file.exists(tam), info = yol)
      try(source(tam, encoding = "UTF-8", local = hedef), silent = TRUE)
    }
    for (fn in spec$functions) {
      expect_true(exists(fn, envir = hedef, mode = "function", inherits = FALSE),
                  info = paste(fn, "<-", paste(spec$path, collapse = ",")))
    }
  }
})

# --- Bağlantı hatası sınıflandırması ------------------------------------------

test_that("kucuk harfli surucu imzalari da VERITABANI hatasi sayilir", {
  env <- .pk_hardening_test_env(c("utils_log_redact.R", "helpers_pk_async_worker.R"))
  env$.pk_async_log <- function(...) invisible(NULL)
  for (metin in c("dsn=sentetik baglanti kurulamadi",
                  "odbc surucu hatasi",
                  "sqlstate 08001",
                  "ODBC Driver hatasi")) {
    expect_equal(env$.pk_async_safe_error_text(metin),
                 "Veritabani erisiminde teknik bir hata olustu.", info = metin)
  }
})

test_that("secim hata log'u BAGLANTI redaktorunu kullanir", {
  kok <- resolve_repo_root_for_tests()
  yol <- file.path(kok, "R", "helpers_pk_query_selection_apply.R")
  ham <- readBin(yol, "raw", file.info(yol)$size)
  metin <- iconv(rawToChar(ham), from = "UTF-8", to = "UTF-8", sub = "byte")
  expect_true(grepl("redact_connection_identifiers(metin)", metin, fixed = TRUE))
  expect_false(grepl("redact_sensitive_text(metin)", metin, fixed = TRUE))
})

# --- XLSX doğrulaması ----------------------------------------------------------

test_that("geri okunan buyuk tam sayi BILIMSEL GOSTERIMLE karsilastirilmaz", {
  # Uretimdeki karsilastirma tabani: `as.character(1e15)` -> "1e+15".
  #
  # `scipen` YUKSEKKEN `as.character(1e15)` "1000000000000000" dondurur ve bu
  # kontrol ihrac davranisi hic test edilmeden duserdi; taban yerel olarak
  # sabitlenir. Asagidaki acik `format(..., scientific = FALSE)` iddiasi zaten
  # `scipen` bagimsizdir.
  eski_scipen <- getOption("scipen")
  on.exit(options(scipen = eski_scipen), add = TRUE)
  options(scipen = 0)
  expect_equal(as.character(1e15), "1e+15")
  expect_equal(trimws(format(1e15, scientific = FALSE, trim = TRUE, digits = 22L)),
               "1000000000000000")

  kok <- resolve_repo_root_for_tests()
  yol <- file.path(kok, "R", "helpers_pk_export_plan.R")
  ham <- readBin(yol, "raw", file.info(yol)$size)
  metin <- iconv(rawToChar(ham), from = "UTF-8", to = "UTF-8", sub = "byte")
  expect_true(grepl("scientific = FALSE", metin, fixed = TRUE))
})

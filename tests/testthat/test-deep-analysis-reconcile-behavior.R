# ==============================================================================
# Dosya Yolu: tests/testthat/test-deep-analysis-reconcile-behavior.R
# Açıklama: Faz 6 (D16, §10) — Derin Düşünme uzlaştırma katmanının davranış
#           testleri. Tamamen çevrimdışı: DB, LLM, SSO sunucusu, ağ GEREKMEZ
#           (SQL yürütme testleri GERÇEK RSQLite kullanır).
#
# Kanıtlanan sözleşmeler (D16 sapmalarının KAPATILMASI):
#   - Kimlik ANA YOL ile aynı kapıdan geçer; hazır değilse DB'ye HİÇ gidilmez ve
#     "Unknown" ile RLS araması YAPILMAZ.
#   - SQL kaynağı ÖNYÜKLÜ metindir; istek anında dosya yeniden okunmaz.
#   - SQL yürütme ana yolla aynı Unicode yolunu + Faz 6 sınırlarını kullanır.
#   - Ardışık derin sorgular yalnızca KALAN bütçeyi alır.
#   - Paketler arası aritmetik YASAKTIR ve bu kısıt istem bağlamına yazılır.
# ==============================================================================

.pk_reconcile_env <- function() {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  # ÜRETİM OPERATÖRÜYLE AYNI (`R/utils_common.R`): yalnız `NULL` yedeğe düşer.
  env$`%||%` <- function(a, b) if (is.null(a)) b else a

  for (dosya in c("helpers_pk_config.R", "helpers_pk_async_cancel.R",
                  "helpers_pk_exec_context.R", "helpers_pk_result_columns.R", "helpers_pk_result_size.R", "helpers_pk_sql_execute.R", "helpers_pk_sql_connection.R",
                  "helpers_deep_analysis_sql.R", "helpers_deep_analysis_reconcile.R")) {
    source(file.path(repo_root, "R", dosya), encoding = "UTF-8", local = env)
  }
  env
}

# Yapılandırma anahtarlarını ORTAM VE `options()` katmanlarında birlikte
# yalıtır. `pk_config_resolve()` ortamı `options()` ÖNCESİNDE okur; yalnızca
# birini temizlemek dağıtım değerinin teste sızmasına yeter. Anahtar adı ->
# option adı eşlemesi üretimdeki ASCII katlamayla AYNIdır (Türkçe yerelde
# `tolower("I")` noktasız `ı` üretir).
.pk_recon_option_key <- function(anahtar) {
  if (exists("pk_config_option_key", mode = "function", inherits = TRUE)) {
    return(pk_config_option_key(anahtar))
  }
  paste0("mergen.pk.", chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ",
                              "abcdefghijklmnopqrstuvwxyz",
                              sub("^MERGEN_PK_", "", anahtar)))
}

# BAYAT `withr` ATLAMA MUHAFIZLARI KALDIRILDI: bu dosyadaki hiçbir test
# `withr` çağırmaz; ortam ve `options()` sabitlemesini aşağıdaki yardımcı
# kendisi yapar. `withr` kurulu olmayan bir koşucuda üç SQL zaman aşımı /
# önbellek bütçesi testi, ÇALIŞIP GEÇECEKKEN atlanıyor ve kapsam sessizce
# kayboluyordu.
.pk_recon_with_config <- function(anahtarlar, deger = character(0), code) {
  opsiyonlar <- vapply(anahtarlar, .pk_recon_option_key, character(1),
                       USE.NAMES = FALSE)
  eski_env <- Sys.getenv(anahtarlar, unset = NA_character_, names = TRUE)
  eski_opt <- lapply(opsiyonlar, function(k) getOption(k, default = NULL))
  names(eski_opt) <- opsiyonlar

  on.exit({
    for (ad in names(eski_env)) {
      if (is.na(eski_env[[ad]])) Sys.unsetenv(ad)
      else do.call(Sys.setenv, stats::setNames(list(eski_env[[ad]]), ad))
    }
    do.call(options, eski_opt)
  }, add = TRUE)

  for (ad in anahtarlar) Sys.unsetenv(ad)
  bos <- vector("list", length(opsiyonlar))
  names(bos) <- opsiyonlar
  do.call(options, bos)
  if (length(deger)) do.call(Sys.setenv, as.list(deger))

  force(code)
}

.PK_RECON_CACHE_KEYS <- c(
  "MERGEN_PK_CACHE_MAX_ENTRIES", "MERGEN_PK_CACHE_MAX_MB",
  "MERGEN_PK_CACHE_MAX_ENTRY_MB", "MERGEN_PK_CACHE_TTL_SEC",
  # Onbellek ISABETI de bu tavandan gecer (`pk_cache_entry_within_limit()`,
  # R/helpers_deep_analysis_sql.R): kucuk bir deger disaridan export
  # edildiginde giris gecersiz sayilir, ikinci cagri DUSURULMUS tabloya SQL
  # calistirir ve uretim davranisi DOGRUYKEN test duserdi.
  "MERGEN_PK_MAX_RESULT_MB"
)

# --- D16 (1): KİMLİK ----------------------------------------------------------

test_that("kimlik hazır değilse derin analiz DB'ye HİÇ gitmez", {
  env <- .pk_reconcile_env()
  env$resolve_pk_analysis_username <- function(session) {
    list(ready = FALSE, username = NA_character_, reason = "auth_not_initialized")
  }

  durum <- env$pk_deep_resolve_username(list(userData = list()))
  expect_false(durum$ready)
  expect_true(is.na(durum$username))
  expect_equal(durum$reason, "auth_not_initialized")
  expect_true(grepl("Kimlik Doğrulama Hazırlanıyor", durum$message, fixed = TRUE))
  # KRİTİK: "Unknown" ASLA kullanıcı adı olarak dönmez.
  expect_false(identical(durum$username, "Unknown"))
})

test_that("kimlik hazırsa ana yolun çözdüğü kullanıcı adı kullanılır", {
  env <- .pk_reconcile_env()
  env$resolve_pk_analysis_username <- function(session) {
    list(ready = TRUE, username = "ali.veli", reason = "ok")
  }

  durum <- env$pk_deep_resolve_username(list(userData = list()))
  expect_true(durum$ready)
  expect_equal(durum$username, "ali.veli")
})

test_that("çözümleyici yardımcı yoksa KAPALI BAŞARISIZ olunur", {
  env <- .pk_reconcile_env()
  # Çözümleyici AÇIKÇA yok sayılır. Eski kod bu durumda "Unknown" ile devam
  # ediyordu; bu tam olarak D16'nın kapattığı güvenlik açığıydı.
  #
  # Not: enjeksiyon bilinçlidir — global ortamın "boş" olmasına GÜVENİLMEZ.
  # Tam suite'te başka bir test dosyası `resolve_pk_analysis_username`'i
  # global ortamda bırakabildiği için "yokluk" testi kırılgandı.
  durum <- env$pk_deep_resolve_username(list(userData = list()), resolver = NA)
  expect_false(durum$ready)
  expect_equal(durum$reason, "resolver_missing")
  expect_true(nzchar(durum$message))
})

test_that("enjekte edilen çözümleyici GERÇEKTEN kullanılır", {
  env <- .pk_reconcile_env()
  env$resolve_pk_analysis_username <- function(session) {
    list(ready = TRUE, username = "global.olan", reason = "ok")
  }
  durum <- env$pk_deep_resolve_username(
    list(), resolver = function(session) list(ready = TRUE, username = "enjekte", reason = "ok")
  )
  expect_true(durum$ready)
  expect_equal(durum$username, "enjekte")
})

test_that("çözümleyici hata atarsa da kapalı başarısız olunur", {
  env <- .pk_reconcile_env()
  env$resolve_pk_analysis_username <- function(session) stop("SSO durumu okunamadi")
  durum <- env$pk_deep_resolve_username(list())
  expect_false(durum$ready)
})

# --- D16 (2): SQL KAYNAĞI -----------------------------------------------------

test_that("ÖNYÜKLÜ SQL birincildir; dosya YENİDEN OKUNMAZ", {
  env <- .pk_reconcile_env()
  okundu <- FALSE
  okuyucu <- function(path) {
    okundu <<- TRUE
    "SELECT 'dosyadan' AS kaynak"
  }

  sonuc <- env$pk_deep_query_sql_text(
    list(sql = "SELECT 'onyuklu' AS kaynak", sql_file = "/var/sql/q.sql"),
    read_file_fn = okuyucu
  )

  expect_equal(sonuc$source, "preloaded")
  expect_true(grepl("onyuklu", sonuc$sql, fixed = TRUE))
  # KRİTİK: UNC'de yavaş olan istek-anı dosya okuması YAPILMADI.
  expect_false(okundu)
})

test_that("önyüklü SQL gerçekten boşsa dosyaya düşülür ve kaynak raporlanır", {
  env <- .pk_reconcile_env()
  tmp <- tempfile(fileext = ".sql")
  writeLines("SELECT 'dosyadan' AS kaynak", tmp)
  on.exit(unlink(tmp), add = TRUE)

  sonuc <- env$pk_deep_query_sql_text(
    list(sql = "   ", sql_file = tmp),
    read_file_fn = function(path) paste(readLines(path, warn = FALSE), collapse = "\n")
  )
  expect_equal(sonuc$source, "file")
  expect_true(grepl("dosyadan", sonuc$sql, fixed = TRUE))
})

test_that("SQL hiç yoksa missing raporlanır", {
  env <- .pk_reconcile_env()
  expect_equal(env$pk_deep_query_sql_text(list())$source, "missing")
  expect_equal(env$pk_deep_query_sql_text(list(sql = "", sql_file = ""))$source, "missing")
  expect_equal(
    env$pk_deep_query_sql_text(list(sql = "", sql_file = "/olmayan/dosya.sql"))$source,
    "missing"
  )
})

test_that("SQL normalizasyonu ana yolla AYNIDIR (BOM + satır sonu)", {
  env <- .pk_reconcile_env()
  bom <- intToUtf8(65279L)
  metin <- paste0(bom, "SELECT 1\r\nFROM t\rWHERE x = 1")

  temiz <- env$pk_deep_normalize_sql_text(metin)
  expect_false(startsWith(temiz, bom))
  expect_false(grepl("\r", temiz, fixed = TRUE))
  expect_equal(temiz, "SELECT 1\nFROM t\nWHERE x = 1")
  expect_equal(env$pk_deep_normalize_sql_text(NULL), "")
})

# --- D16 (3): SQL YÜRÜTME + FAZ 6 SINIRLARI ----------------------------------

test_that("derin SQL yürütme gerçek veriyi döner (Unicode olmayan yol)", {
  skip_if_not_installed("RSQLite")
  env <- .pk_reconcile_env()

  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  DBI::dbWriteTable(conn, "veri", data.frame(id = 1:50, ad = paste0("Proje ", 1:50)))

  # VARSAYILAN SABİTLENİR: ortam değişkeni dağıtımda tanımlıysa (VM/CI kabuğu)
  # üretim çözümleyicisi doğru olduğu hâlde test kırılırdı.
  # HER IKI KATMAN YALITILIR (PR #705 incelemesi, P3): `pk_config_resolve()`
  # ortamdan SONRA `options()` okur; salt `with_envvar()` `mergen.pk.sql_timeout_sec`
  # secenegini birakan baska bir testte bu iddiayi kirardi.
  sonuc <- .pk_recon_with_config("MERGEN_PK_SQL_TIMEOUT_SEC", code = {
    env$pk_deep_execute_sql(
      conn, "SELECT * FROM veri", deadline_at = NULL,
      cancel_token = NULL, unicode_param = FALSE
    )
  })

  expect_equal(sonuc$status, "ok")
  expect_equal(sonuc$rows, 50L)
  expect_equal(sonuc$timeout_sec, 120L)   # varsayılan MERGEN_PK_SQL_TIMEOUT_SEC
  expect_equal(sonuc$timeout_reason, "configured")
})

test_that("kalan bütçe tükendiyse ifade GÖNDERİLMEZ", {
  skip_if_not_installed("RSQLite")
  env <- .pk_reconcile_env()

  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  DBI::dbWriteTable(conn, "veri", data.frame(id = 1:5))

  # Son tarih 10 saniye ÖNCE doldu.
  son_tarih <- Sys.time() - 10
  sonuc <- env$pk_deep_execute_sql(
    conn, "SELECT * FROM veri", deadline_at = son_tarih, unicode_param = FALSE
  )

  expect_equal(sonuc$status, "deadline")
  expect_null(sonuc$data)
  expect_equal(sonuc$timeout_reason, "deadline_exhausted")
})

test_that("SQL zaman aşımı kalan bütçeyle SINIRLANIR", {
  skip_if_not_installed("RSQLite")
  env <- .pk_reconcile_env()

  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  DBI::dbWriteTable(conn, "veri", data.frame(id = 1:5))

  # 30 saniye kaldı, yapılandırılmış 120 saniye -> etkin 30 (aşağı yuvarlanmış).
  # VARSAYILAN SABİTLENİR: dağıtım kabuğu `MERGEN_PK_SQL_TIMEOUT_SEC=20`
  # verirse etkin süre YAPILANDIRMADAN gelir, `timeout_reason` "configured"
  # olur ve üretim doğru olduğu hâlde test kırılır.
  sonuc <- .pk_recon_with_config("MERGEN_PK_SQL_TIMEOUT_SEC", code = {
    env$pk_deep_execute_sql(
      conn, "SELECT * FROM veri",
      deadline_at = Sys.time() + 30.9, unicode_param = FALSE
    )
  })

  expect_equal(sonuc$status, "ok")
  expect_true(sonuc$timeout_sec <= 31L)
  expect_equal(sonuc$timeout_reason, "bounded_by_deadline")
})

test_that("sorgu metadata SQL zaman aşımını yükseltir ama son tarihi UZATMAZ", {
  skip_if_not_installed("RSQLite")
  env <- .pk_reconcile_env()

  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  DBI::dbWriteTable(conn, "veri", data.frame(id = 1:5))

  # §9 senaryosu: 600 sn sorgu override'ı, 300 sn analiz bütçesi.
  # Ortam değeri, sorgu override'ından bağımsız olarak taban çözümlemeyi
  # etkilediği için burada da SABİTLENİR.
  sonuc <- .pk_recon_with_config("MERGEN_PK_SQL_TIMEOUT_SEC", code = {
    env$pk_deep_execute_sql(
      conn, "SELECT * FROM veri",
      deadline_at = Sys.time() + 300,
      query_meta = list(sql_timeout_sec = 600L),
      unicode_param = FALSE
    )
  })

  expect_equal(sonuc$status, "ok")
  expect_true(sonuc$timeout_sec <= 300L)
  expect_equal(sonuc$timeout_reason, "bounded_by_deadline")
})

test_that("iptal jetonu derin SQL yürütmeyi durdurur", {
  skip_if_not_installed("RSQLite")
  env <- .pk_reconcile_env()

  kok <- file.path(tempdir(), paste0("pk_deep_", as.integer(runif(1, 1, 1e9))))
  dir.create(kok, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(kok, recursive = TRUE), add = TRUE)

  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  DBI::dbWriteTable(conn, "veri", data.frame(id = 1:100))

  jeton <- env$pk_cancel_token_path("deep_iptal", base_dir = kok)
  env$pk_cancel_token_signal(jeton)

  sonuc <- env$pk_deep_execute_sql(
    conn, "SELECT * FROM veri", cancel_token = jeton, unicode_param = FALSE
  )
  expect_equal(sonuc$status, "cancelled")
})

test_that("ardışık derin sorgular yalnızca KALAN bütçeyi alır", {
  # Beş derin sorgu, 300 sn bütçe, her biri 120 sn yapılandırılmış zaman aşımı.
  env <- .pk_reconcile_env()
  butce <- 300
  kalan <- butce
  etkinler <- integer(0)

  for (i in 1:5) {
    plan <- env$pk_sql_timeout_plan(120, kalan)
    if (!isTRUE(plan$dispatch)) break
    etkinler <- c(etkinler, plan$timeout_sec)
    kalan <- kalan - plan$timeout_sec
  }

  expect_equal(etkinler, c(120L, 120L, 60L))
  expect_lte(sum(etkinler), butce)
})

# --- Derin sorgu tavanı -------------------------------------------------------

test_that("derin sorgu tavanı YAPILANDIRMADAN gelir", {
  env <- .pk_reconcile_env()

  # HER İKİ KATMAN YALITILIR: ortam değişkeni TANIMSIZ olduğunda
  # `pk_config_resolve()` yerleşik varsayılandan ÖNCE `options()` okur; başka
  # bir testin bıraktığı `mergen.pk.deep_max_queries` değeri 5L iddiasını
  # kırar ve test paylaşılan oturum durumuna bağımlı hâle gelirdi.
  .pk_recon_with_config("MERGEN_PK_DEEP_MAX_QUERIES", code = {
    expect_equal(env$pk_deep_max_queries(), 5L)

    Sys.setenv(MERGEN_PK_DEEP_MAX_QUERIES = "3")
    expect_equal(env$pk_deep_max_queries(), 3L)

    # Sorgu metadata global ayarı EZER.
    expect_equal(env$pk_deep_max_queries(list(deep_max_queries = 2L)), 2L)

    # Geçersiz değer varsayılana düşer (sessizce 0 sorgu ÇALIŞTIRILMAZ).
    Sys.setenv(MERGEN_PK_DEEP_MAX_QUERIES = "bogus")
    expect_equal(env$pk_deep_max_queries(), 5L)
  })
})

# --- Paket uzlaştırma ---------------------------------------------------------

test_that("her paket KENDİ kökenini korur", {
  env <- .pk_reconcile_env()
  sonuclar <- list(
    list(query_name = "Kalan İşçilik", success = TRUE, row_count = 120,
         relevance = 92,
         pk_observation = list(query_id = "q001", filter_status = "ok_filtered",
                              pre_rls_rows = 5000, authorized_rows = 900,
                              filtered_rows = 120)),
    list(query_name = "Maliyet Özeti", success = FALSE,
         error_msg = "Yetki dahilinde veri bulunamadı.",
         pk_observation = list(query_id = "q002", filter_status = "not_reached",
                               pre_rls_rows = 3000, authorized_rows = 0,
                               filtered_rows = 0))
  )

  uzlasma <- env$pk_deep_reconcile_packets(sonuclar)

  expect_equal(uzlasma$successful, 1L)
  expect_equal(uzlasma$failed, 1L)
  expect_length(uzlasma$provenance, 2L)
  expect_equal(uzlasma$provenance[[1]]$query_id, "q001")
  expect_equal(uzlasma$provenance[[1]]$authorized_rows, 900)
  expect_equal(uzlasma$provenance[[2]]$query_id, "q002")
  expect_false(uzlasma$provenance[[2]]$success)
  expect_equal(uzlasma$provenance[[2]]$filter_status, "not_reached")
})

test_that("ÇAPRAZ SORGU ARİTMETİĞİ her koşulda YASAKTIR", {
  env <- .pk_reconcile_env()

  # Aynı kırılım (grain) bile İZİN DEĞİLDİR.
  ayni_grain <- list(
    list(query_name = "A", success = TRUE, row_count = 10,
         pk_observation = list(query_id = "q1", grain = "proje")),
    list(query_name = "B", success = TRUE, row_count = 20,
         pk_observation = list(query_id = "q2", grain = "proje"))
  )
  uzlasma <- env$pk_deep_reconcile_packets(ayni_grain)

  expect_false(uzlasma$cross_query_arithmetic_allowed)
  expect_false(uzlasma$comparability$comparable)
  expect_equal(uzlasma$comparability$reason, "distinct_queries_distinct_scopes")

  # Kısıt metni istem bağlamına yazılır ve TOPLAMAYI açıkça yasaklar.
  expect_true(grepl("TOPLAMAYIN", uzlasma$instruction, fixed = TRUE))
  expect_true(grepl("ORTALAMASINI ALMAYIN", uzlasma$instruction, fixed = TRUE))
  expect_true(grepl("grain", uzlasma$instruction, fixed = TRUE))
})

test_that("BİR sorgunun başarısızlığı diğerlerini DÜŞÜRMEZ", {
  env <- .pk_reconcile_env()
  sonuclar <- list(
    list(query_name = "A", success = TRUE, row_count = 5, pk_observation = list(query_id = "q1")),
    list(query_name = "B", success = FALSE, error_msg = "SQL hatası", pk_observation = list(query_id = "q2")),
    list(query_name = "C", success = TRUE, row_count = 7, pk_observation = list(query_id = "q3"))
  )
  uzlasma <- env$pk_deep_reconcile_packets(sonuclar)

  expect_equal(uzlasma$successful, 2L)
  expect_equal(uzlasma$failed, 1L)
  expect_length(uzlasma$packets, 3L)
})

test_that("boş/bozuk girdi güvenli uzlaştırma üretir", {
  env <- .pk_reconcile_env()
  bos <- env$pk_deep_reconcile_packets(list())
  expect_equal(bos$successful, 0L)
  expect_equal(bos$failed, 0L)
  expect_false(bos$cross_query_arithmetic_allowed)
  expect_equal(bos$comparability$reason, "single_packet")

  expect_equal(env$pk_deep_reconcile_packets(NULL)$successful, 0L)
  expect_equal(env$pk_deep_reconcile_packets("metin")$successful, 0L)
})

test_that("kısıt metni istem bağlamında SABİTTİR (yapılandırma anahtarı yok)", {
  env <- .pk_reconcile_env()
  # Çapraz aritmetiği açan bir env/options anahtarı OLMAMALIDIR: uyumluluğu
  # kanıtlanmadan yapılan toplama kullanıcıya kendinden emin YANLIŞ sayı verir.
  Sys.setenv(MERGEN_PK_CROSS_QUERY_ARITHMETIC = "true")
  on.exit(Sys.unsetenv("MERGEN_PK_CROSS_QUERY_ARITHMETIC"), add = TRUE)
  options(mergen.pk.cross_query_arithmetic = TRUE)
  on.exit(options(mergen.pk.cross_query_arithmetic = NULL), add = TRUE)

  uzlasma <- env$pk_deep_reconcile_packets(list(
    list(query_name = "A", success = TRUE, pk_observation = list(query_id = "q1")),
    list(query_name = "B", success = TRUE, pk_observation = list(query_id = "q2"))
  ))
  expect_false(uzlasma$cross_query_arithmetic_allowed)
})

# --- SONUÇ ÖNBELLEĞİ (§5.10: takip soruları anında) --------------------------

test_that("önbellek anahtarı YETKİ İMZASINI taşır ve SQL metnini içerir", {
  env <- .pk_reconcile_env()
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_pk_cache_key.R"),
         encoding = "UTF-8", local = env)
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_pk_cache.R"),
         encoding = "UTF-8", local = env)

  q <- list(id = "q001", db_target = "primary")
  r1 <- list(authorized = TRUE, username = "ali", projects = c("P1"))
  r2 <- list(authorized = TRUE, username = "veli", projects = c("P1"))

  k1 <- env$pk_query_result_cache_key(q, r1, "SELECT 1")
  k2 <- env$pk_query_result_cache_key(q, r2, "SELECT 1")
  k3 <- env$pk_query_result_cache_key(q, r1, "SELECT 2")

  expect_true(nzchar(k1))
  expect_false(identical(k1, k2))  # farklı yetki kapsamı
  expect_false(identical(k1, k3))  # SQL metni değişti -> deterministik geçersizleştirme
  expect_identical(k1, env$pk_query_result_cache_key(q, r1, "SELECT 1"))
})

test_that("kimlik/kapsam/SQL eksikse önbellek ATLANIR (boş anahtar)", {
  env <- .pk_reconcile_env()
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_pk_cache_key.R"),
         encoding = "UTF-8", local = env)
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_pk_cache.R"),
         encoding = "UTF-8", local = env)

  yetkili <- list(authorized = TRUE, username = "ali")
  expect_equal(env$pk_query_result_cache_key(list(), yetkili, "SELECT 1"), "")
  expect_equal(env$pk_query_result_cache_key(list(id = "q1"), yetkili, ""), "")
  # Yetkisiz veya kapsamsız istek ASLA önbelleğe girmez.
  expect_equal(env$pk_query_result_cache_key(list(id = "q1"), list(authorized = FALSE), "SELECT 1"), "")
  expect_equal(env$pk_query_result_cache_key(list(id = "q1"), NULL, "SELECT 1"), "")
})

test_that("önbellek isabeti SQL'i ATLAR ama sonucu birebir döner", {
  skip_if_not_installed("RSQLite")
  env <- .pk_reconcile_env()
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_pk_cache_key.R"),
         encoding = "UTF-8", local = env)
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_pk_cache.R"),
         encoding = "UTF-8", local = env)
  env$pk_cache_reset()
  on.exit(env$pk_cache_reset(), add = TRUE)

  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  DBI::dbWriteTable(conn, "veri", data.frame(id = 1:25, ad = paste0("P", 1:25)))

  anahtar <- env$pk_query_result_cache_key(
    list(id = "q001"), list(authorized = TRUE, username = "ali"), "SELECT * FROM veri"
  )

  # ÖNBELLEK SINIRLARI SABİTLENİR: dağıtım `MERGEN_PK_CACHE_MAX_MB=0` ya da
  # `MERGEN_PK_CACHE_TTL_SEC=0` verirse giriş HİÇ saklanmaz, ikinci çağrı
  # silinmiş tabloya gider ve üretim doğru olduğu hâlde test kırılır.
  .pk_recon_with_config(.PK_RECON_CACHE_KEYS, code = {
    ilk <- env$pk_deep_execute_sql(conn, "SELECT * FROM veri", unicode_param = FALSE,
                                   cache_key = anahtar)
    expect_equal(ilk$status, "ok")
    expect_false(isTRUE(ilk$cached))
    expect_equal(ilk$rows, 25L)

    # Tabloyu SİL: ikinci çağrı SQL çalıştırsaydı hata verirdi.
    DBI::dbExecute(conn, "DROP TABLE veri")

    ikinci <- env$pk_deep_execute_sql(conn, "SELECT * FROM veri", unicode_param = FALSE,
                                      cache_key = anahtar)
    expect_equal(ikinci$status, "ok")
    expect_true(isTRUE(ikinci$cached))
    expect_equal(ikinci$timeout_reason, "cache_hit")
    expect_equal(ikinci$rows, 25L)
    expect_identical(ikinci$data, ilk$data)
  })
})

test_that("BAŞARISIZ sonuç önbelleğe ALINMAZ", {
  skip_if_not_installed("RSQLite")
  env <- .pk_reconcile_env()
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_pk_cache_key.R"),
         encoding = "UTF-8", local = env)
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_pk_cache.R"),
         encoding = "UTF-8", local = env)
  env$pk_cache_reset()
  on.exit(env$pk_cache_reset(), add = TRUE)

  kok <- file.path(tempdir(), paste0("pk_cache_neg_", as.integer(runif(1, 1, 1e9))))
  dir.create(kok, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(kok, recursive = TRUE), add = TRUE)

  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  DBI::dbWriteTable(conn, "veri", data.frame(id = 1:5))

  anahtar <- env$pk_query_result_cache_key(
    list(id = "q001"), list(authorized = TRUE, username = "ali"), "SELECT * FROM veri"
  )
  jeton <- env$pk_cancel_token_path("negatif", base_dir = kok)
  env$pk_cancel_token_signal(jeton)

  iptal <- env$pk_deep_execute_sql(conn, "SELECT * FROM veri", unicode_param = FALSE,
                                   cancel_token = jeton, cache_key = anahtar)
  expect_equal(iptal$status, "cancelled")
  # Bir kez iptal edilen sorgu KALICI olarak "boş sonuç" gibi davranmamalıdır.
  expect_false(env$pk_cache_get(anahtar)$hit)

  env$pk_cancel_token_clear(jeton)
  temiz <- env$pk_deep_execute_sql(conn, "SELECT * FROM veri", unicode_param = FALSE,
                                   cache_key = anahtar)
  expect_equal(temiz$status, "ok")
  expect_equal(temiz$rows, 5L)
})

test_that("anahtar YOKSA önbellek hiç kullanılmaz", {
  skip_if_not_installed("RSQLite")
  env <- .pk_reconcile_env()
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_pk_cache_key.R"),
         encoding = "UTF-8", local = env)
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_pk_cache.R"),
         encoding = "UTF-8", local = env)
  env$pk_cache_reset()
  on.exit(env$pk_cache_reset(), add = TRUE)

  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  DBI::dbWriteTable(conn, "veri", data.frame(id = 1:5))

  sonuc <- env$pk_deep_execute_sql(conn, "SELECT * FROM veri", unicode_param = FALSE)
  expect_equal(sonuc$status, "ok")
  expect_false(isTRUE(sonuc$cached))
  expect_equal(env$pk_cache_stats()$entries, 0L)
})

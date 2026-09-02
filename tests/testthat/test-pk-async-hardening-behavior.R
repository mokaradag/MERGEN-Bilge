# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-async-hardening-behavior.R
# Açıklama: Faz 6 async sertleştirme incelemesindeki P0/P1/P2 bulgularının
#           DAVRANIŞ regresyon testleri. Tamamen ÇEVRİMDIŞI: gerçek DB, LLM,
#           tarayıcı, SSO veya ağ YOKTUR.
#
# Bu dosya bulguları KÖK NEDENE göre gruplar; her grup, bulgunun tarif ettiği
# YANLIŞ davranışın artık üretilemediğini kanıtlar.
# ==============================================================================

local({
  repo_root <- resolve_repo_root_for_tests()
  if (!exists("%||%", mode = "function", inherits = TRUE)) {
    `%||%` <<- function(a, b) if (is.null(a)) b else a
  }
  if (!exists("log_warn", mode = "function", inherits = TRUE)) {
    log_warn <<- function(...) invisible(NULL)
  }
  if (!exists("log_info", mode = "function", inherits = TRUE)) {
    log_info <<- function(...) invisible(NULL)
  }

  yukle <- function(...) source(file.path(repo_root, "R", ...),
                                encoding = "UTF-8", local = globalenv())

  yukle("helpers_pk_config.R")
  yukle("helpers_pk_async_cancel.R")
  yukle("helpers_pk_exec_context.R")
  yukle("helpers_pk_cancel_http.R")
  yukle("helpers_pk_result_columns.R")
  yukle("helpers_pk_result_size.R")
  yukle("helpers_pk_cache_key.R")
  yukle("helpers_pk_cache.R")
  yukle("helpers_pk_async_worker_env.R")
  yukle("helpers_pk_async_bootstrap_fs.R")
  yukle("helpers_pk_async_worker_pool.R")
  yukle("helpers_pk_async_snapshot.R")
  yukle("helpers_pk_async_secrets.R")  # işçiye taşınan sırlar: anlık görüntüden SONRA
  yukle("helpers_pk_async_probe.R")
  yukle("helpers_pk_async_plan.R")
  yukle("helpers_pk_async_request.R")
  yukle("helpers_pk_analysis_query_selection.R")
  yukle("helpers_pk_async_marker_store.R")  # süreç-yerel ayna: sahip dosyadan ÖNCE
  yukle("helpers_pk_async_request_markers.R")
  yukle("helpers_pk_async_session_registry.R")
  yukle("helpers_pk_async_routing.R")
  yukle("helpers_db_connection.R")
  # `pk_async_worker_globals()` bootstrap giriş noktalarını da paketler;
  # globals KAPALILIK testi için bunlar YÜKLÜ olmalıdır.
  yukle("config_source_manifest.R")
  yukle("helpers_pk_async_bootstrap.R")
})

# Yazılabilir sahte oturum: `userData` gerçek bir ORTAMDIR.
.pk_hard_session <- function(writable = TRUE) {
  ud <- new.env(parent = emptyenv())
  # Kancalar ORTAMDA tutulur: liste kopyalama semantiği yüzünden çağıranın
  # gördüğü nesne aksi hâlde güncellenmezdi.
  kanca_deposu <- new.env(parent = emptyenv())
  kanca_deposu$liste <- list()
  oturum <- list(
    token = paste0("tok_", sample.int(1e6, 1L)),
    userData = if (isTRUE(writable)) ud else .pk_hard_readonly_userdata(),
    .kancalar = kanca_deposu
  )
  oturum$onSessionEnded <- function(fn) {
    kanca_deposu$liste[[length(kanca_deposu$liste) + 1L]] <- fn
    invisible(TRUE)
  }
  oturum
}

# YAZILAMAYAN `userData`: gerçek dünyada yıkılmakta olan oturumlar ve bazı
# sahte/salt-okunur uygulamalar yazımı reddeder veya yutar. KİLİTLİ bir ortam
# bunu S3 hilesi olmadan, gerçek R semantiğiyle üretir.
.pk_hard_readonly_userdata <- function() {
  ud <- new.env(parent = emptyenv())
  lockEnvironment(ud, bindings = TRUE)
  ud
}

# ------------------------------------------------------------------------------
# 1) ASENKRON KILL SWITCH TEK YÖNLÜDÜR
# ------------------------------------------------------------------------------

test_that("küresel MERGEN_PK_ASYNC=false sorgu metadata'sıyla YENİDEN AÇILAMAZ", {
  eski <- Sys.getenv("MERGEN_PK_ASYNC", unset = NA_character_)
  on.exit({
    if (is.na(eski)) Sys.unsetenv("MERGEN_PK_ASYNC") else Sys.setenv(MERGEN_PK_ASYNC = eski)
  }, add = TRUE)

  Sys.setenv(MERGEN_PK_ASYNC = "false")
  expect_false(pk_async_enabled(NULL))
  # Metadata AÇMAYA çalışıyor: küresel geri alma sınırı KIRILAMAZ.
  expect_false(pk_async_enabled(list(async = TRUE)))
  expect_identical(pk_async_available(list(async = TRUE))$reason, "flag_off")
})

test_that("küresel AÇIKKEN sorgu metadata'sı YALNIZCA sıkılaştırabilir", {
  eski <- Sys.getenv("MERGEN_PK_ASYNC", unset = NA_character_)
  on.exit({
    if (is.na(eski)) Sys.unsetenv("MERGEN_PK_ASYNC") else Sys.setenv(MERGEN_PK_ASYNC = eski)
  }, add = TRUE)

  Sys.setenv(MERGEN_PK_ASYNC = "true")
  expect_true(pk_async_enabled(NULL))
  expect_false(pk_async_enabled(list(async = FALSE)))
  # Muafiyet `flag_off` DEĞİL AYRI raporlanır: degrade yolda Faz 6 sınırları
  # uygulanmalıdır.
  expect_identical(pk_async_available(list(async = FALSE))$reason, "query_opt_out")
})

test_that("yönlendirme muafiyeti SEMANTİK istemde de bulunur (alt dize aramaz)", {
  kutuphane <- list(
    list(id = "q1", name = "Butce Asim Raporu",
         description = "proje butce maliyet asim analizi",
         meta = list(async = FALSE)),
    list(id = "q2", name = "Kaynak Listesi",
         description = "personel ekip kaynak listesi", meta = list())
  )
  eski_kutuphane <- get0("query_library", envir = globalenv(), inherits = FALSE)
  assign("query_library", kutuphane, envir = globalenv())
  on.exit({
    if (is.null(eski_kutuphane)) {
      suppressWarnings(rm("query_library", envir = globalenv()))
    } else {
      assign("query_library", eski_kutuphane, envir = globalenv())
    }
  }, add = TRUE)

  # ÜRETİMİN GERÇEKTEN TAŞIDIĞI ALAN: `server_send_message.R` bağlamı
  # `user_message_text` kurar. Yalnızca `user_prompt` sınanırsa, üretim alanının
  # okunması kaldırıldığında test YEŞİL kalır ve muafiyet sessizce ölür.
  # İstem sorgu ADINI İÇERMEZ; eski alt-dize yaklaşımı muafiyeti KAÇIRIRDI.
  meta <- mergen_pk_routing_query_meta(
    list(user_message_text = "bu yilki butce asimlarini goster")
  )
  expect_true(is.list(meta))
  expect_false(isTRUE(meta$async))

  # Geriye dönük `user_prompt` yedeği de çalışmaya devam eder.
  meta_yedek <- mergen_pk_routing_query_meta(
    list(user_prompt = "bu yilki butce asimlarini goster")
  )
  expect_true(is.list(meta_yedek))
  expect_false(isTRUE(meta_yedek$async))

  # İlgisiz istem muafiyet ÜRETMEZ.
  expect_null(mergen_pk_routing_query_meta(list(user_message_text = "merhaba nasilsin")))
  expect_null(mergen_pk_routing_query_meta(list(user_prompt = "merhaba nasilsin")))
})

# ------------------------------------------------------------------------------
# 2) FUTURE PLANI: workers = 1 ile I(1) AYRIDIR
# ------------------------------------------------------------------------------

test_that("sıradan sayısal tek işçi REDDEDİLİR, AsIs I(1) kabul edilir", {
  expect_true(.pk_async_spec_is_plain_single(1))
  expect_true(.pk_async_spec_is_plain_single(1L))
  expect_false(.pk_async_spec_is_plain_single(I(1)))
  expect_false(.pk_async_spec_is_plain_single(2))
  expect_false(.pk_async_spec_is_plain_single(NULL))
  expect_false(.pk_async_spec_is_plain_single("localhost"))
})

# ------------------------------------------------------------------------------
# 3) OTURUM DURUMU KALICILIĞI KAPALI BAŞARISIZDIR
# ------------------------------------------------------------------------------

test_that("pk_session_state_write yazımı GERİ OKUYARAK doğrular", {
  ok_oturum <- .pk_hard_session(writable = TRUE)
  expect_true(pk_session_state_write(ok_oturum, "x", c("a", "b")))
  expect_identical(ok_oturum$userData[["x"]], c("a", "b"))

  yutan <- .pk_hard_session(writable = FALSE)
  expect_false(pk_session_state_write(yutan, "x", "deger"))
})

test_that("jeton sahipliği KALICI DEĞİLSE kayıt BAŞARISIZ döner", {
  pk_request_markers_reset()
  yutan <- .pk_hard_session(writable = FALSE)
  expect_false(isTRUE(mergen_pk_register_cancel_token(yutan, "req-A")))
  # Sahiplik görünmediği için Durdur gözlemcisi bu istek için jeton YAZMAZ.
  expect_false(mergen_pk_request_has_cancel_token(yutan, "req-A"))
})

test_that("sahiplik kaldırma YAZILAMASA BİLE veto eder", {
  pk_request_markers_reset()
  oturum <- .pk_hard_session(writable = TRUE)
  expect_true(isTRUE(mergen_pk_register_cancel_token(oturum, "req-B")))
  expect_true(mergen_pk_request_has_cancel_token(oturum, "req-B"))

  # `userData` yazımı artık yutuluyormuş gibi davranmak yerine, süreç-yerel
  # vetonun TEK BAŞINA yeterli olduğu kanıtlanır.
  expect_true(isTRUE(mergen_pk_unregister_cancel_token(oturum, "req-B")))
  expect_false(mergen_pk_request_has_cancel_token(oturum, "req-B"))
})

test_that("terk işareti oturuma yazılamasa da GEÇERSİZLEME kaybolmaz", {
  pk_request_markers_reset()
  yutan <- .pk_hard_session(writable = FALSE)
  mergen_pk_invalidate_requests(yutan, "req-C")
  expect_true(mergen_pk_request_abandoned(yutan, "req-C"))
  # Farklı bir oturumun aynı istek kimliği ETKİLENMEZ (ayna oturum kapsamlıdır).
  expect_false(mergen_pk_request_abandoned(.pk_hard_session(TRUE), "req-C"))
})

test_that("oturum-sonu kancası OTURUM BAŞINA TEK kalır", {
  pk_request_markers_reset()
  oturum <- .pk_hard_session(writable = TRUE)
  jeton <- file.path(tempdir(), "pk_hard_tok.flag")

  expect_true(isTRUE(mergen_pk_register_active_request(oturum, "r1", jeton)))
  expect_true(isTRUE(mergen_pk_register_active_request(oturum, "r2", jeton)))
  # Kanca ikinci istekte YENİDEN kurulmamalıdır.
  expect_equal(length(oturum$.kancalar$liste), 1L)
})

test_that("kanca işareti oturuma yazılamasa da SÜREÇ-YEREL ayna TEKliği korur", {
  pk_request_markers_reset()
  oturum <- .pk_hard_session(writable = TRUE)
  expect_false(isTRUE(.pk_session_hook_installed(oturum)))
  expect_true(isTRUE(.pk_session_hook_mark(oturum)))
  expect_true(isTRUE(.pk_session_hook_installed(oturum)))

  # `userData` yazımı MÜMKÜN OLMAYAN oturumda da işaret KAYBOLMAZ.
  yutan <- .pk_hard_session(writable = FALSE)
  expect_false(isTRUE(.pk_session_hook_installed(yutan)))
  expect_true(isTRUE(.pk_session_hook_mark(yutan)))
  expect_true(isTRUE(.pk_session_hook_installed(yutan)))
})

# ------------------------------------------------------------------------------
# 4) DB ADMİSYONU VE LOGIN ZAMAN AŞIMI
# ------------------------------------------------------------------------------

test_that("agregat DB admisyonu ilan edilen tavanı AŞMAZ", {
  plan <- pk_db_admission_plan(cap = 8L, workers = 3L)
  expect_true(plan$fits)
  expect_lte(plan$total, 8L)
  expect_equal(plan$total, plan$main_share + plan$workers * plan$worker_share)
  expect_gte(plan$main_share, 1L)
  expect_gte(plan$worker_share, 1L)

  # Tavan süreç sayısına yetmiyorsa durum AÇIKÇA raporlanır.
  dar <- pk_db_admission_plan(cap = 2L, workers = 5L)
  expect_false(dar$fits)
})

test_that("login zaman aşımı planı ÜÇ AYRI sonuç üretir", {
  eski <- Sys.getenv("MERGEN_DB_LOGIN_TIMEOUT_SEC", unset = NA_character_)
  on.exit({
    if (is.na(eski)) Sys.unsetenv("MERGEN_DB_LOGIN_TIMEOUT_SEC")
    else Sys.setenv(MERGEN_DB_LOGIN_TIMEOUT_SEC = eski)
  }, add = TRUE)

  Sys.unsetenv("MERGEN_DB_LOGIN_TIMEOUT_SEC")
  # PK bütçesi YOK + yapılandırma YOK => SÜRÜCÜ VARSAYILANI (timeout GEÇİLMEZ).
  expect_identical(.db_login_timeout_plan(Inf)$mode, "driver_default")

  # 1 saniyenin ALTINDA kalan bütçe TEMSİL EDİLEMEZ => bağlantı açılmaz.
  expect_identical(.db_login_timeout_plan(0.2)$mode, "refuse")

  # Bütçe varsa sınır bütçeyle KISITLANIR.
  plan <- .db_login_timeout_plan(5)
  expect_identical(plan$mode, "bounded")
  expect_equal(plan$timeout, 5L)

  Sys.setenv(MERGEN_DB_LOGIN_TIMEOUT_SEC = "3")
  expect_identical(.db_login_timeout_plan(Inf)$mode, "bounded")
  expect_equal(.db_login_timeout_plan(Inf)$timeout, 3L)
  expect_equal(.db_login_timeout_plan(10)$timeout, 3L)
})

# ------------------------------------------------------------------------------
# 5) SONUÇ BOYUTU / LOB GÜVENLİĞİ
# ------------------------------------------------------------------------------

test_that("beyanı olmayan DEĞİŞKEN genişlik `__unproven__` sayılır ve REDDEDİLİR", {
  # Üretimdeki `dbColumnInfo()`: yalnızca `name` + SAYISAL ODBC kodu.
  bilgi <- data.frame(name = c("kod", "aciklama"), type = c("4", "-9"),
                      stringsAsFactors = FALSE)
  sutunlar <- pk_sql_columns_from_metadata(bilgi)
  expect_identical(sutunlar[[2]]$type, "__unproven__")

  genislik <- pk_result_width_upper_bound(sutunlar)
  expect_false(genislik$bounded)
  # `pk_result_width_upper_bound()` adsız listede sütunu konumdan adlandırır.
  expect_equal(length(genislik$unproven_columns), 1L)

  plan <- pk_sql_plan_chunk_rows(bilgi, chunk_rows = 5000L, max_result_mb = 512)
  expect_true(isTRUE(plan$refuse))
  expect_identical(plan$reason, "unproven_variable_width_column")
})

test_that("sürücü TANIMLAYICISI varsa sınırlı metin sütunu TEK SATIRA düşmez", {
  bilgi <- data.frame(name = c("kod", "aciklama"), type = c("4", "-9"),
                      stringsAsFactors = FALSE)
  sema <- list(
    list(name = "kod", system_type_name = "int", max_length = 4),
    list(name = "aciklama", system_type_name = "nvarchar(200)", max_length = 400)
  )
  plan <- pk_sql_plan_chunk_rows(bilgi, chunk_rows = 5000L, max_result_mb = 512,
                                 schema = sema)
  expect_true(plan$bounded)
  expect_false(isTRUE(plan$refuse))
  expect_gt(plan$rows, 1L)
})

test_that("tanımlayıcı MAX sütunu bildirdiğinde sonuç REDDEDİLİR", {
  bilgi <- data.frame(name = c("govde"), type = c("-9"), stringsAsFactors = FALSE)
  sema <- list(list(name = "govde", system_type_name = "nvarchar(max)", max_length = -1))
  plan <- pk_sql_plan_chunk_rows(bilgi, max_result_mb = 512, schema = sema)
  expect_true(isTRUE(plan$refuse))
  expect_identical(plan$reason, "unbounded_lob_column")
})

test_that("sorgu metadata'sı sınırsız LOB politikasını GERÇEKTEN etkiler", {
  bilgi <- data.frame(name = c("govde"), type = c("-9"), stringsAsFactors = FALSE)
  sema <- list(list(name = "govde", system_type_name = "nvarchar(max)", max_length = -1))

  # Sorgu düzeyinde AÇIK izin: reddetme kalkar.
  izinli <- pk_sql_plan_chunk_rows(bilgi, max_result_mb = 512, schema = sema,
                                   query_meta = list(allow_unbounded_lob = TRUE))
  expect_false(isTRUE(izinli$refuse))

  # Küresel bayrak AÇIK olsa bile sorgu düzeyinde KAPATMA sıkılaştırır.
  eski <- Sys.getenv("MERGEN_PK_ALLOW_UNBOUNDED_LOB", unset = NA_character_)
  on.exit({
    if (is.na(eski)) Sys.unsetenv("MERGEN_PK_ALLOW_UNBOUNDED_LOB")
    else Sys.setenv(MERGEN_PK_ALLOW_UNBOUNDED_LOB = eski)
  }, add = TRUE)
  Sys.setenv(MERGEN_PK_ALLOW_UNBOUNDED_LOB = "true")
  sikilastirilmis <- pk_sql_plan_chunk_rows(bilgi, max_result_mb = 512, schema = sema,
                                            query_meta = list(allow_unbounded_lob = FALSE))
  expect_true(isTRUE(sikilastirilmis$refuse))
})

test_that("TEK kanıtlanmış satır bile tavana sığmıyorsa GETİRMEDEN reddedilir", {
  # 20 MB'lık kanıtlanmış satır, 1 MB tavan: `dbFetch(n = 1)` bile aşardı.
  sema <- list(list(name = "genis", system_type_name = "binary", max_length = 20 * 1024^2))
  plan <- pk_sql_plan_chunk_rows(NULL, chunk_rows = 100L, max_result_mb = 1,
                                 schema = sema)
  expect_true(isTRUE(plan$refuse))
  expect_identical(plan$reason, "single_row_exceeds_result_ceiling")
})

# ------------------------------------------------------------------------------
# 6) ÖNBELLEK BÜTÇESİ VE SQL İMZASI
# ------------------------------------------------------------------------------

test_that("kendi başına TOPLAM bütçeyi aşan isabet SERVİS EDİLMEZ", {
  pk_cache_reset()
  on.exit(pk_cache_reset(), add = TRUE)

  # ~8 MB'lık giriş: yapılandırma TAM SAYI MB olduğu için ölçülebilir olmalıdır.
  buyuk <- data.frame(x = seq_len(2e6L))
  expect_true(pk_cache_put("k1", buyuk, query_meta = list(cache_max_mb = 64L,
                                                          cache_max_entry_mb = 64L))$stored)

  # Operatör TOPLAM bütçeyi girişin altına indiriyor (giriş-başına tavan YÜKSEK).
  #
  # TOPLAM BÜTÇE ORTAMDAN VERİLİR, SORGU METADATA'SINDAN DEĞİL: `.pk_cache_store`
  # SÜREÇ YERELİDİR ve tüm sorguların girişlerini bir arada tutar, bu yüzden
  # depo geneli `MERGEN_PK_CACHE_MAX_MB` bilerek sorgu metadata'sını GÖRMEZ
  # (aksi hâlde tek bir sorgunun override'ı başka sorguların girişlerini
  # tahliye eder ya da operatör tavanını gevşetirdi). Giriş-başına tavan
  # (`cache_max_entry_mb`) metadata'dan gelmeye devam eder.
  skip_if_not_installed("withr")
  withr::local_envvar(list(MERGEN_PK_CACHE_MAX_MB = "1"))
  isabet <- pk_cache_get("k1", query_meta = list(cache_max_entry_mb = 64L))
  expect_false(isabet$hit)
  expect_identical(isabet$reason, "entry_over_total_budget")
})

test_that("güvenli karma yoksa SQL sonuç önbelleği DEVRE DIŞI kalır", {
  sorgu <- list(id = "q1", db_target = "primary")
  rls <- list(authorized = TRUE, Yetki = "ADMIN")

  anahtar <- pk_query_result_cache_key(sorgu, rls, "SELECT 1", engine = "v1")
  # Ortamda digest/openssl VARSA anahtar üretilir ve UZUNLUK tabanlı olamaz.
  if (requireNamespace("digest", quietly = TRUE) ||
      requireNamespace("openssl", quietly = TRUE)) {
    expect_true(nzchar(anahtar))
    expect_false(grepl("v=n:", anahtar, fixed = TRUE))
    # AYNI uzunlukta FARKLI iki SQL AYNI anahtara düşmemelidir.
    a <- pk_query_result_cache_key(sorgu, rls, "SELECT 1", engine = "v1")
    b <- pk_query_result_cache_key(sorgu, rls, "SELECT 2", engine = "v1")
    expect_false(identical(a, b))
  } else {
    expect_identical(anahtar, "")
  }
})

# ------------------------------------------------------------------------------
# 7) HTTP İPTAL SINIFLANDIRMASI
# ------------------------------------------------------------------------------

test_that("genel curl aktarım hatası TEK BAŞINA iptal SAYILMAZ", {
  expect_true(pk_http_cancelled_error("Callback aborted", halted = FALSE))
  # Belirsiz aktarım hataları YALNIZCA kapı gerçekten durmuşken iptaldir.
  expect_false(pk_http_cancelled_error("Failed writing body (0 != 12)", halted = FALSE))
  expect_false(pk_http_cancelled_error("transfer closed with outstanding read data",
                                       halted = FALSE))
  expect_true(pk_http_cancelled_error("transfer closed with outstanding read data",
                                      halted = TRUE))
})

# ------------------------------------------------------------------------------
# 8) İŞÇİ YAPILANDIRMASI VE ORTAMI
# ------------------------------------------------------------------------------

test_that("eksik güvenlik anahtarı anlık görüntüyü EKSİK işaretler", {
  tam <- pk_async_config_snapshot()
  expect_true(pk_async_config_snapshot_complete(tam))
  expect_true(length(pk_async_config_snapshot_plain(tam)) > 0L)

  eksik <- structure(list(A = 1), `pk_missing_keys` = c("MERGEN_PK_MAX_RESULT_MB"))
  expect_false(pk_async_config_snapshot_complete(eksik))
})

test_that("ortam eşitlemesi HİÇBİR anahtarı kuramazsa NULL (kapalı başarısız) döner", {
  expect_null(pk_async_config_install_env(list(A = list(1, 2))))
  geri <- pk_async_config_install_env(list(MERGEN_PK_MAX_RESULT_MB = 8L))
  expect_true(is.function(geri))
  geri()
})

test_that("havuz option anlık görüntüsü SİLİNMİŞ option'ı da TAŞIR", {
  eski <- getOption("mergen.db.pool_enabled", NULL)
  on.exit(options(mergen.db.pool_enabled = eski), add = TRUE)

  options(mergen.db.pool_enabled = NULL)
  anlik <- pk_async_db_pool_option_snapshot()
  expect_true("mergen.db.pool_enabled" %in% names(anlik))
  expect_identical(anlik[["mergen.db.pool_enabled"]], .PK_ASYNC_OPTION_UNSET)

  # Sıcak işçi simülasyonu: eski değer TEMİZLENMELİDİR.
  options(mergen.db.pool_enabled = TRUE)
  pk_async_db_pool_option_install(anlik)
  expect_null(getOption("mergen.db.pool_enabled", NULL))
})

test_that("havuz parmak izi yapılandırma değiştiğinde DEĞİŞİR", {
  eski <- Sys.getenv("MERGEN_DB_POOL_ENABLED", unset = NA_character_)
  on.exit({
    if (is.na(eski)) Sys.unsetenv("MERGEN_DB_POOL_ENABLED")
    else Sys.setenv(MERGEN_DB_POOL_ENABLED = eski)
  }, add = TRUE)

  Sys.setenv(MERGEN_DB_POOL_ENABLED = "true")
  a <- pk_async_worker_pool_fingerprint(2L)
  Sys.setenv(MERGEN_DB_POOL_ENABLED = "false")
  b <- pk_async_worker_pool_fingerprint(2L)
  expect_false(identical(a, b))
  # İşçi sayısı da admisyon payını değiştirir.
  expect_false(identical(b, pk_async_worker_pool_fingerprint(4L)))
})

test_that("sahneleme ortamı ÖNCEKİ bootstrap sembollerini GÖRMEZ", {
  hedef <- new.env(parent = globalenv())
  assign("bayat_sembol", "ESKI", envir = hedef)

  sahne <- pk_async_worker_stage_env(target = hedef)
  # `inherits = TRUE` ile bile bayat sembol GÖRÜNMEMELİDİR.
  expect_false(exists("bayat_sembol", envir = sahne, inherits = TRUE))
})

test_that("sahneleme ebeveyni TAZELENİNCE yeni eklenen arama yolu GÖRÜNÜR olur", {
  # GERİLEME: `library()` arama yolunun BAŞINA ekler. Sahne ebeveyni kurulum
  # anında dondurulursa, bootstrap sırasında `R/config_packages.R` tarafından
  # attach edilen paketler sonraki dosyalara GÖRÜNMEZ kalır ve
  # `R/config_logging.R` "could not find function log_threshold" ile düşer.
  hedef <- new.env(parent = globalenv())
  assign("bayat_sembol", "ESKI", envir = hedef)
  sahne <- pk_async_worker_stage_env(target = hedef)

  # `attach()` ile arama yolunun BAŞINA yeni bir katman eklenir (library()'nin
  # ortam düzeyindeki karşılığı); kurulmuş sahne bunu HENÜZ görmez.
  yeni_katman <- new.env()
  assign("sonradan_eklenen_islev", function() "TAZE", envir = yeni_katman)
  eski_ebeveyn <- parent.env(hedef)
  parent.env(hedef) <- yeni_katman
  parent.env(yeni_katman) <- eski_ebeveyn
  on.exit(parent.env(hedef) <- eski_ebeveyn, add = TRUE)

  expect_false(exists("sonradan_eklenen_islev", envir = sahne, inherits = TRUE))

  expect_true(isTRUE(pk_async_worker_stage_refresh(sahne, hedef)))
  expect_true(exists("sonradan_eklenen_islev", envir = sahne, inherits = TRUE))
  # İZOLASYON KORUNUR: tazeleme sonrası da bayat sembol GÖRÜNMEZ.
  expect_false(exists("bayat_sembol", envir = sahne, inherits = TRUE))
})

test_that("işçi globals paketi BOOTSTRAP ÖNCESİ çağrı grafiği için KAPALIDIR", {
  # GERİLEME: `dependency_mode = "explicit"` HİÇBİR otomatik tarama yapmaz.
  # Paketlenen bir fonksiyonun gövdesinde adı geçen repo sembolü pakete
  # eklenmezse, işçi bootstrap'tan ÖNCE `object '...' not found` ile düşer ve
  # `MERGEN_PK_ASYNC=true` her istekte SESSİZCE senkron yedeğe geçerdi.
  # Bu test bootstrap-öncesi çağrı grafiğini gezerek paketin KAPALI olduğunu
  # kanıtlar (bootstrap SONRASI semboller kaynak dosyalardan gelir; onlar
  # kapsam dışıdır).
  skip_if_not_installed("codetools")

  paket <- pk_async_worker_globals(force = TRUE)
  expect_true(is.list(paket) && length(paket) > 0L)

  # Repo'ya ait sembol ön ekleri: yalnızca bunlar paketten çözülmek ZORUNDA.
  repo_sembolu <- function(ad) grepl("^\\.?(pk_|PK_|mergen_pk_)", ad)

  # Bootstrap TAMAMLANMADAN önce çalışan giriş noktaları.
  tohumlar <- c("pk_async_worker_bootstrap", "pk_async_bounded_fs",
                "pk_async_bootstrap_fingerprint", "pk_async_worker_stage_env",
                "pk_async_worker_stage_refresh", "pk_async_worker_commit_env",
                "pk_async_worker_install_globals",
                "pk_async_worker_sql_dependencies")
  # TOHUMLAR SESSİZCE DÜŞÜRÜLMEZ: `intersect()` ile kesişim alınırsa, bir giriş
  # noktası pakette olmadığında (yeniden adlandırma / paketten düşme) test daha
  # AZ tohumla yeşil kalır ve tam da koruması gereken regresyonu kaçırır.
  expect_identical(setdiff(tohumlar, names(paket)), character(0))
  expect_true(length(tohumlar) > 0L)

  gorulen <- character(0)
  eksik <- character(0)
  kuyruk <- tohumlar
  while (length(kuyruk)) {
    ad <- kuyruk[1]; kuyruk <- kuyruk[-1]
    if (ad %in% gorulen) next
    gorulen <- c(gorulen, ad)
    fn <- paket[[ad]]
    if (!is.function(fn)) next
    globaller <- tryCatch(codetools::findGlobals(fn, merge = TRUE),
                          error = function(e) character(0))
    for (g in globaller) {
      if (!repo_sembolu(g)) next
      if (!(g %in% names(paket))) {
        eksik <- c(eksik, sprintf("%s -> %s", ad, g))
      } else if (is.function(paket[[g]])) {
        kuyruk <- c(kuyruk, g)
      }
    }
  }

  expect_identical(unique(eksik), character(0))
})

test_that("bootstrap kaynak döngüsü sahne ebeveynini HER DOSYADAN ÖNCE tazeler", {
  # Repo kökü ortak yardımcıyla çözülür (çalışma dizini bağımsız) ve dosya
  # BAYT-GÜVENLİ okunur: Windows VM'de Türkçe yorumlu dosyalarda düz
  # `readLines(encoding = "UTF-8")` "invalid UTF-8" ile düşüyordu.
  yol <- file.path(resolve_repo_root_for_tests(), "R", "helpers_pk_async_bootstrap.R")
  ham <- readBin(yol, what = "raw", n = file.info(yol)$size)
  metin <- iconv(rawToChar(ham), from = "UTF-8", to = "UTF-8", sub = "byte")
  kaynak <- strsplit(metin, "\n", fixed = TRUE)[[1]]
  expect_true(grepl("pk_async_worker_stage_refresh(sahne, hedef)", metin, fixed = TRUE))
  # Tazeleme `sys.source()` ÖNCESİNDE olmalıdır.
  expect_lt(
    which(grepl("pk_async_worker_stage_refresh(sahne, hedef)", kaynak, fixed = TRUE))[1],
    which(grepl("sys.source(tam, envir = sahne", kaynak, fixed = TRUE))[1]
  )
})

test_that("PK gözlemci sarmalayıcıları ZORUNLU dosya kümesindedir", {
  zorunlu <- pk_async_worker_required_files()
  expect_true("R/helpers_pk_worker_observers.R" %in% zorunlu)
  expect_true("R/helpers_pk_worker_direct_exit.R" %in% zorunlu)
  # Bootstrap yüzeyi de bunları TAŞIMALIDIR (aksi hâlde zorunlu ama yüklenmeyen
  # bir dosya bootstrap'ı her istekte düşürürdü).
  yuzey <- pk_async_worker_bootstrap_files()
  expect_true(all(c("R/helpers_pk_worker_observers.R",
                    "R/helpers_pk_worker_direct_exit.R") %in% yuzey))
})

test_that("zorunlu dosya denetimi TAM GÖRELİ yol karşılaştırır", {
  kok <- file.path(tempdir(), paste0("pk_boot_", as.integer(runif(1, 1, 1e6))))
  dir.create(file.path(kok, "R"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(kok, "baska"), recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(kok, recursive = TRUE, force = TRUE), add = TRUE)

  # Zorunlu `R/zorunlu.R` YOKTUR; aynı TEMEL ADA sahip `baska/zorunlu.R` VARDIR.
  writeLines("x <- 1", file.path(kok, "baska", "zorunlu.R"))

  # Süreç-başına önbellek bayrağı temizlenir: aksi hâlde daha önceki bir
  # bootstrap "cached" dönüp denetimi hiç çalıştırmazdı.
  if (exists(.PK_ASYNC_BOOTSTRAP_FLAG, envir = globalenv(), inherits = FALSE)) {
    rm(list = .PK_ASYNC_BOOTSTRAP_FLAG, envir = globalenv())
  }
  sonuc <- pk_async_worker_bootstrap(
    kok, c("baska/zorunlu.R", "R/zorunlu.R"),
    required_files = "R/zorunlu.R"
  )
  expect_false(isTRUE(sonuc$ok))
  expect_true(any(grepl("R/zorunlu.R", sonuc$failed, fixed = TRUE)))
})

test_that("sınırlı yol denetimi bütçe tükendiğinde KAPALI BAŞARISIZ olur", {
  yol <- tempfile(fileext = ".R")
  writeLines("x <- 1", yol)
  on.exit(unlink(yol, force = TRUE), add = TRUE)

  expect_true(pk_async_bounded_path_exists(yol))
  expect_true(pk_async_bounded_path_exists(dirname(yol), dir = TRUE))
  expect_false(pk_async_bounded_path_exists(paste0(yol, ".yok")))
  expect_false(pk_async_bounded_path_exists(NULL))
  expect_false(pk_async_bounded_path_exists(""))

  # Son tarih GEÇMİŞSE bütçe tükenmiştir: denetim çalıştırılmaz.
  expect_false(pk_async_bounded_path_exists(yol, deadline_at = Sys.time() - 5))
})

test_that("commit KISMİ yazımda BAŞARISIZ döner", {
  hedef <- new.env(parent = globalenv())
  sahne <- new.env(parent = emptyenv())
  assign("a", 1, envir = sahne)
  assign("b", 2, envir = sahne)
  # `b` KİLİTLİ: atama başarısız olacak.
  assign("b", 0, envir = hedef)
  lockBinding("b", hedef)

  sonuc <- pk_async_worker_commit_env(sahne, hedef)
  expect_false(isTRUE(sonuc$ok))
  expect_true(any(grepl("b", sonuc$failed, fixed = TRUE)))
})

test_that("KISMİ commit GERİ ALINIR (karışık revizyon kalmaz)", {
  hedef <- new.env(parent = globalenv())
  sahne <- new.env(parent = emptyenv())

  # `a` ÖNCEDEN VAR (eski revizyon), `c` YENİ, `b` KİLİTLİ (commit'i düşürecek).
  assign("a", "eski", envir = hedef)
  assign("b", "kilitli", envir = hedef)
  lockBinding("b", hedef)

  assign("a", "yeni", envir = sahne)
  assign("b", "yeni", envir = sahne)
  assign("c", "yeni", envir = sahne)

  sonuc <- pk_async_worker_commit_env(sahne, hedef)
  expect_false(isTRUE(sonuc$ok))

  # ESKİ değer geri gelmiştir; YENİ sembol kaldırılmıştır.
  expect_identical(get("a", envir = hedef, inherits = FALSE), "eski")
  expect_false(exists("c", envir = hedef, inherits = FALSE))
  # Sahiplik listesi GÜNCELLENMEZ.
  expect_false(exists(.PK_ASYNC_OWNED_NAMES_SLOT, envir = hedef, inherits = FALSE))
})

test_that("BAŞARILI commit eski sembolleri temizler ve sahipliği yazar", {
  hedef <- new.env(parent = globalenv())
  sahne <- new.env(parent = emptyenv())
  assign(.PK_ASYNC_OWNED_NAMES_SLOT, c("eski_sembol"), envir = hedef)
  assign("eski_sembol", 1, envir = hedef)
  assign("yeni_sembol", 2, envir = sahne)

  sonuc <- pk_async_worker_commit_env(sahne, hedef)
  expect_true(isTRUE(sonuc$ok))
  expect_false(exists("eski_sembol", envir = hedef, inherits = FALSE))
  expect_identical(get("yeni_sembol", envir = hedef, inherits = FALSE), 2)
  expect_identical(get(.PK_ASYNC_OWNED_NAMES_SLOT, envir = hedef, inherits = FALSE),
                   "yeni_sembol")
})

test_that("artifact kaydı KAPSAM DIŞINDA no-op'tur", {
  pk_artifact_release_tracked()
  expect_false(pk_artifact_scope_active())
  pk_artifact_track(c("/tmp/pk_hard_a.xlsx"))
  # Kapsam yokken hiçbir şey kaydedilmez (senkron dışa aktarımlar BİRİKMEZ).
  expect_equal(length(pk_artifact_release_tracked()), 0L)

  pk_artifact_scope_begin("req-1")
  expect_true(pk_artifact_scope_active())
  pk_artifact_track("/tmp/pk_hard_b.xlsx")
  expect_equal(length(pk_artifact_release_tracked()), 1L)
  expect_false(pk_artifact_scope_active())
})

# ------------------------------------------------------------------------------
# 9) SINIRLI DOSYA SİSTEMİ SARMALAYICISI
# ------------------------------------------------------------------------------

test_that("bootstrap G/Ç sarmalayıcısı bütçe tükendiğinde ÇALIŞTIRMAZ", {
  calisti <- FALSE
  sonuc <- pk_async_bounded_fs(function() { calisti <<- TRUE; 42 },
                               deadline_at = Sys.time() - 5)
  expect_false(isTRUE(sonuc$ok))
  expect_false(calisti)

  ok <- pk_async_bounded_fs(function() 42, deadline_at = Sys.time() + 60)
  expect_true(ok$ok)
  expect_equal(ok$value, 42)

  # Bütçe YOKSA davranış DEĞİŞMEZ.
  expect_equal(pk_async_bounded_fs(function() 7, NULL)$value, 7)
})

# ------------------------------------------------------------------------------
# 10) TİPLİ TERMİNAL SONUÇ "DEVAM ET"E DÜŞMEZ
# ------------------------------------------------------------------------------

local({
  repo_root <- resolve_repo_root_for_tests()
  source(file.path(repo_root, "R", "helpers_pk_async_apply.R"),
         encoding = "UTF-8", local = globalenv())
  source(file.path(repo_root, "R", "helpers_pk_async_lifecycle.R"),
         encoding = "UTF-8", local = globalenv())
  source(file.path(repo_root, "R", "helpers_pk_export_serve.R"),
         encoding = "UTF-8", local = globalenv())
  source(file.path(repo_root, "R", "helpers_deep_analysis_phase6.R"),
         encoding = "UTF-8", local = globalenv())
})

test_that("`pk_stopped` sonucu nihai LLM'e DEVAM ETMEZ", {
  mesajlar <- list(list(role = "user", content = "ham istem"))
  uygulama <- mergen_pk_apply_analysis_result(list(type = "pk_stopped"), mesajlar)
  expect_identical(uygulama$action, "answer")
  expect_true(nzchar(uygulama$answer))
  # Kullanıcının ham istemi bağlamsız biçimde ilerletilmemelidir.
  expect_false(identical(uygulama$action, "continue"))
})

test_that("BİLİNMEYEN terminal liste tipi KAPALI BAŞARISIZ olur", {
  mesajlar <- list(list(role = "user", content = "ham istem"))
  uygulama <- mergen_pk_apply_analysis_result(list(type = "yeni_terminal_tip"), mesajlar)
  expect_identical(uygulama$action, "answer")

  # BİLİNEN başarı şekli (bağlam taşıyan) devam EDER.
  basarili <- mergen_pk_apply_analysis_result(
    list(user_context = "veri", prompt_context = "sistem"), mesajlar
  )
  expect_identical(basarili$action, "continue")
})

# ------------------------------------------------------------------------------
# 11) DIŞA AKTARIM SUNUMU VE TEMİZLİK SAHİPLİĞİ
# ------------------------------------------------------------------------------

test_that("URL'siz kayıt EXPORT BAŞARISIZLIĞIDIR", {
  expect_false(.pk_artifact_urls_ok(list(files = list(list(path = "/tmp/a", url = NULL)))))
  expect_false(.pk_artifact_urls_ok(list(files = list(list(path = "/tmp/a", url = "")))))
  expect_true(.pk_artifact_urls_ok(list(files = list(list(path = "/tmp/a", url = "/x")))))
  expect_false(.pk_artifact_urls_ok(list(files = list())))
})

test_that("`pk_export_serve` YOKKEN ek taşıyan sonuç KAPALI BAŞARISIZ olur", {
  # Sunum yardımcısı yoksa işçi-yerel artefakt "sunulmuş" sayılamaz: aksi hâlde
  # URL'siz bir indirme kartı gösterilir, tipli `export_failed` yolu ve artefakt
  # temizliği atlanırdı.
  eski <- get("pk_export_serve", envir = globalenv())
  on.exit(assign("pk_export_serve", eski, envir = globalenv()), add = TRUE)
  rm("pk_export_serve", envir = globalenv())

  sonuc <- list(pk_attachment = list(status = "ok",
                                     files = list(list(path = "/tmp/a.xlsx"))))
  cikti <- mergen_pk_serve_worker_artifact(sonuc, session = NULL)
  expect_false(isTRUE(cikti$ok))

  # EK YOKSA davranış değişmez: sıradan sonuç başarıyla geçer.
  expect_true(isTRUE(mergen_pk_serve_worker_artifact(list(a = 1), session = NULL)$ok))
})

test_that("DOSYASIZ ek (refused/failed/empty) başarılı analizi ATMAZ", {
  # `pk_export_serve()` dosyasız eki DEĞİŞTİRMEDEN döndürür; URL denetimi
  # bunları başarısız sayıp analizi `export_failed` ile atıyordu.
  for (durum in c("refused", "failed", "empty")) {
    sonuc <- list(pk_answer_block = "blok",
                  pk_attachment = list(status = durum, files = list()))
    cikti <- mergen_pk_serve_worker_artifact(sonuc, session = NULL)
    expect_true(isTRUE(cikti$ok), info = durum)
    expect_identical(cikti$result$pk_attachment$status, durum)
  }
})

test_that("çip gönderimi HATA verirse `sendCustomMessage` yedeği çalışır", {
  gonderilenler <- new.env(parent = emptyenv())
  gonderilenler$n <- 0L
  ctx <- list(
    emit_chips_fn = function(chips) stop("cip gonderilemedi"),
    session = list(sendCustomMessage = function(tur, veri) {
      gonderilenler$n <- gonderilenler$n + 1L
      gonderilenler$veri <- veri
      invisible(TRUE)
    })
  )
  sonuc <- mergen_pk_emit_chips(ctx, list("a", "b"), message_id = "msg_1")
  expect_true(isTRUE(sonuc))
  expect_equal(gonderilenler$n, 1L)
  expect_identical(gonderilenler$veri$id, "msg_1")

  # BAŞARILI gönderimde yedek çalışmaz (davranış değişmedi).
  gonderilenler$n <- 0L
  ctx$emit_chips_fn <- function(chips) invisible(TRUE)
  expect_true(isTRUE(mergen_pk_emit_chips(ctx, list("a"), message_id = "msg_1")))
  expect_equal(gonderilenler$n, 0L)
})

test_that("registerDataObj adı her artefakt için BENZERSİZDİR", {
  a <- .pk_export_object_nonce()
  b <- .pk_export_object_nonce()
  expect_false(identical(a, b))
})

test_that("oturum-sonu temizlik işareti YALNIZCA kayıt başarılıysa konur", {
  ud <- new.env(parent = emptyenv())
  basarisiz_oturum <- list(userData = ud, onSessionEnded = function(fn) stop("kurulamadi"))
  yol <- file.path(tempdir(), "pk_hard_export.xlsx")

  expect_false(isTRUE(.pk_export_register_cleanup(basarisiz_oturum, yol)))
  # İşaret KONMAMALIDIR: sonraki dışa aktarım yeniden denemelidir.
  expect_false(isTRUE(ud$pk_export_cleanup_registered))
  # Yollar deftere yazılmıştır (kayıt başarılı olduğunda hepsi temizlenir).
  expect_true(yol %in% as.character(ud$pk_export_cleanup_paths))

  kancalar <- new.env(parent = emptyenv())
  kancalar$n <- 0L
  ok_oturum <- list(userData = ud,
                    onSessionEnded = function(fn) { kancalar$n <- kancalar$n + 1L; TRUE })
  expect_true(isTRUE(.pk_export_register_cleanup(ok_oturum, yol)))
  expect_true(isTRUE(ud$pk_export_cleanup_registered))
  expect_equal(kancalar$n, 1L)
})

# ------------------------------------------------------------------------------
# 12) DERİN YOL ORİJİNAL BAŞLANGICI KORUR
# ------------------------------------------------------------------------------

test_that("derin Faz 6 kurulumu YAYINLANMIŞ başlangıcı SIFIRLAMAZ", {
  eski_start <- getOption("mergen.pk.async.started_at", NULL)
  eski_deadline <- getOption("mergen.pk.async.deadline_at", NULL)
  on.exit(options(mergen.pk.async.started_at = eski_start,
                  mergen.pk.async.deadline_at = eski_deadline), add = TRUE)

  yayinlanan <- Sys.time() - 42
  options(mergen.pk.async.started_at = yayinlanan)

  kurulum <- pk_deep_phase6_setup(list(), session = NULL, request_id = "req-x")
  on.exit(try(kurulum$restore(), silent = TRUE), add = TRUE)

  guncel <- getOption("mergen.pk.async.started_at", NULL)
  expect_true(inherits(guncel, "POSIXct"))
  # Bootstrap/kurulum süresi isteğe GERİ VERİLMEZ.
  expect_lt(abs(as.numeric(difftime(guncel, yayinlanan, units = "secs"))), 1)
})

# ------------------------------------------------------------------------------
# 13) GEZİNME: AYNI sohbete yeniden tıklamak isteği TERK ETMEZ
# ------------------------------------------------------------------------------

test_that("kayıtlı sohbet yükleme, PK isteğini YALNIZCA kimlik değişince terk eder", {
  repo_root <- resolve_repo_root_for_tests()
  ham <- readBin(file.path(repo_root, "R", "server_observers_saved_chats.R"),
                 what = "raw",
                 n = file.info(file.path(repo_root, "R", "server_observers_saved_chats.R"))$size)
  metin <- iconv(rawToChar(ham), from = "UTF-8", to = "UTF-8", sub = "byte")

  # Hedef kimlik ile mevcut kimlik KARŞILAŞTIRILIR.
  expect_true(grepl("hedef_degisti", metin, fixed = TRUE, useBytes = TRUE))
  # Terk çağrısı KOŞULA bağlıdır (koşulsuz çağrı geri gelmemelidir).
  expect_true(grepl("isTRUE(hedef_degisti) &&", metin, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("mergen_pk_abandon_active_requests", metin, fixed = TRUE, useBytes = TRUE))
})

test_that("bootstrap parmak izi SQL bagimliliklarini KAYNAK METINDEN turetir", {
  kok <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  for (dosya in c("helpers_pk_config.R", "helpers_pk_async_cancel.R",
                  "helpers_pk_async_worker_env.R")) {
    source(file.path(kok, "R", dosya), encoding = "UTF-8", local = env)
  }

  dosyalar <- c("R/library_queries.R", "R/config_sql_loader.R")

  # Temiz bir PSOCK iscisinde ILK parmak izi bootstrap'tan ONCE hesaplanir ve o
  # an `query_library` HENUZ YOKTUR. Kaynak taramasi her iki durumda da AYNI
  # girdiyi verir; aksi halde isci degismemis bir calisma kopyasinda IKINCI bir
  # tam bootstrap yapiyordu.
  onceki <- get0("query_library", envir = globalenv(), inherits = FALSE)
  on.exit({
    if (is.null(onceki)) {
      if (exists("query_library", envir = globalenv(), inherits = FALSE)) {
        rm("query_library", envir = globalenv())
      }
    } else {
      assign("query_library", onceki, envir = globalenv())
    }
  }, add = TRUE)

  if (exists("query_library", envir = globalenv(), inherits = FALSE)) {
    rm("query_library", envir = globalenv())
  }
  ilk <- env$pk_async_bootstrap_fingerprint(kok, dosyalar)

  assign("query_library",
         list(list(id = "q001", sql_file = "sql_queries/q001_kpi.sql")),
         envir = globalenv())
  ikinci <- env$pk_async_bootstrap_fingerprint(kok, dosyalar)

  expect_identical(ilk, ikinci)

  # Statik tarama, kaynak metindeki TUM `sql_file` bildirimlerini yakalar.
  statik <- env$.pk_async_sql_paths_from_source(kok, dosyalar)
  expect_true(length(statik) >= 1L)
  expect_true(all(grepl("\\.sql$", statik)))

  # `files` gecilmediginde ESKI davranis (calisma zamani kutuphanesi) korunur.
  yedek <- env$pk_async_worker_sql_dependencies(kok)
  expect_true(any(grepl("q001_kpi\\.sql$", yedek)))
})

test_that("ORTAM tabanli havuz girdileri sicak isciye tasinir", {
  kok <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  for (dosya in c("helpers_pk_config.R", "helpers_pk_async_worker_pool.R")) {
    source(file.path(kok, "R", dosya), encoding = "UTF-8", local = env)
  }

  eski <- Sys.getenv(c("MERGEN_DB_POOL_MAX_SIZE", "MERGEN_DB_POOL_MIN_SIZE",
                       "MERGEN_DB_POOL_ENABLED", "MERGEN_DB_POOL_SHARE_APPLIED"),
                     unset = NA_character_)
  on.exit({
    for (ad in names(eski)) {
      if (is.na(eski[[ad]])) Sys.unsetenv(ad)
      else do.call(Sys.setenv, stats::setNames(list(eski[[ad]]), ad))
    }
  }, add = TRUE)

  # ANA SUREC durumu.
  Sys.setenv(MERGEN_DB_POOL_MAX_SIZE = "12", MERGEN_DB_POOL_ENABLED = "true")
  Sys.unsetenv("MERGEN_DB_POOL_MIN_SIZE")
  anlik <- env$pk_async_db_pool_option_snapshot()
  expect_true("env:MERGEN_DB_POOL_MAX_SIZE" %in% names(anlik))

  # SICAK ISCI durumu: ortam FARKLI ve surec rolu isareti kurulu.
  Sys.setenv(MERGEN_DB_POOL_MAX_SIZE = "99", MERGEN_DB_POOL_MIN_SIZE = "7",
             MERGEN_DB_POOL_SHARE_APPLIED = "1")
  env$pk_async_db_pool_option_install(anlik)

  # Ana surecin degeri geri kurulur, ana surecte SILINMIS anahtar iscide de silinir.
  expect_identical(Sys.getenv("MERGEN_DB_POOL_MAX_SIZE"), "12")
  expect_identical(Sys.getenv("MERGEN_DB_POOL_MIN_SIZE"), "")
  # SUREC ROLU isareti BILEREK tasinmaz; silinseydi tavan iki kez bolusulurdu.
  expect_identical(Sys.getenv("MERGEN_DB_POOL_SHARE_APPLIED"), "1")

  # Parmak izi ortam degisimine TEPKI verir; aksi halde isci eski havuzu korurdu.
  ilk <- env$pk_async_worker_pool_fingerprint(2L)
  Sys.setenv(MERGEN_DB_POOL_MAX_SIZE = "4")
  expect_false(identical(ilk, env$pk_async_worker_pool_fingerprint(2L)))
})

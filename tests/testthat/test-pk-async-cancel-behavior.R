# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-async-cancel-behavior.R
# Açıklama: Faz 6 (§5.10) — İŞÇİ TARAFINDAN GÖRÜLEBİLEN iptal jetonu ve
#           duvar-saati son tarih aritmetiğinin davranış testleri.
#
# Tamamen çevrimdışı ve belirlenimcidir: DB, LLM, tarayıcı, ağ, gerçek future
# işçisi veya gizli değer GEREKMEZ. Zaman geçişi Sys.sleep ile DEĞİL, açık
# `now`/`started_at` argümanlarıyla modellenir.
#
# Kanıtlanan sözleşmeler:
#   - Jeton YOKLUĞU "iptal edilmedi" demektir; DİZİN durdurma bayrağı DEĞİLDİR.
#   - `pk_sql_timeout_plan()` her zaman kalan bütçeyle SINIRLIDIR ve pozitif
#     bütçe kalmadığında ifade GÖNDERİLMEZ.
#   - Ardışık geçerli zaman aşımlarının toplamı analiz bütçesini AŞAMAZ.
#   - İptal ve zaman aşımı AYRI durumlar ve AYRI kullanıcı mesajlarıdır.
# ==============================================================================

local({
  repo_root <- resolve_repo_root_for_tests()

  if (!exists("%||%", mode = "function", inherits = TRUE)) {
    `%||%` <<- function(a, b) if (is.null(a)) b else a
  }

  source(file.path(repo_root, "R", "helpers_pk_async_cancel.R"),
         encoding = "UTF-8", local = globalenv())
})

.pk_cancel_tmp_root <- function() {
  yol <- file.path(tempdir(), paste0("pk_cancel_test_", as.integer(runif(1, 1, 1e9))))
  dir.create(yol, recursive = TRUE, showWarnings = FALSE)
  yol
}

test_that("jeton yolu istek kimliğinden ASCII-güvenli üretilir", {
  kok <- .pk_cancel_tmp_root()
  on.exit(unlink(kok, recursive = TRUE), add = TRUE)

  yol <- pk_cancel_token_path("req_123", base_dir = kok)
  expect_true(grepl("pk_stop_req_123\\.flag$", yol))

  # Yol ayırıcı ve traversal içeren kimlik dosya adına SIZAMAZ.
  kirli <- pk_cancel_token_path("../../etc/passwd", base_dir = kok)
  expect_false(grepl("\\.\\.", basename(kirli), fixed = FALSE))
  expect_equal(dirname(kirli), dirname(yol))
})

test_that("jeton YOKLUĞU iptal değildir; işaretlendiğinde iptaldir", {
  kok <- .pk_cancel_tmp_root()
  on.exit(unlink(kok, recursive = TRUE), add = TRUE)

  yol <- pk_cancel_token_path("r1", base_dir = kok)
  expect_false(pk_cancel_token_is_signalled(yol))

  expect_true(pk_cancel_token_signal(yol))
  expect_true(pk_cancel_token_is_signalled(yol))

  expect_true(pk_cancel_token_clear(yol))
  expect_false(pk_cancel_token_is_signalled(yol))
})

test_that("NULL / boş / DİZİN durdurma bayrağı SAYILMAZ", {
  kok <- .pk_cancel_tmp_root()
  on.exit(unlink(kok, recursive = TRUE), add = TRUE)

  expect_false(pk_cancel_token_is_signalled(NULL))
  expect_false(pk_cancel_token_is_signalled(""))
  expect_false(pk_cancel_token_is_signalled(NA_character_))

  # Yanlışlıkla oluşturulmuş bir DİZİN her analizi iptal etmemelidir.
  dizin <- file.path(kok, "pk_stop_dir.flag")
  dir.create(dizin, showWarnings = FALSE)
  expect_true(dir.exists(dizin))
  expect_false(pk_cancel_token_is_signalled(dizin))
})

test_that("bayat jetonlar yaşa göre temizlenir, yeni jeton korunur", {
  kok <- .pk_cancel_tmp_root()
  on.exit(unlink(kok, recursive = TRUE), add = TRUE)

  eski <- pk_cancel_token_path("bayat", base_dir = kok)
  yeni <- pk_cancel_token_path("guncel", base_dir = kok)
  # BAYAT JETON = ÇÖKEN BİR SÜREÇTEN KALAN dosya: süreç-yerel etkin kayıtta yer
  # ALMAZ. Bu yüzden `pk_cancel_token_signal()` ile değil, doğrudan yazılır.
  writeBin(charToRaw("1"), eski)
  pk_cancel_token_signal(yeni)

  # Eski dosyanın mtime'ını geriye al (Sys.sleep kullanmadan).
  Sys.setFileTime(eski, Sys.time() - 7200)

  silinen <- pk_cancel_token_cleanup_stale(base_dir = kok, max_age_sec = 3600)
  expect_equal(silinen, 1L)
  expect_false(file.exists(eski))
  expect_true(file.exists(yeni))
})

test_that("ETKİN isteğin jetonu yaşlı olsa da temizlenmez", {
  kok <- .pk_cancel_tmp_root()
  on.exit(unlink(kok, recursive = TRUE), add = TRUE)

  # İptal edilmiş AMA hâlâ etkin bir istek: bloke bir işlem geri döndüğünde
  # `pk_async_stage_gate()` isteği "iptal edilmemiş" okuyup analize DEVAM
  # etmemelidir. Jeton yalnızca `pk_cancel_token_clear()` ile bayat sayılır.
  etkin <- pk_cancel_token_path("etkin-istek", base_dir = kok)
  pk_cancel_token_signal(etkin)
  Sys.setFileTime(etkin, Sys.time() - 7200)

  expect_equal(pk_cancel_token_cleanup_stale(base_dir = kok, max_age_sec = 3600), 0L)
  expect_true(file.exists(etkin))
  expect_true(pk_cancel_token_is_signalled(etkin))

  # TERMİNAL DURUMDAN SONRA kayıt düşer; yeniden yazılan dosya bayat sayılabilir.
  pk_cancel_token_clear(etkin)
  writeBin(charToRaw("1"), etkin)
  Sys.setFileTime(etkin, Sys.time() - 7200)
  expect_equal(pk_cancel_token_cleanup_stale(base_dir = kok, max_age_sec = 3600), 1L)
  expect_false(file.exists(etkin))
})

test_that("son tarih aritmetiği: kalan süre, dolma ve bütçesiz hâl", {
  baslangic <- as.POSIXct("2026-08-09 10:00:00", tz = "UTC")

  son <- pk_deadline_at(baslangic, 300)
  expect_equal(as.numeric(difftime(son, baslangic, units = "secs")), 300)

  expect_equal(
    pk_deadline_remaining_sec(son, now = baslangic + 100), 200
  )
  expect_false(pk_deadline_expired(son, now = baslangic + 299))
  expect_true(pk_deadline_expired(son, now = baslangic + 300))
  expect_true(pk_deadline_expired(son, now = baslangic + 301))

  # Bütçe tanımlı değilse `Inf` döner ve ASLA dolmuş sayılmaz.
  yok <- pk_deadline_at(baslangic, NA)
  expect_true(is.na(yok))
  expect_equal(pk_deadline_remaining_sec(yok), Inf)
  expect_false(pk_deadline_expired(yok))

  # Geçersiz/negatif bütçe de son tarih ÜRETMEZ (sessizce 0 saniye vermez).
  expect_true(is.na(pk_deadline_at(baslangic, 0)))
  expect_true(is.na(pk_deadline_at(baslangic, -5)))
})

test_that("SQL zaman aşımı DAİMA kalan bütçeyle sınırlıdır", {
  # Yapılandırılmış 120 sn, kalan 300 sn -> yapılandırılmış kazanır.
  p1 <- pk_sql_timeout_plan(120, 300)
  expect_true(p1$dispatch)
  expect_equal(p1$timeout_sec, 120L)
  expect_equal(p1$reason, "configured")

  # §9 senaryosu: sorgu bazlı 600 sn override, 300 sn analiz son tarihi.
  # Override yapılandırılmış zaman aşımını yükseltebilir ama son tarihi UZATAMAZ.
  p2 <- pk_sql_timeout_plan(600, 300)
  expect_true(p2$dispatch)
  expect_equal(p2$timeout_sec, 300L)
  expect_equal(p2$reason, "bounded_by_deadline")

  # Sonraki derin sorgu yalnızca ARTAN bütçeyi alır.
  p3 <- pk_sql_timeout_plan(120, 45.9)
  expect_true(p3$dispatch)
  expect_equal(p3$timeout_sec, 45L)  # AŞAĞI yuvarlanır; bütçeyi asla aşmaz
  expect_equal(p3$reason, "bounded_by_deadline")
})

test_that("pozitif bütçe kalmadığında ifade GÖNDERİLMEZ", {
  for (kalan in list(0, -1, 0.4)) {
    p <- pk_sql_timeout_plan(120, kalan)
    expect_false(p$dispatch, info = sprintf("kalan=%s", kalan))
    expect_equal(p$timeout_sec, 0L)
    expect_equal(p$reason, "deadline_exhausted")
  }
})

test_that("ardışık zaman aşımlarının toplamı analiz bütçesini AŞMAZ", {
  # Beş derin sorgu, her biri 120 sn yapılandırılmış zaman aşımıyla, 300 sn
  # bütçe altında: toplam etkin zaman aşımı 300'ü geçmemelidir.
  butce <- 300
  kalan <- butce
  toplam <- 0
  gonderilen <- 0L

  for (i in 1:5) {
    p <- pk_sql_timeout_plan(120, kalan)
    if (!isTRUE(p$dispatch)) break
    gonderilen <- gonderilen + 1L
    toplam <- toplam + p$timeout_sec
    kalan <- kalan - p$timeout_sec
  }

  expect_lte(toplam, butce)
  # 120 + 120 + 60 = 300; dördüncü sorgu artık gönderilmez.
  expect_equal(gonderilen, 3L)
  expect_equal(toplam, 300)
})

test_that("aşama kapısı iptal ile zaman aşımını AYRI raporlar", {
  kok <- .pk_cancel_tmp_root()
  on.exit(unlink(kok, recursive = TRUE), add = TRUE)

  baslangic <- as.POSIXct("2026-08-09 10:00:00", tz = "UTC")
  son <- pk_deadline_at(baslangic, 300)
  jeton <- pk_cancel_token_path("kapi", base_dir = kok)

  ok <- pk_async_stage_gate(jeton, son, now = baslangic + 10)
  expect_false(ok$halt)
  expect_equal(ok$status, "ok")

  # Son tarih doldu -> "deadline".
  gecti <- pk_async_stage_gate(jeton, son, now = baslangic + 400)
  expect_true(gecti$halt)
  expect_equal(gecti$status, "deadline")

  # İptal, son tarihten ÖNCE değerlendirilir (kullanıcı isteği önceliklidir).
  pk_cancel_token_signal(jeton)
  iptal <- pk_async_stage_gate(jeton, son, now = baslangic + 400)
  expect_true(iptal$halt)
  expect_equal(iptal$status, "cancelled")
})

test_that("kullanıcı mesajları iptal ile zaman aşımını KARIŞTIRMAZ", {
  iptal <- pk_async_halt_message("cancelled")
  zaman <- pk_async_halt_message("deadline")

  expect_false(identical(iptal, zaman))
  expect_true(grepl("Durduruldu", iptal, fixed = TRUE))
  expect_true(grepl("Zaman", zaman, fixed = TRUE))
  # Zaman aşımını "siz iptal ettiniz" diye raporlamak YANLIŞTIR.
  expect_false(grepl("kullanıcı tarafından iptal", zaman, fixed = TRUE))
})

test_that("isci PID sondasi ana olay dongusunu BLOKE ETMEZ ve sonucsuz sonda basari degildir", {
  # `local_mocked_bindings(.package = "future")` ad alanini YUKLEMEYI gerektirir;
  # paket kurulu degilse bu bir ATLAMA degil BASARISIZLIK olur ve
  # `tests/testthat.R` `stop_on_failure = TRUE` ile tum suite'i kirar.
  testthat::skip_if_not_installed("future")
  testthat::skip_if_not_installed("withr")

  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a  # URETIM SEMANTIGI (R/utils_common.R): sifir uzunluk YEDEGE DUSMEZ.
  source(file.path(repo_root, "R", "helpers_pk_async_probe.R"),
         encoding = "UTF-8", local = env)
  source(file.path(repo_root, "R", "helpers_pk_async_plan.R"),
         encoding = "UTF-8", local = env)

  # KUSUR 1: sonda `future::value()` ile SINIRSIZ bekliyordu; tek iscili bir
  # planda o isci mesgulken TUM oturumlarin olay dongusu donuyordu.
  # Cozulmeyen bir future taklit edilir; sonda BUTCE kadar bekleyip NA doner.
  testthat::local_mocked_bindings(
    future = function(...) structure(list(), class = "sahte_future"),
    resolved = function(...) FALSE,
    value = function(...) stop("BLOKE ETMEMELIYDI"),
    .package = "future"
  )

  withr::with_envvar(list(MERGEN_PK_ASYNC_PROBE_TIMEOUT_SEC = "0.2"), {
    env$pk_async_plan_probe_reset()
    baslangic <- Sys.time()
    sonuc <- env$.pk_async_worker_pid_probe(force = TRUE)
    gecen <- as.numeric(difftime(Sys.time(), baslangic, units = "secs"))

    expect_true(is.na(sonuc), info = "Cozulmeyen sonda OLCULEMEDI (NA) olmalidir.")
    # SINIRLI BEKLEME GERCEKTEN CALISTI MI: yuva kapisi kisa devre yaptiginda
    # sonda hic yoklamadan NA doner ve test bosa gecerdi.
    expect_true(gecen >= 0.15,
                info = sprintf("Sonda butcesi kadar beklemeliydi (%.2f sn).", gecen))
    # Sinirli: butcenin biraz uzerinde ama SINIRSIZ degil.
    expect_true(gecen < 5, info = sprintf("Sonda sinirli olmalidir (%.2f sn).", gecen))
  })

  # KUSUR 2: OLCULEMEYEN sonda onbellege ALINMAZ; isci bosalinca yeniden denenir.
  # ÖNCE BAĞLAMA VARLIĞI: önbellek adı kaybolursa zincirli arama `NULL` döner
  # ve `expect_null()` sözleşmeyi HİÇ denetlemeden geçerdi.
  expect_true(is.environment(env$.pk_async_plan_probe_cache))
  expect_null(env$.pk_async_plan_probe_cache$result)
})

test_that("taban R baglanti tutamaclari isci sinirinda REDDEDILIR", {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a  # URETIM SEMANTIGI (R/utils_common.R): sifir uzunluk YEDEGE DUSMEZ.
  source(file.path(repo_root, "R", "helpers_pk_async_snapshot_validate.R"),
         encoding = "UTF-8", local = env)

  # KUSUR: yasakli sinif listesi yalnizca DBI/pool sinirlarini kapsiyordu.
  # Taban R `file()`/`textConnection()` tutamaci `connection` sinifi tasir ama
  # `externalptr` DEGIL `integer` tipindedir; kapidan geciyordu.
  dosya_yolu <- tempfile()
  fcon <- file(dosya_yolu, open = "w")
  tcon <- textConnection("sentetik")
  on.exit({
    try(close(fcon), silent = TRUE)
    try(close(tcon), silent = TRUE)
    try(unlink(dosya_yolu, force = TRUE), silent = TRUE)
  }, add = TRUE)

  for (tutamac in list(fcon, tcon)) {
    sonuc <- env$pk_async_validate_request(list(payload = tutamac))
    expect_false(isTRUE(sonuc$safe))
    expect_true(any(grepl("connection", sonuc$violations, fixed = TRUE)))
  }

  # Iç içe ve OZNITELIK icindeki tutamaclar da yakalanir.
  ic_ice <- env$pk_async_validate_request(list(a = list(b = list(c = fcon))))
  expect_false(isTRUE(ic_ice$safe))

  ozellikli <- structure(list(x = 1), tutamac = fcon)
  expect_false(isTRUE(env$pk_async_validate_request(ozellikli)$safe))

  # DUZ veri hala guvenlidir (yanlis pozitif yok).
  duz <- env$pk_async_validate_request(list(
    a = 1L, b = "metin", c = list(d = TRUE), e = as.Date("2026-01-01"),
    f = c(1.5, NA_real_)
  ))
  expect_true(isTRUE(duz$safe))
})

test_that("onbellek sinirlari KAYIP anahtarda da uzlastirilir", {
  testthat::skip_if_not_installed("withr")
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a  # URETIM SEMANTIGI (R/utils_common.R): sifir uzunluk YEDEGE DUSMEZ.
  for (f in c("helpers_pk_config.R", "helpers_pk_cache_key.R", "helpers_pk_cache.R")) {
    source(file.path(repo_root, "R", f), encoding = "UTF-8", local = env)
  }

  env$pk_cache_reset()
  for (i in 1:5) env$pk_cache_put(sprintf("anahtar_%d", i), data.frame(x = 1:10))
  expect_length(env$.pk_cache_store$entries, 5L)

  # KUSUR: eksik anahtar, sinirlar cozulmeden ONCE donuyordu; kalici bir iscide
  # operator onbellegi kapatsa bile eski girisler yerlesik kaliyordu.
  withr::with_envvar(list(MERGEN_PK_CACHE_MAX_ENTRIES = "0"), {
    sonuc <- env$pk_cache_get("hic_olmayan_anahtar")
    expect_false(isTRUE(sonuc$hit))
    expect_identical(sonuc$reason, "cache_disabled")
    expect_length(env$.pk_cache_store$entries, 0L)
    expect_equal(env$.pk_cache_store$total_bytes, 0)
  })

  # Sinir DUSURULDUGUNDE de kayip anahtarda uzlastirma calisir.
  env$pk_cache_reset()
  for (i in 1:5) env$pk_cache_put(sprintf("anahtar_%d", i), data.frame(x = 1:10))
  withr::with_envvar(list(MERGEN_PK_CACHE_MAX_ENTRIES = "2"), {
    sonuc <- env$pk_cache_get("hic_olmayan_anahtar")
    expect_identical(sonuc$reason, "miss")
    expect_true(length(env$.pk_cache_store$entries) <= 2L)
  })

  # Sinirlar normalken ISABET davranisi DEGISMEZ.
  env$pk_cache_reset()
  env$pk_cache_put("kalici", data.frame(x = 1:3))
  isabet <- env$pk_cache_get("kalici")
  expect_true(isTRUE(isabet$hit))
})

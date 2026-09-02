# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-async-worker-behavior.R
# Açıklama: Faz 6 (§5.10) — İŞÇİ giriş noktasının davranış testleri.
#           Tamamen çevrimdışı: gerçek future işçisi, DB, LLM, ağ GEREKMEZ.
#
# Kanıtlanan sözleşmeler:
#   - İşçi ASLA `stop()` ile dışarı sızmaz; her sonuç TİPLİ bir listedir.
#   - Bootstrap/giriş noktası başarısızlığı boru hattını ÇALIŞTIRMAZ.
#   - İptal ve son tarih boru hattından ÖNCE ve SONRA ayrı ayrı kontrol edilir.
#   - `stop_check` işçi-YEREL bir kapanıştır: mevcut aşama kontrolleri
#     DEĞİŞTİRİLMEDEN iptal-farkında hâle gelir.
#   - Vekil oturum boru hattına kimlik ve kişisel anahtarı taşır.
#   - Ham ODBC/DSN tanılaması ana sürece TAŞINMAZ (D22 işçide de geçerli).
#   - Motor kipi (v1/v2) işçide sabitlenir ve çıkışta GERİ ALINIR.
# ==============================================================================

.pk_worker_env <- function() {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  # ÜRETİM OPERATÖRÜYLE AYNI (`R/utils_common.R`): yalnız `NULL` yedeğe düşer.
  env$`%||%` <- function(a, b) if (is.null(a)) b else a

  for (dosya in c("helpers_pk_config.R", "helpers_pk_async_cancel.R",
                  "helpers_pk_async_worker_env.R", "helpers_pk_async_worker_pool.R", "helpers_pk_async_bootstrap_fs.R", "helpers_pk_async_bootstrap.R", "helpers_pk_async_snapshot_validate.R", "helpers_pk_async_snapshot.R", "helpers_pk_async_secrets.R",
                  "helpers_pk_async_probe.R", "helpers_pk_async_plan.R", "helpers_pk_async_request.R", "helpers_pk_exec_context.R", "helpers_pk_result_columns.R", "helpers_pk_result_size.R",
                  "helpers_pk_cache_key.R", "helpers_pk_cache.R", "helpers_pk_sql_execute.R", "helpers_pk_sql_connection.R",
                  "helpers_pk_async_worker_sql.R", "helpers_pk_async_worker.R")) {
    source(file.path(repo_root, "R", dosya), encoding = "UTF-8", local = env)
  }

  # Varsayılan: bootstrap başarılı, giriş noktaları hazır, boru hattı bağlam döner.
  # `...`: bootstrap artık aşama kapısı, işçi sayısı ve DB havuzu seçeneklerini
  # de alır (iptal/son tarih bootstrap SIRASINDA da gözlenir).
  env$pk_async_worker_bootstrap <- function(repo_root, files, ...) {
    list(ok = TRUE, loaded = length(files), failed = character(0), cached = FALSE)
  }
  env$pk_async_worker_ready <- function(...) list(ready = TRUE, missing = character(0))
  env$pk_analiz_process_request <- function(prompt, history, session, stop_check = NULL) {
    list(prompt_context = "SISTEM", user_context = "KULLANICI")
  }
  env$pk_deep_analysis_process <- function(prompt, history, session, detail_level, stop_check = NULL) {
    list(prompt_context = "DERIN", user_context = "DERIN K")
  }
  env
}

.pk_worker_request <- function(env, deep = FALSE, deadline_sec = 300,
                               cancel_token = "", engine = "v1",
                               started_at = Sys.time()) {
  env$pk_async_build_request(
    user_prompt = "İstanbul projesinin kalan işçiliği nedir?",
    chat_history = list(list(role = "user", content = "önceki soru")),
    username = "ali.veli",
    request_id = "req_w1",
    deep_thinking = deep,
    detail_level = "standart",
    api_key_plan = list(key = "sk-fake-personal", source = "personal"),
    user_session_snapshot = list(system_username = "ali.veli", user_id = 7L),
    select_state = list(s1 = list(query_id = "q001")),
    repo_root = tempdir(),
    cancel_token = cancel_token,
    deadline_sec = deadline_sec,
    engine = engine,
    bootstrap_files = c("R/utils_common.R"),
    started_at = started_at
  )
}

.pk_worker_token_root <- function() {
  yol <- file.path(tempdir(), paste0("pk_worker_", as.integer(runif(1, 1, 1e9))))
  dir.create(yol, recursive = TRUE, showWarnings = FALSE)
  yol
}

test_that("başarılı çalıştırma TİPLİ ok sonucu ve oturum yazımlarını döner", {
  env <- .pk_worker_env()
  env$pk_analiz_process_request <- function(prompt, history, session, stop_check = NULL) {
    # Boru hattı vekil oturuma yazar; işçi bunu geri toplamalıdır.
    session$userData[["pk_select_state"]] <- list(s1 = list(query_id = "q777"))
    session$userData[["pk_provenance_pending"]] <- list(footer = "alt bilgi")
    list(prompt_context = "SISTEM", user_context = "KULLANICI", max_tokens = 4096)
  }

  sonuc <- env$pk_async_run_analysis(.pk_worker_request(env))

  expect_equal(sonuc$status, "ok")
  expect_equal(sonuc$result$prompt_context, "SISTEM")
  expect_equal(sonuc$result$max_tokens, 4096)
  expect_equal(sonuc$session_writes$pk_select_state$s1$query_id, "q777")
  expect_equal(sonuc$session_writes$pk_provenance_pending$footer, "alt bilgi")
  expect_true(sonuc$diagnostics$duration_ms >= 0)
})

test_that("vekil oturum kimliği ve KİŞİSEL anahtarı boru hattına taşır", {
  env <- .pk_worker_env()
  gorulen <- new.env(parent = emptyenv())
  env$pk_analiz_process_request <- function(prompt, history, session, stop_check = NULL) {
    gorulen$username <- session$userData$system_username
    gorulen$auth <- session$userData$auth_initialized
    gorulen$key <- session$userData$ai_api_key
    gorulen$owner <- session$userData$ai_api_key_owner
    gorulen$prior <- session$userData[["pk_select_state"]]$s1$query_id
    gorulen$req <- session$userData[["pk_provenance_request_id"]]
    gorulen$prompt <- prompt
    gorulen$history_len <- length(history)
    gorulen$stop_check_is_fn <- is.function(stop_check)
    list(prompt_context = "S", user_context = "K")
  }

  env$pk_async_run_analysis(.pk_worker_request(env))

  expect_equal(gorulen$username, "ali.veli")
  expect_true(isTRUE(gorulen$auth))
  expect_equal(gorulen$key, "sk-fake-personal")
  expect_equal(gorulen$owner, "ali.veli")
  expect_equal(gorulen$prior, "q001")
  expect_equal(gorulen$req, "req_w1")
  expect_equal(gorulen$prompt, "İstanbul projesinin kalan işçiliği nedir?")
  expect_equal(gorulen$history_len, 1L)
  # KRİTİK: iptal işçiye YEREL bir kapanış olarak ulaşır (serileştirme yok).
  expect_true(gorulen$stop_check_is_fn)
})

test_that("derin mod DERİN yürütücüyü detay seviyesiyle çağırır", {
  env <- .pk_worker_env()
  gorulen <- new.env(parent = emptyenv())
  env$pk_deep_analysis_process <- function(prompt, history, session, detail_level, stop_check = NULL) {
    gorulen$detail <- detail_level
    list(prompt_context = "DERIN", user_context = "K")
  }

  sonuc <- env$pk_async_run_analysis(.pk_worker_request(env, deep = TRUE))
  expect_equal(sonuc$status, "ok")
  expect_equal(gorulen$detail, "standart")
  expect_equal(sonuc$result$prompt_context, "DERIN")
})

test_that("bootstrap başarısızlığı boru hattını ÇALIŞTIRMAZ", {
  env <- .pk_worker_env()
  cagrildi <- FALSE
  env$pk_async_worker_bootstrap <- function(...) {
    list(ok = FALSE, loaded = 3L, failed = c("R/a.R", "R/b.R"), cached = FALSE)
  }
  env$pk_analiz_process_request <- function(...) {
    cagrildi <<- TRUE
    stop("calistirilmamaliydi")
  }

  sonuc <- env$pk_async_run_analysis(.pk_worker_request(env))

  expect_false(cagrildi)
  expect_equal(sonuc$status, "bootstrap_failed")
  expect_equal(sonuc$diagnostics$bootstrap_failed, c("R/a.R", "R/b.R"))
  expect_true(nzchar(sonuc$error))
})

test_that("eksik giriş noktası boru hattını ÇALIŞTIRMAZ ve adlandırılır", {
  env <- .pk_worker_env()
  cagrildi <- FALSE
  env$pk_async_worker_ready <- function(...) {
    list(ready = FALSE, missing = c("get_connection", "apply_rls_to_data"))
  }
  env$pk_analiz_process_request <- function(...) {
    cagrildi <<- TRUE
    stop("calistirilmamaliydi")
  }

  sonuc <- env$pk_async_run_analysis(.pk_worker_request(env))

  expect_false(cagrildi)
  expect_equal(sonuc$status, "bootstrap_failed")
  expect_equal(sonuc$diagnostics$entry_missing, c("get_connection", "apply_rls_to_data"))
})

test_that("boru hattı ÖNCESİNDE işaretli iptal jetonu çalıştırmayı engeller", {
  env <- .pk_worker_env()
  kok <- .pk_worker_token_root()
  on.exit(unlink(kok, recursive = TRUE), add = TRUE)

  jeton <- env$pk_cancel_token_path("onceden_iptal", base_dir = kok)
  env$pk_cancel_token_signal(jeton)

  cagrildi <- FALSE
  env$pk_analiz_process_request <- function(...) {
    cagrildi <<- TRUE
    stop("calistirilmamaliydi")
  }

  sonuc <- env$pk_async_run_analysis(.pk_worker_request(env, cancel_token = jeton))

  expect_false(cagrildi)
  expect_equal(sonuc$status, "cancelled")
  expect_null(sonuc$result)
})

test_that("dolmuş son tarih boru hattını ÇALIŞTIRMAZ ve deadline döner", {
  env <- .pk_worker_env()
  cagrildi <- FALSE
  env$pk_analiz_process_request <- function(...) {
    cagrildi <<- TRUE
    stop("calistirilmamaliydi")
  }

  # 300 saniyelik bütçe, 400 saniye önce başlamış istek.
  istek <- .pk_worker_request(env, deadline_sec = 300, started_at = Sys.time() - 400)
  sonuc <- env$pk_async_run_analysis(istek)

  expect_false(cagrildi)
  expect_equal(sonuc$status, "deadline")
})

test_that("boru hattı İÇİNDE iptal edilirse durum cancelled olur (ok değil)", {
  env <- .pk_worker_env()
  kok <- .pk_worker_token_root()
  on.exit(unlink(kok, recursive = TRUE), add = TRUE)

  jeton <- env$pk_cancel_token_path("ortada_iptal", base_dir = kok)

  # İDDİALAR MOCK BORU HATTININ İÇİNDE DEĞİL, DÖNÜŞTEN SONRA YAPILIR.
  #
  # `pk_async_run_analysis()` boru hattı çağrısını `tryCatch(error = ...)`
  # ile sarar ve bir testthat beklenti hatası da bir HATA KOŞULUDUR: burada
  # başarısız olan bir iddia işçi tarafından yutulur, işçi onu boru hattı
  # sonrası iptal denetimine eşler ve aşağıdaki `cancelled` iddiası YİNE
  # geçerdi (yani bozuk bir `stop_check()` fark edilmezdi). Gözlenen
  # değerler önce kaydedilir.
  gorulen <- new.env(parent = emptyenv())
  env$pk_analiz_process_request <- function(prompt, history, session, stop_check = NULL) {
    # Aşama kontrolü ilk çağrıda FALSE görür; sonra kullanıcı durdurur.
    gorulen$once <- isTRUE(stop_check())
    env$pk_cancel_token_signal(jeton)
    gorulen$sonra <- isTRUE(stop_check())
    # Boru hattı kullanıcıya görünen durdurma metnini döner (mevcut davranış).
    paste0("\U000026A0\U0000FE0F", " **İşlem Durduruldu:** Analiz iptal edildi.")
  }

  sonuc <- env$pk_async_run_analysis(.pk_worker_request(env, cancel_token = jeton))

  # Aşama kapısı GERÇEKTEN önce FALSE, jeton işaretlendikten sonra TRUE gördü.
  expect_false(isTRUE(gorulen$once))
  expect_true(isTRUE(gorulen$sonra))

  # Durum TİPLİ olarak cancelled'dır; "ok + rastgele metin" DEĞİL.
  expect_equal(sonuc$status, "cancelled")
})

test_that("boru hattı hatası TİPLİ error döner ve işçiden dışarı SIZMAZ", {
  env <- .pk_worker_env()
  env$pk_analiz_process_request <- function(...) stop("basit bir R hatasi")

  sonuc <- expect_no_error(env$pk_async_run_analysis(.pk_worker_request(env)))
  expect_equal(sonuc$status, "error")
  # Faz 6 inceleme düzeltmesi: BEKLENMEYEN istisna metni kullanıcıya ASLA ham
  # dönmez (yalnızca DB-benzeri metinleri genelleştiren allowlist yeterli
  # değildi; dosya yolu/host/iç ayrıntı taşıyan metinler sızabiliyordu).
  # Redakte edilmiş orijinal SUNUCU LOGUNDA kalır.
  expect_false(grepl("basit bir R hatasi", sonuc$error, fixed = TRUE))
  expect_true(nzchar(sonuc$error))
})

test_that("HAM ODBC/DSN tanılaması ana sürece TAŞINMAZ (D22)", {
  env <- .pk_worker_env()
  gizli <- "nanodbc/nanodbc.cpp:1234: 00000: [Microsoft][ODBC Driver 17] DSN=PRODSRV;UID=svc"
  env$pk_analiz_process_request <- function(...) stop(gizli)

  sonuc <- env$pk_async_run_analysis(.pk_worker_request(env))

  expect_equal(sonuc$status, "error")
  expect_false(grepl("DSN=", sonuc$error, fixed = TRUE))
  expect_false(grepl("nanodbc", sonuc$error, fixed = TRUE))
  expect_false(grepl("PRODSRV", sonuc$error, fixed = TRUE))
  expect_true(grepl("teknik bir hata", sonuc$error, fixed = TRUE))
})

test_that("geçersiz istek anlık görüntüsü TİPLİ error döner", {
  env <- .pk_worker_env()
  expect_equal(env$pk_async_run_analysis("bu bir liste degil")$status, "error")
  expect_equal(env$pk_async_run_analysis(NULL)$status, "error")
})

test_that("motor kipi işçide sabitlenir ve çıkışta GERİ ALINIR", {
  env <- .pk_worker_env()
  eski <- getOption("mergen.pk.engine", default = NULL)
  on.exit(options(mergen.pk.engine = eski), add = TRUE)
  options(mergen.pk.engine = NULL)

  gorulen <- new.env(parent = emptyenv())
  env$pk_analiz_process_request <- function(...) {
    gorulen$engine <- getOption("mergen.pk.engine", default = NA_character_)
    list(prompt_context = "S", user_context = "K")
  }

  env$pk_async_run_analysis(.pk_worker_request(env, engine = "v2"))

  # İşçi içinde v2 sabitlenmiş olmalı...
  expect_equal(gorulen$engine, "v2")
  # ...ve çıkışta süreç durumu geri alınmış olmalı (sonraki istek sızıntı görmez).
  expect_null(getOption("mergen.pk.engine", default = NULL))
})

test_that("bootstrap memoizasyonu tanılamada raporlanır", {
  env <- .pk_worker_env()
  env$pk_async_worker_bootstrap <- function(...) {
    list(ok = TRUE, loaded = 0L, failed = character(0), cached = TRUE)
  }
  sonuc <- env$pk_async_run_analysis(.pk_worker_request(env))
  expect_true(isTRUE(sonuc$diagnostics$bootstrap_cached))
  expect_equal(sonuc$diagnostics$bootstrap_loaded, 0L)
})

test_that("bootstrap istisna atarsa da TİPLİ bootstrap_failed döner", {
  env <- .pk_worker_env()
  env$pk_async_worker_bootstrap <- function(...) stop("dosya sistemi erisilemez")
  sonuc <- expect_no_error(env$pk_async_run_analysis(.pk_worker_request(env)))
  expect_equal(sonuc$status, "bootstrap_failed")
})

# ------------------------------------------------------------------------------
# İŞÇİ GLOBALS PAKETİ: BOOTSTRAP ÖNCESİ SEMBOLLER
# ------------------------------------------------------------------------------
# `dependency_mode = "explicit"` özyinelemeli global genişletme YAPMAZ. İşçi
# bootstrap'tan ÖNCE mutlak son tarihi türetir ve ilk kapıyı yoklar; bu yolda
# kullanılan her sembol pakette AÇIKÇA taşınmalıdır. Eksik olduklarında hiçbir
# offline test kırılmaz — TEMİZ bir PSOCK işçisi ham bir "could not find
# function" ile ölür ve hata ancak ÜRETİMDE görünürdü.
test_that("işçi globals paketi bootstrap ÖNCESİ yardımcıları taşır", {
  env <- .pk_worker_env()
  paket <- env$pk_async_worker_globals(force = TRUE)

  for (ad in c("%||%", "pk_deadline_at", "pk_deadline_expired",
               "pk_deadline_remaining_sec", "pk_cancel_token_is_signalled",
               "pk_async_stage_gate", "pk_async_halt_message",
               "pk_async_worker_bootstrap", "pk_async_run_analysis")) {
    expect_true(ad %in% names(paket), info = ad)
    expect_true(is.function(paket[[ad]]), info = ad)
  }
})

# ------------------------------------------------------------------------------
# İŞÇİ TARAFI DB HAVUZU ADMİSYONU
# ------------------------------------------------------------------------------
# PSOCK işçisi ana sürecin `.GlobalEnv$pool` nesnesini göremez; havuz açıkken
# bile doğrudan `dbConnect()` yoluna düşmek `MERGEN_DB_POOL_MAX_SIZE` tavanını
# ve admisyon politikasını devre dışı bırakırdı.
test_that("bootstrap sonrasi isci havuzu YALNIZCA havuz acikken kurulur", {
  env <- .pk_worker_env()

  # PAY ORTAMI GERİ YÜKLENİR: `pk_async_worker_pool_apply_share()` süreç
  # ortamına yazar. Sızdırılırsa `pk_db_pool_process_share()` bu testthat
  # sürecinin geri kalanında TAM tavanı döndürür ve sonraki admisyon/havuz
  # testleri üretimden FARKLI bir kod yolunu sınar.
  .eski_havuz <- Sys.getenv(
    c("MERGEN_DB_POOL_SHARE_APPLIED", "MERGEN_DB_POOL_MAX_SIZE",
      "MERGEN_DB_POOL_MIN_SIZE"),
    unset = NA_character_, names = TRUE
  )
  on.exit({
    for (ad in names(.eski_havuz)) {
      if (is.na(.eski_havuz[[ad]])) Sys.unsetenv(ad)
      else do.call(Sys.setenv, stats::setNames(list(.eski_havuz[[ad]]), ad))
    }
  }, add = TRUE)

  cagrildi <- new.env(parent = emptyenv())
  cagrildi$n <- 0L
  # ÜRETİM ŞEKLİ: `init_db_pool_once()` GERÇEK bir `Pool` nesnesi döndürür.
  # `TRUE` döndürmek "havuz kuruldu" saymaz; başarı ölçütü sınıf kontrolüdür.
  sahte_havuz <- structure(list(), class = "Pool")
  env$init_db_pool_once <- function(target = "primary") {
    cagrildi$n <- cagrildi$n + 1L
    sahte_havuz
  }

  env$is_db_pool_enabled <- function() FALSE
  kapali <- env$.pk_async_worker_db_pool_init(env)
  expect_equal(cagrildi$n, 0L)
  expect_true(isTRUE(kapali$ok))
  expect_false(isTRUE(kapali$enabled))

  env$is_db_pool_enabled <- function() TRUE
  acik <- env$.pk_async_worker_db_pool_init(env)
  expect_equal(cagrildi$n, 1L)
  # DÖNÜŞ DURUMU DENETLENİR: yalnız çağrı sayısına bakmak, işçi sessizce
  # doğrudan bağlantı yedeğine düşerken testi yeşil bırakıyordu.
  expect_true(isTRUE(acik$ok))

  # Fail-fast KAPALIYKEN `NULL` dönüşü de BAŞARISIZLIKTIR.
  env$init_db_pool_once <- function(target = "primary") NULL
  expect_false(isTRUE(env$.pk_async_worker_db_pool_init(env)$ok))

  # Havuz kurulumu HATA verse bile bootstrap düşmemelidir.
  env$init_db_pool_once <- function(target = "primary") stop("havuz kurulamadi")
  hata_sonucu <- expect_no_error(env$.pk_async_worker_db_pool_init(env))
  expect_false(isTRUE(hata_sonucu$ok))
})

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
  env$`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

  for (dosya in c("helpers_pk_config.R", "helpers_pk_async_cancel.R",
                  "helpers_pk_async_bootstrap.R", "helpers_pk_async_snapshot.R",
                  "helpers_pk_async_request.R", "helpers_pk_result_size.R",
                  "helpers_pk_cache.R", "helpers_pk_sql_execute.R",
                  "helpers_pk_async_worker_sql.R", "helpers_pk_async_worker.R")) {
    source(file.path(repo_root, "R", dosya), encoding = "UTF-8", local = env)
  }

  # Varsayılan: bootstrap başarılı, giriş noktaları hazır, boru hattı bağlam döner.
  env$pk_async_worker_bootstrap <- function(repo_root, files) {
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

  env$pk_analiz_process_request <- function(prompt, history, session, stop_check = NULL) {
    # Aşama kontrolü ilk çağrıda FALSE görür; sonra kullanıcı durdurur.
    expect_false(isTRUE(stop_check()))
    env$pk_cancel_token_signal(jeton)
    expect_true(isTRUE(stop_check()))
    # Boru hattı kullanıcıya görünen durdurma metnini döner (mevcut davranış).
    "\U000026A0\U0000FE0F **İşlem Durduruldu:** Analiz iptal edildi."
  }

  sonuc <- env$pk_async_run_analysis(.pk_worker_request(env, cancel_token = jeton))

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

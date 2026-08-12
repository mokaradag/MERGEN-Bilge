# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-async-dispatch-behavior.R
# Açıklama: Faz 6 (§5.10) — PK gönderim katmanının (senkron/asenkron kararı,
#           explicit-mode gönderim, İSTEK-KİMLİĞİ KORUMALI geri çağrılar)
#           davranış testleri.
#
# Tamamen çevrimdışı: gerçek future işçisi, gerçek promises, Shiny oturumu, DB,
# LLM veya ağ GEREKMEZ. `tracked_future_promise` ve `promises::then` enjekte
# edilen sahtelerle değiştirilir; böylece geri çağrı gövdeleri SENKRON ve
# DETERMİNİSTİK biçimde çalıştırılabilir.
#
# Kanıtlanan sözleşmeler:
#   - Gönderim `dependency_mode = "explicit"` iledir ve globals paketinde
#     OTURUM/REAKTİF/BAĞLANTI YOKTUR.
#   - BAYAT ve DURDURULMUŞ geri çağrılar hiçbir şeyi mutasyona uğratmaz
#     (devam çağrılmaz, mesaj eklenmez, oturum yazımı uygulanmaz).
#   - İptal ve zaman aşımı AYRI kullanıcı mesajları üretir.
#   - Bootstrap başarısızlığı SENKRON yeniden denemeye düşer (kullanıcı doğru
#     yanıtı alır); sessiz bir hata mesajı DEĞİL.
#   - Senkron ve asenkron yol AYNI uygulama fonksiyonunu kullanır.
# ==============================================================================

.pk_dispatch_env <- function() {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())

  env$`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

  for (dosya in c("helpers_pk_config.R", "helpers_pk_async_cancel.R",
                  "helpers_pk_async_worker_env.R", "helpers_pk_async_worker_pool.R", "helpers_pk_async_bootstrap.R", "helpers_pk_async_snapshot_validate.R", "helpers_pk_async_snapshot.R",
                  "helpers_pk_async_plan.R", "helpers_pk_async_request.R", "helpers_pk_exec_context.R", "helpers_pk_result_columns.R", "helpers_pk_result_size.R",
                  "helpers_pk_async_request_markers.R",
                  "helpers_pk_async_session_registry.R",
                  "helpers_pk_async_routing.R",
                  "helpers_pk_async_lifecycle.R", "helpers_pk_async_apply.R")) {
    source(file.path(repo_root, "R", dosya), encoding = "UTF-8", local = env)
  }
  source(file.path(repo_root, "R", "server_handler_pk_async.R"),
         encoding = "UTF-8", local = env)

  # --- Varsayılan stub'lar (her test gerekeni ezer) --------------------------
  env$log_info <- function(...) invisible(NULL)
  env$log_warn <- function(...) invisible(NULL)
  env$resolve_pk_analysis_username <- function(session) {
    list(ready = TRUE, username = "ali.veli", reason = "ok")
  }
  env$mb_api_key_get_effective_key <- function(...) {
    list(key = "sk-fake-personal", source = "personal", owner = list(username = "ali.veli"))
  }
  env$pk_engine_is_v2 <- function(...) FALSE
  env$pk_analiz_process_request <- function(prompt, history, session, stop_check = NULL) {
    list(prompt_context = "SENKRON SISTEM", user_context = "SENKRON KULLANICI", max_tokens = 1111)
  }
  env$pk_deep_analysis_process <- function(prompt, history, session, detail_level, stop_check = NULL) {
    list(prompt_context = "DERIN SISTEM", user_context = "DERIN KULLANICI")
  }
  env$pk_async_worker_bootstrap_files <- function(...) c("R/utils_common.R")

  env
}

.pk_fake_session <- function(token = "tok_1") {
  ud <- new.env(parent = emptyenv())
  ud$system_username <- "ali.veli"
  ud$auth_initialized <- TRUE
  list(
    userData = ud,
    token = token,
    onSessionEnded = function(fn) invisible(NULL)
  )
}

.pk_ctx <- function(env, req_id = "req_1", active = "req_1", stopped = FALSE,
                    deep = FALSE, session = NULL, chat_id = NULL) {
  kayit <- new.env(parent = emptyenv())
  kayit$devam <- list()
  kayit$mesajlar <- list()
  kayit$cleanup <- 0L

  values <- new.env(parent = emptyenv())
  values$current_chat_id <- chat_id

  ctx <- list(
    session = session %||% .pk_fake_session(),
    values = values,
    user_message_text = "İstanbul projesinin kalan işçiliği nedir?",
    messages_to_process = list(
      list(role = "user", content = "önceki"),
      list(role = "user", content = "İstanbul projesinin kalan işçiliği nedir?")
    ),
    deep_thinking = deep,
    analysis_detail = "standart",
    req_id = req_id,
    active_request_id = function() active,
    stop_generation = function() stopped,
    cleanup_send_message = function(...) kayit$cleanup <- kayit$cleanup + 1L,
    add_message_fn = function(icerik, tur) {
      kayit$mesajlar[[length(kayit$mesajlar) + 1L]] <- list(content = icerik, type = tur)
    },
    continue_fn = function(messages, max_tokens = NULL) {
      kayit$devam[[length(kayit$devam) + 1L]] <- list(messages = messages, max_tokens = max_tokens)
    }
  )
  list(ctx = ctx, kayit = kayit)
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

# --- Sonuç uygulama (senkron ve asenkron için TEK yol) ------------------------

test_that("karakter dönüşü doğrudan yanıt olur", {
  env <- .pk_dispatch_env()
  sonuc <- env$mergen_pk_apply_analysis_result("Yetki hatası.", list(list(role = "user", content = "x")))
  expect_equal(sonuc$action, "answer")
  expect_equal(sonuc$answer, "Yetki hatası.")
})

test_that("error_message dönüşü chips ile birlikte yanıt olur", {
  env <- .pk_dispatch_env()
  sonuc <- env$mergen_pk_apply_analysis_result(
    list(type = "error_message", content = "Netleştirme gerekli",
         pk_chips = list(list(label = "A"))),
    list()
  )
  expect_equal(sonuc$action, "answer")
  expect_equal(sonuc$answer, "Netleştirme gerekli")
  expect_length(sonuc$chips, 1L)
})

test_that("bağlam dönüşü sistem mesajını BAŞA ekler ve son kullanıcı içeriğini değiştirir", {
  env <- .pk_dispatch_env()
  mesajlar <- list(
    list(role = "user", content = "eski"),
    list(role = "user", content = "asıl soru")
  )
  sonuc <- env$mergen_pk_apply_analysis_result(
    list(prompt_context = "SISTEM", user_context = "ZENGIN KULLANICI", max_tokens = 4096),
    mesajlar
  )

  expect_equal(sonuc$action, "continue")
  expect_equal(sonuc$max_output_tokens, 4096)
  expect_equal(sonuc$messages_to_process[[1]]$role, "system")
  expect_equal(sonuc$messages_to_process[[1]]$content, "SISTEM")
  expect_equal(sonuc$messages_to_process[[3]]$content, "ZENGIN KULLANICI")
  expect_equal(sonuc$messages_to_process[[2]]$content, "eski")
})

test_that("beklenmeyen dönüş tipi KAPALI BAŞARISIZ olur (devam ETMEZ)", {
  # Faz 6 inceleme düzeltmesi: liste/karakter olmayan bir sonuç "devam et"
  # sayılırsa, SQL Analizi kipinde kullanıcının ham istemi HİÇBİR veritabanı
  # bağlamı olmadan nihai LLM'e giderdi. Bir sözleşme ihlali, sessizce
  # temelsiz ama normal görünen bir yanıta dönüşmemelidir.
  env <- .pk_dispatch_env()
  mesajlar <- list(list(role = "user", content = "x"))
  sonuc <- env$mergen_pk_apply_analysis_result(42L, mesajlar)
  expect_equal(sonuc$action, "answer")
  expect_true(grepl("Analiz Tamamlanamadı", sonuc$answer, fixed = TRUE))
  expect_identical(sonuc$messages_to_process, mesajlar)
})

# --- Senkron yol --------------------------------------------------------------

test_that("bayrak kapalıyken SENKRON yol kullanılır ve işçi GÖNDERİLMEZ", {
  env <- .pk_dispatch_env()
  gonderildi <- FALSE
  env$pk_async_available <- function(...) list(available = FALSE, reason = "flag_off")
  env$tracked_future_promise <- function(...) {
    gonderildi <<- TRUE
    stop("gonderilmemeliydi")
  }

  h <- .pk_ctx(env)
  sonuc <- env$mergen_pk_analysis_execute(h$ctx)

  expect_false(gonderildi)
  expect_equal(sonuc$action, "continue")
  expect_equal(sonuc$messages_to_process[[1]]$content, "SENKRON SISTEM")
  expect_equal(sonuc$max_output_tokens, 1111)
})

test_that("derin mod senkron yolda DERİN yürütücüyü çağırır", {
  env <- .pk_dispatch_env()
  env$pk_async_available <- function(...) list(available = FALSE, reason = "flag_off")

  h <- .pk_ctx(env, deep = TRUE)
  sonuc <- env$mergen_pk_analysis_execute(h$ctx)
  expect_equal(sonuc$messages_to_process[[1]]$content, "DERIN SISTEM")
})

test_that("durdurma isteği gönderim öncesinde stop döner", {
  env <- .pk_dispatch_env()
  env$pk_async_available <- function(...) list(available = TRUE, reason = "ok")

  h <- .pk_ctx(env, stopped = TRUE)
  expect_equal(env$mergen_pk_analysis_execute(h$ctx)$action, "stop")
})

test_that("senkron yolda boru hattı hatası kullanıcıya görünen mesaja çevrilir", {
  env <- .pk_dispatch_env()
  env$pk_async_available <- function(...) list(available = FALSE, reason = "flag_off")
  env$pk_analiz_process_request <- function(...) stop("beklenmeyen R hatasi")

  h <- .pk_ctx(env)
  sonuc <- env$mergen_pk_analysis_execute(h$ctx)
  expect_equal(sonuc$action, "answer")
  # Faz 6 inceleme düzeltmesi: senkron yol VARSAYILAN üretim yoludur; ham
  # `conditionMessage()` (ODBC/DSN/sürücü tanılaması olabilir) sohbete
  # gömülmez. Kullanıcıya genel Türkçe mesaj döner, redakte edilmiş orijinal
  # sunucu logunda kalır.
  expect_true(grepl("Analiz Hatası", sonuc$answer, fixed = TRUE))
  expect_false(grepl("beklenmeyen R hatasi", sonuc$answer, fixed = TRUE))
})

test_that("SSO kimliği hazır değilse işçi HİÇ başlatılmaz (D16 kapısı)", {
  env <- .pk_dispatch_env()
  env$pk_async_available <- function(...) list(available = TRUE, reason = "ok")
  env$resolve_pk_analysis_username <- function(session) {
    list(ready = FALSE, username = NA_character_, reason = "auth_not_initialized")
  }
  gonderildi <- FALSE
  env$tracked_future_promise <- function(...) {
    gonderildi <<- TRUE
    stop("gonderilmemeliydi")
  }

  h <- .pk_ctx(env)
  sonuc <- env$mergen_pk_analysis_execute(h$ctx)

  expect_false(gonderildi)
  expect_equal(sonuc$action, "answer")
  expect_true(grepl("Kimlik Doğrulama Hazırlanıyor", sonuc$answer, fixed = TRUE))
})

# --- Asenkron gönderim -------------------------------------------------------

# Sahte gönderim altyapısı: `then()` geri çağrılarını YAKALAR, sonra test
# bunları istediği sırayla senkron çalıştırır.
.pk_arm_async <- function(env, worker_result = NULL, reject = NULL) {
  kayit <- new.env(parent = emptyenv())
  kayit$dispatch_args <- NULL
  kayit$callbacks <- NULL

  env$pk_async_available <- function(...) list(available = TRUE, reason = "ok")
  env$mergen_pk_async_repo_root <- function() tempdir()
  env$tracked_future_promise <- function(task_fn, task_type = "generic",
                                         session_token = NULL, meta = list(),
                                         globals = NULL,
                                         dependency_mode = "auto",
                                         packages = NULL) {
    kayit$dispatch_args <- list(
      task_fn = task_fn, task_type = task_type, session_token = session_token,
      globals = globals, dependency_mode = dependency_mode, packages = packages
    )
    structure(list(), class = "pk_fake_promise")
  }

  # `promises::then` `::` ile çağrılır; bu yüzden yerel bir `promises` değişkeni
  # YETMEZ. Bağlama testthat ile paket ad alanında değiştirilir ve kapsam,
  # ÇAĞIRAN testin çerçevesidir (test bitince geri alınır).
  testthat::local_mocked_bindings(
    then = function(promise, onFulfilled = NULL, onRejected = NULL, ...) {
      kayit$callbacks <- list(onFulfilled = onFulfilled, onRejected = onRejected)
      invisible(promise)
    },
    .package = "promises",
    .env = parent.frame()
  )

  kayit$fire <- function() {
    if (!is.null(reject)) return(kayit$callbacks$onRejected(reject))
    kayit$callbacks$onFulfilled(worker_result)
  }

  kayit
}

test_that("gönderim explicit-mode ve globals'da OTURUM/REAKTİF/BAĞLANTI YOK", {
  env <- .pk_dispatch_env()
  arm <- .pk_arm_async(env, worker_result = list(status = "ok", result = NULL, session_writes = list()))

  h <- .pk_ctx(env)
  sonuc <- env$mergen_pk_analysis_execute(h$ctx)

  expect_equal(sonuc$action, "deferred")
  expect_equal(arm$dispatch_args$dependency_mode, "explicit")
  expect_equal(arm$dispatch_args$task_type, "pk_analysis")
  expect_equal(arm$dispatch_args$session_token, "tok_1")

  # KRİTİK: globals paketi işçi-güvenli olmalıdır.
  dogrulama <- env$pk_async_validate_request(arm$dispatch_args$globals$request)
  expect_true(dogrulama$safe)
  expect_false("session" %in% names(arm$dispatch_args$globals))
  expect_false("values" %in% names(arm$dispatch_args$globals))
  expect_false("conn" %in% names(arm$dispatch_args$globals))
})

test_that("derin modda task_type pk_deep_analysis olur", {
  env <- .pk_dispatch_env()
  arm <- .pk_arm_async(env, worker_result = list(status = "ok"))
  h <- .pk_ctx(env, deep = TRUE)
  env$mergen_pk_analysis_execute(h$ctx)
  expect_equal(arm$dispatch_args$task_type, "pk_deep_analysis")
})

test_that("başarılı işçi sonucu DEVAMI çağırır ve oturum yazımlarını uygular", {
  env <- .pk_dispatch_env()
  arm <- .pk_arm_async(env, worker_result = list(
    status = "ok",
    result = list(prompt_context = "ISCI SISTEM", user_context = "ISCI KULLANICI",
                  max_tokens = 2222),
    session_writes = list(pk_select_state = list(s = list(query_id = "q42")))
  ))

  h <- .pk_ctx(env)
  env$mergen_pk_analysis_execute(h$ctx)
  arm$fire()

  expect_length(h$kayit$devam, 1L)
  expect_equal(h$kayit$devam[[1]]$max_tokens, 2222)
  expect_equal(h$kayit$devam[[1]]$messages[[1]]$content, "ISCI SISTEM")
  expect_equal(h$kayit$mesajlar, list())
  expect_equal(h$ctx$session$userData[["pk_select_state"]]$s$query_id, "q42")
})

test_that("BAYAT geri çağrı hiçbir şeyi mutasyona uğratmaz ve kendi slotunu bırakır", {
  env <- .pk_dispatch_env()
  arm <- .pk_arm_async(env, worker_result = list(
    status = "ok",
    result = list(prompt_context = "BAYAT", user_context = "BAYAT"),
    session_writes = list(pk_select_state = list(s = list(query_id = "bayat")))
  ))

  h <- .pk_ctx(env, req_id = "req_1", active = "req_2")
  birakilan <- character(0)
  env$mergen_send_message_release_values_token <- function(values, req_id = NULL) {
    birakilan <<- c(birakilan, as.character(req_id)[1])
    invisible(TRUE)
  }
  env$mergen_pk_analysis_execute(h$ctx)
  arm$fire()

  expect_length(h$kayit$devam, 0L)
  expect_length(h$kayit$mesajlar, 0L)
  expect_equal(h$kayit$cleanup, 0L)
  expect_equal(birakilan, "req_1")
  expect_null(h$ctx$session$userData[["pk_select_state"]])
})

test_that("sohbet değişirse aynı request id sonucu YANLIŞ sohbete uygulanmaz", {
  env <- .pk_dispatch_env()
  arm <- .pk_arm_async(env, worker_result = list(
    status = "ok",
    result = list(prompt_context = "ESKI CHAT", user_context = "ESKI CHAT"),
    session_writes = list(pk_select_state = list(s = list(query_id = "eski")))
  ))

  h <- .pk_ctx(env, chat_id = "chat_a")
  env$mergen_pk_analysis_execute(h$ctx)
  h$ctx$values$current_chat_id <- "chat_b"
  arm$fire()

  expect_length(h$kayit$devam, 0L)
  expect_length(h$kayit$mesajlar, 0L)
  expect_null(h$ctx$session$userData[["pk_select_state"]])
})

test_that("DURDURULMUŞ istek geri çağrısı hiçbir şeyi mutasyona uğratmaz", {
  env <- .pk_dispatch_env()
  arm <- .pk_arm_async(env, worker_result = list(
    status = "ok", result = list(prompt_context = "X", user_context = "X"),
    session_writes = list(pk_provenance_pending = list(footer = "bayat alt bilgi"))
  ))

  kayit_ctx <- .pk_ctx(env, req_id = "req_1", active = "req_1")
  durduruldu <- FALSE
  kayit_ctx$ctx$stop_generation <- function() durduruldu

  env$mergen_pk_analysis_execute(kayit_ctx$ctx)
  durduruldu <- TRUE
  arm$fire()

  expect_length(kayit_ctx$kayit$devam, 0L)
  expect_length(kayit_ctx$kayit$mesajlar, 0L)
  expect_null(kayit_ctx$ctx$session$userData[["pk_provenance_pending"]])
})

test_that("worker export URL'si provenance footer kopyasına da taşınır", {
  env <- .pk_dispatch_env()
  # Faz 6 inceleme düzeltmesi: sunum artık TİPLİ döner (`ok` + `result`);
  # servis edilemeyen bir ek sessizce URL'siz karta geri DÖNMEZ.
  env$mergen_pk_serve_worker_artifact <- function(result, session) {
    result$pk_answer_block <- "YENI_KART"
    list(ok = TRUE, result = result)
  }
  arm <- .pk_arm_async(env, worker_result = list(
    status = "ok",
    result = list(prompt_context = "S", user_context = "K", pk_answer_block = "ESKI_KART"),
    session_writes = list(pk_provenance_pending = list(footer = "ESKI_KART\nALT_BILGI"))
  ))

  h <- .pk_ctx(env)
  env$mergen_pk_analysis_execute(h$ctx)
  arm$fire()

  pending <- h$ctx$session$userData[["pk_provenance_pending"]]
  expect_true(grepl("YENI_KART", pending$footer, fixed = TRUE))
  expect_false(grepl("ESKI_KART", pending$footer, fixed = TRUE))
})

test_that("iptal ve zaman aşımı AYRI kullanıcı mesajları üretir", {
  env <- .pk_dispatch_env()

  arm_iptal <- .pk_arm_async(env, worker_result = list(status = "cancelled", session_writes = list()))
  h1 <- .pk_ctx(env)
  env$mergen_pk_analysis_execute(h1$ctx)
  arm_iptal$fire()

  expect_length(h1$kayit$devam, 0L)
  expect_length(h1$kayit$mesajlar, 1L)
  expect_equal(h1$kayit$cleanup, 1L)
  iptal_metni <- h1$kayit$mesajlar[[1]]$content

  arm_sure <- .pk_arm_async(env, worker_result = list(status = "deadline", session_writes = list()))
  h2 <- .pk_ctx(env)
  env$mergen_pk_analysis_execute(h2$ctx)
  arm_sure$fire()
  sure_metni <- h2$kayit$mesajlar[[1]]$content

  expect_false(identical(iptal_metni, sure_metni))
  expect_true(grepl("Durduruldu", iptal_metni, fixed = TRUE))
  expect_true(grepl("Zaman Aşımı", sure_metni, fixed = TRUE))
})

# PROMISE GERİ ÇAĞRISI ANA SHINY SÜRECİNDE çalışır. Orada `mergen_pk_run_sync()`
# çağırmak uzun bir SQL/LLM turunu OLAY DÖNGÜSÜNE taşır ve o R sürecindeki HER
# oturumu dondurur; üstelik geri çağrı bloklandığı sürece kullanıcının Durdur
# olayı da işlenemez — yani Faz 6'nın ortadan kaldırdığı D15 donması geri gelir.
# Bu yüzden geri çağrı yolunda TİPLİ ALTYAPI HATASI döner, senkron tekrar
# oynatma YAPILMAZ.
test_that("bootstrap başarısızlığı SENKRON TEKRAR OYNATMAZ (tipli altyapı hatası)", {
  env <- .pk_dispatch_env()
  senkron_cagrildi <- FALSE
  eski_senkron <- env$mergen_pk_run_sync
  env$mergen_pk_run_sync <- function(...) {
    senkron_cagrildi <<- TRUE
    eski_senkron(...)
  }

  arm <- .pk_arm_async(env, worker_result = list(
    status = "bootstrap_failed", error = "Isci yardimcilari yuklenemedi.",
    session_writes = list()
  ))

  h <- .pk_ctx(env)
  env$mergen_pk_analysis_execute(h$ctx)
  arm$fire()

  expect_false(senkron_cagrildi)
  expect_length(h$kayit$devam, 0L)
  expect_length(h$kayit$mesajlar, 1L)
  expect_true(grepl("Analiz Altyapısı Hazır Değil", h$kayit$mesajlar[[1]]$content,
                    fixed = TRUE))
})

test_that("işçi reddi (ALTYAPI hatası) SENKRON TEKRAR OYNATMAZ", {
  env <- .pk_dispatch_env()
  senkron_cagrildi <- FALSE
  eski_senkron <- env$mergen_pk_run_sync
  env$mergen_pk_run_sync <- function(...) {
    senkron_cagrildi <<- TRUE
    eski_senkron(...)
  }

  arm <- .pk_arm_async(env, reject = simpleError("isci coktu"))

  h <- .pk_ctx(env)
  env$mergen_pk_analysis_execute(h$ctx)
  arm$fire()

  expect_false(senkron_cagrildi)
  expect_length(h$kayit$devam, 0L)
  expect_length(h$kayit$mesajlar, 1L)
  expect_true(grepl("Analiz Altyapısı Hazır Değil", h$kayit$mesajlar[[1]]$content,
                    fixed = TRUE))
})

test_that("BAYAT red geri çağrısı da hiçbir şeyi mutasyona uğratmaz", {
  env <- .pk_dispatch_env()
  arm <- .pk_arm_async(env, reject = simpleError("bayat red"))
  h <- .pk_ctx(env, req_id = "req_1", active = "req_2")
  env$mergen_pk_analysis_execute(h$ctx)
  arm$fire()

  expect_length(h$kayit$mesajlar, 0L)
  expect_equal(h$kayit$cleanup, 0L)
})

test_that("gönderim hatası SENKRON yola döner (kullanıcı yanıtsız kalmaz)", {
  env <- .pk_dispatch_env()
  env$pk_async_available <- function(...) list(available = TRUE, reason = "ok")
  env$mergen_pk_async_repo_root <- function() tempdir()
  env$tracked_future_promise <- function(...) stop("worker pool dolu")

  h <- .pk_ctx(env)
  sonuc <- env$mergen_pk_analysis_execute(h$ctx)

  expect_equal(sonuc$action, "continue")
  expect_equal(sonuc$messages_to_process[[1]]$content, "SENKRON SISTEM")
})

test_that("işçi-güvensiz anlık görüntü SENKRON yola döner (sessiz serileştirme yok)", {
  env <- .pk_dispatch_env()
  env$pk_async_available <- function(...) list(available = TRUE, reason = "ok")
  env$mergen_pk_async_repo_root <- function() tempdir()
  gonderildi <- FALSE
  env$tracked_future_promise <- function(...) {
    gonderildi <<- TRUE
    structure(list(), class = "pk_fake_promise")
  }
  env$pk_async_build_request <- function(...) list(kotu = new.env())

  h <- .pk_ctx(env)
  sonuc <- env$mergen_pk_analysis_execute(h$ctx)

  expect_false(gonderildi)
  expect_equal(sonuc$action, "continue")
  expect_equal(sonuc$messages_to_process[[1]]$content, "SENKRON SISTEM")
})

test_that("oturum kapanışı yalnız AKTİF session-scoped jetonu işaretler", {
  env <- .pk_dispatch_env()
  arm <- .pk_arm_async(env, worker_result = list(status = "ok", result = NULL, session_writes = list()))

  oturum <- .pk_fake_session("tok_close")
  kapanis <- NULL
  oturum$onSessionEnded <- function(fn) kapanis <<- fn

  h <- .pk_ctx(env, session = oturum)
  env$mergen_pk_analysis_execute(h$ctx)

  expect_true(is.function(kapanis))
  jeton <- env$mergen_pk_cancel_token_for_session(oturum, "req_1")
  expect_false(env$pk_cancel_token_is_signalled(jeton))
  kapanis()
  expect_true(env$pk_cancel_token_is_signalled(jeton))
  env$pk_cancel_token_clear(jeton)
})

test_that("tamamlanmış isteğin session-end callback'i jetonu yeniden yaratmaz", {
  env <- .pk_dispatch_env()
  arm <- .pk_arm_async(env, worker_result = list(status = "ok", result = NULL, session_writes = list()))

  oturum <- .pk_fake_session("tok_done")
  kapanis <- NULL
  oturum$onSessionEnded <- function(fn) kapanis <<- fn
  h <- .pk_ctx(env, session = oturum)
  jeton <- env$mergen_pk_cancel_token_for_session(oturum, "req_1")

  env$mergen_pk_analysis_execute(h$ctx)
  arm$fire()
  expect_false(env$pk_cancel_token_is_signalled(jeton))
  kapanis()
  expect_false(env$pk_cancel_token_is_signalled(jeton))
})

test_that("mergen_pk_signal_cancel session-scoped jetonu yazar; geçersiz kimlikte no-op", {
  env <- .pk_dispatch_env()
  oturum <- .pk_fake_session("tok_cancel")
  jeton <- env$mergen_pk_cancel_token_for_session(oturum, "iptal_testi")
  env$pk_cancel_token_clear(jeton)

  expect_true(env$mergen_pk_signal_cancel("iptal_testi", session = oturum))
  expect_true(env$pk_cancel_token_is_signalled(jeton))
  env$pk_cancel_token_clear(jeton)

  expect_false(env$mergen_pk_signal_cancel(NULL, session = oturum))
  expect_false(env$mergen_pk_signal_cancel("", session = oturum))
  expect_false(env$mergen_pk_signal_cancel(NA_character_, session = oturum))
})

test_that("aynı req_id iki oturumda farklı iptal jetonlarına ayrılır", {
  env <- .pk_dispatch_env()
  a <- env$mergen_pk_cancel_token_for_session(.pk_fake_session("tok_A"), "req_1")
  b <- env$mergen_pk_cancel_token_for_session(.pk_fake_session("tok_B"), "req_1")
  expect_false(identical(a, b))
})

test_that("gönderim öncesinde yalnız kendi BAYAT jetonu temizlenir", {
  env <- .pk_dispatch_env()
  oturum <- .pk_fake_session("tok_stale")
  jeton <- env$mergen_pk_cancel_token_for_session(oturum, "req_1")
  env$pk_cancel_token_signal(jeton)
  expect_true(env$pk_cancel_token_is_signalled(jeton))

  arm <- .pk_arm_async(env, worker_result = list(status = "ok"))
  h <- .pk_ctx(env, session = oturum)
  env$mergen_pk_analysis_execute(h$ctx)

  expect_false(env$pk_cancel_token_is_signalled(jeton))
})

test_that("işçi durum metni bilinmeyen durumda genel hata verir", {
  env <- .pk_dispatch_env()
  expect_true(grepl("Analiz modülü hatası",
                    env$mergen_pk_worker_outcome_text("error", NA), fixed = TRUE))
  expect_true(grepl("Analiz Altyapısı Hazır Değil",
                    env$mergen_pk_worker_outcome_text("bootstrap_failed"), fixed = TRUE))
})

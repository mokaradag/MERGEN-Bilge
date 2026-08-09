# ==============================================================================
# Dosya Yolu: R/helpers_pk_async_apply.R
# Açıklama: Faz 6 (§5.10) — PK analiz sonucunu mesaj bağlamına uygulama,
#           SENKRON yürütme yolu, işçi durum -> kullanıcı metni eşlemesi ve
#           asenkron istek hazırlığı.
#
# `R/server_handler_pk_async.R` içinden BÖLÜNMÜŞTÜR (bakım ratchet'inin
# 25-fonksiyon tavanı). Ayrım aynı zamanda daha iyi bir sınır: "sonucu nasıl
# uygularım / senkron nasıl çalıştırırım" ile "işçiyi nasıl gönderip yaşam
# döngüsünü korurum" farklı sorumluluklardır.
#
# SENKRON ve ASENKRON yolun AYNI uygulama fonksiyonunu kullanması bilinçlidir:
# iki ayrı uygulama, `MERGEN_PK_ASYNC` açıldığında sessiz davranış farkı üretirdi.
# ==============================================================================


#' Analiz sonucunu mesaj bağlamına uygula (SENKRON ve ASENKRON için TEK yol)
#'
#' Senkron ve asenkron yolun aynı uygulama fonksiyonunu kullanması bilinçlidir:
#' iki ayrı uygulama, `MERGEN_PK_ASYNC` açıldığında sessiz davranış farkı üretirdi.
#'
#' @return `list(action = "continue"|"answer"|"stop", messages_to_process=,
#'   max_output_tokens=, answer=, chips=)`.
mergen_pk_apply_analysis_result <- function(analiz_result, messages_to_process) {
  if (is.character(analiz_result)) {
    return(list(action = "answer", answer = as.character(analiz_result)[1],
                messages_to_process = messages_to_process, chips = list()))
  }

  if (!is.list(analiz_result)) {
    return(list(action = "continue", messages_to_process = messages_to_process,
                max_output_tokens = NULL))
  }

  if (identical(analiz_result$type, "error_message")) {
    return(list(
      action = "answer",
      answer = as.character(analiz_result$content %||% "Analiz tamamlanamadı.")[1],
      messages_to_process = messages_to_process,
      chips = analiz_result$pk_chips %||% list()
    ))
  }

  son <- length(messages_to_process)
  if (son > 0L && !is.null(analiz_result$user_context)) {
    messages_to_process[[son]]$content <- analiz_result$user_context
  }

  if (!is.null(analiz_result$prompt_context)) {
    messages_to_process <- append(
      list(list(role = "system", content = analiz_result$prompt_context, type = "system")),
      messages_to_process
    )
  }

  list(action = "continue", messages_to_process = messages_to_process,
       max_output_tokens = analiz_result$max_tokens)
}

#' Analizi SENKRON çalıştır (v1 uyumluluk yolu; `MERGEN_PK_ASYNC=false`)
#'
#' Davranış Faz 5 sonundaki hâliyle BİREBİR aynıdır. Bu fonksiyon yalnızca
#' mevcut çağrıyı tek bir yere toplar ki asenkron yol ile karşılaştırılabilir olsun.
mergen_pk_run_sync <- function(ctx) {
  tryCatch({
    if (isTRUE(ctx$deep_thinking)) {
      pk_deep_analysis_process(
        ctx$user_message_text, ctx$messages_to_process, ctx$session,
        detail_level = ctx$analysis_detail,
        stop_check = ctx$stop_generation
      )
    } else {
      pk_analiz_process_request(
        ctx$user_message_text, ctx$messages_to_process, ctx$session,
        stop_check = ctx$stop_generation
      )
    }
  }, error = function(e) {
    paste0("\U000026A0\U0000FE0F Analiz modülü hatası: ", conditionMessage(e))
  })
}

#' İşçi durum kodunu kullanıcıya görünen sonuca çevir
mergen_pk_worker_outcome_text <- function(status, error = NA_character_) {
  if (identical(status, "cancelled") || identical(status, "deadline")) {
    return(pk_async_halt_message(status))
  }

  if (identical(status, "bootstrap_failed")) {
    return(paste0(
      "\U000026A0\U0000FE0F **Analiz Altyapısı Hazır Değil:** Analiz arka plan ",
      "işçisinde başlatılamadı. Analiz senkron olarak yeniden denendi."
    ))
  }

  mesaj <- tryCatch(as.character(error)[1], error = function(e) NA_character_)
  if (is.null(mesaj) || length(mesaj) == 0L || is.na(mesaj) || !nzchar(mesaj)) {
    mesaj <- "Analiz tamamlanamadı."
  }
  paste0("\U000026A0\U0000FE0F Analiz modülü hatası: ", mesaj)
}

#' Asenkron gönderim için istek anlık görüntüsünü hazırla
#'
#' Kimlik ve API anahtarı ANA SÜREÇTE çözülür. Bu, D16'nın SSO hazırlık
#' ihlalini de kapatır: kimlik hazır değilse işçi HİÇ başlatılmaz ve kullanıcı
#' mevcut Türkçe "kimlik hazırlanıyor" mesajını alır.
#'
#' @return `list(ok=TRUE, request=)` veya `list(ok=FALSE, answer=)`.
mergen_pk_prepare_async_request <- function(ctx) {
  kimlik <- tryCatch(resolve_pk_analysis_username(ctx$session), error = function(e) NULL)
  if (!is.list(kimlik) || !isTRUE(kimlik$ready)) {
    return(list(ok = FALSE, answer = paste0(
      "\U000023F3 **Kimlik Doğrulama Hazırlanıyor:** ",
      "Proje ve Kaynak Analizi için kullanıcı kimliğiniz henüz hazır değil. ",
      "Lütfen SSO oturumunuz tamamlandıktan sonra tekrar deneyin."
    )))
  }

  anahtar_plani <- tryCatch(
    mb_api_key_get_effective_key(
      session = ctx$session, require_auth = TRUE,
      allow_default = NULL, clear_on_mismatch = TRUE
    ),
    error = function(e) list(key = "", source = "missing", owner = NULL)
  )

  jeton <- pk_cancel_token_path(ctx$req_id)
  # Bayat bir jeton dosyası (önceki süreç çökmesi) yeni isteği ANINDA iptal
  # ederdi; bu yüzden gönderimden önce temizlenir.
  pk_cancel_token_clear(jeton)

  motor <- if (exists("pk_engine_is_v2", mode = "function", inherits = TRUE) &&
               isTRUE(tryCatch(pk_engine_is_v2(), error = function(e) FALSE))) "v2" else "v1"

  istek <- pk_async_build_request(
    user_prompt = ctx$user_message_text,
    chat_history = ctx$messages_to_process,
    username = kimlik$username,
    request_id = ctx$req_id,
    deep_thinking = isTRUE(ctx$deep_thinking),
    detail_level = ctx$analysis_detail,
    api_key_plan = anahtar_plani,
    user_session_snapshot = pk_async_capture_user_data(ctx$session),
    select_state = tryCatch(ctx$session$userData[["pk_select_state"]], error = function(e) NULL),
    repo_root = mergen_pk_async_repo_root(),
    cancel_token = jeton,
    deadline_sec = tryCatch(
      pk_config_resolve("MERGEN_PK_ANALYSIS_DEADLINE_SEC"), error = function(e) 300L
    ),
    engine = motor,
    bootstrap_files = pk_async_worker_bootstrap_files(),
    started_at = Sys.time()
  )

  dogrulama <- pk_async_validate_request(istek)
  if (!isTRUE(dogrulama$safe)) {
    # Sessizce serileştirmeye çalışmak yerine SENKRON yola dönülür: işçi
    # tarafında anlaşılmaz bir serileştirme hatası almak, kullanıcıya yanlış
    # bir "analiz başarısız" mesajı göstermekten daha kötüdür.
    log_warn(paste0(
      "[PK_ASYNC] Istek anlik goruntusu isci-guvenli degil; senkron yola donuluyor: ",
      paste(utils::head(dogrulama$violations, 5L), collapse = ", ")
    ))
    return(list(ok = FALSE, fallback_sync = TRUE))
  }

  list(ok = TRUE, request = istek, cancel_token = jeton)
}

# Repo kökü: işçi `getwd()` VARSAYMAZ (çalışma dizini işçide farklı olabilir).
mergen_pk_async_repo_root <- function() {
  kok <- Sys.getenv("MERGEN_REPO_ROOT", unset = "")
  if (nzchar(kok) && dir.exists(kok)) {
    return(normalizePath(kok, winslash = "/", mustWork = FALSE))
  }
  normalizePath(getwd(), winslash = "/", mustWork = FALSE)
}

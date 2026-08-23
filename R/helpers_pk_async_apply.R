# ==============================================================================
# Dosya Yolu: R/helpers_pk_async_apply.R
# Faz 6: PK async sonuç uygulama, senkron fallback ve ana-süreç yardımcıları.
# ==============================================================================

mergen_pk_apply_analysis_result <- function(analiz_result, messages_to_process) {
  if (is.character(analiz_result)) {
    return(list(action = "answer", answer = as.character(analiz_result)[1],
                messages_to_process = messages_to_process, chips = list()))
  }
  # Beklenmeyen bir tip (NULL, sayı, ...) "devam et" olarak yorumlanamaz:
  # SQL Analizi kipinde bu, kullanıcının ham istemini HİÇBİR veritabanı
  # bağlamı olmadan nihai LLM'e göndermek demektir. Bir sözleşme ihlali,
  # sessizce temelsiz ama normal görünen bir yanıta dönüşmemelidir.
  if (!is.list(analiz_result)) {
    try(log_warn(sprintf(
      "[PK] Analiz sonucu beklenmeyen tipte (%s); istek kapali basarisiz.",
      paste(class(analiz_result), collapse = "/")
    )), silent = TRUE)
    return(list(
      action = "answer",
      answer = paste0(
        "\U000026A0\U0000FE0F **Analiz Tamamlanamadı:** Analiz beklenmeyen bir ",
        "sonuç üretti ve güvenli biçimde sürdürülemedi. Lütfen tekrar deneyin."
      ),
      messages_to_process = messages_to_process, chips = list()
    ))
  }
  if (identical(analiz_result$type, "error_message")) {
    return(list(action = "answer",
                answer = as.character(analiz_result$content %||% "Analiz tamamlanamadı.")[1],
                messages_to_process = messages_to_process,
                chips = analiz_result$pk_chips %||% list()))
  }
  # TİPLİ TERMİNAL SONUÇ "devam et" DEĞİLDİR (PR #703 incelemesi).
  # `.pk_result_v2()` paket/dışa aktarım sırasında Durdur gelirse
  # `list(type = "pk_stopped")` döndürür. Eskiden yalnızca `error_message`
  # ele alınıyordu; bu liste her iki kapıdan da geçip `action = "continue"`
  # üretiyordu — yani iptal edilmiş bir analizde kullanıcının HAM istemi
  # hiçbir veri bağlamı olmadan nihai LLM'e gidiyor ve TEMELSİZ ama normal
  # görünen bir yanıt üretiliyordu.
  # SON TARİH ile KULLANICI İPTALİ AYRI raporlanır: `pk_stopped` taşıdığı
  # `pk_halt_status` ile gelir; taşımıyorsa eski davranış (`cancelled`) geçerlidir.
  if (identical(analiz_result$type, "pk_stopped")) {
    halt_durumu <- as.character(analiz_result$pk_halt_status %||% "cancelled")[1]
    if (is.na(halt_durumu) || !nzchar(halt_durumu)) halt_durumu <- "cancelled"
    return(list(action = "answer",
                answer = if (exists("pk_async_halt_message", mode = "function", inherits = TRUE)) {
                  pk_async_halt_message(halt_durumu)
                } else {
                  "\U000026A0\U0000FE0F **İşlem Durduruldu:** Analiz kullanıcı tarafından iptal edildi."
                },
                messages_to_process = messages_to_process, chips = list()))
  }
  # KAPALI BAŞARISIZ BEYAZ LİSTE: yalnızca BİLİNEN başarı şekilleri devam
  # edebilir. Hem tekil (`.pk_result_v1/v2`) hem derin analiz bağlamı
  # `prompt_context` + `user_context` taşır; bunları taşımayan bir liste
  # (yeni bir terminal tip, bozuk paket) sessizce "bağlamsız devam"a
  # dönüşmemelidir.
  # HER İKİSİ DE ZORUNLU ("ve" değil "veya"): tek başına `prompt_context`
  # TEMELSİZ yanıt, tek başına `user_context` talimatsız analiz demektir.
  if (is.null(analiz_result$user_context) || is.null(analiz_result$prompt_context)) {
    try(log_warn(sprintf(
      "[PK] Analiz sonucu bilinmeyen terminal tip (%s); istek kapali basarisiz.",
      as.character(analiz_result$type %||% "<tipsiz>")[1]
    )), silent = TRUE)
    return(list(
      action = "answer",
      answer = paste0(
        "\U000026A0\U0000FE0F **Analiz Tamamlanamadı:** Analiz beklenmeyen bir ",
        "sonuç üretti ve güvenli biçimde sürdürülemedi. Lütfen tekrar deneyin."
      ),
      messages_to_process = messages_to_process, chips = list()
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

# `MERGEN_PK_ASYNC` VARSAYILAN OLARAK KAPALI olduğundan bu yakalama NORMAL
# üretim yoludur. `conditionMessage()` metnini olduğu gibi sohbete gömmek,
# modülün SQL hata sanitizasyonundan ÖNCE oluşan bir ODBC/DSN/sürücü
# tanılamasını doğrudan kullanıcıya gösterirdi. İşçi yolu zaten redakte
# ediyor; senkron yol da AYNI sınırı uygular.
PK_SYNC_GENERIC_ERROR_MESSAGE <- paste0(
  "\U000026A0\U0000FE0F **Analiz Hatası:** Analiz sırasında beklenmeyen bir ",
  "hata oluştu. Lütfen tekrar deneyin."
)

mergen_pk_run_sync <- function(ctx) {
  tryCatch({
    if (isTRUE(ctx$deep_thinking)) {
      pk_deep_analysis_process(
        ctx$user_message_text, ctx$messages_to_process, ctx$session,
        detail_level = ctx$analysis_detail, stop_check = ctx$stop_generation
      )
    } else {
      pk_analiz_process_request(
        ctx$user_message_text, ctx$messages_to_process, ctx$session,
        stop_check = ctx$stop_generation
      )
    }
  }, error = function(e) {
    ham <- tryCatch(conditionMessage(e), error = function(x) "")
    if (exists("redact_sensitive_text", mode = "function", inherits = TRUE)) {
      ham <- tryCatch(redact_sensitive_text(ham), error = function(x) "[redaksiyon yok]")  # fail-closed
    }
    try(log_error(sprintf("[PK_SYNC] Analiz modulu hatasi: %s", substr(ham, 1L, 400L))),
        silent = TRUE)
    PK_SYNC_GENERIC_ERROR_MESSAGE
  })
}

# req_id oturumlar arasında çakışabilir; token adı session$token ile namespace edilir.
mergen_pk_cancel_token_for_session <- function(session, request_id) {
  oturum <- try(as.character(session$token %||% "")[1], silent = TRUE)
  if (inherits(oturum, "try-error")) oturum <- ""
  if (is.na(oturum) || !nzchar(oturum)) oturum <- "session"
  file.path(
    pk_cancel_token_root(),
    paste0("pk_stop_", .pk_cancel_token_slug(oturum), "_",
           .pk_cancel_token_slug(request_id), ".flag")
  )
}

#' @param started_at İSTEĞİN ORİJİNAL başlangıç anı. Hazırlık önemsiz olmayan
#'   bir süre alır; `Sys.time()`ı burada YENİDEN okumak işçi son tarihini ve ana
#'   süreç bekçisini o kadar İLERİ atar ve istek
#'   `MERGEN_PK_ANALYSIS_DEADLINE_SEC` sınırını hazırlık süresi kadar aşabilirdi.
mergen_pk_prepare_async_request <- function(ctx, started_at = NULL) {
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

  # GÜVENLİK YAPILANDIRMASI EKSİKSİZ OLMALIDIR.
  #
  # Tek bir güvenlik anahtarı çözülemediğinde (geçersiz değer, bozuk spec)
  # anlık görüntü onu TAŞIMAZ ve işçi kurulumu yalnızca VAR OLAN anahtarları
  # yazar; sıcak bir PSOCK işçisi o anahtarda BAYAT (daha gevşek olabilen)
  # değerini korurdu. Eksik anlık görüntü bir YAPILANDIRMA ARIZASIDIR: istek
  # asenkron gönderilmez, sınırlı senkron yola düşer.
  config_ss <- tryCatch(pk_async_config_snapshot(), error = function(e) NULL)
  if (!is.list(config_ss) || !isTRUE(pk_async_config_snapshot_complete(config_ss))) {
    eksik <- as.character(attr(config_ss, "pk_missing_keys", exact = TRUE) %||% character(0))
    log_warn(paste0(
      "[PK_ASYNC] Guvenlik yapilandirmasi anlik goruntusu EKSIK; senkron yola donuluyor: ",
      paste(utils::head(eksik, 5L), collapse = ", ")
    ))
    return(list(ok = FALSE, fallback_sync = TRUE))
  }
  config_ss <- pk_async_config_snapshot_plain(config_ss)

  jeton <- mergen_pk_cancel_token_for_session(ctx$session, ctx$req_id)
  pk_cancel_token_clear(jeton)
  motor <- if (exists("pk_engine_is_v2", mode = "function", inherits = TRUE) &&
               isTRUE(tryCatch(pk_engine_is_v2(), error = function(e) FALSE))) "v2" else "v1"

  istek <- pk_async_build_request(
    user_prompt = ctx$user_message_text, chat_history = ctx$messages_to_process,
    username = kimlik$username, request_id = ctx$req_id,
    deep_thinking = isTRUE(ctx$deep_thinking), detail_level = ctx$analysis_detail,
    api_key_plan = anahtar_plani, user_session_snapshot = pk_async_capture_user_data(ctx$session),
    select_state = tryCatch(ctx$session$userData[["pk_select_state"]], error = function(e) NULL),
    repo_root = mergen_pk_async_repo_root(), cancel_token = jeton,
    deadline_sec = tryCatch(pk_config_resolve("MERGEN_PK_ANALYSIS_DEADLINE_SEC"),
                            error = function(e) 300L),
    engine = motor, bootstrap_files = pk_async_worker_bootstrap_files(),
    started_at = started_at %||% Sys.time(),
    # Ana süreçte çözülmüş `options()` basamağı işçiye taşınır; aksi hâlde
    # kalıcı PSOCK işçisi farklı güvenlik sınırlarıyla çalışabilir.
    config_snapshot = config_ss
  )

  dogrulama <- pk_async_validate_request(istek)
  if (!isTRUE(dogrulama$safe)) {
    log_warn(paste0(
      "[PK_ASYNC] Istek anlik goruntusu isci-guvenli degil; senkron yola donuluyor: ",
      paste(utils::head(dogrulama$violations, 5L), collapse = ", ")
    ))
    return(list(ok = FALSE, fallback_sync = TRUE))
  }

  # JETON SAHİPLİĞİ EN SON ve KAPALI BAŞARISIZ kaydedilir.
  #
  # (a) Hazırlık başarısız olan yollarda (kimlik hazır değil, anlık görüntü
  #     işçi-güvenli değil) sahiplik HİÇ kaydedilmez; aksi hâlde senkron yolda
  #     basılan Durdur, hiçbir PK yolunun temizlemediği bir `.flag` bırakırdı.
  # (b) Sahiplik KALICI OLARAK yazılamıyorsa gönderim YAPILMAZ: o durumda Durdur
  #     gözlemcisi bu isteği sahiplenmediği için işçinin dosya jetonunu HİÇ
  #     işaretlemez — yani iptal edilemeyen bir işçi kalırdı. Senkron yola
  #     dönmek (orada Durdur `stop_check` ile çalışır) DAHA GÜVENLİDİR.
  if (!isTRUE(mergen_pk_register_cancel_token(ctx$session, ctx$req_id))) {
    log_warn("[PK_ASYNC] Iptal jetonu sahipligi kaydedilemedi; senkron yola donuluyor.")
    return(list(ok = FALSE, fallback_sync = TRUE))
  }
  list(ok = TRUE, request = istek, cancel_token = jeton)
}

# DOSYA SİSTEMİ SONDASI OLAY DÖNGÜSÜNDE TEKRARLANMAZ: bu çözümleme işçi
# gönderilmeden ÖNCE paylaşılan süreçte senkron çalışır ve `MERGEN_REPO_ROOT`
# yanıt vermeyen bir UNC/NFS noktasını gösterdiğinde HER istekte bloklardı.
# Girdi (env + çalışma dizini) başına bir kez çözülür; testlerde girdi
# değişince yeniden çözümlenir.
.pk_async_repo_root_cache <- new.env(parent = emptyenv())

mergen_pk_async_repo_root <- function() {
  kok <- Sys.getenv("MERGEN_REPO_ROOT", unset = "")
  wd <- getwd()
  anahtar <- paste0(kok, "\u001f", wd)
  onbellek <- .pk_async_repo_root_cache[[anahtar]]
  if (!is.null(onbellek)) return(onbellek)
  if (length(ls(.pk_async_repo_root_cache, all.names = TRUE)) > 32L) {
    rm(list = ls(.pk_async_repo_root_cache, all.names = TRUE),
       envir = .pk_async_repo_root_cache)
  }
  cozum <- normalizePath(if (nzchar(kok) && dir.exists(kok)) kok else wd,
                         winslash = "/", mustWork = FALSE)
  assign(anahtar, cozum, envir = .pk_async_repo_root_cache)
  cozum
}

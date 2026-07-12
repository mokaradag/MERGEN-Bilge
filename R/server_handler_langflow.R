# ==============================================================================
# Dosya Yolu: R/server_handler_langflow.R
# Açıklama: "Süreç Yönetimi Sistemi" ve "Uygulama Uzmanı" araçlarının kurumsal
#           Langflow akışına (Chat Input / Chat Output) yönlendirilen işleyicisi.
#           Bu araçlar artık normal yerel LLM uç noktasını ve MCP araçlarını
#           kullanmaz; bunun yerine yapılandırılmış Langflow akışını çağırır.
#           Asenkron çağrı, görsel oluşturma işleyicisiyle aynı tracked future +
#           bayat-istek koruması desenini izler.
# ==============================================================================

# Langflow sohbet modunu işle.
# ctx: mesaj gönderme bağlamından gerekli değişkenleri içeren liste.
# Döndürür: TRUE (işlendi ve send_message erken dönüş yapmalı).
handle_langflow_chat_mode <- function(ctx) {
  config <- ctx$api_config %||% api_config
  tool_family <- ctx$tool_family

  lf_cfg <- mergen_langflow_config(config)
  base_url <- normalize_langflow_base_url(lf_cfg$base_url)
  # Süreç Yönetimi çoklu akış: seçilen akış (key/id) çözülür; diğer aileler tekil.
  selected_process_flow <- ctx$selected_process_flow
  flow_id <- mergen_langflow_flow_id_for_family(tool_family, config, selected_flow = selected_process_flow)
  # Yalnızca loglama/metadata için akış adı (API anahtarı/URL asla loglanmaz).
  flow_label <- tryCatch(
    if (identical(tool_family, "process")) {
      mergen_langflow_process_flow_label(config, selected_process_flow)
    } else {
      ""
    },
    error = function(e) ""
  )
  api_key <- tryCatch(as.character(lf_cfg$api_key %||% "")[1], error = function(e) "")
  timeout_seconds <- suppressWarnings(as.numeric(lf_cfg$timeout_seconds %||% 300))
  if (length(timeout_seconds) == 0 || is.na(timeout_seconds) || timeout_seconds <= 0) {
    timeout_seconds <- 300
  }

  log_debug("[LANGFLOW] Araç={tool_family} akış={flow_label} için Langflow akışı çağrılıyor")

  # Yarış koruması: bu isteğin kimliğini en başta yakala. Kullanıcı durdurup yeni
  # bir istek başlatırsa bayat sonuç yeni isteğin yazma alanını/sohbetini ezmemeli.
  active_request_id_local <- ctx$active_request_id
  stop_generation_local <- ctx$stop_generation
  req_id_local <- tryCatch(
    if (is.function(active_request_id_local)) active_request_id_local() else NULL,
    error = function(e) NULL
  )

  # Backpressure slotu yaşam döngüsü: send_message slotu values$backpressure_token
  # içine devretti. Bu asenkron yol normal cleanup callback'ini çağırmadığından,
  # slot bu istek bitince (başarı/hata/iptal) açıkça serbest bırakılır. req_id
  # koruması yeni bir isteğin slotunu yanlışlıkla serbest bırakmayı engeller.
  # Backpressure kapalıyken (varsayılan) token NULL'dur ve bu çağrı no-op'tur.
  release_langflow_backpressure_slot <- function() {
    mergen_send_message_release_values_token(ctx$values, req_id = req_id_local)
  }

  is_stale_langflow_request <- function() {
    if (!is.function(active_request_id_local) || is.null(req_id_local)) {
      return(FALSE)
    }
    !mergen_is_current_request(active_request_id_local, req_id_local, stop_generation_local)
  }

  # Yapılandırma eksikse net, kullanıcı dostu hata ver ve normal LLM yoluna geçme.
  if (!nzchar(base_url) || !nzchar(flow_id)) {
    log_warn("[LANGFLOW] Yapılandırma eksik (araç={tool_family}); taban URL veya akış kimliği çözülemedi")
    release_langflow_backpressure_slot()
    removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
    ctx$values$typing <- FALSE
    ctx$add_message_fn(
      paste0(
        "\U000026A0\U0000FE0F Bu araç için kurumsal Langflow yapılandırması eksik ",
        "veya seçili süreç akışı bulunamadı. Lütfen sistem yöneticisiyle iletişime ",
        "geçin (LANGFLOW_BASE_URL ve süreç akışı kimlikleri)."
      ),
      "ai"
    )
    ctx$reset_chat_state_fn()
    return(TRUE)
  }

  # Oturum kimliği çözülen akış kimliğiyle daraltılır; böylece aynı Mergen
  # sohbetinde farklı süreç akışları arasında geçildiğinde Langflow'un session_id
  # ile anahtarlanan sohbet belleği akışlar arasında karışmaz (akış başına
  # süreklilik korunur).
  session_id <- mergen_build_langflow_session_id(ctx$current_user_id, ctx$chat_id_val, flow_id = flow_id)

  # Standart düşünme paneli (simüle fazlı) send_message tarafından zaten
  # gösterildi ve Langflow non-streaming yanıtı gelene kadar canlı kalır.
  # Görsel oluşturma spinner'ı KULLANILMAZ; böylece bu araçlar diğer düşünen
  # model akışlarıyla aynı deneyimi verir.

  # Asenkron çağrı için yalnızca skalar yereller yakalanır (ağır api_config
  # nesnesi worker tarafına taşınmaz).
  input_value_local <- ctx$user_message_text
  base_url_local <- base_url
  flow_id_local <- flow_id
  api_key_local <- api_key
  session_id_local <- session_id
  timeout_local <- timeout_seconds

  tracked_future_promise(
    task_fn = function() {
      call_langflow_chat(
        input_value = input_value_local,
        base_url = base_url_local,
        flow_id = flow_id_local,
        api_key = api_key_local,
        session_id = session_id_local,
        timeout_seconds = timeout_local
      )
    },
    task_type = "langflow_chat",
    session_token = ctx$session$token,
    meta = list(tool_family = tool_family)
  ) %...>% (function(result) {
    # Bayat sonuç: kullanıcı durdurup yeni istek başlattıysa UI mutasyonu yapma.
    # Durdurma/iptal yolunda (Durdur) henüz yeni istek başlamamış olabilir; bu
    # durumda slot hâlâ bu isteğe aittir ve req_id korumalı serbest bırakma onu
    # açar. Yeni bir istek slotun sahibiyse koruma no-op yapar.
    if (isTRUE(is_stale_langflow_request())) {
      release_langflow_backpressure_slot()
      return(invisible(NULL))
    }

    release_langflow_backpressure_slot()
    removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
    ctx$values$typing <- FALSE

    if (isTRUE(result$success)) {
      # Belge kaynakları (başlık/yol/sayfa/tür) düz metin Kaynakça işaretleyici
      # bloğu olarak içeriğe eklenir; render sırasında process_message_content
      # bloğu güvenli tıklanabilir .source-link HTML'ine yükseltir. İçerik DB'ye
      # işaretleyiciyle kaydedildiği için kayıtlı sohbet yeniden yüklemesinde de
      # aynı tıklanabilir Kaynakça üretilir.
      final_text <- result$text
      if (exists("mergen_langflow_kaynakca_marker_block", mode = "function", inherits = TRUE)) {
        kaynak_blok <- tryCatch(
          mergen_langflow_kaynakca_marker_block(result$sources),
          error = function(e) ""
        )
        if (nzchar(kaynak_blok)) {
          final_text <- paste0(final_text, kaynak_blok)
        }
      }
      ctx$add_message_fn(final_text, "ai")
    } else {
      err_msg <- result$error %||% "Langflow yanıtı alınamadı."
      # Hata önizlemesi worker tarafında üretildiğinden, ana süreçte (sır
      # redaksiyon yardımcısı garanti yüklüyken) yeniden redakte edilir; böylece
      # bir üst-akış/proxy hatası API anahtarını prose içinde yansıtsa bile
      # sohbete/toast'a sızmaz. Redaksiyon idempotenttir.
      if (exists("redact_sensitive_text", mode = "function", inherits = TRUE)) {
        err_msg <- redact_sensitive_text(err_msg)
      }
      ctx$add_message_fn(paste0("\U000026A0\U0000FE0F ", err_msg), "ai")
      showToast(ctx$session, err_msg, "error")
    }

    ctx$reset_chat_state_fn()
  }) %...!% (function(err) {
    # Bayat hata sonucu da yeni isteğin durumunu etkilememeli. Durdurma/iptal
    # yolunda slot hâlâ bu isteğe ait olabilir; req_id korumalı serbest bırakma
    # onu açar, yeni istek sahibiyse no-op olur.
    if (isTRUE(is_stale_langflow_request())) {
      release_langflow_backpressure_slot()
      return(invisible(NULL))
    }

    release_langflow_backpressure_slot()
    removeUI(selector = "#typing-animation-wrapper", immediate = TRUE)
    ctx$values$typing <- FALSE
    ctx$add_message_fn(paste0("\U0000274C Langflow hatası: ", err$message), "ai")
    showToast(ctx$session, paste("Hata:", err$message), "error")
    ctx$reset_chat_state_fn()
  })

  TRUE
}

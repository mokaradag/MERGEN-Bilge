# ==============================================================================
# Dosya Yolu: R/module_claude_code_akis.R
# Açıklama: Claude Code canlı akış (streaming) yardımcı fonksiyonlarını içerir.
#           Akış parçalarını istemciye gönderme (send_parca) ve akışı sonlandırma
#           (finalize_streaming) fonksiyonlarını sağlar. module_claude_code.R
#           sunucu fonksiyonu tarafından oluşturulur ve kullanılır.
# ==============================================================================

#' Akış Yardımcılarını Oluştur
#'
#' Claude Code canlı akış işlemleri için gerekli yardımcı fonksiyonları
#' oluşturur ve bir liste olarak döndürür. Döndürülen fonksiyonlar oturum
#' kapsamında çalışır (session, ns, rv referanslarını taşır).
#'
#' @param session Shiny session nesnesi
#' @param ns Ad alanı fonksiyonu (session$ns)
#' @param rv Reaktif değerler (is_running, active_process, stream_env vs.)
#' @return Liste: send_parca ve finalize_streaming fonksiyonları
create_akis_yardimcilari <- function(session, ns, rv) {

  # --- Akış parçası gönderme ---
  # stream-json formatındaki olayları istemciye iletir.
  # Desteklenen parça tipleri:
  #   text_delta: Metin parçası (anlık gösterilir)
  #   tool_use: Araç kullanımı başlangıcı (kabuk bloğu oluşturur)
  #   tool_input_delta: Araç girdisi parçası (komut bilgisi geldiğinde günceller)
  #   tool_result: Araç sonucu (mevcut bloğu günceller)
  #   content_block_stop: İçerik bloğu sonu
  #   assistant: Eski format uyumluluğu (alt blokları ayrı gönderir)
  #   result: Son sonuç (oturum kimliğini kaydeder)
  send_parca <- function(parca, env) {
    if (is.null(parca)) return()

    send_chunk <- function(tip, html, arac_id = "", ekstra = list()) {
      mesaj <- c(
        list(
          target = ns("output_area"),
          welcomeId = ns("welcome_screen"),
          chunkType = tip,
          html = html,
          toolId = arac_id,
          accentColor = env$karakter_renk,
          characterName = env$karakter_adi,
          timestamp = env$zaman_damgasi
        ),
        ekstra
      )
      session$sendCustomMessage(type = "cc-stream-chunk", message = mesaj)
    }

    tip <- parca$tip

    if (tip == "text_delta") {
      # Metin parçası - anlık olarak istemciye ilet
      icerik <- parca$icerik %||% ""
      if (nzchar(icerik)) {
        send_chunk("text_delta", htmltools::htmlEscape(icerik))
      }

    } else if (tip == "tool_input_delta") {
      # Araç girdisi JSON parçası - istemcide biriktirmek için ilet
      send_chunk("tool_input_delta", parca$parcali_json %||% "",
                 ekstra = list(blockIndex = parca$blok_indeks %||% 0))

    } else if (tip == "content_block_stop") {
      # İçerik bloğu tamamlandı - istemciye bildir
      send_chunk("content_block_stop", "",
                 ekstra = list(blockIndex = parca$blok_indeks %||% 0))

    } else if (tip == "tool_use") {
      # Araç kullanımı başladı - canlı kabuk bloğu oluştur
      fmt <- format_streaming_chunk_html(parca)
      if (!is.null(fmt)) {
        send_chunk(fmt$tip, fmt$html, fmt$arac_id %||% "")
      }

    } else if (tip == "tool_result") {
      # Araç sonucu geldi - mevcut bloğu güncelle
      fmt <- format_streaming_chunk_html(parca)
      if (!is.null(fmt)) {
        send_chunk(fmt$tip, fmt$html, fmt$arac_id %||% "")
      }

    } else if (tip == "result") {
      # Son sonuç - oturum kimliğini kaydet
      if (!is.null(parca$session_id) && nzchar(parca$session_id %||% "")) {
        env$oturum_id <- parca$session_id
      }
      # Son sonucu metin olarak gönder
      fmt <- format_streaming_chunk_html(parca)
      if (!is.null(fmt)) send_chunk("text", fmt$html)

    } else if (tip == "assistant" && !is.null(parca$bloklar)) {
      # Eski format: asistan mesajını alt bloklarına ayır
      for (blok in parca$bloklar) {
        blok_fmt <- format_streaming_chunk_html(blok)
        if (!is.null(blok_fmt)) {
          send_chunk(blok_fmt$tip, blok_fmt$html, blok_fmt$arac_id %||% "")
        }
      }

    } else if (tip == "message_start" || tip == "message_delta" || tip == "message_stop") {
      # Mesaj seviyesi olaylar - şimdilik yoksay
      NULL

    } else if (tip == "text" || tip == "raw_text") {
      # Eski format metin veya ham metin
      fmt <- format_streaming_chunk_html(parca)
      if (!is.null(fmt)) {
        send_chunk(fmt$tip, fmt$html, fmt$arac_id %||% "")
      }
    }
  }

  # --- Akış sonlandırma ---
  # Akış tamamlandığında, hata oluştuğunda veya durdurulduğunda çağrılır.
  # UI öğelerini (düğmeler, düşünme animasyonu, durum çubuğu) günceller.
  finalize_streaming <- function(durum_metin, durum_ikon, durum_renk, sure = NULL) {
    rv$is_running <- FALSE
    rv$active_process <- NULL
    rv$stream_env <- NULL

    # Düğmeleri güncelle
    session$sendCustomMessage(
      type = "cc-finalize-ui",
      message = list(
        runBtnId = ns("run_command"),
        stopBtnId = ns("stop_command")
      )
    )

    # Düşünme animasyonunu durdur
    session$sendCustomMessage(
      type = "cc-thinking-stop",
      message = list(
        overlayId = ns("thinking_overlay"),
        statusId = ns("status_text"),
        durationId = ns("duration_text")
      )
    )

    # Durum çubuğunu güncelle
    session$sendCustomMessage(
      type = "cc-update-status",
      message = list(
        statusId = ns("status_text"),
        durationId = ns("duration_text"),
        status = durum_metin,
        statusIcon = durum_ikon,
        statusColor = durum_renk,
        duration = if (!is.null(sure)) paste0(sure, " sn") else ""
      )
    )
  }

  # Yardımcı fonksiyonları döndür
  list(
    send_parca = send_parca,
    finalize_streaming = finalize_streaming
  )
}

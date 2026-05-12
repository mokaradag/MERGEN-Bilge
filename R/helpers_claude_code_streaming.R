# ==============================================================================
# Dosya Yolu: R/helpers_claude_code_streaming.R
# Açıklama: Claude Code CLI canlı akış desteği. processx ile alt süreç
#           çıktılarını satır satır okuyarak kabuk komutları, dosya işlemleri
#           ve metin parçalarını anlık olarak istemciye iletir.
# ==============================================================================

# ------------------------------------------------------------------------------
# CANLI AKIŞ İLE CLI ÇALIŞTIRMA
# Sürecin çıktısını satır satır okuyarak parçaları bir geri çağırma
# fonksiyonuna iletir. Bu sayede kullanıcı kabuk komutlarını ve araç
# kullanımlarını gerçek zamanlı görebilir.
# ------------------------------------------------------------------------------

#' Claude Code CLI komutunu canlı akış ile çalıştır
#'
#' @param prompt Kullanıcının gönderdiği komut/soru metni
#' @param workdir Çalışma dizini (proje klasörü)
#' @param model Kullanılacak model adı (boş ise varsayılan)
#' @param timeout_sec Zaman aşımı süresi (saniye)
#' @param session_id CLI oturum kimliği (--resume için)
#' @param cli_path Claude Code CLI çalıştırılabilir dosya yolu
#' @param on_chunk Parça geldiğinde çağrılacak fonksiyon (tip, veri)
#' @return Liste: success, output, error, duration, tool_uses, session_id
run_claude_code_streaming <- function(prompt,
                                       workdir = getwd(),
                                       model = NULL,
                                       timeout_sec = 300L,
                                       session_id = NULL,
                                       cli_path = NULL,
                                       on_chunk = NULL) {
  baslangic <- Sys.time()

  # Girdi doğrulaması
  if (!nzchar(trimws(prompt))) {
    return(list(
      success = FALSE, output = "", error = "Komut metni boş olamaz.",
      duration = 0, tool_uses = list(), session_id = NULL
    ))
  }

  # CLI yolunu çözümle
  if (is.null(cli_path) || !nzchar(cli_path)) {
    cli_path <- resolve_claude_cli_path(claude_code_config$cli_path)
  }
  if (is.null(cli_path)) {
    return(list(
      success = FALSE, output = "",
      error = "Claude Code CLI bulunamadı. Lütfen CLI yolunu kontrol edin.",
      duration = 0, tool_uses = list(), session_id = NULL
    ))
  }

  # Çalışma dizini kontrolü
  if (!dir.exists(workdir)) {
    return(list(
      success = FALSE, output = "",
      error = paste0("Çalışma dizini bulunamadı: ", workdir),
      duration = 0, tool_uses = list(), session_id = NULL
    ))
  }

  # CLI argümanları (stream-json ile gerçek zamanlı çıktı)
  # --verbose bayrağı stream-json formatı için zorunlu
  args <- c(
    "--print",
    "--verbose",
    "--output-format", "stream-json",
    "--include-partial-messages",
    "--dangerously-skip-permissions"
  )

  if (!is.null(model) && nzchar(model)) {
    args <- c(args, "--model", model)
  }

  if (!is.null(session_id) && nzchar(session_id)) {
    args <- c(args, "--resume", session_id)
  }

  args <- c(args, prompt)

  tryCatch({
    log_info(paste(CLAUDE_CODE_LOG_PREFIX, "Akış modu ile CLI çalıştırılıyor"))

    # Windows'ta .cmd dosyalarını cmd.exe üzerinden çalıştır
    komut <- build_processx_command(cli_path, args)

    proc <- processx::process$new(
      command = komut$command,
      args = komut$args,
      env = komut$env,
      wd = workdir,
      stdout = "|",
      stderr = "|",
      cleanup = TRUE,
      cleanup_tree = TRUE
    )

    # Sonuç biriktirici
    tum_cikti <- ""
    tum_satirlar <- c()
    son_zaman <- Sys.time()
    zaman_asimi_ms <- timeout_sec * 1000

    # Satır satır oku (yoklama döngüsü)
    while (proc$is_alive()) {
      # Zaman aşımı kontrolü
      gecen_sure <- as.numeric(difftime(Sys.time(), baslangic, units = "secs"))
      if (gecen_sure > timeout_sec) {
        tryCatch(proc$kill(), error = function(e) NULL)
        log_error(paste(CLAUDE_CODE_LOG_PREFIX, "Akış zaman aşımı:", timeout_sec, "sn"))
        return(list(
          success = FALSE, output = tum_cikti,
          error = paste0("İşlem zaman aşımına uğradı (", timeout_sec, " saniye)."),
          duration = round(gecen_sure, 1), tool_uses = list(), session_id = NULL
        ))
      }

      # stdout'tan oku (kısa bekleme ile)
      # Windows'ta processx yerel kodlama kullanır; UTF-8'e dönüştür
      proc$poll_io(200)
      yeni_veri <- tryCatch(ensure_utf8(proc$read_output_lines()), error = function(e) character(0))

      if (length(yeni_veri) > 0) {
        for (satir in yeni_veri) {
          satir <- trimws(satir)
          if (!nzchar(satir)) next

          tum_satirlar <- c(tum_satirlar, satir)
          tum_cikti <- paste0(tum_cikti, satir, "\n")

          # Parçayı ayrıştır ve geri çağırmaya ilet
          if (!is.null(on_chunk)) {
            parca <- parse_streaming_chunk(satir)
            if (!is.null(parca)) {
              tryCatch(
                on_chunk(parca),
                error = function(e) {
                  log_warn(paste(CLAUDE_CODE_LOG_PREFIX,
                                 "Akış parçası geri çağırma hatası:",
                                 conditionMessage(e)))
                }
              )
            }
          }
        }
      }
    }

    # Kalan çıktıyı oku (UTF-8'e dönüştür)
    kalan <- tryCatch(ensure_utf8(proc$read_all_output()), error = function(e) "")
    if (nzchar(kalan)) {
      kalan_satirlar <- strsplit(kalan, "\n")[[1]]
      for (satir in kalan_satirlar) {
        satir <- trimws(satir)
        if (!nzchar(satir)) next
        tum_satirlar <- c(tum_satirlar, satir)
        tum_cikti <- paste0(tum_cikti, satir, "\n")

        if (!is.null(on_chunk)) {
          parca <- parse_streaming_chunk(satir)
          if (!is.null(parca)) {
            tryCatch(on_chunk(parca), error = function(e) NULL)
          }
        }
      }
    }

    stderr_metin <- tryCatch(ensure_utf8(proc$read_all_error()), error = function(e) "")
    cikis_kodu <- proc$get_exit_status()
    sure <- as.numeric(difftime(Sys.time(), baslangic, units = "secs"))

    if (identical(cikis_kodu, 0L)) {
      log_info(paste(CLAUDE_CODE_LOG_PREFIX, "Akış tamamlandı - Süre:",
                     round(sure, 1), "sn"))

      # Tam çıktıyı ayrıştır
      ayristirma <- parse_claude_code_json_output(tum_cikti)

      list(
        success = TRUE,
        output = ayristirma$text_output,
        error = "",
        duration = round(sure, 1),
        tool_uses = ayristirma$tool_uses,
        session_id = ayristirma$session_id
      )
    } else {
      hata_mesaji <- if (nzchar(stderr_metin)) stderr_metin else tum_cikti
      temiz_log <- gsub("[{}]", "", substr(hata_mesaji, 1, 200))
      log_warn(paste(CLAUDE_CODE_LOG_PREFIX, "Akış hata kodu:", cikis_kodu,
                     "- Mesaj:", temiz_log))
      list(
        success = FALSE, output = tum_cikti, error = hata_mesaji,
        duration = round(sure, 1), tool_uses = list(), session_id = NULL
      )
    }

  }, error = function(e) {
    sure <- as.numeric(difftime(Sys.time(), baslangic, units = "secs"))
    hata_metni <- conditionMessage(e)
    temiz_hata <- gsub("[{}]", "", hata_metni)
    log_error(paste(CLAUDE_CODE_LOG_PREFIX, "Akış CLI hatası:", temiz_hata))
    list(
      success = FALSE, output = "",
      error = paste0("Claude Code çalıştırılırken hata oluştu: ", hata_metni),
      duration = round(sure, 1), tool_uses = list(), session_id = NULL
    )
  })
}

# ------------------------------------------------------------------------------
# TEK SATIR JSONL AYRIŞTIRMA (AKIŞ PARCASI)
# Her satırı ayrıştırıp tip ve içerik bilgisi döndürür.
# stream-json formatı: {"type":"stream_event","event":{...},"session_id":"..."}
# Eski json formatı da geriye uyumluluk için desteklenir.
# ------------------------------------------------------------------------------

#' Akış parçasını (tek JSONL satırı) ayrıştır
#'
#' stream-json formatında her satır bir stream_event sarmalayıcısı içerir.
#' İç olay (event) Anthropic API akış formatını takip eder:
#' content_block_start, content_block_delta, content_block_stop,
#' message_start, message_delta, message_stop vb.
#'
#' @param satir Tek bir JSON satırı
#' @return Liste: tip ve ilgili veriler, veya NULL
parse_streaming_chunk <- function(satir) {
  tryCatch({
    if (exists("normalize_text_utf8", mode = "function", inherits = TRUE)) {
      satir <- normalize_text_utf8(satir, repair_mojibake = TRUE)
    }

    nesne <- jsonlite::fromJSON(satir, simplifyVector = FALSE)
    tur <- nesne$type %||% ""

    # --- stream-json formatı (sarmalayıcı ile) ---
    if (tur == "stream_event") {
      olay <- nesne$event
      if (is.null(olay)) return(NULL)
      oturum_id <- nesne$session_id %||% NULL
      return(parse_stream_event(olay, oturum_id))
    }

    # --- Eski json formatı (geriye uyumluluk) ---
    if (tur == "text") {
      return(list(tip = "text", icerik = nesne$content %||% ""))

    } else if (tur == "tool_use") {
      return(parse_tool_use_nesne(nesne))

    } else if (tur == "tool_result") {
      return(list(
        tip = "tool_result",
        arac_id = nesne$tool_use_id %||% "",
        icerik = nesne$content %||% ""
      ))

    } else if (tur == "result") {
      return(list(
        tip = "result",
        icerik = nesne$result %||% "",
        session_id = nesne$session_id %||% NULL
      ))

    } else if (tur == "assistant") {
      bloklar <- list()
      if (!is.null(nesne$content) && is.list(nesne$content)) {
        for (blok in nesne$content) {
          blok_tur <- blok$type %||% ""
          if (blok_tur == "text") {
            bloklar <- c(bloklar, list(list(tip = "text", icerik = blok$text %||% "")))
          } else if (blok_tur == "tool_use") {
            bloklar <- c(bloklar, list(parse_tool_use_nesne(blok)))
          }
        }
      }
      return(list(tip = "assistant", bloklar = bloklar))
    }

    return(NULL)
  }, error = function(e) {
    return(list(tip = "raw_text", icerik = satir))
  })
}

# ------------------------------------------------------------------------------
# STREAM-JSON OLAY AYRIŞTIRMA
# Anthropic API akış formatındaki olayları dahili tiplere dönüştürür.
# ------------------------------------------------------------------------------

#' stream-json formatındaki bir olayı ayrıştır
#'
#' @param olay İç olay nesnesi (event alanı)
#' @param oturum_id Oturum kimliği (sarmalayıcıdan)
#' @return Ayrıştırılmış parça listesi veya NULL
parse_stream_event <- function(olay, oturum_id = NULL) {
  normalize_stream_text <- function(value) {
    if (exists("normalize_text_utf8", mode = "function", inherits = TRUE)) {
      return(normalize_text_utf8(value, repair_mojibake = TRUE))
    }
    value
  }

  olay_turu <- olay$type %||% ""

  if (olay_turu == "content_block_start") {
    # İçerik bloğu başlangıcı (metin veya araç kullanımı)
    blok <- olay$content_block
    if (is.null(blok)) return(NULL)
    blok_turu <- blok$type %||% ""

    if (blok_turu == "tool_use") {
      # Araç kullanımı başladı - girdi henüz boş, sonra delta ile gelecek
      arac_adi <- blok$name %||% ""
      arac_turu <- detect_tool_type(arac_adi)
      return(list(
        tip = "tool_use",
        arac_id = blok$id %||% "",
        arac_adi = arac_adi,
        arac_turu = arac_turu,
        girdi = blok$input %||% list(),
        komut = "",
        dosya_yolu = "",
        dosya_icerigi = "",
        # Hangi içerik bloğu olduğunu takip et
        blok_indeks = olay$index %||% 0
      ))
    } else if (blok_turu == "text") {
      # Metin bloğu başlangıcı (genelde boş, delta ile dolar)
      ilk_metin <- blok$text %||% ""
      if (nzchar(ilk_metin)) {
        return(list(tip = "text_delta", icerik = ilk_metin))
      }
      return(NULL)
    }
    return(NULL)

  } else if (olay_turu == "content_block_delta") {
    # İçerik parçası (metin veya araç girdisi delta)
    delta <- olay$delta
    if (is.null(delta)) return(NULL)
    delta_turu <- delta$type %||% ""

    if (delta_turu == "text_delta") {
      # Metin parçası - anlık olarak gösterilecek
      return(list(
        tip = "text_delta",
        icerik = normalize_stream_text(delta$text %||% "")
      ))

    } else if (delta_turu == "input_json_delta") {
      # Araç girdisi JSON parçası - biriktirmek gerekir
      return(list(
        tip = "tool_input_delta",
        parcali_json = normalize_stream_text(delta$partial_json %||% ""),
        blok_indeks = olay$index %||% 0
      ))
    }
    return(NULL)

  } else if (olay_turu == "content_block_stop") {
    # İçerik bloğu sonu
    return(list(
      tip = "content_block_stop",
      blok_indeks = olay$index %||% 0
    ))

  } else if (olay_turu == "message_start") {
    # Mesaj başlangıcı (model bilgisi içerir)
    mesaj <- olay$message
    return(list(
      tip = "message_start",
      model = if (!is.null(mesaj)) mesaj$model %||% "" else ""
    ))

  } else if (olay_turu == "message_delta") {
    # Mesaj seviyesi güncelleme (durdurma nedeni, token kullanımı)
    return(list(tip = "message_delta"))

  } else if (olay_turu == "message_stop") {
    # Mesaj tamamlandı
    return(list(tip = "message_stop"))

  } else if (olay_turu == "result") {
    # Son sonuç
    return(list(
      tip = "result",
      icerik = normalize_stream_text(olay$result %||% ""),
      session_id = oturum_id
    ))
  }

  return(NULL)
}

# ------------------------------------------------------------------------------
# ARAÇ KULLANIMI NESNE AYRIŞTIRMA YARDIMCISI
# tool_use tipindeki nesneleri standart formata dönüştürür.
# ------------------------------------------------------------------------------

#' Araç kullanımı nesnesini standart formata dönüştür
#' @param nesne tool_use JSON nesnesi
#' @return Standart araç kullanımı listesi
parse_tool_use_nesne <- function(nesne) {
  girdi <- nesne$input %||% list()
  arac_adi <- nesne$name %||% ""
  arac_turu <- detect_tool_type(arac_adi)

  list(
    tip = "tool_use",
    arac_id = nesne$id %||% "",
    arac_adi = arac_adi,
    arac_turu = arac_turu,
    girdi = girdi,
    komut = girdi$command %||% girdi$cmd %||% "",
    dosya_yolu = girdi$path %||% girdi$file_path %||% "",
    dosya_icerigi = girdi$content %||% girdi$new_content %||% ""
  )
}

# ------------------------------------------------------------------------------
# ARAÇ TÜRÜ TESPİTİ
# Araç adından türü belirler (kabuk, dosya okuma, dosya yazma, arama vb.)
# ------------------------------------------------------------------------------

#' Araç adından türünü tespit et
#'
#' @param arac_adi Araç adı
#' @return Araç türü: "bash", "file_read", "file_write", "search", "other"
detect_tool_type <- function(arac_adi) {
  arac_adi <- tolower(arac_adi)
  if (grepl("bash|execute|shell|command", arac_adi)) {
    return("bash")
  } else if (grepl("read|file_read", arac_adi)) {
    return("file_read")
  } else if (grepl("write|file_write|edit|create", arac_adi)) {
    return("file_write")
  } else if (grepl("search|grep|glob|find", arac_adi)) {
    return("search")
  } else {
    return("other")
  }
}
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
#' @param stop_file İsteğe bağlı durdurma bayrak dosyası: yoklama döngüsünde bu
#'   yol GERÇEK bir dosya olarak var olduğunda süreç öldürülür ve sonuç
#'   stopped=TRUE ile döner (SSE işçisindeki stop-file deseniyle aynı sözleşme).
#' @return Liste: success, output, error, duration, tool_uses, session_id,
#'   stopped (yalnızca kullanıcı durdurmasında TRUE)
run_claude_code_streaming <- function(prompt,
                                       workdir = getwd(),
                                       model = NULL,
                                       timeout_sec = 300L,
                                       session_id = NULL,
                                       cli_path = NULL,
                                       on_chunk = NULL,
                                       stop_file = NULL,
                                       api_key = NULL) {
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
  workdir_policy <- cc_policy_validate_workdir(
    workdir,
    allow_system_temp = TRUE
  )
  if (!isTRUE(workdir_policy$ok)) {
    return(list(
      success = FALSE, output = "",
      error = workdir_policy$error,
      duration = 0, tool_uses = list(), session_id = NULL
    ))
  }
  workdir <- workdir_policy$path

  prompt_path_policy <- cc_policy_validate_prompt_file_intent(prompt, workdir = workdir)
  if (!isTRUE(prompt_path_policy$ok)) return(list(success = FALSE, output = "", error = prompt_path_policy$error, duration = 0, tool_uses = list(), session_id = NULL))

  # CLI argümanları merkezi güvenlik ilkesinden oluştur
  # --verbose bayrağı stream-json formatı için zorunlu
  args <- cc_policy_build_cli_args(
    prompt = prompt,
    output_format = "stream-json",
    model = model,
    session_id = session_id,
    include_partial_messages = TRUE,
    verbose = TRUE,
    workdir = workdir
  )

  tryCatch({
    log_info(paste(CLAUDE_CODE_LOG_PREFIX, "Akış modu ile CLI çalıştırılıyor"))

    # Windows'ta .cmd dosyalarını cmd.exe üzerinden çalıştır
    komut <- build_processx_command(cli_path, args, workdir = workdir)

    # Etkin API anahtarı çalışma anında alt süreç ortamına enjekte edilir
    # (run_claude_code ile aynı sözleşme; dosyaya/günlüğe asla yazılmaz).
    if (exists("cc_apply_runtime_api_key_env", mode = "function", inherits = TRUE)) {
      komut$env <- cc_apply_runtime_api_key_env(komut$env, api_key)
    }

	proc <- processx::process$new(
	  command = komut$command,
	  args = komut$args,
	  env = komut$env,
	  wd = komut$wd %||% workdir,
	  stdout = "|",
	  stderr = "|",
	  cleanup = TRUE,
	  cleanup_tree = TRUE,
	  windows_verbatim_args = isTRUE(komut$windows_verbatim_args)
	)

    # Sonuç biriktirici
    tum_cikti <- ""
    tum_satirlar <- c()
    son_zaman <- Sys.time()
    zaman_asimi_ms <- timeout_sec * 1000

    # Durdurma bayrağı: yalnızca gerçek bir DOSYA durdurma isteğidir (dizin,
    # boş yol veya NA hiçbir zaman durdurmaz; SSE stop-file sözleşmesi).
    durdurma_istendi <- function() {
      if (is.null(stop_file) || length(stop_file) != 1L) {
        return(FALSE)
      }
      yol <- as.character(stop_file)[1]
      if (is.na(yol) || !nzchar(yol)) {
        return(FALSE)
      }
      isTRUE(tryCatch(
        file.exists(yol) && !dir.exists(yol),
        error = function(e) FALSE
      ))
    }

    # Satır satır oku (yoklama döngüsü)
    while (proc$is_alive()) {
      # Kullanıcı durdurması: süreç öldürülür, o ana dek biriken çıktı korunur.
      if (durdurma_istendi()) {
        tryCatch(proc$kill(), error = function(e) NULL)
        gecen <- as.numeric(difftime(Sys.time(), baslangic, units = "secs"))
        log_info(paste(CLAUDE_CODE_LOG_PREFIX, "Akış kullanıcı tarafından durduruldu"))
        return(list(
          success = FALSE, output = tum_cikti,
          error = "Çalıştırma kullanıcı tarafından durduruldu.",
          duration = round(gecen, 1), tool_uses = list(), session_id = NULL,
          stopped = TRUE
        ))
      }

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

    if (exists("normalize_text_tree_utf8", mode = "function", inherits = TRUE)) {
      nesne <- normalize_text_tree_utf8(nesne, repair_mojibake = TRUE)
    }

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
      # Claude Code CLI stream-json çıktısında asistan içerik blokları
      # genelde nesne$message$content altında gelir; eski kod yalnızca
      # nesne$content yolundan okuduğu için tool_use blokları canlı akışta
      # araç bloğu olarak gözükmüyordu.
      #
      # --include-partial-messages açıkken aynı metin önce content_block_delta
      # text_delta olarak granular akıştan geldi; sonra asistan toplu bloku
      # tekrar metin içeriyor. Canlı akışta metin parçalarını tekrar yayarsak
      # son mesaj iki kere görünür. Bu yüzden asistan blokunda yalnızca
      # tool_use kayıtlarını yayınla (text bloklarını yoksay).
      bloklar <- list()
      icerik_bloklari <- nesne$message$content
      if (is.null(icerik_bloklari)) {
        icerik_bloklari <- nesne$content
      }

      # Bazı on-prem proxy varyantları içerik bloğunu tek nesne olarak
      # gönderebiliyor; standart Anthropic formatı her zaman dizidir.
      if (!is.null(icerik_bloklari) &&
          is.list(icerik_bloklari) &&
          !is.null(icerik_bloklari$type)) {
        icerik_bloklari <- list(icerik_bloklari)
      }

      if (!is.null(icerik_bloklari) && is.list(icerik_bloklari)) {
        for (blok in icerik_bloklari) {
          if (!is.list(blok)) next
          blok_tur <- blok$type %||% ""
          if (blok_tur == "tool_use") {
            bloklar <- c(bloklar, list(parse_tool_use_nesne(blok)))
          }
          # text bloklarını yoksay; canlı akış zaten content_block_delta
          # üzerinden text_delta parçalarını gönderdi.
        }
      }
      return(list(tip = "assistant", bloklar = bloklar))

    } else if (tur == "user") {
      # Tool result blokları Claude Code CLI'da user mesajı altında gelir;
      # canlı akışta tool sonucu olarak göster.
      bloklar <- list()
      icerik_bloklari <- nesne$message$content
      if (is.null(icerik_bloklari)) {
        icerik_bloklari <- nesne$content
      }

      # Tek nesne formunu da destekle (bazı proxy varyantları için)
      if (!is.null(icerik_bloklari) &&
          is.list(icerik_bloklari) &&
          !is.null(icerik_bloklari$type)) {
        icerik_bloklari <- list(icerik_bloklari)
      }

      if (!is.null(icerik_bloklari) && is.list(icerik_bloklari)) {
        for (blok in icerik_bloklari) {
          if (!is.list(blok)) next
          if ((blok$type %||% "") != "tool_result") next

          tr_icerik <- blok$content %||% ""
          if (is.list(tr_icerik)) {
            parca_listesi <- character(0)
            for (parca in tr_icerik) {
              if (is.list(parca)) {
                parca_listesi <- c(parca_listesi, as.character(parca$text %||% ""))
              }
            }
            tr_icerik <- paste(parca_listesi, collapse = "")
          }

          bloklar <- c(bloklar, list(list(
            tip = "tool_result",
            arac_id = blok$tool_use_id %||% "",
            icerik = tr_icerik
          )))
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
# ------------------------------------------------------------------------------
# SENTETİK ARAÇ KULLANIMI ÇIKARSAMA
# Model proxy katmanında Anthropic tool_use bloklarını yaymadığı halde
# Bilge Yolaç snapshot diff'i yeni dosya algıladığında, ARAÇ KULLANIMLARI
# sayacının gerçekleşen dosya işlemini yansıtabilmesi için sentetik bir
# Write araç bloğu yayınlanır. Bu blok canlı akış UI'sına eklenir ve
# tool_uses listesine kaydedilir.
#
# YENİ DAVRANIŞ: Synthesis artık ek bir koşul kullanır. Mevcut tool_uses
# listesinde dosya yolu zaten kapsanmış üretilen dosyalar için sentetik
# eklenmez (aksi halde aynı dosya iki kez listelenir). Ancak parser bazı
# dosyaları kaçırdıysa (örn. on-prem proxy yalnızca bir kısmını emit
# ettiyse), bu fonksiyon kapsanmamış dosyalar için ek sentetik blok üretir.
# ------------------------------------------------------------------------------

#' Mevcut tool_use'larda kapsanan dosya yollarını topla
#'
#' @param tool_uses ayristirma$tool_uses içeriği
#' @return Normalize edilmiş dosya yolu vektörü
cc_collect_covered_tool_paths <- function(tool_uses) {
  if (!length(tool_uses %||% list())) return(character(0))

  kapsanan <- character(0)

  for (arac in tool_uses) {
    if (!is.list(arac)) next
    girdi <- arac$input %||% list()
    if (!is.list(girdi)) next

    yol_adaylari <- c(
      girdi$file_path %||% "",
      girdi$path %||% "",
      girdi$new_file %||% "",
      girdi$file %||% ""
    )

    for (yol in yol_adaylari) {
      yol <- as.character(yol %||% "")[1]
      if (is.na(yol) || !nzchar(yol)) next
      kapsanan <- c(kapsanan, tolower(yol))
    }
  }

  unique(kapsanan)
}

#' İndirme listesinden sentetik Write araç kullanımları üret
#'
#' @description Mevcut tool_uses bulunsa bile, parser'ın kaçırdığı dosyalar
#'   için sentetik Write tool_use üretir. Böylece ARAÇ KULLANIMLARI sayacı
#'   gerçekten oluşturulan tüm dosyaları yansıtır. Aynı dosya hem gerçek hem
#'   sentetik olarak listelenmesin diye dosya yolu eşleştirmesi yapılır.
#'
#' @param session Shiny session
#' @param ns Namespace function
#' @param env Akış ortamı (stream_env)
#' @param ayristirma parse_claude_code_json_output sonucu
#' @param olusan_dosyalar İndirme/üretilen dosya listesi
#' @return Eklenen sentetik tool_use entry listesi (boş olabilir)
cc_synthesize_tool_uses_from_downloads <- function(session,
                                                    ns,
                                                    env,
                                                    ayristirma,
                                                    olusan_dosyalar) {
  if (!length(olusan_dosyalar %||% list())) {
    return(list())
  }

  # Halihazırda parser'ın yakaladığı tool_use'ların dosya yolu setini al.
  # Aynı yol için ikinci kez sentetik üretme.
  kapsanan_yollar <- tryCatch(
    cc_collect_covered_tool_paths(ayristirma$tool_uses %||% list()),
    error = function(e) character(0)
  )

  sentetik_araclar <- list()

  for (i in seq_along(olusan_dosyalar)) {
    dosya <- olusan_dosyalar[[i]]
    yol <- as.character(dosya$original_path %||% "")[1]
    if (is.na(yol) || !nzchar(yol)) next

    if (tolower(yol) %in% kapsanan_yollar) next

    dosya_adi <- basename(yol)

    sentetik_id <- paste0(
      "synth_write_",
      gsub("[^A-Za-z0-9_-]+", "_", dosya_adi, perl = TRUE),
      "_",
      i
    )

    sentetik_arac <- list(
      id = sentetik_id,
      name = "Write",
      input = list(file_path = yol),
      result = "Algılandı: çalışma dizini snapshot diff'i ile yeni dosya tespit edildi."
    )

    sentetik_parca <- list(
      tip = "tool_use",
      arac_id = sentetik_id,
      arac_adi = "Write",
      arac_turu = "file_write",
      girdi = sentetik_arac$input,
      komut = "",
      dosya_yolu = yol,
      dosya_icerigi = ""
    )

    fmt <- tryCatch(
      format_streaming_chunk_html(sentetik_parca),
      error = function(e) NULL
    )

    if (!is.null(fmt) && nzchar(fmt$html %||% "")) {
      tryCatch(
        session$sendCustomMessage(
          type = "cc-stream-chunk",
          message = list(
            target = ns("output_area"),
            welcomeId = ns("welcome_screen"),
            chunkType = fmt$tip,
            html = fmt$html,
            toolId = fmt$arac_id %||% sentetik_id,
            accentColor = env$karakter_renk,
            characterName = env$karakter_adi,
            timestamp = env$zaman_damgasi
          )
        ),
        error = function(e) NULL
      )
    }

    sentetik_araclar <- c(sentetik_araclar, list(sentetik_arac))
  }

  sentetik_araclar
}

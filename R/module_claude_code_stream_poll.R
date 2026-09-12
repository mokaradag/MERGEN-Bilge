# ==============================================================================
# Dosya Yolu: R/module_claude_code_stream_poll.R
# Açıklama: Bilge Yolaç canlı akış yoklama, durdurma ve klavye gönderim
#           gözlemcilerini ana module_claude_code.R dosyasından ayırır.
# ==============================================================================

# Akış satırları liste tamponunda biriktirilir; her satırda vektör kopyalayan
# c() birikimi uzun çalıştırmalarda O(n^2) maliyet üretiyordu. Tampon ayrıca
# üst sınırla korunur: sınırsız canlı çıktı worker belleğini tüketebilirdi.
# Üst sınır sabitleri R/config_claude_code.R içinde tanımlıdır (bu dosya ve
# helpers_claude_code_streaming.R ortak kullanır).

# En eski satırları düşürürken bayt sayacını da tutarlı tutar.
.cc_stream_trim_oldest <- function(env, dusurulecek) {
  dusurulecek <- min(as.integer(dusurulecek), length(env$satir_tamponu))
  if (dusurulecek <= 0L) return(invisible(NULL))
  dusen <- env$satir_tamponu[seq_len(dusurulecek)]
  env$satir_tamponu <- env$satir_tamponu[-seq_len(dusurulecek)]
  dusen_bayt <- sum(vapply(
    dusen, function(x) nchar(as.character(x)[1], type = "bytes"), numeric(1)
  ))
  env$stdout_bayt <- max(0, (env$stdout_bayt %||% 0) - dusen_bayt)
  invisible(NULL)
}

cc_stream_append_line <- function(env, satir) {
  if (is.null(env$satir_tamponu)) env$satir_tamponu <- list()

  # KAYIT BAŞINA bayt sınırı: tek bir devasa satır (ör. base64 gövde) hem
  # tamponu hem cc_stream_collect_lines() kopyasını şişirebiliyordu.
  satir <- as.character(satir)[1]
  if (is.na(satir)) satir <- ""
  # Dönüş değeri: kayıt bütçe İÇİNDE mi? Çağıranlar bütçeyi aşan kaydı
  # `parse_streaming_chunk()` / `send_parca()` yoluna sokmaz; kırpma yalnızca
  # SAKLANAN kopyayı sınırlıyor, ayrıştırma ham kaydı işlemeye devam ediyordu.
  butce_icinde <- TRUE
  if (nchar(satir, type = "bytes") > CC_STREAM_MAX_RECORD_BYTES) {
    butce_icinde <- FALSE
    satir <- cc_output_truncate_bytes(satir, CC_STREAM_MAX_RECORD_BYTES)
    if (!isTRUE(env$satir_kaydi_kirpildi)) {
      env$satir_kaydi_kirpildi <- TRUE
      try(log_warn(paste(
        CLAUDE_CODE_LOG_PREFIX,
        "Canlı akış kaydı bayt sınırını aştı; kayıt kırpıldı:",
        CC_STREAM_MAX_RECORD_BYTES
      )), silent = TRUE)
    }
  }

  if (length(env$satir_tamponu) >= CC_STREAM_MAX_LINES) {
    if (!isTRUE(env$satir_tamponu_kirpildi)) {
      env$satir_tamponu_kirpildi <- TRUE
      try(log_warn(paste(
        CLAUDE_CODE_LOG_PREFIX,
        "Canlı akış satır sınırına ulaşıldı; en eski satırlar düşürülüyor:",
        CC_STREAM_MAX_LINES
      )), silent = TRUE)
    }
    # En eski çeyreği düş; JSONL sonuç satırları akışın sonunda gelir.
    .cc_stream_trim_oldest(env, as.integer(CC_STREAM_MAX_LINES / 4L))
  }

  env$satir_tamponu[[length(env$satir_tamponu) + 1L]] <- satir
  env$stdout_bayt <- (env$stdout_bayt %||% 0) + nchar(satir, type = "bytes")

  # TOPLAM stdout bayt sınırı: satır sayısı sınırın altındayken bile çok sayıda
  # büyük kayıt belleği doldurabiliyordu.
  while ((env$stdout_bayt %||% 0) > CC_STREAM_MAX_STDOUT_BYTES &&
         length(env$satir_tamponu) > 1L) {
    if (!isTRUE(env$stdout_bayt_kirpildi)) {
      env$stdout_bayt_kirpildi <- TRUE
      try(log_warn(paste(
        CLAUDE_CODE_LOG_PREFIX,
        "Canlı akış stdout bayt sınırına ulaşıldı; en eski satırlar düşürülüyor:",
        CC_STREAM_MAX_STDOUT_BYTES
      )), silent = TRUE)
    }
    .cc_stream_trim_oldest(env, max(1L, as.integer(length(env$satir_tamponu) / 4L)))
  }

  invisible(butce_icinde)
}

cc_stream_collect_lines <- function(env) {
  satirlar <- as.character(unlist(env$satir_tamponu %||% list(), use.names = FALSE))
  env$tum_satirlar <- satirlar
  paste(satirlar, collapse = "\n")
}

# stderr borusunu boşaltır; okunamayan durumda sessizce geçilir.
cc_stream_drain_stderr <- function(proc, env, son = FALSE) {
  if (is.null(env$stderr_tamponu)) env$stderr_tamponu <- list()

  parca <- tryCatch(
    if (isTRUE(son)) proc$read_all_error() else proc$read_error(),
    error = function(e) ""
  )
  parca <- as.character(parca %||% "")[1]
  if (is.na(parca) || !nzchar(parca)) return(invisible(NULL))

  onceki_bayt <- env$stderr_bayt %||% 0L
  parca_bayt <- nchar(parca, type = "bytes")
  kalan <- CC_STREAM_MAX_STDERR_BYTES - onceki_bayt

  if (parca_bayt > kalan) {
    if (!isTRUE(env$stderr_sinir_bildirildi)) {
      env$stderr_sinir_bildirildi <- TRUE
      try(log_warn(paste(
        CLAUDE_CODE_LOG_PREFIX,
        "stderr tampon sınırına ulaşıldı; sonraki stderr çıktısı saklanmıyor:",
        CC_STREAM_MAX_STDERR_BYTES
      )), silent = TRUE)
    }
    # Tek büyük tanı mesajında tüm parçayı düşürmek hata raporunu boş
    # bırakıyordu; bütçeye sığan önek saklanır, gerisi yalnızca boşaltılır.
    if (kalan > 0) {
      onek <- cc_output_truncate_bytes(parca, kalan)
      if (nzchar(onek)) {
        env$stderr_tamponu[[length(env$stderr_tamponu) + 1L]] <- onek
        env$stderr_bayt <- onceki_bayt + nchar(onek, type = "bytes")
      }
    }
    return(invisible(NULL))
  }

  env$stderr_bayt <- onceki_bayt + parca_bayt
  env$stderr_tamponu[[length(env$stderr_tamponu) + 1L]] <- parca
  invisible(NULL)
}

cc_bind_claude_code_stream_polling <- function(input,
                                               session,
                                               ns,
                                               rv,
                                               send_parca,
                                               finalize_streaming,
                                               observe_dir_contents) {
  shiny::observe({
    shiny::req(isTRUE(rv$is_running))
    proc <- rv$active_process
    shiny::req(!is.null(proc))

    shiny::invalidateLater(200, session)

    env <- rv$stream_env
    if (is.null(env)) return()

    if (isTRUE(env$durduruldu)) {
      tryCatch(proc$kill(), error = function(e) NULL)
      finalize_streaming(
        "Durduruldu",
        "stop-circle",
        "#FFB74D",
        request_id = env$request_id
      )
      return()
    }

    gecen_sure <- as.numeric(difftime(Sys.time(), env$baslangic, units = "secs"))

    # Lease heartbeat: uzun çalıştırmalarda temizlik yolu aktif çalışma alanını
    # yetim sayıp silmesin. 30 saniyede bir yeterlidir (poll 200 ms).
    if (is.null(env$lease_heartbeat) ||
        as.numeric(difftime(Sys.time(), env$lease_heartbeat, units = "secs")) > 30) {
      env$lease_heartbeat <- Sys.time()
      if (exists("cc_touch_runtime_lease", mode = "function", inherits = TRUE)) {
        cc_touch_runtime_lease(env$runtime_lease %||% "")
      }
    }

    if (gecen_sure > env$zaman_asimi) {
      tryCatch(proc$kill(), error = function(e) NULL)

      log_error(paste(
        CLAUDE_CODE_LOG_PREFIX,
        "Akış zaman aşımı:",
        env$zaman_asimi,
        "sn"
      ))

      # Zaman aşımına uğrayan çalıştırma da kalıcı geçmişe yazılır.
      if (exists("cc_persist_run_result", mode = "function", inherits = TRUE)) {
        cc_persist_run_result(
          rv = rv,
          env = env,
          status = "failed",
          final_output = paste0(
            "İşlem zaman aşımına uğradı (", env$zaman_asimi, " saniye)."
          ),
          duration = round(gecen_sure, 1),
          cli_session_id = env$oturum_id
        )
      }

      session$sendCustomMessage(
        type = "cc-add-message",
        message = list(
          target = ns("output_area"),
          type = "error",
          content = paste0(
            "İşlem zaman aşımına uğradı (",
            env$zaman_asimi,
            " saniye)."
          ),
          timestamp = format(Sys.time(), "%H:%M:%S"),
          welcomeId = ns("welcome_screen")
        )
      )

      finalize_streaming(
        "Zaman Aşımı",
        "clock",
        "#FFB74D",
        request_id = env$request_id
      )
      return()
    }

    tryCatch({
      proc$poll_io(0)

      yeni_satirlar <- tryCatch(
        ensure_utf8(proc$read_output_lines()),
        error = function(e) character(0)
      )

      # stderr borusu her turda boşaltılır: dolan stderr tamponu çocuk süreci
      # yazarken kilitler ve çalıştırma sahte zaman aşımına düşer.
      cc_stream_drain_stderr(proc, env)

      if (length(yeni_satirlar) > 0) {
        for (satir in yeni_satirlar) {
          satir <- trimws(satir)
          if (!nzchar(satir)) next

          # Bütçe yalnızca SAKLANAN kopyayı sınırlar: satırı ayrıştırmadan
          # atlamak uzun akışlarda metni, araç olaylarını ve son `result`
          # kaydındaki `session_id` değerini düşürüyordu.
          cc_stream_append_line(env, satir)

          parca <- parse_streaming_chunk(satir)
          send_parca(parca, env)
        }
      }
    }, error = function(e) {
      log_warn(paste(
        CLAUDE_CODE_LOG_PREFIX,
        "Akış okuma hatası:",
        conditionMessage(e)
      ))
    })

    if (!proc$is_alive()) {
      # Çıktı işleme çalıştırma başına YALNIZCA BİR KEZ yapılır; poll
      # gözlemcisi yeniden tetiklenirse aynı pahalı tarama tekrarlanmaz.
      if (isTRUE(env$cikti_islendi)) return()
      env$cikti_islendi <- TRUE

      tryCatch({
        kalan <- ensure_utf8(proc$read_all_output())

        if (nzchar(kalan)) {
          kalan_satirlar <- strsplit(kalan, "\n")[[1]]

          for (satir in kalan_satirlar) {
            satir <- trimws(satir)
            if (!nzchar(satir)) next

            cc_stream_append_line(env, satir)

            parca <- parse_streaming_chunk(satir)
            send_parca(parca, env)
          }
        }
      }, error = function(e) NULL)

      tam_cikti <- cc_stream_collect_lines(env)
      ayristirma <- parse_claude_code_json_output(tam_cikti)
      cikis_kodu <- proc$get_exit_status()
      sure <- round(
        as.numeric(difftime(Sys.time(), env$baslangic, units = "secs")),
        1
      )

      hata_mesaji <- ""
      if (!identical(cikis_kodu, 0L)) {
        cc_stream_drain_stderr(proc, env, son = TRUE)
        stderr_metin <- ensure_utf8(paste0(
          as.character(unlist(env$stderr_tamponu %||% list(), use.names = FALSE)),
          collapse = ""
        ))

        hata_mesaji <- if (nzchar(stderr_metin)) stderr_metin else tam_cikti
      }

      # Süreç bitti: yoklama gözlemcisini durdur, pahalı çıktı işlemesini
      # arka plana gönder. Ana Shiny süreci diğer oturumlara yanıt vermeye
      # devam eder.
      rv$active_process <- NULL

      tryCatch({
        cc_dispatch_run_output_processing(list(
          session = session,
          ns = ns,
          rv = rv,
          env = env,
          ayristirma = ayristirma,
          cikis_kodu = cikis_kodu,
          sure = sure,
          hata_mesaji = hata_mesaji,
          finalize_streaming = finalize_streaming,
          observe_dir_contents = observe_dir_contents
        ))
      }, error = function(e) {
        # tracked_future_promise() worker'a gönderim ANINDA (ör. küme çökmüş
        # veya globals serileştirilemiyorsa) senkron olarak da hata verebilir.
        # Bu durumda hiçbir promise/catch zinciri hiç kurulmaz; UI hazırlık
        # durumunda takılı kalmasın diye burada da açıkça sonlandırılır.
        log_warn(paste(
          CLAUDE_CODE_LOG_PREFIX,
          "[OUTPUT_DIFF] Çıktı işleme worker'ı başlatılamadı:",
          conditionMessage(e)
        ))
        cc_report_output_processing_failure(
          list(
            session = session,
            ns = ns,
            rv = rv,
            env = env,
            finalize_streaming = finalize_streaming
          ),
          e
        )
      })
    }
  })

  shiny::observeEvent(input$stop_command, {
    if (isTRUE(rv$is_running)) {
      env <- rv$stream_env %||% rv$poll_state

      # Süreç zaten bitti ve çıktı işleme başladıysa durdurma noktası geçilmiştir:
      # sync guard'ı silmek çalışan çıktı worker'ını sabote eder ve tamamlanma
      # yolu zaten kalıcı kayıt yazacağı için ikinci bir "stopped" kaydı oluşurdu.
      # Süreç bu yoklamadan SONRA çıkmışsa `cikti_islendi` henüz FALSE olur;
      # o pencerede Durdur'a basmak guard dosyasını silip "stopped" kaydı
      # yazıyor ve tamamlanmış çıktı/üretilen dosyalar kaybolabiliyordu.
      # KALAN PENCERE bilinçli olarak kabul edilir: bu gözlemci ve yoklama
      # gözlemcisi AYNI tek iş parçacıklı olay döngüsünde çalışır, dolayısıyla
      # gövde içinde `cikti_islendi` değişemez ve "az önce bitti" ile "şimdi
      # öldürülecek" ayrımı bloklamadan yapılamaz. Pencere tek bir olay döngüsü
      # turuna inmiştir ve sonuç kullanıcının İSTEDİĞİ "durduruldu" durumudur;
      # tek terminal-durum hakemi, korunan çalıştırma yaşam döngüsü
      # sözleşmesinin yeniden tasarımını gerektirir.
      surec_bitti <- isTRUE(tryCatch(
        !is.null(rv$active_process) && !isTRUE(rv$active_process$is_alive()),
        error = function(e) FALSE
      ))
      if (!is.null(env) && (isTRUE(env$cikti_islendi) || isTRUE(surec_bitti))) {
        log_info(paste(
          CLAUDE_CODE_LOG_PREFIX,
          "Durdurma isteği yok sayıldı: çalıştırma tamamlandı, çıktılar işleniyor."
        ))
        # Durum kullanıcıya bildirilir: aksi hâlde buton görünürde hiçbir şey
        # yapmıyor ve çıktı eşitlemesi sürerken tekrar tekrar basılıyordu.
        session$sendCustomMessage(
          type = "cc-add-message",
          message = list(
            target = ns("output_area"),
            type = "info",
            content = "Çalıştırma tamamlandı; üretilen dosyalar işleniyor. Durdurma uygulanmadı.",
            timestamp = format(Sys.time(), "%H:%M:%S"),
            welcomeId = ns("welcome_screen")
          )
        )
        return()
      }

      request_id <- if (!is.null(env)) {
        env$request_id %||% rv$active_request_id
      } else {
        rv$active_request_id
      }

      if (!is.null(env)) {
        env$durduruldu <- TRUE
        cc_release_runtime_lease(env$runtime_lease %||% "")
        # Çıktı worker'ı ana süreçteki reaktif isteği göremez. Bu dosyanın
        # kaldırılması, worker'ın her kaynak yazısından hemen önce yaptığı
        # kontrolü düşürür ve durdurulmuş çalıştırmanın stale yazmasını keser.
        if (nzchar(env$output_sync_guard %||% "")) {
          unlink(env$output_sync_guard, force = TRUE)
        }
      }

      proc <- rv$active_process
      if (!is.null(proc)) {
        tryCatch({
          proc$kill()
          log_info(paste(
            CLAUDE_CODE_LOG_PREFIX,
            "Süreç kullanıcı tarafından durduruldu"
          ))
        }, error = function(e) NULL)
      }

      session$sendCustomMessage(
        type = "cc-stream-end",
        message = list(target = ns("output_area"))
      )

      # Kullanıcının durdurduğu çalıştırma da kalıcı geçmişe yazılır.
      if (!is.null(env) &&
          exists("cc_persist_run_result", mode = "function", inherits = TRUE)) {
        cc_persist_run_result(
          rv = rv,
          env = env,
          status = "stopped",
          final_output = "Çalıştırma kullanıcı tarafından durduruldu.",
          cli_session_id = env$oturum_id
        )
      }

      finalize_streaming(
        "Durduruldu",
        "stop-circle",
        "#FFB74D",
        request_id = request_id
      )
    }
  })

  shiny::observeEvent(input$prompt_submit_key, {
    if (!isTRUE(rv$is_running)) {
      shinyjs::click("run_command")
    }
  })

  invisible(TRUE)
}

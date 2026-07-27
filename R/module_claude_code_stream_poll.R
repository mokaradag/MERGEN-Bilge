# ==============================================================================
# Dosya Yolu: R/module_claude_code_stream_poll.R
# Açıklama: Bilge Yolaç canlı akış yoklama, durdurma ve klavye gönderim
#           gözlemcilerini ana module_claude_code.R dosyasından ayırır.
# ==============================================================================

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

      if (length(yeni_satirlar) > 0) {
        for (satir in yeni_satirlar) {
          satir <- trimws(satir)
          if (!nzchar(satir)) next

          env$tum_satirlar <- c(env$tum_satirlar, satir)

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

            env$tum_satirlar <- c(env$tum_satirlar, satir)

            parca <- parse_streaming_chunk(satir)
            send_parca(parca, env)
          }
        }
      }, error = function(e) NULL)

      tam_cikti <- paste(env$tum_satirlar, collapse = "\n")
      ayristirma <- parse_claude_code_json_output(tam_cikti)
      cikis_kodu <- proc$get_exit_status()
      sure <- round(
        as.numeric(difftime(Sys.time(), env$baslangic, units = "secs")),
        1
      )

      hata_mesaji <- ""
      if (!identical(cikis_kodu, 0L)) {
        stderr_metin <- tryCatch(
          ensure_utf8(proc$read_all_error()),
          error = function(e) ""
        )

        hata_mesaji <- if (nzchar(stderr_metin)) stderr_metin else tam_cikti
      }

      # Süreç bitti: yoklama gözlemcisini durdur, pahalı çıktı işlemesini
      # arka plana gönder. Ana Shiny süreci diğer oturumlara yanıt vermeye
      # devam eder.
      rv$active_process <- NULL

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
    }
  })

  shiny::observeEvent(input$stop_command, {
    if (isTRUE(rv$is_running)) {
      env <- rv$stream_env %||% rv$poll_state

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

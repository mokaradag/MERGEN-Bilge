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

      olusan_dosyalar <- tryCatch(
        collect_claude_code_workdir_changes_downloads(
          before_snapshot = env$workdir_snapshot,
          tool_uses = ayristirma$tool_uses,
          runtime_workdir = env$calisma_dizini,
          source_workdir = env$kaynak_calisma_dizini,
          user_id = env$user_id,
          session_token = env$session_token
        ),
        error = function(e) list()
      )

      indirme_html <- tryCatch(
        format_claude_code_generated_downloads_html(olusan_dosyalar),
        error = function(e) ""
      )

      log_info(sprintf(
        "%s [DOWNLOADS] cikis_kodu=%s | tespit edilen dosya sayisi=%d",
        CLAUDE_CODE_LOG_PREFIX,
        as.character(cikis_kodu %||% ""),
        length(olusan_dosyalar)
      ))

      if (identical(cikis_kodu, 0L)) {
        log_info(paste(
          CLAUDE_CODE_LOG_PREFIX,
          "Akış tamamlandı - Süre:",
          sure,
          "sn"
        ))

        oturum_id <- env$oturum_id %||% ayristirma$session_id
        if (!is.null(oturum_id) && nzchar(oturum_id %||% "")) {
          rv$cli_session_id <- oturum_id
        }

        rv$conversation_context <- c(
          rv$conversation_context,
          list(list(role = "assistant", content = ayristirma$text_output))
        )

        olusan_dosyalar <- cc_collect_streaming_run_downloads(
          before_snapshot = env$workdir_snapshot,
          tool_uses = ayristirma$tool_uses,
          runtime_workdir = env$calisma_dizini,
          source_workdir = env$kaynak_calisma_dizini,
          user_id = env$user_id,
          session_token = env$session_token
        )

        log_info(sprintf(
          "%s [DOWNLOADS] tespit edilen indirme sayisi=%d",
          CLAUDE_CODE_LOG_PREFIX,
          length(olusan_dosyalar)
        ))

        son_icerik <- paste0(
          format_claude_code_output(ayristirma$text_output),
          indirme_html
        )

        session$sendCustomMessage(
          type = "cc-stream-end",
          message = list(
            target = ns("output_area"),
            duration = sure,
            finalContent = son_icerik,
            accentColor = env$karakter_renk,
            characterName = env$karakter_adi
          )
        )

        rv$last_result <- list(
          success = TRUE,
          output = ayristirma$text_output,
          error = "",
          duration = sure,
          tool_uses = ayristirma$tool_uses,
          session_id = oturum_id,
          generated_downloads = olusan_dosyalar
        )

        finalize_streaming(
          "Tamamlandı",
          "check-circle",
          "#81C784",
          sure,
          request_id = env$request_id
        )
      } else {
        stderr_metin <- tryCatch(
          ensure_utf8(proc$read_all_error()),
          error = function(e) ""
        )

        hata_mesaji <- if (nzchar(stderr_metin)) stderr_metin else tam_cikti
        temiz_log <- gsub("[{}]", "", substr(hata_mesaji, 1, 200))

        log_warn(paste(
          CLAUDE_CODE_LOG_PREFIX,
          "Akış hata kodu:",
          cikis_kodu,
          "- Mesaj:",
          temiz_log
        ))

        session$sendCustomMessage(
          type = "cc-stream-end",
          message = list(target = ns("output_area"))
        )

        session$sendCustomMessage(
          type = "cc-add-message",
          message = list(
            target = ns("output_area"),
            type = "error",
            content = htmltools::htmlEscape(hata_mesaji),
            timestamp = format(Sys.time(), "%H:%M:%S"),
            welcomeId = ns("welcome_screen")
          )
        )

        if (nzchar(indirme_html)) {
          session$sendCustomMessage(
            type = "cc-add-message",
            message = list(
              target = ns("output_area"),
              type = "ai",
              content = indirme_html,
              timestamp = format(Sys.time(), "%H:%M:%S"),
              welcomeId = ns("welcome_screen"),
              accentColor = env$karakter_renk,
              characterName = env$karakter_adi
            )
          )
        }

        rv$last_result <- list(
          success = FALSE,
          output = "",
          error = hata_mesaji,
          duration = sure,
          tool_uses = ayristirma$tool_uses,
          session_id = env$oturum_id %||% ayristirma$session_id,
          generated_downloads = olusan_dosyalar
        )

        finalize_streaming(
          "Hata",
          "exclamation-triangle",
          "#E57373",
          sure,
          request_id = env$request_id
        )
      }

      rv$output_history <- c(
        rv$output_history,
        list(list(
          prompt = env$prompt,
          result = rv$last_result,
          timestamp = Sys.time(),
          character = env$karakter_id
        ))
      )

      if (isTRUE(env$mirror_kullanildi)) {
        tryCatch(
          sync_claude_runtime_workdir_back(
            runtime_workdir = env$calisma_dizini,
            source_workdir = env$kaynak_calisma_dizini
          ),
          error = function(e) {
            log_warn(paste(
              CLAUDE_CODE_LOG_PREFIX,
              "Yerel çalışma alanı geri senkronlanamadı:",
              conditionMessage(e)
            ))
          }
        )
      }

      observe_dir_contents(
        dizin = env$kaynak_calisma_dizini %||% env$calisma_dizini
      )

      # Canlı akış kullanıcının yükleme klasörü içinde yeni dosya ürettiyse
      # Dosya Yönetimi tablosunun bu yeni dosyayı sayfa yenilemeden görmesi
      # için File Manager'a yumuşak bir yenileme sinyali gönder.
      cc_refresh_user_file_manager_after_run(
        session = session,
        user_id = env$user_id
      )
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
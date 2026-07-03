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

      # ARAÇ_KULLANIMI tanılaması: parser'ın ham CLI çıktısından kaç tool_use
      # yakaladığını ve ham çıktıda kaç stream-json olay türü olduğunu loga
      # yaz. Bu, on-prem proxy CLI'sının hangi formatı emit ettiğini sahada
      # debug etmek için kritiktir. ARAÇ KULLANIMLARI (0) raporlandığında
      # logs/mergen_*.log içinden bu satırlara bakılır.
      tryCatch({
        ham_satir_sayisi <- length(env$tum_satirlar)
        ilk_n <- min(3L, ham_satir_sayisi)
        ornek_ozet <- if (ilk_n > 0L) {
          paste(
            substr(env$tum_satirlar[seq_len(ilk_n)], 1L, 200L),
            collapse = " || "
          )
        } else {
          "(ham satır yok)"
        }

        olay_turleri <- character(0)
        tryCatch({
          if (ham_satir_sayisi > 0L) {
            for (satir in env$tum_satirlar) {
              if (!nzchar(satir)) next
              nesne <- tryCatch(
                jsonlite::fromJSON(satir, simplifyVector = FALSE),
                error = function(e) NULL
              )
              if (is.null(nesne)) next
              tur <- as.character(nesne$type %||% "")
              if (identical(tur, "stream_event")) {
                tur <- paste0(
                  "stream_event:",
                  as.character(nesne$event$type %||% "")
                )
              }
              olay_turleri <- c(olay_turleri, tur)
            }
          }
        }, error = function(e) NULL)

        olay_ozeti <- if (length(olay_turleri)) {
          olay_say <- table(olay_turleri)
          paste(
            sprintf("%s=%d", names(olay_say), as.integer(olay_say)),
            collapse = ","
          )
        } else {
          "(olay tespit edilmedi)"
        }

        log_info(sprintf(
          "%s [TOOL_USE_DEBUG] ham_satir=%d | parsed_tool_uses=%d | olay_dagilimi=%s",
          CLAUDE_CODE_LOG_PREFIX,
          ham_satir_sayisi,
          length(ayristirma$tool_uses %||% list()),
          olay_ozeti
        ))

        if (length(ayristirma$tool_uses %||% list()) == 0L &&
            length(olusan_dosyalar %||% list()) > 0L) {
          log_warn(sprintf(
            "%s [TOOL_USE_DEBUG] Parser tool_use yakalamadı ama %d dosya üretildi. İlk %d ham JSONL örneği: %s",
            CLAUDE_CODE_LOG_PREFIX,
            length(olusan_dosyalar),
            ilk_n,
            gsub("[{}]", "", ornek_ozet)
          ))
        }
      }, error = function(e) NULL)

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

        # Eğer model proxy katmanında Anthropic tool_use blokları yaymadıysa
        # (ayristirma$tool_uses boş) ama snapshot diff yeni dosya algıladıysa,
        # gerçekleşen dosya işlemini ARAÇ KULLANIMLARI sayacına yansıtmak için
        # sentetik bir Write araç bloğu yayınla. Bu, on-prem LLM proxy
        # tool_use bloklarını farklı sarmaladığında veya yalnızca text
        # response döndürdüğünde dahi kullanıcının "araç kullanıldı" geri
        # bildirimi almasını sağlar.
        sentetik_arac_eklendi <- cc_synthesize_tool_uses_from_downloads(
          session = session,
          ns = ns,
          env = env,
          ayristirma = ayristirma,
          olusan_dosyalar = olusan_dosyalar
        )
        if (length(sentetik_arac_eklendi)) {
          ayristirma$tool_uses <- c(
            ayristirma$tool_uses,
            sentetik_arac_eklendi
          )
        }

        # Bilge Yolaç başarıyla tamamlandı sayılsa bile, kullanıcı dosya
        # oluşturma/değiştirme istediğinde model gerçekten araç çağrısı
        # yapmadıysa ve çalışma dizininde yeni dosya da oluşmadıysa,
        # cevabın "yaptım" demesi kullanıcıyı yanıltıcı olabilir. Bunu
        # kullanıcıya açık bir not olarak göster ve loglara da kaydet.
        no_tool_kullanildi <- length(ayristirma$tool_uses %||% list()) == 0L
        no_dosya_uretildi <- length(olusan_dosyalar %||% list()) == 0L
        yazma_niyeti_var <- tryCatch(
          isTRUE(cc_policy_prompt_has_write_intent(env$prompt)),
          error = function(e) FALSE
        )

        arac_uyarisi_html <- ""
        if (isTRUE(yazma_niyeti_var) &&
            isTRUE(no_tool_kullanildi) &&
            isTRUE(no_dosya_uretildi)) {
          log_warn(paste(
            CLAUDE_CODE_LOG_PREFIX,
            "Kullanıcı dosya oluşturma/değiştirme istedi ancak hiç araç",
            "kullanımı (tool_use) algılanmadı ve çalışma dizininde yeni dosya",
            "üretilmedi. On-prem LLM proxy araç olaylarını üretmiyor olabilir."
          ))

          arac_uyarisi_html <- paste0(
            '<div class="cc-tool-warning" ',
            'style="margin-top:12px; padding:10px 14px; border-left:3px solid #FFB74D; ',
            'background:rgba(255,183,77,0.08); color:#FFB74D; ',
            'border-radius:6px; font-size:13px;">',
            '<i class="fas fa-triangle-exclamation"></i> ',
            'Model bir dosya oluşturma/değiştirme isteğine yanıt verdi ancak ',
            'gerçekte hiçbir araç (Read/Write/Edit vb.) çağrısı yapılmadı ve ',
            'çalışma dizininde yeni bir dosya algılanmadı. Yanıttaki bilgiler ',
            'yalnızca metin tabanlı olabilir; gerçek bir dosya işlemi ',
            'beklediyseniz lütfen isteğinizi netleştirip yeniden deneyin.',
            '</div>'
          )
        }

        son_icerik <- paste0(
          format_claude_code_output(ayristirma$text_output),
          indirme_html,
          arac_uyarisi_html
        )

        # ARAÇ KULLANIMLARI bölümünü canlı akıştan bağımsız olarak garanti et:
        # Bazı on-prem LLM proxy varyantlarında canlı stream tool_use parçaları
        # boş HTML ile gelebilir veya hiç emit edilmeyebilir; bu durumda sayaç
        # 0 görünür. cc-stream-end ile birlikte final tool_uses bloğunun
        # sunumunu da gönder; istemci eksik/boş canlı bölümü bu HTML ile
        # tamamlar veya yenisini ekler. Tool_use bulunamadıysa boş string
        # gönderilir; bu durumda istemci hiçbir bölüm oluşturmaz.
        son_arac_kullanim_html <- tryCatch(
          if (length(ayristirma$tool_uses %||% list()) > 0L) {
            format_tool_uses_html_enhanced(ayristirma$tool_uses)
          } else {
            ""
          },
          error = function(e) ""
        )

        log_info(sprintf(
          "%s [TOOL_USE_DEBUG] final_tool_uses=%d | final_html_len=%d | sentetik_eklendi=%d",
          CLAUDE_CODE_LOG_PREFIX,
          length(ayristirma$tool_uses %||% list()),
          nchar(son_arac_kullanim_html %||% ""),
          length(sentetik_arac_eklendi %||% list())
        ))

        session$sendCustomMessage(
          type = "cc-stream-end",
          message = list(
            target = ns("output_area"),
            duration = sure,
            finalContent = son_icerik,
            finalToolUsesHtml = son_arac_kullanim_html,
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

        # Başarılı çalıştırmayı kalıcılaştır (persist hatası canlı yanıtı
        # asla etkilemez; helper içeride güvenli değerlendirme yapar).
        if (exists("cc_persist_run_result", mode = "function", inherits = TRUE)) {
          cc_persist_run_result(
            rv = rv,
            env = env,
            status = "completed",
            final_output = ayristirma$text_output %||% "",
            exit_code = cikis_kodu,
            duration = sure,
            tool_uses = ayristirma$tool_uses,
            downloads = olusan_dosyalar,
            cli_session_id = oturum_id
          )
        }

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

        # Başarısız çalıştırma da kalıcılaştırılır; hata mesajı FinalOutput
        # alanında saklanır (hidrasyonda hata balonu olarak geri oynatılır).
        if (exists("cc_persist_run_result", mode = "function", inherits = TRUE)) {
          cc_persist_run_result(
            rv = rv,
            env = env,
            status = "failed",
            final_output = hata_mesaji %||% "",
            exit_code = cikis_kodu,
            duration = sure,
            tool_uses = ayristirma$tool_uses,
            downloads = olusan_dosyalar,
            cli_session_id = env$oturum_id %||% ayristirma$session_id
          )
        }

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
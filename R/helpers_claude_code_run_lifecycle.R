# ==============================================================================
# Dosya Yolu: R/helpers_claude_code_run_lifecycle.R
# Açıklama: Bilge Yolaç komut çalıştırma yaşam döngüsü ve async sonuç korumaları.
#           Bu dosya Shiny modülünden bağımsız, küçük ve test edilebilir yardımcılar
#           içerir. Amaç stale promise/poll callback'lerinin yeni çalışma durumunu
#           ezmesini engellemektir.
# ==============================================================================

cc_next_run_request_id <- function(prefix = "ccrun") {
  prefix <- as.character(prefix %||% "ccrun")[1]
  if (is.na(prefix) || !nzchar(prefix)) {
    prefix <- "ccrun"
  }

  paste0(
    prefix,
    "_",
    format(Sys.time(), "%Y%m%d%H%M%OS6"),
    "_",
    sprintf("%04d", sample.int(10000L, 1L) - 1L)
  )
}

cc_mark_active_run <- function(rv, request_id) {
  request_id <- as.character(request_id %||% "")[1]

  if (is.na(request_id) || !nzchar(request_id)) {
    stop("request_id boş olamaz.", call. = FALSE)
  }

  rv$active_request_id <- request_id
  invisible(request_id)
}

cc_is_active_run <- function(rv, request_id = NULL) {
  # Geriye dönük uyumluluk: eski çağrılar request_id göndermediğinde
  # finalize davranışı aynen devam eder.
  if (is.null(request_id) || length(request_id) == 0L) {
    return(TRUE)
  }

  request_id <- as.character(request_id)[1]
  if (is.na(request_id) || !nzchar(request_id)) {
    return(TRUE)
  }

  active <- tryCatch(
    as.character(rv$active_request_id %||% "")[1],
    error = function(e) ""
  )

  !is.na(active) && nzchar(active) && identical(active, request_id)
}

cc_abort_run_before_streaming <- function(rv, request_id = NULL) {
  if (!cc_is_active_run(rv, request_id)) {
    return(invisible(FALSE))
  }

  rv$is_running <- FALSE
  rv$active_request_id <- NULL

  invisible(TRUE)
}

cc_send_run_blocked_message <- function(session, ns, message, escape = TRUE) {
  msg <- as.character(message %||% "")[1]
  if (is.na(msg)) msg <- ""

  content <- if (isTRUE(escape)) {
    htmltools::htmlEscape(msg)
  } else {
    msg
  }

  session$sendCustomMessage(
    type = "cc-add-message",
    message = list(
      target = ns("output_area"),
      type = "error",
      content = content,
      timestamp = format(Sys.time(), "%H:%M:%S"),
      welcomeId = ns("welcome_screen")
    )
  )

  invisible(TRUE)
}

cc_validate_selected_workdir_for_run <- function(session,
                                                 ns,
                                                 rv,
                                                 request_id,
                                                 workdir,
                                                 user_id) {
  allow_selected <- TRUE

  if (exists("claude_code_config", inherits = TRUE)) {
    allow_selected <- cc_policy_truthy(
      claude_code_config$allow_user_selected_workdirs %||% TRUE
    )
  }

  workdir_policy <- cc_policy_validate_workdir(
    workdir,
    user_id = user_id,
    allow_selected_workdir = allow_selected
  )

  if (!isTRUE(workdir_policy$ok)) {
    cc_abort_run_before_streaming(rv, request_id)

    cc_send_run_blocked_message(
      session = session,
      ns = ns,
      message = workdir_policy$error
    )

    log_warn(paste(
      CLAUDE_CODE_LOG_PREFIX,
      "Çalışma dizini güvenlik ilkesi tarafından engellendi:",
      gsub("[{}]", "", workdir %||% "")
    ))
  }

  workdir_policy
}

cc_prepare_safe_workdir_for_run <- function(session,
                                            ns,
                                            rv,
                                            request_id,
                                            workdir,
                                            user_id,
                                            prompt) {
  workdir_policy <- cc_validate_selected_workdir_for_run(
    session = session,
    ns = ns,
    rv = rv,
    request_id = request_id,
    workdir = workdir,
    user_id = user_id
  )

  if (!isTRUE(workdir_policy$ok)) {
    return(workdir_policy)
  }

  prompt_path_policy <- cc_policy_validate_prompt_file_intent(
    prompt = prompt,
    workdir = workdir_policy$path,
    user_id = user_id
  )

  if (!isTRUE(prompt_path_policy$ok)) {
    cc_abort_run_before_streaming(rv, request_id)

    cc_send_run_blocked_message(
      session = session,
      ns = ns,
      message = prompt_path_policy$error
    )

    log_warn(paste(
      CLAUDE_CODE_LOG_PREFIX,
      "Komut çalıştırma dış yol yazma isteği nedeniyle engellendi:",
      paste(gsub("[{}]", "", prompt_path_policy$blocked_paths), collapse = ", ")
    ))

    return(list(
      ok = FALSE,
      path = workdir_policy$path,
      error = prompt_path_policy$error,
      prompt_policy = prompt_path_policy
    ))
  }

  workdir_policy
}

cc_finalize_if_active <- function(rv,
                                  request_id = NULL,
                                  finalize_streaming,
                                  durum_metin,
                                  durum_ikon,
                                  durum_renk,
                                  sure = NULL) {
  if (!cc_is_active_run(rv, request_id)) {
    return(invisible(FALSE))
  }

  finalize_streaming(
    durum_metin,
    durum_ikon,
    durum_renk,
    sure,
    request_id = request_id
  )

  invisible(TRUE)
}

cc_observe_dir_if_active <- function(rv,
                                     request_id = NULL,
                                     observe_dir_contents,
                                     dizin) {
  if (!cc_is_active_run(rv, request_id)) {
    return(invisible(FALSE))
  }

  observe_dir_contents(dizin = dizin)
  invisible(TRUE)
}

cc_reset_document_summary_session_context <- function(rv, model) {
  rv$cli_session_id <- NULL
  rv$conversation_context <- list()
  rv$current_runtime_model <- model

  invisible(TRUE)
}

# Bilge Yolaç başarıyla tamamlandığında ve oluşturulan dosyalar kullanıcının
# yükleme klasörü içine yazıldığında Dosya Yönetimi tablosunu sayfa yenilemesi
# olmadan tazeler. Yenileme fonksiyonu yoksa sessizce çıkar; File Manager kendi
# refresh guard'ı ile eş zamanlı çağrıları korur.
cc_refresh_user_file_manager_after_run <- function(session, user_id = NULL) {
  if (is.null(session) || is.null(session$userData)) {
    return(invisible(FALSE))
  }

  fm_data <- session$userData$file_manager_data
  if (is.null(fm_data)) {
    return(invisible(FALSE))
  }

  refresh_fn <- fm_data$refresh_persisted_files
  if (!is.function(refresh_fn)) {
    return(invisible(FALSE))
  }

  tryCatch(
    refresh_fn("bilge_yolac_generated"),
    error = function(e) {
      log_warn(paste(
        CLAUDE_CODE_LOG_PREFIX,
        "Dosya Yönetimi tazeleme başarısız:",
        conditionMessage(e)
      ))
      NULL
    }
  )

  invisible(TRUE)
}

cc_handle_document_summary_run <- function(session,
                                           ns,
                                           rv,
                                           run_request_id,
                                           dokuman_baglami,
                                           model,
                                           zaman_asimi,
                                           kaynak_calisma_dizini,
                                           calisma_dizini,
                                           effective_user_id,
                                           kullanici_prompt,
                                           karakter,
                                           karakter_id,
                                           karakter_renk,
                                           runtime_lease = "",
                                           cikti_dizini = NULL,
                                           finalize_streaming,
                                           observe_dir_contents) {
  # Doküman görevlerinde Claude Code CLI oturumu kesinlikle kullanılmaz.
  # Eski --resume oturumu veya araç bağlamı bu akışa taşınmaz.
  cc_reset_document_summary_session_context(rv, model)

  target_dir <- kaynak_calisma_dizini %||% calisma_dizini

  # Worker ASLA kaynak klasöre yazmaz. Özet önce izole runtime çıktı alanında
  # üretilir; kaynak klasöre terfi yalnızca aşağıdaki `cc_is_active_run()`
  # korumasından geçen ANA süreç geri çağrısında yapılır. Aksi halde kullanıcı
  # Durdur'a bastıktan sonra tamamlanan bir worker, iptal edilmiş bir
  # çalıştırmanın çıktısını kaynak klasördeki dosyanın üzerine yazabilirdi.
  worker_cikti_dizini <- as.character(cikti_dizini %||% "")[1]
  if (!nzchar(worker_cikti_dizini) || !dir.exists(worker_cikti_dizini)) {
    worker_cikti_dizini <- target_dir
  }

  if (!isTRUE(dokuman_baglami$text_sidecars_ready)) {
    cc_release_runtime_lease(runtime_lease)
    cikarma_detayi <- paste(
      c(
        "Doküman görevi algılandı ancak yerel metin çıkarımı hazırlanamadı.",
        if (length(dokuman_baglami$extraction_errors %||% character(0))) {
          "Çıkarma hataları:"
        } else {
          NULL
        },
        dokuman_baglami$extraction_errors %||% character(0)
      ),
      collapse = "\n"
    )

    log_error(paste(
      CLAUDE_CODE_LOG_PREFIX,
      "Doküman görevi CLI'a düşmeden durduruldu.",
      gsub("[{}]", "", cikarma_detayi)
    ))

    session$sendCustomMessage(
      type = "cc-add-message",
      message = list(
        target = ns("output_area"),
        type = "error",
        content = htmltools::htmlEscape(cikarma_detayi),
        timestamp = format(Sys.time(), "%H:%M:%S"),
        welcomeId = ns("welcome_screen")
      )
    )

    cc_finalize_if_active(
      rv = rv,
      request_id = run_request_id,
      finalize_streaming = finalize_streaming,
      durum_metin = "Hata",
      durum_ikon = "exclamation-triangle",
      durum_renk = "#E57373",
      sure = NULL
    )

    cc_observe_dir_if_active(
      rv = rv,
      request_id = run_request_id,
      observe_dir_contents = observe_dir_contents,
      dizin = target_dir
    )

    return(invisible(FALSE))
  }

  log_info(paste(
    CLAUDE_CODE_LOG_PREFIX,
    "Doküman görevi yerel özetleme yoluna yönlendirildi.",
    "Model:", model,
    "| Hazır dosya sayısı:", length(dokuman_baglami$prepared_files %||% list()),
    "| Destek dizini:", dokuman_baglami$effective_workdir %||% ""
  ))

  dokuman_api_key <- tryCatch(
    mb_api_key_get_effective_key_value(
      session = session,
      require_auth = TRUE,
      allow_default = NULL,
      clear_on_mismatch = TRUE
    ),
    error = function(e) ""
  )

  # tracked_future_promise() gönderim anında SENKRON hata verebilir (worker
  # planı yok, serileştirme hatası). Yakalanmazsa ne then() ne catch() kurulur
  # ve doküman çalıştırması kalıcı olarak asılı kalırdı.
  gonderim <- tryCatch(
  tracked_future_promise(
    task_fn = function() {
      summarize_claude_code_documents_with_local_llm(
        document_context = dokuman_baglami,
        model_id = model,
        api_key = dokuman_api_key,
        request_timeout_sec = zaman_asimi,
        output_dir = worker_cikti_dizini,
        user_id = effective_user_id,
        session_token = session$token %||% format(Sys.time(), "%Y%m%d%H%M%S")
      )
    },
    task_type = "claude_code_document_summary",
    session_token = session$token
  ) |>
    promises::then(function(sonuc) {
      on.exit(cc_release_runtime_lease(runtime_lease), add = TRUE)
      if (!cc_is_active_run(rv, run_request_id)) {
        return(NULL)
      }

      sure <- sonuc$duration %||% NA_real_

      if (isTRUE(sonuc$success)) {
        rv$conversation_context <- c(
          rv$conversation_context,
          list(list(role = "assistant", content = sonuc$output %||% ""))
        )

        # KRİTİK: Bu akışta dosya zaten kullanıcı yükleme klasöründe oluşuyor.
        # Kopyalama/staging yapma. Var olan dosyanın kendisine doğrudan link üret.
        son_indirme_html <- ""

        if (nzchar(sonuc$output %||% "") &&
            exists("format_claude_code_existing_file_link_html", mode = "function")) {

          ozet_yolu <- tryCatch({
            hedef_yol <- file.path(target_dir, "dosya_aciklamalari.txt")

            # Ana Shiny oturumunda senkron yaz.
			if (exists("write_claude_code_utf8_bom_text_file", mode = "function")) {
			  write_claude_code_utf8_bom_text_file(sonuc$output %||% "", hedef_yol)
			} else {
			  writeLines(enc2utf8(sonuc$output %||% ""), hedef_yol, useBytes = TRUE)
			}

            if (!isTRUE(file.exists(hedef_yol)) || isTRUE(dir.exists(hedef_yol))) {
              stop("Özet dosyası fiziksel olarak oluşturulamadı: ", hedef_yol)
            }

            normalizePath(hedef_yol, winslash = "/", mustWork = TRUE)
          }, error = function(e) {
            log_warn(paste(
              CLAUDE_CODE_LOG_PREFIX,
              "Doküman özeti ana oturumda yazılamadı:",
              conditionMessage(e)
            ))
            ""
          })

          if (nzchar(ozet_yolu)) {
            sonuc$generated_summary_path <- ozet_yolu

            dogrudan_allowed_roots <- unique(Filter(nzchar, c(
              target_dir,
              dirname(ozet_yolu),
              tryCatch(
                cc_policy_allowed_output_roots(
                  user_id = effective_user_id,
                  workdir = target_dir
                ),
                error = function(e) character(0)
              )
            )))

            son_indirme_html <- tryCatch(
              format_claude_code_existing_file_link_html(
                file_path = ozet_yolu,
                user_id = effective_user_id,
                session_token = session$token %||% format(Sys.time(), "%Y%m%d%H%M%S"),
                allowed_roots = dogrudan_allowed_roots,
                display_path = basename(ozet_yolu)
              ),
              error = function(e) {
                log_warn(paste(
                  CLAUDE_CODE_LOG_PREFIX,
                  "Var olan doküman özeti için doğrudan link üretilemedi:",
                  conditionMessage(e)
                ))
                ""
              }
            )
          }
        }

        assistant_html <- paste0(
          format_claude_code_output(sonuc$output %||% ""),
          son_indirme_html
        )

        session$sendCustomMessage(
          type = "cc-add-message",
          message = list(
            target = ns("output_area"),
            type = "assistant",
            content = assistant_html,
            timestamp = format(Sys.time(), "%H:%M:%S"),
            accentColor = karakter_renk,
            characterName = karakter$display_name,
            welcomeId = ns("welcome_screen")
          )
        )

        rv$last_result <- sonuc

        cc_finalize_if_active(
          rv = rv,
          request_id = run_request_id,
          finalize_streaming = finalize_streaming,
          durum_metin = "Tamamlandı",
          durum_ikon = "check-circle",
          durum_renk = "#81C784",
          sure = sure
        )
      } else {
        rv$last_result <- sonuc

        session$sendCustomMessage(
          type = "cc-add-message",
          message = list(
            target = ns("output_area"),
            type = "error",
            content = htmltools::htmlEscape(sonuc$error %||% "Bilinmeyen hata"),
            timestamp = format(Sys.time(), "%H:%M:%S"),
            welcomeId = ns("welcome_screen")
          )
        )

        cc_finalize_if_active(
          rv = rv,
          request_id = run_request_id,
          finalize_streaming = finalize_streaming,
          durum_metin = "Hata",
          durum_ikon = "exclamation-triangle",
          durum_renk = "#E57373",
          sure = sure
        )
      }

      rv$output_history <- c(
        rv$output_history,
        list(list(
          prompt = kullanici_prompt,
          result = rv$last_result,
          timestamp = Sys.time(),
          character = karakter_id
        ))
      )

      # Doküman özetleme çalıştırmasını da kalıcı oturum geçmişine yaz.
      # Persist hatası canlı yanıtı etkilemez (helper güvenli değerlendirir).
      if (exists("cc_persist_run_result", mode = "function", inherits = TRUE)) {
        cc_persist_run_result(
          rv = rv,
          env = list(
            prompt = kullanici_prompt,
            tum_satirlar = character(0),
            calisma_dizini = calisma_dizini,
            kaynak_calisma_dizini = kaynak_calisma_dizini,
            # Sahip kapsamı: user_id verilmezse devam durumu güncellemesi
            # UserID yüklemi olmadan çalışırdı.
            user_id = effective_user_id
          ),
          status = if (isTRUE(sonuc$success)) "completed" else "failed",
          final_output = if (isTRUE(sonuc$success)) {
            sonuc$output %||% ""
          } else {
            sonuc$error %||% "Bilinmeyen hata"
          },
          duration = sure
        )
      }

      cc_observe_dir_if_active(
        rv = rv,
        request_id = run_request_id,
        observe_dir_contents = observe_dir_contents,
        dizin = target_dir
      )

      # Doküman özetleme yolu kullanıcının yükleme klasörüne dosya yazdığında
      # Dosya Yönetimi tablosunun yeni dosyayı oturum yenilemeden görmesi için
      # File Manager'a yumuşak bir yenileme sinyali gönder.
      cc_refresh_user_file_manager_after_run(
        session = session,
        user_id = effective_user_id
      )

      NULL
    }) |>
    promises::catch(function(e) {
      on.exit(cc_release_runtime_lease(runtime_lease), add = TRUE)
      if (!cc_is_active_run(rv, run_request_id)) {
        return(NULL)
      }

      hata_metni <- conditionMessage(e)

      rv$last_result <- list(
        success = FALSE,
        output = "",
        error = hata_metni,
        duration = NA_real_,
        tool_uses = list(),
        session_id = NULL
      )

      # Beklenmeyen hatayla biten doküman çalıştırması da geçmişe yazılır.
      if (exists("cc_persist_run_result", mode = "function", inherits = TRUE)) {
        cc_persist_run_result(
          rv = rv,
          env = list(
            prompt = kullanici_prompt,
            tum_satirlar = character(0),
            calisma_dizini = calisma_dizini,
            kaynak_calisma_dizini = kaynak_calisma_dizini,
            # Sahip kapsamı: user_id verilmezse devam durumu güncellemesi
            # UserID yüklemi olmadan çalışırdı.
            user_id = effective_user_id
          ),
          status = "failed",
          final_output = hata_metni
        )
      }

      session$sendCustomMessage(
        type = "cc-add-message",
        message = list(
          target = ns("output_area"),
          type = "error",
          content = htmltools::htmlEscape(hata_metni),
          timestamp = format(Sys.time(), "%H:%M:%S"),
          welcomeId = ns("welcome_screen")
        )
      )

      cc_finalize_if_active(
        rv = rv,
        request_id = run_request_id,
        finalize_streaming = finalize_streaming,
        durum_metin = "Hata",
        durum_ikon = "exclamation-triangle",
        durum_renk = "#E57373",
        sure = NULL
      )

      cc_observe_dir_if_active(
        rv = rv,
        request_id = run_request_id,
        observe_dir_contents = observe_dir_contents,
        dizin = target_dir
      )

      NULL
    }),
    error = function(e) e
  )

  if (inherits(gonderim, "condition")) {
    cc_release_runtime_lease(runtime_lease)
    gonderim_hata_metni <- conditionMessage(gonderim)
    log_error(paste(
      CLAUDE_CODE_LOG_PREFIX,
      "Doküman özeti görevi gönderilemedi:",
      gsub("[{}]", "", gonderim_hata_metni)
    ))

    if (cc_is_active_run(rv, run_request_id)) {
      # KALICILAŞTIRMA ÖNCE: `session$sendCustomMessage()` kapanan oturumda hata
      # verebilir; senkron gönderim hatası aksi hâlde ne son sonuç ne de terminal
      # oturum durumu olarak yazılıyor, açılan oturum bayat "çalışıyor" durumunda
      # kalıyordu.
      rv$last_result <- list(
        success = FALSE,
        output = "",
        error = gonderim_hata_metni,
        duration = NA_real_,
        tool_uses = list(),
        session_id = NULL
      )

      if (exists("cc_persist_run_result", mode = "function", inherits = TRUE)) {
        try(cc_persist_run_result(
          rv = rv,
          env = list(
            prompt = kullanici_prompt,
            tum_satirlar = character(0),
            calisma_dizini = calisma_dizini,
            kaynak_calisma_dizini = kaynak_calisma_dizini,
            user_id = effective_user_id
          ),
          status = "failed",
          final_output = gonderim_hata_metni
        ), silent = TRUE)
      }

      # Bildirim hatası SONLANDIRMAYI engellememelidir; aksi hâlde çalıştırma
      # etkin kalıp sonraki istekleri bloke ediyordu.
      try(session$sendCustomMessage(
        type = "cc-add-message",
        message = list(
          target = ns("output_area"),
          type = "error",
          content = htmltools::htmlEscape(paste0(
            "Doküman özeti görevi başlatılamadı: ", gonderim_hata_metni
          )),
          timestamp = format(Sys.time(), "%H:%M:%S"),
          welcomeId = ns("welcome_screen")
        )
      ), silent = TRUE)

      # Oturum bu sırada kapanmışsa `finalize_streaming()` kendi
      # `session$sendCustomMessage()` çağrılarından hata fırlatır; `rv$is_running`
      # sıfırlansa bile korumasız hata `cc_handle_document_summary_run()`
      # dışına yayılıyordu.
      try(cc_finalize_if_active(
        rv = rv,
        request_id = run_request_id,
        finalize_streaming = finalize_streaming,
        durum_metin = "Hata",
        durum_ikon = "exclamation-triangle",
        durum_renk = "#E57373",
        sure = NULL
      ), silent = TRUE)
    }
  }

  invisible(TRUE)
}
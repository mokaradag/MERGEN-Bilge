# ==============================================================================
# Dosya Yolu: R/module_claude_code_sessions.R
# Açıklama: Bilge Yolaç Oturumları sayfasının sunucu modülü. Kalıcı oturum
#           listesini (MB_ClaudeCode_Sessions) kullanıcı-izole olarak yükler,
#           özet metrikleri/filtreleri yönetir, detay modali gösterir ve
#           "Devam Et" akışında çalışma alanı modülüne hidrasyon delege eder.
#
# Sözleşmeler:
#   * Kullanıcı kimliği canlı sağlayıcıdan çözülür; SSO hazır olmadan
#     (user_id <= 0) DB'ye kullanıcı-kapsamlı sorgu atılmaz.
#   * Tablolar yoksa sayfa açık bir kurulum yönergesi gösterir; hata atmaz.
#   * Arşivleme yumuşak silmedir (IsDeleted = 1) ve onay modalı ister.
#   * Eski/stale yenileme sonuçları refresh guard ile yok sayılır.
# ==============================================================================

claudeCodeSessionsServer <- function(id,
                                     current_user_id,
                                     workbench = NULL,
                                     parent_session = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    rv <- reactiveValues(
      sessions = NULL,          # Son başarılı liste sonucu (data.frame)
      tables_available = NULL,  # NULL: henüz bakılmadı, TRUE/FALSE: sonuç
      auth_pending = FALSE,     # Kimlik hazır değilken açıklayıcı durum
      limit = 24L,              # Sayfalama: kart sayısı sınırı
      pending_archive_id = NULL # Onay bekleyen arşivleme kaydı
    )

    refresh_guard <- cc_create_dir_refresh_guard()

    resolve_user <- function() {
      cc_require_ready_user_id(
        session = session,
        current_user_id = current_user_id,
        sso_enabled = SSO_ENABLED,
        action_label = "oturum listeleme"
      )
    }

    # --- Liste yenileme (stale sonuç korumalı) --------------------------------
    refresh_sessions <- function(trigger = "manual") {
      refresh_id <- refresh_guard$next_id()

      user_check <- resolve_user()
      if (!isTRUE(user_check$ok)) {
        if (!refresh_guard$is_latest(refresh_id)) return(invisible(FALSE))
        rv$auth_pending <- TRUE
        return(invisible(FALSE))
      }
      rv$auth_pending <- FALSE

      mevcut <- isTRUE(tryCatch(
        cc_db_claude_tables_available(),
        error = function(e) FALSE
      ))

      if (!refresh_guard$is_latest(refresh_id)) return(invisible(FALSE))

      rv$tables_available <- mevcut
      if (!mevcut) {
        rv$sessions <- data.frame()
        return(invisible(FALSE))
      }

      durum <- as.character(input$filter_status %||% "")[1]
      arsiv_gorunumu <- identical(durum, "archived")

      liste <- cc_db_list_sessions(
        user_id = user_check$user_id,
        limit = rv$limit,
        include_deleted = arsiv_gorunumu,
        query = input$filter_query,
        status = if (arsiv_gorunumu) NULL else durum,
        model = input$filter_model,
        sort = input$filter_sort %||% "last_activity"
      )

      if (arsiv_gorunumu && is.data.frame(liste) && nrow(liste) > 0L &&
          "IsDeleted" %in% names(liste)) {
        silinmis <- suppressWarnings(as.integer(liste$IsDeleted)) == 1L
        silinmis[is.na(silinmis)] <- FALSE
        liste <- liste[silinmis, , drop = FALSE]
      }

      if (!refresh_guard$is_latest(refresh_id)) return(invisible(FALSE))

      rv$sessions <- liste

      # Model filtresi seçeneklerini mevcut sonuçlarla zenginleştir
      # (seçim korunur; stale sonuç guard'ı yukarıda uygulandı).
      if (is.data.frame(liste) && nrow(liste) > 0L) {
        modeller <- unique(stats::na.omit(c(
          as.character(liste$RuntimeModel),
          as.character(liste$ModelUsed)
        )))
        modeller <- modeller[nzchar(modeller)]

        if (length(modeller)) {
          secili <- isolate(input$filter_model %||% "")
          updateSelectInput(
            session,
            "filter_model",
            choices = c("Tümü" = "", sort(modeller)),
            selected = secili
          )
        }
      }

      invisible(TRUE)
    }

    # --- Başlık eylemleri ------------------------------------------------------
    observeEvent(input$refresh_sessions, {
      refresh_sessions("manual")
    })

    observeEvent(input$goto_workbench, {
      if (!is.null(parent_session)) {
        shinydashboard::updateTabItems(parent_session, "tabs", "claude_code")
      }
    })

    observeEvent(input$new_session, {
      basarili <- TRUE
      if (!is.null(workbench) && is.function(workbench$start_new_session)) {
        basarili <- isTRUE(workbench$start_new_session())
      }

      if (!basarili) {
        showNotification(
          "Aktif bir çalıştırma sürerken yeni oturum başlatılamaz.",
          type = "warning", duration = 5
        )
        return()
      }

      if (!is.null(parent_session)) {
        shinydashboard::updateTabItems(parent_session, "tabs", "claude_code")
      }
    })

    # --- Filtre değişimlerinde yenile (arama debounce'lı) ---------------------
    filtre_reaktif <- reactive({
      list(
        query = input$filter_query,
        status = input$filter_status,
        model = input$filter_model,
        sort = input$filter_sort
      )
    })
    filtre_debounced <- debounce(filtre_reaktif, 400)

    observeEvent(filtre_debounced(), {
      refresh_sessions("filter")
    }, ignoreInit = TRUE)

    # --- Sayfalama --------------------------------------------------------------
    observeEvent(input$load_more, {
      rv$limit <- min(rv$limit + 24L, 500L)
      refresh_sessions("load_more")
    })

    # --- Özet metrikler ---------------------------------------------------------
    output$summary_metrics <- renderUI({
      df <- rv$sessions
      if (!is.data.frame(df) || nrow(df) == 0L) return(NULL)

      cli <- as.character(df$ClaudeCliSessionID %||% "")
      devam <- sum(!is.na(cli) & nzchar(cli))
      basarisiz <- sum(suppressWarnings(as.integer(df$FailedRunCount)) > 0L, na.rm = TRUE)
      dosyali <- sum(suppressWarnings(as.integer(df$RunsWithFiles)), na.rm = TRUE)

      son <- suppressWarnings(max(
        as.POSIXct(
          c(as.character(df$LastRunAt), as.character(df$CreatedAt)),
          tz = "Europe/Istanbul"
        ),
        na.rm = TRUE
      ))

      tagList(
        ccs_metric_card("layer-group", nrow(df), "Toplam Oturum", "primary"),
        ccs_metric_card("rotate-right", devam, "Devam Edilebilir", "success"),
        ccs_metric_card("triangle-exclamation", basarisiz, "Hatalı Oturum", "danger"),
        ccs_metric_card("file-arrow-down", dosyali, "Dosyalı Çalıştırma", "info"),
        ccs_metric_card("clock", ccs_time_label(son), "Son Etkinlik", "muted")
      )
    })

    # --- Oturum kartları --------------------------------------------------------
    output$sessions_list <- renderUI({
      if (isTRUE(rv$auth_pending)) {
        return(ccs_sessions_empty_state("auth"))
      }

      if (identical(rv$tables_available, FALSE)) {
        return(ccs_sessions_empty_state("unavailable"))
      }

      df <- rv$sessions
      if (is.null(df)) {
        return(div(
          class = "ccs-loading-state",
          icon("spinner", class = "fa-spin"),
          span("Oturumlar yükleniyor...")
        ))
      }

      if (!is.data.frame(df) || nrow(df) == 0L) {
        return(ccs_sessions_empty_state("empty"))
      }

      div(
        class = "ccs-sessions-grid",
        role = "list",
        `aria-label` = "Bilge Yolaç oturum listesi",
        lapply(seq_len(nrow(df)), function(i) {
          ccs_session_card(as.list(df[i, , drop = FALSE]), ns = ns)
        })
      )
    })

    output$load_more_ui <- renderUI({
      df <- rv$sessions
      if (!is.data.frame(df) || nrow(df) < rv$limit) return(NULL)

      actionButton(
        ns("load_more"),
        label = tagList(icon("angles-down"), span("Daha Fazla Yükle")),
        class = "btn-modern ccs-load-more-btn"
      )
    })

    # --- Detay modali -----------------------------------------------------------
    observeEvent(input$session_open, {
      user_check <- resolve_user()
      if (!isTRUE(user_check$ok)) {
        showNotification(user_check$message, type = "warning", duration = 5)
        return()
      }

      kayit <- cc_db_load_session(
        user_id = user_check$user_id,
        session_record_id = input$session_open,
        max_runs = 50L
      )

      if (is.null(kayit)) {
        showNotification(
          "Oturum bulunamadı veya bu oturuma erişim yetkiniz yok.",
          type = "error", duration = 5
        )
        return()
      }

      plan <- cc_session_hydration_plan(kayit)
      silinmis <- identical(
        suppressWarnings(as.integer(kayit$session$IsDeleted %||% 0L)),
        1L
      )

      baslik <- as.character(kayit$session$SessionTitle %||% "Bilge Yolaç Oturumu")[1]

      showModal(modalDialog(
        title = tagList(icon("clock-rotate-left"), baslik),
        div(
          class = "ccs-detail-modal-content",
          ccs_session_detail_content(kayit, resume_ok = isTRUE(plan$resume$ok))
        ),
        size = "l",
        easyClose = TRUE,
        footer = tagList(
          if (!silinmis) {
            actionButton(
              ns("detail_resume"),
              label = tagList(icon("play"), span("Devam Et")),
              class = "btn-modern btn-primary"
            )
          },
          modalButton("Kapat")
        )
      ))

      rv$detail_record_id <- suppressWarnings(as.integer(input$session_open))
    })

    observeEvent(input$detail_resume, {
      removeModal()
      kayit_id <- rv$detail_record_id
      if (!is.null(kayit_id)) {
        .ccs_resume_session(kayit_id)
      }
    })

    # --- Devam Et (çalışma alanına hidrasyon) ----------------------------------
    .ccs_resume_session <- function(record_id) {
      if (is.null(workbench) || !is.function(workbench$load_persisted_session)) {
        showNotification(
          "Çalışma alanı modülü hazır değil; oturum yüklenemedi.",
          type = "error", duration = 5
        )
        return(invisible(FALSE))
      }

      basarili <- isTRUE(workbench$load_persisted_session(record_id))

      if (basarili && !is.null(parent_session)) {
        shinydashboard::updateTabItems(parent_session, "tabs", "claude_code")
      }

      invisible(basarili)
    }

    observeEvent(input$session_resume, {
      .ccs_resume_session(input$session_resume)
    })

    # --- Arşivleme (yumuşak silme; onaylı) --------------------------------------
    observeEvent(input$session_archive, {
      rv$pending_archive_id <- suppressWarnings(as.integer(input$session_archive))

      showModal(modalDialog(
        title = tagList(icon("box-archive"), "Oturumu Arşivle"),
        p(paste(
          "Bu oturum arşivlenecek. Kalıcı geçmiş silinmez; oturum",
          "'Arşivlenmiş' filtresi altında görünmeye devam eder."
        )),
        size = "s",
        easyClose = TRUE,
        footer = tagList(
          actionButton(
            ns("archive_confirm"),
            label = tagList(icon("box-archive"), span("Arşivle")),
            class = "btn-modern btn-danger"
          ),
          modalButton("Vazgeç")
        )
      ))
    })

    observeEvent(input$archive_confirm, {
      removeModal()

      kayit_id <- rv$pending_archive_id
      rv$pending_archive_id <- NULL
      if (is.null(kayit_id) || is.na(kayit_id)) return()

      user_check <- resolve_user()
      if (!isTRUE(user_check$ok)) {
        showNotification(user_check$message, type = "warning", duration = 5)
        return()
      }

      basarili <- cc_db_soft_delete_session(user_check$user_id, kayit_id)

      if (isTRUE(basarili)) {
        showNotification("Oturum arşivlendi.", type = "message", duration = 4)
        refresh_sessions("archive")
      } else {
        showNotification(
          "Oturum arşivlenemedi. Lütfen tekrar deneyin.",
          type = "error", duration = 5
        )
      }
    })

    list(
      refresh = refresh_sessions
    )
  })
}
